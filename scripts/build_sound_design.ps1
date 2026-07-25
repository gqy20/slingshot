[CmdletBinding()]
param([Parameter(Mandatory = $true, Position = 0)][string]$Episode)

. (Join-Path $PSScriptRoot 'common.ps1')
$ffmpeg = Find-SlingshotTool -Name 'ffmpeg'
$ffprobe = Find-SlingshotTool -Name 'ffprobe'
$episodePath = (Resolve-Path -LiteralPath $Episode).Path
$config = Get-Content -Raw -Encoding UTF8 $episodePath | ConvertFrom-Json
$stem = [IO.Path]::GetFileNameWithoutExtension($episodePath)
$duration = Get-SlingshotEpisodeDuration $config
$outputDir = Join-Path $script:RenderRoot "audio\$stem"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$output = Join-Path $outputDir 'sound-design.wav'
$manifest = Join-Path $outputDir 'sound-design.manifest.txt'

$frequencies = switch ($stem) {
    's01e01-angle-sweep' { @(523, 659, 784, 659); break }
    's01e02-stretch-sweep' { @(440, 554, 659, 880); break }
    default { @(440, 554, 659, 554) }
}
$filter = "anullsrc=r=48000:cl=mono:d=$duration[base]"
$filter += ";anullsrc=r=48000:cl=mono:d=12[bgbase]"
$filter += ";sine=f=$($frequencies[0]):r=48000:d=0.28,volume=0.045,afade=t=out:st=0.12:d=0.16,adelay=350:all=1[bg1]"
$filter += ";sine=f=$($frequencies[1]):r=48000:d=0.28,volume=0.040,afade=t=out:st=0.12:d=0.16,adelay=1100:all=1[bg2]"
$filter += ";sine=f=$($frequencies[2]):r=48000:d=0.28,volume=0.036,afade=t=out:st=0.12:d=0.16,adelay=2050:all=1[bg3]"
$filter += ";sine=f=$($frequencies[3]):r=48000:d=0.32,volume=0.040,afade=t=out:st=0.14:d=0.18,adelay=3300:all=1[bg4]"
$filter += ";[bgbase][bg1][bg2][bg3][bg4]amix=inputs=5:duration=first:normalize=0,lowpass=f=2600,aloop=loop=-1:size=576000,atrim=0:$duration[bgm]"
$mixInputs = '[base][bgm]'
$cueCount = 0
foreach ($beat in @($config.beats)) {
    $sfxProperty = $beat.PSObject.Properties['sfx']
    if ($null -eq $sfxProperty -or -not [string]$sfxProperty.Value) { continue }
    $delay = [int][Math]::Floor([double]$beat.at * 1000 + 0.5)
    $label = "cue$cueCount"
    switch ([string]$sfxProperty.Value) {
        'cold-open' { $filter += ";sine=f=330:r=48000:d=0.62,volume=0.10,tremolo=f=7:d=0.55,afade=t=out:st=0.28:d=0.34,adelay=${delay}:all=1[$label]" }
        'release' { $filter += ";anoisesrc=color=pink:r=48000:d=0.72:a=0.10,highpass=f=420,lowpass=f=6200,afade=t=in:st=0:d=0.03,afade=t=out:st=0.18:d=0.54,adelay=${delay}:all=1[$label]" }
        'landing' { $filter += ";anoisesrc=color=brown:r=48000:d=0.42:a=0.13,highpass=f=70,lowpass=f=900,afade=t=out:st=0.06:d=0.36,adelay=${delay}:all=1[$label]" }
        'result' { $filter += ";sine=f=660:r=48000:d=0.78,volume=0.075,tremolo=f=5:d=0.65,afade=t=out:st=0.34:d=0.44,adelay=${delay}:all=1[$label]" }
        default { throw "Unsupported sound cue: $($sfxProperty.Value)" }
    }
    $mixInputs += "[$label]"
    $cueCount++
}
$filter += ";${mixInputs}amix=inputs=$($cueCount + 2):duration=longest:normalize=0,alimiter=limit=0.35[out]"
& $ffmpeg -y -loglevel error -filter_complex $filter -map '[out]' -t $duration `
    -ar 48000 -ac 1 -c:a pcm_s24le $output
if ($LASTEXITCODE -ne 0) { throw "Sound design generation failed for $stem" }
$actual = [double]((& $ffprobe -v error -show_entries format=duration `
    -of default=nw=1:nk=1 $output).Trim())
if ([Math]::Abs($actual - $duration) -gt 0.01) { throw "Unexpected sound duration: $actual" }
$lines = @(
    "episode=$([IO.Path]::GetFileName($episodePath))",
    "episode_sha256=$(Get-SlingshotSha256 $episodePath)",
    "sound_design_sha256=$(Get-SlingshotSha256 $output)",
    "cue_count=$cueCount",
    "bgm_note_frequencies_hz=$($frequencies -join ' ')",
    "duration_sec=$actual",
    'sample_rate_hz=48000', 'channels=1', 'codec=pcm_s24le'
)
Write-SlingshotUtf8 $manifest (($lines -join "`n") + "`n")
Write-Host "sound-design: $stem cues=$cueCount duration=${actual}s"

