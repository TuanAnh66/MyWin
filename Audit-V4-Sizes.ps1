$ErrorActionPreference='Stop'
$blobs=@{}
$pathNow=''
$hashNow=''
foreach($line in [IO.File]::ReadLines('C:\tiny11-work\lite-v4\size-audit-detail.txt')) {
 if($line -match '^Full Path\s*= "(.*)"'){$pathNow=$matches[1]}
 elseif($line -match '^Hash\s*= (\S+)'){
  $hashNow=$matches[1]
  if(-not $blobs.ContainsKey($hashNow)){$blobs[$hashNow]=[pscustomobject]@{Hash=$hashNow;Raw=0L;Compressed=0L;Paths=[Collections.Generic.List[string]]::new()}}
  $blobs[$hashNow].Paths.Add($pathNow)
 }
 elseif($line -match '^Uncompressed size\s*= (\d+)'){$blobs[$hashNow].Raw=[long]$matches[1]}
 elseif($line -match '^Compressed size\s*= (\d+)'){$blobs[$hashNow].Compressed=[long]$matches[1]}
}
$groups=@{}
foreach($b in $blobs.Values){
 $keys=@($b.Paths | ForEach-Object { $parts=$_.TrimStart('\').Split('\'); if($parts.Count -gt 3){'\'+($parts[0..2] -join '\')}else{'\'+($parts[0..([Math]::Max(0,$parts.Count-2))] -join '\')} } | Select-Object -Unique)
 foreach($key in $keys){
  if(-not $groups.ContainsKey($key)){$groups[$key]=[pscustomobject]@{Folder=$key;UniqueRaw=0L;UniqueCompressed=0L;ExclusiveCompressed=0L}}
  $g=$groups[$key];$g.UniqueRaw+=$b.Raw;$g.UniqueCompressed+=$b.Compressed
  if($keys.Count -eq 1){$g.ExclusiveCompressed+=$b.Compressed}
 }
}
$groups.Values | Sort-Object UniqueCompressed -Descending | Export-Csv 'C:\tiny11-work\lite-v4\size-audit-folders.csv' -NoTypeInformation
$blobs.Values | Sort-Object Compressed -Descending | Select-Object -First 60 @{n='MiB';e={[math]::Round($_.Compressed/1MB,2)}},@{n='RawMiB';e={[math]::Round($_.Raw/1MB,2)}},@{n='Path';e={$_.Paths[0]}} | Format-Table -AutoSize
$groups.Values | Sort-Object UniqueCompressed -Descending | Select-Object -First 35 Folder,@{n='RawMiB';e={[math]::Round($_.UniqueRaw/1MB,1)}},@{n='CompressedMiB';e={[math]::Round($_.UniqueCompressed/1MB,1)}},@{n='ExclusiveMiB';e={[math]::Round($_.ExclusiveCompressed/1MB,1)}} | Format-Table -AutoSize
