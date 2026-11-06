$ErrorActionPreference='Stop'
$root='C:\tiny11-work\app-metadata-cleanup'
Add-Type -Path (Join-Path $root 'OfflineAppMetadata.cs')
$names=[string[]](Get-Content -LiteralPath (Join-Path $root 'all-removed-app-identities.txt'))
$clean=Join-Path $root 'SOFTWARE.clean'
if(Test-Path -LiteralPath $clean) {throw 'Cleaned hive already exists; refusing overwrite.'}
$changes=[OfflineAppMetadata]::Process((Join-Path $root 'SOFTWARE'),$clean,$names,$true)
[IO.File]::WriteAllLines((Join-Path $root 'software-removed-records.txt'),$changes)
Write-Output ('SOFTWARE: removed '+$changes.Length+' matching keys/values')
$remaining=[OfflineAppMetadata]::Process($clean,'',$names,$false)
[IO.File]::WriteAllLines((Join-Path $root 'software-after.txt'),$remaining)
if($remaining.Length) {throw 'Matching app metadata remains in cleaned SOFTWARE hive.'}
$userRemaining=[OfflineAppMetadata]::Process((Join-Path $root 'NTUSER.DAT'),'',$names,$false)
[IO.File]::WriteAllLines((Join-Path $root 'default-user-after.txt'),$userRemaining)
if($userRemaining.Length) {throw 'Default user hive contains matching app metadata requiring cleanup.'}
Write-Output 'Reopened cleaned SOFTWARE: zero matching app-identity keys/string values; default NTUSER: zero matches.'
