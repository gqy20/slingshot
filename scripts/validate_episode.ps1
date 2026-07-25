[CmdletBinding()]
param([Parameter(Mandatory = $true, Position = 0)][string]$Episode)

. (Join-Path $PSScriptRoot 'common.ps1')
$episodePath = (Resolve-Path -LiteralPath $Episode).Path
$godot = Get-SlingshotGodot
Initialize-SlingshotGodotEnvironment
& $godot --headless --path $script:ProjectRoot `
    --script res://scripts/validate_episode.gd -- $episodePath
if ($LASTEXITCODE -ne 0) { throw 'Episode validation failed.' }
