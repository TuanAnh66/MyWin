param([switch]$ReuseCleanHives)
$ErrorActionPreference='Stop'
$root='C:\tiny11-work\lite-v3'
$hives=Join-Path $root 'hives'
Add-Type -Path C:\tiny11-work\LiteV3Registry.cs
Add-Type -Path C:\tiny11-work\app-metadata-cleanup\OfflineAppMetadata.cs
$identities=[string[]](Get-Content (Join-Path $root 'removed-app-identities.txt'))
$audit=[Collections.Generic.List[string]]::new()
foreach($name in @('SOFTWARE','NTUSER.DAT')) {
    $source=Join-Path $hives $name
    $clean=$source+'.appclean'
    if($ReuseCleanHives){if(-not(Test-Path -LiteralPath $clean)){throw 'Prior cleaned hive missing'};continue}
    $hits=[OfflineAppMetadata]::Process($source,$clean,$identities,$true)
    $hits | Set-Content (Join-Path $root ($name+'-removed-app-metadata.txt'))
    if(-not(Test-Path -LiteralPath $clean)){Copy-Item -LiteralPath $source -Destination $clean}
    $remaining=[OfflineAppMetadata]::Process($clean,'',$identities,$false)
    if($remaining.Count){throw "$name retains removed app identity metadata"}
}
$sys=[LiteV3Registry]::new((Join-Path $hives 'SYSTEM'))
$soft=[LiteV3Registry]::new((Join-Path $hives 'SOFTWARE.appclean'))
$user=[LiteV3Registry]::new((Join-Path $hives 'NTUSER.DAT.appclean'))
try {
    if($soft.Text('Microsoft\Windows NT\CurrentVersion','CurrentBuildNumber') -ne '26300' -or $soft.Dword('Microsoft\Windows NT\CurrentVersion','UBR',0) -ne 9818){throw 'Unexpected source build in SOFTWARE hive'}
    $disabled=@('wuauserv','UsoSvc','WaaSMedicSvc','DoSvc','DiagTrack','dmwappushservice','WSearch','MapsBroker','PhoneSvc','lfsvc','WerSvc','WMPNetworkSvc','RetailDemo','RemoteRegistry','XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc','WinDefend','WdNisSvc','WdNisDrv','WdFilter','Sense','SecurityHealthService','edgeupdate','edgeupdatem')
    foreach($control in @($sys.Children('') | Where-Object {$_ -match '^ControlSet\d{3}$'})) {
        foreach($service in $sys.Children(($control+'\Services'))) {
            if($service -in $disabled -or $service -match '^(OneSyncSvc|PimIndexMaintenanceSvc|UnistoreSvc|UserDataSvc|MessagingService)(_|$)') {
                $key=$control+'\Services\'+$service
                $before=$sys.Dword($key,'Start',-1)
                $sys.SetDword($key,'Start',4)
                if($sys.Exists($key+'\StartOverride')){$sys.DeleteTree($key+'\StartOverride')}
                $audit.Add("SERVICE`t$service`t$before -> 4")
            }
        }
        foreach($service in @('BFE','MpsSvc','Dhcp','Dnscache','RpcSs','DcomLaunch','EventLog','Schedule','Winmgmt','AppXSvc','ClipSVC','StateRepository')) {
            $key=$control+'\Services\'+$service
            if(-not $sys.Exists($key)){throw "Essential service missing: $service"}
            if($sys.Dword($key,'Start',4) -eq 4){throw "Essential service disabled: $service"}
            $audit.Add("PRESERVED_SERVICE`t$service`t$($sys.Dword($key,'Start',-1))")
        }
        $sys.SetDword($control+'\Control\BitLocker','PreventDeviceEncryption',1)
        $sys.SetDword($control+'\Control\Power','HibernateEnabled',0)
    }
    foreach($n in @('BypassTPMCheck','BypassCPUCheck','BypassRAMCheck','BypassSecureBootCheck','BypassStorageCheck')){$sys.SetDword('Setup\LabConfig',$n,1)}
    $sys.SetDword('Setup\MoSetup','AllowUpgradesWithUnsupportedTPMOrCPU',1)
    $policies=@(
        @('Policies\Microsoft\Windows\WindowsUpdate\AU','NoAutoUpdate',1),
        @('Policies\Microsoft\Windows\WindowsUpdate','DisableWindowsUpdateAccess',1),
        @('Policies\Microsoft\Windows Defender','DisableAntiSpyware',1),
        @('Policies\Microsoft\Windows Defender\Real-Time Protection','DisableRealtimeMonitoring',1),
        @('Policies\Microsoft\Windows\CloudContent','DisableWindowsConsumerFeatures',1),
        @('Policies\Microsoft\Windows\CloudContent','DisableCloudOptimizedContent',1),
        @('Policies\Microsoft\Windows\WindowsCopilot','TurnOffWindowsCopilot',1),
        @('Policies\Microsoft\Windows\WindowsAI','DisableAIDataAnalysis',1),
        @('Policies\Microsoft\Dsh','AllowNewsAndInterests',0),
        @('Policies\Microsoft\Windows\DataCollection','AllowTelemetry',0),
        @('Policies\Microsoft\Windows\Windows Search','AllowCortana',0),
        @('Policies\Microsoft\Windows\Windows Search','AllowCloudSearch',0),
        @('Policies\Microsoft\Windows\OneDrive','DisableFileSyncNGSC',1),
        @('Policies\Microsoft\Windows\OOBE','DisablePrivacyExperience',1),
        @('Microsoft\Windows\CurrentVersion\ReserveManager','ShippedWithReserves',0)
    )
    foreach($p in $policies){$soft.SetDword($p[0],$p[1],[int]$p[2]);$audit.Add("POLICY`t$($p[0])\$($p[1]) = $($p[2])")}
    $soft.SetText('Policies\Microsoft\Windows\Explorer','ConfigureStartPins','{"pinnedList":[]}')
    foreach($base in @('Microsoft\Windows\CurrentVersion','WOW6432Node\Microsoft\Windows\CurrentVersion')) {
        foreach($n in @('SecurityHealth','WindowsDefender','OneDriveSetup','MicrosoftEdgeAutoLaunch')){$soft.DeleteValue($base+'\Run',$n)}
        foreach($n in $soft.Children($base+'\Uninstall')) {
            $entry=$base+'\Uninstall\'+$n
            $display=$soft.Text($entry,'DisplayName')
            if($display -in @('Microsoft Edge','Microsoft Edge Update')){$soft.DeleteTree($entry);$audit.Add("UNINSTALL_ENTRY`t$entry")}
        }
    }
    $taskRoot='Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache'
    $taskFolders=[string[]](Get-Content (Join-Path $root 'removed-task-folders.txt'))
    function RemoveTaskNode([string]$path) {
        foreach($child in $soft.Children($path)){RemoveTaskNode ($path+'\'+$child)}
        $id=$soft.Text($path,'Id')
        if($id -match '^\{[0-9A-Fa-f-]+\}$') {
            foreach($bucket in @('Tasks','Plain','Logon','Boot','Maintenance')){$soft.DeleteTree($taskRoot+'\'+$bucket+'\'+$id)}
            $audit.Add("TASK`t$path`t$id")
        }
    }
    foreach($folder in $taskFolders) {
        $path=$taskRoot+'\Tree\Microsoft\Windows\'+$folder
        RemoveTaskNode $path
        $soft.DeleteTree($path)
    }
    $user.SetDword('Software\Microsoft\Windows\CurrentVersion\Search','SearchboxTaskbarMode',0)
    $user.SetDword('Software\Policies\Microsoft\Windows\Explorer','DisableSearchBoxSuggestions',1)
    $user.SetDword('Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced','TaskbarDa',0)
    $user.SetDword('Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced','ShowCopilotButton',0)
    $user.SetDword('Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement','ScoobeSystemSettingEnabled',0)
    foreach($key in @('Software\Microsoft\Windows\CurrentVersion\Run','Software\Microsoft\Windows\CurrentVersion\RunOnce')) {
        foreach($name in @('OneDrive','OneDriveSetup')){$user.DeleteValue($key,$name)}
    }
    foreach($n in @('ContentDeliveryAllowed','OemPreInstalledAppsEnabled','PreInstalledAppsEnabled','SilentInstalledAppsEnabled','SoftLandingEnabled','SubscribedContentEnabled','SystemPaneSuggestionsEnabled')) {
        $user.SetDword('Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',$n,0)
    }
    $sys.Save((Join-Path $hives 'SYSTEM.final'))
    $soft.Save((Join-Path $hives 'SOFTWARE.final'))
    $user.Save((Join-Path $hives 'NTUSER.DAT.final'))
} finally {$sys.Dispose();$soft.Dispose();$user.Dispose()}
$audit | Set-Content (Join-Path $root 'registry-changes.txt')
foreach($hive in @('SOFTWARE','NTUSER.DAT')) {
    $remaining=[OfflineAppMetadata]::Process((Join-Path $hives ($hive+'.final')),'',$identities,$false)
    if($remaining.Count){throw 'Removed app references reappeared'}
}
'OK' | Set-Content (Join-Path $root 'registry-complete.txt')
