Set-StrictMode -Version Latest

function Get-SlingshotStoryboardRenderShards {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Episode,
        [Parameter(Mandatory = $true)][int]$Fps,
        [Parameter(Mandatory = $true)][int]$FrameStart,
        [Parameter(Mandatory = $true)][int]$FrameEnd,
        [Parameter(Mandatory = $true)][int]$WorkerCount,
        [ValidateRange(0, 8)][int]$WarmupFrames = 2
    )

    if ($Fps -lt 1) { throw 'Fps must be positive.' }
    if ($FrameStart -lt 0 -or $FrameEnd -le $FrameStart) {
        throw "Invalid render frame range [$FrameStart,$FrameEnd)."
    }
    if ($WorkerCount -lt 1) { throw 'WorkerCount must be positive.' }

    # A split is only allowed at a storyboard boundary. This prevents a worker
    # from starting halfway through a camera transition or narrative reveal.
    $boundarySet = [Collections.Generic.SortedSet[int]]::new()
    $beatProperty = $Episode.PSObject.Properties['beats']
    $episodeBeats = @()
    if ($null -ne $beatProperty) { $episodeBeats = @($beatProperty.Value) }
    foreach ($beat in $episodeBeats) {
        $boundary = [int][Math]::Floor(([double]$beat.at * $Fps) + 0.5)
        if ($boundary -gt $FrameStart -and $boundary -lt $FrameEnd) {
            [void]$boundarySet.Add($boundary)
        }
    }
    # Template-based episodes are expanded by Godot at load time, so their raw
    # JSON has no beats for this PowerShell-side planner. Phase transitions are
    # still deterministic storyboard boundaries and provide a safe fallback.
    if ($episodeBeats.Count -eq 0) {
        $storyProperty = $Episode.PSObject.Properties['story']
        if ($null -ne $storyProperty) {
            $story = $storyProperty.Value
            $cursorSeconds = 0.0
            foreach ($durationName in @('question_sec', 'explain_sec', 'setup_sec', 'flight_sec')) {
                $durationProperty = $story.PSObject.Properties[$durationName]
                if ($null -ne $durationProperty) {
                    $cursorSeconds += [double]$durationProperty.Value
                    $boundary = [int][Math]::Floor(($cursorSeconds * $Fps) + 0.5)
                    if ($boundary -gt $FrameStart -and $boundary -lt $FrameEnd) {
                        [void]$boundarySet.Add($boundary)
                    }
                }
            }
        }
    }
    $boundaries = @($boundarySet)
    $actualWorkers = [Math]::Min($WorkerCount, $boundaries.Count + 1)
    $cuts = [Collections.Generic.List[int]]::new()
    [void]$cuts.Add($FrameStart)

    for ($index = 1; $index -lt $actualWorkers; $index++) {
        $target = $FrameStart + (($FrameEnd - $FrameStart) * $index / $actualWorkers)
        $remainingCuts = $actualWorkers - $index - 1
        $maximumIndex = $boundaries.Count - $remainingCuts - 1
        $best = $boundaries[0]
        $bestDistance = [Math]::Abs($best - $target)
        for ($candidateIndex = 0; $candidateIndex -le $maximumIndex; $candidateIndex++) {
            $candidate = $boundaries[$candidateIndex]
            $distance = [Math]::Abs($candidate - $target)
            if ($distance -lt $bestDistance) {
                $best = $candidate
                $bestDistance = $distance
            }
        }
        [void]$cuts.Add($best)
        $boundaries = @($boundaries | Where-Object { $_ -gt $best })
    }
    [void]$cuts.Add($FrameEnd)

    $shards = @()
    for ($index = 0; $index -lt $actualWorkers; $index++) {
        $start = $cuts[$index]
        $end = $cuts[$index + 1]
        $renderStart = if ($index -eq 0) {
            $start
        } else {
            [Math]::Max($FrameStart, $start - $WarmupFrames)
        }
        $shards += [pscustomobject]@{
            Index = $index
            FrameStart = $start
            FrameEnd = $end
            RenderStart = $renderStart
            WarmupFrames = $start - $renderStart
            FrameCount = $end - $start
        }
    }
    return $shards
}
