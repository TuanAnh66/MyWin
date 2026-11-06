$ErrorActionPreference='Stop'
Add-Type -Path C:\tiny11-work\LiteV3Registry.cs
$root=$PSScriptRoot
$s=[LiteV3Registry]::new((Join-Path $root 'hives\SOFTWARE'))
$y=[LiteV3Registry]::new((Join-Path $root 'hives\SYSTEM'))
$u=[LiteV3Registry]::new((Join-Path $root 'hives\NTUSER.DAT'))
try{
 $q=@(
  @('User','Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced','TaskbarAnimations'),
  @('User','Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced','Start_AccountNotifications'),
  @('User','Control Panel\Desktop\WindowMetrics','MinAnimate'),
  @('User','Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','EnableTransparency'),
  @('User','System\GameConfigStore','GameDVR_Enabled'),
  @('Software','Policies\Microsoft\Windows\GameDVR','AllowGameDVR'),
  @('Software','Policies\Microsoft\Biometrics','Enabled'),
  @('System','ControlSet001\Control\Power','HibernateEnabled'),
  @('System','ControlSet001\Control\Terminal Server','fDenyTSConnections'),
  @('System','ControlSet001\Control\Terminal Server\WinStations\RDP-Tcp','UserAuthentication')
 )
 $out=@(foreach($item in $q){$h=if($item[0] -eq 'User'){$u}elseif($item[0] -eq 'System'){$y}else{$s};$t=$h.Kind($item[1],$item[2]);$v=if($t -eq 4){$h.Dword($item[1],$item[2],0)}elseif($t -in @(1,2,7)){$h.MultiText($item[1],$item[2])}else{$null};[pscustomobject]@{Hive=$item[0];Key=$item[1];Name=$item[2];Kind=$t;Value=$v}})
 $tasks=@(foreach($name in @('LanguageComponentsInstaller\Installation','Application Experience\Microsoft Compatibility Appraiser','Maintenance\WinSAT','Windows Defender')){ $key='Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\'+$name;[pscustomobject]@{Task=$name;Exists=$s.Exists($key);Id=$s.Text($key,'Id');Children=@($s.Children($key))}})
 $dependents=@(foreach($name in $y.Children('ControlSet001\Services')){$key='ControlSet001\Services\'+$name;$deps=$y.MultiText($key,'DependOnService');if($deps -and ($deps -split "`0") -contains 'SENS'){[pscustomobject]@{Service=$name;Dependencies=$deps.Replace("`0",';')}}})
 @{Values=$out;Tasks=$tasks;SensDependents=$dependents}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $root 'extra-v5-settings.json')
 $out|ForEach-Object {Write-Output ($_.Hive+' '+$_.Key+' '+$_.Name+' kind='+$_.Kind+' value='+$_.Value)}
 $tasks|ConvertTo-Json -Depth 4
}finally{$s.Dispose();$y.Dispose();$u.Dispose()}
