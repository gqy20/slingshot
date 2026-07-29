Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:RenderRoot = Join-Path $script:ProjectRoot 'renders'
$script:RenderWorkRoot = Join-Path $script:RenderRoot 'work'
$script:RenderMasterRoot = Join-Path $script:RenderRoot 'masters'
$script:RenderDeliveryRoot = Join-Path $script:RenderRoot 'deliveries'
$script:RenderArchiveRoot = Join-Path $script:RenderRoot 'archive'
$script:RenderCacheRoot = Join-Path $script:RenderRoot 'cache'

function Get-SlingshotEpisodePaths {
    param([Parameter(Mandatory = $true)][string]$EpisodeId)
    if ($EpisodeId -notmatch '^s\d{2}e\d{2}-[a-z0-9][a-z0-9-]*$') {
        throw "Unsafe episode id: $EpisodeId"
    }
    $work = Join-Path $script:RenderWorkRoot $EpisodeId
    $masters = Join-Path $script:RenderMasterRoot $EpisodeId
    return [pscustomobject]@{
        Id = $EpisodeId
        Work = $work
        Previews = Join-Path $work 'previews'
        Review = Join-Path $work 'review'
        Frames = Join-Path $work 'review\frames'
        Logs = Join-Path $work 'logs'
        Masters = $masters
        MasterAudio = Join-Path $masters 'audio'
        MasterSubtitles = Join-Path $masters 'subtitles'
        PictureCleanMaster = Join-Path $masters 'picture-clean-4k.mp4'
        ProgramMaster = Join-Path $masters 'program-master-4k.mp4'
        Deliveries = Join-Path $script:RenderDeliveryRoot $EpisodeId
        Archive = Join-Path $script:RenderArchiveRoot $EpisodeId
        Cache = Join-Path $script:RenderCacheRoot $EpisodeId
    }
}

function New-SlingshotRenderTempDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Kind,
        [string]$EpisodeId = '_shared'
    )
    $base = Join-Path $script:RenderCacheRoot "tmp\$EpisodeId"
    New-Item -ItemType Directory -Force -Path $base | Out-Null
    $path = Join-Path $base ('.' + $Kind + '-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    return $path
}

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
    $dataRoot = Join-Path $script:RenderCacheRoot 'godot-user'
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
