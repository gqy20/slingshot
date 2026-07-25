Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:RenderRoot = Join-Path $script:ProjectRoot 'renders'

function Find-SlingshotTool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$Fallback = @()
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($candidate in $Fallback) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "Missing required command: $Name"
}

function Get-SlingshotGodot {
    if ($env:GODOT_BIN) {
        if (-not (Test-Path -LiteralPath $env:GODOT_BIN)) { throw "GODOT_BIN not found: $env:GODOT_BIN" }
        return (Resolve-Path -LiteralPath $env:GODOT_BIN).Path
    }
    $preferred = @(
        (Join-Path $HOME '.local\bin\Godot_v4.7.1-stable_win64_console.exe'),
        'C:\Users\gqy17\.local\bin\Godot_v4.7.1-stable_win64_console.exe'
    )
    foreach ($candidate in $preferred) {
        if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    return Find-SlingshotTool -Name 'godot'
}

function Initialize-SlingshotGodotEnvironment {
    $dataRoot = Join-Path $script:RenderRoot '.godot-user'
    New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null
    $env:APPDATA = $dataRoot
    $env:LOCALAPPDATA = $dataRoot
}

function Invoke-SlingshotNative {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath"
    }
}

function Write-SlingshotUtf8 {
    param([string]$Path, [string]$Text)
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Get-SlingshotSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-SlingshotEpisodeDuration {
    param($Episode)
    $explain = if ($null -eq $Episode.story.explain_sec) { 0.0 } else { [double]$Episode.story.explain_sec }
    return [double]$Episode.story.question_sec + $explain +
        [double]$Episode.story.setup_sec + [double]$Episode.story.flight_sec +
        [double]$Episode.story.compare_sec
}
