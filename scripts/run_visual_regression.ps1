[CmdletBinding()]
param(
    [switch]$UpdateBaselines,
    [switch]$ShowRenderWindow,
    [ValidateSet('projectile', 'impact', 'track', 'orbital')][string[]]$Domain = @()
)

. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-SlingshotGodot
$godotProcess = $godot
if ($godot.EndsWith('_console.exe', [StringComparison]::OrdinalIgnoreCase)) {
    $guiCandidate = $godot.Substring(0, $godot.Length - '_console.exe'.Length) + '.exe'
    if (Test-Path -LiteralPath $guiCandidate) { $godotProcess = $guiCandidate }
}
Initialize-SlingshotGodotEnvironment

function Invoke-VisualGodot {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $logId = [Guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path ([IO.Path]::GetTempPath()) "slingshot-visual-$logId.stdout.log"
    $stderrPath = Join-Path ([IO.Path]::GetTempPath()) "slingshot-visual-$logId.stderr.log"
    try {
        $process = Start-Process -FilePath $godotProcess -ArgumentList $Arguments `
            -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath
        $process.WaitForExit()
        $process.Refresh()
        $exitCode = $process.ExitCode
        $lines = @()
        if (Test-Path -LiteralPath $stdoutPath) { $lines += @(Get-Content $stdoutPath) }
        if (Test-Path -LiteralPath $stderrPath) { $lines += @(Get-Content $stderrPath) }
    } finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
    $lines | ForEach-Object { Write-Host $_ }
    $text = $lines -join "`n"
    $fatalText = $text `
        -replace '(?m)^.*ERROR: Failed to read the root certificate store\..*\r?\n?', '' `
        -replace '(?m)^\s*at: get_system_ca_certificates.*\r?\n?', ''
    if (($null -ne $exitCode -and $exitCode -ne 0) -or $fatalText -match 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|(?m)^ERROR:') {
        throw "Godot visual-regression step failed (exit=$exitCode)."
    }
}

$baselineRoot = Join-Path $script:ProjectRoot 'tests\visual_baselines'
New-Item -ItemType Directory -Force -Path $baselineRoot | Out-Null
$tempRoot = New-SlingshotRenderTempDirectory -Kind 'visual-regression'
$cases = @(
    @{ Episode = 'content\episodes\s01e03-angle-with-drag.json'; Prefix = 'projectile' },
    @{ Episode = 'content\episodes\s01e04-impact-force-curve.json'; Prefix = 'impact' },
    @{ Episode = 'content\episodes\s01e05-shortest-is-not-fastest.json'; Prefix = 'track' },
    @{ Episode = 'content\episodes\s01e06-earth-quasi-satellite.json'; Prefix = 'orbital' }
)
$keyframeCount = 0

foreach ($case in $cases) {
    if ($Domain.Count -gt 0 -and $case.Prefix -notin $Domain) { continue }
    $episodePath = (Resolve-Path -LiteralPath (Join-Path $script:ProjectRoot $case.Episode)).Path
    $config = Get-Content -Raw -Encoding UTF8 $episodePath | ConvertFrom-Json
    $recordPath = Join-Path $tempRoot ($case.Prefix + '-record.json')
    Invoke-VisualGodot -Arguments @(
        '--headless', '--path', $script:ProjectRoot, '--fixed-fps', '120',
        'res://episode.tscn', '--', '--episode', $episodePath,
        '--simulate-record', $recordPath
    )

    $question = [double]$config.story.question_sec
    $explain = [double]$config.story.explain_sec
    $compare = [double]$config.story.compare_sec
    $duration = $question + $explain + [double]$config.story.setup_sec +
        [double]$config.story.flight_sec + $compare
	$moments = @(
        @{ Name = 'question'; Seconds = $question * 0.5 },
        @{ Name = 'explain'; Seconds = $question + $explain * 0.5 },
        @{ Name = 'compare'; Seconds = $duration - $compare * 0.5 }
	)
	if ($case.Prefix -eq 'track') {
		$beatMidpoint = {
			param([string]$BeatId)
			$beat = $config.beats | Where-Object { [string]$_.id -eq $BeatId } | Select-Object -First 1
			if ($null -eq $beat) { throw "Track visual beat not found: $BeatId" }
			[double]$beat.at + 0.5 * [double]$beat.duration
		}
		$beatAtProgress = {
			param([string]$BeatId, [double]$Progress)
			$beat = $config.beats | Where-Object { [string]$_.id -eq $BeatId } | Select-Object -First 1
			if ($null -eq $beat) { throw "Track visual beat not found: $BeatId" }
			[double]$beat.at + $Progress * [double]$beat.duration
		}
		$moments += @(
			@{ Name = 'beat-cold-open'; Seconds = & $beatMidpoint 'cold-open' },
			@{ Name = 'beat-shortest-bet'; Seconds = & $beatMidpoint 'shortest-bet' },
			@{ Name = 'beat-distance-is-not-time'; Seconds = & $beatMidpoint 'distance-is-not-time' },
			@{ Name = 'beat-energy-drop-early'; Seconds = & $beatAtProgress 'energy-drop' 0.25 },
			@{ Name = 'beat-energy-drop-late'; Seconds = & $beatAtProgress 'energy-drop' 0.75 },
			@{ Name = 'beat-time-integral'; Seconds = & $beatMidpoint 'time-integral' },
			@{ Name = 'setup-controls'; Seconds = & $beatMidpoint 'fair-controls' },
			@{ Name = 'beat-track-preview'; Seconds = & $beatMidpoint 'track-preview' },
			@{ Name = 'beat-race-release'; Seconds = & $beatMidpoint 'race-release' },
			@{ Name = 'beat-race-separation'; Seconds = & $beatMidpoint 'race-separation' },
			@{ Name = 'beat-finish-slow-motion'; Seconds = & $beatMidpoint 'finish-slow-motion' },
			@{ Name = 'compare-results'; Seconds = & $beatMidpoint 'distance-time-table' },
			@{ Name = 'beat-cycloid-generation'; Seconds = & $beatMidpoint 'cycloid-generation' },
			@{ Name = 'model-boundary'; Seconds = & $beatMidpoint 'model-boundary' }
		)
		$record = Get-Content -Raw -Encoding UTF8 $recordPath | ConvertFrom-Json
		$arrivals = @($record.records | ForEach-Object {
			[double]$_.metrics.arrival_time_sec
		} | Sort-Object)
		if ($arrivals.Count -ge 2) {
			$flightStart = $question + $explain + [double]$config.story.setup_sec
			$flightDuration = [double]$config.story.flight_sec
			$simulationDuration = [double]$config.simulation.duration_sec
			$toVideoTime = {
				param([double]$simulationTime)
				$flightStart + $simulationTime / $simulationDuration * $flightDuration
			}
			$moments += @(
				@{ Name = 'flight-pre-arrival'; Seconds = & $toVideoTime ([Math]::Max(0.0, $arrivals[0] - 0.06)) },
				@{ Name = 'flight-staggered-arrival'; Seconds = & $toVideoTime ($arrivals[0] + [Math]::Min(0.01, 0.2 * ($arrivals[1] - $arrivals[0]))) },
				@{ Name = 'flight-all-arrived'; Seconds = & $toVideoTime ([Math]::Min($simulationDuration, $arrivals[-1] + 0.08)) }
			)
		}
	} elseif ($case.Prefix -eq 'orbital') {
		$beatMidpoint = {
			param([string]$BeatId)
			$beat = $config.beats | Where-Object { [string]$_.id -eq $BeatId } | Select-Object -First 1
			if ($null -eq $beat) { throw "Orbital visual beat not found: $BeatId" }
			[double]$beat.at + 0.5 * [double]$beat.duration
		}
		$beatAtProgress = {
			param([string]$BeatId, [double]$Progress)
			$beat = $config.beats | Where-Object { [string]$_.id -eq $BeatId } | Select-Object -First 1
			if ($null -eq $beat) { throw "Orbital visual beat not found: $BeatId" }
			[double]$beat.at + $Progress * [double]$beat.duration
		}
		$moments += @(
			@{ Name = 'beat-cold-open'; Seconds = & $beatMidpoint 'cold-open' },
			@{ Name = 'beat-earth-frame'; Seconds = & $beatMidpoint 'earth-frame' },
			@{ Name = 'beat-sun-reveal'; Seconds = & $beatMidpoint 'sun-reveal' },
			@{ Name = 'beat-speed-change'; Seconds = & $beatMidpoint 'speed-change' },
			@{ Name = 'beat-reference-frames'; Seconds = & $beatAtProgress 'same-state-two-frames' 0.72 },
			@{ Name = 'beat-resonance'; Seconds = & $beatMidpoint 'resonance-boundary' },
			@{ Name = 'beat-moon-comparison'; Seconds = & $beatMidpoint 'moon-comparison' },
			@{ Name = 'beat-rendezvous'; Seconds = & $beatMidpoint 'rendezvous' },
			@{ Name = 'beat-optical-navigation'; Seconds = & $beatMidpoint 'optical-navigation' },
			@{ Name = 'beat-science-close'; Seconds = & $beatAtProgress 'science-close' 0.58 },
			@{ Name = 'beat-outro'; Seconds = & $beatAtProgress 'science-close' 0.90 }
		)
	}
	foreach ($moment in $moments) {
		$keyframeCount += 1
        $frame = [int][Math]::Floor($moment.Seconds * [double]$config.video.fps + 0.5)
        $caseRoot = Join-Path $tempRoot ($case.Prefix + '-' + $moment.Name)
        New-Item -ItemType Directory -Force -Path $caseRoot | Out-Null
        $moviePath = Join-Path $caseRoot 'frame.png'
        $sidecarPath = Join-Path $caseRoot 'sidecar.json'
        $renderArguments = @(
            '--path', $script:ProjectRoot, '--rendering-method', 'mobile',
            '--rendering-driver', 'vulkan', '--write-movie', $moviePath,
            '--fixed-fps', [string]$config.video.fps, '--disable-vsync', '--audio-driver', 'Dummy',
            'res://episode.tscn', '--', '--episode', $episodePath,
            '--play-record', $recordPath, '--frame-start', [string]$frame,
            '--frame-end', [string]($frame + 1), '--sidecar', $sidecarPath
        )
        if (-not $ShowRenderWindow) {
            $renderArguments = @('--position', '10000,10000') + $renderArguments
        }
        Invoke-VisualGodot -Arguments $renderArguments
        $actualPath = Join-Path $caseRoot 'frame00000000.png'
        if (-not (Test-Path -LiteralPath $actualPath)) {
            throw "Visual-regression frame was not generated: $actualPath"
        }
        $baselinePath = Join-Path $baselineRoot ($case.Prefix + '-' + $moment.Name + '.png')
        if ($UpdateBaselines) {
            Copy-Item -LiteralPath $actualPath -Destination $baselinePath -Force
            Write-Host "visual-regression: updated $baselinePath"
        } elseif (-not (Test-Path -LiteralPath $baselinePath)) {
            throw "Missing visual baseline: $baselinePath. Run with -UpdateBaselines."
        } else {
            Invoke-VisualGodot -Arguments @(
                '--headless', '--path', $script:ProjectRoot,
                '--script', 'res://scripts/compare_images.gd', '--',
                $baselinePath, $actualPath
            )
        }
    }
}

Write-Host "visual-regression: $keyframeCount keyframes passed"
