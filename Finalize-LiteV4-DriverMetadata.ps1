$ErrorActionPreference='Stop'
$root='C:\tiny11-work\lite-v4'
$image=Join-Path $root 'install.wim'
$wim='C:\26300.9818\bin\wimlib-imagex.exe'
function Stage($name){@{Stage=$name;Updated=(Get-Date).ToString('o');Output=$image}|ConvertTo-Json|Set-Content (Join-Path $root 'status.json')}
function Native([string[]]$a,[string]$label) {
    & $wim @a *> (Join-Path $root ($label+'.log'))
    if($LASTEXITCODE -ne 0){throw "$label failed with exit $LASTEXITCODE"}
}
try {
    while(-not(Test-Path -LiteralPath (Join-Path $root 'report.json'))) {
        if(Test-Path -LiteralPath (Join-Path $root 'error.txt')){throw (Get-Content (Join-Path $root 'error.txt') -Raw)}
        Start-Sleep -Seconds 2
    }
    $report=Get-Content (Join-Path $root 'report.json') -Raw|ConvertFrom-Json
    $driver=Get-Content (Join-Path $root 'driver-database-corrected-report.json') -Raw|ConvertFrom-Json
    if($driver.Changes -lt 1 -or $driver.AfterRegisteredPackages -ge $driver.BeforeRegisteredPackages -or -not $driver.KeptPackageAndInfRegistrationsVerified){throw 'Corrected driver metadata has not passed validation'}
    Copy-Item -LiteralPath (Join-Path $root 'report.json') -Destination (Join-Path $root 'report-before-driver-metadata-fix.json')
    Stage 'Embed corrected driver database and retain original hive file permissions'
    $hive=Join-Path $root 'hives\DRIVERS'
    $sddl=(Get-Acl -LiteralPath $hive).Sddl
    [IO.File]::WriteAllBytes($hive,[IO.File]::ReadAllBytes((Join-Path $root 'hives\DRIVERS.corrected')))
    if((Get-Acl -LiteralPath $hive).Sddl -ne $sddl){throw 'Driver hive ACL changed'}
    ('add "'+$hive+'" "\Windows\System32\config\DRIVERS"')| & $wim update $image 1 --check *> (Join-Path $root 'driver-metadata-update.log')
    if($LASTEXITCODE -ne 0){throw 'WIM driver metadata update failed'}
    Stage 'Compact changed WIM without changing its standard LZX compression'
    Native @('optimize',$image,'--check') 'final-optimize'
    Stage 'Verify final WIM again after the driver metadata correction'
    Native @('verify',$image) 'final-verify'
    $check=Join-Path $root 'corrected-hive-check';New-Item -ItemType Directory -Path $check -Force|Out-Null
    Native @('extract',$image,'1','\Windows\System32\config\DRIVERS',"--dest-dir=$check") 'final-extract-driver-hive'
    if((Get-FileHash (Join-Path $check 'DRIVERS')).Hash -ne (Get-FileHash $hive).Hash){throw 'Final embedded driver hive differs from corrected source'}
    if((Get-Acl (Join-Path $check 'DRIVERS')).Sddl -ne $sddl){throw 'Final driver hive ACL differs'}
    # Only DRIVERS changed in this correction; the complete runtime comparison was completed by the main build.
    $report.Bytes=(Get-Item -LiteralPath $image).Length
    $report.SavedBytes=$report.SourceBytes-$report.Bytes
    $report.SHA256=(Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash
    $report.DriverDatabaseRegisteredPackagesBefore=$driver.BeforeRegisteredPackages
    $report.DriverDatabaseRegisteredPackagesAfter=$driver.AfterRegisteredPackages
    $report|Add-Member -NotePropertyName DriverDatabaseMappingChanges -NotePropertyValue $driver.Changes -Force
    $report|Add-Member -NotePropertyName KeptDriverRegistrationsVerified -NotePropertyValue $true -Force
    $report|Add-Member -NotePropertyName FinalDriverMetadataCorrectionVerified -NotePropertyValue $true -Force
    $report|ConvertTo-Json -Depth 5|Set-Content (Join-Path $root 'report.json')
    $report.SHA256|Set-Content (Join-Path $root 'install.wim.sha256')
    Copy-Item -LiteralPath (Join-Path $root 'driver-database-corrected-report.json') -Destination (Join-Path $root 'driver-database-report.json')
    Native @('info',$image) 'image-info-final'
    Stage 'Complete: v4 install.wim ready; v3 unchanged; final driver metadata verified'
}catch {
    $_|Out-String|Set-Content (Join-Path $root 'metadata-finalize-error.txt')
    Stage ('FAILED: '+$_.Exception.Message)
    exit 1
}
