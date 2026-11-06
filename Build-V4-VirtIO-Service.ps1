$ErrorActionPreference='Stop'
$root='C:\tiny11-work\lite-v4-virtio'
$mount=Join-Path $root 'mount'
$work=Join-Path $root 'working.wim'
$source='C:\tiny11-work\lite-v4\install.wim'
$esd='C:\tiny11-work\lite-v4\install.esd'
New-Item -ItemType Directory -Path $mount -Force|Out-Null
function Stage($name){@{Stage=$name;Updated=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $root 'status.json');"[$(Get-Date -Format o)] $name"|Add-Content (Join-Path $root 'service-build.log')}
function Dism([string[]]$a,[string]$label){
    $arguments=@('/English')+$a+@('/LogPath:'+(Join-Path $root 'dism.log'))
    & C:\Windows\System32\dism.exe @arguments *> (Join-Path $root ($label+'.log'))
    if($LASTEXITCODE -ne 0){throw "$label failed ($LASTEXITCODE); inspect its log"}
    Get-Content (Join-Path $root ($label+'.log')) -Raw
}
try {
    if(Test-Path -LiteralPath $work){throw 'Private working WIM already exists; refusing to overwrite'}
    Stage 'Verify and preserve existing v4 WIM and ESD; copy only WIM to private workspace'
    $baseline=Get-Content C:\tiny11-work\lite-v4\report.json -Raw|ConvertFrom-Json
    $compressed=Get-Content C:\tiny11-work\lite-v4\esd-report.json -Raw|ConvertFrom-Json
    $hash=(Get-FileHash -LiteralPath $source).Hash
    $esdHash=(Get-FileHash -LiteralPath $esd).Hash
    if($hash -ne $baseline.SHA256 -or $esdHash -ne $compressed.OutputSHA256){throw 'Original v4 file hash differs from its verified report'}
    @{Wim=$source;WimSHA256=$hash;Esd=$esd;EsdSHA256=$esdHash}|ConvertTo-Json|Set-Content (Join-Path $root 'preserved-source.json')
    Copy-Item -LiteralPath $source -Destination $work
    (Get-Item -LiteralPath $work).IsReadOnly=$false
    Stage 'Mount private v4 working image using independent elevated servicing process'
    [void](Dism @('/Mount-Image',"/ImageFile:$work",'/Index:1',"/MountDir:$mount") 'mount')
    Stage 'Add Microsoft-signed Windows 11 x64 VirtIO packages through offline DISM'
    $drivers=Join-Path $root 'drivers'
    $packages=@(Get-Content (Join-Path $root 'driver-packages.json') -Raw|ConvertFrom-Json)
    if($packages.Count -ne 6){throw 'Expected exactly six verified driver packages'}
    foreach($p in $packages){
        $signature=Get-AuthenticodeSignature -FilePath $p.Catalog
        if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Windows Hardware Compatibility Publisher'){throw 'Driver catalog verification failed'}
    }
    [void](Dism @("/Image:$mount",'/Add-Driver',"/Driver:$drivers",'/Recurse') 'add-virtio')
    Stage 'Verify staged OEM packages and boot-critical storage driver flags'
    $listing=Dism @("/Image:$mount",'/Get-Drivers','/Format:List') 'drivers-after'
    $records=[Collections.Generic.List[object]]::new()
    foreach($block in [regex]::Split($listing,'(?m)(?=^Published Name\s*:)')) {
        $published=[regex]::Match($block,'(?m)^Published Name\s*:\s*([^\r\n]+)').Groups[1].Value.Trim()
        $original=[regex]::Match($block,'(?m)^Original File Name\s*:\s*([^\r\n]+)').Groups[1].Value.Trim()
        if(-not $published -or $original -notin @('balloon.inf','netkvm.inf','vioscsi.inf','viostor.inf','vioser.inf','viorng.inf')){continue}
        $detail=Dism @("/Image:$mount",'/Get-DriverInfo',"/Driver:$published") ('driver-'+$original)
        $boot=[regex]::Match($detail,'(?m)^Boot Critical\s*:\s*([^\r\n]+)').Groups[1].Value.Trim()
        if($original -in @('vioscsi.inf','viostor.inf') -and $boot -ne 'Yes'){throw "Storage driver not boot critical: $original"}
        $versionMatches=[regex]::Matches($detail,'(?m)^Version\s*:\s*([^\r\n]+)')
        $version=$versionMatches[$versionMatches.Count-1].Groups[1].Value.Trim()
        $records.Add([pscustomobject]@{Published=$published;Original=$original;BootCritical=$boot;Version=$version})
    }
    if($records.Count -ne 6){throw "Only $($records.Count)/6 VirtIO packages found after DISM staging"}
    $records.ToArray()|ConvertTo-Json|Set-Content (Join-Path $root 'staged-drivers.json')
    Stage 'Commit driver additions to private working WIM'
    [void](Dism @('/Unmount-Image',"/MountDir:$mount",'/Commit') 'unmount')
    'OK'|Set-Content (Join-Path $root 'service-complete.txt')
    Stage 'Offline driver integration completed'
}catch {
    $_|Out-String|Set-Content (Join-Path $root 'service-error.txt')
    Stage ('FAILED: '+$_.Exception.Message)
    exit 1
}
