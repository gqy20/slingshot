param(
    [string]$OutputDir = 'renders/publishing/s01e03-angle-with-drag/cover'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$OutputRoot = Join-Path $ProjectRoot $OutputDir
$DataPath = Join-Path $OutputRoot 'trajectory-data.json'
$GodotLog = Join-Path $ProjectRoot '.godot/cover-export.log'

New-Item -ItemType Directory -Force $OutputRoot | Out-Null

Push-Location $ProjectRoot
try {
    & godot --headless --path . --log-file $GodotLog --script res://scripts/export_bilibili_cover.gd -- $DataPath
    if ($LASTEXITCODE -ne 0) {
        throw "Godot trajectory export failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

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

function Get-UnicodeText {
    param([string]$Escaped)
    return [regex]::Unescape($Escaped)
}

function New-PrivateFont {
    param([string]$Path, [float]$Size)
    $collection = [System.Drawing.Text.PrivateFontCollection]::new()
    $collection.AddFontFile((Resolve-Path $Path).Path)
    $font = [System.Drawing.Font]::new(
        $collection.Families[0],
        $Size,
        [System.Drawing.FontStyle]::Regular,
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

function Draw-Trajectory {
    param(
        [System.Drawing.Graphics]$Graphics,
        [object[]]$Points,
        [System.Drawing.PointF]$Launch,
        [double]$OriginX,
        [double]$OriginY,
        [double]$XScale,
        [double]$YScale,
        [System.Drawing.Color]$Color,
        [float]$GlowWidth,
        [float]$LineWidth
    )
    $screenPoints = [System.Collections.Generic.List[System.Drawing.PointF]]::new()
    foreach ($point in $Points) {
        $screenPoints.Add([System.Drawing.PointF]::new(
            [float]($Launch.X + ([double]$point[0] - $OriginX) * $XScale),
            [float]($Launch.Y - ($OriginY - [double]$point[1]) * $YScale)
        ))
    }
    $array = $screenPoints.ToArray()
    $glow = New-Pen ([System.Drawing.Color]::FromArgb(38, $Color)) $GlowWidth
    $line = New-Pen $Color $LineWidth
    try {
        $Graphics.DrawLines($glow, $array)
        $Graphics.DrawLines($line, $array)
    }
    finally {
        $glow.Dispose()
        $line.Dispose()
    }
    return $array
}

function Draw-AngleMark {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.PointF]$Origin,
        [float]$Angle,
        [float]$Radius,
        [System.Drawing.Color]$Color
    )
    $pen = New-Pen ([System.Drawing.Color]::FromArgb(150, $Color)) 4
    try {
        $Graphics.DrawArc($pen, $Origin.X - $Radius, $Origin.Y - $Radius, $Radius * 2, $Radius * 2, -$Angle, $Angle)
    }
    finally {
        $pen.Dispose()
    }
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

$data = Get-Content -Raw -Encoding UTF8 $DataPath | ConvertFrom-Json
$record40 = $data.records.angle_40
$record45 = $data.records.angle_45

$masterWidth = 2292
$masterHeight = 1434
$background = ConvertTo-Color '#050608'
$surface = ConvertTo-Color '#090b0e'
$text = ConvertTo-Color '#f4f1ea'
$muted = ConvertTo-Color '#a9adb4'
$accent = ConvertTo-Color '#ff8a3d'
$angle40 = ConvertTo-Color '#98ae7a'
$angle45 = ConvertTo-Color '#c0af6b'

$fontRegular = New-PrivateFont (Join-Path $ProjectRoot 'assets/fonts/SarasaGothicSC-Regular.ttf') 34
$fontBrand = New-PrivateFont (Join-Path $ProjectRoot 'assets/fonts/SarasaGothicSC-SemiBold.ttf') 42
$fontBody = New-PrivateFont (Join-Path $ProjectRoot 'assets/fonts/SarasaGothicSC-SemiBold.ttf') 43
$fontBold = New-PrivateFont (Join-Path $ProjectRoot 'assets/fonts/SarasaGothicSC-Bold.ttf') 142
$fontAngle = New-PrivateFont (Join-Path $ProjectRoot 'assets/fonts/SarasaGothicSC-SemiBold.ttf') 45
$fontHero = New-PrivateFont (Join-Path $ProjectRoot 'assets/fonts/SmileySans-Oblique.ttf') 292

$bitmap = [System.Drawing.Bitmap]::new($masterWidth, $masterHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

$disposables = [System.Collections.Generic.List[System.IDisposable]]::new()
try {
    $graphics.Clear($background)

    $gridPenVertical = New-Pen ([System.Drawing.Color]::FromArgb(28, 48, 54, 61)) 2
    $gridPenHorizontal = New-Pen ([System.Drawing.Color]::FromArgb(22, 48, 54, 61)) 2
    $disposables.Add($gridPenVertical)
    $disposables.Add($gridPenHorizontal)
    for ($x = 1070; $x -lt 2210; $x += 150) { $graphics.DrawLine($gridPenVertical, $x, 210, $x, 1190) }
    for ($y = 310; $y -lt 1190; $y += 145) { $graphics.DrawLine($gridPenHorizontal, 1010, $y, 2210, $y) }

    $accentBrush = [System.Drawing.SolidBrush]::new($accent)
    $textBrush = [System.Drawing.SolidBrush]::new($text)
    $mutedBrush = [System.Drawing.SolidBrush]::new($muted)
    $angle40Brush = [System.Drawing.SolidBrush]::new($angle40)
    $angle45Brush = [System.Drawing.SolidBrush]::new($angle45)
    $surfaceBrush = [System.Drawing.SolidBrush]::new($surface)
    foreach ($item in @($accentBrush, $textBrush, $mutedBrush, $angle40Brush, $angle45Brush, $surfaceBrush)) { $disposables.Add($item) }

    $graphics.FillRectangle($accentBrush, 126, 112, 12, 54)
    $identityMain = Get-UnicodeText '\u7269\u7406\u5b9e\u9a8c\u5ba4'
    $identitySecondary = Get-UnicodeText '\u7a7a\u6c14\u963b\u529b\u5b9e\u9a8c'
    $headlineAngle = Get-UnicodeText '40\u00b0'
    $headlineCopy = Get-UnicodeText '\u53cd\u800c\u66f4\u8fdc\uff1f'
    $controlCopy = Get-UnicodeText '\u540c\u4e00\u9897\u7403 \u00b7 \u540c\u6837\u7684\u901f\u5ea6'
    $graphics.DrawString($identityMain, $fontBrand.Font, $textBrush, 166, 103)
    $graphics.DrawString($identitySecondary, $fontRegular.Font, $mutedBrush, 410, 112)

    $graphics.DrawString($headlineAngle, $fontHero.Font, $angle40Brush, 120, 278)
    $graphics.DrawString($headlineCopy, $fontBold.Font, $textBrush, 132, 618)
    $headlineRule = New-Pen ([System.Drawing.Color]::FromArgb(46, $text)) 3
    $disposables.Add($headlineRule)
    $graphics.DrawLine($headlineRule, 134, 833, 770, 833)
    $graphics.DrawString($controlCopy, $fontBody.Font, $mutedBrush, 136, 858)

    $launch = [System.Drawing.PointF]::new(1050, 1110)
    $maxRange = [Math]::Max([double]$record40.metrics.flight_range_m, [double]$record45.metrics.flight_range_m)
    $maxHeight = [Math]::Max([double]$record40.metrics.max_height_m, [double]$record45.metrics.max_height_m)
    $xScale = 1080.0 / ($maxRange * 1.06)
    $yScale = 735.0 / ($maxHeight * 1.14)
    $originX = [double]$record40.points_m[0][0]
    $originY = [double]$record40.points_m[0][1]

    $groundPen = New-Pen ([System.Drawing.Color]::FromArgb(132, $text)) 4
    $disposables.Add($groundPen)
    $graphics.DrawLine($groundPen, 1000, $launch.Y, 2210, $launch.Y)
    $graphics.FillEllipse($textBrush, $launch.X - 15, $launch.Y - 15, 30, 30)
    $backgroundBrush = [System.Drawing.SolidBrush]::new($background)
    $disposables.Add($backgroundBrush)
    $graphics.FillEllipse($backgroundBrush, $launch.X - 7, $launch.Y - 7, 14, 14)

    $points45 = Draw-Trajectory $graphics $record45.points_m $launch $originX $originY $xScale $yScale $angle45 23 7
    $points40 = Draw-Trajectory $graphics $record40.points_m $launch $originX $originY $xScale $yScale $angle40 29 10
    Draw-AngleMark $graphics $launch 45 168 $angle45
    Draw-AngleMark $graphics $launch 40 122 $angle40

    $end45 = $points45[$points45.Length - 1]
    $end40 = $points40[$points40.Length - 1]
    $graphics.FillEllipse($angle45Brush, $end45.X - 13, $end45.Y - 13, 26, 26)
    $graphics.FillEllipse($angle40Brush, $end40.X - 15, $end40.Y - 15, 30, 30)

    $lensCenter = [System.Drawing.PointF]::new(1990, 1080)
    $connector45 = New-Pen ([System.Drawing.Color]::FromArgb(96, $angle45)) 3
    $connector40 = New-Pen ([System.Drawing.Color]::FromArgb(116, $angle40)) 3
    $disposables.Add($connector45)
    $disposables.Add($connector40)
    $graphics.DrawLine($connector45, $end45.X, $end45.Y - 8, $lensCenter.X - 70, $lensCenter.Y - 105)
    $graphics.DrawLine($connector40, $end40.X, $end40.Y - 8, $lensCenter.X + 70, $lensCenter.Y - 105)

    # Draw the handle behind the lens. The fill hides its inner end and the rim
    # closes the seam, avoiding the visible round-cap bump from the first version.
    $lensHandle = New-Pen ([System.Drawing.Color]::FromArgb(158, $text)) 14
    $disposables.Add($lensHandle)
    $graphics.DrawLine(
        $lensHandle,
        $lensCenter.X + 110,
        $lensCenter.Y + 110,
        $lensCenter.X + 198,
        $lensCenter.Y + 198
    )
    $graphics.FillEllipse($surfaceBrush, $lensCenter.X - 172, $lensCenter.Y - 172, 344, 344)
    $lensPen = New-Pen ([System.Drawing.Color]::FromArgb(174, $text)) 4
    $lensRail = New-Pen ([System.Drawing.Color]::FromArgb(96, $text)) 4
    foreach ($item in @($lensPen, $lensRail)) { $disposables.Add($item) }
    $graphics.DrawEllipse($lensPen, $lensCenter.X - 172, $lensCenter.Y - 172, 344, 344)
    $graphics.DrawLine($lensRail, $lensCenter.X - 122, $lensCenter.Y + 34, $lensCenter.X + 122, $lensCenter.Y + 34)

    $lens45 = [System.Drawing.PointF]::new($lensCenter.X - 51, $lensCenter.Y + 34)
    $lens40 = [System.Drawing.PointF]::new($lensCenter.X + 51, $lensCenter.Y + 34)
    $marker45 = New-Pen ([System.Drawing.Color]::FromArgb(225, $angle45)) 5
    $marker40 = New-Pen ([System.Drawing.Color]::FromArgb(235, $angle40)) 5
    $disposables.Add($marker45)
    $disposables.Add($marker40)
    $graphics.DrawLine($marker45, $lens45.X, $lens45.Y - 48, $lens45.X, $lens45.Y)
    $graphics.DrawLine($marker40, $lens40.X, $lens40.Y - 48, $lens40.X, $lens40.Y)
    $graphics.FillEllipse($angle45Brush, $lens45.X - 14, $lens45.Y - 14, 28, 28)
    $graphics.FillEllipse($angle40Brush, $lens40.X - 16, $lens40.Y - 16, 32, 32)
    $graphics.DrawString((Get-UnicodeText '45\u00b0'), $fontAngle.Font, $angle45Brush, $lensCenter.X - 122, $lensCenter.Y - 99)
    $graphics.DrawString((Get-UnicodeText '40\u00b0'), $fontAngle.Font, $angle40Brush, $lensCenter.X + 34, $lensCenter.Y - 99)

    $masterPath = Join-Path $OutputRoot 's01e03-cover-master-2292x1434.png'
    $bilibiliPath = Join-Path $OutputRoot 's01e03-cover-bilibili-1146x717.png'
    $socialPath = Join-Path $OutputRoot 's01e03-cover-social-1920x1080.png'
    $previewPath = Join-Path $OutputRoot 's01e03-cover-preview-320x200.png'
    $bitmap.Save($masterPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Save-ResizedPng $bitmap $bilibiliPath 1146 717 ([System.Drawing.Rectangle]::new(0, 0, $masterWidth, $masterHeight))
    $socialCropHeight = [int][Math]::Round($masterWidth / (16.0 / 9.0))
    $socialCropY = [int](($masterHeight - $socialCropHeight) / 2)
    Save-ResizedPng $bitmap $socialPath 1920 1080 ([System.Drawing.Rectangle]::new(0, $socialCropY, $masterWidth, $socialCropHeight))
    Save-ResizedPng $bitmap $previewPath 320 200 ([System.Drawing.Rectangle]::new(0, 0, $masterWidth, $masterHeight))

    $manifest = [ordered]@{
        schema_version = 1
        episode_id = 's01e03-angle-with-drag'
        source_sidecar = 'renders/final/s01e03-angle-with-drag.json'
        source_preset = 'presets/t001-drag-base.json'
        headline = ($headlineAngle + $headlineCopy)
        identity = ($identityMain + (Get-UnicodeText ' \u00b7 ') + $identitySecondary)
        data = [ordered]@{
            angle_40_range_m = [double]$record40.metrics.flight_range_m
            angle_45_range_m = [double]$record45.metrics.flight_range_m
        }
        exports = @(
            [ordered]@{ path = $masterPath; width = 2292; height = 1434; purpose = 'master' }
            [ordered]@{ path = $bilibiliPath; width = 1146; height = 717; purpose = 'bilibili' }
            [ordered]@{ path = $socialPath; width = 1920; height = 1080; purpose = 'social_16_9' }
            [ordered]@{ path = $previewPath; width = 320; height = 200; purpose = 'mobile_readability' }
        )
        provenance = 'Deterministic Godot trajectory export and PowerShell System.Drawing composition using bundled project fonts.'
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'cover.manifest.json')
}
finally {
    $graphics.Dispose()
    $bitmap.Dispose()
    foreach ($item in $disposables) { $item.Dispose() }
    foreach ($fontResource in @($fontRegular, $fontBrand, $fontBody, $fontBold, $fontAngle, $fontHero)) {
        $fontResource.Font.Dispose()
        $fontResource.Collection.Dispose()
    }
}

Write-Host ('cover-export: {0}' -f $OutputRoot)
Write-Host ('cover-export: 40deg={0:N5} m 45deg={1:N5} m' -f [double]$record40.metrics.flight_range_m, [double]$record45.metrics.flight_range_m)
