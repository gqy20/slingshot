param(
    [string]$OutputDir = 'renders/deliveries/s01e05-shortest-is-not-fastest/cover'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outputRoot = Join-Path $projectRoot $OutputDir
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

Add-Type -AssemblyName System.Drawing

function ConvertTo-Color {
    param([string]$Hex, [int]$Alpha = 255)
    $clean = $Hex.TrimStart('#')
    [System.Drawing.Color]::FromArgb(
        $Alpha,
        [Convert]::ToInt32($clean.Substring(0, 2), 16),
        [Convert]::ToInt32($clean.Substring(2, 2), 16),
        [Convert]::ToInt32($clean.Substring(4, 2), 16)
    )
}

function New-PrivateFont {
    param([string]$Path, [float]$Size)
    $collection = [System.Drawing.Text.PrivateFontCollection]::new()
    $collection.AddFontFile((Resolve-Path -LiteralPath $Path).Path)
    $font = [System.Drawing.Font]::new(
        $collection.Families[0], $Size, [System.Drawing.FontStyle]::Regular,
        [System.Drawing.GraphicsUnit]::Pixel
    )
    [pscustomobject]@{ Collection = $collection; Font = $font }
}

function New-Pen {
    param([System.Drawing.Color]$Color, [float]$Width)
    $pen = [System.Drawing.Pen]::new($Color, $Width)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $pen
}

function Save-ResizedPng {
    param(
        [System.Drawing.Bitmap]$Source,
        [string]$Path,
        [int]$Width,
        [int]$Height,
        [System.Drawing.Rectangle]$SourceRect
    )
    $target = [System.Drawing.Bitmap]::new(
        $Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $target.SetResolution(600.0, 600.0)
    $graphics = [System.Drawing.Graphics]::FromImage($target)
    try {
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage(
            $Source,
            [System.Drawing.Rectangle]::new(0, 0, $Width, $Height),
            $SourceRect,
            [System.Drawing.GraphicsUnit]::Pixel
        )
        $target.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $target.Dispose()
    }
}

function Draw-Identity {
    param([System.Drawing.Graphics]$Graphics)
    $Graphics.FillRectangle($script:brushes.Accent, 126, 105, 10, 54)
    $Graphics.DrawString('物理实验室', $script:fonts.Identity.Font, $script:brushes.Text, 166, 99)
    # Match EP03's compact identity lockup: roughly 48 px between the two labels.
    $Graphics.DrawString('最速降线实验', $script:fonts.Meta.Font, $script:brushes.Muted, 665, 126)
}

function Draw-Ball {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.PointF]$Center,
        [System.Drawing.Color]$Color,
        [float]$Radius,
        [System.Collections.Generic.List[System.IDisposable]]$Disposables
    )
    $halo = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(38, $Color))
    $fill = [System.Drawing.SolidBrush]::new($Color)
    $shine = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(165, 255, 255, 255))
    $Disposables.Add($halo)
    $Disposables.Add($fill)
    $Disposables.Add($shine)
    $Graphics.FillEllipse($halo, $Center.X - $Radius * 1.55, $Center.Y - $Radius * 1.55, $Radius * 3.1, $Radius * 3.1)
    $Graphics.FillEllipse($fill, $Center.X - $Radius, $Center.Y - $Radius, $Radius * 2.0, $Radius * 2.0)
    $Graphics.FillEllipse($shine, $Center.X - $Radius * 0.38, $Center.Y - $Radius * 0.52, $Radius * 0.28, $Radius * 0.28)
}

function Get-CubicBezierPoint {
    param(
        [System.Drawing.PointF]$P0,
        [System.Drawing.PointF]$P1,
        [System.Drawing.PointF]$P2,
        [System.Drawing.PointF]$P3,
        [double]$T
    )
    $u = 1.0 - $T
    [System.Drawing.PointF]::new(
        [float](
            $u * $u * $u * $P0.X +
            3.0 * $u * $u * $T * $P1.X +
            3.0 * $u * $T * $T * $P2.X +
            $T * $T * $T * $P3.X
        ),
        [float](
            $u * $u * $u * $P0.Y +
            3.0 * $u * $u * $T * $P1.Y +
            3.0 * $u * $T * $T * $P2.Y +
            $T * $T * $T * $P3.Y
        )
    )
}

function Draw-GhostBall {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.PointF]$Center,
        [System.Drawing.Color]$Color,
        [float]$Radius,
        [int]$Alpha,
        [System.Collections.Generic.List[System.IDisposable]]$Disposables
    )
    $halo = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb([Math]::Max(8, [int]($Alpha * 0.36)), $Color))
    $core = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb($Alpha, $Color))
    $Disposables.Add($halo)
    $Disposables.Add($core)
    $Graphics.FillEllipse($halo, $Center.X - $Radius * 1.8, $Center.Y - $Radius * 1.8, $Radius * 3.6, $Radius * 3.6)
    $Graphics.FillEllipse($core, $Center.X - $Radius, $Center.Y - $Radius, $Radius * 2.0, $Radius * 2.0)
}

function Draw-TrackPath {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Drawing2D.GraphicsPath]$Path,
        [System.Drawing.Color]$Color,
        [float]$Width,
        [System.Collections.Generic.List[System.IDisposable]]$Disposables
    )
    $glow = New-Pen ([System.Drawing.Color]::FromArgb(48, $Color)) ($Width * 2.8)
    $under = New-Pen ([System.Drawing.Color]::FromArgb(86, $Color)) ($Width * 1.55)
    $line = New-Pen $Color $Width
    $Disposables.Add($glow)
    $Disposables.Add($under)
    $Disposables.Add($line)
    $Graphics.DrawPath($glow, $Path)
    $Graphics.DrawPath($under, $Path)
    $Graphics.DrawPath($line, $Path)
}

function Draw-TrackStage {
    param(
        [System.Drawing.Graphics]$Graphics,
        [bool]$ShowArc,
        [bool]$ShowTimes,
        [System.Collections.Generic.List[System.IDisposable]]$Disposables,
        [bool]$FreezeFrame = $false
    )
    # Keep the experiment on the left and let its motion lead into the conclusion
    # on the right. The paths still descend left-to-right; they are not mirrored.
    $start = [System.Drawing.PointF]::new(150, 315)
    $finish = [System.Drawing.PointF]::new(1220, 1110)

    $linePath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $cycloidPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $arcPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $Disposables.Add($linePath)
    $Disposables.Add($cycloidPath)
    $Disposables.Add($arcPath)
    $linePath.AddLine($start, $finish)
    $cycloidPath.AddBezier($start, [System.Drawing.PointF]::new(164, 800), [System.Drawing.PointF]::new(565, 1110), $finish)
    $arcPath.AddBezier($start, [System.Drawing.PointF]::new(260, 680), [System.Drawing.PointF]::new(675, 1015), $finish)

    Draw-TrackPath $Graphics $linePath $script:colors.Line 10 $Disposables
    if ($ShowArc) { Draw-TrackPath $Graphics $arcPath $script:colors.Arc 9 $Disposables }
    Draw-TrackPath $Graphics $cycloidPath $script:colors.Cycloid 13 $Disposables

    if ($FreezeFrame) {
        # A deterministic speed-light ramp: the cycloid becomes more luminous
        # toward the finish without changing its geometry.
        $cycloidC1 = [System.Drawing.PointF]::new(164, 800)
        $cycloidC2 = [System.Drawing.PointF]::new(565, 1110)
        $previous = Get-CubicBezierPoint $start $cycloidC1 $cycloidC2 $finish 0.50
        for ($index = 1; $index -le 12; $index++) {
            $t = 0.50 + $index * (0.50 / 12.0)
            $current = Get-CubicBezierPoint $start $cycloidC1 $cycloidC2 $finish $t
            $rampPen = New-Pen (
                [System.Drawing.Color]::FromArgb(14 + $index * 5, $script:colors.Cycloid)
            ) (14.0 + $index * 0.65)
            $Disposables.Add($rampPen)
            $Graphics.DrawLine($rampPen, $previous, $current)
            $previous = $current
        }

        foreach ($ghost in @(
            @{ T = 0.78; Alpha = 30; Radius = 15 },
            @{ T = 0.86; Alpha = 46; Radius = 16 },
            @{ T = 0.93; Alpha = 68; Radius = 18 }
        )) {
            $point = Get-CubicBezierPoint $start $cycloidC1 $cycloidC2 $finish $ghost.T
            Draw-GhostBall $Graphics $point $script:colors.Cycloid $ghost.Radius $ghost.Alpha $Disposables
        }
    }

    $startBrush = [System.Drawing.SolidBrush]::new($script:colors.Text)
    $finishBrush = [System.Drawing.SolidBrush]::new($script:colors.Background)
    $endpointPen = New-Pen ([System.Drawing.Color]::FromArgb(190, $script:colors.Text)) 4
    $Disposables.Add($startBrush)
    $Disposables.Add($finishBrush)
    $Disposables.Add($endpointPen)
    $Graphics.FillEllipse($finishBrush, $start.X - 11, $start.Y - 11, 22, 22)
    $Graphics.DrawEllipse($endpointPen, $start.X - 11, $start.Y - 11, 22, 22)
    $Graphics.FillEllipse($finishBrush, $finish.X - 11, $finish.Y - 11, 22, 22)
    $Graphics.DrawEllipse($endpointPen, $finish.X - 11, $finish.Y - 11, 22, 22)

    # At the instant the cycloid arrives, the straight-track ball has covered
    # (t / T)^2 of its path because its acceleration along the line is constant.
    $lineProgressAtCycloidArrival = [Math]::Pow(1.790 / 2.150, 2.0)
    $lineBall = [System.Drawing.PointF]::new(
        $start.X + ($finish.X - $start.X) * $lineProgressAtCycloidArrival,
        $start.Y + ($finish.Y - $start.Y) * $lineProgressAtCycloidArrival
    )
    if ($FreezeFrame) {
        foreach ($ghost in @(
            @{ Progress = 0.55; Alpha = 28; Radius = 14 },
            @{ Progress = 0.60; Alpha = 44; Radius = 15 },
            @{ Progress = 0.65; Alpha = 62; Radius = 17 }
        )) {
            $point = [System.Drawing.PointF]::new(
                $start.X + ($finish.X - $start.X) * $ghost.Progress,
                $start.Y + ($finish.Y - $start.Y) * $ghost.Progress
            )
            Draw-GhostBall $Graphics $point $script:colors.Line $ghost.Radius $ghost.Alpha $Disposables
        }

        $pulseInner = New-Pen ([System.Drawing.Color]::FromArgb(112, $script:colors.Cycloid)) 5
        $pulseOuter = New-Pen ([System.Drawing.Color]::FromArgb(52, $script:colors.Cycloid)) 3
        $Disposables.Add($pulseInner)
        $Disposables.Add($pulseOuter)
        $Graphics.DrawEllipse($pulseInner, $finish.X - 54, $finish.Y - 54, 108, 108)
        $Graphics.DrawEllipse($pulseOuter, $finish.X - 96, $finish.Y - 96, 192, 192)
    }
    Draw-Ball $Graphics $lineBall $script:colors.Line 22 $Disposables
    if ($ShowArc) {
        Draw-Ball $Graphics ([System.Drawing.PointF]::new(1055, 1070)) $script:colors.Arc 22 $Disposables
    }
    Draw-Ball $Graphics $finish $script:colors.Cycloid 27 $Disposables

    if ($ShowTimes) {
        $Graphics.DrawString('直线  2.150 s', $script:fonts.Data.Font, $script:brushes.Line, 1370, 935)
        $Graphics.DrawString('摆线  1.790 s', $script:fonts.Data.Font, $script:brushes.Cycloid, 1370, 1005)
    }
}

function Export-CoverDirection {
    param([string]$Id, [scriptblock]$Draw)

    $designWidth = 2292
    $designHeight = 1434
    $renderScale = 2.0
    $masterWidth = [int]($designWidth * $renderScale)
    $masterHeight = [int]($designHeight * $renderScale)
    $bitmap = [System.Drawing.Bitmap]::new(
        $masterWidth, $masterHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $bitmap.SetResolution(600.0, 600.0)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $disposables = [System.Collections.Generic.List[System.IDisposable]]::new()
    try {
        $graphics.Clear($script:colors.Background)
        $graphics.ScaleTransform($renderScale, $renderScale)
        Draw-Identity $graphics
        & $Draw $graphics $disposables

        $masterPath = Join-Path $outputRoot ("{0}-master-4584x2868.png" -f $Id)
        $hqPath = Join-Path $outputRoot ("{0}-bilibili-hq-2292x1434.png" -f $Id)
        $standardPath = Join-Path $outputRoot ("{0}-bilibili-1146x717.png" -f $Id)
        $socialPath = Join-Path $outputRoot ("{0}-social-1920x1080.png" -f $Id)
        $previewPath = Join-Path $outputRoot ("{0}-preview-320x200.png" -f $Id)
        $bitmap.Save($masterPath, [System.Drawing.Imaging.ImageFormat]::Png)
        Save-ResizedPng $bitmap $hqPath 2292 1434 ([System.Drawing.Rectangle]::new(0, 0, $masterWidth, $masterHeight))
        Save-ResizedPng $bitmap $standardPath 1146 717 ([System.Drawing.Rectangle]::new(0, 0, $masterWidth, $masterHeight))
        $socialCropHeight = [int][Math]::Round($masterWidth / (16.0 / 9.0))
        $socialCropY = [int](($masterHeight - $socialCropHeight) / 2)
        Save-ResizedPng $bitmap $socialPath 1920 1080 ([System.Drawing.Rectangle]::new(0, $socialCropY, $masterWidth, $socialCropHeight))
        Save-ResizedPng $bitmap $previewPath 320 200 ([System.Drawing.Rectangle]::new(0, 0, $masterWidth, $masterHeight))
        [ordered]@{
            id = $Id
            master = [IO.Path]::GetFileName($masterPath)
            bilibili_hq = [IO.Path]::GetFileName($hqPath)
            bilibili = [IO.Path]::GetFileName($standardPath)
            social_16_9 = [IO.Path]::GetFileName($socialPath)
            mobile_preview = [IO.Path]::GetFileName($previewPath)
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
    Text = ConvertTo-Color '#f4f1ea'
    Muted = ConvertTo-Color '#9da2aa'
    Accent = ConvertTo-Color '#ff8a3d'
    Line = ConvertTo-Color '#7594b3'
    Arc = ConvertTo-Color '#d6a85f'
    Cycloid = ConvertTo-Color '#f06a47'
}
$script:brushes = [ordered]@{
    Text = [System.Drawing.SolidBrush]::new($script:colors.Text)
    Muted = [System.Drawing.SolidBrush]::new($script:colors.Muted)
    Accent = [System.Drawing.SolidBrush]::new($script:colors.Accent)
    Line = [System.Drawing.SolidBrush]::new($script:colors.Line)
    Arc = [System.Drawing.SolidBrush]::new($script:colors.Arc)
    Cycloid = [System.Drawing.SolidBrush]::new($script:colors.Cycloid)
}
$script:fonts = [ordered]@{
    Identity = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SarasaGothicSC-SemiBold.ttf') 82
    Meta = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SarasaGothicSC-Regular.ttf') 34
    Eyebrow = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SarasaGothicSC-SemiBold.ttf') 66
    Hero = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SmileySans-Oblique.ttf') 242
    HeroSymbol = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SmileySans-Oblique.ttf') 310
    HeroCompact = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SmileySans-Oblique.ttf') 218
    Metric = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SmileySans-Oblique.ttf') 210
    Body = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SarasaGothicSC-SemiBold.ttf') 68
    Data = New-PrivateFont (Join-Path $projectRoot 'assets/fonts/SarasaMonoSC-SemiBold.ttf') 58
}

$exports = [System.Collections.Generic.List[object]]::new()
try {
    $exports.Add((Export-CoverDirection 'ep05-cover-a-shortest-not-fastest' {
        param($g, $d)
        $g.DrawString('最短', $script:fonts.Hero.Font, $script:brushes.Text, 1350, 330)
        $g.DrawString('≠ 最快', $script:fonts.Hero.Font, $script:brushes.Cycloid, 1350, 680)
        Draw-TrackStage $g $false $false $d
    }))

    $exports.Add((Export-CoverDirection 'ep05-cover-b-line-vs-cycloid' {
        param($g, $d)
        $g.DrawString('直线最短', $script:fonts.HeroCompact.Font, $script:brushes.Text, 1350, 380)
        $g.DrawString('摆线先到', $script:fonts.HeroCompact.Font, $script:brushes.Cycloid, 1350, 665)
        $g.DrawString('同一起点 · 同一终点', $script:fonts.Body.Font, $script:brushes.Muted, 1370, 995)
        Draw-TrackStage $g $false $false $d
    }))

    $exports.Add((Export-CoverDirection 'ep05-cover-c-time-proof' {
        param($g, $d)
        $g.DrawString('直线', $script:fonts.Eyebrow.Font, $script:brushes.Line, 1370, 315)
        $g.DrawString('2.150 s', $script:fonts.Metric.Font, $script:brushes.Line, 1335, 390)
        $g.DrawString('摆线', $script:fonts.Eyebrow.Font, $script:brushes.Cycloid, 1370, 690)
        $g.DrawString('1.790 s', $script:fonts.Metric.Font, $script:brushes.Cycloid, 1335, 765)
        $g.DrawString('更长的路，反而更快', $script:fonts.Body.Font, $script:brushes.Text, 1370, 1085)
        Draw-TrackStage $g $false $false $d
    }))

    $exports.Add((Export-CoverDirection 'ep05-cover-d-distance-time' {
        param($g, $d)
        $g.DrawString('多走', $script:fonts.Eyebrow.Font, $script:brushes.Muted, 1370, 325)
        $g.DrawString('0.92 m', $script:fonts.Metric.Font, $script:brushes.Text, 1335, 390)
        $g.DrawString('却快', $script:fonts.Eyebrow.Font, $script:brushes.Muted, 1370, 700)
        $g.DrawString('0.36 s', $script:fonts.Metric.Font, $script:brushes.Cycloid, 1335, 765)
        $g.DrawString('距离短 ≠ 时间短', $script:fonts.Body.Font, $script:brushes.Text, 1370, 1085)
        Draw-TrackStage $g $true $false $d
    }))

    $exports.Add((Export-CoverDirection 'ep05-cover-e-freeze-frame' {
        param($g, $d)
        Draw-TrackStage $g $false $false $d $true

        $symbolBrush = [System.Drawing.SolidBrush]::new(
            [System.Drawing.Color]::FromArgb(148, $script:colors.Text)
        )
        $d.Add($symbolBrush)
        $g.DrawString('最短', $script:fonts.Hero.Font, $script:brushes.Text, 1540, 315)
        $g.DrawString('≠', $script:fonts.HeroSymbol.Font, $symbolBrush, 1250, 525)
        $g.DrawString('最快', $script:fonts.Hero.Font, $script:brushes.Cycloid, 1540, 755)
    }))

    $manifest = [ordered]@{
        schema_version = 1
        episode_id = 's01e05-shortest-is-not-fastest'
        platform = 'bilibili'
        source_video = 'renders/masters/s01e05-shortest-is-not-fastest/program-master-4k.mp4'
        exact_facts = [ordered]@{
            line_path_m = 11.662
            cycloid_path_m = 12.58
            line_arrival_s = 2.150
            arc_arrival_s = 1.821
            cycloid_arrival_s = 1.790
            cycloid_arc_lead_ms = 30
            cycloid_line_lead_s = 0.360
            extra_distance_m_rounded = 0.92
        }
        recommended = 'ep05-cover-a-shortest-not-fastest'
        exports = $exports
        provenance = 'Deterministic PowerShell System.Drawing composition using bundled project fonts and exact episode values.'
    }
    $manifestPath = Join-Path $outputRoot 'cover.manifest.json'
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $manifestPath
}
finally {
    foreach ($brush in $script:brushes.Values) { $brush.Dispose() }
    foreach ($fontResource in $script:fonts.Values) {
        $fontResource.Font.Dispose()
        $fontResource.Collection.Dispose()
    }
}

Write-Host ("cover-export: {0}" -f $outputRoot)
Write-Host 'cover-export: generated 5 deterministic directions at 600 DPI with 4584x2868 masters'
