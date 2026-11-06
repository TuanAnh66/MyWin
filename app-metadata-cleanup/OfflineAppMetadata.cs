using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

public static class OfflineAppMetadata {
    const string Lib = @"C:\26300.9818\bin\offreg.dll";
    [DllImport(Lib, CharSet=CharSet.Unicode)] static extern uint OROpenHive(string path,out IntPtr h);
    [DllImport(Lib)] static extern uint ORCloseHive(IntPtr h);
    [DllImport(Lib, CharSet=CharSet.Unicode)] static extern uint OROpenKey(IntPtr h,string path,out IntPtr key);
    [DllImport(Lib)] static extern uint ORCloseKey(IntPtr h);
    [DllImport(Lib, CharSet=CharSet.Unicode)] static extern uint OREnumKey(IntPtr h,uint index,StringBuilder name,ref uint length,IntPtr cls,IntPtr clsLen,IntPtr time);
    [DllImport(Lib, CharSet=CharSet.Unicode)] static extern uint OREnumValue(IntPtr h,uint index,StringBuilder name,ref uint length,out uint type,byte[] data,ref uint size);
    [DllImport(Lib, CharSet=CharSet.Unicode)] static extern uint ORDeleteKey(IntPtr h,string path);
    [DllImport(Lib, CharSet=CharSet.Unicode)] static extern uint ORDeleteValue(IntPtr h,string name);
    [DllImport(Lib, CharSet=CharSet.Unicode)] static extern uint ORSaveHive(IntPtr h,string path,uint major,uint minor);
    static void Check(uint code,string action) { if(code!=0) throw new Win32Exception((int)code,action); }
    static List<string> Children(IntPtr h) {
        var result=new List<string>();
        for(uint i=0;;i++) {
            var b=new StringBuilder(32768); uint n=32768;
            uint e=OREnumKey(h,i,b,ref n,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero);
            if(e==259) break;
            Check(e,"Enumerate offline key"); result.Add(b.ToString());
        }
        return result;
    }
    static void DeleteTree(IntPtr parent,string name) {
        IntPtr child; Check(OROpenKey(parent,name,out child),"Open subtree for deletion");
        try { foreach(var sub in Children(child)) DeleteTree(child,sub); }
        finally { Check(ORCloseKey(child),"Close deleted subtree"); }
        Check(ORDeleteKey(parent,name),"Delete offline app subtree");
    }
    static void Walk(IntPtr h,string path,Regex match,bool apply,List<string> hits) {
        foreach(var name in Children(h)) {
            string full=path.Length==0?name:path+"\\"+name;
            if(match.IsMatch(name)) {
                hits.Add("KEY\t"+full);
                if(apply) DeleteTree(h,name);
                continue;
            }
            IntPtr child; Check(OROpenKey(h,name,out child),"Open "+full);
            try { Walk(child,full,match,apply,hits); }
            finally { Check(ORCloseKey(child),"Close offline key"); }
        }
        var remove=new List<string>();
        byte[] data=new byte[65536];
        for(uint i=0;;i++) {
            var name=new StringBuilder(32768); uint n=32768,type,size=(uint)data.Length;
            uint e=OREnumValue(h,i,name,ref n,out type,data,ref size);
            if(e==259) break;
            if(e==234) {
                data=new byte[Math.Max(size,(uint)data.Length*2)]; n=32768; size=(uint)data.Length;
                e=OREnumValue(h,i,name,ref n,out type,data,ref size);
            }
            Check(e,"Enumerate offline values at "+path);
            string valueName=name.ToString();
            string text=(type==1||type==2||type==7)?Encoding.Unicode.GetString(data,0,(int)size):"";
            if(match.IsMatch(valueName)||match.IsMatch(text)) {
                hits.Add("VALUE\t"+path+"\\"+valueName);
                remove.Add(valueName);
            }
        }
        if(apply) foreach(var name in remove) Check(ORDeleteValue(h,name),"Delete offline app value");
    }
    public static string[] Process(string input,string output,string[] appNames,bool apply) {
        var patterns=new List<string>(); foreach(var name in appNames) patterns.Add(Regex.Escape(name)+"_");
        var match=new Regex(string.Join("|",patterns),RegexOptions.IgnoreCase|RegexOptions.CultureInvariant|RegexOptions.Compiled);
        IntPtr hive; Check(OROpenHive(input,out hive),"Open offline hive "+input);
        var hits=new List<string>();
        try {
            Walk(hive,"",match,apply,hits);
            if(apply) Check(ORSaveHive(hive,output,6,1),"Save cleaned offline hive");
        } finally { Check(ORCloseHive(hive),"Close offline hive"); }
        return hits.ToArray();
    }
}
