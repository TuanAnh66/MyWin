$ErrorActionPreference='Stop'
$root='C:\tiny11-work\extreme-v2'
$media=Join-Path $root 'media'
$output='C:\tiny11-work\tiny11-extreme-v2-fast-26300.9818.iso'
$wim='C:\26300.9818\bin\wimlib-imagex.exe'
$isoTool='C:\Users\Administrator\AppData\Local\Tiny11Builder\tools\oscdimg.exe'
$log=Join-Path $root 'fast-build.log'
function Stage([string]$text) {
    [pscustomobject]@{Stage=$text;Updated=(Get-Date).ToString('o');Output=$output} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'status.json') -Encoding utf8
}
try {
    if(Test-Path -LiteralPath $output) {throw 'Fast ISO already exists.'}
    if(Test-Path -LiteralPath (Join-Path $media 'sources\install.esd')) {throw 'Unexpected ESD in output media.'}
    Stage 'Verify fast installation image'
    & $wim verify (Join-Path $media 'sources\install.wim') *> $log
    if($LASTEXITCODE -ne 0){throw 'Installation WIM integrity verification failed.'}
    Stage 'Verify trimmed boot image'
    & $wim verify (Join-Path $media 'sources\boot.wim') *>> $log
    if($LASTEXITCODE -ne 0){throw 'Boot WIM integrity verification failed.'}
    Stage 'Create fast-compressed test ISO'
    $bios=Join-Path $media 'boot\etfsboot.com'
    $efi=Join-Path $media 'efi\microsoft\boot\efisys.bin'
    $bootArg='-bootdata:2#p0,e,b'+$bios+'#pEF,e,b'+$efi
    & $isoTool -m -o -u2 -udfver102 -lTINY11_V2_FAST $bootArg $media $output *>> $log
    if($LASTEXITCODE -ne 0){throw 'ISO creation failed.'}
    Stage 'Hash fast test ISO'
    $hash=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    [pscustomobject]@{
        Source='C:\tiny11-work\tiny11-extreme-26300.9818.iso'
        Output=$output;OutputBytes=(Get-Item -LiteralPath $output).Length;Sha256=$hash
        InstallCompression='XPRESS (fast, no solid LZMS)'
        BootBytes=(Get-Item -LiteralPath (Join-Path $media 'sources\boot.wim')).Length
        RemovedWindowsAppsDirectories=@(Get-Content -LiteralPath (Join-Path $root 'removed-app-directories.txt')).Count
        ImageIntegrityVerified=$true;BootValidated=$false
        Notes=@('WindowsApps payloads removed directly; provisioning metadata may remain.','Experimental boot image; a complete VM installation test is still required.','Original v1 ISO preserved.')
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $root 'fast-report.json') -Encoding utf8
    $hash | Set-Content -LiteralPath ($output+'.sha256') -Encoding ascii
    Stage 'Complete: fast test ISO created'
} catch {
    $_ | Out-String | Add-Content -LiteralPath $log
    Stage ('FAILED: '+$_.Exception.Message)
    throw
}
