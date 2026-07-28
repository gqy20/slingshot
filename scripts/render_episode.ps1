[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Episode,
    [Parameter(Position = 1)][string]$Output,
    [int]$Width = 0,
    [int]$Height = 0,
    [switch]$SkipNarration,
    [switch]$SkipSubtitles,
    [int]$CaptureRepeat = 1,
    [ValidateSet('auto', 'nvenc', 'libx264')][string]$VideoEncoder = 'auto',
    [double]$PreviewSeconds = 0,
    [double]$PreviewStartSeconds = 0
)

. (Join-Path $PSScriptRoot 'common.ps1')

$episodePath = (Resolve-Path -LiteralPath $Episode).Path
$config = Get-Content -Raw -Encoding UTF8 $episodePath | ConvertFrom-Json
$episodeName = [IO.Path]::GetFileNameWithoutExtension($episodePath)
$fps = [int]$config.video.fps
$sourceWidth = [int]$config.video.width
$sourceHeight = [int]$config.video.height
if ($Width -eq 0) {
    $Width = if ($env:EPISODE_RENDER_WIDTH) { [int]$env:EPISODE_RENDER_WIDTH } else { $sourceWidth }
}
if ($Height -eq 0) {
    $Height = if ($env:EPISODE_RENDER_HEIGHT) { [int]$env:EPISODE_RENDER_HEIGHT } else { $sourceHeight }
}
if ($env:EPISODE_SKIP_NARRATION -eq '1') { $SkipNarration = $true }
if ($fps -notin @(30, 60)) { throw "Video FPS must be 30 or 60; got $fps" }
if ("$sourceWidth,$sourceHeight" -ne '3840,2160') { throw 'Episode source resolution must be 3840x2160.' }
if ("$Width,$Height" -notin @('3840,2160', '1920,1080')) { throw 'Render resolution must be 3840x2160 or 1920x1080.' }
if ($CaptureRepeat -lt 1) { throw 'CaptureRepeat must be positive.' }
if ($PreviewSeconds -lt 0) { throw 'PreviewSeconds cannot be negative.' }
if ($PreviewStartSeconds -lt 0) { throw 'PreviewStartSeconds cannot be negative.' }

$narrationProperty = $config.PSObject.Properties['narration']
$hasNarration = $null -ne $narrationProperty -and $null -ne $narrationProperty.Value -and -not $SkipNarration
$subtitleSrt = $null
if ($hasNarration -and $PreviewStartSeconds -gt 0) {
    throw 'PreviewStartSeconds currently requires -SkipNarration because audio and subtitle offsets must remain exact.'
}
if ($hasNarration) {
    $narrationDir = Join-Path $script:RenderRoot "narration\$episodeName"
    $narrationSource = Join-Path $narrationDir 'narration.mp3'
    $narrationAudio = Join-Path $narrationDir 'narration-normalized.wav'
    $generatedSubtitleSrt = Join-Path $narrationDir 'narration.srt'
    $subtitleSrt = $generatedSubtitleSrt
    foreach ($asset in @($narrationSource, $narrationAudio, $generatedSubtitleSrt)) {
        if (-not (Test-Path $asset)) {
            throw "Narration asset missing: $asset. Run: .\scripts\generate_narration.ps1 $episodePath"
        }
    }
    & (Join-Path $PSScriptRoot 'build_sound_design.ps1') -Episode $episodePath
    $soundDesignAudio = Join-Path $script:RenderRoot "audio\$episodeName\sound-design.wav"
    if (-not (Test-Path $soundDesignAudio)) { throw 'Sound design generation failed.' }
}
if ($null -ne $narrationProperty -and $null -ne $narrationProperty.Value) {
    $editorialSubtitle = [string]$config.narration.subtitle_script
    if (-not [string]::IsNullOrWhiteSpace($editorialSubtitle)) {
        if (-not $editorialSubtitle.StartsWith('res://') -or $editorialSubtitle.Contains('..')) {
            throw "Unsafe narration.subtitle_script: $editorialSubtitle"
        }
        $subtitleSrt = Join-Path $script:ProjectRoot $editorialSubtitle.Substring(6).Replace('/', '\')
        if (-not (Test-Path -LiteralPath $subtitleSrt)) {
            throw "Editorial subtitle asset missing: $subtitleSrt"
        }
    }
}
if ($SkipSubtitles) { $subtitleSrt = $null }
$hasSubtitles = -not [string]::IsNullOrWhiteSpace([string]$subtitleSrt)

$outputDir = if ($Width -eq 1920) { Join-Path $script:RenderRoot 'previews' } else { Join-Path $script:RenderRoot 'final' }
if (-not $Output) { $Output = Join-Path $outputDir "$episodeName.mp4" }
if ([IO.Path]::GetExtension($Output) -ne '.mp4') { throw 'Output path must end in .mp4.' }
$outputPath = if ([IO.Path]::IsPathRooted($Output)) {
    [IO.Path]::GetFullPath($Output)
} else {
    [IO.Path]::GetFullPath((Join-Path (Get-Location) $Output))
}
$outputDir = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$godot = Get-SlingshotGodot
$godotProcess = $godot -replace '_console\.exe$', '.exe'
if (-not (Test-Path -LiteralPath $godotProcess)) { $godotProcess = $godot }
$ffmpeg = Find-SlingshotTool -Name 'ffmpeg'
$ffprobe = Find-SlingshotTool -Name 'ffprobe'
Initialize-SlingshotGodotEnvironment

& (Join-Path $PSScriptRoot 'build_formula_assets.ps1') -Episode $episodePath
if ($LASTEXITCODE -ne 0) { throw 'Formula asset build failed.' }
Invoke-SlingshotNative $godot --headless --import --path $script:ProjectRoot

$episodeDuration = Get-SlingshotEpisodeDuration $config
$previewStart = [Math]::Min($PreviewStartSeconds, $episodeDuration)
$duration = if ($PreviewSeconds -gt 0) {
    [Math]::Min($PreviewSeconds, $episodeDuration - $previewStart)
} else {
    $episodeDuration - $previewStart
}
$frameStart = [int][Math]::Floor($previewStart * $fps + 0.5)
$totalFrames = [int][Math]::Floor($duration * $fps + 0.5)
if ($totalFrames -lt 1) { throw 'Preview range does not contain any frames.' }
$frameEnd = $frameStart + $totalFrames
$tempRoot = Join-Path $script:RenderRoot ('.episode-tmp-' + [Guid]::NewGuid().ToString('N'))
$rawFrames = Join-Path $tempRoot 'raw-frames'
$frames = Join-Path $tempRoot 'frames'
$recordPath = Join-Path $tempRoot 'run-record.json'
$sidecarPath = Join-Path $tempRoot 'output.json'
$videoTemp = Join-Path $tempRoot 'output.mp4'
$simulationLog = Join-Path $tempRoot 'simulation.log'
$renderLog = Join-Path $tempRoot 'render.log'
$projectView = Join-Path $tempRoot 'project'
New-Item -ItemType Directory -Force -Path $rawFrames, $frames, $projectView | Out-Null
Copy-Item -LiteralPath (Join-Path $script:ProjectRoot 'project.godot') -Destination $projectView
Copy-Item -LiteralPath (Join-Path $script:ProjectRoot 'episode.tscn') -Destination $projectView
foreach ($entry in @('assets', 'content', 'presets', 'src')) {
    New-Item -ItemType Junction -Path (Join-Path $projectView $entry) `
        -Target (Join-Path $script:ProjectRoot $entry) | Out-Null
}
if (Test-Path (Join-Path $script:ProjectRoot '.godot')) {
    New-Item -ItemType Junction -Path (Join-Path $projectView '.godot') `
        -Target (Join-Path $script:ProjectRoot '.godot') | Out-Null
}
$overrideConfig = @"
[display]
window/size/viewport_width=$Width
window/size/viewport_height=$Height
window/stretch/mode="disabled"
"@
Write-SlingshotUtf8 (Join-Path $projectView 'override.cfg') $overrideConfig
$succeeded = $false

try {
    Write-Host "episode-render: simulate=$episodePath"
    $simulationErrorLog = Join-Path $tempRoot 'simulation.stderr.log'
    $simulationArgs = @('--headless', '--path', $script:ProjectRoot, '--fixed-fps', '120',
        '--disable-vsync', 'res://episode.tscn', '--', '--episode', $episodePath,
        '--simulate-record', $recordPath)
    $simulationBatch = Join-Path $tempRoot 'simulate.cmd'
    $simulationCommand = 'start "" /wait /b "' + $godotProcess + '" ' + (($simulationArgs | ForEach-Object {
        '"' + ([string]$_).Replace('"', '""') + '"'
    }) -join ' ') + ' >"' + $simulationLog + '" 2>"' + $simulationErrorLog + '"'
    Write-SlingshotUtf8 $simulationBatch ("@echo off`r`n$simulationCommand`r`nexit /b %errorlevel%`r`n")
    & $env:ComSpec /d /c $simulationBatch
    $simulationExitCode = $LASTEXITCODE
    if (Test-Path $simulationErrorLog) {
        Add-Content -LiteralPath $simulationLog -Value (Get-Content -Raw $simulationErrorLog)
    }
    if ($simulationExitCode -ne 0 -or -not (Test-Path $recordPath)) {
        Get-Content $simulationLog -ErrorAction SilentlyContinue | Select-Object -First 260
        throw 'Godot simulation failed.'
    }
    $simulationText = Get-Content -Raw $simulationLog
    $simulationFatalText = $simulationText `
        -replace '(?m)^.*ERROR: Failed to read the root certificate store\..*\r?\n', '' `
        -replace '(?m)^\s*at: get_system_ca_certificates.*\r?\n', ''
    if ($simulationFatalText -match 'SCRIPT ERROR|(?m)^ERROR:') {
        throw "Godot simulation logged an error. See $simulationLog"
    }

    Write-Host "episode-render: render=$outputPath frames=$totalFrames"
    $moviePath = Join-Path $rawFrames 'frame.png'
    $renderErrorLog = Join-Path $tempRoot 'render.stderr.log'
    $renderArgs = @('--path', $projectView, '--rendering-method', 'mobile',
        '--rendering-driver', 'vulkan', '--resolution', "${Width}x${Height}",
        '--write-movie', $moviePath, '--fixed-fps', [string]($fps * $CaptureRepeat),
        '--disable-vsync', 'res://episode.tscn', '--', '--episode', $episodePath,
        '--play-record', $recordPath, '--render-width', [string]$Width, '--render-height',
        [string]$Height, '--capture-repeat', [string]$CaptureRepeat, '--frame-start', [string]$frameStart,
        '--frame-end', [string]$frameEnd, '--sidecar', $sidecarPath)
    $ffmpegInputArgs = @('-y', '-loglevel', 'error', '-framerate', [string]$fps,
        '-i', (Join-Path $frames 'frame%08d.png'))
    if ($hasSubtitles) {
        $renderArgs += @('--subtitles', $subtitleSrt, '--external-subtitles')
    }
    $renderBatch = Join-Path $tempRoot 'render.cmd'
    $renderCommand = 'start "" /wait /b "' + $godotProcess + '" ' + (($renderArgs | ForEach-Object {
        '"' + ([string]$_).Replace('"', '""') + '"'
    }) -join ' ') + ' >"' + $renderLog + '" 2>"' + $renderErrorLog + '"'
    Write-SlingshotUtf8 $renderBatch ("@echo off`r`n$renderCommand`r`nexit /b %errorlevel%`r`n")
    & $env:ComSpec /d /c $renderBatch
    $renderExitCode = $LASTEXITCODE
    if (Test-Path $renderErrorLog) {
        Add-Content -LiteralPath $renderLog -Value (Get-Content -Raw $renderErrorLog)
    }
    if ($renderExitCode -ne 0) {
        Get-Content $renderLog -ErrorAction SilentlyContinue | Select-Object -First 260
        throw 'Godot movie writer failed.'
    }
    $renderText = Get-Content -Raw $renderLog
    $renderFatalText = $renderText `
        -replace '(?m)^.*ERROR: Failed to read the root certificate store\..*\r?\n', '' `
        -replace '(?m)^\s*at: get_system_ca_certificates.*\r?\n', ''
    if ($renderFatalText -match 'SCRIPT ERROR|(?m)^ERROR:') {
        throw "Godot render logged an error. See $renderLog"
    }

    $generated = @(Get-ChildItem -LiteralPath $rawFrames -File -Filter 'frame*.png' | Sort-Object Name)
    $expectedRaw = $totalFrames * $CaptureRepeat
    if ($generated.Count -ne $expectedRaw) {
        throw "Godot produced $($generated.Count) frames; expected $expectedRaw. Diagnostics: $tempRoot"
    }
    $merged = 0
    for ($index = $CaptureRepeat - 1; $index -lt $generated.Count; $index += $CaptureRepeat) {
        $destination = Join-Path $frames ('frame{0:d8}.png' -f $merged)
        Move-Item -LiteralPath $generated[$index].FullName -Destination $destination
        $merged++
    }
    if ($merged -ne $totalFrames -or -not (Test-Path $sidecarPath)) {
        throw 'Frame merge or sidecar generation failed.'
    }

    $videoFilter = $null
    if ($hasSubtitles) {
        $subtitleAss = Join-Path $tempRoot 'subtitles.ass'
        & $ffmpeg -y -loglevel error -i $subtitleSrt $subtitleAss
        if ($LASTEXITCODE -ne 0) { throw 'Subtitle conversion failed.' }
        $assText = Get-Content -Raw -Encoding UTF8 $subtitleAss
        $assText = $assText -replace '(?m)^PlayResX:.*$', 'PlayResX: 1920'
        $assText = $assText -replace '(?m)^PlayResY:.*$', 'PlayResY: 1080'
        $style = 'Style: Default,Sarasa Gothic SC,36,&H00E9F0F2,&H00E9F0F2,&H60050608,&H00050608,-1,0,0,0,100,100,0,0,1,2,0,2,190,190,60,1'
        $assText = $assText -replace '(?m)^Style: Default,.*$', $style
        Write-SlingshotUtf8 $subtitleAss $assText
        $assFilterPath = $subtitleAss.Replace('\', '/').Replace(':', '\:').Replace("'", "\'")
        $fontFilterPath = (Join-Path $script:ProjectRoot 'assets\fonts').Replace('\', '/').Replace(':', '\:').Replace("'", "\'")
        $subtitleClock = if ($previewStart -gt 0) {
            "setpts=PTS+$previewStart/TB,subtitles=filename='$assFilterPath':fontsdir='$fontFilterPath',setpts=PTS-STARTPTS"
        } else {
            "subtitles=filename='$assFilterPath':fontsdir='$fontFilterPath'"
        }
        $videoFilter = "[0:v]$subtitleClock[vout]"
    }
    if ($hasNarration) {
        $filter = $(if ($videoFilter) { "$videoFilter;" } else { '' }) +
            '[2:a]volume=0.40[sfx];[sfx][1:a]sidechaincompress=threshold=0.015:ratio=8:attack=15:release=300[sfxduck];' +
            '[1:a][sfxduck]amix=inputs=2:duration=longest:normalize=0,alimiter=limit=0.78:level=false[premaster];' +
            '[premaster]loudnorm=I=-16:TP=-1:LRA=7[aout]'
        $ffmpegInputArgs += @('-i', $narrationAudio, '-i', $soundDesignAudio,
            '-t', [string]$duration, '-filter_complex', $filter,
            '-map', $(if ($videoFilter) { '[vout]' } else { '0:v' }), '-map', '[aout]')
    } elseif ($videoFilter) {
        $ffmpegInputArgs += @('-t', [string]$duration, '-filter_complex', $videoFilter,
            '-map', '[vout]')
    } else {
        $ffmpegInputArgs += @('-t', [string]$duration)
    }

    $encoderList = (& $ffmpeg -hide_banner -encoders 2>&1) -join "`n"
    $nvencAvailable = $encoderList -match '(?m)^\s*V\S*\s+h264_nvenc\s'
    $encoderCandidates = switch ($VideoEncoder) {
        'auto' { if ($nvencAvailable) { @('h264_nvenc', 'libx264') } else { @('libx264') }; break }
        'nvenc' {
            if (-not $nvencAvailable) { throw 'h264_nvenc is not available in this FFmpeg build.' }
            @('h264_nvenc')
            break
        }
        'libx264' { @('libx264'); break }
    }
    $selectedEncoder = $null
    foreach ($candidate in $encoderCandidates) {
        if (Test-Path $videoTemp) { Remove-Item -LiteralPath $videoTemp -Force }
        $codecArgs = if ($candidate -eq 'h264_nvenc') {
            @('-c:v', 'h264_nvenc', '-preset', 'p6', '-tune', 'hq', '-rc', 'vbr',
                '-cq', '19', '-b:v', '0', '-pix_fmt', 'yuv420p', '-fps_mode', 'cfr', '-r', [string]$fps)
        } else {
            @('-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p',
                '-fps_mode', 'cfr', '-r', [string]$fps)
        }
        $outputArgs = if ($hasNarration) {
            @('-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '1',
                '-movflags', '+faststart', $videoTemp)
        } else {
            @('-movflags', '+faststart', '-an', $videoTemp)
        }
        & $ffmpeg @ffmpegInputArgs @codecArgs @outputArgs
        if ($LASTEXITCODE -eq 0 -and (Test-Path $videoTemp)) {
            $selectedEncoder = $candidate
            break
        }
        if ($VideoEncoder -eq 'auto' -and $candidate -eq 'h264_nvenc') {
            Write-Warning 'NVENC encoding failed; retrying with libx264.'
        }
    }
    if (-not $selectedEncoder -or -not (Test-Path $videoTemp)) {
        throw 'FFmpeg video encoding failed.'
    }

    $probe = (& $ffprobe -v error -select_streams v:0 `
        -show_entries stream=codec_name,width,height,avg_frame_rate -of csv=p=0 $videoTemp).Trim()
    if ($probe -ne "h264,$Width,$Height,$fps/1") { throw "Unexpected video metadata: $probe" }
    $actualDuration = [double]((& $ffprobe -v error -show_entries format=duration `
        -of default=nw=1:nk=1 $videoTemp).Trim())
    if ([Math]::Abs($actualDuration - $duration) -gt 0.05) {
        throw "Unexpected video duration: $actualDuration (expected $duration)"
    }

    $manifest = @(
        "episode=$([IO.Path]::GetFileName($episodePath))",
        "episode_sha256=$(Get-SlingshotSha256 $episodePath)",
        "record_sha256=$(Get-SlingshotSha256 $recordPath)",
        "video_sha256=$(Get-SlingshotSha256 $videoTemp)",
        "video_stream=$probe",
        "video_duration_sec=$actualDuration",
        "episode_duration_sec=$episodeDuration",
        "preview_seconds=$PreviewSeconds",
        "engine=$((& $godot --version | Select-Object -First 1))",
        'renderer=mobile_vulkan_windows',
        "render_resolution=${Width}x${Height}",
        'render_workers=1',
        "capture_repeat=$CaptureRepeat",
        "video_encoder=$selectedEncoder",
        "video_encoder_request=$VideoEncoder",
        'render_sharding=serial_windows',
        'deterministic_seeded=true',
        "subtitles=$(if ($hasSubtitles) { 'burned_in' } else { 'none' })",
        $(if ($hasNarration) { 'audio_mix=voice_plus_ducked_beat_sfx' } else { 'audio=none' })
    ) -join "`n"
    $manifestPath = [IO.Path]::ChangeExtension($outputPath, '.manifest.txt')
    $outputSidecar = [IO.Path]::ChangeExtension($outputPath, '.json')
    Move-Item -Force $videoTemp $outputPath
    Move-Item -Force $sidecarPath $outputSidecar
    Write-SlingshotUtf8 $manifestPath ($manifest + "`n")
    $succeeded = $true
    Write-Host "episode-render: completed $outputPath"
    Write-Host "episode-render: analysis $outputSidecar"
    Write-Host "episode-render: manifest $manifestPath"
} finally {
    if ($succeeded -and (Test-Path $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    } elseif (-not $succeeded) {
        Write-Warning "Render diagnostics preserved at $tempRoot"
    }
}
