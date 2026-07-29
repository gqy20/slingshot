[CmdletBinding()]
param(
    [int]$Jobs = 1,
    [string]$OutputDirectory,
    [switch]$DryRun,
    [switch]$SkipNarration,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Episode = @()
)

. (Join-Path $PSScriptRoot 'common.ps1')
if ($Jobs -lt 1) { throw 'Jobs must be positive.' }
if ($Episode.Count -eq 0) {
    $Episode = @(Get-ChildItem (Join-Path $script:ProjectRoot 'content\episodes') `
        -File -Filter 's??e??-*.json' | Sort-Object Name | ForEach-Object FullName)
}
if ($Episode.Count -eq 0) { throw 'No production episodes found.' }

$preview = $env:EPISODE_RENDER_WIDTH -eq '1920' -and $env:EPISODE_RENDER_HEIGHT -eq '1080'
if ($OutputDirectory) { New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null }
Write-Host "batch-render: jobs=$Jobs episodes=$($Episode.Count) output=$(if ($OutputDirectory) { $OutputDirectory } else { 'episode-scoped defaults' })"
if ($Jobs -gt 1) {
    Write-Warning 'Windows rendering is intentionally serial to keep Movie Writer output deterministic.'
}
if ($DryRun) { return }

foreach ($episodePath in $Episode) {
    if ($OutputDirectory) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($episodePath)
        $output = Join-Path $OutputDirectory "$stem.mp4"
        & (Join-Path $PSScriptRoot 'render_episode.ps1') -Episode $episodePath `
            -Output $output -SkipNarration:$SkipNarration
    } else {
        & (Join-Path $PSScriptRoot 'render_episode.ps1') -Episode $episodePath `
            -SkipNarration:$SkipNarration
    }
}
Write-Host "batch-render: completed $($Episode.Count) episode(s)"
