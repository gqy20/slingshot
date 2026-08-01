[CmdletBinding()]
param(
    [string]$Video = 'renders/masters/s01e05-shortest-is-not-fastest/program-master-4k.mp4',
    [string]$PublishingDocument = 'docs/publishing/s01e05-bilibili.md'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')

$episodeId = 's01e05-shortest-is-not-fastest'
$episodePaths = Get-SlingshotEpisodePaths $episodeId
$packageRoot = Join-Path $episodePaths.Deliveries 'bilibili'
$coverRoot = Join-Path $episodePaths.Deliveries 'cover'
$extrasRoot = Join-Path $packageRoot 'extras'
$optionsRoot = Join-Path $packageRoot 'cover-options'

$videoPath = (Resolve-Path -LiteralPath (Join-Path $script:ProjectRoot $Video)).Path
$documentPath = (Resolve-Path -LiteralPath (Join-Path $script:ProjectRoot $PublishingDocument)).Path
$videoAnalysisPath = [IO.Path]::ChangeExtension($videoPath, '.json')
$videoManifestPath = [IO.Path]::ChangeExtension($videoPath, '.manifest.txt')
$coverPath = Join-Path $coverRoot 'ep05-cover-a-shortest-not-fastest-bilibili-hq-2292x1434.png'
$coverMasterPath = Join-Path $coverRoot 'ep05-cover-a-shortest-not-fastest-master-4584x2868.png'
$coverSocialPath = Join-Path $coverRoot 'ep05-cover-a-shortest-not-fastest-social-1920x1080.png'
$coverPreviewPath = Join-Path $coverRoot 'ep05-cover-a-shortest-not-fastest-preview-320x200.png'
$coverManifestPath = Join-Path $coverRoot 'cover.manifest.json'
$subtitleSourcePath = Join-Path $episodePaths.MasterAudio 'narration.srt'

foreach ($required in @(
    $videoPath, $documentPath, $videoAnalysisPath, $videoManifestPath,
    $coverPath, $coverMasterPath, $coverSocialPath, $coverPreviewPath,
    $coverManifestPath, $subtitleSourcePath
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing release input: $required"
    }
}

$ffprobe = Find-SlingshotTool -Name 'ffprobe'
$probeText = ((& $ffprobe -v error -show_entries `
    'format=duration:stream=index,codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels' `
    -of json $videoPath) -join [Environment]::NewLine)
if ($LASTEXITCODE -ne 0) { throw "ffprobe failed for $videoPath" }
$probe = $probeText | ConvertFrom-Json
$videoStream = @($probe.streams | Where-Object codec_type -eq 'video') | Select-Object -First 1
$audioStream = @($probe.streams | Where-Object codec_type -eq 'audio') | Select-Object -First 1
if ($null -eq $videoStream -or $null -eq $audioStream) {
    throw 'Release video must contain video and audio streams.'
}
if ([int]$videoStream.width -ne 3840 -or [int]$videoStream.height -ne 2160) {
    throw "Expected 3840x2160, got $($videoStream.width)x$($videoStream.height)."
}
$duration = [double]$probe.format.duration
if ([Math]::Abs($duration - 219.0) -gt 0.05) {
    throw "Expected 219 seconds, got $duration."
}

$videoManifestText = Get-Content -Raw -Encoding UTF8 -LiteralPath $videoManifestPath
foreach ($requiredManifestLine in @(
    'render_resolution=3840x2160',
    'subtitles=burned_in',
    'subtitle_font_size=42',
    'subtitle_bottom_margin=68',
    'audio_mix=voice_plus_ducked_beat_sfx'
)) {
    if (-not $videoManifestText.Contains($requiredManifestLine)) {
        throw "Video manifest is missing: $requiredManifestLine"
    }
}

Add-Type -AssemblyName System.Drawing
$coverImage = [System.Drawing.Image]::FromFile($coverPath)
try {
    if ($coverImage.Width -ne 2292 -or $coverImage.Height -ne 1434) {
        throw "Expected 2292x1434 cover, got $($coverImage.Width)x$($coverImage.Height)."
    }
    if ([Math]::Abs($coverImage.HorizontalResolution - 600.0) -gt 0.5 -or
        [Math]::Abs($coverImage.VerticalResolution - 600.0) -gt 0.5) {
        throw "Expected 600 DPI cover, got $($coverImage.HorizontalResolution)x$($coverImage.VerticalResolution)."
    }
}
finally {
    $coverImage.Dispose()
}
if ((Get-Item -LiteralPath $coverPath).Length -ge 5MB) {
    throw 'Bilibili cover must be smaller than 5 MB.'
}

New-Item -ItemType Directory -Force -Path $packageRoot, $extrasRoot, $optionsRoot | Out-Null
$packageVideo = Join-Path $packageRoot 'video.mp4'
$packageCover = Join-Path $packageRoot 'cover.png'
$packageCopy = Join-Path $packageRoot 'publish-copy.md'
$displaySubtitlePath = Join-Path $extrasRoot 'subtitles-display.srt'
Copy-Item -LiteralPath $videoPath -Destination $packageVideo -Force
Copy-Item -LiteralPath $coverPath -Destination $packageCover -Force
Copy-Item -LiteralPath $documentPath -Destination $packageCopy -Force
Copy-Item -LiteralPath $coverMasterPath -Destination (Join-Path $extrasRoot 'cover-master-4584x2868.png') -Force
Copy-Item -LiteralPath $coverSocialPath -Destination (Join-Path $extrasRoot 'cover-social-1920x1080.png') -Force
Copy-Item -LiteralPath $coverPreviewPath -Destination (Join-Path $extrasRoot 'cover-preview-320x200.png') -Force
Copy-Item -LiteralPath $coverManifestPath -Destination (Join-Path $extrasRoot 'cover.manifest.json') -Force
Copy-Item -LiteralPath $videoAnalysisPath -Destination (Join-Path $extrasRoot 'video-analysis.json') -Force
Copy-Item -LiteralPath $videoManifestPath -Destination (Join-Path $extrasRoot 'video-render.manifest.txt') -Force
Copy-Item -LiteralPath $subtitleSourcePath -Destination (Join-Path $extrasRoot 'subtitles-source.srt') -Force

$godot = Get-SlingshotGodot
& $godot --headless --path $script:ProjectRoot --script res://scripts/export_subtitles.gd `
    '--' $subtitleSourcePath $displaySubtitlePath
if ($LASTEXITCODE -ne 0) { throw 'Subtitle display export failed.' }

$alternatives = @()
foreach ($direction in @(
    'ep05-cover-b-line-vs-cycloid',
    'ep05-cover-c-time-proof',
    'ep05-cover-d-distance-time',
    'ep05-cover-e-freeze-frame'
)) {
    $name = "$direction-bilibili-1146x717.png"
    $source = Join-Path $coverRoot $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Missing alternative cover: $source"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $optionsRoot $name) -Force
    $alternatives += "cover-options/$name"
}

$titleLine = Get-Content -Encoding UTF8 -LiteralPath $documentPath |
    Where-Object { $_.StartsWith('> ') } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($titleLine)) {
    throw 'Recommended title blockquote is missing from publishing document.'
}
$recommendedTitle = $titleLine.Substring(2).Trim()
$manifest = [ordered]@{
    schema_version = 1
    episode_id = $episodeId
    platform = 'bilibili'
    packaged_at_utc = [DateTime]::UtcNow.ToString('o')
    recommended_title = $recommendedTitle
    model_scope = 'uniform gravity; fixed tracks; frictionless sliding point mass; shared endpoints'
    primary_files = [ordered]@{
        video = [ordered]@{
            path = 'video.mp4'
            bytes = (Get-Item -LiteralPath $packageVideo).Length
            sha256 = Get-SlingshotSha256 $packageVideo
            width = [int]$videoStream.width
            height = [int]$videoStream.height
            frame_rate = [string]$videoStream.r_frame_rate
            duration_sec = $duration
            video_codec = [string]$videoStream.codec_name
            audio_codec = [string]$audioStream.codec_name
            audio_sample_rate_hz = [int]$audioStream.sample_rate
            audio_channels = [int]$audioStream.channels
        }
        cover = [ordered]@{
            path = 'cover.png'
            bytes = (Get-Item -LiteralPath $packageCover).Length
            sha256 = Get-SlingshotSha256 $packageCover
            width = 2292
            height = 1434
            dpi = 600
            direction = 'ep05-cover-a-shortest-not-fastest'
        }
        publishing_copy = [ordered]@{
            path = 'publish-copy.md'
            bytes = (Get-Item -LiteralPath $packageCopy).Length
            sha256 = Get-SlingshotSha256 $packageCopy
        }
    }
    alternatives = $alternatives
    supporting_files = @(
        'extras/cover-master-4584x2868.png',
        'extras/cover-social-1920x1080.png',
        'extras/cover-preview-320x200.png',
        'extras/cover.manifest.json',
        'extras/video-analysis.json',
        'extras/video-render.manifest.txt',
        'extras/subtitles-source.srt',
        'extras/subtitles-display.srt'
    )
}
$releaseManifestPath = Join-Path $packageRoot 'release.manifest.json'
Write-SlingshotUtf8 $releaseManifestPath ($manifest | ConvertTo-Json -Depth 8)

$checksumLines = Get-ChildItem -LiteralPath $packageRoot -Recurse -File |
    Where-Object Name -ne 'SHA256SUMS.txt' |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($packageRoot.Length + 1).Replace('\', '/')
        "$(Get-SlingshotSha256 $_.FullName)  $relative"
    }
Write-SlingshotUtf8 (Join-Path $packageRoot 'SHA256SUMS.txt') (($checksumLines -join "`n") + "`n")

Write-Host "release-package: $packageRoot"
Write-Host "release-package: video=3840x2160 duration=${duration}s cover=2292x1434@600DPI"
