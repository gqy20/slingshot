param(
    [string]$OutputDir = 'renders/deliveries/s01e04-impact-force-curve/cover'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outputRoot = Join-Path $projectRoot $OutputDir
New-Item -ItemType Directory -Force $outputRoot | Out-Null

Add-Type -AssemblyName System.Drawing

function ConvertTo-Color {
    param([string]$Hex, [int]$Alpha = 255)
    $clean = $Hex.TrimStart('#')
    return [System.Drawing.Color]::FromArgb(
        $Alpha,
        [Convert]::ToInt32($clean.Substring(0, 2), 16),
        [Convert]::ToInt32($clean.Substring(2, 2), 16),
        [Convert]::ToInt32($clean.Substring(4, 2), 16)
    )
}

function New-PrivateFont {
    param([string]$Path, [float]$Size)
    $collection = [System.Drawing.Text.PrivateFontCollection]::new()
    $collection.AddFontFile((Resolve-Path $Path).Path)
    $font = [System.Drawing.Font]::new(
        $collection.Families[0], $Size, [System.Drawing.FontStyle]::Regular,
        [System.Drawing.GraphicsUnit]::Pixel
    )
    return [pscustomobject]@{ Collection = $collection; Font = $font }
}

function New-Pen {
    param([System.Drawing.Color]$Color, [float]$Width)
    $pen = [System.Drawing.Pen]::new($Color, $Width)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    return $pen
}

function Save-ResizedPng {
    param(
        [System.Drawing.Bitmap]$Source,
        [string]$Path,
        [int]$Width,
        [int]$Height,
        [System.Drawing.Rectangle]$SourceRect
    )
    $target = [System.Drawing.Bitmap]::new($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $target.SetResolution(600.0, 600.0)
    $graphics = [System.Drawing.Graphics]::FromImage($target)
    try {
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($Source, [System.Drawing.Rectangle]::new(0, 0, $Width, $Height), $SourceRect, [System.Drawing.GraphicsUnit]::Pixel)
        $target.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $target.Dispose()
    }
}

function Draw-Grid {
    param([System.Drawing.Graphics]$Graphics, [System.Collections.Generic.List[System.IDisposable]]$Disposables)
    $vertical = New-Pen ([System.Drawing.Color]::FromArgb(28, 48, 54, 61)) 2
    $horizontal = New-Pen ([System.Drawing.Color]::FromArgb(22, 48, 54, 61)) 2
    $Disposables.Add($vertical)
    $Disposables.Add($horizontal)
    for ($x = 1020; $x -lt 2220; $x += 150) { $Graphics.DrawLine($vertical, $x, 200, $x, 1200) }
    for ($y = 300; $y -lt 1200; $y += 145) { $Graphics.DrawLine($horizontal, 960, $y, 2220, $y) }
}

function Draw-Identity {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Brush]$AccentBrush,
        [System.Drawing.Brush]$TextBrush,
        [System.Drawing.Brush]$MutedBrush,
        [System.Drawing.Font]$BrandFont,
        [System.Drawing.Font]$RegularFont
    )
    $Graphics.FillRectangle($AccentBrush, 126, 112, 12, 54)
    $Graphics.DrawString('物理实验室', $BrandFont, $TextBrush, 166, 103)
}

function Draw-Curve {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.RectangleF]$Rect,
        [double]$DurationRatio,
        [double]$PeakRatio,
        [System.Drawing.Color]$Color,
        [System.Drawing.Brush]$FillBrush,
        [System.Collections.Generic.List[System.IDisposable]]$Disposables
    )
    $points = [System.Collections.Generic.List[System.Drawing.PointF]]::new()
    $steps = 72
    for ($i = 0; $i -le $steps; $i++) {
        $u = $i / [double]$steps
        $x = $Rect.Left + [float]($Rect.Width * $DurationRatio * $u)
        $y = $Rect.Bottom - [float]($Rect.Height * $PeakRatio * [Math]::Sin([Math]::PI * $u))
        $points.Add([System.Drawing.PointF]::new($x, $y))
    }
    $polygon = [System.Collections.Generic.List[System.Drawing.PointF]]::new()
    $polygon.Add([System.Drawing.PointF]::new($Rect.Left, $Rect.Bottom))
    foreach ($point in $points) { $polygon.Add($point) }
    $polygon.Add([System.Drawing.PointF]::new($points[$points.Count - 1].X, $Rect.Bottom))
    $Graphics.FillPolygon($FillBrush, $polygon.ToArray())
    $glow = New-Pen ([System.Drawing.Color]::FromArgb(50, $Color)) 24
    $line = New-Pen $Color 10
    $Disposables.Add($glow)
    $Disposables.Add($line)
    $Graphics.DrawLines($glow, $points.ToArray())
    $Graphics.DrawLines($line, $points.ToArray())
}

function Draw-Axis {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.RectangleF]$Rect,
        [System.Drawing.Brush]$MutedBrush,
        [System.Drawing.Font]$SmallFont,
        [bool]$ShowLabels = $true,
        [System.Collections.Generic.List[System.IDisposable]]$Disposables
    )
    $axis = New-Pen ([System.Drawing.Color]::FromArgb(128, 169, 173, 180)) 4
    $Disposables.Add($axis)
    $Graphics.DrawLine($axis, $Rect.Left, $Rect.Top, $Rect.Left, $Rect.Bottom)
    $Graphics.DrawLine($axis, $Rect.Left, $Rect.Bottom, $Rect.Right, $Rect.Bottom)
    if ($ShowLabels) {
        $Graphics.DrawString('法向接触力 Fₙ / N', $SmallFont, $MutedBrush, $Rect.Left, $Rect.Top - 62)
        $Graphics.DrawString('时间 t / ms', $SmallFont, $MutedBrush, $Rect.Right - 180, $Rect.Bottom + 26)
    }
}

function Draw-ImpactCard {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.RectangleF]$Rect,
        [string]$Label,
        [string]$Value,
        [System.Drawing.Color]$Color,
        [bool]$Soft,
        [System.Drawing.Brush]$TextBrush,
        [System.Drawing.Brush]$SurfaceBrush,
        [System.Drawing.Font]$LabelFont,
        [System.Drawing.Font]$ValueFont,
        [System.Collections.Generic.List[System.IDisposable]]$Disposables
    )
    $border = New-Pen ([System.Drawing.Color]::FromArgb(95, 80, 86, 94)) 3
    $Disposables.Add($border)
    $Graphics.FillRectangle($SurfaceBrush, $Rect)
    $Graphics.DrawRectangle($border, $Rect.X, $Rect.Y, $Rect.Width, $Rect.Height)
    $brush = [System.Drawing.SolidBrush]::new($Color)
    $fill = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(230, $Color))
    $Disposables.Add($brush)
    $Disposables.Add($fill)
    $Graphics.DrawString($Label, $LabelFont, $TextBrush, $Rect.Left + 44, $Rect.Top + 34)
    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $Graphics.DrawString($Value, $ValueFont, $brush, $Rect.Left + 40, $Rect.Top + 93)
    }

    $ballCenter = [System.Drawing.PointF]::new($Rect.Left + 200, $Rect.Bottom - 190)
    for ($i = 4; $i -ge 1; $i--) {
        $trail = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(12 + 9 * (5 - $i), $Color))
        $Disposables.Add($trail)
        $Graphics.FillEllipse($trail, $ballCenter.X - 68 - 38 * $i, $ballCenter.Y - 68, 136, 136)
    }
    $Graphics.FillEllipse($fill, $ballCenter.X - 70, $ballCenter.Y - 70, 140, 140)
    $shine = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(150, 255, 255, 255))
    $Disposables.Add($shine)
    $Graphics.FillEllipse($shine, $ballCenter.X - 25, $ballCenter.Y - 41, 22, 22)

    $wallX = $Rect.Right - 118
    if ($Soft) {
        $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
        $Disposables.Add($path)
        $path.AddBezier($wallX, $Rect.Top + 205, $wallX - 5, $ballCenter.Y - 160, $wallX - 72, $ballCenter.Y - 100, $wallX - 66, $ballCenter.Y)
        $path.AddBezier($wallX - 66, $ballCenter.Y, $wallX - 72, $ballCenter.Y + 100, $wallX - 5, $ballCenter.Y + 160, $wallX, $Rect.Bottom - 80)
        $padPen = New-Pen $Color 13
        $Disposables.Add($padPen)
        $Graphics.DrawPath($padPen, $path)
    }
    else {
        $wallPen = New-Pen ([System.Drawing.Color]::FromArgb(220, 205, 205, 199)) 20
        $Disposables.Add($wallPen)
        $Graphics.DrawLine($wallPen, $wallX, $Rect.Top + 205, $wallX, $Rect.Bottom - 80)
    }
}

function Export-CoverDirection {
    param([string]$Id, [scriptblock]$Draw)

    $designWidth = 2292
    $designHeight = 1434
    $renderScale = 2.0
    $masterWidth = [int]($designWidth * $renderScale)
    $masterHeight = [int]($designHeight * $renderScale)
    $bitmap = [System.Drawing.Bitmap]::new($masterWidth, $masterHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bitmap.SetResolution(600.0, 600.0)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $disposables = [System.Collections.Generic.List[System.IDisposable]]::new()
    try {
        $graphics.Clear($script:colors.Background)
        $graphics.ScaleTransform($renderScale, $renderScale)
        Draw-Grid $graphics $disposables
        Draw-Identity $graphics $script:brushes.Accent $script:brushes.Text $script:brushes.Muted $script:fonts.Brand.Font $script:fonts.Regular.Font
        & $Draw $graphics $disposables

        $masterPath = Join-Path $outputRoot ("{0}-master-4584x2868.png" -f $Id)
        $highResolutionPath = Join-Path $outputRoot ("{0}-bilibili-hq-2292x1434.png" -f $Id)
        $bilibiliPath = Join-Path $outputRoot ("{0}-bilibili-1146x717.png" -f $Id)
        $socialPath = Join-Path $outputRoot ("{0}-social-1920x1080.png" -f $Id)
        $previewPath = Join-Path $outputRoot ("{0}-preview-320x200.png" -f $Id)
        $bitmap.Save($masterPath, [System.Drawing.Imaging.ImageFormat]::Png)
        Save-ResizedPng $bitmap $highResolutionPath 2292 1434 ([System.Drawing.Rectangle]::new(0, 0, $masterWidth, $masterHeight))
        Save-ResizedPng $bitmap $bilibiliPath 1146 717 ([System.Drawing.Rectangle]::new(0, 0, $masterWidth, $masterHeight))
        $socialCropHeight = [int][Math]::Round($masterWidth / (16.0 / 9.0))
        $socialCropY = [int](($masterHeight - $socialCropHeight) / 2)
        Save-ResizedPng $bitmap $socialPath 1920 1080 ([System.Drawing.Rectangle]::new(0, $socialCropY, $masterWidth, $socialCropHeight))
        Save-ResizedPng $bitmap $previewPath 320 200 ([System.Drawing.Rectangle]::new(0, 0, $masterWidth, $masterHeight))
        return [ordered]@{
            id = $Id
            master = $masterPath
            bilibili_hq = $highResolutionPath
            bilibili = $bilibiliPath
            social_16_9 = $socialPath
            mobile_preview = $previewPath
        }
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
        foreach ($item in $disposables) { $item.Dispose() }
    }
}

$script:colors = [ordered]@{
    Background = ConvertTo-Color '#050608'
    Surface = ConvertTo-Color '#090b0e'
    Text = ConvertTo-Color '#f4f1ea'
    Muted = ConvertTo-Color '#a9adb4'
    Accent = ConvertTo-Color '#ff8a3d'
    Soft = ConvertTo-Color '#72a08d'
}
$script:brushes = [ordered]@{
    Surface = [System.Drawing.SolidBrush]::new($script:colors.Surface)
    Text = [System.Drawing.SolidBrush]::new($script:colors.Text)
    Muted = [System.Drawing.SolidBrush]::new($script:colors.Muted)
    Accent = [System.Drawing.SolidBrush]::new($script:colors.Accent)
    Soft = [System.Drawing.SolidBrush]::new($script:colors.Soft)
    AccentFill = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(82, $script:colors.Accent))
    SoftFill = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(68, $script:colors.Soft))
}
$script:fonts = [ordered]@{
    Regular = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SarasaGothicSC-Regular.ttf') 34
    Brand = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SarasaGothicSC-SemiBold.ttf') 100
    Small = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SarasaGothicSC-Regular.ttf') 31
    Body = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SarasaGothicSC-SemiBold.ttf') 58
    Grid = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SmileySans-Oblique.ttf') 184
    GridMetric = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SmileySans-Oblique.ttf') 368
    Bold = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SarasaGothicSC-Bold.ttf') 150
    Hero = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SmileySans-Oblique.ttf') 360
    Metric = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SmileySans-Oblique.ttf') 190
}

$exports = [System.Collections.Generic.List[object]]::new()
try {
    $exports.Add((Export-CoverDirection 'ep04-cover-a-fivefold' {
        param($g, $d)
        # Two-row, two-column information lockup in the upper-right safe area.
        # Both left-column rows use the same font size; the metric is exactly 2x.
        $leftCenterX = 1170.0
        $rowOne = '同球 · 同速'
        $rowTwo = '峰值差'
        $rowOneSize = $g.MeasureString($rowOne, $script:fonts.Grid.Font)
        $rowTwoSize = $g.MeasureString($rowTwo, $script:fonts.Grid.Font)
        $g.DrawString($rowOne, $script:fonts.Grid.Font, $script:brushes.Muted, $leftCenterX - $rowOneSize.Width / 2.0, 345)
        $g.DrawString($rowTwo, $script:fonts.Grid.Font, $script:brushes.Text, $leftCenterX - $rowTwoSize.Width / 2.0, 605)
        $g.DrawString('5X', $script:fonts.GridMetric.Font, $script:brushes.Accent, 1600, 345)

        # Enlarge and lower the comparison graph so it becomes the main visual.
        $rect = [System.Drawing.RectangleF]::new(100, 405, 2070, 820)
        Draw-Axis $g $rect $script:brushes.Muted $script:fonts.Small.Font $false $d
        Draw-Curve $g $rect 0.23 0.95 $script:colors.Accent $script:brushes.AccentFill $d
        Draw-Curve $g $rect 0.92 0.20 $script:colors.Soft $script:brushes.SoftFill $d
        $g.DrawString('钢板', $script:fonts.Body.Font, $script:brushes.Accent, 260, 1240)
        $g.DrawString('软垫', $script:fonts.Body.Font, $script:brushes.Soft, 1840, 1240)
    }))

    $exports.Add((Export-CoverDirection 'ep04-cover-b-duration' {
        param($g, $d)
        $g.DrawString('接触时间', $script:fonts.Bold.Font, $script:brushes.Text, 126, 270)
        $g.DrawString('8 ms', $script:fonts.Metric.Font, $script:brushes.Accent, 126, 485)
        $g.DrawString('40 ms', $script:fonts.Metric.Font, $script:brushes.Soft, 126, 700)
        $g.DrawString('峰值差 5 倍', $script:fonts.Body.Font, $script:brushes.Text, 136, 985)
        $rect = [System.Drawing.RectangleF]::new(970, 315, 1180, 760)
        Draw-Axis $g $rect $script:brushes.Muted $script:fonts.Small.Font $false $d
        Draw-Curve $g $rect 0.23 0.95 $script:colors.Accent $script:brushes.AccentFill $d
        Draw-Curve $g $rect 0.92 0.20 $script:colors.Soft $script:brushes.SoftFill $d
    }))

    $exports.Add((Export-CoverDirection 'ep04-cover-c-readout' {
        param($g, $d)
        $g.DrawString('峰值差', $script:fonts.Bold.Font, $script:brushes.Text, 126, 285)
        $g.DrawString('5×', $script:fonts.Hero.Font, $script:brushes.Accent, 105, 460)
        $g.DrawString('同球 · 同速', $script:fonts.Body.Font, $script:brushes.Muted, 136, 990)
        Draw-ImpactCard $g ([System.Drawing.RectangleF]::new(980, 260, 570, 870)) '钢板' '' $script:colors.Accent $false $script:brushes.Text $script:brushes.Surface $script:fonts.Body.Font $script:fonts.Metric.Font $d
        Draw-ImpactCard $g ([System.Drawing.RectangleF]::new(1600, 260, 570, 870)) '软垫' '' $script:colors.Soft $true $script:brushes.Text $script:brushes.Surface $script:fonts.Body.Font $script:fonts.Metric.Font $d
    }))

    $exports.Add((Export-CoverDirection 'ep04-cover-d-not-number' {
        param($g, $d)
        $g.DrawString('接触力', $script:fonts.Bold.Font, $script:brushes.Text, 126, 285)
        $g.DrawString('≠ 一个数', $script:fonts.Bold.Font, $script:brushes.Accent, 126, 500)
        $g.DrawString('钢板 vs 软垫', $script:fonts.Body.Font, $script:brushes.Muted, 136, 780)
        $rect = [System.Drawing.RectangleF]::new(970, 315, 1180, 760)
        Draw-Axis $g $rect $script:brushes.Muted $script:fonts.Small.Font $false $d
        Draw-Curve $g $rect 0.23 0.95 $script:colors.Accent $script:brushes.AccentFill $d
        Draw-Curve $g $rect 0.92 0.20 $script:colors.Soft $script:brushes.SoftFill $d
    }))

    $manifest = [ordered]@{
        schema_version = 1
        episode_id = 's01e04-impact-force-curve'
        platform = 'bilibili'
        source_video = 'renders/masters/s01e04-impact-force-curve/program-master-4k.mp4'
        exact_facts = [ordered]@{
            mass_kg = 1
            impact_speed_mps = 5
            rebound_speed_mps = 3
            impulse_ns = 8
            hard_contact_ms = 8
            hard_peak_force_n = 1570
            soft_contact_ms = 40
            soft_peak_force_n = 314
            peak_ratio = 5
        }
        recommended = 'ep04-cover-a-fivefold'
        exports = $exports
        provenance = 'Deterministic PowerShell System.Drawing composition using bundled project fonts and episode data.'
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $outputRoot 'cover.manifest.json')
}
finally {
    foreach ($brush in $script:brushes.Values) { $brush.Dispose() }
    foreach ($fontResource in $script:fonts.Values) {
        $fontResource.Font.Dispose()
        $fontResource.Collection.Dispose()
    }
}

Write-Host ("cover-export: {0}" -f $outputRoot)
Write-Host 'cover-export: generated 4 deterministic directions at 600 DPI with 4584x2868 masters'
