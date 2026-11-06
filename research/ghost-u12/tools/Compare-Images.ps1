$ErrorActionPreference='Stop'
$root='C:\tiny11-work\ghost-u12-audit'
Add-Type @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Text.RegularExpressions;
public static class WimAuditManifest {
 public static Dictionary<string,string> Read(string file) {
  var result=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
  string path=null;bool dir=false;var streams=new List<string>();
  foreach(var line in File.ReadLines(file)) {
   if(line.StartsWith("Full Path")) {
    if(path!=null && !dir)result.Add(path,string.Join(";",streams));
    int a=line.IndexOf('"'),b=line.LastIndexOf('"');path=line.Substring(a+1,b-a-1);dir=false;streams.Clear();
   } else if(line.Contains("FILE_ATTRIBUTE_DIRECTORY is set")){dir=true;}
   else if(line.StartsWith("Hash ") || line.StartsWith("Uncompressed size")){streams.Add(line.Substring(line.IndexOf('=')+1).Trim());}
  }
  if(path!=null && !dir)result.Add(path,string.Join(";",streams));
  return result;
 }
}
'@
$maps=@{}
foreach($i in @(1,3,5)){$maps[$i]=[WimAuditManifest]::Read((Join-Path $root ('detail-'+$i+'.txt')))}
$summary=@()
foreach($i in @(3,5)) {
 $changes=@(foreach($key in $maps[1].Keys){if(-not $maps[$i].ContainsKey($key)){[pscustomobject]@{Path=$key;Change='Missing'}}elseif($maps[1][$key] -ne $maps[$i][$key]){[pscustomobject]@{Path=$key;Change='Content differs'}}};foreach($key in $maps[$i].Keys){if(-not $maps[1].ContainsKey($key)){[pscustomobject]@{Path=$key;Change='Added'}}})
 $changes|ConvertTo-Json -Depth 4|Set-Content (Join-Path $root ('file-content-diff-1-vs-'+$i+'.json'))
 $summary+=[pscustomobject]@{Baseline=1;Compared=$i;BaselineFiles=$maps[1].Count;ComparedFiles=$maps[$i].Count;Changes=$changes}
}
$summary|ConvertTo-Json -Depth 6|Set-Content (Join-Path $root 'image-content-comparison.json')
$summary|ConvertTo-Json -Depth 6
