[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Episode,
    [Parameter(Position = 1)][string]$CleanMaster = '',
    [Parameter(Position = 2)][string]$Output = '',
    [string]$Bgm = '',
    [ValidateRange(24, 64)][int]$SubtitleFontSize = 42,
    [ValidateRange(30, 180)][int]$SubtitleBottomMargin = 68,
    [ValidateSet('auto', 'nvenc', 'libx264')][string]$VideoEncoder = 'auto'
)

. (Join-Path $PSScriptRoot 'common.ps1')

$episodePath = (Resolve-Path -LiteralPath $Episode).Path
$config = Get-Content -Raw -Encoding UTF8 $episodePath | ConvertFrom-Json
$episodeName = [string]$config.id
$episodePaths = Get-SlingshotEpisodePaths $episodeName
$videoConfig = $config.video
if (-not $PSBoundParameters.ContainsKey('SubtitleFontSize') -and $videoConfig.PSObject.Properties['subtitle_font_size']) {
    $SubtitleFontSize = [int]$videoConfig.subtitle_font_size
}
if (-not $PSBoundParameters.ContainsKey('SubtitleBottomMargin') -and $videoConfig.PSObject.Properties['subtitle_bottom_margin']) {
    $SubtitleBottomMargin = [int]$videoConfig.subtitle_bottom_margin
}
if ($SubtitleFontSize -lt 24 -or $SubtitleFontSize -gt 64) {
    throw "video.subtitle_font_size must be between 24 and 64: $SubtitleFontSize"
}
if ($SubtitleBottomMargin -lt 30 -or $SubtitleBottomMargin -gt 180) {
    throw "video.subtitle_bottom_margin must be between 30 and 180: $SubtitleBottomMargin"
}
$CleanMaster = if ($CleanMaster) { $CleanMaster } else { $episodePaths.PictureCleanMaster }
$Output = if ($Output) { $Output } else { $episodePaths.ProgramMaster }
$cleanMasterPath = (Resolve-Path -LiteralPath $CleanMaster).Path
$duration = Get-SlingshotEpisodeDuration $config
$fps = [int]$config.video.fps

$outputPath = if ([IO.Path]::IsPathRooted($Output)) {
    [IO.Path]::GetFullPath($Output)
} else {
    [IO.Path]::GetFullPath((Join-Path (Get-Location) $Output))
}
if ([IO.Path]::GetExtension($outputPath) -ne '.mp4') { throw 'Output path must end in .mp4.' }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPath) | Out-Null

$timingMode = if ($config.narration.PSObject.Properties['timing_mode']) {
    [string]$config.narration.timing_mode
} else {
    'continuous'
}
$subtitlePath = if ($timingMode -eq 'beats') {
    Join-Path $episodePaths.MasterAudio 'narration.srt'
} else {
    $subtitleRelative = [string]$config.narration.subtitle_script
    if (-not $subtitleRelative.StartsWith('res://') -or $subtitleRelative.Contains('..')) {
        throw "Unsafe narration.subtitle_script: $subtitleRelative"
    }
    Join-Path $script:ProjectRoot $subtitleRelative.Substring(6).Replace('/', '\')
}
$narrationPath = Join-Path $episodePaths.MasterAudio 'narration-normalized.wav'
$soundDesignPath = Join-Path $episodePaths.MasterAudio 'sound-design.wav'
$required = @($cleanMasterPath, $subtitlePath, $narrationPath, $soundDesignPath)
$bgmPath = $null
if (-not [string]::IsNullOrWhiteSpace($Bgm)) {
    $bgmPath = (Resolve-Path -LiteralPath $Bgm).Path
    $required += $bgmPath
}
foreach ($asset in $required) {
    if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) { throw "Missing reburn asset: $asset" }
}

$ffmpeg = Find-SlingshotTool -Name 'ffmpeg'
$ffprobe = Find-SlingshotTool -Name 'ffprobe'
$godot = Get-SlingshotGodot
Initialize-SlingshotGodotEnvironment
$tempRoot = New-SlingshotRenderTempDirectory -Kind 'reburn' -EpisodeId $episodeName
$displaySrt = Join-Path $tempRoot 'subtitles-display.srt'
$subtitleAss = Join-Path $tempRoot 'subtitles.ass'
$outputTemp = Join-Path $tempRoot 'output.mp4'
$succeeded = $false

try {
    & $godot --headless --path $script:ProjectRoot --script res://scripts/export_subtitles.gd `
        '--' $subtitlePath $displaySrt
    if ($LASTEXITCODE -ne 0) { throw 'Subtitle display export failed.' }
    & $ffmpeg -y -loglevel error -i $displaySrt $subtitleAss
    if ($LASTEXITCODE -ne 0) { throw 'Subtitle conversion failed.' }

    $assText = Get-Content -Raw -Encoding UTF8 $subtitleAss
    $assText = $assText -replace '(?m)^PlayResX:.*$', 'PlayResX: 1920'
    $assText = $assText -replace '(?m)^PlayResY:.*$', 'PlayResY: 1080'
    $style = "Style: Default,Sarasa Gothic SC,$SubtitleFontSize,&H00E9F0F2,&H00E9F0F2,&H60050608,&H00050608,-1,0,0,0,100,100,0,0,1,2,0,2,190,190,$SubtitleBottomMargin,1"
    $assText = $assText -replace '(?m)^Style: Default,.*$', $style
    Write-SlingshotUtf8 $subtitleAss $assText

    $assFilterPath = $subtitleAss.Replace('\', '/').Replace(':', '\:').Replace("'", "\'")
    $fontFilterPath = (Join-Path $script:ProjectRoot 'assets\fonts').Replace('\', '/').Replace(':', '\:').Replace("'", "\'")
    $filterParts = @(
        "[0:v]subtitles=filename='$assFilterPath':fontsdir='$fontFilterPath'[vout]",
        '[2:a]volume=0.40[sfx]',
        '[sfx][1:a]sidechaincompress=threshold=0.015:ratio=8:attack=15:release=300[sfxduck]'
    )
    $inputArgs = @('-i', $cleanMasterPath, '-i', $narrationPath, '-i', $soundDesignPath)
    if ($bgmPath) {
        $inputArgs += @('-stream_loop', '-1', '-i', $bgmPath)
        $filterParts += @(
            "[3:a]atrim=duration=$duration,asetpts=PTS-STARTPTS,volume=-16dB,volume=-4dB:enable='between(t,89,104)',afade=t=in:st=0:d=1.0,afade=t=out:st=$($duration - 3):d=3[bg]",
            '[bg][1:a]sidechaincompress=threshold=0.018:ratio=8:attack=15:release=350[bgduck]',
            '[1:a][sfxduck][bgduck]amix=inputs=3:duration=longest:normalize=0,alimiter=limit=0.78:level=false[premaster]',
            '[premaster]loudnorm=I=-16:TP=-1.5:LRA=7[aout]'
        )
    } else {
        $filterParts += @(
            '[1:a][sfxduck]amix=inputs=2:duration=longest:normalize=0,alimiter=limit=0.78:level=false[premaster]',
            '[premaster]loudnorm=I=-16:TP=-1.5:LRA=7[aout]'
        )
    }
    $filter = $filterParts -join ';'

    $encoderList = (& $ffmpeg -hide_banner -encoders 2>&1) -join "`n"
    $nvencAvailable = $encoderList -match '(?m)^\s*V\S*\s+h264_nvenc\s'
    $encoderCandidates = switch ($VideoEncoder) {
        'auto' { if ($nvencAvailable) { @('h264_nvenc', 'libx264') } else { @('libx264') }; break }
        'nvenc' {
            if (-not $nvencAvailable) { throw 'h264_nvenc is not available in this FFmpeg build.' }
            @('h264_nvenc'); break
        }
        'libx264' { @('libx264'); break }
    }
    $selectedEncoder = $null
    foreach ($candidate in $encoderCandidates) {
        if (Test-Path $outputTemp) { Remove-Item -LiteralPath $outputTemp -Force }
        $codecArgs = if ($candidate -eq 'h264_nvenc') {
            @('-c:v', 'h264_nvenc', '-preset', 'p6', '-tune', 'hq', '-rc', 'vbr', '-cq', '19', '-b:v', '0')
        } else {
            @('-c:v', 'libx264', '-preset', 'medium', '-crf', '18')
        }
        & $ffmpeg -y -loglevel error @inputArgs -t $duration -filter_complex $filter `
            -map '[vout]' -map '[aout]' @codecArgs -pix_fmt yuv420p -fps_mode cfr -r $fps `
            -c:a aac -b:a 256k -ar 48000 -ac $(if ($bgmPath) { 2 } else { 1 }) `
            -movflags +faststart $outputTemp
        if ($LASTEXITCODE -eq 0 -and (Test-Path $outputTemp)) {
            $selectedEncoder = $candidate
            break
        }
    }
    if (-not $selectedEncoder) { throw 'Reburn encoding failed.' }

    $probe = (& $ffprobe -v error -select_streams v:0 `
        -show_entries stream=codec_name,width,height,avg_frame_rate -of csv=p=0 $outputTemp).Trim()
    if ($probe -ne "h264,3840,2160,$fps/1") { throw "Unexpected reburn metadata: $probe" }
    $actualDuration = [double]((& $ffprobe -v error -show_entries format=duration `
        -of default=nw=1:nk=1 $outputTemp).Trim())
    if ([math]::Abs($actualDuration - $duration) -gt 0.05) {
        throw "Unexpected reburn duration: $actualDuration (expected $duration)"
    }

    $manifest = @(
        "episode=$([IO.Path]::GetFileName($episodePath))",
        "episode_sha256=$(Get-SlingshotSha256 $episodePath)",
        "clean_master=$([IO.Path]::GetFileName($cleanMasterPath))",
        "clean_master_sha256=$(Get-SlingshotSha256 $cleanMasterPath)",
        "subtitles_sha256=$(Get-SlingshotSha256 $subtitlePath)",
        "narration_sha256=$(Get-SlingshotSha256 $narrationPath)",
        "sound_design_sha256=$(Get-SlingshotSha256 $soundDesignPath)",
        "bgm_sha256=$(if ($bgmPath) { Get-SlingshotSha256 $bgmPath } else { 'none' })",
        "subtitle_font_size=$SubtitleFontSize",
        "subtitle_bottom_margin=$SubtitleBottomMargin",
        "video_stream=$probe",
        "video_duration_sec=$actualDuration",
        "video_encoder=$selectedEncoder",
        "audio_mix=$(if ($bgmPath) { 'voice_plus_ducked_sfx_plus_ducked_bgm' } else { 'voice_plus_ducked_sfx' })"
    ) -join "`n"
    Move-Item -Force $outputTemp $outputPath
    Write-SlingshotUtf8 ([IO.Path]::ChangeExtension($outputPath, '.manifest.txt')) ($manifest + "`n")
    $succeeded = $true
    Write-Host "episode-reburn: completed $outputPath"
} finally {
    if ($succeeded -and (Test-Path $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    } elseif (-not $succeeded) {
        Write-Warning "Reburn diagnostics preserved at $tempRoot"
    }
}
