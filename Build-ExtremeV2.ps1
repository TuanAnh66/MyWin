[CmdletBinding()]
param([switch]$Resume)
$ErrorActionPreference = 'Stop'
$root = 'C:\tiny11-work\extreme-v2'
$sourceIso = 'C:\tiny11-work\tiny11-extreme-26300.9818.iso'
$outputIso = 'C:\tiny11-work\tiny11-extreme-v2-26300.9818.iso'
$wim = 'C:\26300.9818\bin\wimlib-imagex.exe'
$isoTool = 'C:\Users\Administrator\AppData\Local\Tiny11Builder\tools\oscdimg.exe'
if ((Test-Path -LiteralPath $root) -and -not $Resume) { throw 'V2 workspace already exists; inspect it instead of overwriting.' }
if (Test-Path -LiteralPath $outputIso) { throw 'Output already exists.' }
New-Item -ItemType Directory -Path $root -Force | Out-Null
$log = Join-Path $root 'build.log'
$statusFile = Join-Path $root 'status.json'
function Stage([string]$name) {
    [pscustomobject]@{ Stage=$name; Updated=(Get-Date).ToString('o'); Source=$sourceIso; Output=$outputIso } |
        ConvertTo-Json | Set-Content -LiteralPath $statusFile -Encoding UTF8
    ('[{0}] {1}' -f (Get-Date -Format o),$name) | Add-Content -LiteralPath $log
}
function Run([string]$exe, [string[]]$toolArgs, [string]$inputText) {
    ('RUN: {0} {1}' -f $exe,($toolArgs -join ' ')) | Add-Content -LiteralPath $log
    $start = [Diagnostics.ProcessStartInfo]::new($exe)
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    $hasInput=-not [string]::IsNullOrEmpty($inputText)
    $start.RedirectStandardInput=$hasInput
    foreach($arg in $toolArgs) { $start.ArgumentList.Add($arg) }
    $proc=[Diagnostics.Process]::new()
    $proc.StartInfo=$start
    [void]$proc.Start()
    $stdout=$proc.StandardOutput.ReadToEndAsync()
    $stderr=$proc.StandardError.ReadToEndAsync()
    $inputFailure=$null
    if($hasInput) {
        try { $proc.StandardInput.Write($inputText); $proc.StandardInput.Close() }
        catch { $inputFailure=$_ }
    }
    $proc.WaitForExit()
    $out=$stdout.GetAwaiter().GetResult()
    $err=$stderr.GetAwaiter().GetResult()
    $out | Add-Content -LiteralPath $log
    $err | Add-Content -LiteralPath $log
    if($proc.ExitCode -ne 0) { throw ('Tool exit {0}: {1}' -f $proc.ExitCode,$err) }
    if($inputFailure) { throw $inputFailure }
    return $out
}
function DeleteCommands([string[]]$paths) {
    return (($paths | ForEach-Object { 'delete --force --recursive "' + $_ + '"' }) -join "`n") + "`n"
}
try {
    Stage 'Verify preserved source ISO'
    $sourceHash=(Get-FileHash -LiteralPath $sourceIso -Algorithm SHA256).Hash
    if($sourceHash -ne '9D7B813A243B5EFF15B2B3FD38B0E49A175FD71602231DBDA7D6307F8A7E9188') { throw 'Source hash differs from the completed v1 report.' }
    $disk=Get-DiskImage -ImagePath $sourceIso
    if(-not $disk.Attached) { $disk=Mount-DiskImage -ImagePath $sourceIso -PassThru }
    $source=($disk | Get-Volume).DriveLetter + ':\'
    $media=Join-Path $root 'media'
    Stage 'Copy setup media without changing source ISO'
    $copyLog=Join-Path $root 'copy.log'
    & robocopy.exe $source $media /E /XF install.esd install.wim /R:1 /W:1 /NFL /NDL /NP "/LOG:$copyLog" | Out-Null
    if($LASTEXITCODE -ge 8) { throw 'Copy failed.' }
    # ISO files are read-only. Clear that attribute only on the private copied media.
    Get-ChildItem -LiteralPath $media -File -Recurse | ForEach-Object { $_.IsReadOnly=$false }
    $install=Join-Path $root 'install-working.wim'
    Stage 'Export v1 installation image for payload removal'
    if(-not (Test-Path -LiteralPath $install)) {
        [void](Run $wim @('export',($source+'sources\install.esd'),'1',$install,'--compress=XPRESS','--check','--threads=8') $null)
    }
    $installPaths=(Run $wim @('dir',$install,'1') $null) -split '\r?\n'
    $appDirectories=@($installPaths | Where-Object {$_ -match '^\\Program Files\\WindowsApps\\[^\\]+$'})
    $installDeletes=@('\Program Files\WindowsApps')
    $installDeletes | Set-Content -LiteralPath (Join-Path $root 'install-removed-paths.txt')
    if($appDirectories.Count) { $appDirectories | Set-Content -LiteralPath (Join-Path $root 'removed-app-directories.txt') }
    Stage 'Remove all remaining WindowsApps application and shared-framework payloads'
    [void](Run $wim @('update',$install,'1','--check') (DeleteCommands $installDeletes))
    $afterPaths=(Run $wim @('dir',$install,'1') $null) -split '\r?\n'
    if($afterPaths | Where-Object {$_ -match '^\\Program Files\\WindowsApps(?:\\|$)'}) { throw 'WindowsApps payload removal verification failed.' }
    Stage 'Inventory boot image for aggressive trimming'
    $boot=Join-Path $media 'sources\boot.wim'
    $bootBefore=(Get-Item -LiteralPath $boot).Length
    $bootPaths=(Run $wim @('dir',$boot,'1') $null) -split '\r?\n'
    $metadata=@('Catalogs','FileMaps','Fusion','InstallTemp','Manifests','SettingsManifests','Temp')
    $runtime='common-controls|c\.\.-controls|gdiplus|isolationautomation|utomation\.proxystub|microsoft\.vc\d+\.crt|servicing|s\.\.(?:ngstack|stack)'
    $bootDeletes=@('\Windows\servicing\MumX','\Windows\WinSxS\Backup','\Windows\WinSxS\Temp',
        '\Windows\Logs','\Windows\SoftwareDistribution\Download','\Windows\Temp',
        '\Windows\Speech','\Windows\Speech_OneCore','\Windows\OCR','\Windows\IME',
        '\Windows\System32\IME','\Windows\System32\InputMethod','\Windows\Web',
        '\Windows\Media','\Windows\Help','\Windows\Cursors','\Windows\Microsoft.NET',
        '\Windows\assembly','\Windows\Fonts\seguiemj.ttf')
    foreach($path in $bootPaths) {
        if($path -match '^\\Windows\\WinSxS\\([^\\]+)$') {
            $name=$Matches[1]
            if($name -notin $metadata -and $name -notmatch $runtime) { $bootDeletes += $path }
        }
    }
    $bootDeletes=@($bootDeletes | Where-Object {$_ -in $bootPaths} | Sort-Object -Unique)
    $bootDeletes | Set-Content -LiteralPath (Join-Path $root 'boot-removed-paths.txt')
    Stage 'Trim WinPE component-store copies, servicing cache and optional resources'
    [void](Run $wim @('update',$boot,'1','--check') (DeleteCommands $bootDeletes))
    Stage 'Recompress boot.wim as bootable LZX'
    [void](Run $wim @('optimize',$boot,'--recompress','--compress=LZX','--threads=8','--check') $null)
    $bootAfter=(Get-Item -LiteralPath $boot).Length
    if($bootAfter -ge $bootBefore) { throw 'Boot image trimming did not reduce size.' }
    $bootAfterPaths=(Run $wim @('dir',$boot,'1') $null) -split '\r?\n'
    foreach($required in @('\Windows\System32\winload.efi','\Windows\System32\wpeinit.exe','\Windows\System32\winpeshl.ini','\sources\setup.exe')) {
        if($required -notin $bootAfterPaths) { throw ('Required boot/setup file missing: '+$required) }
    }
    Stage 'Export application-free image using solid LZMS compression'
    $finalInstall=Join-Path $media 'sources\install.esd'
    [void](Run $wim @('export',$install,'1',$finalInstall,'--compress=LZMS','--solid','--threads=8','--check') $null)
    Stage 'Verify installation and boot WIM integrity'
    [void](Run $wim @('verify',$finalInstall) $null)
    [void](Run $wim @('verify',$boot) $null)
    Stage 'Create separate v2 ISO'
    $efi=Join-Path $media 'efi\microsoft\boot\efisys.bin'
    $bios=Join-Path $media 'boot\etfsboot.com'
    $bootArg=if(Test-Path -LiteralPath $bios) { '-bootdata:2#p0,e,b'+$bios+'#pEF,e,b'+$efi } else { '-bootdata:1#pEF,e,b'+$efi }
    [void](Run $isoTool @('-m','-o','-u2','-udfver102','-lTINY11_EXTREME_V2',$bootArg,$media,$outputIso) $null)
    Stage 'Hash final ISO and record measured results'
    $outputHash=(Get-FileHash -LiteralPath $outputIso -Algorithm SHA256).Hash
    $sourceHashAfter=(Get-FileHash -LiteralPath $sourceIso -Algorithm SHA256).Hash
    if($sourceHashAfter -ne $sourceHash) { throw 'Preserved source hash changed.' }
    [pscustomobject]@{
        SourceIso=$sourceIso; SourceSha256=$sourceHash; SourcePreserved=$true
        OutputIso=$outputIso; OutputBytes=(Get-Item -LiteralPath $outputIso).Length; Sha256=$outputHash
        RemovedWindowsAppsDirectories=@(Get-Content -LiteralPath (Join-Path $root 'removed-app-directories.txt')).Count; BootBytesBefore=$bootBefore; BootBytesAfter=$bootAfter
        RemovedBootPaths=$bootDeletes.Count; BootValidated=$false
        Notes=@('All remaining WindowsApps payloads, including shared app frameworks, removed directly from already-unserviceable Core image.',
            'No DISM deprovisioning attempted on the Core image; registration metadata may remain.',
            'Windows shell SystemApps and boot/storage/USB driver files retained. Boot is experimental and untested in a VM.')
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root 'report.json') -Encoding UTF8
    Stage 'Complete'
} catch {
    $_ | Out-String | Add-Content -LiteralPath $log
    Stage ('FAILED: '+$_.Exception.Message)
    throw
}
