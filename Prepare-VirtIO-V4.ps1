$ErrorActionPreference='Stop'
$root='C:\tiny11-work\lite-v4-virtio'
$msi=Join-Path $root 'downloads\virtio-win-gt-x64.msi'
$raw=Join-Path $root 'extracted-msi'
$dest=Join-Path $root 'drivers'
$wanted=@('balloon','netkvm','vioscsi','viostor','vioser','viorng')
Add-Type -Path C:\tiny11-work\ReadMsiFiles.cs
$rows=[ReadMsiFiles]::Read($msi)
$records=[Collections.Generic.List[object]]::new()
    foreach($record in $rows) {
        $id=$record.Id
        $name=$record.Name
        if($id -notmatch '^FILE_(balloon|netkvm|vioscsi|viostor|vioser|viorng)(?:_.*)?_w11_amd64(?:\.[a-z0-9]+)?$'){continue}
        $driver=$Matches[1]
        $name=($name -split '\|')[-1]
        if([IO.Path]::GetFileName($name) -ne $name -or $name -match '[\\/]'){throw 'Unsafe MSI member filename'}
        if([IO.Path]::GetFileName($id) -ne $id){throw 'Unsafe MSI member identifier'}
        $folder=Join-Path $dest $driver
        New-Item -ItemType Directory -Path $folder -Force|Out-Null
        $from=Join-Path $raw $id
        if(-not(Test-Path -LiteralPath $from)){throw "MSI archive member missing: $id"}
        $to=Join-Path $folder $name
        Copy-Item -LiteralPath $from -Destination $to
        $records.Add([pscustomobject]@{Driver=$driver;File=$name;SourceMember=$id;SHA256=(Get-FileHash -LiteralPath $to).Hash;Bytes=(Get-Item -LiteralPath $to).Length})
    }
$packages=[Collections.Generic.List[object]]::new()
foreach($driver in $wanted) {
    $folder=Join-Path $dest $driver
    $infs=@(Get-ChildItem -LiteralPath $folder -Filter *.inf -File)
    $cats=@(Get-ChildItem -LiteralPath $folder -Filter *.cat -File)
    if($infs.Count -ne 1 -or $cats.Count -ne 1){throw "Expected one INF and catalog for $driver"}
    $sig=Get-AuthenticodeSignature -FilePath $cats[0].FullName
    if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Windows Hardware Compatibility Publisher'){throw "Microsoft catalog signature invalid: $driver"}
    $content=Get-Content -LiteralPath $infs[0].FullName -Raw
    $version=[regex]::Match($content,'(?im)^DriverVer\s*=\s*([^\r\n]+)').Groups[1].Value.Trim()
    if(-not $version){throw 'Driver version unreadable'}
    $packages.Add([pscustomobject]@{Driver=$driver;Inf=$infs[0].FullName;Catalog=$cats[0].FullName;Version=$version;CatalogSignature=$sig.Status.ToString();Signer=$sig.SignerCertificate.Subject;CatalogSHA256=(Get-FileHash $cats[0].FullName).Hash})
}
$records.ToArray()|ConvertTo-Json -Depth 4|Set-Content (Join-Path $root 'driver-files.json')
$packages.ToArray()|ConvertTo-Json -Depth 4|Set-Content (Join-Path $root 'driver-packages.json')
@{Version='0.1.302';Upstream='https://github.com/virtio-win/virtio-win-pkg-scripts';Download='https://fedora-virt.repo.nfrance.com/virtio-win/direct-downloads/stable-virtio/virtio-win-gt-x64.msi';InstallerExecuted=$false;MsiReadOnlyExtraction=$true;MsiSHA256=(Get-FileHash $msi).Hash;MicrosoftCatalogSignaturesVerified=$true;PackageCount=$packages.Count}|ConvertTo-Json|Set-Content (Join-Path $root 'driver-source.json')
$packages.ToArray()|Select-Object Driver,Version,CatalogSignature|ConvertTo-Json
