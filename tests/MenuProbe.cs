using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
namespace MenuDiagnostics {
[ComImport, Guid("A08CE4D0-FA25-44AB-B57C-C7B1C323E0B9"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ICommand {
    [PreserveSig] int GetTitle(IntPtr items, out IntPtr text);
    [PreserveSig] int GetIcon(IntPtr items, out IntPtr text);
    [PreserveSig] int GetToolTip(IntPtr items, out IntPtr text);
    [PreserveSig] int GetCanonicalName(out Guid name);
    [PreserveSig] int GetState(IntPtr items, [MarshalAs(UnmanagedType.Bool)] bool slow, out uint state);
    [PreserveSig] int Invoke(IntPtr items, IntPtr context);
    [PreserveSig] int GetFlags(out uint flags);
    [PreserveSig] int EnumSubCommands(out ICommands commands);
}
[ComImport, Guid("A88826F8-186F-4987-AADE-EA0CEF8FBFE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ICommands {
    [PreserveSig] int Next(uint count, [Out, MarshalAs(UnmanagedType.LPArray, SizeParamIndex=0)] ICommand[] commands, out uint fetched);
    [PreserveSig] int Skip(uint count);
    [PreserveSig] int Reset();
    [PreserveSig] int Clone(out ICommands commands);
}
[ComVisible(true), Guid("B63EA76D-1F85-456F-A19C-48159EFA858B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMeasuredItems {
    [PreserveSig] int BindToHandler(IntPtr context, ref Guid handler, ref Guid iid, out IntPtr value);
    [PreserveSig] int GetPropertyStore(int flags, ref Guid iid, out IntPtr value);
    [PreserveSig] int GetPropertyDescriptionList(IntPtr key, ref Guid iid, out IntPtr value);
    [PreserveSig] int GetAttributes(int flags, uint mask, out uint attributes);
    [PreserveSig] int GetCount(out uint count);
    [PreserveSig] int GetItemAt(uint index, out IntPtr item);
    [PreserveSig] int EnumItems(out IntPtr items);
}
[ComVisible(true), ClassInterface(ClassInterfaceType.None)]
public sealed class MeasuredItems : IMeasuredItems {
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int Count(IntPtr self,out uint count);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int ItemAt(IntPtr self,uint index,out IntPtr item);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int Attributes(IntPtr self,int flags,uint mask,out uint attributes);
    readonly IntPtr inner; readonly int delayMs; public int ItemRequests;
    public MeasuredItems(IntPtr array,int delay) { inner=array;delayMs=delay; }
    T Method<T>(int index) { return (T)(object)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(Marshal.ReadIntPtr(inner),index*IntPtr.Size),typeof(T)); }
    public int BindToHandler(IntPtr context,ref Guid handler,ref Guid iid,out IntPtr value) {value=IntPtr.Zero;return unchecked((int)0x80004001);}
    public int GetPropertyStore(int flags,ref Guid iid,out IntPtr value) {value=IntPtr.Zero;return unchecked((int)0x80004001);}
    public int GetPropertyDescriptionList(IntPtr key,ref Guid iid,out IntPtr value) {value=IntPtr.Zero;return unchecked((int)0x80004001);}
    public int GetAttributes(int flags,uint mask,out uint attributes) {return Method<Attributes>(6)(inner,flags,mask,out attributes);}
    public int GetCount(out uint count) {return Method<Count>(7)(inner,out count);}
    public int GetItemAt(uint index,out IntPtr item) {ItemRequests++;if(delayMs>0)System.Threading.Thread.Sleep(delayMs);return Method<ItemAt>(8)(inner,index,out item);}
    public int EnumItems(out IntPtr items) {items=IntPtr.Zero;return unchecked((int)0x80004001);}
}
public sealed class Entry {
    public string Title; public uint Flags; public string FastResult; public double FastMs; public uint State; public string EnumerationResult; public List<Entry> Children = new List<Entry>();
}
public sealed class Report {
    public double CreateMs; public double TitleMs; public string FastResult; public double FastMs; public uint State; public string SlowResult; public double SlowMs; public int TopLevelItemRequests;
    public double EnumerationMs; public string EnumerationResult; public int NestedSubmenuCount; public int DeferredStateCount; public List<Entry> Entries = new List<Entry>();
}
public static class Probe {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
    [DllImport("kernel32.dll", CharSet=CharSet.Ansi, ExactSpelling=true)] static extern IntPtr GetProcAddress(IntPtr module, string name);
    [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr module);
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)] static extern int SHParseDisplayName(string path, IntPtr context, out IntPtr pidl, uint requested, out uint attributes);
    [DllImport("shell32.dll")] static extern int SHCreateShellItemArrayFromIDLists(uint count, [In] IntPtr[] pidls, out IntPtr items);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int GetClassObject(ref Guid clsid, ref Guid iid, out IntPtr factory);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int CreateInstance(IntPtr factory, IntPtr outer, ref Guid iid, out IntPtr command);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int CanUnload();
    static string HResult(int hr) { return "0x" + ((uint)hr).ToString("X8"); }
    static List<Entry> Enumerate(ICommand command, IntPtr items, Report report, int depth, out string enumerationResult) {
        var entries = new List<Entry>(); ICommands enumerator = null;
        int hr = command.EnumSubCommands(out enumerator);
        enumerationResult = HResult(hr);
        Marshal.ThrowExceptionForHR(hr);
        if (enumerator == null) throw new InvalidOperationException("Missing command enumerator.");
        try {
            var batch = new ICommand[1]; uint fetched;
            for (;;) {
                hr=enumerator.Next(1,batch,out fetched);
                Marshal.ThrowExceptionForHR(hr);
                if(fetched==0) break;
                if(fetched!=1 || batch[0]==null) throw new InvalidOperationException("Invalid enumeration result.");
                var child = batch[0];
                try {
                    var e = new Entry(); IntPtr text = IntPtr.Zero;
                    Marshal.ThrowExceptionForHR(child.GetTitle(items,out text));
                    try { e.Title = Marshal.PtrToStringUni(text); } finally { if(text != IntPtr.Zero) Marshal.FreeCoTaskMem(text); }
                    Marshal.ThrowExceptionForHR(child.GetFlags(out e.Flags));
                    var watch = Stopwatch.StartNew(); uint state; int fast = child.GetState(items,false,out state); watch.Stop();
                    e.FastResult=HResult(fast); e.FastMs=watch.Elapsed.TotalMilliseconds; e.State=state;
                    if(fast == unchecked((int)0x8000000A)) report.DeferredStateCount++;
                    if((e.Flags & 1) != 0) {
                        report.NestedSubmenuCount++;
                        if(depth < 4) e.Children = Enumerate(child,items,report,depth+1,out e.EnumerationResult);
                    }
                    entries.Add(e);
                } finally { Marshal.ReleaseComObject(child); }
            }
        } finally { Marshal.ReleaseComObject(enumerator); }
        return entries;
    }
    public static Report Run(string dll, string classId, string[] paths, int itemDelayMs, bool checkLifetime = false, string invokeTitle = null) {
        var report = new Report(); var ids = new IntPtr[paths.Length]; IntPtr items=IntPtr.Zero, realItems=IntPtr.Zero, module=IntPtr.Zero, factory=IntPtr.Zero;
        ICommand command=null;
        try {
            for(int i=0;i<paths.Length;i++) { uint attrs; Marshal.ThrowExceptionForHR(SHParseDisplayName(paths[i],IntPtr.Zero,out ids[i],0,out attrs)); }
            Marshal.ThrowExceptionForHR(SHCreateShellItemArrayFromIDLists((uint)ids.Length,ids,out realItems));
            var measured = new MeasuredItems(realItems,itemDelayMs);
            items=Marshal.GetComInterfaceForObject(measured,typeof(IMeasuredItems));
            var watch = Stopwatch.StartNew();
            module = LoadLibraryEx(dll,IntPtr.Zero,0x1100);
            if(module == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            var getFactory = (GetClassObject)Marshal.GetDelegateForFunctionPointer(GetProcAddress(module,"DllGetClassObject"),typeof(GetClassObject));
            Guid clsid = new Guid(classId), factoryIid = new Guid("00000001-0000-0000-C000-000000000046"), commandIid = new Guid("A08CE4D0-FA25-44AB-B57C-C7B1C323E0B9");
            Marshal.ThrowExceptionForHR(getFactory(ref clsid,ref factoryIid,out factory));
            var create = (CreateInstance)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(Marshal.ReadIntPtr(factory),3*IntPtr.Size),typeof(CreateInstance));
            IntPtr pointer;
            Marshal.ThrowExceptionForHR(create(factory,IntPtr.Zero,ref commandIid,out pointer));
            try { command = (ICommand)Marshal.GetObjectForIUnknown(pointer); } finally { Marshal.Release(pointer); }
            watch.Stop(); report.CreateMs=watch.Elapsed.TotalMilliseconds;
            IntPtr rootTitle;
            watch.Restart();
            Marshal.ThrowExceptionForHR(command.GetTitle(items,out rootTitle));
            watch.Stop(); report.TitleMs=watch.Elapsed.TotalMilliseconds;
            if(rootTitle != IntPtr.Zero) Marshal.FreeCoTaskMem(rootTitle);
            uint state;
            watch.Restart(); int fast = command.GetState(items,false,out state); watch.Stop();
            report.FastResult=HResult(fast); report.FastMs=watch.Elapsed.TotalMilliseconds; report.State=state;
            if(fast == unchecked((int)0x8000000A)) report.DeferredStateCount++;
            watch.Restart(); int slow=command.GetState(items,true,out state); watch.Stop();
            report.SlowResult=HResult(slow); report.SlowMs=watch.Elapsed.TotalMilliseconds;
            report.TopLevelItemRequests=measured.ItemRequests;
            watch.Restart(); report.Entries=Enumerate(command,items,report,0,out report.EnumerationResult); watch.Stop();
            report.EnumerationMs=watch.Elapsed.TotalMilliseconds;
            if(checkLifetime) {
                int requests=measured.ItemRequests;
                CheckEnumerator(command,items,report.Entries.Count);
                if(requests!=measured.ItemRequests) throw new InvalidOperationException("Repeated enumeration reread file items.");
                ICommands retained;
                Marshal.ThrowExceptionForHR(command.EnumSubCommands(out retained));
                Marshal.ReleaseComObject(command); command=null;
                try {
                    var batch=new ICommand[1]; uint fetched; bool invoked=false;
                    while(retained.Next(1,batch,out fetched)==0 && fetched==1) {
                        ICommand leaf=batch[0];
                        try {
                            string title=Title(leaf,items);
                            if(invokeTitle!=null && title==invokeTitle) {
                                // The command must keep the original DLL alive after its root and enumerator die.
                                Marshal.ReleaseComObject(retained); retained=null;
                                Marshal.ThrowExceptionForHR(leaf.Invoke(items,IntPtr.Zero));
                                invoked=true; break;
                            }
                        } finally { Marshal.ReleaseComObject(leaf); }
                    }
                    if(invokeTitle!=null && !invoked) throw new InvalidOperationException("Command not found: "+invokeTitle);
                } finally { if(retained!=null) Marshal.ReleaseComObject(retained); }
            }
            return report;
        } finally {
            if(command != null) Marshal.ReleaseComObject(command);
            if(factory != IntPtr.Zero) Marshal.Release(factory);
            if(module != IntPtr.Zero) {
                try {
                    if(checkLifetime) {
                        var canUnload=(CanUnload)Marshal.GetDelegateForFunctionPointer(GetProcAddress(module,"DllCanUnloadNow"),typeof(CanUnload));
                        if(canUnload()!=0) throw new InvalidOperationException("Adapter still holds COM objects after all commands were released.");
                    }
                } finally { FreeLibrary(module); }
            }
            if(items != IntPtr.Zero) Marshal.Release(items);
            if(realItems != IntPtr.Zero) Marshal.Release(realItems);
            foreach(var id in ids) if(id != IntPtr.Zero) Marshal.FreeCoTaskMem(id);
        }
    }
    static string Title(ICommand command,IntPtr items) {
        IntPtr title; Marshal.ThrowExceptionForHR(command.GetTitle(items,out title));
        try { return Marshal.PtrToStringUni(title); } finally { Marshal.FreeCoTaskMem(title); }
    }
    static void CheckEnumerator(ICommand root,IntPtr items,int expected) {
        ICommands first=null,clone=null;
        try {
            Marshal.ThrowExceptionForHR(root.EnumSubCommands(out first));
            if(first.Skip(1)!=0) throw new InvalidOperationException("Skip failed.");
            Marshal.ThrowExceptionForHR(first.Clone(out clone));
            var a=new ICommand[2]; var b=new ICommand[2]; uint ac,bc;
            int ah=first.Next(2,a,out ac),bh=clone.Next(2,b,out bc);
            if(ah!=0 || bh!=0 || ac!=2 || bc!=2) throw new InvalidOperationException("Batch/clone failed.");
            for(int i=0;i<2;i++) {
                try { if(Title(a[i],items)!=Title(b[i],items)) throw new InvalidOperationException("Clone changed position."); }
                finally { Marshal.ReleaseComObject(a[i]); Marshal.ReleaseComObject(b[i]); }
            }
            Marshal.ThrowExceptionForHR(first.Reset());
            if(first.Skip((uint)expected)!=0 || first.Next(2,a,out ac)!=1 || ac!=0 || first.Skip(1)!=1)
                throw new InvalidOperationException("Enumeration end contract failed.");
            // Resetting first must not reset clone.
            if(clone.Skip((uint)(expected-3))!=0 || clone.Next(2,b,out bc)!=1 || bc!=0)
                throw new InvalidOperationException("Clone cursor is not independent.");
        } finally {
            if(clone!=null) Marshal.ReleaseComObject(clone);
            if(first!=null) Marshal.ReleaseComObject(first);
        }
    }
}
}
