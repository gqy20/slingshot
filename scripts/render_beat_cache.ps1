Set-StrictMode -Version Latest

function Get-SlingshotTextSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-SlingshotRenderSourceFingerprint {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)
    $files = @(
        Get-Item -LiteralPath (Join-Path $ProjectRoot 'project.godot'), (Join-Path $ProjectRoot 'episode.tscn')
        Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'src') -Recurse -File
        Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'presets') -Recurse -File
        Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'content\themes') -Recurse -File
        Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'assets\fonts') -Recurse -File -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'assets\generated') -Recurse -File -ErrorAction SilentlyContinue
    ) | Sort-Object FullName
    $lines = foreach ($file in $files) {
        $relative = $file.FullName.Substring($ProjectRoot.Length).TrimStart('\', '/').Replace('\', '/')
        "$relative=$((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash)"
    }
    return Get-SlingshotTextSha256 ($lines -join "`n")
}

function Get-SlingshotStoryboardSegments {
    param(
        [Parameter(Mandatory = $true)]$Episode,
        [Parameter(Mandatory = $true)][int]$Fps,
        [Parameter(Mandatory = $true)][int]$TotalFrames
    )
    $segments = @()
    $beatProperty = $Episode.PSObject.Properties['beats']
    if ($null -ne $beatProperty -and @($beatProperty.Value).Count -gt 0) {
        foreach ($beat in @($beatProperty.Value)) {
            $start = [int][Math]::Floor(([double]$beat.at * $Fps) + 0.5)
            $end = [int][Math]::Floor((([double]$beat.at + [double]$beat.duration) * $Fps) + 0.5)
            $segments += [pscustomobject]@{
                Id = [string]$beat.id
                FrameStart = $start
                FrameEnd = [Math]::Min($TotalFrames, $end)
                FingerprintJson = ($beat | ConvertTo-Json -Depth 20 -Compress)
            }
        }
        return $segments
    }

    $story = $Episode.story
    $cursor = 0
    foreach ($phase in @(
        @{ Id = 'question'; Field = 'question_sec' },
        @{ Id = 'explain'; Field = 'explain_sec' },
        @{ Id = 'setup'; Field = 'setup_sec' },
        @{ Id = 'flight'; Field = 'flight_sec' },
        @{ Id = 'compare'; Field = 'compare_sec' }
    )) {
        $duration = [int][Math]::Floor(([double]$story.($phase.Field) * $Fps) + 0.5)
        $segments += [pscustomobject]@{
            Id = $phase.Id
            FrameStart = $cursor
            FrameEnd = [Math]::Min($TotalFrames, $cursor + $duration)
            FingerprintJson = "$($phase.Id):$duration"
        }
        $cursor += $duration
    }
    return $segments
}

function Get-SlingshotBeatCacheEntries {
    param(
        [Parameter(Mandatory = $true)]$Episode,
        [Parameter(Mandatory = $true)][int]$Fps,
        [Parameter(Mandatory = $true)][int]$TotalFrames,
        [Parameter(Mandatory = $true)][string]$CacheRoot,
        [Parameter(Mandatory = $true)][string]$CommonFingerprint
    )
    $entries = @()
    foreach ($segment in @(Get-SlingshotStoryboardSegments -Episode $Episode -Fps $Fps -TotalFrames $TotalFrames)) {
        $key = Get-SlingshotTextSha256 "$CommonFingerprint|$($segment.FingerprintJson)"
        $entries += [pscustomobject]@{
            Id = $segment.Id
            FrameStart = $segment.FrameStart
            FrameEnd = $segment.FrameEnd
            Key = $key
            Directory = Join-Path $CacheRoot ("picture-frames\{0}-{1}" -f $segment.Id, $key)
            Hit = $false
        }
    }
    return $entries
}

function Test-SlingshotBeatCacheEntry {
    param([Parameter(Mandatory = $true)]$Entry)
    if (-not (Test-Path -LiteralPath $Entry.Directory)) { return $false }
    for ($frame = $Entry.FrameStart; $frame -lt $Entry.FrameEnd; $frame++) {
        if (-not (Test-Path -LiteralPath (Join-Path $Entry.Directory ('frame{0:d8}.png' -f $frame)))) {
            return $false
        }
    }
    return $true
}

function Merge-SlingshotMissingBeatRanges {
    param(
        [Parameter(Mandatory = $true)][array]$Entries,
        [Parameter(Mandatory = $true)][int]$MaximumRanges,
        [ValidateRange(0, 8)][int]$WarmupFrames = 2
    )
    $ranges = @()
    foreach ($entry in @($Entries | Sort-Object FrameStart)) {
        if ($ranges.Count -gt 0 -and $ranges[-1].FrameEnd -eq $entry.FrameStart) {
            $ranges[-1].FrameEnd = $entry.FrameEnd
            $ranges[-1].FrameCount = $ranges[-1].FrameEnd - $ranges[-1].FrameStart
        } else {
            $ranges += [pscustomobject]@{
                FrameStart = $entry.FrameStart
                FrameEnd = $entry.FrameEnd
                FrameCount = $entry.FrameEnd - $entry.FrameStart
            }
        }
    }
    while ($ranges.Count -gt $MaximumRanges) {
        $bestIndex = 0
        $bestGap = [int]::MaxValue
        for ($index = 0; $index -lt $ranges.Count - 1; $index++) {
            $gap = $ranges[$index + 1].FrameStart - $ranges[$index].FrameEnd
            if ($gap -lt $bestGap) { $bestGap = $gap; $bestIndex = $index }
        }
        $merged = [pscustomobject]@{
            FrameStart = $ranges[$bestIndex].FrameStart
            FrameEnd = $ranges[$bestIndex + 1].FrameEnd
            FrameCount = $ranges[$bestIndex + 1].FrameEnd - $ranges[$bestIndex].FrameStart
        }
        $next = @()
        if ($bestIndex -gt 0) { $next += $ranges[0..($bestIndex - 1)] }
        $next += $merged
        if ($bestIndex + 2 -lt $ranges.Count) { $next += $ranges[($bestIndex + 2)..($ranges.Count - 1)] }
        $ranges = $next
    }
    for ($index = 0; $index -lt $ranges.Count; $index++) {
        $ranges[$index] | Add-Member -NotePropertyName Index -NotePropertyValue $index
        $renderStart = if ($ranges[$index].FrameStart -eq 0) { 0 } else { [Math]::Max(0, $ranges[$index].FrameStart - $WarmupFrames) }
        $ranges[$index] | Add-Member -NotePropertyName RenderStart -NotePropertyValue $renderStart
        $ranges[$index] | Add-Member -NotePropertyName WarmupFrames -NotePropertyValue ($ranges[$index].FrameStart - $renderStart)
    }
    return $ranges
}
