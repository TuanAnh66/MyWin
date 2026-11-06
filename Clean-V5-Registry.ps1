$ErrorActionPreference='Stop'
$root='C:\tiny11-work\lite-v5'
Add-Type -Path C:\tiny11-work\LiteV3Registry.cs
$fonts=[string[]](Get-Content (Join-Path $root 'removed-font-files.txt'))
$set=[Collections.Generic.HashSet[string]]::new($fonts,[StringComparer]::OrdinalIgnoreCase)
$h=[LiteV3Registry]::new((Join-Path $root 'hives\SOFTWARE'))
$audit=[Collections.Generic.List[string]]::new()
try {
 foreach($base in @('Microsoft\Windows NT\CurrentVersion','WOW6432Node\Microsoft\Windows NT\CurrentVersion')) {
  $key=$base+'\Fonts'
  foreach($name in $h.Values($key)) {
   $file=$h.Text($key,$name)
   if($file -and $set.Contains([IO.Path]::GetFileName($file))){$h.DeleteValue($key,$name);$audit.Add("FONT`t$name`t$file")}
  }
  $link=$base+'\FontLink\SystemLink'
  foreach($name in $h.Values($link)) {
   if($h.Kind($link,$name) -ne 7){continue}
   $old=[string[]]($h.MultiText($link,$name) -split "`0")
   $new=[string[]]@($old | Where-Object {$_ -and -not $set.Contains([IO.Path]::GetFileName(($_ -split ',')[0]))})
   if($old.Count -ne $new.Count){
    if($new.Count){$h.SetMultiText($link,$name,$new)}else{$h.DeleteValue($link,$name)}
    $audit.Add("FONTLINK`t$name`t$($old.Count) -> $($new.Count)")
   }
  }
 }
 # Remove only WebView runtime updater/uninstaller registrations, preserving other products.
 foreach($base in @('Microsoft','WOW6432Node\Microsoft')) {
  foreach($key in @(($base+'\Windows\CurrentVersion\Uninstall'),($base+'\EdgeUpdate\Clients'),($base+'\EdgeUpdate\ClientState'),($base+'\EdgeUpdate\ClientStateMedium'))) {
   foreach($child in $h.Children($key)) {
    $entry=$key+'\'+$child
    $label=$h.Text($entry,'DisplayName')+' '+$h.Text($entry,'name')
    if($label -match 'WebView2|EdgeWebView'){$h.DeleteTree($entry);$audit.Add("WEBVIEW_REG`t$entry`t$label")}
   }
  }
 }
 $h.Save((Join-Path $root 'hives\SOFTWARE.cleaned'))
}finally{$h.Dispose()}
$audit | Set-Content (Join-Path $root 'registry-changes.txt')
$check=[LiteV3Registry]::new((Join-Path $root 'hives\SOFTWARE.cleaned'))
try {
 if($check.Text('Microsoft\Windows NT\CurrentVersion','CurrentBuildNumber') -ne '26300' -or $check.Dword('Microsoft\Windows NT\CurrentVersion','UBR',0) -ne 9818){throw 'Build identity changed'}
 foreach($base in @('Microsoft\Windows NT\CurrentVersion','WOW6432Node\Microsoft\Windows NT\CurrentVersion')) {
  foreach($n in $check.Values($base+'\Fonts')) {
   $v=$check.Text($base+'\Fonts',$n)
   if($v -and $set.Contains([IO.Path]::GetFileName($v))){throw 'Removed font still registered'}
  }
 }
}finally{$check.Dispose()}
