$ErrorActionPreference='Stop'
$root='C:\tiny11-work\lite-v5'
$source='C:\tiny11-work\lite-v4-virtio\install.wim'
$work=Join-Path $root 'working.wim'
$output=Join-Path $root 'install.wim'
$wim='C:\26300.9818\bin\wimlib-imagex.exe'
if(Test-Path -LiteralPath $root){throw 'V5 directory already exists; refusing to overwrite'}
New-Item -ItemType Directory -Path $root | Out-Null
$log=Join-Path $root 'build.log'
function Stage($s){@{Stage=$s;Updated=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $root 'status.json');"[$(Get-Date -Format o)] $s"|Add-Content $log}
function Run([string[]]$arguments,[string]$inputText='',[string]$exe=$wim) {
 $si=[Diagnostics.ProcessStartInfo]::new($exe);$si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true;$si.RedirectStandardInput=($inputText.Length -gt 0)
 foreach($a in $arguments){$si.ArgumentList.Add($a)}
 $p=[Diagnostics.Process]::new();$p.StartInfo=$si;[void]$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync()
 if($si.RedirectStandardInput){$p.StandardInput.Write($inputText);$p.StandardInput.Close()}
 $p.WaitForExit();$out=$o.GetAwaiter().GetResult();$err=$e.GetAwaiter().GetResult()
 if($arguments[0] -ne 'dir'){$out,$err|Add-Content $log}
 if($p.ExitCode -ne 0){throw "$exe exit $($p.ExitCode): $err"}
 return $out
}
function Manifest([string]$image,[string]$label) {
 $dict=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
 $text=Run @('dir',$image,'1','--detailed')
 foreach($block in [regex]::Split($text,'(?m)^-{20,}\r?$')) {
  if($block -match 'FILE_ATTRIBUTE_DIRECTORY is set'){continue}
  $m=[regex]::Match($block,'(?m)^Full Path\s*=\s*"([^"]+)"');if(-not $m.Success){continue}
  $hash=@([regex]::Matches($block,'(?m)^Hash\s*=\s*(0x[0-9a-fA-F]+)\s*$')|ForEach-Object {$_.Groups[1].Value})
  $size=@([regex]::Matches($block,'(?m)^Uncompressed size\s*=\s*([0-9]+) bytes\s*$')|ForEach-Object {$_.Groups[1].Value})
  $dict.Add($m.Groups[1].Value,(($hash -join ';')+"`t"+($size -join ';')))
 }
 $dict.GetEnumerator()|ForEach-Object {$_.Key+"`t"+$_.Value}|Sort-Object|Set-Content (Join-Path $root ($label+'-files.txt'))
 return ,$dict
}
try {
 Stage 'Verify v4 VirtIO source and record all file hashes'
 $srcReport=Get-Content 'C:\tiny11-work\lite-v4-virtio\report.json' -Raw|ConvertFrom-Json
 $before=(Get-FileHash -LiteralPath $source).Hash
 if($before -ne $srcReport.SHA256){throw 'Source hash differs from verified v4 VirtIO build'}
 $baseline=Manifest $source 'source'
 $paths=(Run @('dir',$source,'1')) -split '\r?\n' | Where-Object {$_ -match '^\\'}
 $remove=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach($r in @('\Windows\System32\Microsoft-Edge-WebView','\Program Files (x86)\Microsoft\EdgeWebView','\Windows\System32\SecureBootUpdates','\Windows\SystemApps\Shared\WebView2SDK')) {
  if($paths -notcontains $r){throw "Expected removal folder missing: $r"};[void]$remove.Add($r)
 }
 # Explicit CJK families, including Chinese Yi and CJK DOS code-page fonts.
 $fontPattern='^(app(932|936|949|950)\.fon|malgun[^\\]*\.ttf|mingliu[^\\]*\.ttc|msgothic\.ttc|msjh[^\\]*\.ttc|msyh[^\\]*\.ttc|msyi\.ttf|simsun[^\\]*\.(ttc|ttf)|yugoth[^\\]*\.ttc|yumin[^\\]*\.ttc|meiryo[^\\]*\.ttc|simhei\.ttf|simkai\.ttf|simfang\.ttf|kaiu\.ttf|batang[^\\]*\.ttc|gulim[^\\]*\.ttc|dotum[^\\]*\.ttc)$'
 $fonts=@($paths | Where-Object {$_ -match '^\\Windows\\Fonts\\[^\\]+$' -and (($_ -split '\\')[-1] -match $fontPattern)})
 if($fonts.Count -lt 20){throw 'CJK font plan unexpectedly small'}
 $fonts|ForEach-Object {($_ -split '\\')[-1]}|Set-Content (Join-Path $root 'removed-font-files.txt')
 foreach($f in $fonts){[void]$remove.Add($f)}
 foreach($p in $paths){
  if($p -match '\\(Microsoft\.Web\.WebView2\.[^\\]+|WebView2Loader\.dll|WebView2Standalone\.(dll|winmd))$' -or $p -eq '\Windows\Fonts\StaticCache.dat'){[void]$remove.Add($p)}
 }
 $protected=@('\Windows\Microsoft.NET','\Windows\assembly','\Windows\SysWOW64','\Windows\System32\WindowsPowerShell','\Program Files\WindowsPowerShell','\Program Files (x86)\WindowsPowerShell','\Windows\System32\DriverStore','\Windows\System32\drivers')
 foreach($d in $remove){foreach($r in $protected){if($d -eq $r -or $d.StartsWith($r+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Protected file removal: $d"}}}
 $remove|Sort-Object|Set-Content (Join-Path $root 'removed-paths.txt')
 Stage 'Copy source WIM and clean font/runtime registrations in private SOFTWARE hive'
 Copy-Item -LiteralPath $source -Destination $work
 $hives=Join-Path $root 'hives';New-Item -ItemType Directory -Path $hives|Out-Null
 [void](Run @('extract',$work,'1','\Windows\System32\config\SOFTWARE',"--dest-dir=$hives"))
 [void](Run @('-NoProfile','-ExecutionPolicy','Bypass','-File','C:\tiny11-work\Clean-V5-Registry.ps1') '' 'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe')
 $hive=Join-Path $hives 'SOFTWARE';$acl=(Get-Acl -LiteralPath $hive).Sddl
 [IO.File]::WriteAllBytes($hive,[IO.File]::ReadAllBytes($hive+'.cleaned'))
 if((Get-Acl -LiteralPath $hive).Sddl -ne $acl){throw 'SOFTWARE ACL changed'}
 foreach($p in $paths){if($p -match '^\\Windows\\System32\\config\\SOFTWARE.+\.(LOG[12]?|TM\.blf|regtrans-ms)(\.cnpf)?$' -or $p -match '^\\Windows\\System32\\config\\SOFTWARE\.LOG[12]?$'){[void]$remove.Add($p)}}
 $cmds=@($remove | Sort-Object | ForEach-Object {'delete --force --recursive "'+$_+'"'})
 $cmds+=('add "'+$hive+'" "\Windows\System32\config\SOFTWARE"')
 $cmds|Set-Content (Join-Path $root 'wim-update-commands.txt')
 Stage 'Remove selected payloads from private WIM; export normal LZX install.wim'
 [void](Run @('update',$work,'1','--check') (($cmds -join "`n")+"`n"))
 [void](Run @('export',$work,'1',$output,'--compress=LZX','--threads=8','--check'))
 Stage 'Verify all WIM data and compare every retained file with v4 VirtIO'
 [void](Run @('verify',$output))
 $after=Manifest $output 'output'
 $removedFiles=0;$unchanged=0
 foreach($entry in $baseline.GetEnumerator()) {
  $cut=$false
  foreach($r in $remove){if($entry.Key -eq $r -or $entry.Key.StartsWith($r+'\',[StringComparison]::OrdinalIgnoreCase)){$cut=$true;break}}
  if($cut){if($after.ContainsKey($entry.Key)){throw "Deleted file remains: $($entry.Key)"};$removedFiles++;continue}
  if(-not $after.ContainsKey($entry.Key)){throw "Unexpected missing file: $($entry.Key)"}
  if($entry.Key -eq '\Windows\System32\config\SOFTWARE'){continue}
  if($entry.Value -ne $after[$entry.Key]){throw "Unexpected file change: $($entry.Key)"};$unchanged++
 }
 foreach($key in $after.Keys){if(-not $baseline.ContainsKey($key)){throw "Unexpected new file: $key"}}
 $pathsAfter=(Run @('dir',$output,'1')) -split '\r?\n'|Where-Object {$_ -match '^\\'}
 $pathsAfter|Set-Content (Join-Path $root 'paths-final.txt')
 foreach($r in $remove){if($pathsAfter -contains $r){throw "Removal path remains: $r"}}
 foreach($font in @('segoeui.ttf','SegUIVar.ttf','arial.ttf','consola.ttf','seguiemj.ttf','seguisym.ttf','SegoeIcons.ttf')){if($pathsAfter -notcontains ('\Windows\Fonts\'+$font)){throw "Protected font missing: $font"}}
 $protectedCount=@($after.Keys|Where-Object {$p=$_;@($protected|Where-Object {$p.StartsWith($_+'\',[StringComparison]::OrdinalIgnoreCase)}).Count -gt 0}).Count
 Stage 'Confirm source preserved and write final checksum/report'
 if((Get-FileHash -LiteralPath $source).Hash -ne $before){throw 'Original v4 VirtIO WIM changed'}
 $hash=(Get-FileHash -LiteralPath $output).Hash;$hash|Set-Content (Join-Path $root 'install.wim.sha256')
 @{Output=$output;Build='26300.9818';Compression='LZX';Bytes=(Get-Item $output).Length;SHA256=$hash;Source=$source;SourceSHA256=$before;SourcePreserved=$true;RemovedFontFiles=$fonts.Count;RemovedFileCount=$removedFiles;UnchangedRetainedFiles=$unchanged;ProtectedFiles=$protectedCount;DotNetPowerShellWow64AndVirtioUnchanged=$true;SystemAndDriversHivesUnchanged=$true;WimIntegrityVerified=$true;VmBootTestPerformed=$false;RemovedWebViewRuntimes=$true;RemovedWebViewSdkFiles=$true;RemovedSecureBootUpdates=$true;SoftwareHiveAclPreserved=$true;SavedBytes=((Get-Item $source).Length-(Get-Item $output).Length)}|ConvertTo-Json|Set-Content (Join-Path $root 'report.json')
 Stage 'Complete: v5 install.wim ready for installation test'
}catch{$_|Out-String|Set-Content (Join-Path $root 'error.txt');Stage ('FAILED: '+$_.Exception.Message);exit 1}
