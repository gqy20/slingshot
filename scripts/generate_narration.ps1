[CmdletBinding()]
param(
    [switch]$Reuse,
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

    $stem = [IO.Path]::GetFileNameWithoutExtension($episodePath)
    $outputDir = Join-Path $script:RenderRoot "narration\$stem"
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    $audio = Join-Path $outputDir 'narration.mp3'
    $subtitles = Join-Path $outputDir 'narration.srt'
    $normalized = Join-Path $outputDir 'narration-normalized.wav'
    $manifest = Join-Path $outputDir 'narration.manifest.txt'

    if (-not $Reuse) {
        $tempDir = Join-Path $script:RenderRoot ('.narration-tmp-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        try {
            $tempAudio = Join-Path $tempDir 'narration.mp3'
            $model = if ($narration.PSObject.Properties['model']) { [string]$narration.model } else { 'speech-2.8-hd' }
            $language = if ($narration.PSObject.Properties['language']) { [string]$narration.language } else { 'Chinese' }
            $speed = if ($narration.PSObject.Properties['speed']) { [string]$narration.speed } else { '1.0' }
            $volume = if ($narration.PSObject.Properties['volume']) { [string]$narration.volume } else { '1.0' }
            $pitch = if ($narration.PSObject.Properties['pitch']) { [string]$narration.pitch } else { '0' }
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
            $tempSrt = Join-Path $tempDir 'narration.srt'
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
    if ($duration -le 0 -or $duration -gt $videoDuration) {
        throw "Narration duration $duration exceeds video duration $videoDuration for $stem"
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
        "mmx_cli=$((& $mmx --version | Select-Object -First 1))",
        'audio_standard=-16_LUFS_-1.5_dBTP_48kHz_mono_PCM24'
    )
    Write-SlingshotUtf8 $manifest (($lines -join "`n") + "`n")
    Write-Host "narration: $stem audio=${duration}s video=${videoDuration}s"
}

