[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')

$episodeId = 's01e06-earth-quasi-satellite'
$episodePaths = Get-SlingshotEpisodePaths $episodeId
$episodeConfigPath = Join-Path $script:ProjectRoot 'content/episodes/s01e06-earth-quasi-satellite.json'
$episodeConfig = Get-Content -Raw -Encoding UTF8 -LiteralPath $episodeConfigPath | ConvertFrom-Json
$expectedDuration = Get-SlingshotEpisodeDuration $episodeConfig
$packageRoot = Join-Path $episodePaths.Deliveries 'bilibili'
$extrasRoot = Join-Path $packageRoot 'extras'
$sourceVideo = Join-Path $episodePaths.Masters 'program-master-4k.mp4'
$sourceVideoManifest = Join-Path $episodePaths.Masters 'program-master-4k.manifest.txt'
$sourceCoverRoot = Join-Path $episodePaths.Deliveries 'cover'
$sourceCover = Join-Path $sourceCoverRoot 'ep06-cover-b-orbits-the-sun-bilibili-1146x717.png'
$sourceCoverMaster = Join-Path $sourceCoverRoot 'ep06-cover-b-orbits-the-sun-master-4584x2868.png'
$sourceCoverPreview = Join-Path $sourceCoverRoot 'ep06-cover-b-orbits-the-sun-preview-320x200.png'
$sourceCoverManifest = Join-Path $sourceCoverRoot 'cover.manifest.json'
$sourceCopy = Join-Path $script:ProjectRoot 'docs/publishing/s01e06-bilibili.md'
$sourceSubtitles = Join-Path $episodePaths.MasterAudio 'narration.srt'
$sourceNarrationManifest = Join-Path $episodePaths.MasterAudio 'narration.manifest.txt'

foreach ($required in @(
    $sourceVideo, $sourceVideoManifest, $sourceCover, $sourceCoverMaster,
    $sourceCoverPreview, $sourceCoverManifest, $sourceCopy,
    $sourceSubtitles, $sourceNarrationManifest
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing release input: $required"
    }
}

$ffprobe = Find-SlingshotTool -Name 'ffprobe'
$probeText = ((& $ffprobe -v error -show_entries `
    'format=duration:stream=index,codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels' `
    -of json $sourceVideo) -join [Environment]::NewLine)
if ($LASTEXITCODE -ne 0) { throw 'ffprobe failed for release video.' }
$probe = $probeText | ConvertFrom-Json
$videoStream = @($probe.streams | Where-Object codec_type -eq 'video') | Select-Object -First 1
$audioStream = @($probe.streams | Where-Object codec_type -eq 'audio') | Select-Object -First 1
if ($null -eq $videoStream -or $null -eq $audioStream) { throw 'Release video needs picture and sound.' }
if ([int]$videoStream.width -ne 3840 -or [int]$videoStream.height -ne 2160 -or
    [string]$videoStream.r_frame_rate -ne '30/1') {
    throw 'Release video is not 3840x2160 at 30 fps.'
}
$duration = [double]$probe.format.duration
if ([Math]::Abs($duration - $expectedDuration) -gt 0.05) {
    throw "Unexpected release duration: $duration (expected $expectedDuration)."
}
if ([int]$audioStream.sample_rate -ne 48000) { throw 'Release audio must be 48 kHz.' }

$videoManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $sourceVideoManifest
$narrationHash = Get-SlingshotSha256 (Join-Path $episodePaths.MasterAudio 'narration-normalized.wav')
if (-not $videoManifest.Contains("narration_sha256=$narrationHash") -or
    -not $videoManifest.Contains('subtitle_font_size=48') -or
    -not $videoManifest.Contains('subtitle_bottom_margin=96')) {
    throw 'Release video manifest does not match current narration and subtitle configuration.'
}

Add-Type -AssemblyName System.Drawing
$coverImage = [System.Drawing.Image]::FromFile($sourceCover)
try {
    if ($coverImage.Width -ne 1146 -or $coverImage.Height -ne 717) {
        throw 'Expected 1146x717 cover.'
    }
} finally { $coverImage.Dispose() }
if ((Get-Item -LiteralPath $sourceCover).Length -ge 5MB) {
    throw 'Cover exceeds 5 MB.'
}
$coverManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $sourceCoverManifest | ConvertFrom-Json
if ([string]$coverManifest.recommended -ne 'ep06-cover-b-orbits-the-sun') {
    throw 'Cover manifest does not select the user-approved B direction.'
}

New-Item -ItemType Directory -Force -Path $packageRoot, $extrasRoot | Out-Null
$packageVideo = Join-Path $packageRoot 'video.mp4'
$packageCover = Join-Path $packageRoot 'cover.png'
$packageCopy = Join-Path $packageRoot 'publish-copy.md'
Copy-Item -LiteralPath $sourceVideo -Destination $packageVideo -Force
Copy-Item -LiteralPath $sourceCover -Destination $packageCover -Force
Copy-Item -LiteralPath $sourceCopy -Destination $packageCopy -Force
Copy-Item -LiteralPath $sourceCoverMaster -Destination (Join-Path $extrasRoot 'cover-master-4584x2868.png') -Force
Copy-Item -LiteralPath $sourceCoverPreview -Destination (Join-Path $extrasRoot 'cover-preview-320x200.png') -Force
Copy-Item -LiteralPath $sourceCoverManifest -Destination (Join-Path $extrasRoot 'cover.manifest.json') -Force
Copy-Item -LiteralPath $sourceVideoManifest -Destination (Join-Path $extrasRoot 'video-render.manifest.txt') -Force
Copy-Item -LiteralPath $sourceNarrationManifest -Destination (Join-Path $extrasRoot 'narration.manifest.txt') -Force
Copy-Item -LiteralPath $sourceSubtitles -Destination (Join-Path $extrasRoot 'subtitles-source.srt') -Force

if ((Get-SlingshotSha256 $sourceVideo) -ne (Get-SlingshotSha256 $packageVideo) -or
    (Get-SlingshotSha256 $sourceCover) -ne (Get-SlingshotSha256 $packageCover)) {
    throw 'Release copy verification failed.'
}

$titleLine = Get-Content -Encoding UTF8 -LiteralPath $sourceCopy |
    Where-Object { $_.StartsWith('> ') } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($titleLine)) { throw 'Publishing title is missing.' }

$release = [ordered]@{
    schema_version = 1
    episode_id = $episodeId
    platform = 'bilibili'
    packaged_at_utc = [DateTime]::UtcNow.ToString('o')
    recommended_title = $titleLine.Substring(2).Trim()
    publication_status = 'awaiting_external_image_rights_review'
    primary_files = [ordered]@{
        video = [ordered]@{
            path = 'video.mp4'; bytes = (Get-Item $packageVideo).Length
            sha256 = Get-SlingshotSha256 $packageVideo
            width = 3840; height = 2160; fps = 30; duration_sec = $duration
            video_codec = [string]$videoStream.codec_name
            audio_codec = [string]$audioStream.codec_name
            audio_sample_rate_hz = [int]$audioStream.sample_rate
        }
        cover = [ordered]@{
            path = 'cover.png'; bytes = (Get-Item $packageCover).Length
            sha256 = Get-SlingshotSha256 $packageCover
            width = 1146; height = 717; direction = 'ep06-cover-b-orbits-the-sun'
        }
        publishing_copy = [ordered]@{
            path = 'publish-copy.md'; sha256 = Get-SlingshotSha256 $packageCopy
        }
    }
    supporting_files = @(
        'extras/cover-master-4584x2868.png', 'extras/cover-preview-320x200.png',
        'extras/cover.manifest.json', 'extras/video-render.manifest.txt',
        'extras/narration.manifest.txt', 'extras/subtitles-source.srt'
    )
}
Write-SlingshotUtf8 (Join-Path $packageRoot 'release.manifest.json') ($release | ConvertTo-Json -Depth 8)
$checksumLines = Get-ChildItem -LiteralPath $packageRoot -Recurse -File |
    Where-Object Name -ne 'SHA256SUMS.txt' | Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($packageRoot.Length + 1).Replace('\', '/')
        "$(Get-SlingshotSha256 $_.FullName)  $relative"
    }
Write-SlingshotUtf8 (Join-Path $packageRoot 'SHA256SUMS.txt') (($checksumLines -join "`n") + "`n")

Write-Host "release-package: $packageRoot"
Write-Host "release-package: 3840x2160 30fps ${duration}s; cover 1146x717; rights review pending"
