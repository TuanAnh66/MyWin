param([string]$OutputName='DRIVERS.final',[string]$ReportName='driver-database-report.json',[string]$AuditName='driver-database-changes.txt')
$ErrorActionPreference='Stop'
$root='C:\tiny11-work\lite-v4'
Add-Type -Path C:\tiny11-work\LiteV3Registry.cs
# Windows PowerShell 5.1 emits a JSON array as one pipeline object; assign it directly.
$removed=Get-Content (Join-Path $root 'drivers-removed.json') -Raw|ConvertFrom-Json
$all=Get-Content (Join-Path $root 'driver-inventory.json') -Raw|ConvertFrom-Json
if($removed.Count -ne 212 -or $all.Count -ne 717){throw 'Unexpected driver JSON array shape or inventory count'}
$infSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$folders=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($d in $removed){[void]$folders.Add($d.Folder)}
foreach($inf in @($removed.Inf|Sort-Object -Unique)) {
    $kept=@($all|Where-Object {$_.Inf -eq $inf -and -not $folders.Contains($_.Folder)})
    if($kept.Count -eq 0){[void]$infSet.Add($inf)}
}
$h=[LiteV3Registry]::new((Join-Path $root 'hives\DRIVERS'))
$audit=[Collections.Generic.List[string]]::new()
function ScrubMappings([string]$key) {
    foreach($child in $h.Children($key)) {
        $sub=$key+'\'+$child
        ScrubMappings $sub
        if($h.Values($sub).Count -eq 0 -and $h.Children($sub).Count -eq 0){$h.DeleteTree($sub)}
    }
    foreach($name in $h.Values($key)) {
        if($infSet.Contains($name) -or $folders.Contains($name)) {
            $h.DeleteValue($key,$name);$audit.Add("DELETE_VALUE`t$key\$name");continue
        }
        $text=$h.MultiText($key,$name)
        if($null -eq $text){continue}
        $values=[string[]]@($text.Split([char]0)|Where-Object {$_})
        $keep=[string[]]@($values|Where-Object {-not $infSet.Contains($_) -and -not $folders.Contains($_)})
        if($values.Count -ne $keep.Count) {
            if($keep.Count -eq 0){$h.DeleteValue($key,$name)}
            elseif($h.Kind($key,$name) -eq 7){$h.SetMultiText($key,$name,$keep)}
            else{$h.SetText($key,$name,$keep[0])}
            $audit.Add("FILTER_VALUE`t$key\$name")
        }
    }
}
try {
    $registeredBefore=[Collections.Generic.HashSet[string]]::new([string[]]$h.Children('DriverDatabase\DriverPackages'),[StringComparer]::OrdinalIgnoreCase)
    $infsBefore=[Collections.Generic.HashSet[string]]::new([string[]]$h.Children('DriverDatabase\DriverInfFiles'),[StringComparer]::OrdinalIgnoreCase)
    $before=$registeredBefore.Count
    foreach($d in $removed) {
        $key='DriverDatabase\DriverPackages\'+$d.Folder
        if($h.Exists($key)){$h.DeleteTree($key);$audit.Add("DELETE_PACKAGE`t$($d.Folder)")}
    }
    foreach($inf in $infSet) {
        $key='DriverDatabase\DriverInfFiles\'+$inf
        if($h.Exists($key)){$h.DeleteTree($key);$audit.Add("DELETE_INF`t$inf")}
    }
    foreach($bucket in @('DeviceIds','DriverFiles')){ScrubMappings ('DriverDatabase\'+$bucket)}
    foreach($d in $removed){if($h.Exists('DriverDatabase\DriverPackages\'+$d.Folder)){throw 'Removed driver package is still registered'}}
    foreach($inf in $infSet){if($h.Exists('DriverDatabase\DriverInfFiles\'+$inf)){throw 'Removed INF is still registered'}}
    $registeredBefore.ExceptWith($folders)
    $infsBefore.ExceptWith($infSet)
    if(-not $registeredBefore.SetEquals([string[]]$h.Children('DriverDatabase\DriverPackages'))){throw 'Retained driver-package registrations changed unexpectedly'}
    if(-not $infsBefore.SetEquals([string[]]$h.Children('DriverDatabase\DriverInfFiles'))){throw 'Retained INF registrations changed unexpectedly'}
    $after=$h.Children('DriverDatabase\DriverPackages').Count
    if($before -eq $after){throw 'Selected driver registrations were not removed'}
    $h.Save((Join-Path (Join-Path $root 'hives') $OutputName))
}finally{$h.Dispose()}
$audit|Set-Content (Join-Path $root $AuditName)
@{BeforeRegisteredPackages=$before;AfterRegisteredPackages=$after;Changes=$audit.Count;RemovedInfIdentities=@($infSet);KeptPackageAndInfRegistrationsVerified=$true}|ConvertTo-Json -Depth 4|Set-Content (Join-Path $root $ReportName)
