[CmdletBinding()]
param(
    [string]$Video = 'renders/masters/s01e04-impact-force-curve/program-master-4k.mp4',
    [string]$PublishingDocument = 'docs/publishing/s01e04-bilibili.md'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')

$episodeId = 's01e04-impact-force-curve'
$episodePaths = Get-SlingshotEpisodePaths $episodeId
$packageRoot = Join-Path $episodePaths.Deliveries 'bilibili'
$coverRoot = Join-Path $episodePaths.Deliveries 'cover'
$extrasRoot = Join-Path $packageRoot 'extras'
$optionsRoot = Join-Path $packageRoot 'cover-options'
$videoPath = (Resolve-Path -LiteralPath (Join-Path $script:ProjectRoot $Video)).Path
$documentPath = (Resolve-Path -LiteralPath (Join-Path $script:ProjectRoot $PublishingDocument)).Path
$coverPath = Join-Path $coverRoot 'ep04-cover-a-fivefold-bilibili-hq-2292x1434.png'
$masterPath = Join-Path $coverRoot 'ep04-cover-a-fivefold-master-4584x2868.png'
$socialPath = Join-Path $coverRoot 'ep04-cover-a-fivefold-social-1920x1080.png'
$previewPath = Join-Path $coverRoot 'ep04-cover-a-fivefold-preview-320x200.png'
$coverManifestPath = Join-Path $coverRoot 'cover.manifest.json'
$bgmLicensePath = Join-Path $script:ProjectRoot 'assets\audio\bgm\sonor-2-mixkit-license.md'
$subtitlePath = Join-Path $script:ProjectRoot 'content\subtitles\s01e04-impact-force-curve.srt'

foreach ($required in @(
    $videoPath, $documentPath, $coverPath, $masterPath, $socialPath, $previewPath,
    $coverManifestPath, $bgmLicensePath, $subtitlePath
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing release input: $required" }
}

$ffprobe = Find-SlingshotTool -Name 'ffprobe'
$probe = ((& $ffprobe -v error -show_entries `
    'format=duration:stream=index,codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels' `
    -of json $videoPath) -join [Environment]::NewLine) | ConvertFrom-Json
$videoStream = @($probe.streams | Where-Object codec_type -eq 'video') | Select-Object -First 1
$audioStream = @($probe.streams | Where-Object codec_type -eq 'audio') | Select-Object -First 1
if ($null -eq $videoStream -or $null -eq $audioStream) { throw 'Release video must contain video and audio streams.' }
if ([int]$videoStream.width -ne 3840 -or [int]$videoStream.height -ne 2160) {
    throw "Expected 3840x2160, got $($videoStream.width)x$($videoStream.height)."
}
$duration = [double]$probe.format.duration
if ([math]::Abs($duration - 220.0) -gt 0.05) { throw "Expected 220 seconds, got $duration." }

Add-Type -AssemblyName System.Drawing
$coverImage = [System.Drawing.Image]::FromFile($coverPath)
try {
    if ($coverImage.Width -ne 2292 -or $coverImage.Height -ne 1434) {
        throw "Expected 2292x1434 cover, got $($coverImage.Width)x$($coverImage.Height)."
    }
    if ([math]::Abs($coverImage.HorizontalResolution - 600.0) -gt 0.5 -or
        [math]::Abs($coverImage.VerticalResolution - 600.0) -gt 0.5) {
        throw "Expected 600 DPI cover, got $($coverImage.HorizontalResolution)x$($coverImage.VerticalResolution)."
    }
} finally { $coverImage.Dispose() }
if ((Get-Item -LiteralPath $coverPath).Length -ge 5MB) { throw 'Bilibili cover must be smaller than 5 MB.' }

New-Item -ItemType Directory -Force -Path $packageRoot, $extrasRoot, $optionsRoot | Out-Null
Copy-Item -LiteralPath $videoPath -Destination (Join-Path $packageRoot 'video.mp4') -Force
Copy-Item -LiteralPath $coverPath -Destination (Join-Path $packageRoot 'cover.png') -Force
Copy-Item -LiteralPath $documentPath -Destination (Join-Path $packageRoot 'publish-copy.md') -Force
Copy-Item -LiteralPath $masterPath -Destination (Join-Path $extrasRoot 'cover-master-4584x2868.png') -Force
Copy-Item -LiteralPath $socialPath -Destination (Join-Path $extrasRoot 'cover-social-1920x1080.png') -Force
Copy-Item -LiteralPath $previewPath -Destination (Join-Path $extrasRoot 'cover-preview-320x200.png') -Force
Copy-Item -LiteralPath $coverManifestPath -Destination (Join-Path $extrasRoot 'cover.manifest.json') -Force
Copy-Item -LiteralPath $bgmLicensePath -Destination (Join-Path $extrasRoot 'bgm-license-mixkit.md') -Force
Copy-Item -LiteralPath $subtitlePath -Destination (Join-Path $extrasRoot 'subtitles-burn-in.srt') -Force
$legacyContestNote = Join-Path $extrasRoot 'contest-entry-private.md'
if (Test-Path -LiteralPath $legacyContestNote -PathType Leaf) {
    Remove-Item -LiteralPath $legacyContestNote -Force
}

$alternatives = @()
foreach ($direction in @('b-duration', 'c-readout', 'd-not-number')) {
    $name = "ep04-cover-$direction-bilibili-1146x717.png"
    Copy-Item -LiteralPath (Join-Path $coverRoot $name) -Destination (Join-Path $optionsRoot $name) -Force
    $alternatives += "cover-options/$name"
}

$packageVideo = Join-Path $packageRoot 'video.mp4'
$packageCover = Join-Path $packageRoot 'cover.png'
$packageCopy = Join-Path $packageRoot 'publish-copy.md'
$titleLine = Get-Content -Encoding UTF8 $documentPath | Where-Object { $_.StartsWith('> ') } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($titleLine)) { throw 'Recommended title blockquote is missing from publishing document.' }
$recommendedTitle = $titleLine.Substring(2).Trim()
$manifest = [ordered]@{
    schema_version = 1
    episode_id = $episodeId
    platform = 'bilibili'
    packaged_at_utc = [DateTime]::UtcNow.ToString('o')
    recommended_title = $recommendedTitle
    model_scope = '1D normal impact; equal half-sine waveform and 8 N*s normal impulse'
    primary_files = [ordered]@{
        video = [ordered]@{
            path = 'video.mp4'; bytes = (Get-Item $packageVideo).Length; sha256 = Get-SlingshotSha256 $packageVideo
            width = 3840; height = 2160; frame_rate = [string]$videoStream.r_frame_rate; duration_sec = $duration
            video_codec = [string]$videoStream.codec_name; audio_codec = [string]$audioStream.codec_name
            audio_sample_rate_hz = [int]$audioStream.sample_rate; audio_channels = [int]$audioStream.channels
        }
        cover = [ordered]@{
            path = 'cover.png'; bytes = (Get-Item $packageCover).Length; sha256 = Get-SlingshotSha256 $packageCover
            width = 2292; height = 1434; dpi = 600; direction = 'ep04-cover-a-fivefold'
        }
        publishing_copy = [ordered]@{
            path = 'publish-copy.md'; bytes = (Get-Item $packageCopy).Length; sha256 = Get-SlingshotSha256 $packageCopy
        }
    }
    alternatives = $alternatives
    internal_records = [ordered]@{
        public_copy = $false
        contest = [ordered]@{
            status = 'entered'
            label = 'Bilibili Science 3 Minutes 2026'
            activity_url = 'https://www.bilibili.com/blackboard/era/science3min2026pc.html?spm_id_from=333.1035.top.function_card.click'
            note = 'publish-copy.md (internal contest note section)'
        }
        bgm_license = 'extras/bgm-license-mixkit.md'
        burned_subtitles = 'extras/subtitles-burn-in.srt'
    }
}
Write-SlingshotUtf8 (Join-Path $packageRoot 'release.manifest.json') ($manifest | ConvertTo-Json -Depth 8)

$checksumLines = Get-ChildItem -LiteralPath $packageRoot -Recurse -File |
    Where-Object Name -ne 'SHA256SUMS.txt' | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($packageRoot.Length + 1).Replace('\', '/')
        "$(Get-SlingshotSha256 $_.FullName)  $relative"
    }
Write-SlingshotUtf8 (Join-Path $packageRoot 'SHA256SUMS.txt') (($checksumLines -join "`n") + "`n")
Write-Host "release-package: $packageRoot"
Write-Host "release-package: video=3840x2160 duration=${duration}s cover=2292x1434@600DPI"
