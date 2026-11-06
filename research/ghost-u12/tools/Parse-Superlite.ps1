param([string]$SourcePath='C:\tiny11-work\ghost-u12-audit\payload-index-3\C\Windows\System32\oobe.cmd',[string]$OutputPrefix='')
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$source=$SourcePath
$main=([IO.Path]::GetFileName($source) -eq 'oobe.cmd')
function OutFile([string]$name){Join-Path $root ($OutputPrefix+$name)}
$lines=[IO.File]::ReadAllLines($source)
$rows=[Collections.Generic.List[object]]::new()
$excluded=[Collections.Generic.List[object]]::new()
$addPattern='(?i)^\s*@?reg(?:\.exe)?\s+(add|delete)\s+(?:"([^"]+)"|(\S+))(.*)$'
for($i=0;$i -lt $lines.Length;$i++){
 $line=$lines[$i];$n=$i+1
 if($line -match '^\s*(::|REM(?:\s|$))'){continue}
 if($main -and $n -ge 648){if($line -match $addPattern){$excluded.Add([pscustomobject]@{Line=$n;Reason='After unconditional exit /b on line 647';Command=$line})};continue}
 if(($main -and $n -ge 337 -and $n -le 345) -or (-not $main -and $n -ge 132 -and $n -le 136)){if($line -match $addPattern){$excluded.Add([pscustomobject]@{Line=$n;Reason='SUPERLITE SE branch, not the SUPERLITE profile';Command=$line})};continue}
 if($line -notmatch $addPattern){continue}
 $operation=$matches[1].ToLowerInvariant();$key=$matches[2];if(-not $key){$key=$matches[3]};$rest=$matches[4]
 $key=$key -replace '^HKEY_LOCAL_MACHINE\\','HKLM\' -replace '^HKEY_CURRENT_USER\\','HKCU\' -replace '^HKEY_USERS\\','HKU\'
 $name=$null;$type=$null;$value=$null
 if($rest -match '(?i)(?:^|\s)/v\s+(?:"([^"]+)"|(\S+))'){$name=$matches[1];if(-not $name){$name=$matches[2]}}
 elseif($rest -match '(?i)(?:^|\s)/ve(?:\s|$)'){$name=''}
 if($rest -match '(?i)(?:^|\s)/t\s+(REG_\w+)'){$type=$matches[1].ToUpperInvariant()}
 if($rest -match '(?i)(?:^|\s)/d\s+(?:"([^"]*)"|([^\s>&]+))'){$value=$matches[1];if($null -eq $value -or ($value -eq '' -and $matches[2])){$value=$matches[2]}}
 if($operation -eq 'add' -and $null -eq $name){$operation='create-key'}
 if($operation -eq 'delete' -and $null -eq $name){$operation='delete-key'}
 $conditional='';if($main -and $n -ge 27 -and $n -le 28){$conditional='Only if MRT value absent'};if($main -and $n -eq 580){$conditional='Only if GhostSpectre registry query contains DEF'}
 $rows.Add([pscustomobject]@{Line=$n;Operation=$operation;Key=$key;Name=$name;Type=$type;Value=$value;Conditional=$conditional;ShadowedByLine=$null;Command=$line})
}
$last=@{}
foreach($row in $rows){if($row.Operation -in @('add','delete')){$identity=$row.Key.ToUpperInvariant()+"`t"+$row.Name.ToUpperInvariant();if($last.ContainsKey($identity)){$last[$identity].ShadowedByLine=$row.Line};$last[$identity]=$row}}
$rows|ConvertTo-Json -Depth 5|Set-Content (OutFile 'registry-operations.json')
$rows|Export-Csv (OutFile 'registry-operations.csv') -NoTypeInformation
$excluded|ConvertTo-Json|Set-Content (OutFile 'excluded-operations.json')
$services=@($rows|Where-Object {$_.Operation -eq 'add' -and $_.Name -eq 'Start' -and $_.Key -match '^HKLM\\SYSTEM\\CurrentControlSet\\Services\\([^\\]+)$'}|ForEach-Object {[pscustomobject]@{Name=($_.Key -split '\\')[-1];TargetStart=[int]$_.Value;Line=$_.Line;ShadowedByLine=$_.ShadowedByLine}})
$services|ConvertTo-Json|Set-Content (OutFile 'service-operations.json')
$services|Where-Object {$null -eq $_.ShadowedByLine}|Export-Csv (OutFile 'service-targets.csv') -NoTypeInformation
@{TotalSourceLines=$lines.Length;ParsedRegistryOperations=$rows.Count;ExcludedConditionalOrUnreachableOperations=$excluded.Count;FinalValueOperations=@($rows|Where-Object {$_.Operation -in @('add','delete') -and $null -eq $_.ShadowedByLine}).Count;ShadowedOperations=@($rows|Where-Object {$null -ne $_.ShadowedByLine}).Count;UniqueServiceTargets=@($services|Where-Object {$null -eq $_.ShadowedByLine}).Count;SourceExecuted=$false;Scope='Static analysis for SUPERLITE profile, assuming earlier commands continue; external helpers may change final runtime state'}|ConvertTo-Json|Set-Content (OutFile 'parse-summary.json')
