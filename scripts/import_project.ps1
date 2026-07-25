[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-SlingshotGodot
Initialize-SlingshotGodotEnvironment
Invoke-SlingshotNative $godot --headless --import --path $script:ProjectRoot
Write-Host 'godot-import: completed'

