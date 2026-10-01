// Modern menu adapter. Every action remains an original 7-Zip action.
#include <windows.h>
#include <shobjidl.h>
#include <shlwapi.h>
#include <wrl/client.h>
#include <algorithm>
#include <memory>
#include <new>
#include <string>
#include <vector>
#include "SevenZipConfig.h"

using Microsoft::WRL::ComPtr;
namespace {
const CLSID kAdapter = {0xa51841e4,0xacd0,0x4a8b,{0xb1,0xad,0x54,0x88,0xda,0x4d,0xbe,0xe6}};
const CLSID kSevenZip = {0x23170f69,0x40c1,0x278a,{0x10,0x00,0x00,0x01,0x00,0x02,0x00,0x00}};
volatile LONG objects = 0, locks = 0;

template<class Interface> class ComObject : public Interface {
    volatile LONG refs_ = 1;
protected:
    ComObject() { InterlockedIncrement(&objects); }
    virtual ~ComObject() { InterlockedDecrement(&objects); }
public:
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id, void** result) override {
        if (!result) return E_POINTER;
        *result = nullptr;
        if (id != IID_IUnknown && id != __uuidof(Interface)) return E_NOINTERFACE;
        *result = static_cast<Interface*>(this); AddRef(); return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs_); }
    ULONG STDMETHODCALLTYPE Release() override {
        const LONG remaining = InterlockedDecrement(&refs_);
        if (!remaining) delete this;
        return remaining;
    }
};
template<class F> HRESULT Guard(F&& operation) noexcept {
    try { return operation(); }
    catch (const std::bad_alloc&) { return E_OUTOFMEMORY; }
    catch (...) { return E_FAIL; }
}
struct TaskString {
    PWSTR value = nullptr;
    ~TaskString() { CoTaskMemFree(value); }
};

struct Backend {
    HMODULE module = nullptr;
    ComPtr<IExplorerCommand> root;
    ~Backend() { root.Reset(); if (module) FreeLibrary(module); }
    HRESULT Open(IShellItemArray* items) {
        module = LoadLibraryExW(kSevenZipDll, nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
        if (!module) return HRESULT_FROM_WIN32(GetLastError());
        using GetFactory = HRESULT (STDAPICALLTYPE*)(REFCLSID, REFIID, void**);
        const auto getFactory = reinterpret_cast<GetFactory>(GetProcAddress(module, "DllGetClassObject"));
        if (!getFactory) return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
        ComPtr<IClassFactory> factory;
        HRESULT hr = getFactory(kSevenZip, IID_PPV_ARGS(&factory));
        if (FAILED(hr)) return hr;
        hr = factory->CreateInstance(nullptr, IID_PPV_ARGS(&root));
        if (FAILED(hr)) return hr;
        // 7-Zip prepares its command map in GetTitle. Defer this until EnumSubCommands.
        TaskString title;
        return root->GetTitle(items, &title.value);
    }
};

class Leaf final : public ComObject<IExplorerCommand> {
    // Release commands before unloading their module, even if the root has been released.
    std::shared_ptr<Backend> backend_;
    ComPtr<IExplorerCommand> command_;
    std::wstring prefix_;
public:
    Leaf(std::shared_ptr<Backend> backend, IExplorerCommand* command, std::wstring prefix)
        : backend_(std::move(backend)), command_(command), prefix_(std::move(prefix)) {}
    HRESULT STDMETHODCALLTYPE GetTitle(IShellItemArray* items, LPWSTR* text) override {
        if (!text) return E_POINTER;
        *text = nullptr;
        if (prefix_.empty()) return command_->GetTitle(items, text);
        return Guard([&]() -> HRESULT {
            TaskString title;
            const HRESULT hr = command_->GetTitle(items, &title.value);
            if (FAILED(hr)) return hr;
            return SHStrDupW((prefix_ + (title.value ? title.value : L"")).c_str(), text);
        });
    }
    HRESULT STDMETHODCALLTYPE GetIcon(IShellItemArray* items, LPWSTR* icon) override { return command_->GetIcon(items, icon); }
    HRESULT STDMETHODCALLTYPE GetToolTip(IShellItemArray* items, LPWSTR* tip) override { return command_->GetToolTip(items, tip); }
    HRESULT STDMETHODCALLTYPE GetCanonicalName(GUID* name) override { return command_->GetCanonicalName(name); }
    HRESULT STDMETHODCALLTYPE GetState(IShellItemArray* items, BOOL slow, EXPCMDSTATE* state) override { return command_->GetState(items, slow, state); }
    HRESULT STDMETHODCALLTYPE Invoke(IShellItemArray* items, IBindCtx* context) override { return command_->Invoke(items, context); }
    HRESULT STDMETHODCALLTYPE GetFlags(EXPCMDFLAGS* flags) override { return command_->GetFlags(flags); }
    HRESULT STDMETHODCALLTYPE EnumSubCommands(IEnumExplorerCommand** result) override {
        if (!result) return E_POINTER;
        *result = nullptr; return E_NOTIMPL;
    }
};

using Commands = std::vector<ComPtr<IExplorerCommand>>;
HRESULT Flatten(IExplorerCommand* parent, IShellItemArray* items, const std::shared_ptr<Backend>& backend,
                const std::wstring& prefix, Commands& output, unsigned depth = 0) {
    if (depth > 8) return E_UNEXPECTED;
    ComPtr<IEnumExplorerCommand> enumerator;
    HRESULT hr = parent->EnumSubCommands(&enumerator);
    if (FAILED(hr)) return hr;
    if (!enumerator) return E_UNEXPECTED;
    for (;;) {
        ComPtr<IExplorerCommand> child;
        ULONG fetched = 0;
        hr = enumerator->Next(1, &child, &fetched);
        if (FAILED(hr)) return hr;
        if (!fetched) return S_OK;
        if (!child || fetched != 1) return E_UNEXPECTED;
        EXPCMDFLAGS flags;
        hr = child->GetFlags(&flags);
        if (FAILED(hr)) return hr;
        if (flags & ECF_HASSUBCOMMANDS) {
            TaskString title;
            hr = child->GetTitle(items, &title.value);
            if (FAILED(hr)) return hr;
            hr = Flatten(child.Get(), items, backend, prefix + (title.value ? title.value : L"") + L" / ", output, depth + 1);
            if (FAILED(hr)) return hr;
        } else {
            ComPtr<IExplorerCommand> leaf;
            leaf.Attach(new Leaf(backend, child.Get(), (flags & ECF_ISSEPARATOR) ? L"" : prefix));
            output.push_back(std::move(leaf));
        }
    }
}

class Enumerator final : public ComObject<IEnumExplorerCommand> {
    Commands commands_;
    size_t position_ = 0;
public:
    explicit Enumerator(const Commands& commands, size_t position = 0) : commands_(commands), position_(position) {}
    HRESULT STDMETHODCALLTYPE Next(ULONG count, IExplorerCommand** commands, ULONG* fetched) override {
        if (fetched) *fetched = 0;
        if ((!commands && count) || (!fetched && count != 1)) return E_POINTER;
        ULONG done = 0;
        while (done < count && position_ < commands_.size()) {
            commands_[position_++].CopyTo(&commands[done++]);
        }
        if (fetched) *fetched = done;
        return done == count ? S_OK : S_FALSE;
    }
    HRESULT STDMETHODCALLTYPE Skip(ULONG count) override {
        const size_t skipped = std::min<size_t>(count, commands_.size() - position_);
        position_ += skipped; return skipped == count ? S_OK : S_FALSE;
    }
    HRESULT STDMETHODCALLTYPE Reset() override { position_ = 0; return S_OK; }
    HRESULT STDMETHODCALLTYPE Clone(IEnumExplorerCommand** result) override {
        if (!result) return E_POINTER;
        *result = nullptr;
        return Guard([&]() -> HRESULT { *result = new Enumerator(commands_, position_); return S_OK; });
    }
};

class Root final : public ComObject<IExplorerCommand> {
    ComPtr<IShellItemArray> selection_;
    Commands commands_;
    bool initialized_ = false;
    void Capture(IShellItemArray* items) {
        if (items && items != selection_.Get()) {
            selection_ = items; commands_.clear(); initialized_ = false;
        }
    }
public:
    HRESULT STDMETHODCALLTYPE GetTitle(IShellItemArray* items, LPWSTR* title) override {
        if (!title) return E_POINTER;
        Capture(items);
        return SHStrDupW(L"7-Zip", title);
    }
    HRESULT STDMETHODCALLTYPE GetIcon(IShellItemArray*, LPWSTR* icon) override {
        if (!icon) return E_POINTER;
        return SHStrDupW(kSevenZipIcon, icon);
    }
    HRESULT STDMETHODCALLTYPE GetToolTip(IShellItemArray*, LPWSTR* tip) override {
        if (!tip) return E_POINTER;
        *tip = nullptr; return E_NOTIMPL;
    }
    HRESULT STDMETHODCALLTYPE GetCanonicalName(GUID* name) override {
        if (!name) return E_POINTER;
        *name = kAdapter; return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetState(IShellItemArray* items, BOOL, EXPCMDSTATE* state) override {
        if (!state) return E_POINTER;
        Capture(items);
        DWORD count = 0;
        *state = selection_ && SUCCEEDED(selection_->GetCount(&count)) && count ? ECS_ENABLED : ECS_HIDDEN;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE Invoke(IShellItemArray*, IBindCtx*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE GetFlags(EXPCMDFLAGS* flags) override {
        if (!flags) return E_POINTER;
        *flags = ECF_HASSUBCOMMANDS; return S_OK;
    }
    HRESULT STDMETHODCALLTYPE EnumSubCommands(IEnumExplorerCommand** result) override {
        if (!result) return E_POINTER;
        *result = nullptr;
        if (!selection_) return E_UNEXPECTED;
        return Guard([&]() -> HRESULT {
            if (!initialized_) {
                auto backend = std::make_shared<Backend>();
                HRESULT hr = backend->Open(selection_.Get());
                if (FAILED(hr)) return hr;
                Commands commands;
                hr = Flatten(backend->root.Get(), selection_.Get(), backend, L"", commands);
                if (FAILED(hr)) return hr;
                commands_ = std::move(commands);
                initialized_ = true;
            }
            *result = new Enumerator(commands_);
            return S_OK;
        });
    }
};

class Factory final : public ComObject<IClassFactory> {
public:
    HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer, REFIID id, void** result) override {
        if (!result) return E_POINTER;
        *result = nullptr;
        if (outer) return CLASS_E_NOAGGREGATION;
        auto* root = new (std::nothrow) Root();
        if (!root) return E_OUTOFMEMORY;
        const HRESULT hr = root->QueryInterface(id, result);
        root->Release(); return hr;
    }
    HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override {
        if (lock) InterlockedIncrement(&locks); else InterlockedDecrement(&locks);
        return S_OK;
    }
};
}
STDAPI DllGetClassObject(REFCLSID clsid, REFIID iid, void** result) {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (clsid != kAdapter) return CLASS_E_CLASSNOTAVAILABLE;
    auto* factory = new (std::nothrow) Factory();
    if (!factory) return E_OUTOFMEMORY;
    const HRESULT hr = factory->QueryInterface(iid, result);
    factory->Release(); return hr;
}
STDAPI DllCanUnloadNow() {
    return !objects && !locks ? S_OK : S_FALSE;
}
