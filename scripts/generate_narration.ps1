[CmdletBinding()]
param(
    [switch]$Reuse,
    [switch]$AllowLong,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Episode = @()
)

. (Join-Path $PSScriptRoot 'common.ps1')
$mmx = Find-SlingshotTool -Name 'mmx'
$ffmpeg = Find-SlingshotTool -Name 'ffmpeg'
$ffprobe = Find-SlingshotTool -Name 'ffprobe'

if ($Episode.Count -eq 0) {
    $Episode = @(Get-ChildItem (Join-Path $script:ProjectRoot 'content\episodes') `
        -File -Filter 's??e??-*.json' | Sort-Object Name | ForEach-Object FullName)
}

foreach ($episodeInput in $Episode) {
    $episodePath = (Resolve-Path -LiteralPath $episodeInput).Path
    $config = Get-Content -Raw -Encoding UTF8 $episodePath | ConvertFrom-Json
    $narrationProperty = $config.PSObject.Properties['narration']
    if ($null -eq $narrationProperty) { continue }
    $narration = $narrationProperty.Value
    $scriptRelative = ([string]$narration.script).Substring('res://'.Length).Replace('/', '\')
    $textPath = Join-Path $script:ProjectRoot $scriptRelative
    if (-not (Test-Path $textPath)) { throw "Narration text not found: $textPath" }

    $stem = [string]$config.id
    $episodePaths = Get-SlingshotEpisodePaths $stem
    $outputDir = $episodePaths.MasterAudio
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    $audio = Join-Path $outputDir 'narration.mp3'
    $subtitles = Join-Path $outputDir 'narration.srt'
    $normalized = Join-Path $outputDir 'narration-normalized.wav'
    $manifest = Join-Path $outputDir 'narration.manifest.txt'
    $timingMode = if ($narration.PSObject.Properties['timing_mode']) {
        [string]$narration.timing_mode
    } else {
        'continuous'
    }
    $beatTimingLines = @()

    if (-not $Reuse) {
        $tempDir = New-SlingshotRenderTempDirectory -Kind 'narration' -EpisodeId $stem
        try {
            $tempAudio = Join-Path $tempDir 'narration.mp3'
            $model = if ($narration.PSObject.Properties['model']) { [string]$narration.model } else { 'speech-2.8-hd' }
            $language = if ($narration.PSObject.Properties['language']) { [string]$narration.language } else { 'Chinese' }
            $speed = if ($narration.PSObject.Properties['speed']) { [string]$narration.speed } else { '1.0' }
            $volume = if ($narration.PSObject.Properties['volume']) { [string]$narration.volume } else { '1.0' }
            $pitch = if ($narration.PSObject.Properties['pitch']) { [string]$narration.pitch } else { '0' }
            $tempSrt = Join-Path $tempDir 'narration.srt'
            if ($timingMode -eq 'beats') {
                $paragraphs = @([regex]::Split(
                    (Get-Content -Raw -Encoding UTF8 $textPath).Trim(),
                    '\r?\n\s*\r?\n'
                ) | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                $beats = @($config.beats)
                if ($paragraphs.Count -ne $beats.Count) {
                    throw "Beat-timed narration requires one paragraph per beat; got $($paragraphs.Count) paragraphs and $($beats.Count) beats for $stem"
                }
                $concatLines = @()
                for ($index = 0; $index -lt $beats.Count; $index++) {
                    $segmentText = Join-Path $tempDir ('beat-{0:d2}.txt' -f $index)
                    $segmentMp3 = Join-Path $tempDir ('beat-{0:d2}.mp3' -f $index)
                    $segmentWav = Join-Path $tempDir ('beat-{0:d2}.wav' -f $index)
                    Write-SlingshotUtf8 $segmentText $paragraphs[$index]
                    $arguments = @('speech', 'synthesize', '--text-file', $segmentText, '--model', $model,
                        '--voice', [string]$narration.voice, '--speed', $speed, '--volume', $volume,
                        '--pitch', $pitch, '--language', $language, '--format', 'mp3', '--sample-rate',
                        '32000', '--bitrate', '128000', '--channels', '1', '--out', $segmentMp3,
                        '--non-interactive', '--quiet', '--output', 'json')
                    if ($narration.PSObject.Properties['pronunciations']) {
                        foreach ($pronunciation in @($narration.pronunciations)) {
                            $arguments += @('--pronunciation', [string]$pronunciation)
                        }
                    }
                    & $mmx @arguments
                    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $segmentMp3)) {
                        throw "mmx beat narration generation failed for $stem beat $($beats[$index].id)"
                    }
                    $segmentDuration = [double]((& $ffprobe -v error -show_entries format=duration `
                        -of default=nw=1:nk=1 $segmentMp3).Trim())
                    $beatDuration = [double]$beats[$index].duration
                    if ($segmentDuration -gt $beatDuration - 0.1) {
                        throw "Narration beat $($beats[$index].id) is ${segmentDuration}s but only ${beatDuration}s is available"
                    }
                    & $ffmpeg -y -loglevel error -i $segmentMp3 -af apad -t $beatDuration `
                        -ar 32000 -ac 1 -c:a pcm_s16le $segmentWav
                    if ($LASTEXITCODE -ne 0) { throw "Failed to pad narration beat $($beats[$index].id)" }
                    $concatPath = $segmentWav.Replace('\', '/')
                    $concatLines += "file '$concatPath'"
                    $beatTimingLines += "beat_$($beats[$index].id)_speech_sec=$segmentDuration"
                    $beatTimingLines += "beat_$($beats[$index].id)_slot_sec=$beatDuration"
                }
                $concatFile = Join-Path $tempDir 'beats.concat.txt'
                Write-SlingshotUtf8 $concatFile (($concatLines -join "`n") + "`n")
                & $ffmpeg -y -loglevel error -f concat -safe 0 -i $concatFile `
                    -c:a libmp3lame -b:a 128k -ar 32000 -ac 1 $tempAudio
                if ($LASTEXITCODE -ne 0) { throw "Failed to concatenate beat narration for $stem" }
                $subtitleProperty = $narration.PSObject.Properties['subtitle_script']
                if ($null -eq $subtitleProperty) {
                    throw "Beat-timed narration requires narration.subtitle_script for $stem"
                }
                $subtitleResource = [string]$subtitleProperty.Value
                if (-not $subtitleResource.StartsWith('res://') -or $subtitleResource.Contains('..')) {
                    throw "Unsafe narration.subtitle_script: $subtitleResource"
                }
                $editorialSrt = Join-Path $script:ProjectRoot $subtitleResource.Substring(6).Replace('/', '\')
                Copy-Item -LiteralPath $editorialSrt -Destination $tempSrt
            } else {
                $arguments = @('speech', 'synthesize', '--text-file', $textPath, '--model', $model,
                    '--voice', [string]$narration.voice, '--speed', $speed, '--volume', $volume,
                    '--pitch', $pitch, '--language', $language, '--format', 'mp3', '--sample-rate',
                    '32000', '--bitrate', '128000', '--channels', '1', '--subtitles', '--out',
                    $tempAudio, '--non-interactive', '--quiet', '--output', 'json')
                if ($narration.PSObject.Properties['pronunciations']) {
                    foreach ($pronunciation in @($narration.pronunciations)) {
                        $arguments += @('--pronunciation', [string]$pronunciation)
                    }
                }
                & $mmx @arguments
                if ($LASTEXITCODE -ne 0) { throw "mmx narration generation failed for $stem" }
            }
            if (-not (Test-Path $tempAudio) -or -not (Test-Path $tempSrt)) {
                throw "mmx did not produce MP3 and SRT for $stem"
            }
            Move-Item -Force $tempAudio $audio
            Move-Item -Force $tempSrt $subtitles
        } finally {
            if (Test-Path $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
        }
    } elseif (-not (Test-Path $audio) -or -not (Test-Path $subtitles)) {
        throw "-Reuse requested but narration assets are missing for $stem"
    }

    & $ffmpeg -y -loglevel error -i $audio `
        -af 'loudnorm=I=-16:TP=-1.5:LRA=7' -ar 48000 -ac 1 `
        -c:a pcm_s24le $normalized
    if ($LASTEXITCODE -ne 0) { throw "Narration normalization failed for $stem" }
    $duration = [double]((& $ffprobe -v error -show_entries format=duration `
        -of default=nw=1:nk=1 $normalized).Trim())
    $videoDuration = Get-SlingshotEpisodeDuration $config
    if ($duration -le 0) {
        throw "Narration duration is invalid for $stem"
    }
    if ($duration -gt $videoDuration -and -not $AllowLong) {
        throw "Narration duration $duration exceeds video duration $videoDuration for $stem; use -AllowLong before timeline alignment"
    }
    $lines = @(
        "episode=$([IO.Path]::GetFileName($episodePath))",
        "episode_sha256=$(Get-SlingshotSha256 $episodePath)",
        "script_sha256=$(Get-SlingshotSha256 $textPath)",
        "source_audio_sha256=$(Get-SlingshotSha256 $audio)",
        "normalized_audio_sha256=$(Get-SlingshotSha256 $normalized)",
        "subtitles_sha256=$(Get-SlingshotSha256 $subtitles)",
        "audio_duration_sec=$duration",
        "video_duration_sec=$videoDuration",
        "timing_mode=$timingMode",
        "mmx_cli=$((& $mmx --version | Select-Object -First 1))",
        'audio_standard=-16_LUFS_-1.5_dBTP_48kHz_mono_PCM24'
    ) + $beatTimingLines
    Write-SlingshotUtf8 $manifest (($lines -join "`n") + "`n")
    Write-Host "narration: $stem audio=${duration}s video=${videoDuration}s"
}
