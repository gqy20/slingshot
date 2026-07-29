[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\render_shard_planner.ps1')

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) {
        throw "$Message (actual=$Actual expected=$Expected)"
    }
}

$episode = [pscustomobject]@{
    beats = @(
        [pscustomobject]@{ at = 0.0; duration = 12.0 },
        [pscustomobject]@{ at = 12.0; duration = 13.0 },
        [pscustomobject]@{ at = 25.0; duration = 17.0 },
        [pscustomobject]@{ at = 42.0; duration = 18.0 },
        [pscustomobject]@{ at = 60.0; duration = 15.0 },
        [pscustomobject]@{ at = 75.0; duration = 15.0 },
        [pscustomobject]@{ at = 90.0; duration = 15.0 },
        [pscustomobject]@{ at = 105.0; duration = 12.0 },
        [pscustomobject]@{ at = 117.0; duration = 18.0 },
        [pscustomobject]@{ at = 135.0; duration = 15.0 },
        [pscustomobject]@{ at = 150.0; duration = 15.0 },
        [pscustomobject]@{ at = 165.0; duration = 18.0 },
        [pscustomobject]@{ at = 183.0; duration = 17.0 },
        [pscustomobject]@{ at = 200.0; duration = 10.0 }
    )
}

$two = @(Get-SlingshotStoryboardRenderShards -Episode $episode -Fps 30 `
    -FrameStart 0 -FrameEnd 6300 -WorkerCount 2 -WarmupFrames 2)
Assert-Equal $two.Count 2 'two workers create two shards'
Assert-Equal $two[0].FrameEnd 3150 'planner selects the nearest storyboard midpoint'
Assert-Equal $two[1].FrameStart 3150 'shards meet at the 105 second beat boundary'
Assert-Equal $two[1].RenderStart 3148 'later shards include deterministic warm-up frames'
Assert-Equal ($two | Measure-Object FrameCount -Sum).Sum 6300 'shards cover every requested frame once'

$preview = @(Get-SlingshotStoryboardRenderShards -Episode $episode -Fps 30 `
    -FrameStart 300 -FrameEnd 900 -WorkerCount 4 -WarmupFrames 2)
Assert-Equal $preview.Count 3 'workers are capped by available beat boundaries'
Assert-Equal $preview[0].FrameStart 300 'preview keeps its absolute start frame'
Assert-Equal $preview[-1].FrameEnd 900 'preview keeps its absolute end frame'

$single = @(Get-SlingshotStoryboardRenderShards -Episode $episode -Fps 30 `
    -FrameStart 10 -FrameEnd 20 -WorkerCount 2 -WarmupFrames 2)
Assert-Equal $single.Count 1 'a range without beat boundaries remains serial'

$templateEpisode = [pscustomobject]@{
    beat_template = 'standard-14'
    story = [pscustomobject]@{
        question_sec = 15.0
        explain_sec = 30.0
        setup_sec = 15.0
        flight_sec = 20.0
        compare_sec = 40.0
    }
}
$templateShards = @(Get-SlingshotStoryboardRenderShards -Episode $templateEpisode -Fps 30 `
    -FrameStart 0 -FrameEnd 3600 -WorkerCount 2 -WarmupFrames 2)
Assert-Equal $templateShards.Count 2 'template episodes use phase boundaries for parallel rendering'
Assert-Equal $templateShards[0].FrameEnd 1800 'template planner selects the nearest safe midpoint'
Assert-Equal $templateShards[1].RenderStart 1798 'template shard keeps boundary warm-up frames'

Write-Host 'RENDER SHARD PLANNER: passed'
