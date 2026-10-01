using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using MenuDiagnostics;

// Calls the actual IExplorerCommand ABI. No shell registration or certificate changes.
static class MenuRegression {
    const string Original="23170F69-40C1-278A-1000-000100020000";
    const string Adapter="a51841e4-acd0-4a8b-b1ad-5488da4dbee6";
    static IEnumerable<string> Flatten(IEnumerable<Entry> entries,string prefix="") {
        foreach(var entry in entries) {
            if((entry.Flags&8)!=0) continue;
            if((entry.Flags&1)!=0) {
                foreach(var title in Flatten(entry.Children,prefix+entry.Title+" / ")) yield return title;
            } else yield return prefix+entry.Title;
        }
    }
    static void Assert(bool success,string message) {if(!success) throw new Exception(message);}
    [STAThread] static int Main(string[] args) {
        try {
            Console.OutputEncoding=new UTF8Encoding(false);
            if(args.Length<3) throw new ArgumentException("Usage: MenuRegression.exe adapter.dll|@registered original.dll fixture-path [--original-only | --report | --invoke exact-title]");
            string[] paths=args[2].Split('|');
            bool originalOnly=args.Length>3 && args[3]=="--original-only";
            bool reportOnly=args.Length>3 && args[3]=="--report";
            string invoke=args.Length>4 && args[3]=="--invoke" ? args[4] : null;
            var baseline=Probe.Run(Path.GetFullPath(args[1]),Original,paths,reportOnly?0:250);
            var target=args[0]=="@registered" ? args[0] : Path.GetFullPath(args[0]);
            var updated=originalOnly?baseline:Probe.Run(target,Adapter,paths,reportOnly?0:250,!reportOnly,invoke);
            var json=new JavaScriptSerializer();
            // ASCII JSON stays intact under either Windows console code page.
            Console.WriteLine(Regex.Replace(json.Serialize(new {Baseline=baseline,Updated=updated}), "[^\\u0000-\\u007F]",
                m => "\\u" + ((int)m.Value[0]).ToString("x4")));
            if(reportOnly) return 0;
            Assert(updated.Entries.Count>0,"FAIL: empty submenu.");
            if(target!="@registered") Assert(updated.TopLevelItemRequests==0,"FAIL: top-level menu enumerates selected files.");
            Assert(updated.NestedSubmenuCount==0,"FAIL: nested submenus are invisible in the modern menu.");
            Assert(updated.DeferredStateCount==0,"FAIL: local file state query is deferred.");
            Assert(Flatten(baseline.Entries).SequenceEqual(Flatten(updated.Entries)),"FAIL: original actions were lost or reordered.");
            Console.WriteLine(target=="@registered" ? "PASS: packaged activation, native shell selection, flat complete commands and child lifetime." : "PASS: lazy top-level, flat complete command list, independent enum/clone, cache and child lifetime.");
            return 0;
        } catch(Exception error) {Console.Error.WriteLine(error);return 1;}
    }
}
