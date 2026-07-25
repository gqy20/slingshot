[CmdletBinding()]
param([switch]$SkipImport)

. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-SlingshotGodot
Initialize-SlingshotGodotEnvironment
if (-not $SkipImport) {
    Invoke-SlingshotNative $godot --headless --import --path $script:ProjectRoot
}
Invoke-SlingshotNative $godot --headless --path $script:ProjectRoot --script res://tests/run_tests.gd

