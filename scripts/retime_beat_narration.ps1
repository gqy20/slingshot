[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Episode,
    [Parameter(Mandatory = $true)][string]$SourceAudio,
    [Parameter(Mandatory = $true)][string]$SourceSrt,
    [Parameter(Mandatory = $true)][string]$SourceManifest
)

. (Join-Path $PSScriptRoot 'common.ps1')
$ffmpeg = Find-SlingshotTool -Name 'ffmpeg'
$ffprobe = Find-SlingshotTool -Name 'ffprobe'
$episodePath = (Resolve-Path -LiteralPath $Episode).Path
$sourceAudioPath = (Resolve-Path -LiteralPath $SourceAudio).Path
$sourceSrtPath = (Resolve-Path -LiteralPath $SourceSrt).Path
$sourceManifestPath = (Resolve-Path -LiteralPath $SourceManifest).Path
$config = Get-Content -LiteralPath $episodePath -Raw -Encoding UTF8 | ConvertFrom-Json
$paths = Get-SlingshotEpisodePaths -EpisodeId ([string]$config.id)
$beats = @($config.beats)
$sourceValues = @{}
foreach ($line in Get-Content -LiteralPath $sourceManifestPath -Encoding UTF8) {
    if ($line -match '^([^=]+)=(.*)$') { $sourceValues[$Matches[1]] = $Matches[2] }
}
if ($sourceValues['timing_mode'] -ne 'beats') { throw 'Source narration is not beat-timed' }
$culture = [System.Globalization.CultureInfo]::InvariantCulture
$oldStarts = @()
$oldSlots = @()
$speechLengths = @()
$oldCursor = 0.0
$newCursor = 0.0
foreach ($beat in $beats) {
    $id = [string]$beat.id
    $speechKey = "beat_${id}_speech_sec"
    $slotKey = "beat_${id}_slot_sec"
    if (-not $sourceValues.ContainsKey($speechKey) -or -not $sourceValues.ContainsKey($slotKey)) {
        throw "Missing source timing for $id"
    }
    $speech = [double]::Parse($sourceValues[$speechKey], $culture)
    $oldSlot = [double]::Parse($sourceValues[$slotKey], $culture)
    $newSlot = [double]$beat.duration
    if ([Math]::Abs([double]$beat.at - $newCursor) -gt 0.001) {
        throw "Non-contiguous episode timeline before $id"
    }
    if ($newSlot - $speech -lt 0.15) {
        throw "Beat $id has less than 0.15 seconds after the source speech"
    }
    if ($id -notin @('science-close', 'brand-gate') -and $newSlot - $speech -gt 1.0) {
        throw "Beat $id has more than one second after the source speech"
    }
    $oldStarts += $oldCursor
    $oldSlots += $oldSlot
    $speechLengths += $speech
    $oldCursor += $oldSlot
    $newCursor += $newSlot
}
if ([Math]::Abs($newCursor - (Get-SlingshotEpisodeDuration $config)) -gt 0.001) {
    throw 'Beat duration and story duration do not match'
}

function ConvertFrom-SrtStamp([string]$Stamp) {
    if ($Stamp -notmatch '^(\d{2}):(\d{2}):(\d{2}),(\d{3})$') { throw "Invalid SRT stamp: $Stamp" }
    return [int64]((([int64]$Matches[1] * 60 + [int64]$Matches[2]) * 60 + [int64]$Matches[3]) * 1000 + [int64]$Matches[4])
}

function ConvertTo-SrtStamp([int64]$Milliseconds) {
    $hours = [Math]::Floor($Milliseconds / 3600000)
    $minutes = [Math]::Floor(($Milliseconds % 3600000) / 60000)
    $seconds = [Math]::Floor(($Milliseconds % 60000) / 1000)
    $millis = $Milliseconds % 1000
    return '{0:00}:{1:00}:{2:00},{3:000}' -f $hours, $minutes, $seconds, $millis
}

$srtSource = Get-Content -LiteralPath $sourceSrtPath -Raw -Encoding UTF8
$cuePattern = '(?ms)^\s*\d+\s*\r?\n(?<start>\d{2}:\d{2}:\d{2},\d{3})\s+-->\s+(?<end>\d{2}:\d{2}:\d{2},\d{3})[^\r\n]*\r?\n(?<text>.*?)(?=\r?\n\r?\n|\z)'
$cueMatches = [regex]::Matches($srtSource, $cuePattern)
if ($cueMatches.Count -eq 0) { throw 'Source SRT contains no cues' }
$retimedCues = New-Object System.Collections.Generic.List[string]
foreach ($cue in $cueMatches) {
    $cueStart = ConvertFrom-SrtStamp $cue.Groups['start'].Value
    $cueEnd = ConvertFrom-SrtStamp $cue.Groups['end'].Value
    $beatIndex = -1
    for ($index = 0; $index -lt $beats.Count; $index++) {
        $oldStartMs = [int64][Math]::Round($oldStarts[$index] * 1000)
        $oldEndMs = [int64][Math]::Round(($oldStarts[$index] + $oldSlots[$index]) * 1000)
        if ($cueStart -ge $oldStartMs -and $cueStart -lt $oldEndMs) {
            $beatIndex = $index
            break
        }
    }
    if ($beatIndex -lt 0) { throw "SRT cue at $cueStart ms has no source beat" }
    $offsetMs = [int64][Math]::Round(([double]$beats[$beatIndex].at - $oldStarts[$beatIndex]) * 1000)
    $newStart = $cueStart + $offsetMs
    $newEnd = $cueEnd + $offsetMs
    $beatEndMs = [int64][Math]::Round(([double]$beats[$beatIndex].at + [double]$beats[$beatIndex].duration) * 1000)
    if ($newEnd -gt $beatEndMs) { throw "Retimed SRT cue crosses beat $($beats[$beatIndex].id)" }
    $retimedCues.Add(('{0}' -f ($retimedCues.Count + 1)) + "`n" +
        (ConvertTo-SrtStamp $newStart) + ' --> ' + (ConvertTo-SrtStamp $newEnd) + "`n" +
        $cue.Groups['text'].Value.Trim())
}

$tempDir = New-SlingshotRenderTempDirectory -Kind 'narration-retime' -EpisodeId ([string]$config.id)
try {
    $raw = Join-Path $tempDir 'narration-retimed-raw.wav'
    $normalized = Join-Path $tempDir 'narration-normalized.wav'
    $mp3 = Join-Path $tempDir 'narration.mp3'
    $srt = Join-Path $tempDir 'narration.srt'
    $branchNames = @()
    $segmentFilters = @()
    $segmentNames = @()
    for ($index = 0; $index -lt $beats.Count; $index++) {
        $branchNames += "[branch$index]"
        $segmentNames += "[segment$index]"
        $oldStart = $oldStarts[$index].ToString('0.###', $culture)
        $speech = $speechLengths[$index].ToString('0.###', $culture)
        $newSlot = ([double]$beats[$index].duration).ToString('0.###', $culture)
        [double]$sourceLength = if ($speechLengths[$index] -gt 0.0) { $speechLengths[$index] } else { $oldSlots[$index] }
        $sourceLengthText = $sourceLength.ToString('0.###', $culture)
        $muteFilter = if ($speechLengths[$index] -gt 0.0) { '' } else { ',volume=0' }
        $segmentFilters += "[branch$index]atrim=start=${oldStart}:duration=${sourceLengthText},asetpts=PTS-STARTPTS${muteFilter},apad,atrim=duration=${newSlot},asetpts=PTS-STARTPTS[segment$index]"
    }
    $filter = '[0:a]asplit=' + $beats.Count + ($branchNames -join '') + ';' +
        ($segmentFilters -join ';') + ';' + ($segmentNames -join '') +
        'concat=n=' + $beats.Count + ':v=0:a=1[out]'
    & $ffmpeg -y -loglevel error -i $sourceAudioPath -filter_complex $filter -map '[out]' `
        -ar 48000 -ac 1 -c:a pcm_s24le $raw
    if ($LASTEXITCODE -ne 0) { throw 'Failed to retime narration audio' }
    & $ffmpeg -y -loglevel error -i $raw -af 'loudnorm=I=-16:TP=-1.5:LRA=7' `
        -ar 48000 -ac 1 -c:a pcm_s24le $normalized
    if ($LASTEXITCODE -ne 0) { throw 'Failed to normalize retimed narration' }
    & $ffmpeg -y -loglevel error -i $normalized -ar 48000 -ac 1 -c:a libmp3lame -b:a 192k $mp3
    if ($LASTEXITCODE -ne 0) { throw 'Failed to encode retimed narration MP3' }
    Write-SlingshotUtf8 $srt (($retimedCues -join "`n`n") + "`n")
    $actualDuration = [double]((& $ffprobe -v error -show_entries format=duration `
        -of default=nw=1:nk=1 $normalized).Trim())
    if ([Math]::Abs($actualDuration - $newCursor) -gt 0.005) {
        throw "Retimed audio is $actualDuration seconds; expected $newCursor"
    }
    $silenceOutput = & $ffmpeg -hide_banner -loglevel info -i $normalized `
        -af 'silencedetect=noise=-38dB:d=1.0' -f null NUL 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Failed to inspect retimed narration silence' }
    $outroAt = [double]$config.story.brand.outro_at_sec
    $silentBrand = @($beats | Where-Object { [string]$_.id -eq 'brand-gate' })
    $brandStart = if ($silentBrand.Count -gt 0) { [double]$silentBrand[0].at } else { -1.0 }
    $brandEnd = if ($silentBrand.Count -gt 0) { $brandStart + [double]$silentBrand[0].duration } else { -1.0 }
    foreach ($entry in $silenceOutput) {
        if ([string]$entry -match 'silence_start:\s*([0-9.]+)') {
            $silenceStart = [double]::Parse($Matches[1], $culture)
            $isBrandBreath = $brandStart -ge 0.0 -and $silenceStart -ge $brandStart - 1.0 -and $silenceStart -le $brandEnd
            if ($silenceStart -lt $outroAt - 1.0 -and -not $isBrandBreath) {
                throw "Narration contains at least one second of silence starting at $silenceStart s"
            }
        }
    }
    New-Item -ItemType Directory -Force -Path $paths.MasterAudio | Out-Null
    $narrationScript = Join-Path $script:ProjectRoot ([string]$config.narration.script).Substring(6).Replace('/', '\')
    $manifestLines = @(
        "episode=$([IO.Path]::GetFileName($episodePath))",
        "episode_sha256=$(Get-SlingshotSha256 $episodePath)",
        "script_sha256=$(Get-SlingshotSha256 $narrationScript)",
        "source_audio_sha256=$(Get-SlingshotSha256 $mp3)",
        "normalized_audio_sha256=$(Get-SlingshotSha256 $normalized)",
        "subtitles_sha256=$(Get-SlingshotSha256 $srt)",
        "audio_duration_sec=$actualDuration",
        "video_duration_sec=$newCursor",
        'timing_mode=beats',
        "model=$($sourceValues['model'])",
        "voice=$($sourceValues['voice'])",
        "language=$($sourceValues['language'])",
        "speed=$($sourceValues['speed'])",
        "volume=$($sourceValues['volume'])",
        "pitch=$($sourceValues['pitch'])",
        "mmx_cli=$($sourceValues['mmx_cli'])",
        'audio_standard=-16_LUFS_-1.5_dBTP_48kHz_mono_PCM24',
        "retimed_from_sha256=$(Get-SlingshotSha256 $sourceAudioPath)"
    )
    for ($index = 0; $index -lt $beats.Count; $index++) {
        $id = [string]$beats[$index].id
        $manifestLines += "beat_${id}_speech_sec=$($speechLengths[$index].ToString('0.###', $culture))"
        $manifestLines += "beat_${id}_slot_sec=$(([double]$beats[$index].duration).ToString('0.###', $culture))"
    }
    $manifest = Join-Path $paths.MasterAudio 'narration.manifest.txt'
    Copy-Item -LiteralPath $normalized -Destination (Join-Path $paths.MasterAudio 'narration-normalized.wav') -Force
    Copy-Item -LiteralPath $mp3 -Destination (Join-Path $paths.MasterAudio 'narration.mp3') -Force
    Copy-Item -LiteralPath $srt -Destination (Join-Path $paths.MasterAudio 'narration.srt') -Force
    $editorialSrt = Join-Path $script:ProjectRoot ([string]$config.narration.subtitle_script).Substring(6).Replace('/', '\')
    Copy-Item -LiteralPath $srt -Destination $editorialSrt -Force
    Write-SlingshotUtf8 $manifest (($manifestLines -join "`n") + "`n")
    Write-Host "narration-retime: $($config.id) duration=${actualDuration}s cues=$($retimedCues.Count)"
} finally {
    $resolvedTemp = [IO.Path]::GetFullPath($tempDir)
    $resolvedCache = [IO.Path]::GetFullPath((Join-Path $script:RenderCacheRoot 'tmp'))
    if ($resolvedTemp.StartsWith($resolvedCache + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}
