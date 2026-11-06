$ErrorActionPreference='Stop'
$root='C:\tiny11-work\lite-v4'
$source='C:\tiny11-work\lite-v3\install.wim'
$expected='D0DE50A9E50EA81455333669ADCB3A4A67B5FE9F4705EB99D476A8D799D361AD'
$work=Join-Path $root 'working.wim'
$output=Join-Path $root 'install.wim'
$wim='C:\26300.9818\bin\wimlib-imagex.exe'
$log=Join-Path $root 'build.log'
function Stage($name){@{Stage=$name;Updated=(Get-Date).ToString('o');Source=$source;Output=$output}|ConvertTo-Json|Set-Content (Join-Path $root 'status.json');"[$(Get-Date -Format o)] $name"|Add-Content $log}
function Run([string]$exe,[string[]]$arguments,[string]$inputText='') {
    $s=[Diagnostics.ProcessStartInfo]::new($exe);$s.UseShellExecute=$false;$s.CreateNoWindow=$true
    $s.RedirectStandardOutput=$true;$s.RedirectStandardError=$true;$s.RedirectStandardInput=($inputText.Length -gt 0)
    foreach($a in $arguments){$s.ArgumentList.Add($a)}
    $p=[Diagnostics.Process]::new();$p.StartInfo=$s;[void]$p.Start()
    $o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync()
    if($s.RedirectStandardInput){$p.StandardInput.Write($inputText);$p.StandardInput.Close()}
    $p.WaitForExit();$out=$o.GetAwaiter().GetResult();$err=$e.GetAwaiter().GetResult()
    if($p.ExitCode -ne 0){$out,$err|Add-Content $log;throw "$exe exit $($p.ExitCode): $err"}
    if($arguments[0] -ne 'dir'){$out,$err|Add-Content $log}
    return $out
}
function ComponentKey([string]$path) {
    $name=($path -split '\\')[-1]
    if($name -match '^(.+?)_([0-9a-f]{16})_([0-9]+\.[0-9]+)\.[0-9.]+_([^_]+)_[0-9a-f]+$') {
        return $Matches[1]+'|'+$Matches[2]+'|'+$Matches[3]+'|'+$Matches[4]
    }
    return $name
}
$runtimeRoots=@('\Windows\Microsoft.NET','\Windows\assembly','\Windows\SysWOW64','\Windows\System32\WindowsPowerShell','\Program Files\WindowsPowerShell','\Program Files (x86)\WindowsPowerShell')
function RuntimeManifest([string]$image,[string]$label) {
    $records=[Collections.Generic.List[string]]::new()
    foreach($path in $runtimeRoots) {
        $detail=Run $wim @('dir',$image,'1',"--path=$path",'--detailed')
        foreach($block in [regex]::Split($detail,'(?m)^-{20,}\r?$')) {
            if($block -match 'FILE_ATTRIBUTE_DIRECTORY is set'){continue}
            $m=[regex]::Match($block,'(?m)^Full Path\s*=\s*"([^"]+)"')
            if(-not $m.Success){continue}
            $hashes=@([regex]::Matches($block,'(?m)^Hash\s*=\s*(0x[0-9a-fA-F]+)\s*$')|ForEach-Object {$_.Groups[1].Value})
            $sizes=@([regex]::Matches($block,'(?m)^Uncompressed size\s*=\s*([0-9]+) bytes\s*$')|ForEach-Object {$_.Groups[1].Value})
            if($hashes.Count -eq 0){throw 'Runtime file data hash is missing from WIM metadata'}
            $records.Add($m.Groups[1].Value+"`t"+($hashes -join ';')+"`t"+($sizes -join ';'))
        }
    }
    $sorted=[string[]]@($records|Sort-Object -Unique)
    if($sorted.Count -lt 1000){throw 'Runtime file manifest is unexpectedly small'}
    [IO.File]::WriteAllLines((Join-Path $root ($label+'-runtime-files.txt')),$sorted)
    return ,$sorted
}
try {
    if(Test-Path -LiteralPath $work){throw 'V4 working file already exists; refusing to overwrite'}
    if(Test-Path -LiteralPath $output){throw 'V4 output already exists; refusing to overwrite'}
    Stage 'Verify preserved v3 source and create separate working WIM'
    $before=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if($before -ne $expected){throw 'V3 source hash differs from its completed build report'}
    Copy-Item -LiteralPath $source -Destination $work
    (Get-Item -LiteralPath $work).IsReadOnly=$false
    Stage 'Record every file hash in protected .NET, PowerShell and WoW64 directories'
    $runtimeBefore=RuntimeManifest $source 'v3'
    Stage 'Plan WinSxS removal using Oprekin component families, language and runtime generation'
    $paths=(Run $wim @('dir',$work,'1')) -split '\r?\n'
    $pathSet=[Collections.Generic.HashSet[string]]::new([string[]]$paths,[StringComparer]::OrdinalIgnoreCase)
    $other=Get-Content C:\tiny11-work\oprekin-audit\paths.txt
    $benchmark=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($p in $other){if($p -match '^\\Windows\\WinSxS\\[^\\]+$'){[void]$benchmark.Add((ComponentKey $p))}}
    $metadata=@('Catalogs','FileMaps','Fusion','FusionDiff','InstallTemp','Manifests','SettingsManifests','Temp')
    $components=@($paths|Where-Object {$_ -match '^\\Windows\\WinSxS\\[^\\]+$'})
    $componentRemove=[Collections.Generic.List[string]]::new()
    foreach($p in $components) {
        $name=($p -split '\\')[-1]
        $extraInterop=($name -match 'isolationautomation|utomation\.proxystub') -and ($name -match '_(none|en-us)_[0-9a-f]+$')
        if($name -notin $metadata -and -not $benchmark.Contains((ComponentKey $p)) -and -not $extraInterop){$componentRemove.Add($p)}
    }
    $componentRemove|Set-Content (Join-Path $root 'winsxs-removed-paths.txt')
    $componentSet=[Collections.Generic.HashSet[string]]::new([string[]]$componentRemove.ToArray(),[StringComparer]::OrdinalIgnoreCase)
    $components|Where-Object {-not $componentSet.Contains($_)}|Set-Content (Join-Path $root 'winsxs-kept-paths.txt')
    Stage 'Select unused modem, vendor network and peripheral driver packages'
    $all=@(Get-Content (Join-Path $root 'driver-inventory.json') -Raw|ConvertFrom-Json)
    if($all.Count -ne 717){throw 'Driver inventory does not match the preserved v3 image'}
    $virtual=@('vmxnet3.inf','dc21x4vm.inf','wnetvsc.inf','usbnet.inf','usb4p2pnetadapter.inf','kdnic.inf','kdnic_legacy.inf')
    $optional=@('Modem','Net','Printer','Sensor','EhStorSilo','HidMsr','FDC','FloppyDisk','Biometric','BarcodeScanner','Proximity','SBP2','POSPrinter','RemotePosDevice','PCMCIA','MidiEndpoint','HidLineDisplay','HidCashDrawer','1394','61883')
    $removed=[Collections.Generic.List[object]]::new()
    $kept=[Collections.Generic.List[object]]::new()
    foreach($d in $all) {
        $reason='Preserve core/unknown driver class'
        $cut=$false
        if($d.OprekinHasInf){$reason='Present in Oprekin baseline'}
        elseif($d.BootCritical){$reason='Boot-critical INF'}
        elseif($d.Inf -match '^c_'){$reason='Preserve device-class installer metadata'}
        elseif($d.Inf -in $virtual){$reason='Preserve virtual machine, generic USB or debug networking'}
        elseif($d.Class -in $optional) {
            $text=Get-Content -LiteralPath $d.SourceFile -Raw
            if($d.Class -eq 'Net' -and $text -match 'PCI\\VEN_8086&DEV_153[AB]'){$reason='Preserve known Intel I217 adapter'}
            else{$reason='Optional device package absent from Oprekin baseline';$cut=$true}
        }
        $d|Add-Member -NotePropertyName Decision -NotePropertyValue $reason -Force
        if($cut){$removed.Add($d)}else{$kept.Add($d)}
    }
    $removed.ToArray()|ConvertTo-Json -Depth 4|Set-Content (Join-Path $root 'drivers-removed.json')
    $kept.ToArray()|ConvertTo-Json -Depth 4|Set-Content (Join-Path $root 'drivers-kept.json')
    $driverPaths=@($removed|ForEach-Object {'\Windows\System32\DriverStore\FileRepository\'+$_.Folder})
    $infNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($d in $removed){if(-not @($kept|Where-Object {$_.Inf -eq $d.Inf}).Count){[void]$infNames.Add($d.Inf)}}
    $infPaths=@(foreach($inf in $infNames){'\Windows\INF\'+$inf;'\Windows\INF\'+[IO.Path]::ChangeExtension($inf,'pnf')})
    $deletes=[string[]]@((@($componentRemove.ToArray())+$driverPaths+$infPaths)|Where-Object {$pathSet.Contains($_)}|Sort-Object -Unique)
    foreach($d in $deletes) {
        $allowed=$d.StartsWith('\Windows\WinSxS\',[StringComparison]::OrdinalIgnoreCase) -or $d.StartsWith('\Windows\System32\DriverStore\FileRepository\',[StringComparison]::OrdinalIgnoreCase) -or $d.StartsWith('\Windows\INF\',[StringComparison]::OrdinalIgnoreCase)
        if(-not $allowed){throw "Removal escaped permitted image folders: $d"}
        foreach($r in $runtimeRoots){if($d -eq $r -or $d.StartsWith($r+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Attempted runtime deletion: $d"}}
    }
    $deletes|Set-Content (Join-Path $root 'removed-paths.txt')
    Stage 'Remove corresponding package and hardware-ID registrations from private DRIVERS hive'
    $hive=Join-Path $root 'hives\DRIVERS'
    # Re-extract the source hive to preserve its original WIM security descriptor.
    [void](Run $wim @('extract',$work,'1','\Windows\System32\config\DRIVERS',('--dest-dir='+(Join-Path $root 'hives'))))
    (Get-Item -LiteralPath $hive).IsReadOnly=$false
    [void](Run 'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File','C:\tiny11-work\Clean-LiteV4-DriverDatabase.ps1'))
    $acl=(Get-Acl -LiteralPath $hive).Sddl
    [IO.File]::WriteAllBytes($hive,[IO.File]::ReadAllBytes($hive+'.final'))
    if((Get-Acl -LiteralPath $hive).Sddl -ne $acl){throw 'DRIVERS hive file ACL changed'}
    $commands=[Collections.Generic.List[string]]::new()
    foreach($d in $deletes){$commands.Add('delete --force --recursive "'+$d+'"')}
    $commands.Add('add "'+$hive+'" "\Windows\System32\config\DRIVERS"')
    foreach($p in $paths){if($p -match '^\\Windows\\System32\\config\\DRIVERS.+\.(LOG[12]?|TM\.blf|regtrans-ms)(\.cnpf)?$' -or $p -match '^\\Windows\\System32\\config\\DRIVERS\.LOG[12]?$'){$commands.Add('delete --force "'+$p+'"')}}
    $commands|Set-Content (Join-Path $root 'wim-update-commands.txt')
    Stage 'Apply only planned WinSxS, driver-store and driver-registration changes to the v4 copy'
    [void](Run $wim @('update',$work,'1','--check') (($commands -join "`n")+"`n"))
    Stage 'Export standalone install.wim with standard LZX compression'
    [void](Run $wim @('export',$work,'1',$output,'--compress=LZX','--check'))
    Stage 'Verify complete WIM data and compare protected runtime file hashes against v3'
    [void](Run $wim @('verify',$output))
    $runtimeAfter=RuntimeManifest $output 'v4'
    $beforeSet=[Collections.Generic.HashSet[string]]::new([string[]]$runtimeBefore,[StringComparer]::Ordinal)
    if(-not $beforeSet.SetEquals([string[]]$runtimeAfter)){throw '.NET, PowerShell or WoW64 file contents differ from v3'}
    $final=(Run $wim @('dir',$output,'1')) -split '\r?\n'
    $finalSet=[Collections.Generic.HashSet[string]]::new([string[]]$final,[StringComparer]::OrdinalIgnoreCase)
    foreach($d in $deletes){if($finalSet.Contains($d)){throw "Removal verification failed: $d"}}
    foreach($d in $kept){if(-not $finalSet.Contains('\Windows\System32\DriverStore\FileRepository\'+$d.Folder)){throw "Kept driver package missing: $($d.Folder)"}}
    $final|Set-Content (Join-Path $root 'paths-final.txt')
    Stage 'Verify embedded hives, build identity, and preserved v3 source hash'
    $check=Join-Path $root 'final-hive-check';New-Item -ItemType Directory -Path $check -Force|Out-Null
    [void](Run $wim @('extract',$output,'1','\Windows\System32\config\DRIVERS','\Windows\System32\config\SYSTEM','\Windows\System32\config\SOFTWARE','\Users\Default\NTUSER.DAT',"--dest-dir=$check"))
    if((Get-FileHash (Join-Path $check 'DRIVERS')).Hash -ne (Get-FileHash $hive).Hash){throw 'Embedded DRIVERS hive hash mismatch'}
    if((Get-Acl (Join-Path $check 'DRIVERS')).Sddl -ne $acl){throw 'Embedded DRIVERS hive ACL mismatch'}
    foreach($h in @('SYSTEM','SOFTWARE','NTUSER.DAT')) {
        $baseline=Join-Path C:\tiny11-work\lite-v3\final-hive-check $h
        if((Get-FileHash (Join-Path $check $h)).Hash -ne (Get-FileHash $baseline).Hash){throw "V3 registry hive unexpectedly changed: $h"}
    }
    $info=Run $wim @('info',$output);$info|Set-Content (Join-Path $root 'image-info.txt')
    if($info -notmatch 'Build:\s+26300' -or $info -notmatch 'Service Pack Build:\s+9818'){throw 'Requested build identity not preserved'}
    $after=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if($after -ne $expected){throw 'Preserved v3 source hash changed'}
    $hash=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    $hash|Set-Content (Join-Path $root 'install.wim.sha256')
    $driverReport=Get-Content (Join-Path $root 'driver-database-report.json') -Raw|ConvertFrom-Json
    @{Output=$output;Source=$source;Build='26300.9818';Compression='LZX';Bytes=(Get-Item $output).Length;SourceBytes=(Get-Item $source).Length;SavedBytes=((Get-Item $source).Length-(Get-Item $output).Length);SHA256=$hash;SourceSHA256=$after;V3Preserved=$true;WinSxSTopEntriesBefore=$components.Count;WinSxSTopEntriesAfter=($components.Count-$componentRemove.Count);RemovedWinSxSPayloadDirectories=$componentRemove.Count;DriverFoldersBefore=$all.Count;DriverFoldersRemoved=$removed.Count;DriverFoldersAfter=$kept.Count;ProtectedRuntimeFileCount=$runtimeBefore.Count;AllProtectedRuntimeFileHashesUnchanged=$true;SystemSoftwareAndDefaultUserHivesUnchanged=$true;DriverDatabaseRegisteredPackagesBefore=$driverReport.BeforeRegisteredPackages;DriverDatabaseRegisteredPackagesAfter=$driverReport.AfterRegisteredPackages;WimIntegrityVerified=$true;DriverHiveHashAndAclVerified=$true;Serviceable=$false;VmBootTestPerformed=$false}|ConvertTo-Json|Set-Content (Join-Path $root 'report.json')
    Stage 'Complete: v4 install.wim ready; v3 unchanged'
}catch {
    $_|Out-String|Set-Content (Join-Path $root 'error.txt')
    Stage ('FAILED: '+$_.Exception.Message)
    exit 1
}
