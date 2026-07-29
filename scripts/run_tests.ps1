[CmdletBinding()]
param([switch]$SkipImport, [switch]$Visual)

. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-SlingshotGodot
Initialize-SlingshotGodotEnvironment

& (Join-Path $script:ProjectRoot 'tests\test_render_shard_planner.ps1')
& (Join-Path $script:ProjectRoot 'tests\test_render_beat_cache.ps1')

function Invoke-GodotTestStep {
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
        throw "Godot test step failed (exit=$exitCode)."
    }
}

if (-not $SkipImport) {
    Invoke-GodotTestStep -Arguments @('--headless', '--import', '--path', $script:ProjectRoot)
}
Invoke-GodotTestStep -Arguments @('--headless', '--path', $script:ProjectRoot, '--script', 'res://tests/run_tests.gd')
if ($Visual) {
    & (Join-Path $PSScriptRoot 'run_visual_regression.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Visual regression failed.' }
}
