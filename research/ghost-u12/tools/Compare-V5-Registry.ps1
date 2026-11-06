param([string]$OutputPrefix='')
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
Add-Type -Path C:\tiny11-work\LiteV3Registry.cs
$soft=[LiteV3Registry]::new((Join-Path $root 'hives\SOFTWARE'))
$sys=[LiteV3Registry]::new((Join-Path $root 'hives\SYSTEM'))
$usr=[LiteV3Registry]::new((Join-Path $root 'hives\NTUSER.DAT'))
function OutFile([string]$name){Join-Path $root ($OutputPrefix+$name)}
$rows=Get-Content (OutFile 'registry-operations.json') -Raw|ConvertFrom-Json
$result=@()
try {
 $control='ControlSet'+$sys.Dword('Select','Default',1).ToString('000')
 foreach($row in $rows){
  if($null -ne $row.ShadowedByLine){continue}
  $h=$null;$path='';$scope=''
  if($row.Key -match '^HKLM\\SOFTWARE(?:\\(.*))?$'){$h=$soft;$path=$matches[1];$scope='Machine SOFTWARE'}
  elseif($row.Key -match '^HKLM\\SYSTEM\\(.*)$'){$h=$sys;$path=$matches[1] -replace '^CurrentControlSet(?=\\|$)',$control;$scope='Machine SYSTEM'}
  elseif($row.Key -match '^HKU\\Default\\(.*)$'){$h=$usr;$path=$matches[1];$scope='Default User template'}
  elseif($row.Key -match '^HKCU\\(.*)$'){$h=$usr;$path=$matches[1];$scope='HKCU at OOBE; baseline from Default User only'}
  $kind=0;$current=$null;$state='Unsupported hive'
  if($h){
   if($row.Operation -in @('delete-key','create-key')){$current=$h.Exists($path);$state='Key existence only'}
   else {
    $kind=$h.Kind($path,$row.Name)
    if($kind -eq 0){$state='Value absent'}
    elseif($kind -eq 4){$current=([long]$h.Dword($path,$row.Name,0) -band 4294967295);$state='Value present'}
    elseif($kind -in @(1,2,7)){$current=$h.MultiText($path,$row.Name);$state='Value present'}
    else{$current='<binary or other type present>';$state='Value present; binary not decoded'}
   }
  }
  $same=$null
  if($row.Operation -eq 'add' -and $kind -ne 0 -and $state -ne 'Value present; binary not decoded'){
   if($row.Type -eq 'REG_DWORD'){$target=if($row.Value -match '^0x'){[Convert]::ToInt64($row.Value.Substring(2),16)}else{[long]$row.Value};$same=($kind -eq 4 -and $current -eq $target)}
   elseif($row.Type -in @('REG_SZ','REG_EXPAND_SZ')){$targetKind=if($row.Type -eq 'REG_SZ'){1}else{2};$same=($kind -eq $targetKind -and $current -ceq $row.Value)}
  }
  $result+=[pscustomobject]@{Line=$row.Line;Operation=$row.Operation;Scope=$scope;Key=$row.Key;Name=$row.Name;TargetType=$row.Type;Target=$row.Value;V5Kind=$kind;V5Value=$current;V5State=$state;AlreadySame=$same;Conditional=$row.Conditional}
 }
 $result|ConvertTo-Json -Depth 5|Set-Content (OutFile 'v5-registry-comparison.json')
 $result|Export-Csv (OutFile 'v5-registry-comparison.csv') -NoTypeInformation
 $targets=Import-Csv (OutFile 'service-targets.csv')
 $serviceResult=@(foreach($s in $targets){$key=$control+'\Services\'+$s.Name;$exists=$sys.Exists($key);$start=if($exists){$sys.Dword($key,'Start',-1)}else{$null};[pscustomobject]@{Service=$s.Name;SourceLine=[int]$s.Line;SuperliteStart=[int]$s.TargetStart;V5Exists=$exists;V5Start=$start;AlreadySame=($exists -and $start -eq [int]$s.TargetStart);StartOverrideNames=($sys.Values($key+'\StartOverride') -join ';')}})
 $serviceResult|ConvertTo-Json|Set-Content (OutFile 'v5-service-comparison.json')
 $serviceResult|Export-Csv (OutFile 'v5-service-comparison.csv') -NoTypeInformation
 $services=@(foreach($name in $sys.Children($control+'\Services')){$key=$control+'\Services\'+$name;[pscustomobject]@{Name=$name;Start=$sys.Dword($key,'Start',-1);Type=$sys.Dword($key,'Type',-1);ServiceDll=$sys.Text($key+'\Parameters','ServiceDll')}})
 $services|Export-Csv (Join-Path $root 'v5-services-all.csv') -NoTypeInformation
 $serviceResult|Format-Table -AutoSize
}finally{$soft.Dispose();$sys.Dispose();$usr.Dispose()}
