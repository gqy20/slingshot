[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Episode,
    [Parameter(Position = 1)][string]$Output,
    [int]$Width = 0,
    [int]$Height = 0,
    [switch]$SkipNarration,
    [int]$CaptureRepeat = 2
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

$narrationProperty = $config.PSObject.Properties['narration']
$hasNarration = $null -ne $narrationProperty -and $null -ne $narrationProperty.Value -and -not $SkipNarration
if ($hasNarration) {
    $narrationDir = Join-Path $script:RenderRoot "narration\$episodeName"
    $narrationSource = Join-Path $narrationDir 'narration.mp3'
    $narrationAudio = Join-Path $narrationDir 'narration-normalized.wav'
    $subtitleSrt = Join-Path $narrationDir 'narration.srt'
    foreach ($asset in @($narrationSource, $narrationAudio, $subtitleSrt)) {
        if (-not (Test-Path $asset)) {
            throw "Narration asset missing: $asset. Run: .\scripts\generate_narration.ps1 $episodePath"
        }
    }
    & (Join-Path $PSScriptRoot 'build_sound_design.ps1') -Episode $episodePath
    $soundDesignAudio = Join-Path $script:RenderRoot "audio\$episodeName\sound-design.wav"
    if (-not (Test-Path $soundDesignAudio)) { throw 'Sound design generation failed.' }
}

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

$duration = Get-SlingshotEpisodeDuration $config
$totalFrames = [int][Math]::Floor($duration * $fps + 0.5)
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
        [string]$Height, '--capture-repeat', [string]$CaptureRepeat, '--frame-start', '0',
        '--frame-end', [string]$totalFrames, '--sidecar', $sidecarPath)
    if ($hasNarration) {
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

    if ($hasNarration) {
        $subtitleAss = Join-Path $tempRoot 'subtitles.ass'
        & $ffmpeg -y -loglevel error -i $subtitleSrt $subtitleAss
        if ($LASTEXITCODE -ne 0) { throw 'Subtitle conversion failed.' }
        $assText = Get-Content -Raw -Encoding UTF8 $subtitleAss
        $assText = $assText -replace '(?m)^PlayResX:.*$', 'PlayResX: 1920'
        $assText = $assText -replace '(?m)^PlayResY:.*$', 'PlayResY: 1080'
        $style = 'Style: Default,Sarasa Gothic SC,26,&H00E9F0F2,&H00E9F0F2,&HC0050608,&H00050608,-1,0,0,0,100,100,0,0,1,0,1,2,190,190,48,1'
        $assText = $assText -replace '(?m)^Style: Default,.*$', $style
        Write-SlingshotUtf8 $subtitleAss $assText
        $assFilterPath = $subtitleAss.Replace('\', '/').Replace(':', '\:').Replace("'", "\'")
        $fontFilterPath = (Join-Path $script:ProjectRoot 'assets\fonts').Replace('\', '/').Replace(':', '\:').Replace("'", "\'")
        $filter = "[0:v]subtitles=filename='$assFilterPath':fontsdir='$fontFilterPath'[vout];" +
            '[2:a]volume=0.40[sfx];[sfx][1:a]sidechaincompress=threshold=0.015:ratio=8:attack=15:release=300[sfxduck];' +
            '[1:a][sfxduck]amix=inputs=2:duration=longest:normalize=0,alimiter=limit=0.78:level=false[aout]'
        & $ffmpeg -y -loglevel error -framerate $fps `
            -i (Join-Path $frames 'frame%08d.png') -i $narrationAudio -i $soundDesignAudio `
            -t $duration -filter_complex $filter -map '[vout]' -map '[aout]' `
            -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p `
            -c:a aac -b:a 192k -movflags +faststart $videoTemp
    } else {
        & $ffmpeg -y -loglevel error -framerate $fps `
            -i (Join-Path $frames 'frame%08d.png') -t $duration `
            -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p `
            -movflags +faststart -an $videoTemp
    }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $videoTemp)) {
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
        "engine=$((& $godot --version | Select-Object -First 1))",
        'renderer=mobile_vulkan_windows',
        "render_resolution=${Width}x${Height}",
        'render_workers=1',
        "capture_repeat=$CaptureRepeat",
        'render_sharding=serial_windows',
        'deterministic_seeded=true',
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
