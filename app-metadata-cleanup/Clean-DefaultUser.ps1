$ErrorActionPreference='Stop'
$root='C:\tiny11-work\app-metadata-cleanup'
Add-Type -Path (Join-Path $root 'OfflineAppMetadata.cs')
$names=[string[]](Get-Content -LiteralPath (Join-Path $root 'all-removed-app-identities.txt'))
$output=Join-Path $root 'NTUSER.clean'
if(Test-Path -LiteralPath $output){throw 'Output already exists.'}
$changes=[OfflineAppMetadata]::Process((Join-Path $root 'NTUSER.DAT'),$output,$names,$true)
[IO.File]::WriteAllLines((Join-Path $root 'default-user-removed-records.txt'),$changes)
$remaining=[OfflineAppMetadata]::Process($output,'',$names,$false)
[IO.File]::WriteAllLines((Join-Path $root 'default-user-clean-after.txt'),$remaining)
if($remaining.Length){throw 'Matching metadata remains.'}
Write-Output ('Default user hive: removed '+$changes.Length+' matching record(s); zero matches after reopening.')
