param(
    [string]$EpisodeId = 's01e03-angle-with-drag',
    [string]$Platform = 'bilibili',
    [string]$PublishingDocument = 'docs/publishing/s01e03-bilibili.md'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')

$projectRoot = $script:ProjectRoot
$finalRoot = Join-Path $projectRoot 'renders/final'
$publishingRoot = Join-Path $projectRoot ("renders/publishing/{0}" -f $EpisodeId)
$coverRoot = Join-Path $publishingRoot 'cover'
$packageRoot = Join-Path $publishingRoot $Platform
$extrasRoot = Join-Path $packageRoot 'extras'

$sourceVideo = Join-Path $finalRoot ("{0}.mp4" -f $EpisodeId)
$sourceSidecar = Join-Path $finalRoot ("{0}.json" -f $EpisodeId)
$sourceVideoManifest = Join-Path $finalRoot ("{0}.manifest.txt" -f $EpisodeId)
$sourceCover = Join-Path $coverRoot ("s01e03-cover-bilibili-1146x717.png")
$sourceCoverMaster = Join-Path $coverRoot 's01e03-cover-master-2292x1434.png'
$sourceCoverSocial = Join-Path $coverRoot 's01e03-cover-social-1920x1080.png'
$sourceCoverPreview = Join-Path $coverRoot 's01e03-cover-preview-320x200.png'
$sourceCoverManifest = Join-Path $coverRoot 'cover.manifest.json'
$sourceTrajectoryData = Join-Path $coverRoot 'trajectory-data.json'
$sourcePublishingDocument = Join-Path $projectRoot $PublishingDocument

$requiredSources = @(
    $sourceVideo,
    $sourceSidecar,
    $sourceVideoManifest,
    $sourceCover,
    $sourceCoverMaster,
    $sourceCoverSocial,
    $sourceCoverPreview,
    $sourceCoverManifest,
    $sourceTrajectoryData,
    $sourcePublishingDocument
)
foreach ($source in $requiredSources) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Missing release input: $source"
    }
}

$ffprobe = Find-SlingshotTool -Name 'ffprobe'
$probeJson = & $ffprobe -v error -show_entries 'format=duration:stream=index,codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels' -of json $sourceVideo
if ($LASTEXITCODE -ne 0) {
    throw "ffprobe failed for $sourceVideo"
}
$probe = ($probeJson -join [Environment]::NewLine) | ConvertFrom-Json
$videoStream = @($probe.streams | Where-Object { $_.codec_type -eq 'video' }) | Select-Object -First 1
$audioStream = @($probe.streams | Where-Object { $_.codec_type -eq 'audio' }) | Select-Object -First 1
if ($null -eq $videoStream) { throw 'Release video has no video stream' }
if ($null -eq $audioStream) { throw 'Release video has no audio stream' }
if ([int]$videoStream.width -ne 3840 -or [int]$videoStream.height -ne 2160) {
    throw ("Expected a 3840x2160 video, got {0}x{1}" -f $videoStream.width, $videoStream.height)
}
$durationSec = [double]$probe.format.duration
if ([Math]::Abs($durationSec - 300.0) -gt 0.5) {
    throw ("Expected an approximately 300 second video, got {0:N3}" -f $durationSec)
}

Add-Type -AssemblyName System.Drawing
$coverImage = [System.Drawing.Image]::FromFile($sourceCover)
try {
    if ($coverImage.Width -ne 1146 -or $coverImage.Height -ne 717) {
        throw ("Expected a 1146x717 cover, got {0}x{1}" -f $coverImage.Width, $coverImage.Height)
    }
}
finally {
    $coverImage.Dispose()
}
if ((Get-Item -LiteralPath $sourceCover).Length -ge 5MB) {
    throw 'Bilibili cover must be smaller than 5 MB'
}

New-Item -ItemType Directory -Force -Path $packageRoot, $extrasRoot | Out-Null

$packageVideo = Join-Path $packageRoot 'video.mp4'
$packageCover = Join-Path $packageRoot 'cover.png'
$packageCopy = Join-Path $packageRoot 'publish-copy.md'
Copy-Item -LiteralPath $sourceVideo -Destination $packageVideo -Force
Copy-Item -LiteralPath $sourceCover -Destination $packageCover -Force
Copy-Item -LiteralPath $sourcePublishingDocument -Destination $packageCopy -Force

$extraCopies = [ordered]@{
    'cover-master.png' = $sourceCoverMaster
    'cover-social-1920x1080.png' = $sourceCoverSocial
    'cover-preview-320x200.png' = $sourceCoverPreview
    'video-sidecar.json' = $sourceSidecar
    'video-render.manifest.txt' = $sourceVideoManifest
    'cover.manifest.json' = $sourceCoverManifest
    'trajectory-data.json' = $sourceTrajectoryData
}
foreach ($name in $extraCopies.Keys) {
    Copy-Item -LiteralPath $extraCopies[$name] -Destination (Join-Path $extrasRoot $name) -Force
}

$packageRelativeRoot = "renders/publishing/$EpisodeId/$Platform"
$supportingFiles = @($extraCopies.Keys | ForEach-Object { "$packageRelativeRoot/extras/$_" })
$examplesRoot = Join-Path $packageRoot 'examples'
if (Test-Path -LiteralPath $examplesRoot -PathType Container) {
    $supportingFiles += @(Get-ChildItem -LiteralPath $examplesRoot -File | Sort-Object Name | ForEach-Object {
        "$packageRelativeRoot/examples/$($_.Name)"
    })
}

$releaseManifest = [ordered]@{
    schema_version = 1
    episode_id = $EpisodeId
    platform = $Platform
    packaged_at_utc = [DateTime]::UtcNow.ToString('o')
    primary_files = [ordered]@{
        video = [ordered]@{
            path = "$packageRelativeRoot/video.mp4"
            bytes = (Get-Item -LiteralPath $packageVideo).Length
            sha256 = Get-SlingshotSha256 $packageVideo
            width = [int]$videoStream.width
            height = [int]$videoStream.height
            frame_rate = [string]$videoStream.r_frame_rate
            duration_sec = $durationSec
            video_codec = [string]$videoStream.codec_name
            audio_codec = [string]$audioStream.codec_name
            audio_sample_rate_hz = [int]$audioStream.sample_rate
            audio_channels = [int]$audioStream.channels
        }
        cover = [ordered]@{
            path = "$packageRelativeRoot/cover.png"
            bytes = (Get-Item -LiteralPath $packageCover).Length
            sha256 = Get-SlingshotSha256 $packageCover
            width = 1146
            height = 717
        }
        publishing_copy = [ordered]@{
            path = "$packageRelativeRoot/publish-copy.md"
            bytes = (Get-Item -LiteralPath $packageCopy).Length
            sha256 = Get-SlingshotSha256 $packageCopy
            source = $PublishingDocument.Replace('\', '/')
        }
    }
    supporting_files = $supportingFiles
}

$manifestPath = Join-Path $packageRoot 'release.manifest.json'
Write-SlingshotUtf8 -Path $manifestPath -Text ($releaseManifest | ConvertTo-Json -Depth 8)

$checksumFiles = Get-ChildItem -LiteralPath $packageRoot -Recurse -File |
    Where-Object { $_.Name -ne 'SHA256SUMS.txt' } |
    Sort-Object FullName
$checksumLines = foreach ($file in $checksumFiles) {
    $relative = $file.FullName.Substring($packageRoot.Length + 1).Replace('\', '/')
    "{0}  {1}" -f (Get-SlingshotSha256 $file.FullName), $relative
}
Write-SlingshotUtf8 -Path (Join-Path $packageRoot 'SHA256SUMS.txt') -Text (($checksumLines -join "`n") + "`n")

Write-Host ("release-package: {0}" -f $packageRoot)
Write-Host ("release-package: video={0}x{1} duration={2:N3}s" -f $videoStream.width, $videoStream.height, $durationSec)
Write-Host 'release-package: cover=1146x717'
