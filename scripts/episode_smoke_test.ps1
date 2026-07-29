[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'common.ps1')
$ffprobe = Find-SlingshotTool -Name 'ffprobe'
$smokeDir = New-SlingshotRenderTempDirectory -Kind 'smoke-test'
New-Item -ItemType Directory -Force -Path $smokeDir | Out-Null
try {
    $output = Join-Path $smokeDir 'episode-smoke.mp4'
    & (Join-Path $PSScriptRoot 'render_episode.ps1') `
        -Episode (Join-Path $script:ProjectRoot 'content\episodes\smoke.json') `
        -Output $output -SkipNarration
    if (-not (Test-Path $output)) { throw 'Smoke render did not produce an MP4.' }
    $probe = (& $ffprobe -v error -select_streams v:0 `
        -show_entries stream=codec_name,width,height,avg_frame_rate -of csv=p=0 $output).Trim()
    if ($probe -ne 'h264,3840,2160,30/1') { throw "Unexpected smoke metadata: $probe" }
    Write-Host "EPISODE SMOKE: passed ($probe)"
} finally {
    if (Test-Path $smokeDir) { Remove-Item -LiteralPath $smokeDir -Recurse -Force }
}
