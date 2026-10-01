#include <windows.h>
#include <shellapi.h>
#include "SevenZipConfig.h"

// The package requires an executable identity. It runs only if explicitly activated,
// opens the existing 7-Zip file manager, and exits; context menus never launch it.
int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    return reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr, L"open", kSevenZipFm,
        nullptr, nullptr, SW_SHOWNORMAL)) > 32 ? 0 : 1;
}
