$ErrorActionPreference='Stop'
$root='C:\tiny11-work\app-metadata-cleanup'
Add-Type -Path (Join-Path $root 'OfflineAppMetadata.cs')
$names=[string[]](Get-Content -LiteralPath (Join-Path $root 'app-identities.txt'))
foreach($hive in @('SOFTWARE','NTUSER.DAT')) {
    $hits=[OfflineAppMetadata]::Process((Join-Path $root $hive),'',$names,$false)
    [IO.File]::WriteAllLines((Join-Path $root ($hive+'.before.txt')),$hits)
    Write-Output ($hive+': '+$hits.Length+' matching keys/values')
}
