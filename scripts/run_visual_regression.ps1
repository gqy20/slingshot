[CmdletBinding()]
param(
    [switch]$UpdateBaselines,
    [ValidateSet('projectile', 'impact', 'track')][string[]]$Domain = @()
)

. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-SlingshotGodot
Initialize-SlingshotGodotEnvironment

function Invoke-VisualGodot {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $previousErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $lines = @(& $godot @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorPreference
    $lines | ForEach-Object { Write-Host $_ }
    $text = $lines -join "`n"
    $fatalText = $text `
        -replace '(?m)^.*ERROR: Failed to read the root certificate store\..*\r?\n?', '' `
        -replace '(?m)^\s*at: get_system_ca_certificates.*\r?\n?', ''
    if ($exitCode -ne 0 -or $fatalText -match 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|(?m)^ERROR:') {
        throw "Godot visual-regression step failed (exit=$exitCode)."
    }
}

$baselineRoot = Join-Path $script:ProjectRoot 'tests\visual_baselines'
New-Item -ItemType Directory -Force -Path $baselineRoot | Out-Null
$tempRoot = New-SlingshotRenderTempDirectory -Kind 'visual-regression'
$cases = @(
    @{ Episode = 'content\episodes\s01e03-angle-with-drag.json'; Prefix = 'projectile' },
    @{ Episode = 'content\episodes\s01e04-impact-force-curve.json'; Prefix = 'impact' },
    @{ Episode = 'content\episodes\s01e05-shortest-is-not-fastest.json'; Prefix = 'track' }
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
	}
	foreach ($moment in $moments) {
		$keyframeCount += 1
        $frame = [int][Math]::Floor($moment.Seconds * [double]$config.video.fps + 0.5)
        $caseRoot = Join-Path $tempRoot ($case.Prefix + '-' + $moment.Name)
        New-Item -ItemType Directory -Force -Path $caseRoot | Out-Null
        $moviePath = Join-Path $caseRoot 'frame.png'
        $sidecarPath = Join-Path $caseRoot 'sidecar.json'
        Invoke-VisualGodot -Arguments @(
            '--path', $script:ProjectRoot, '--rendering-method', 'mobile',
            '--rendering-driver', 'vulkan', '--write-movie', $moviePath,
            '--fixed-fps', [string]$config.video.fps, '--disable-vsync',
            'res://episode.tscn', '--', '--episode', $episodePath,
            '--play-record', $recordPath, '--frame-start', [string]$frame,
            '--frame-end', [string]($frame + 1), '--sidecar', $sidecarPath
        )
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
