[CmdletBinding()]
param()

$projectRoot = Split-Path -Parent $PSScriptRoot
& git -C $projectRoot config core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) { throw 'Failed to configure Git hooks.' }
Write-Host 'git-hooks: installed core.hooksPath=.githooks'

