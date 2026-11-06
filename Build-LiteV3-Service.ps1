param([switch]$Resume)
$ErrorActionPreference='Stop'
$root='C:\tiny11-work\lite-v3'
$mount=Join-Path $root 'mount'
$wim='C:\26300.9818\bin\wimlib-imagex.exe'
$work=Join-Path $root 'working.wim'
New-Item -ItemType Directory -Path $root,$mount -Force | Out-Null
$log=Join-Path $root 'service-build.log'
function Stage($name) {
    @{Stage=$name;Updated=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $root 'status.json')
    "[$(Get-Date -Format o)] $name" | Add-Content $log
}
function Native($exe,[string[]]$arguments,$name) {
    $out=Join-Path $root ($name+'.log')
    & $exe @arguments *> $out
    if($LASTEXITCODE -ne 0){throw "$name failed ($LASTEXITCODE); see $out"}
    Get-Content -LiteralPath $out -Raw
}
try {
    if(-not $Resume) {
    Stage 'Export original updated Windows 11 Pro, retaining standard LZX compression'
    if(Test-Path -LiteralPath $work){throw 'Working image already exists; refusing to overwrite.'}
    $iso='C:\26300.9818\26300.9818.261025-0959.26H2_GE_RELEASE_SVC_PROD3_CLIENTMULTI_X64FRE_EN-US.ISO'
    $disk=Get-DiskImage -ImagePath $iso
    if(-not $disk.Attached){$disk=Mount-DiskImage -ImagePath $iso -PassThru}
    $source=(($disk | Get-Volume).DriveLetter)+':\sources\install.wim'
    [void](Native $wim @('export',$source,'1',$work,'--compress=LZX','--check') 'export-source')
    Stage 'Mount private working image'
    [void](Native dism.exe @('/English','/Mount-Image',"/ImageFile:$work",'/Index:1',"/MountDir:$mount",('/LogPath:'+(Join-Path $root 'dism.log'))) 'mount')
    } elseif(-not (Test-Path -LiteralPath (Join-Path $mount 'Windows\System32\config\SYSTEM'))) {throw 'Expected private mounted image is absent'}
    Stage 'Check that updates and features have no pending servicing'
    foreach($marker in @('Windows\WinSxS\pending.xml','Windows\WinSxS\reboot.xml')) {
        if(Test-Path -LiteralPath (Join-Path $mount $marker)){throw "Pending operation marker: $marker"}
    }
    foreach($kind in @('Packages','Features')) {
        $listing=Native dism.exe @('/English',"/Image:$mount","/Get-$kind",('/LogPath:'+(Join-Path $root 'dism.log'))) ('get-'+$kind)
        if($listing -match '(?im)^\s*State\s*:\s*.*pending\s*$'){throw "Pending $kind found; no component pruning permitted."}
        if($listing -notmatch '(?im)^\s*State\s*:'){throw "Cannot validate $kind listing."}
    }
    Stage 'Inventory provisioned apps before supported removal'
    $listing=Native dism.exe @('/English',"/Image:$mount",'/Get-ProvisionedAppxPackages',('/LogPath:'+(Join-Path $root 'dism.log'))) 'apps-before'
    $apps=@([regex]::Matches($listing,'(?ms)^DisplayName\s*:\s*([^\r\n]+).*?^PackageName\s*:\s*([^\r\n]+)') | ForEach-Object {
        [pscustomobject]@{Name=$_.Groups[1].Value.Trim();Package=$_.Groups[2].Value.Trim()}
    })
    if($apps.Count -eq 0){throw 'Provisioned app inventory empty or unreadable.'}
    $keep='^Microsoft\.(NET\.Native\.|UI\.Xaml\.|VCLibs\.|WindowsAppRuntime\.|AV1VideoExtension$|AVCEncoderVideoExtension$|HEIFImageExtension$|HEVCVideoExtension$|MPEG2VideoExtension$|RawImageExtension$|VP9VideoExtensions$|WebMediaExtensions$|WebpImageExtension$|WindowsCalculator$|DesktopAppInstaller$|SecHealthUI$|Services\.Store\.Engagement$)'
    if(-not $Resume){$apps | ConvertTo-Json | Set-Content (Join-Path $root 'apps-before.json')}
    $remove=@($apps | Where-Object {$_.Name -notmatch $keep})
    $remove | ConvertTo-Json | Set-Content (Join-Path $root 'apps-removed.json')
    $i=0
    $protected=[Collections.Generic.List[object]]::new()
    foreach($app in @($apps|Where-Object {$_.Name -in @('Microsoft.DesktopAppInstaller','Microsoft.SecHealthUI','Microsoft.Services.Store.Engagement')})){$protected.Add($app)}
    foreach($app in $remove) {
        $i++
        Stage "Deprovision app $i/$($remove.Count): $($app.Name)"
        try {
            [void](Native dism.exe @('/English',"/Image:$mount",'/Remove-ProvisionedAppxPackage',"/PackageName:$($app.Package)",('/LogPath:'+(Join-Path $root 'dism.log'))) ('remove-app-'+$i))
        } catch {
            $tail=(Get-Content (Join-Path $root 'dism.log') -Tail 180) -join "`n"
            if($LASTEXITCODE -eq 15610 -and $tail -match 'policy prevents the removal of this package') {
                $protected.Add($app)
                "Retained protected provisioned package: $($app.Package)"|Add-Content $log
            }else{throw}
        }
    }
    Stage 'Verify remaining provisioned apps'
    $remaining=Native dism.exe @('/English',"/Image:$mount",'/Get-ProvisionedAppxPackages',('/LogPath:'+(Join-Path $root 'dism.log'))) 'apps-after'
    foreach($app in $remove){if($app.Package -notin $protected.Package -and $remaining.Contains($app.Package)){throw "App still provisioned: $($app.Package)"}}
    $original=@(Get-Content (Join-Path $root 'apps-before.json') -Raw|ConvertFrom-Json)
    @($original|Where-Object {-not $remaining.Contains($_.Package)})|ConvertTo-Json|Set-Content (Join-Path $root 'apps-removed.json')
    @($protected)|ConvertTo-Json|Set-Content (Join-Path $root 'apps-protected-retained.json')
    Stage 'Commit supported app removals before final offline payload trimming'
    [void](Native dism.exe @('/English','/Unmount-Image',"/MountDir:$mount",'/Commit',('/LogPath:'+(Join-Path $root 'dism.log'))) 'unmount')
    Stage 'Servicing phase completed'
    'OK' | Set-Content (Join-Path $root 'service-complete.txt')
} catch {
    $_ | Out-String | Set-Content (Join-Path $root 'service-error.txt')
    Stage ('FAILED: '+$_.Exception.Message)
    exit 1
}
