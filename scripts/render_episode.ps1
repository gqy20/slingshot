[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Episode,
    [Parameter(Position = 1)][string]$Output,
    [int]$Width = 0,
    [int]$Height = 0,
    [switch]$SkipNarration,
    [switch]$SkipSubtitles,
    [switch]$SkipImport,
    [switch]$ShowRenderWindow,
    [switch]$NoFrameCache,
    [int]$CaptureRepeat = 1,
    [ValidateRange(0, 4)][int]$RenderWorkers = 0,
    [ValidateRange(0, 8)][int]$ShardWarmupFrames = 2,
    [ValidateSet('auto', 'nvenc', 'libx264')][string]$VideoEncoder = 'auto',
    [ValidateRange(24, 64)][int]$SubtitleFontSize = 42,
    [ValidateRange(30, 160)][int]$SubtitleBottomMargin = 100,
    [double]$PreviewSeconds = 0,
    [double]$PreviewStartSeconds = 0
)

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'render_shard_planner.ps1')
. (Join-Path $PSScriptRoot 'render_beat_cache.ps1')

$episodePath = (Resolve-Path -LiteralPath $Episode).Path
$config = Get-Content -Raw -Encoding UTF8 $episodePath | ConvertFrom-Json
$episodeName = [string]$config.id
$episodePaths = Get-SlingshotEpisodePaths $episodeName
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
if ($RenderWorkers -eq 0) {
    $RenderWorkers = if ($env:EPISODE_RENDER_WORKERS) {
        [int]$env:EPISODE_RENDER_WORKERS
    } else {
        2
    }
}
if ($fps -notin @(30, 60)) { throw "Video FPS must be 30 or 60; got $fps" }
if ("$sourceWidth,$sourceHeight" -ne '3840,2160') { throw 'Episode source resolution must be 3840x2160.' }
if ("$Width,$Height" -notin @('3840,2160', '1920,1080')) { throw 'Render resolution must be 3840x2160 or 1920x1080.' }
if ($CaptureRepeat -lt 1) { throw 'CaptureRepeat must be positive.' }
if ($RenderWorkers -lt 1 -or $RenderWorkers -gt 4) { throw 'RenderWorkers must be between 1 and 4.' }
if ($PreviewSeconds -lt 0) { throw 'PreviewSeconds cannot be negative.' }
if ($PreviewStartSeconds -lt 0) { throw 'PreviewStartSeconds cannot be negative.' }

$narrationProperty = $config.PSObject.Properties['narration']
$hasNarration = $null -ne $narrationProperty -and $null -ne $narrationProperty.Value -and -not $SkipNarration
$subtitleSrt = $null
if ($hasNarration -and $PreviewStartSeconds -gt 0) {
    throw 'PreviewStartSeconds currently requires -SkipNarration because audio and subtitle offsets must remain exact.'
}
if ($hasNarration) {
    $narrationDir = $episodePaths.MasterAudio
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
    $soundDesignAudio = Join-Path $episodePaths.MasterAudio 'sound-design.wav'
    if (-not (Test-Path $soundDesignAudio)) { throw 'Sound design generation failed.' }
}
if ($null -ne $narrationProperty -and $null -ne $narrationProperty.Value) {
    $editorialSubtitle = [string]$config.narration.subtitle_script
    $timingMode = if ($config.narration.PSObject.Properties['timing_mode']) {
        [string]$config.narration.timing_mode
    } else {
        'continuous'
    }
    # Beat-timed narration gets sentence timings from the actual generated audio.
    # An editorial SRT is only a fallback for continuous narration workflows.
    if ($timingMode -ne 'beats' -and -not [string]::IsNullOrWhiteSpace($editorialSubtitle)) {
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

$defaultOutput = if ($Width -eq 1920) {
    Join-Path $episodePaths.Previews 'episode-preview.mp4'
} else {
    $episodePaths.ProgramMaster
}
if (-not $Output) { $Output = $defaultOutput }
if ([IO.Path]::GetExtension($Output) -ne '.mp4') { throw 'Output path must end in .mp4.' }
$outputPath = if ([IO.Path]::IsPathRooted($Output)) {
    [IO.Path]::GetFullPath($Output)
} else {
    [IO.Path]::GetFullPath((Join-Path (Get-Location) $Output))
}
$outputDir = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$godot = Get-SlingshotGodot
# Start-Process must track the actual Movie Writer process. In recent Windows
# builds the console binary is a launcher which can remain alive after its GUI
# child has finished recording, so waiting on it can deadlock the merge stage.
$godotProcess = $godot
if ($godot.EndsWith('_console.exe', [StringComparison]::OrdinalIgnoreCase)) {
    $guiCandidate = $godot.Substring(0, $godot.Length - '_console.exe'.Length) + '.exe'
    if (Test-Path -LiteralPath $guiCandidate) { $godotProcess = $guiCandidate }
}
$ffmpeg = Find-SlingshotTool -Name 'ffmpeg'
$ffprobe = Find-SlingshotTool -Name 'ffprobe'
Initialize-SlingshotGodotEnvironment

& (Join-Path $PSScriptRoot 'build_formula_assets.ps1') -Episode $episodePath
if ($LASTEXITCODE -ne 0) { throw 'Formula asset build failed.' }
if (-not $SkipImport) {
    Invoke-SlingshotNative $godot --headless --import --path $script:ProjectRoot
}

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
$renderShards = @(Get-SlingshotStoryboardRenderShards -Episode $config -Fps $fps `
    -FrameStart $frameStart -FrameEnd $frameEnd -WorkerCount $RenderWorkers `
    -WarmupFrames $ShardWarmupFrames)
$actualRenderWorkers = $renderShards.Count
$frameCacheEnabled = -not $NoFrameCache -and $PreviewSeconds -le 0 -and $PreviewStartSeconds -le 0
$frameCacheEntries = @()
$frameCacheHits = 0
$frameCacheMisses = 0
$frameCacheFingerprint = 'disabled'
$sidecarCachePath = $null
$tempRoot = New-SlingshotRenderTempDirectory -Kind 'episode' -EpisodeId $episodeName
$shardRoot = Join-Path $tempRoot 'shards'
$frames = Join-Path $tempRoot 'frames'
$recordPath = Join-Path $tempRoot 'run-record.json'
$sidecarPath = Join-Path $tempRoot 'output.json'
$videoTemp = Join-Path $tempRoot 'output.mp4'
$cleanVideoTemp = Join-Path $tempRoot 'clean-master.mp4'
$simulationLog = Join-Path $tempRoot 'simulation.log'
New-Item -ItemType Directory -Force -Path $shardRoot, $frames | Out-Null
$succeeded = $false
$renderJobs = @()

try {
    Write-Host "episode-render: simulate=$episodePath"
    $simulationErrorLog = Join-Path $tempRoot 'simulation.stderr.log'
    $simulationArgs = @('--headless', '--path', $script:ProjectRoot, '--fixed-fps', '120',
        '--disable-vsync', 'res://episode.tscn', '--', '--episode', $episodePath,
        '--simulate-record', $recordPath)
    $simulationProcess = Start-Process -FilePath $godotProcess -ArgumentList $simulationArgs `
        -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $simulationLog `
        -RedirectStandardError $simulationErrorLog
    $simulationExitCode = $simulationProcess.ExitCode
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

    if ($frameCacheEnabled) {
        # Narration and subtitles are mixed after picture capture, so editorial
        # audio changes must not invalidate otherwise identical Beat frames.
        $commonEpisode = $config | Select-Object * -ExcludeProperty beats, narration
        $sourceFingerprint = Get-SlingshotRenderSourceFingerprint -ProjectRoot $script:ProjectRoot
        $commonCacheText = @(
            'picture-cache-schema=2',
            "episode=$($commonEpisode | ConvertTo-Json -Depth 40 -Compress)",
            "record=$(Get-SlingshotSha256 $recordPath)",
            "source=$sourceFingerprint",
            "resolution=${Width}x${Height}",
            "fps=$fps",
            "capture_repeat=$CaptureRepeat"
        ) -join "`n"
        $frameCacheFingerprint = Get-SlingshotTextSha256 $commonCacheText
        $frameCacheEntries = @(Get-SlingshotBeatCacheEntries -Episode $config -Fps $fps `
            -TotalFrames $totalFrames -CacheRoot $episodePaths.Cache `
            -CommonFingerprint $frameCacheFingerprint)
        $allBeatJson = ($frameCacheEntries | ForEach-Object { "$($_.Id)=$($_.Key)" }) -join "`n"
        $sidecarKey = Get-SlingshotTextSha256 "$frameCacheFingerprint|$allBeatJson"
        $sidecarCachePath = Join-Path $episodePaths.Cache "picture-sidecars\$sidecarKey.json"
        foreach ($entry in $frameCacheEntries) {
            $entry.Hit = Test-SlingshotBeatCacheEntry -Entry $entry
            if ($entry.Hit) {
                $frameCacheHits++
                for ($frame = $entry.FrameStart; $frame -lt $entry.FrameEnd; $frame++) {
                    Copy-Item -LiteralPath (Join-Path $entry.Directory ('frame{0:d8}.png' -f $frame)) `
                        -Destination (Join-Path $frames ('frame{0:d8}.png' -f $frame))
                }
            } else {
                $frameCacheMisses++
            }
        }
        $missingEntries = @($frameCacheEntries | Where-Object { -not $_.Hit })
        if ($missingEntries.Count -eq 0 -and (Test-Path -LiteralPath $sidecarCachePath)) {
            Copy-Item -LiteralPath $sidecarCachePath -Destination $sidecarPath
            $renderShards = @()
        } elseif ($missingEntries.Count -eq $frameCacheEntries.Count) {
            # Cold cache keeps the balanced storyboard plan instead of paying
            # one Godot startup for every beat.
        } else {
            if ($missingEntries.Count -eq 0) { $missingEntries = @($frameCacheEntries[0]) }
            $renderShards = @(Merge-SlingshotMissingBeatRanges -Entries $missingEntries `
                -MaximumRanges $RenderWorkers -WarmupFrames $ShardWarmupFrames)
        }
        $actualRenderWorkers = $renderShards.Count
        Write-Host "episode-render: frame-cache hits=$frameCacheHits misses=$frameCacheMisses fingerprint=$frameCacheFingerprint"
    }

    Write-Host "episode-render: render=$outputPath frames=$totalFrames workers=$actualRenderWorkers"
    $ffmpegInputArgs = @('-y', '-loglevel', 'error', '-framerate', [string]$fps,
        '-i', (Join-Path $frames 'frame%08d.png'))
    foreach ($shard in $renderShards) {
        $shardName = 'shard-{0:d2}' -f $shard.Index
        $shardDir = Join-Path $shardRoot $shardName
        $rawFrames = Join-Path $shardDir 'raw-frames'
        $projectView = Join-Path $shardDir 'project'
        $renderLog = Join-Path $shardDir 'render.log'
        $renderErrorLog = Join-Path $shardDir 'render.stderr.log'
        New-Item -ItemType Directory -Force -Path $rawFrames, $projectView | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:ProjectRoot 'project.godot') -Destination $projectView
        Copy-Item -LiteralPath (Join-Path $script:ProjectRoot 'episode.tscn') -Destination $projectView
        foreach ($entry in @('assets', 'content', 'presets', 'src')) {
            New-Item -ItemType Junction -Path (Join-Path $projectView $entry) `
                -Target (Join-Path $script:ProjectRoot $entry) | Out-Null
        }
        # Imported resources are copied once per worker. Sharing this directory
        # lets concurrent Godot processes race while updating import metadata.
        if (Test-Path (Join-Path $script:ProjectRoot '.godot')) {
            Copy-Item -LiteralPath (Join-Path $script:ProjectRoot '.godot') `
                -Destination $projectView -Recurse
        }
        $workerProjectName = "SlingshotRender-$($tempRoot | Split-Path -Leaf)-$($shard.Index)"
        $overrideConfig = @"
[application]
config/name="$workerProjectName"

[display]
window/size/viewport_width=$Width
window/size/viewport_height=$Height
window/stretch/mode="disabled"
"@
        Write-SlingshotUtf8 (Join-Path $projectView 'override.cfg') $overrideConfig

        $moviePath = Join-Path $rawFrames 'frame.png'
        $renderArgs = @('--path', $projectView, '--rendering-method', 'mobile',
            '--rendering-driver', 'vulkan', '--resolution', "${Width}x${Height}",
            '--write-movie', $moviePath, '--fixed-fps', [string]($fps * $CaptureRepeat),
            '--disable-vsync', '--audio-driver', 'Dummy', '--log-file', (Join-Path $shardDir 'godot.log'),
            'res://episode.tscn', '--', '--episode', $episodePath,
            '--play-record', $recordPath, '--render-width', [string]$Width, '--render-height',
            [string]$Height, '--capture-repeat', [string]$CaptureRepeat,
            '--frame-start', [string]$shard.RenderStart, '--frame-end', [string]$shard.FrameEnd)
        if (-not $ShowRenderWindow) {
            $renderArgs = @('--position', '10000,10000') + $renderArgs
        }
        if ($shard.Index -eq 0) { $renderArgs += @('--sidecar', $sidecarPath) }
        if ($hasSubtitles) { $renderArgs += @('--subtitles', $subtitleSrt, '--external-subtitles') }
        Write-Host ("episode-render: {0} frames=[{1},{2}) warmup={3}" -f `
            $shardName, $shard.FrameStart, $shard.FrameEnd, $shard.WarmupFrames)
        $process = Start-Process -FilePath $godotProcess -ArgumentList $renderArgs `
            -PassThru -WindowStyle Hidden -RedirectStandardOutput $renderLog `
            -RedirectStandardError $renderErrorLog
        $renderJobs += [pscustomobject]@{
            Shard = $shard
            Name = $shardName
            RawFrames = $rawFrames
            Log = $renderLog
            ErrorLog = $renderErrorLog
            Process = $process
        }
    }

    foreach ($job in $renderJobs) {
        $job.Process.WaitForExit()
        $job.Process.Refresh()
    }
    foreach ($job in $renderJobs) {
        if (Test-Path $job.ErrorLog) {
            Add-Content -LiteralPath $job.Log -Value (Get-Content -Raw $job.ErrorLog)
        }
        $renderExitCode = $job.Process.ExitCode
        if ($null -ne $renderExitCode -and $renderExitCode -ne 0) {
            Get-Content $job.Log -ErrorAction SilentlyContinue | Select-Object -First 260
            throw "Godot movie writer failed for $($job.Name) (exit=$renderExitCode)."
        }
        $renderText = Get-Content -Raw $job.Log
        $renderFatalText = $renderText `
            -replace '(?m)^.*ERROR: Failed to read the root certificate store\..*\r?\n', '' `
            -replace '(?m)^\s*at: get_system_ca_certificates.*\r?\n', ''
        if ($renderFatalText -match 'SCRIPT ERROR|(?m)^ERROR:') {
            throw "Godot render logged an error. See $($job.Log)"
        }
    }

    $renderedOutputFrames = 0
    foreach ($job in $renderJobs) {
        $generated = @(Get-ChildItem -LiteralPath $job.RawFrames -File -Filter 'frame*.png' | Sort-Object Name)
        $renderedLogicalFrames = $job.Shard.FrameEnd - $job.Shard.RenderStart
        $expectedRaw = $renderedLogicalFrames * $CaptureRepeat
        if ($generated.Count -ne $expectedRaw) {
            throw "$($job.Name) produced $($generated.Count) frames; expected $expectedRaw. Diagnostics: $tempRoot"
        }
        $firstStableFrame = ($job.Shard.WarmupFrames * $CaptureRepeat) + $CaptureRepeat - 1
        $logicalFrame = $job.Shard.FrameStart
        for ($index = $firstStableFrame; $index -lt $generated.Count; $index += $CaptureRepeat) {
            $outputIndex = $logicalFrame - $frameStart
            $destination = Join-Path $frames ('frame{0:d8}.png' -f $outputIndex)
            Move-Item -LiteralPath $generated[$index].FullName -Destination $destination -Force
            $logicalFrame++
            $renderedOutputFrames++
        }
    }
    $finalFrameCount = @(Get-ChildItem -LiteralPath $frames -File -Filter 'frame*.png').Count
    if ($finalFrameCount -ne $totalFrames -or -not (Test-Path $sidecarPath)) {
        throw 'Frame merge or sidecar generation failed.'
    }
    if ($frameCacheEnabled -and $renderJobs.Count -gt 0) {
        foreach ($entry in $frameCacheEntries) {
            New-Item -ItemType Directory -Force -Path $entry.Directory | Out-Null
            for ($frame = $entry.FrameStart; $frame -lt $entry.FrameEnd; $frame++) {
                Copy-Item -LiteralPath (Join-Path $frames ('frame{0:d8}.png' -f $frame)) `
                    -Destination (Join-Path $entry.Directory ('frame{0:d8}.png' -f $frame)) -Force
            }
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $sidecarCachePath) | Out-Null
        Copy-Item -LiteralPath $sidecarPath -Destination $sidecarCachePath -Force
    }

    $videoFilter = $null
    if ($hasSubtitles) {
        $subtitleAss = Join-Path $tempRoot 'subtitles.ass'
        & $ffmpeg -y -loglevel error -i $subtitleSrt $subtitleAss
        if ($LASTEXITCODE -ne 0) { throw 'Subtitle conversion failed.' }
        $assText = Get-Content -Raw -Encoding UTF8 $subtitleAss
        $assText = $assText -replace '(?m)^PlayResX:.*$', 'PlayResX: 1920'
        $assText = $assText -replace '(?m)^PlayResY:.*$', 'PlayResY: 1080'
        $style = "Style: Default,Sarasa Gothic SC,$SubtitleFontSize,&H00E9F0F2,&H00E9F0F2,&H60050608,&H00050608,-1,0,0,0,100,100,0,0,1,2,0,2,190,190,$SubtitleBottomMargin,1"
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

    # Preserve a high-quality, subtitle-free picture master for full 4K renders.
    # Future subtitle, narration, SFX, and BGM changes can then be produced without
    # rerunning Godot's frame capture.
    $preserveCleanMaster = $hasSubtitles -and $Width -eq 3840 -and `
        $PreviewSeconds -le 0 -and $PreviewStartSeconds -le 0
    $cleanMasterPath = $null
    $cleanMasterSha = $null
    $cleanProbe = $null
    if ($preserveCleanMaster) {
        $cleanMasterPath = $episodePaths.PictureCleanMaster
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cleanMasterPath) | Out-Null
        $cleanCodecArgs = if ($selectedEncoder -eq 'h264_nvenc') {
            @('-c:v', 'h264_nvenc', '-preset', 'p6', '-tune', 'hq', '-rc', 'vbr',
                '-cq', '16', '-b:v', '0', '-pix_fmt', 'yuv420p', '-fps_mode', 'cfr', '-r', [string]$fps)
        } else {
            @('-c:v', 'libx264', '-preset', 'medium', '-crf', '14', '-pix_fmt', 'yuv420p',
                '-fps_mode', 'cfr', '-r', [string]$fps)
        }
        & $ffmpeg -y -loglevel error -framerate $fps -i (Join-Path $frames 'frame%08d.png') `
            -t $duration @cleanCodecArgs -movflags +faststart -an $cleanVideoTemp
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $cleanVideoTemp)) {
            throw 'Subtitle-free clean master encoding failed.'
        }
        $cleanProbe = (& $ffprobe -v error -select_streams v:0 `
            -show_entries stream=codec_name,width,height,avg_frame_rate -of csv=p=0 $cleanVideoTemp).Trim()
        if ($cleanProbe -ne "h264,$Width,$Height,$fps/1") {
            throw "Unexpected clean master metadata: $cleanProbe"
        }
        $cleanDuration = [double]((& $ffprobe -v error -show_entries format=duration `
            -of default=nw=1:nk=1 $cleanVideoTemp).Trim())
        if ([Math]::Abs($cleanDuration - $duration) -gt 0.05) {
            throw "Unexpected clean master duration: $cleanDuration (expected $duration)"
        }
        $cleanMasterSha = Get-SlingshotSha256 $cleanVideoTemp
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
        "render_workers=$actualRenderWorkers",
        "render_workers_requested=$RenderWorkers",
        "render_shard_warmup_frames=$ShardWarmupFrames",
        "render_shards=$(($renderShards | ForEach-Object { '({0},{1})' -f $_.FrameStart, $_.FrameEnd }) -join ';')",
        "frame_cache=$(if ($frameCacheEnabled) { 'enabled' } else { 'disabled' })",
        "frame_cache_fingerprint=$frameCacheFingerprint",
        "frame_cache_hits=$frameCacheHits",
        "frame_cache_misses=$frameCacheMisses",
        "frame_cache_rendered_frames=$renderedOutputFrames",
        "capture_repeat=$CaptureRepeat",
        "video_encoder=$selectedEncoder",
        "video_encoder_request=$VideoEncoder",
        "render_sharding=$(if ($actualRenderWorkers -eq 0) { 'beat_cache_only' } elseif ($frameCacheHits -gt 0) { 'beat_cache_miss_ranges' } elseif ($actualRenderWorkers -gt 1) { 'storyboard_beat_boundaries' } else { 'serial_windows' })",
        'deterministic_seeded=true',
        "subtitles=$(if ($hasSubtitles) { 'burned_in' } else { 'none' })",
        "subtitle_font_size=$SubtitleFontSize",
        "subtitle_bottom_margin=$SubtitleBottomMargin",
        "clean_master=$(if ($preserveCleanMaster) { [IO.Path]::GetFileName($cleanMasterPath) } else { 'not_created' })",
        "clean_master_sha256=$(if ($cleanMasterSha) { $cleanMasterSha } else { 'none' })",
        "clean_master_stream=$(if ($cleanProbe) { $cleanProbe } else { 'none' })",
        "clean_master_subtitles=none",
        "clean_master_audio=none",
        "clean_master_purpose=subtitle_audio_bgm_reburn_without_godot",
        $(if ($hasNarration) { 'audio_mix=voice_plus_ducked_beat_sfx' } else { 'audio=none' })
    ) -join "`n"
    $manifestPath = [IO.Path]::ChangeExtension($outputPath, '.manifest.txt')
    $outputSidecar = [IO.Path]::ChangeExtension($outputPath, '.json')
    Move-Item -Force $videoTemp $outputPath
    if ($preserveCleanMaster) {
        Move-Item -Force $cleanVideoTemp $cleanMasterPath
    }
    Move-Item -Force $sidecarPath $outputSidecar
    Write-SlingshotUtf8 $manifestPath ($manifest + "`n")
    $succeeded = $true
    Write-Host "episode-render: completed $outputPath"
    Write-Host "episode-render: analysis $outputSidecar"
    Write-Host "episode-render: manifest $manifestPath"
    if ($preserveCleanMaster) {
        Write-Host "episode-render: clean master $cleanMasterPath"
    }
} finally {
    foreach ($job in $renderJobs) {
        if ($null -ne $job.Process -and -not $job.Process.HasExited) {
            Stop-Process -Id $job.Process.Id -Force -ErrorAction SilentlyContinue
        }
    }
    if ($succeeded -and (Test-Path $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    } elseif (-not $succeeded) {
        Write-Warning "Render diagnostics preserved at $tempRoot"
    }
}
