[CmdletBinding(SupportsShouldProcess)]
param()

. (Join-Path $PSScriptRoot 'common.ps1')

$resolvedRenderRoot = [IO.Path]::GetFullPath($script:RenderRoot)
$expectedRenderRoot = [IO.Path]::GetFullPath((Join-Path $script:ProjectRoot 'renders'))
if ($resolvedRenderRoot -ne $expectedRenderRoot -or -not (Test-Path -LiteralPath $resolvedRenderRoot)) {
    throw "Unsafe render root: $resolvedRenderRoot"
}

function Move-SlingshotPath {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Source)) { return }
    if (Test-Path -LiteralPath $Destination) {
        throw "Migration destination already exists: $Destination"
    }
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    if ($PSCmdlet.ShouldProcess($Source, "Move to $Destination")) {
        Move-Item -LiteralPath $Source -Destination $Destination
    }
}

function Move-SlingshotDirectoryContents {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { return }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        Move-SlingshotPath $item.FullName (Join-Path $Destination $item.Name)
    }
}

$ep01 = Get-SlingshotEpisodePaths 's01e01-angle-sweep'
$ep03 = Get-SlingshotEpisodePaths 's01e03-angle-with-drag'
$ep04 = Get-SlingshotEpisodePaths 's01e04-impact-force-curve'
foreach ($path in @(
    $script:RenderWorkRoot, $script:RenderMasterRoot, $script:RenderDeliveryRoot,
    $script:RenderArchiveRoot, $script:RenderCacheRoot,
    $ep01.Previews, $ep01.Review, $ep01.MasterAudio, $ep01.Deliveries, $ep01.Archive,
    $ep03.Previews, $ep03.Review, $ep03.MasterAudio, $ep03.Deliveries, $ep03.Archive,
    $ep04.Previews, $ep04.Review, $ep04.MasterAudio, $ep04.Deliveries, $ep04.Archive
)) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
}

# Current masters.
$oldFinal = Join-Path $script:RenderRoot 'final'
Move-SlingshotPath (Join-Path $oldFinal 's01e03-angle-with-drag.mp4') $ep03.ProgramMaster
Move-SlingshotPath (Join-Path $oldFinal 's01e03-angle-with-drag.json') `
    (Join-Path $ep03.Masters 'program-master-4k.json')
Move-SlingshotPath (Join-Path $oldFinal 's01e03-angle-with-drag.manifest.txt') `
    (Join-Path $ep03.Masters 'program-master-4k.manifest.txt')

Move-SlingshotPath `
    (Join-Path $oldFinal 's01e04-impact-force-curve-final-4k-v5-bright-voice-bgm.mp4') `
    $ep04.ProgramMaster
Move-SlingshotPath `
    (Join-Path $oldFinal 's01e04-impact-force-curve-final-4k-v5-bright-voice-bgm.manifest.txt') `
    (Join-Path $ep04.Masters 'program-master-4k.manifest.txt')
Move-SlingshotPath `
    (Join-Path $oldFinal 's01e04-impact-force-curve-final-4k-v5-premix-clean-master.mp4') `
    $ep04.PictureCleanMaster
Move-SlingshotPath (Join-Path $oldFinal 's01e04-impact-force-curve-final-4k-v5-premix.json') `
    (Join-Path $ep04.Masters 'picture-analysis.json')
Move-SlingshotPath (Join-Path $oldFinal 's01e04-impact-force-curve-final-4k-v5-premix.manifest.txt') `
    (Join-Path $ep04.Masters 'picture-render.manifest.txt')
Move-SlingshotPath (Join-Path $oldFinal 's01e04-impact-force-curve-final-4k-v5-premix.mp4') `
    (Join-Path $ep04.Archive '2026-07-29-release-build\program-premix-4k.mp4')

# Old final/review exports remain recoverable in the episode archive.
if (Test-Path -LiteralPath $oldFinal) {
    foreach ($item in Get-ChildItem -LiteralPath $oldFinal -Force) {
        $destinationRoot = if ($item.Name -like 's01e03-*') { $ep03.Archive } else { $ep04.Archive }
        Move-SlingshotPath $item.FullName (Join-Path $destinationRoot "legacy-final\$($item.Name)")
    }
}

# Audio stems become part of the episode master; old voice comparisons are archived.
Move-SlingshotDirectoryContents (Join-Path $script:RenderRoot 'audio\s01e01-angle-sweep') $ep01.MasterAudio
Move-SlingshotDirectoryContents (Join-Path $script:RenderRoot 'audio\s01e03-angle-with-drag') $ep03.MasterAudio
Move-SlingshotDirectoryContents (Join-Path $script:RenderRoot 'audio\s01e04-impact-force-curve') $ep04.MasterAudio
Move-SlingshotDirectoryContents (Join-Path $script:RenderRoot 'narration\s01e03-angle-with-drag') $ep03.MasterAudio
$oldEp04Narration = Join-Path $script:RenderRoot 'narration\s01e04-impact-force-curve'
if (Test-Path -LiteralPath $oldEp04Narration) {
    foreach ($item in Get-ChildItem -LiteralPath $oldEp04Narration -Force) {
        if ($item.PSIsContainer -and $item.Name.StartsWith('backup-')) {
            Move-SlingshotPath $item.FullName (Join-Path $ep04.Archive "voice-tests\$($item.Name)")
        } else {
            Move-SlingshotPath $item.FullName (Join-Path $ep04.MasterAudio $item.Name)
        }
    }
}

# Platform packages and cover assets.
Move-SlingshotDirectoryContents `
    (Join-Path $script:RenderRoot 'publishing\s01e03-angle-with-drag') $ep03.Deliveries
Move-SlingshotDirectoryContents `
    (Join-Path $script:RenderRoot 'publishing\s01e04-impact-force-curve') $ep04.Deliveries

# Episode-scoped previews and review materials.
$oldPreviews = Join-Path $script:RenderRoot 'previews'
if (Test-Path -LiteralPath $oldPreviews) {
    foreach ($item in Get-ChildItem -LiteralPath $oldPreviews -Force) {
        $destination = if ($item.Name -like 's01e04-*') {
            Join-Path $ep04.Previews "legacy\$($item.Name)"
        } elseif ($item.Name -like 's01e03-*') {
            Join-Path $ep03.Previews "legacy\$($item.Name)"
        } else {
            Join-Path $script:RenderWorkRoot "_shared\previews\$($item.Name)"
        }
        Move-SlingshotPath $item.FullName $destination
    }
}
foreach ($name in @('animation-polish', 'cold-open-candidates', 'cold-open-fivefold')) {
    Move-SlingshotPath (Join-Path $script:RenderRoot $name) (Join-Path $ep04.Previews $name)
}
Move-SlingshotDirectoryContents (Join-Path $script:RenderRoot 'frames\s01e03-angle-with-drag') `
    (Join-Path $ep03.Review 'frames')
Move-SlingshotDirectoryContents (Join-Path $script:RenderRoot 'frames\s01e04-impact-force-curve') `
    (Join-Path $ep04.Review 'frames')
Move-SlingshotDirectoryContents (Join-Path $script:RenderRoot 'frames\s01e04-v5-final') `
    (Join-Path $ep04.Review 'final-frames')
$oldReview = Join-Path $script:RenderRoot 'review'
if (Test-Path -LiteralPath $oldReview) {
    foreach ($item in Get-ChildItem -LiteralPath $oldReview -Force) {
        Move-SlingshotPath $item.FullName (Join-Path $ep04.Review $item.Name)
    }
}
Move-SlingshotDirectoryContents (Join-Path $script:RenderRoot 'logs') (Join-Path $script:RenderWorkRoot '_shared\logs')

# Preserve failed captures for diagnosis instead of deleting them during migration.
$failedRoot = Join-Path $script:RenderArchiveRoot '_failed-renders'
foreach ($temp in Get-ChildItem -LiteralPath $script:RenderRoot -Directory -Force -Filter '.episode-tmp-*') {
    Move-SlingshotPath $temp.FullName (Join-Path $failedRoot $temp.Name)
}
Move-SlingshotPath (Join-Path $script:RenderRoot '.godot-user') `
    (Join-Path $script:RenderCacheRoot 'godot-user')

# Remove only empty legacy containers after every file has been routed.
foreach ($legacy in @('final', 'audio', 'narration', 'publishing', 'previews', 'frames', 'review', 'logs')) {
    $path = Join-Path $script:RenderRoot $legacy
    if ((Test-Path -LiteralPath $path -PathType Container) -and
        @(Get-ChildItem -LiteralPath $path -Force -Recurse).Count -eq 0) {
        Remove-Item -LiteralPath $path -Recurse
    }
}

Write-Host "render-layout-migration: completed $resolvedRenderRoot"
