using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace SevenZipModernMenu
{
    // Diagnostics only: this helper is never registered as a shell extension.
    public static class Native
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
        [DllImport("kernel32.dll", CharSet = CharSet.Ansi, ExactSpelling = true)]
        private static extern IntPtr GetProcAddress(IntPtr module, string name);
        [DllImport("kernel32.dll")]
        private static extern bool FreeLibrary(IntPtr module);
        [DllImport("ole32.dll")]
        private static extern int CoCreateInstance(ref Guid clsid, IntPtr outer, uint context, ref Guid iid, out IntPtr instance);
        [DllImport("shell32.dll")]
        private static extern void SHChangeNotify(uint eventId, uint flags, IntPtr first, IntPtr second);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetClassObject(ref Guid clsid, ref Guid iid, out IntPtr factory);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int CreateInstance(IntPtr factory, IntPtr outer, ref Guid iid, out IntPtr command);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetIcon(IntPtr command, IntPtr items, out IntPtr icon);

        public static void CheckLibrary(string path)
        {
            // Absolute path + restricted dependency search; do not use COM registry redirection.
            IntPtr module = LoadLibraryEx(path, IntPtr.Zero, 0x1100);
            if (module == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            IntPtr factory = IntPtr.Zero, command = IntPtr.Zero;
            try
            {
                IntPtr entry = GetProcAddress(module, "DllGetClassObject");
                if (entry == IntPtr.Zero) throw new InvalidOperationException("7-zip.dll has no COM class factory.");
                var getFactory = (GetClassObject)Marshal.GetDelegateForFunctionPointer(entry, typeof(GetClassObject));
                Guid clsid = new Guid("23170F69-40C1-278A-1000-000100020000");
                Guid factoryId = new Guid("00000001-0000-0000-C000-000000000046");
                Marshal.ThrowExceptionForHR(getFactory(ref clsid, ref factoryId, out factory));
                IntPtr vtable = Marshal.ReadIntPtr(factory);
                var create = (CreateInstance)Marshal.GetDelegateForFunctionPointer(
                    Marshal.ReadIntPtr(vtable, 3 * IntPtr.Size), typeof(CreateInstance));
                Guid commandId = new Guid("A08CE4D0-FA25-44AB-B57C-C7B1C323E0B9");
                Marshal.ThrowExceptionForHR(create(factory, IntPtr.Zero, ref commandId, out command));
            }
            finally
            {
                if (command != IntPtr.Zero) Marshal.Release(command);
                if (factory != IntPtr.Zero) Marshal.Release(factory);
                FreeLibrary(module);
            }
        }

        public static string CheckPackagedActivation()
        {
            Guid clsid = new Guid("23170F69-40C1-278A-1000-000100020000");
            Guid iid = new Guid("A08CE4D0-FA25-44AB-B57C-C7B1C323E0B9");
            IntPtr command;
            Marshal.ThrowExceptionForHR(CoCreateInstance(ref clsid, IntPtr.Zero, 4, ref iid, out command));
            IntPtr icon = IntPtr.Zero;
            try
            {
                IntPtr vtable = Marshal.ReadIntPtr(command);
                var getIcon = (GetIcon)Marshal.GetDelegateForFunctionPointer(
                    Marshal.ReadIntPtr(vtable, 4 * IntPtr.Size), typeof(GetIcon));
                Marshal.ThrowExceptionForHR(getIcon(command, IntPtr.Zero, out icon));
                return Marshal.PtrToStringUni(icon);
            }
            finally
            {
                if (icon != IntPtr.Zero) Marshal.FreeCoTaskMem(icon);
                Marshal.Release(command);
            }
        }

        public static void RefreshShell()
        {
            SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero);
        }
    }
}
