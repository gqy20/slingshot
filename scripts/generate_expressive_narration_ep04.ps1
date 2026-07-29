[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

function Convert-HexAudio([string]$Hex) {
    $bytes = New-Object byte[] ($Hex.Length / 2)
    for ($index = 0; $index -lt $bytes.Length; $index++) {
        $bytes[$index] = [Convert]::ToByte($Hex.Substring($index * 2, 2), 16)
    }
    return $bytes
}

function Format-SrtTime([double]$Seconds) {
    $milliseconds = [int64][math]::Round($Seconds * 1000)
    $hours = [math]::Floor($milliseconds / 3600000)
    $milliseconds %= 3600000
    $minutes = [math]::Floor($milliseconds / 60000)
    $milliseconds %= 60000
    $secondsPart = [math]::Floor($milliseconds / 1000)
    $fraction = $milliseconds % 1000
    return ('{0:D2}:{1:D2}:{2:D2},{3:D3}' -f `
        [int]$hours, [int]$minutes, [int]$secondsPart, [int]$fraction)
}

$episodePath = (Resolve-Path -LiteralPath `
    (Join-Path $script:ProjectRoot 'content\episodes\s01e04-impact-force-curve.json')).Path
$config = Get-Content -Raw -Encoding UTF8 $episodePath | ConvertFrom-Json
$episodePaths = Get-SlingshotEpisodePaths ([string]$config.id)
$scriptRelative = ([string]$config.narration.script).Substring('res://'.Length).Replace('/', '\')
$textPath = Join-Path $script:ProjectRoot $scriptRelative
$paragraphs = @((Get-Content -Raw -Encoding UTF8 $textPath) -split '(?:\r?\n){2,}' |
    ForEach-Object { $_.Trim() } | Where-Object { $_ })
$emotions = @($config.narration.emotion_profile)
if ($paragraphs.Count -ne $emotions.Count) {
    throw "Paragraph/emotion count mismatch: $($paragraphs.Count)/$($emotions.Count)"
}

$mmxConfigPath = Join-Path $env:USERPROFILE '.mmx\config.json'
if (-not (Test-Path -LiteralPath $mmxConfigPath)) {
    throw "MiniMax configuration not found: $mmxConfigPath"
}
$mmxConfig = Get-Content -Raw -Encoding UTF8 $mmxConfigPath | ConvertFrom-Json
$headers = @{
    Authorization = "Bearer $($mmxConfig.api_key)"
    'Content-Type' = 'application/json'
}
$ffmpeg = Find-SlingshotTool -Name 'ffmpeg'
$ffprobe = Find-SlingshotTool -Name 'ffprobe'
$tempRoot = New-SlingshotRenderTempDirectory -Kind 'narration-expressive' -EpisodeId ([string]$config.id)

try {
    $offset = 0.0
    $cueNumber = 1
    $srtBlocks = New-Object System.Collections.Generic.List[string]
    $segmentPaths = @()

    for ($index = 0; $index -lt $paragraphs.Count; $index++) {
        $payload = @{
            model = [string]$config.narration.model
            text = $paragraphs[$index]
            stream = $false
            voice_setting = @{
                voice_id = [string]$config.narration.voice
                speed = [double]$config.narration.speed
                vol = [double]$config.narration.volume
                pitch = [int]$config.narration.pitch
                emotion = [string]$emotions[$index]
            }
            audio_setting = @{
                sample_rate = 44100
                bitrate = 128000
                format = 'wav'
                channel = 1
            }
            language_boost = [string]$config.narration.language
            pronunciation_dict = @{ tone = @($config.narration.pronunciations) }
            subtitle_enable = $true
            subtitle_type = 'sentence'
            output_format = 'hex'
        } | ConvertTo-Json -Depth 7 -Compress

        $response = Invoke-RestMethod -Method Post `
            -Uri 'https://api.minimaxi.com/v1/t2a_v2' `
            -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($payload))
        if ($response.base_resp.status_code -ne 0) {
            throw "Segment $($index + 1): $($response.base_resp.status_msg)"
        }

        $segmentPath = Join-Path $tempRoot ('segment-{0:D2}.wav' -f ($index + 1))
        [IO.File]::WriteAllBytes(
            $segmentPath,
            (Convert-HexAudio ([string]$response.data.audio))
        )
        $segmentPaths += $segmentPath

        $subtitleContent = (Invoke-WebRequest -UseBasicParsing `
            -Uri ([string]$response.data.subtitle_file)).Content
        if ($subtitleContent -is [byte[]]) {
            $subtitleContent = [Text.Encoding]::UTF8.GetString($subtitleContent)
        }
        $cues = $subtitleContent | ConvertFrom-Json
        foreach ($cue in @($cues)) {
            $start = $offset + [double]$cue.time_begin / 1000.0
            $end = $offset + [double]$cue.time_end / 1000.0
            $srtBlocks.Add(
                "$cueNumber`r`n$(Format-SrtTime $start) --> $(Format-SrtTime $end)`r`n$([string]$cue.text)"
            )
            $cueNumber++
        }

        $duration = [double]((& $ffprobe -v error -show_entries format=duration `
            -of default=nw=1:nk=1 $segmentPath).Trim())
        $offset += $duration
        Write-Host ('expressive-narration: segment {0:D2}/15 emotion={1} duration={2:F2}s' -f `
            ($index + 1), $emotions[$index], $duration)
    }

    $combinedAudio = Join-Path $tempRoot 'narration.mp3'
    $ffmpegArgs = @('-y', '-loglevel', 'error')
    foreach ($segmentPath in $segmentPaths) {
        $ffmpegArgs += @('-i', $segmentPath)
    }
    $inputLabels = (0..($segmentPaths.Count - 1) | ForEach-Object { "[$($_):a]" }) -join ''
    $ffmpegArgs += @(
        '-filter_complex', ($inputLabels + "concat=n=$($segmentPaths.Count):v=0:a=1[out]"),
        '-map', '[out]', '-ar', '44100', '-ac', '1', '-c:a', 'libmp3lame', '-b:a', '192k',
        $combinedAudio
    )
    & $ffmpeg @ffmpegArgs
    if ($LASTEXITCODE -ne 0) { throw 'Narration segment concatenation failed.' }

    $combinedSrt = Join-Path $tempRoot 'narration.srt'
    Write-SlingshotUtf8 $combinedSrt (($srtBlocks -join "`r`n`r`n") + "`r`n")

    $outputDir = $episodePaths.MasterAudio
    $backupDir = Join-Path $episodePaths.Archive ('voice-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force $backupDir | Out-Null
    foreach ($name in @(
        'narration.mp3', 'narration.srt', 'narration-normalized.wav', 'narration.manifest.txt'
    )) {
        $oldPath = Join-Path $outputDir $name
        if (Test-Path -LiteralPath $oldPath) {
            Copy-Item -LiteralPath $oldPath -Destination $backupDir -Force
        }
    }
    Copy-Item -LiteralPath $combinedAudio -Destination (Join-Path $outputDir 'narration.mp3') -Force
    Copy-Item -LiteralPath $combinedSrt -Destination (Join-Path $outputDir 'narration.srt') -Force
    Write-Host "expressive-narration: source_duration=$($offset.ToString('F3'))s"
    Write-Host "expressive-narration: backup=$backupDir"
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
