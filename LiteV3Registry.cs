using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
public sealed class LiteV3Registry : IDisposable {
    const string Lib=@"C:\26300.9818\bin\offreg.dll";
    [DllImport(Lib,CharSet=CharSet.Unicode)] static extern uint OROpenHive(string p,out IntPtr h);
    [DllImport(Lib)] static extern uint ORCloseHive(IntPtr h);
    [DllImport(Lib,CharSet=CharSet.Unicode)] static extern uint OROpenKey(IntPtr h,string p,out IntPtr k);
    [DllImport(Lib)] static extern uint ORCloseKey(IntPtr h);
    [DllImport(Lib,CharSet=CharSet.Unicode)] static extern uint ORCreateKey(IntPtr h,string p,string c,uint o,IntPtr s,out IntPtr k,out uint d);
    [DllImport(Lib,CharSet=CharSet.Unicode)] static extern uint ORSetValue(IntPtr h,string n,uint t,byte[] b,uint size);
    [DllImport(Lib,CharSet=CharSet.Unicode)] static extern uint ORGetValue(IntPtr h,string p,string n,out uint t,byte[] b,ref uint size);
    [DllImport(Lib,CharSet=CharSet.Unicode)] static extern uint OREnumKey(IntPtr h,uint i,StringBuilder n,ref uint l,IntPtr c,IntPtr cl,IntPtr ft);
    [DllImport(Lib,CharSet=CharSet.Unicode)] static extern uint OREnumValue(IntPtr h,uint i,StringBuilder n,ref uint l,out uint t,byte[] b,ref uint size);
    [DllImport(Lib,CharSet=CharSet.Unicode)] static extern uint ORDeleteKey(IntPtr h,string p);
    [DllImport(Lib,CharSet=CharSet.Unicode)] static extern uint ORDeleteValue(IntPtr h,string n);
    [DllImport(Lib,CharSet=CharSet.Unicode)] static extern uint ORSaveHive(IntPtr h,string p,uint major,uint minor);
    IntPtr root;
    static void Check(uint e,string a) { if(e!=0)throw new Win32Exception((int)e,a); }
    public LiteV3Registry(string p){Check(OROpenHive(p,out root),"Open offline hive");}
    public bool Exists(string p){IntPtr k;uint e=OROpenKey(root,p,out k);if(e==2||e==3)return false;Check(e,"Check key");ORCloseKey(k);return true;}
    static string[] Enum(IntPtr h){var list=new List<string>();for(uint i=0;;i++){var b=new StringBuilder(32768);uint n=32768;uint e=OREnumKey(h,i,b,ref n,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero);if(e==259)break;Check(e,"Enum key");list.Add(b.ToString());}return list.ToArray();}
    public string[] Children(string p){if(p.Length==0)return Enum(root);IntPtr k;uint e=OROpenKey(root,p,out k);if(e==2||e==3)return new string[0];Check(e,"Open child list");try{return Enum(k);}finally{ORCloseKey(k);}}
    public string[] Values(string p){IntPtr k;uint e=OROpenKey(root,p,out k);if(e==2||e==3)return new string[0];Check(e,"Open value list");try{var names=new List<string>();byte[] b=new byte[65536];for(uint i=0;;i++){var n=new StringBuilder(32768);uint l=32768,t,size=(uint)b.Length;e=OREnumValue(k,i,n,ref l,out t,b,ref size);if(e==259)break;if(e==234){b=new byte[Math.Max(size,(uint)b.Length*2)];l=32768;size=(uint)b.Length;e=OREnumValue(k,i,n,ref l,out t,b,ref size);}Check(e,"Enum values");names.Add(n.ToString());}return names.ToArray();}finally{ORCloseKey(k);}}
    public string MultiText(string p,string n){byte[] b=new byte[65536];uint size=(uint)b.Length,t;uint e=ORGetValue(root,p,n,out t,b,ref size);if(e==2||e==3)return null;Check(e,"Read multi text");if(t!=1&&t!=2&&t!=7)return null;return Encoding.Unicode.GetString(b,0,(int)size).TrimEnd('\0');}
    public uint Kind(string p,string n){byte[] b=new byte[65536];uint size=(uint)b.Length,t;uint e=ORGetValue(root,p,n,out t,b,ref size);if(e==2||e==3)return 0;Check(e,"Read value kind");return t;}
    public int Dword(string p,string n,int fallback){byte[] b=new byte[4];uint size=4,t;uint e=ORGetValue(root,p,n,out t,b,ref size);if(e==2||e==3)return fallback;Check(e,"Read DWORD "+p+"\\"+n);if(t!=4||size!=4)throw new Exception("Not DWORD");return BitConverter.ToInt32(b,0);}
    public string Text(string p,string n){byte[] b=new byte[65536];uint size=(uint)b.Length,t;uint e=ORGetValue(root,p,n,out t,b,ref size);if(e==2||e==3)return null;Check(e,"Read text "+p+"\\"+n);if(t!=1&&t!=2)return null;return Encoding.Unicode.GetString(b,0,(int)size).TrimEnd('\0');}
    void Set(string p,string n,uint t,byte[] b){
        var opened=new List<IntPtr>();IntPtr parent=root;
        try {
            foreach(string part in p.Split(new char[]{'\\'},StringSplitOptions.RemoveEmptyEntries)) {
                IntPtr k;uint e=OROpenKey(parent,part,out k);
                if(e==2||e==3){uint d;e=ORCreateKey(parent,part,null,0,IntPtr.Zero,out k,out d);}
                Check(e,"Create/open key "+p+" part "+part);opened.Add(k);parent=k;
            }
            Check(ORSetValue(parent,n,t,b,(uint)b.Length),"Set "+p+"\\"+n);
        }finally{for(int i=opened.Count-1;i>=0;i--)ORCloseKey(opened[i]);}
    }
    public void SetDword(string p,string n,int v){Set(p,n,4,BitConverter.GetBytes(v));}
    public void SetText(string p,string n,string v){Set(p,n,1,Encoding.Unicode.GetBytes(v+"\0"));}
    public void SetMultiText(string p,string n,string[] v){Set(p,n,7,Encoding.Unicode.GetBytes(string.Join("\0",v)+"\0\0"));}
    static void Delete(IntPtr h,string p){IntPtr k;uint e=OROpenKey(h,p,out k);if(e==2||e==3)return;Check(e,"Open delete key");try{foreach(var c in Enum(k))Delete(k,c);}finally{ORCloseKey(k);}Check(ORDeleteKey(h,p),"Delete key "+p);}
    public void DeleteTree(string p){Delete(root,p);}
    public void DeleteValue(string p,string n){IntPtr k;uint e=OROpenKey(root,p,out k);if(e==2||e==3)return;Check(e,"Open delete value");try{e=ORDeleteValue(k,n);if(e!=2)Check(e,"Delete value");}finally{ORCloseKey(k);}}
    public void Save(string p){Check(ORSaveHive(root,p,6,1),"Save offline hive");}
    public void Dispose(){if(root!=IntPtr.Zero){Check(ORCloseHive(root),"Close offline hive");root=IntPtr.Zero;}}
}
