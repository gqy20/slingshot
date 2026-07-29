[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Episode
)

. (Join-Path $PSScriptRoot 'common.ps1')
$ffmpeg = Find-SlingshotTool -Name 'ffmpeg'
$ffprobe = Find-SlingshotTool -Name 'ffprobe'

$episodePath = (Resolve-Path -LiteralPath $Episode).Path
$config = Get-Content -Raw -Encoding UTF8 $episodePath | ConvertFrom-Json
if ([string]$config.id -ne 's01e04-impact-force-curve') {
    throw 'This alignment map currently supports s01e04-impact-force-curve only.'
}

$scriptRelative = ([string]$config.narration.script).Substring('res://'.Length).Replace('/', '\')
$textPath = Join-Path $script:ProjectRoot $scriptRelative
$episodePaths = Get-SlingshotEpisodePaths ([string]$config.id)
$outputDir = $episodePaths.MasterAudio
$audioPath = Join-Path $outputDir 'narration.mp3'
$generatedSrtPath = Join-Path $outputDir 'narration.srt'
$alignedSrtPath = Join-Path $outputDir 'narration-aligned.srt'
$alignedPath = Join-Path $outputDir 'narration-normalized.wav'
$manifestPath = Join-Path $outputDir 'narration.manifest.txt'
$editorialSubtitleRelative = ([string]$config.narration.subtitle_script).Substring('res://'.Length).Replace('/', '\')
$editorialSubtitlePath = Join-Path $script:ProjectRoot $editorialSubtitleRelative

foreach ($required in @($textPath, $audioPath, $generatedSrtPath)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Missing narration input: $required" }
}

$targetWindows = @(
    @(0.0, 14.0), @(16.0, 20.0), @(20.0, 33.0), @(33.0, 49.0),
    @(49.0, 64.0), @(64.0, 77.0), @(77.0, 89.0), @(89.0, 104.0),
    @(104.0, 127.0), @(127.0, 142.0), @(142.0, 152.0), @(152.0, 168.0),
    @(168.0, 185.0), @(185.0, 200.0), @(200.0, 220.0)
)

function ConvertTo-CanonicalNarrationText([string]$Text) {
    $withoutPauses = [regex]::Replace($Text, '<#\d+(?:\.\d+)?#>', '')
    return [regex]::Replace($withoutPauses, '[^\p{L}\p{N}]', '').ToLowerInvariant()
}

function ConvertFrom-SrtTime([string]$Text) {
    if ($Text -notmatch '^(\d{2}):(\d{2}):(\d{2}),(\d{3})$') { throw "Invalid SRT timestamp: $Text" }
    return [double]$Matches[1] * 3600.0 + [double]$Matches[2] * 60.0 +
        [double]$Matches[3] + [double]$Matches[4] / 1000.0
}

function ConvertTo-SrtTime([double]$Seconds) {
    $totalMilliseconds = [int64][math]::Round([math]::Max(0.0, $Seconds) * 1000.0)
    $milliseconds = $totalMilliseconds % 1000
    $totalSeconds = [int64][math]::Floor($totalMilliseconds / 1000.0)
    $secondsPart = $totalSeconds % 60
    $totalMinutes = [int64][math]::Floor($totalSeconds / 60.0)
    $minutesPart = $totalMinutes % 60
    $hoursPart = [int64][math]::Floor($totalMinutes / 60.0)
    return '{0:D2}:{1:D2}:{2:D2},{3:D3}' -f $hoursPart, $minutesPart, $secondsPart, $milliseconds
}

$paragraphs = @((Get-Content -Raw -Encoding UTF8 $textPath) -split '(?:\r?\n){2,}' |
    ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($paragraphs.Count -ne $targetWindows.Count) {
    throw "Expected $($targetWindows.Count) narration paragraphs, found $($paragraphs.Count)."
}

$srtRaw = Get-Content -Raw -Encoding UTF8 $generatedSrtPath
$matches = [regex]::Matches(
    $srtRaw,
    '(?ms)^\s*(\d+)\r?\n(\d{2}:\d{2}:\d{2},\d{3})\s+-->\s+(\d{2}:\d{2}:\d{2},\d{3})\r?\n(.*?)(?=\r?\n\r?\n|\z)'
)
$cues = @($matches | ForEach-Object {
    [pscustomobject]@{
        Start = ConvertFrom-SrtTime $_.Groups[2].Value
        End = ConvertFrom-SrtTime $_.Groups[3].Value
        Text = $_.Groups[4].Value.Trim()
        Canonical = ConvertTo-CanonicalNarrationText $_.Groups[4].Value
    }
})
if ($cues.Count -eq 0) { throw "No cues parsed from $generatedSrtPath" }

$segments = @()
$cueIndex = 0
for ($paragraphIndex = 0; $paragraphIndex -lt $paragraphs.Count; $paragraphIndex++) {
    $wanted = ConvertTo-CanonicalNarrationText $paragraphs[$paragraphIndex]
    $accumulated = ''
    $firstCue = $cueIndex
    while ($cueIndex -lt $cues.Count -and $accumulated.Length -lt $wanted.Length) {
        $accumulated += $cues[$cueIndex].Canonical
        $cueIndex++
    }
    if ($accumulated -ne $wanted) {
        throw "Generated SRT does not match narration paragraph $($paragraphIndex + 1). Expected '$wanted', got '$accumulated'."
    }
    $lastCue = $cueIndex - 1
    $sourceStart = [math]::Max(0.0, [double]$cues[$firstCue].Start - 0.10)
    $sourceEnd = [double]$cues[$lastCue].End + 0.18
    if ($paragraphIndex -lt $paragraphs.Count - 1) {
        $sourceEnd = [math]::Min($sourceEnd, [double]$cues[$cueIndex].Start - 0.02)
    }
    $targetStart = [double]$targetWindows[$paragraphIndex][0]
    $targetEnd = [double]$targetWindows[$paragraphIndex][1]
    $sourceDuration = $sourceEnd - $sourceStart
    $available = $targetEnd - $targetStart - 0.12
    $tempo = if ($sourceDuration -gt $available) { $sourceDuration / $available } else { 1.0 }
    if ($tempo -gt 2.0) {
        throw "Paragraph $($paragraphIndex + 1) requires excessive time compression: $tempo"
    }
    $segments += [pscustomobject]@{
        FirstCue = $firstCue
        LastCue = $lastCue
        SourceStart = $sourceStart
        SourceEnd = $sourceEnd
        TargetStart = $targetStart
        TargetEnd = $targetEnd
        Tempo = $tempo
    }
}
if ($cueIndex -ne $cues.Count) { throw "Unmapped generated SRT cues remain: $($cues.Count - $cueIndex)" }

$alignedCues = @()
foreach ($segment in $segments) {
    for ($index = $segment.FirstCue; $index -le $segment.LastCue; $index++) {
        $alignedStart = $segment.TargetStart + ([double]$cues[$index].Start - $segment.SourceStart) / $segment.Tempo
        $alignedEnd = $segment.TargetStart + ([double]$cues[$index].End - $segment.SourceStart) / $segment.Tempo
        $alignedCues += [pscustomobject]@{
            Start = [math]::Max($segment.TargetStart, $alignedStart)
            End = [math]::Min($segment.TargetEnd, $alignedEnd)
            Text = [string]$cues[$index].Text
        }
    }
}
# Keep the final takeaway visible through picture lock and preserve the episode-wide subtitle coverage.
$alignedCues[-1].End = 220.0
$alignedBlocks = for ($index = 0; $index -lt $alignedCues.Count; $index++) {
    $cue = $alignedCues[$index]
    "{0}`n{1} --> {2}`n{3}" -f ($index + 1), (ConvertTo-SrtTime $cue.Start), `
        (ConvertTo-SrtTime $cue.End), $cue.Text
}
Write-SlingshotUtf8 $alignedSrtPath (($alignedBlocks -join "`n`n") + "`n")

$godot = Get-SlingshotGodot
Initialize-SlingshotGodotEnvironment
& $godot --headless --path $script:ProjectRoot --script res://scripts/export_subtitles.gd `
    '--' $alignedSrtPath $editorialSubtitlePath
if ($LASTEXITCODE -ne 0) { throw 'Aligned subtitle display export failed.' }

$filterParts = @()
$mixInputs = @('[1:a]')
for ($index = 0; $index -lt $segments.Count; $index++) {
    $segment = $segments[$index]
    $delayMs = [int][math]::Round($segment.TargetStart * 1000.0)
    $filter = "[0:a]atrim=start=$($segment.SourceStart.ToString('0.000',[Globalization.CultureInfo]::InvariantCulture)):end=$($segment.SourceEnd.ToString('0.000',[Globalization.CultureInfo]::InvariantCulture)),asetpts=PTS-STARTPTS"
    if ($segment.Tempo -gt 1.0005) {
        $filter += ",atempo=$($segment.Tempo.ToString('0.000000',[Globalization.CultureInfo]::InvariantCulture))"
    }
    $filter += ",adelay=${delayMs}:all=1[p$index]"
    $filterParts += $filter
    $mixInputs += "[p$index]"
}
$inputCount = $mixInputs.Count
$filterParts += (($mixInputs -join '') + "amix=inputs=${inputCount}:duration=first:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=7[out]")
$filterComplex = $filterParts -join ';'

& $ffmpeg -y -loglevel error -i $audioPath -f lavfi -t 220 -i 'anullsrc=r=48000:cl=mono' `
    -filter_complex $filterComplex -map '[out]' -t 220 -ar 48000 -ac 1 -c:a pcm_s24le $alignedPath
if ($LASTEXITCODE -ne 0) { throw 'Narration timeline alignment failed.' }

$duration = [double]((& $ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 $alignedPath).Trim())
if ([math]::Abs($duration - 220.0) -gt 0.01) { throw "Aligned narration duration is $duration, expected 220.0." }

$manifestLines = @(
    "episode=$([IO.Path]::GetFileName($episodePath))",
    "episode_sha256=$(Get-SlingshotSha256 $episodePath)",
    "script_sha256=$(Get-SlingshotSha256 $textPath)",
    "source_audio_sha256=$(Get-SlingshotSha256 $audioPath)",
    "normalized_audio_sha256=$(Get-SlingshotSha256 $alignedPath)",
    "subtitles_sha256=$(Get-SlingshotSha256 $generatedSrtPath)",
    "aligned_subtitles_sha256=$(Get-SlingshotSha256 $alignedSrtPath)",
    "editorial_subtitles_sha256=$(Get-SlingshotSha256 $editorialSubtitlePath)",
    "source_audio_duration_sec=$((& $ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 $audioPath).Trim())",
    "audio_duration_sec=$duration",
    'video_duration_sec=220',
    'alignment=15_paragraphs_to_editorial_timeline',
    "model=$([string]$config.narration.model)",
    "voice=$([string]$config.narration.voice)",
    "speed=$([string]$config.narration.speed)",
    "emotion_profile=$((@($config.narration.emotion_profile) -join ','))",
    'audio_standard=-16_LUFS_-1.5_dBTP_48kHz_mono_PCM24'
)
Write-SlingshotUtf8 $manifestPath (($manifestLines -join "`n") + "`n")

for ($index = 0; $index -lt $segments.Count; $index++) {
    $segment = $segments[$index]
    Write-Host ("align {0:D2}: source {1:F3}-{2:F3}s -> target {3:F1}-{4:F1}s tempo={5:F4}" -f `
        ($index + 1), $segment.SourceStart, $segment.SourceEnd, $segment.TargetStart, $segment.TargetEnd, $segment.Tempo)
}
Write-Host "narration-aligned: $($config.id) duration=${duration}s"
