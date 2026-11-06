param([switch]$ResumeVerification)
$ErrorActionPreference='Stop'
$root='C:\tiny11-work\lite-v4-virtio'
$work=Join-Path $root 'working.wim'
$output=Join-Path $root 'install.wim'
$wim='C:\26300.9818\bin\wimlib-imagex.exe'
$log=Join-Path $root 'finish-build.log'
function Stage($name){@{Stage=$name;Updated=(Get-Date).ToString('o');Output=$output}|ConvertTo-Json|Set-Content (Join-Path $root 'status.json');"[$(Get-Date -Format o)] $name"|Add-Content $log}
function Run([string]$exe,[string[]]$arguments) {
    $s=[Diagnostics.ProcessStartInfo]::new($exe);$s.UseShellExecute=$false;$s.CreateNoWindow=$true;$s.RedirectStandardOutput=$true;$s.RedirectStandardError=$true
    foreach($a in $arguments){$s.ArgumentList.Add($a)}
    $p=[Diagnostics.Process]::new();$p.StartInfo=$s;[void]$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();$p.WaitForExit()
    $out=$o.GetAwaiter().GetResult();$err=$e.GetAwaiter().GetResult()
    if($p.ExitCode -ne 0){$out,$err|Add-Content $log;throw "$exe exit $($p.ExitCode): $err"}
    if($arguments[0] -ne 'dir'){$out,$err|Add-Content $log}
    return $out
}
try {
    while(-not(Test-Path -LiteralPath (Join-Path $root 'service-complete.txt'))) {
        if(Test-Path -LiteralPath (Join-Path $root 'service-error.txt')){throw (Get-Content (Join-Path $root 'service-error.txt') -Raw)}
        Start-Sleep -Seconds 3
    }
    if(-not $ResumeVerification) {
    if(Test-Path -LiteralPath $output){throw 'Output WIM already exists; refusing to overwrite'}
    Stage 'Export new VirtIO-enabled install.wim using standard LZX compression'
    [void](Run $wim @('export',$work,'1',$output,'--compress=LZX','--check'))
    Stage 'Verify every file in new WIM and compare .NET, PowerShell and WoW64 file contents'
    [void](Run $wim @('verify',$output))
    }else {
        if(-not(Test-Path -LiteralPath $output)){throw 'Previously exported WIM missing'}
        if(-not (Select-String -LiteralPath $log -Pattern 'was successfully verified' -Quiet)){throw 'No completed WIM integrity verification found'}
        if((Get-Item -LiteralPath $output).LastWriteTime -gt (Get-Item (Join-Path $root 'runtime-files.txt')).LastWriteTime){throw 'WIM changed since completed data verification'}
        Stage 'Resume driver validation using verified unchanged WIM'
    }
    $records=[Collections.Generic.List[string]]::new()
    foreach($path in @('\Windows\Microsoft.NET','\Windows\assembly','\Windows\SysWOW64','\Windows\System32\WindowsPowerShell','\Program Files\WindowsPowerShell','\Program Files (x86)\WindowsPowerShell')) {
        $detail=Run $wim @('dir',$output,'1',"--path=$path",'--detailed')
        foreach($block in [regex]::Split($detail,'(?m)^-{20,}\r?$')) {
            if($block -match 'FILE_ATTRIBUTE_DIRECTORY is set'){continue}
            $m=[regex]::Match($block,'(?m)^Full Path\s*=\s*"([^"]+)"');if(-not $m.Success){continue}
            $hashes=@([regex]::Matches($block,'(?m)^Hash\s*=\s*(0x[0-9a-fA-F]+)\s*$')|ForEach-Object {$_.Groups[1].Value})
            $sizes=@([regex]::Matches($block,'(?m)^Uncompressed size\s*=\s*([0-9]+) bytes\s*$')|ForEach-Object {$_.Groups[1].Value})
            if($hashes.Count -eq 0){throw 'Runtime file hash missing'}
            $records.Add($m.Groups[1].Value+"`t"+($hashes -join ';')+"`t"+($sizes -join ';'))
        }
    }
    $baseline=Get-Content C:\tiny11-work\lite-v4\v4-runtime-files.txt
    $before=[Collections.Generic.HashSet[string]]::new([string[]]$baseline,[StringComparer]::Ordinal)
    if(-not $before.SetEquals([string[]]$records.ToArray())){throw '.NET, PowerShell or WoW64 files changed'}
    $records.ToArray()|Sort-Object|Set-Content (Join-Path $root 'runtime-files.txt')
    Stage 'Verify driver payloads, Microsoft signatures and boot-critical registry entries'
    $paths=(Run $wim @('dir',$output,'1')) -split '\r?\n'
    $paths|Set-Content (Join-Path $root 'paths-final.txt')
    $hives=Join-Path $root 'final-hives';New-Item -ItemType Directory -Path $hives -Force|Out-Null
    [void](Run $wim @('extract',$output,'1','\Windows\System32\config\SYSTEM','\Windows\System32\config\SOFTWARE','\Windows\System32\config\DRIVERS',"--dest-dir=$hives"))
    [void](Run 'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File','C:\tiny11-work\Verify-V4-VirtIO-Registry.ps1'))
    $payloadCheck=Join-Path $root 'verified-driver-payload';New-Item -ItemType Directory -Path $payloadCheck -Force|Out-Null
    $packages=Get-Content (Join-Path $root 'driver-packages.json') -Raw|ConvertFrom-Json
    $inputFiles=Get-Content (Join-Path $root 'driver-files.json') -Raw|ConvertFrom-Json
    foreach($package in $packages) {
        $name=$package.Driver
        $folder=@($paths|Where-Object {$_ -match ('^\\Windows\\System32\\DriverStore\\FileRepository\\'+[regex]::Escape($name)+'.inf_amd64_[^\\]+$')})
        if($folder.Count -ne 1){throw "Expected one staged folder for $name"}
        $dir=Join-Path $payloadCheck $name;New-Item -ItemType Directory -Path $dir -Force|Out-Null
        [void](Run $wim @('extract',$output,'1',$folder[0],"--dest-dir=$dir",'--no-acls'))
        $actual=Join-Path $dir (($folder[0] -split '\\')[-1])
        $infText=Get-Content -LiteralPath $package.Inf -Raw
        foreach($file in @($inputFiles|Where-Object {$_.Driver -eq $name})) {
            $path=Join-Path $actual $file.File
            if(-not(Test-Path -LiteralPath $path)){
                # The MSI includes optional configuration executables/readmes not declared by the driver INF.
                $required=([IO.Path]::GetExtension($file.File) -in @('.cat','.inf','.sys')) -or ($infText -match [regex]::Escape($file.File))
                if(-not $required){continue}
                throw "Staged driver file missing: $name/$($file.File)"
            }
            if((Get-FileHash -LiteralPath $path).Hash -ne $file.SHA256){throw 'Staged driver data differs from verified signed package'}
        }
        foreach($file in Get-ChildItem -LiteralPath $actual -File|Where-Object {$_.Extension -in @('.cat','.sys')}) {
            $sig=Get-AuthenticodeSignature -FilePath $file.FullName
            if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Windows Hardware Compatibility Publisher'){throw "Embedded Microsoft signature check failed: $($file.Name)"}
        }
    }
    Stage 'Confirm both original v4 files remain unchanged and calculate new WIM checksum'
    $preserved=Get-Content (Join-Path $root 'preserved-source.json') -Raw|ConvertFrom-Json
    if((Get-FileHash -LiteralPath $preserved.Wim).Hash -ne $preserved.WimSHA256 -or (Get-FileHash -LiteralPath $preserved.Esd).Hash -ne $preserved.EsdSHA256){throw 'Original v4 WIM or ESD changed'}
    $sha=(Get-FileHash -LiteralPath $output).Hash
    $sha|Set-Content (Join-Path $root 'install.wim.sha256')
    [void](Run $wim @('info',$output))
    @{Output=$output;Build='26300.9818';Compression='LZX';Bytes=(Get-Item $output).Length;SHA256=$sha;SourceWim=$preserved.Wim;SourceWimSHA256=$preserved.WimSHA256;SourceEsdSHA256=$preserved.EsdSHA256;OriginalV4WimAndEsdPreserved=$true;DriverRelease='0.1.302';Drivers=@($packages.Driver);DriverCount=6;MicrosoftCatalogAndKernelSignaturesVerified=$true;StagedDriverFileHashesVerified=$true;BootCriticalStorageVerified=$true;RuntimeFileCount=$before.Count;DotNetPowerShellWow64FilesUnchanged=$true;WimIntegrityVerified=$true;NativeDismDriverStagingUsed=$true;ForceUnsignedUsed=$false;VmKvmBootTestPerformed=$false;BootWimModified=$false}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $root 'report.json')
    Stage 'Complete: new VirtIO WIM ready; original v4 WIM and ESD preserved'
}catch {
    $_|Out-String|Set-Content (Join-Path $root 'finish-error.txt')
    Stage ('FAILED: '+$_.Exception.Message)
    exit 1
}
