# Run only after the previous UUP conversion has finished.
# Example: .\Rebuild-FromCache.ps1 -UupFolder 'D:\UUP-download'
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$UupFolder,
    [string]$CacheFolder
)
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell as administrator, then run this script again.'
}
$root = (Resolve-Path -LiteralPath $UupFolder).Path
$candidates = @(
    (Join-Path $root 'convert-UUP.cmd'),
    (Join-Path $root 'files\convert-UUP.cmd')
)
$converter = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $converter) { throw 'convert-UUP.cmd was not found in UupFolder or its files subfolder.' }
$converterDir = Split-Path -Parent $converter
if (-not $CacheFolder) {
    foreach ($candidate in @((Join-Path $root 'UUPs'), (Join-Path $converterDir 'UUPs'))) {
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            if (Get-ChildItem -LiteralPath $candidate -Filter '*.esd' -File | Select-Object -First 1) {
                $CacheFolder = $candidate
                break
            }
        }
    }
}
if (-not $CacheFolder) { throw 'UUP cache not found. Supply -CacheFolder with the folder containing downloaded UUP ESD files.' }
$cache = (Resolve-Path -LiteralPath $CacheFolder).Path
if (-not (Get-ChildItem -LiteralPath $cache -Filter '*.esd' -File | Select-Object -First 1)) {
    throw 'CacheFolder does not contain UUP ESD files.'
}
$config = Join-Path $converterDir 'ConvertConfig.ini'
if (Test-Path -LiteralPath $config) {
    $backup = $config + '.' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.bak'
    Copy-Item -LiteralPath $config -Destination $backup
    Write-Host "Previous config saved: $backup"
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'ConvertConfig.ini') -Destination $config -Force
Write-Host "Converter: $converter"
Write-Host "UUP cache: $cache"
Write-Host 'Building installation media folder without ISO. Select one edition if prompted.'
Push-Location -LiteralPath $converterDir
try {
    & $converter $cache
    if ($LASTEXITCODE -ne 0) { throw "Converter exited with code $LASTEXITCODE. Read its output/log before continuing." }
} finally {
    Pop-Location
}
Write-Host 'Converter returned. Confirm its success message and locate the output folder containing sources\install.wim and sources\boot.wim.'
