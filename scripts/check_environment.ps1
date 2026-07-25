[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'common.ps1')

$godot = Get-SlingshotGodot
$typst = Find-SlingshotTool -Name 'typst' -Fallback @(
    (Join-Path $HOME '.local\bin\typst.exe'),
    'C:\Users\gqy17\.local\bin\typst.exe'
)
$ffmpeg = Find-SlingshotTool -Name 'ffmpeg'
$ffprobe = Find-SlingshotTool -Name 'ffprobe'
$mmx = Find-SlingshotTool -Name 'mmx'

$checks = @(
    [pscustomobject]@{ Name = 'Godot'; Expected = '4.7.1'; Actual = ((& $godot --version) | Select-Object -First 1) }
    [pscustomobject]@{ Name = 'Typst'; Expected = '0.15.1'; Actual = ((& $typst --version) | Select-Object -First 1) }
    [pscustomobject]@{ Name = 'mmx'; Expected = '1.0.18+'; Actual = ((& $mmx --version) | Select-Object -First 1) }
    [pscustomobject]@{ Name = 'FFmpeg'; Expected = 'available'; Actual = ((& $ffmpeg -version) | Select-Object -First 1) }
    [pscustomobject]@{ Name = 'ffprobe'; Expected = 'available'; Actual = ((& $ffprobe -version) | Select-Object -First 1) }
)
$checks | Format-Table Name, Expected, Actual -AutoSize

if ($checks[0].Actual -notmatch '^4\.7\.1\.') { throw 'Godot 4.7.1 is required.' }
if ($checks[1].Actual -notmatch '^typst 0\.15\.1\b') { throw 'Typst 0.15.1 is required.' }
if ($checks[2].Actual -notmatch '^mmx 1\.(?:0\.(?:1[89]|[2-9][0-9])|[1-9]\.)') {
    throw 'mmx-cli 1.0.18 or newer is required.'
}
