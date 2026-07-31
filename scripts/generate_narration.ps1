[CmdletBinding()]
param(
    [switch]$Reuse,
    [switch]$AllowLong,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Episode = @()
)

. (Join-Path $PSScriptRoot 'common.ps1')
$mmx = Find-SlingshotTool -Name 'mmx'
$ffmpeg = Find-SlingshotTool -Name 'ffmpeg'
$ffprobe = Find-SlingshotTool -Name 'ffprobe'

function ConvertFrom-SrtTimestamp([string]$Value) {
    if ($Value -notmatch '^(\d{2}):(\d{2}):(\d{2}),(\d{3})$') {
        throw "Invalid SRT timestamp: $Value"
    }
    return ((([int64]$Matches[1] * 60 + [int64]$Matches[2]) * 60 +
        [int64]$Matches[3]) * 1000 + [int64]$Matches[4])
}

function ConvertTo-SrtTimestamp([int64]$Milliseconds) {
    $value = [Math]::Max(0, $Milliseconds)
    $hours = [Math]::Floor($value / 3600000)
    $value %= 3600000
    $minutes = [Math]::Floor($value / 60000)
    $value %= 60000
    $seconds = [Math]::Floor($value / 1000)
    $millis = $value % 1000
    return '{0:00}:{1:00}:{2:00},{3:000}' -f $hours, $minutes, $seconds, $millis
}

function Add-SrtSegment(
    [System.Collections.Generic.List[object]]$Entries,
    [string]$Path,
    [double]$OffsetSeconds,
    [double]$SlotDuration
) {
    $source = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
    $pattern = '(?ms)^\s*\d+\s*\r?\n(?<start>\d{2}:\d{2}:\d{2},\d{3})\s+-->\s+(?<end>\d{2}:\d{2}:\d{2},\d{3})[^\r\n]*\r?\n(?<text>.*?)(?=\r?\n\r?\n|\z)'
    $offsetMs = [int64][Math]::Round($OffsetSeconds * 1000)
    $slotEndMs = [int64][Math]::Round(($OffsetSeconds + $SlotDuration) * 1000)
    foreach ($match in [regex]::Matches($source, $pattern)) {
        $startMs = $offsetMs + (ConvertFrom-SrtTimestamp $match.Groups['start'].Value)
        $endMs = [Math]::Min(
            $slotEndMs,
            $offsetMs + (ConvertFrom-SrtTimestamp $match.Groups['end'].Value)
        )
        $text = $match.Groups['text'].Value.Trim()
        if ($text -and $endMs -gt $startMs) {
            $Entries.Add([pscustomobject]@{ Start = $startMs; End = $endMs; Text = $text })
        }
    }
}

function Split-SrtText([string]$Text, [int]$MaximumCharacters = 32) {
    $normalized = ($Text -replace '\s+', ' ').Trim()
    if (-not $normalized) { return @() }
    $result = @()
    $remaining = $normalized
    while ($remaining.Length -gt $MaximumCharacters) {
        $window = $remaining.Substring(0, $MaximumCharacters)
        # Use Unicode escapes so Windows PowerShell 5 can parse this UTF-8 script
        # without corrupting the Chinese punctuation literals.
        $cut = $MaximumCharacters
        $minimumCut = [Math]::Floor($MaximumCharacters * 0.45)
        $strongBreaks = [regex]::Matches($window, '[\u3002\uFF01\uFF1F\uFF1B]')
        $candidate = if ($strongBreaks.Count -gt 0) {
            $strongBreaks[$strongBreaks.Count - 1].Index + 1
        } else { 0 }
        if ($candidate -lt $minimumCut) {
            $softBreaks = [regex]::Matches($window, '[\uFF0C\u3001\uFF1A]')
            $candidate = if ($softBreaks.Count -gt 0) {
                $softBreaks[$softBreaks.Count - 1].Index + 1
            } else { 0 }
        }
        if ($candidate -ge $minimumCut) {
            $cut = $candidate
        }
        $result += $remaining.Substring(0, $cut).Trim()
        $remaining = $remaining.Substring($cut).Trim()
    }
    if ($remaining) { $result += $remaining }
    return @($result)
}

function Read-SrtEntries([string]$Path) {
    $entries = [System.Collections.Generic.List[object]]::new()
    $source = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
    $pattern = '(?ms)^\s*\d+\s*\r?\n(?<start>\d{2}:\d{2}:\d{2},\d{3})\s+-->\s+(?<end>\d{2}:\d{2}:\d{2},\d{3})[^\r\n]*\r?\n(?<text>.*?)(?=\r?\n\r?\n|\z)'
    foreach ($match in [regex]::Matches($source, $pattern)) {
        $entries.Add([pscustomobject]@{
            Start = ConvertFrom-SrtTimestamp $match.Groups['start'].Value
            End = ConvertFrom-SrtTimestamp $match.Groups['end'].Value
            Text = $match.Groups['text'].Value.Trim()
        })
    }
    return $entries
}

function Merge-SrtEntriesByBeat(
    [System.Collections.Generic.List[object]]$Entries,
    [object[]]$Beats
) {
    $merged = [System.Collections.Generic.List[object]]::new()
    foreach ($beat in $Beats) {
        $beatStart = [int64][Math]::Round([double]$beat.at * 1000)
        $beatEnd = [int64][Math]::Round(([double]$beat.at + [double]$beat.duration) * 1000)
        $members = @($Entries | Where-Object {
            [int64]$_.Start -ge $beatStart -and [int64]$_.Start -lt $beatEnd
        } | Sort-Object Start)
        if ($members.Count -eq 0) { continue }
        $merged.Add([pscustomobject]@{
            Start = [int64]$members[0].Start
            End = [int64]$members[-1].End
            Text = (($members | ForEach-Object { [string]$_.Text }) -join '')
        })
    }
    return $merged
}

function Apply-SrtTextReplacements(
    [System.Collections.Generic.List[object]]$Entries,
    [object[]]$Replacements
) {
    $result = [System.Collections.Generic.List[object]]::new()
    $replacementCounts = @{}
    foreach ($replacement in $Replacements) {
        $from = [string]$replacement.from
        $to = [string]$replacement.to
        if ([string]::IsNullOrWhiteSpace($from)) {
            throw 'narration.subtitle_replacements contains an empty from value'
        }
        $replacementCounts[$from] = 0
    }

    foreach ($entry in $Entries) {
        $text = [string]$entry.Text
        foreach ($replacement in $Replacements) {
            $from = [string]$replacement.from
            $to = [string]$replacement.to
            if ($text.Contains($from)) {
                $replacementCounts[$from] += 1
                $text = $text.Replace($from, $to)
            } elseif ($text.Contains($to)) {
                # Keep -Reuse idempotent when the generated master already uses editorial text.
                $replacementCounts[$from] += 1
            }
        }
        $result.Add([pscustomobject]@{
            Start = [int64]$entry.Start
            End = [int64]$entry.End
            Text = $text
        })
    }

    foreach ($replacement in $Replacements) {
        $from = [string]$replacement.from
        if ($replacementCounts[$from] -eq 0) {
            $to = [string]$replacement.to
            $targetExists = @($result | Where-Object { ([string]$_.Text).Contains($to) }).Count -gt 0
            if (-not $targetExists) {
                throw "Subtitle replacement source was not found: $from"
            }
        }
    }
    return $result
}

function Write-SrtEntries([string]$Path, [System.Collections.Generic.List[object]]$Entries) {
    $expanded = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $Entries) {
        $parts = @(Split-SrtText -Text ([string]$entry.Text) -MaximumCharacters 32)
        if ($parts.Count -eq 0) { continue }
        $totalCharacters = ($parts | ForEach-Object Length | Measure-Object -Sum).Sum
        $duration = [int64]$entry.End - [int64]$entry.Start
        $consumedCharacters = 0
        for ($partIndex = 0; $partIndex -lt $parts.Count; $partIndex++) {
            $partStart = if ($partIndex -eq 0) {
                [int64]$entry.Start
            } else {
                [int64]$entry.Start + [int64][Math]::Round(
                    $duration * $consumedCharacters / $totalCharacters
                )
            }
            $consumedCharacters += $parts[$partIndex].Length
            $partEnd = if ($partIndex -eq $parts.Count - 1) {
                [int64]$entry.End
            } else {
                [int64]$entry.Start + [int64][Math]::Round(
                    $duration * $consumedCharacters / $totalCharacters
                )
            }
            $expanded.Add([pscustomobject]@{
                Start = $partStart
                End = $partEnd
                Text = $parts[$partIndex]
            })
        }
    }
    $blocks = for ($index = 0; $index -lt $expanded.Count; $index++) {
        $entry = $expanded[$index]
        @(
            ($index + 1),
            "$(ConvertTo-SrtTimestamp $entry.Start) --> $(ConvertTo-SrtTimestamp $entry.End)",
            $entry.Text
        ) -join "`n"
    }
    Write-SlingshotUtf8 $Path (($blocks -join "`n`n") + "`n")
}

if ($Episode.Count -eq 0) {
    $Episode = @(Get-ChildItem (Join-Path $script:ProjectRoot 'content\episodes') `
        -File -Filter 's??e??-*.json' | Sort-Object Name | ForEach-Object FullName)
}

foreach ($episodeInput in $Episode) {
    $episodePath = (Resolve-Path -LiteralPath $episodeInput).Path
    $config = Get-Content -Raw -Encoding UTF8 $episodePath | ConvertFrom-Json
    $narrationProperty = $config.PSObject.Properties['narration']
    if ($null -eq $narrationProperty) { continue }
    $narration = $narrationProperty.Value
    $scriptRelative = ([string]$narration.script).Substring('res://'.Length).Replace('/', '\')
    $textPath = Join-Path $script:ProjectRoot $scriptRelative
    if (-not (Test-Path $textPath)) { throw "Narration text not found: $textPath" }

    $stem = [string]$config.id
    $episodePaths = Get-SlingshotEpisodePaths $stem
    $outputDir = $episodePaths.MasterAudio
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    $audio = Join-Path $outputDir 'narration.mp3'
    $subtitles = Join-Path $outputDir 'narration.srt'
    $normalized = Join-Path $outputDir 'narration-normalized.wav'
    $manifest = Join-Path $outputDir 'narration.manifest.txt'
    $timingMode = if ($narration.PSObject.Properties['timing_mode']) {
        [string]$narration.timing_mode
    } else {
        'continuous'
    }
	$model = if ($narration.PSObject.Properties['model']) { [string]$narration.model } else { 'speech-2.8-hd' }
	$language = if ($narration.PSObject.Properties['language']) { [string]$narration.language } else { 'Chinese' }
	$speed = if ($narration.PSObject.Properties['speed']) { [string]$narration.speed } else { '1.0' }
	$volume = if ($narration.PSObject.Properties['volume']) { [string]$narration.volume } else { '1.0' }
	$pitch = if ($narration.PSObject.Properties['pitch']) { [string]$narration.pitch } else { '0' }
    $beatTimingLines = @()

    if (-not $Reuse) {
        $tempDir = New-SlingshotRenderTempDirectory -Kind 'narration' -EpisodeId $stem
        try {
            $tempAudio = Join-Path $tempDir 'narration.mp3'
            $tempSrt = Join-Path $tempDir 'narration.srt'
            if ($timingMode -eq 'beats') {
                $paragraphs = @([regex]::Split(
                    (Get-Content -Raw -Encoding UTF8 $textPath).Trim(),
                    '\r?\n\s*\r?\n'
                ) | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                $beats = @($config.beats)
                if ($paragraphs.Count -ne $beats.Count) {
                    throw "Beat-timed narration requires one paragraph per beat; got $($paragraphs.Count) paragraphs and $($beats.Count) beats for $stem"
                }
                $concatLines = @()
                $subtitleEntries = [System.Collections.Generic.List[object]]::new()
                for ($index = 0; $index -lt $beats.Count; $index++) {
                    $segmentText = Join-Path $tempDir ('beat-{0:d2}.txt' -f $index)
                    $segmentMp3 = Join-Path $tempDir ('beat-{0:d2}.mp3' -f $index)
                    $segmentSrt = Join-Path $tempDir ('beat-{0:d2}.srt' -f $index)
                    $segmentWav = Join-Path $tempDir ('beat-{0:d2}.wav' -f $index)
                    Write-SlingshotUtf8 $segmentText $paragraphs[$index]
                    $arguments = @('speech', 'synthesize', '--text-file', $segmentText, '--model', $model,
                        '--voice', [string]$narration.voice, '--speed', $speed, '--volume', $volume,
                        '--pitch', $pitch, '--language', $language, '--format', 'mp3', '--sample-rate',
                        '32000', '--bitrate', '128000', '--channels', '1', '--subtitles', '--out', $segmentMp3,
                        '--non-interactive', '--quiet', '--output', 'json')
                    if ($narration.PSObject.Properties['pronunciations']) {
                        foreach ($pronunciation in @($narration.pronunciations)) {
                            $arguments += @('--pronunciation', [string]$pronunciation)
                        }
                    }
                    & $mmx @arguments
                    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $segmentMp3) -or -not (Test-Path $segmentSrt)) {
                        throw "mmx beat narration generation failed for $stem beat $($beats[$index].id)"
                    }
                    $segmentDuration = [double]((& $ffprobe -v error -show_entries format=duration `
                        -of default=nw=1:nk=1 $segmentMp3).Trim())
                    $beatDuration = [double]$beats[$index].duration
                    if ($segmentDuration -gt $beatDuration - 0.1) {
                        throw "Narration beat $($beats[$index].id) is ${segmentDuration}s but only ${beatDuration}s is available"
                    }
                    & $ffmpeg -y -loglevel error -i $segmentMp3 -af apad -t $beatDuration `
                        -ar 32000 -ac 1 -c:a pcm_s16le $segmentWav
                    if ($LASTEXITCODE -ne 0) { throw "Failed to pad narration beat $($beats[$index].id)" }
                    $concatPath = $segmentWav.Replace('\', '/')
                    $concatLines += "file '$concatPath'"
                    Add-SrtSegment $subtitleEntries $segmentSrt ([double]$beats[$index].at) $beatDuration
                    $beatTimingLines += "beat_$($beats[$index].id)_speech_sec=$segmentDuration"
                    $beatTimingLines += "beat_$($beats[$index].id)_slot_sec=$beatDuration"
                }
                $concatFile = Join-Path $tempDir 'beats.concat.txt'
                Write-SlingshotUtf8 $concatFile (($concatLines -join "`n") + "`n")
                & $ffmpeg -y -loglevel error -f concat -safe 0 -i $concatFile `
                    -c:a libmp3lame -b:a 128k -ar 32000 -ac 1 $tempAudio
                if ($LASTEXITCODE -ne 0) { throw "Failed to concatenate beat narration for $stem" }
                if ($subtitleEntries.Count -eq 0) {
                    throw "mmx produced no subtitle cues for beat-timed narration $stem"
                }
                Write-SrtEntries $tempSrt $subtitleEntries
            } else {
                $arguments = @('speech', 'synthesize', '--text-file', $textPath, '--model', $model,
                    '--voice', [string]$narration.voice, '--speed', $speed, '--volume', $volume,
                    '--pitch', $pitch, '--language', $language, '--format', 'mp3', '--sample-rate',
                    '32000', '--bitrate', '128000', '--channels', '1', '--subtitles', '--out',
                    $tempAudio, '--non-interactive', '--quiet', '--output', 'json')
                if ($narration.PSObject.Properties['pronunciations']) {
                    foreach ($pronunciation in @($narration.pronunciations)) {
                        $arguments += @('--pronunciation', [string]$pronunciation)
                    }
                }
                & $mmx @arguments
                if ($LASTEXITCODE -ne 0) { throw "mmx narration generation failed for $stem" }
            }
            if (-not (Test-Path $tempAudio) -or -not (Test-Path $tempSrt)) {
                throw "mmx did not produce MP3 and SRT for $stem"
            }
            Move-Item -Force $tempAudio $audio
            Move-Item -Force $tempSrt $subtitles
        } finally {
            if (Test-Path $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
        }
    } elseif (-not (Test-Path $audio) -or -not (Test-Path $subtitles)) {
        throw "-Reuse requested but narration assets are missing for $stem"
    }

    if ($timingMode -eq 'beats') {
        [System.Collections.Generic.List[object]]$existingEntries = Read-SrtEntries -Path $subtitles
        if ($existingEntries.Count -eq 0) {
            throw "Beat-timed narration subtitle file contains no cues for $stem"
        }
        [System.Collections.Generic.List[object]]$beatEntries = Merge-SrtEntriesByBeat `
            -Entries $existingEntries -Beats @($config.beats)
        if ($narration.PSObject.Properties['subtitle_replacements']) {
            $beatEntries = Apply-SrtTextReplacements `
                -Entries $beatEntries -Replacements @($narration.subtitle_replacements)
        }
        Write-SrtEntries -Path $subtitles -Entries $beatEntries
        if ($narration.PSObject.Properties['subtitle_script']) {
            $editorialRelative = [string]$narration.subtitle_script
            if (-not $editorialRelative.StartsWith('res://') -or $editorialRelative.Contains('..')) {
                throw "Unsafe narration.subtitle_script: $editorialRelative"
            }
            $editorialPath = Join-Path $script:ProjectRoot $editorialRelative.Substring(6).Replace('/', '\')
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $editorialPath) | Out-Null
            Copy-Item -LiteralPath $subtitles -Destination $editorialPath -Force
        }
    }

    & $ffmpeg -y -loglevel error -i $audio `
        -af 'loudnorm=I=-16:TP=-1.5:LRA=7' -ar 48000 -ac 1 `
        -c:a pcm_s24le $normalized
    if ($LASTEXITCODE -ne 0) { throw "Narration normalization failed for $stem" }
    $duration = [double]((& $ffprobe -v error -show_entries format=duration `
        -of default=nw=1:nk=1 $normalized).Trim())
    $videoDuration = Get-SlingshotEpisodeDuration $config
    if ($duration -le 0) {
        throw "Narration duration is invalid for $stem"
    }
    if ($duration -gt $videoDuration -and -not $AllowLong) {
        throw "Narration duration $duration exceeds video duration $videoDuration for $stem; use -AllowLong before timeline alignment"
    }
    $lines = @(
        "episode=$([IO.Path]::GetFileName($episodePath))",
        "episode_sha256=$(Get-SlingshotSha256 $episodePath)",
        "script_sha256=$(Get-SlingshotSha256 $textPath)",
        "source_audio_sha256=$(Get-SlingshotSha256 $audio)",
        "normalized_audio_sha256=$(Get-SlingshotSha256 $normalized)",
        "subtitles_sha256=$(Get-SlingshotSha256 $subtitles)",
        "audio_duration_sec=$duration",
        "video_duration_sec=$videoDuration",
        "timing_mode=$timingMode",
		"model=$model",
		"voice=$([string]$narration.voice)",
		"language=$language",
		"speed=$speed",
		"volume=$volume",
		"pitch=$pitch",
        "mmx_cli=$((& $mmx --version | Select-Object -First 1))",
        'audio_standard=-16_LUFS_-1.5_dBTP_48kHz_mono_PCM24'
    ) + $beatTimingLines
    Write-SlingshotUtf8 $manifest (($lines -join "`n") + "`n")
    Write-Host "narration: $stem audio=${duration}s video=${videoDuration}s"
}
