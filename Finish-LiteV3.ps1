param([switch]$ResumeRegistry)
$ErrorActionPreference='Stop'
$root='C:\tiny11-work\lite-v3'
$work=Join-Path $root 'working.wim'
$output=Join-Path $root 'install.wim'
$wim='C:\26300.9818\bin\wimlib-imagex.exe'
$log=Join-Path $root 'finish-build.log'
function Stage($name){@{Stage=$name;Updated=(Get-Date).ToString('o');Output=$output}|ConvertTo-Json|Set-Content (Join-Path $root 'status.json');"[$(Get-Date -Format o)] $name"|Add-Content $log}
function Run([string]$exe,[string[]]$arguments,[string]$inputText='') {
    $s=[Diagnostics.ProcessStartInfo]::new($exe);$s.UseShellExecute=$false;$s.CreateNoWindow=$true
    $s.RedirectStandardOutput=$true;$s.RedirectStandardError=$true
    $s.RedirectStandardInput=($inputText.Length -gt 0)
    foreach($a in $arguments){$s.ArgumentList.Add($a)}
    $p=[Diagnostics.Process]::new();$p.StartInfo=$s;[void]$p.Start()
    $o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync()
    if($s.RedirectStandardInput){$p.StandardInput.Write($inputText);$p.StandardInput.Close()}
    $p.WaitForExit();$out=$o.GetAwaiter().GetResult();$err=$e.GetAwaiter().GetResult()
    if($p.ExitCode -ne 0){$out,$err|Add-Content $log;throw "$exe exit $($p.ExitCode): $err"}
    if($arguments[0] -ne 'dir'){$out,$err|Add-Content $log}
    return $out
}
try {
    if(-not(Test-Path (Join-Path $root 'service-complete.txt'))){throw 'Supported servicing phase has not finished'}
    if(Test-Path -LiteralPath $output){throw 'Final output already exists; refusing to overwrite'}
    Stage 'Plan payload removals with explicit runtime and shell preservation'
    $paths=(Run $wim @('dir',$work,'1')) -split '\r?\n'
    $pathSet=[Collections.Generic.HashSet[string]]::new([string[]]$paths,[StringComparer]::OrdinalIgnoreCase)
    $paths|Set-Content (Join-Path $root 'paths-before-trim.txt')
    foreach($pending in @('\Windows\WinSxS\pending.xml','\Windows\WinSxS\reboot.xml')){if($pathSet.Contains($pending)){throw "Pending marker before pruning: $pending"}}
    $shellKeep=@('Microsoft.AAD.BrokerPlugin','Microsoft.AccountsControl','Microsoft.AsyncTextService','Microsoft.creddialoghost','Microsoft.UI.Xaml.CBS','Microsoft.Windows.AugLoop.CBS','Microsoft.Windows.CapturePicker','Microsoft.Windows.CloudExperienceHost','Microsoft.Windows.OOBENetworkCaptivePortal','Microsoft.Windows.OOBENetworkConnectionFlow','Microsoft.Windows.PrintQueueActionCenter','Microsoft.Windows.StartMenuExperienceHost','Microsoft.WindowsAppRuntime.CBS','Microsoft.WindowsAppRuntime.CBS2','Microsoft.WindowsAppRuntime.vNext.CBS','MicrosoftWindows.Client.AIX','MicrosoftWindows.Client.CBS','MicrosoftWindows.Client.Core','MicrosoftWindows.Client.FileExp','MicrosoftWindows.Client.OOBE','MicrosoftWindows.UndockedDevKit','ShellExperienceHost','Windows.PrintDialog','Shared','SxS')
    # This build adds Photon shell/service-experience COM registrations absent in the older comparison image.
    $shellKeep+='MicrosoftWindows.Client.Photon'
    $systemRemove=@($paths|Where-Object {$_ -match '^\\Windows\\SystemApps\\([^\\]+)$' -and (($Matches[1] -split '_')[0] -notin $shellKeep)})
    $systemRemove|Set-Content (Join-Path $root 'removed-systemapp-paths.txt')
    $removedApps=@(Get-Content (Join-Path $root 'apps-removed.json') -Raw|ConvertFrom-Json)
    $identities=@($removedApps.Name)+@($systemRemove|ForEach-Object {($_ -split '\\')[-1] -replace '_.*$',''})
    $identities=@($identities|Where-Object {$_}|Sort-Object -Unique)
    $identities|Set-Content (Join-Path $root 'removed-app-identities.txt')
    $appRemove=@($paths|Where-Object {$_ -match '^\\Program Files\\WindowsApps\\([^\\]+)$' -and (($Matches[1] -split '_')[0] -in $identities)})
    $tasks=@('WindowsUpdate','UpdateOrchestrator','WaaSMedic','Application Experience','Autochk','Customer Experience Improvement Program','Feedback','Maps','Windows Error Reporting','Location','Speech','XblGameSave','Xbox')
    $tasks|Set-Content (Join-Path $root 'removed-task-folders.txt')
    $deletes=@($systemRemove)+@($appRemove)+@($tasks|ForEach-Object {'\Windows\System32\Tasks\Microsoft\Windows\'+$_})
    $deletes+='\Program Files\WindowsApps\Deleted'
    $deletes+=@('\Windows\System32\Recovery\winre.wim','\Windows\SysWOW64\OneDriveSetup.exe','\Windows\System32\OneDriveSetup.exe','\Windows\Speech','\Windows\Speech_OneCore','\Windows\OCR','\Windows\Web','\Windows\Media','\Windows\Help','\Windows\Logs','\Windows\SoftwareDistribution\Download','\Windows\Temp','\Windows\servicing\LCU','\Windows\servicing\MumX','\ProgramData\Microsoft\Windows Defender','\ProgramData\Microsoft\Windows Defender Advanced Threat Protection')
    foreach($base in @('\Program Files','\Program Files (x86)')) {
        foreach($folder in @('Windows Defender','Windows Defender Advanced Threat Protection','Microsoft\Edge','Microsoft\EdgeCore','Microsoft\EdgeUpdate')){$deletes+=$base+'\'+$folder}
    }
    $metadata=@('Catalogs','FileMaps','Fusion','FusionDiff','InstallTemp','Manifests','SettingsManifests','Temp')
    $runtime='common-controls|c\.\.-controls|gdiplus|isolationautomation|utomation\.proxystub|microsoft\.vc\d+\.crt|servicing|s\.\.(?:ngstack|stack)|netfx|net-framework|mscore|dotnet|microsoft-windows-ndu|dual_(?:ntprint|prn)'
    foreach($p in $paths){if($p -match '^\\Windows\\WinSxS\\([^\\]+)$'){$n=$Matches[1];if($n -notin $metadata -and $n -notmatch $runtime){$deletes+=$p}}}
    $deletes=@($deletes|Where-Object {$pathSet.Contains($_)}|Sort-Object -Unique)
    $deletes|Set-Content (Join-Path $root 'removed-paths.txt')
    $deletes|Where-Object {$_ -match '^\\Windows\\WinSxS\\'}|Set-Content (Join-Path $root 'removed-component-paths.txt')
    foreach($critical in @('\Windows\Microsoft.NET','\Windows\assembly','\Windows\SysWOW64','\Windows\System32\WindowsPowerShell','\Windows\System32\DriverStore','\Windows\System32\oobe')) {
        if($critical -notin $paths){throw "Required runtime directory absent: $critical"}
        foreach($d in $deletes){if($critical -eq $d -or $critical.StartsWith($d+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Unsafe deletion of $critical"}}
    }
    Stage 'Extract private offline hives retaining original file security descriptors'
    $hives=Join-Path $root 'hives'
    New-Item -ItemType Directory -Path $hives -Force|Out-Null
    [void](Run $wim @('extract',$work,'1','\Windows\System32\config\SOFTWARE','\Windows\System32\config\SYSTEM','\Users\Default\NTUSER.DAT',"--dest-dir=$hives"))
    Get-ChildItem -LiteralPath $hives -File|ForEach-Object {$_.IsReadOnly=$false}
    Stage 'Clean app metadata and configure offline services, policies and task registration'
    $configArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File','C:\tiny11-work\Configure-LiteV3-Hives.ps1')
    if($ResumeRegistry){$configArgs+='-ReuseCleanHives'}
    [void](Run 'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe' $configArgs)
    if(-not(Test-Path (Join-Path $root 'registry-complete.txt'))){throw 'Offline registry configuration did not complete'}
    $commands=[Collections.Generic.List[string]]::new()
    foreach($d in $deletes){$commands.Add('delete --force --recursive "'+$d+'"')}
    $layoutTarget='\Users\Default\AppData\Local\Microsoft\Windows\Shell\DefaultLayouts.xml'
    if($pathSet.Contains($layoutTarget)) {
        $layoutDir=Join-Path $root 'layout';New-Item -ItemType Directory -Path $layoutDir -Force|Out-Null
        [void](Run $wim @('extract',$work,'1',$layoutTarget,"--dest-dir=$layoutDir"))
        $layoutFile=Join-Path $layoutDir 'DefaultLayouts.xml'
        (Get-Item -LiteralPath $layoutFile).IsReadOnly=$false
        [xml]$xml=Get-Content -LiteralPath $layoutFile -Raw
        $pattern='(?i)('+ (($identities|ForEach-Object {[regex]::Escape($_)+'_'}) -join '|') +')'
        $removedTiles=[Collections.Generic.List[string]]::new()
        foreach($node in @($xml.SelectNodes('//*[@AppUserModelID or @DesktopApplicationID or @DesktopApplicationLinkPath]'))) {
            $value=$node.OuterXml
            if($value -match $pattern -or $value -match '(?i)Microsoft\.MicrosoftEdge|Microsoft\.Office\.OneDrive|Microsoft\.(?:Teams|MSTeams)|\\Microsoft Edge\.lnk|\\OneDrive\.lnk') {
                $removedTiles.Add($value);[void]$node.ParentNode.RemoveChild($node)
            }
        }
        $xml.Save($layoutFile)
        $removedTiles|Set-Content (Join-Path $root 'removed-start-tiles.txt')
        $commands.Add('add "'+$layoutFile+'" "'+$layoutTarget+'"')
    }
    foreach($h in @('SOFTWARE','SYSTEM','NTUSER.DAT')) {
        $destination=Join-Path $hives $h
        $sddlBefore=(Get-Acl -LiteralPath $destination).Sddl
        # Write bytes into the already extracted file instead of replacing its ACL.
        [IO.File]::WriteAllBytes($destination,[IO.File]::ReadAllBytes($destination+'.final'))
        if((Get-Acl -LiteralPath $destination).Sddl -ne $sddlBefore){throw 'Hive file security descriptor changed'}
        $target=if($h -eq 'NTUSER.DAT'){'\Users\Default\NTUSER.DAT'}else{'\Windows\System32\config\'+$h}
        $commands.Add('add "'+$destination+'" "'+$target+'"')
        $deletesSidecars=@($paths|Where-Object {$_.StartsWith($target,[StringComparison]::OrdinalIgnoreCase) -and $_ -ne $target -and ($_ -match '\.(LOG[12]?|TM\.blf|regtrans-ms)(\.cnpf)?$')})
        foreach($s in $deletesSidecars){$commands.Add('delete --force "'+$s+'"')}
    }
    Stage 'Prune component payloads and selected apps, keeping CLR, WoW64, WebView2 and drivers'
    $commands|Set-Content (Join-Path $root 'wim-update-commands.txt')
    [void](Run $wim @('update',$work,'1','--check') (($commands -join "`n")+"`n"))
    Stage 'Export final install.wim with ordinary LZX compression'
    [void](Run $wim @('export',$work,'1',$output,'--compress=LZX','--check'))
    Stage 'Verify final WIM integrity and retained runtime files'
    [void](Run $wim @('verify',$output))
    $final=(Run $wim @('dir',$output,'1')) -split '\r?\n'
    $finalSet=[Collections.Generic.HashSet[string]]::new([string[]]$final,[StringComparer]::OrdinalIgnoreCase)
    $final|Set-Content (Join-Path $root 'paths-final.txt')
    $required=@('\Windows\Microsoft.NET\Framework64\v4.0.30319\clr.dll','\Windows\Microsoft.NET\Framework\v4.0.30319\clr.dll','\Windows\Microsoft.NET\Framework64\v4.0.30319\mscorlib.dll','\Windows\System32\mscoree.dll','\Windows\SysWOW64\mscoree.dll','\Windows\System32\WindowsPowerShell\v1.0\powershell.exe','\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe','\Windows\SysWOW64\kernel32.dll','\Windows\explorer.exe','\Windows\System32\cmd.exe','\Windows\System32\tzsync.exe')
    $automation=@($final|Where-Object {$_ -match '^\\Windows\\Microsoft.NET\\assembly\\GAC_MSIL\\System.Management.Automation\\[^\\]+\\System.Management.Automation.dll$'})
    if($automation.Count -ne 1){throw 'PowerShell automation assembly cannot be identified'}
    $required+=$automation[0]
    foreach($r in $required){if($r -notin $final){throw "Final image is missing required file: $r"}}
    $webview=@($final|Where-Object {$_ -match '\\msedgewebview2.exe$'})
    if($webview.Count -eq 0){throw 'Preserved WebView2 runtime executable is absent'}
    foreach($d in $deletes){if($finalSet.Contains($d)){throw "Removed path remains: $d"}}
    $check=Join-Path $root 'final-hive-check';New-Item -ItemType Directory -Path $check -Force|Out-Null
    [void](Run $wim @('extract',$output,'1','\Windows\System32\config\SOFTWARE','\Windows\System32\config\SYSTEM','\Users\Default\NTUSER.DAT',"--dest-dir=$check"))
    foreach($h in @('SOFTWARE','SYSTEM','NTUSER.DAT')) {
        if((Get-FileHash (Join-Path $check $h)).Hash -ne (Get-FileHash (Join-Path $hives $h)).Hash){throw "Final hive hash mismatch: $h"}
        if((Get-Acl (Join-Path $check $h)).Sddl -ne (Get-Acl (Join-Path $hives $h)).Sddl){throw "Final hive ACL mismatch: $h"}
    }
    $hash=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    $hash|Set-Content (Join-Path $root 'install.wim.sha256')
    $info=Run $wim @('info',$output)
    $info|Set-Content (Join-Path $root 'image-info.txt')
    if($info -notmatch 'Build:\s+26300' -or $info -notmatch 'Service Pack Build:\s+9818'){throw 'Final WIM build differs from requested build'}
    $protected=@(Get-Content (Join-Path $root 'apps-protected-retained.json') -Raw|ConvertFrom-Json)
    @{Output=$output;Build='26300.9818';Bytes=(Get-Item $output).Length;SHA256=$hash;Compression='LZX';RemovedProvisionedApps=$removedApps.Count;ProtectedAppsRetained=@($protected.Name);RemovedSystemApps=$systemRemove.Count;RemovedPayloadPaths=$deletes.Count;RequiredFilesChecked=$required.Count;WimIntegrityVerified=$true;EmbeddedHiveHashesVerified=$true;HiveAclsPreserved=$true;DotNetAndWow64Retained=$true;FirewallRetained=$true;WebView2Retained=$true;PostInstallWindowsUpdateEnabled=$false;Serviceable=$false;VmBootTestPerformed=$false;SourceIsoUnmodified=$true}|ConvertTo-Json|Set-Content (Join-Path $root 'report.json')
    Stage 'Complete: standalone install.wim ready'
} catch {
    $_|Out-String|Set-Content (Join-Path $root 'finish-error.txt')
    Stage ('FAILED: '+$_.Exception.Message)
    exit 1
}
