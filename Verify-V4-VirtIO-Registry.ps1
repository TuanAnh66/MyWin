$ErrorActionPreference='Stop'
$root='C:\tiny11-work\lite-v4-virtio'
Add-Type -Path C:\tiny11-work\LiteV3Registry.cs
$system=[LiteV3Registry]::new((Join-Path $root 'final-hives\SYSTEM'))
$software=[LiteV3Registry]::new((Join-Path $root 'final-hives\SOFTWARE'))
$db=[LiteV3Registry]::new((Join-Path $root 'final-hives\DRIVERS'))
$imagePaths=[Collections.Generic.HashSet[string]]::new([string[]](Get-Content (Join-Path $root 'paths-final.txt')),[StringComparer]::OrdinalIgnoreCase)
$services=[Collections.Generic.List[object]]::new()
try {
    if($software.Text('Microsoft\Windows NT\CurrentVersion','CurrentBuildNumber') -ne '26300' -or $software.Dword('Microsoft\Windows NT\CurrentVersion','UBR',0) -ne 9818){throw 'Windows build identity changed'}
    $controls=$system.Children('')|Where-Object {$_ -match '^ControlSet\d{3}$'}
    foreach($control in $controls) {
        foreach($driver in @('viostor','vioscsi')) {
            $key=$control+'\Services\'+$driver
            if(-not $system.Exists($key)){throw "Boot storage service missing: $driver"}
            $start=$system.Dword($key,'Start',-1)
            $group=$system.Text($key,'Group')
            $path=$system.Text($key,'ImagePath')
            if($start -ne 0 -or $group -ne 'SCSI miniport' -or $path -notmatch ($driver+'\.sys$')){throw "Storage service is not ready for boot: $driver"}
            if($path -match '^System32\\'){$imagePath='\Windows\'+$path}
            elseif($path -match '^\\SystemRoot\\'){$imagePath=$path -replace '^\\SystemRoot\\','\Windows\'}
            else{throw "Unexpected boot driver path format: $path"}
            if(-not $imagePaths.Contains($imagePath)){throw "Boot service binary missing from WIM: $imagePath"}
            foreach($name in $system.Values($key+'\StartOverride')) {
                if($system.Dword($key+'\StartOverride',$name,0) -ne 0){throw "Boot storage driver has a disabling StartOverride: $driver"}
            }
            $services.Add([pscustomobject]@{Control=$control;Driver=$driver;Start=$start;Group=$group;ImagePath=$path;WimPath=$imagePath;BinaryExists=$true})
        }
        foreach($name in @('BFE','MpsSvc','Winmgmt','AppXSvc','StateRepository')) {
            if($system.Dword($control+'\Services\'+$name,'Start',4) -eq 4){throw "Previously preserved service is now disabled: $name"}
        }
    }
    # Windows keeps boot-critical package records in SYSTEM and other records in DRIVERS.
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $names.UnionWith([string[]]$db.Children('DriverDatabase\DriverPackages'))
    $names.UnionWith([string[]]$system.Children('DriverDatabase\DriverPackages'))
    foreach($inf in @('balloon','netkvm','vioscsi','viostor','vioser','viorng')) {
        if(-not @($names|Where-Object {$_ -like ($inf+'.inf_amd64_*')}).Count){throw "Driver database registration missing: $inf"}
    }
}finally{$system.Dispose();$software.Dispose();$db.Dispose()}
@{Build='26300.9818';BootStorageServices=$services.ToArray();AllSixDriverDatabaseRegistrationsPresent=$true;EssentialServicesPreserved=$true}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $root 'registry-verification.json')
