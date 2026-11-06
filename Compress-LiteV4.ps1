param([string]$Root='C:\tiny11-work\lite-v4',[string]$ImageLabel='v4',[string]$SeedEsd='')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($Root)
$source=Join-Path $root 'install.wim'
$partial=Join-Path $root 'install.partial.esd'
$output=Join-Path $root 'install.esd'
$wim='C:\26300.9818\bin\wimlib-imagex.exe'
$started=Get-Date
function Stage($name){@{Stage=$name;Updated=(Get-Date).ToString('o');Source=$source;Output=$output;Started=$started.ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $root 'esd-status.json')}
function Native([string[]]$toolArgs,[string]$label){
    & $wim @toolArgs *> (Join-Path $root ($label+'.log'))
    if($LASTEXITCODE -ne 0){throw "$label failed ($LASTEXITCODE); see $label.log"}
}
try {
    if((Test-Path -LiteralPath $partial) -or (Test-Path -LiteralPath $output)){throw 'An ESD output or incomplete compression already exists; refusing to overwrite'}
    Stage "Verify original $ImageLabel WIM before lossless recompression"
    $baseline=Get-Content (Join-Path $root 'report.json') -Raw|ConvertFrom-Json
    $sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if($sourceHash -ne $baseline.SHA256){throw 'V4 WIM hash differs from the verified build report'}
    $seedHash=$null
    if($SeedEsd) {
        Stage 'Verify existing compressed v4 seed and copy it without modifying the original'
        $SeedEsd=[IO.Path]::GetFullPath($SeedEsd)
        if($SeedEsd -eq $output -or $SeedEsd -eq $partial){throw 'Seed ESD must be a different file'}
        $seedReport=Get-Content (Join-Path (Split-Path $SeedEsd -Parent) 'esd-report.json') -Raw|ConvertFrom-Json
        $seedHash=(Get-FileHash -LiteralPath $SeedEsd).Hash
        if($seedHash -ne $seedReport.OutputSHA256){throw 'Compressed seed hash differs from its verified report'}
        Copy-Item -LiteralPath $SeedEsd -Destination $partial
        Stage "Append $ImageLabel using existing compressed blobs; compress only changed data"
        Native @('export',$source,'1',$partial,'Windows 11 Pro VirtIO staging','--compress=LZMS','--solid','--solid-chunk-size=16M','--threads=8','--check') 'esd-compress'
        Stage 'Remove the old seed image from the private copy and retain only the VirtIO image'
        Native @('delete',$partial,'1','--check') 'esd-remove-seed-image'
        Native @('info',$partial,'1','Windows 11 Pro','--check') 'esd-restore-image-name'
    }else {
        Stage "Compress $ImageLabel to a separate solid LZMS ESD with 8 threads"
        Native @('export',$source,'1',$partial,'--compress=LZMS','--solid','--solid-chunk-size=16M','--threads=8','--check') 'esd-compress'
    }
    Stage 'Verify every file in the completed ESD'
    Native @('verify',$partial) 'esd-verify'
    Stage 'Compare image identity and file paths; verify original WIM stayed unchanged'
    Native @('info',$source) 'esd-source-info'
    Native @('info',$partial) 'esd-output-info'
    $srcInfo=Get-Content (Join-Path $root 'esd-source-info.log') -Raw
    $dstInfo=Get-Content (Join-Path $root 'esd-output-info.log') -Raw
    foreach($field in @('Image Count','Directory Count','File Count','Total Bytes','Hard Link Bytes','Architecture','Edition ID','Build','Service Pack Build')) {
        $pattern='(?m)^'+[regex]::Escape($field)+':\s*([^\r\n]+)'
        $a=[regex]::Match($srcInfo,$pattern).Groups[1].Value.Trim()
        $b=[regex]::Match($dstInfo,$pattern).Groups[1].Value.Trim()
        if(-not $a -or $a -ne $b){throw "Image metadata differs: $field ($a vs $b)"}
    }
    Native @('dir',$partial,'1') 'esd-paths'
    $expected=@(Get-Content (Join-Path $root 'paths-final.txt')|Where-Object {$_ -match '^\\'})
    $actual=@(Get-Content (Join-Path $root 'esd-paths.log')|Where-Object {$_ -match '^\\'})
    $set=[Collections.Generic.HashSet[string]]::new([string[]]$expected,[StringComparer]::Ordinal)
    if(-not $set.SetEquals([string[]]$actual)){throw 'File paths differ after recompression'}
    $sourceHashAfter=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if($sourceHashAfter -ne $sourceHash){throw 'Original WIM hash changed'}
    if($SeedEsd -and (Get-FileHash -LiteralPath $SeedEsd).Hash -ne $seedHash){throw 'Original seed ESD changed'}
    $esdHash=(Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash
    Move-Item -LiteralPath $partial -Destination $output
    $esdHash|Set-Content (Join-Path $root 'install.esd.sha256')
    $sourceBytes=(Get-Item -LiteralPath $source).Length
    $outputBytes=(Get-Item -LiteralPath $output).Length
    $compressionLog=Get-Content (Join-Path $root 'esd-compress.log') -Raw
    $actualThreads=[int][regex]::Match($compressionLog,'Using LZMS compression with (\d+) threads').Groups[1].Value
    @{Source=$source;Output=$output;Build='26300.9818';Compression='Solid LZMS';RequestedThreads=8;ActualThreads=$actualThreads;SolidChunkBytes=16777216;SeedEsd=$SeedEsd;SeedSHA256=$seedHash;SeedPreserved=[bool]$SeedEsd;CompressedDataReused=[bool]$SeedEsd;SourceBytes=$sourceBytes;OutputBytes=$outputBytes;SavedBytes=($sourceBytes-$outputBytes);SavedPercent=[math]::Round(100*(1-$outputBytes/$sourceBytes),2);SourceSHA256=$sourceHashAfter;OutputSHA256=$esdHash;WimPreserved=$true;EsdIntegrityVerified=$true;ImageMetadataMatches=$true;FilePathsMatch=$true;ElapsedMinutes=[math]::Round(((Get-Date)-$started).TotalMinutes,2)}|ConvertTo-Json|Set-Content (Join-Path $root 'esd-report.json')
    Stage 'Complete: install.esd verified; original install.wim unchanged'
}catch {
    $_|Out-String|Set-Content (Join-Path $root 'esd-error.txt')
    Stage ('FAILED: '+$_.Exception.Message)
    exit 1
}
