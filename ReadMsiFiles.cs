using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
public sealed class MsiFileRow { public string Id; public string Name; }
public static class ReadMsiFiles {
    [DllImport("msi.dll",CharSet=CharSet.Unicode)] static extern uint MsiOpenDatabaseW(string path,IntPtr mode,out uint handle);
    [DllImport("msi.dll",CharSet=CharSet.Unicode)] static extern uint MsiDatabaseOpenViewW(uint db,string sql,out uint view);
    [DllImport("msi.dll")] static extern uint MsiViewExecute(uint view,uint record);
    [DllImport("msi.dll")] static extern uint MsiViewFetch(uint view,out uint record);
    [DllImport("msi.dll",CharSet=CharSet.Unicode)] static extern uint MsiRecordGetStringW(uint record,uint field,StringBuilder value,ref uint size);
    [DllImport("msi.dll")] static extern uint MsiViewClose(uint view);
    [DllImport("msi.dll")] static extern uint MsiCloseHandle(uint handle);
    static void Check(uint e){if(e!=0)throw new Win32Exception((int)e,"Read MSI database");}
    static string Field(uint r,uint f){var b=new StringBuilder(4096);uint size=4096;Check(MsiRecordGetStringW(r,f,b,ref size));return b.ToString();}
    public static MsiFileRow[] Read(string path){
        uint db=0,view=0;var rows=new List<MsiFileRow>();
        try {
            Check(MsiOpenDatabaseW(path,IntPtr.Zero,out db));
            Check(MsiDatabaseOpenViewW(db,"SELECT `File`, `FileName` FROM `File`",out view));
            Check(MsiViewExecute(view,0));
            for(;;){uint r;uint e=MsiViewFetch(view,out r);if(e==259)break;Check(e);try{rows.Add(new MsiFileRow{Id=Field(r,1),Name=Field(r,2)});}finally{MsiCloseHandle(r);}}
            return rows.ToArray();
        }finally{if(view!=0){MsiViewClose(view);MsiCloseHandle(view);}if(db!=0)MsiCloseHandle(db);}
    }
}
