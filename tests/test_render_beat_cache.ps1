[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\render_beat_cache.ps1')

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message (actual=$Actual expected=$Expected)" }
}

$episode = [pscustomobject]@{
    beats = @(
        [pscustomobject]@{ id = 'a'; at = 0.0; duration = 2.0 },
        [pscustomobject]@{ id = 'b'; at = 2.0; duration = 3.0 },
        [pscustomobject]@{ id = 'c'; at = 5.0; duration = 5.0 }
    )
}
$entries = @(Get-SlingshotBeatCacheEntries -Episode $episode -Fps 10 -TotalFrames 100 `
    -CacheRoot 'C:\cache' -CommonFingerprint 'common')
Assert-Equal $entries.Count 3 'cache creates one entry per beat'
Assert-Equal $entries[1].FrameStart 20 'cache entry keeps absolute start frame'
Assert-Equal $entries[1].FrameEnd 50 'cache entry keeps absolute end frame'
if ($entries[0].Key -eq $entries[1].Key) { throw 'different beats must have different cache keys' }

$missing = @($entries[0], $entries[2])
$ranges = @(Merge-SlingshotMissingBeatRanges -Entries $missing -MaximumRanges 1 -WarmupFrames 2)
Assert-Equal $ranges.Count 1 'range limiter merges separated misses when worker budget is exhausted'
Assert-Equal $ranges[0].FrameStart 0 'merged miss starts at first dirty beat'
Assert-Equal $ranges[0].FrameEnd 100 'merged miss ends at last dirty beat'

$adjacent = @(Merge-SlingshotMissingBeatRanges -Entries @($entries[0], $entries[1]) `
    -MaximumRanges 2 -WarmupFrames 2)
Assert-Equal $adjacent.Count 1 'adjacent dirty beats form one render range'
Assert-Equal $adjacent[0].FrameEnd 50 'adjacent range covers both beats'

Write-Host 'RENDER BEAT CACHE: passed'
