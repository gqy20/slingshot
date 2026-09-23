param(
    [string]$OutputDir = 'renders/deliveries/s01e06-earth-quasi-satellite/cover'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies @([System.Drawing.Bitmap].Assembly.Location, [System.Drawing.Color].Assembly.Location) -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;

public static class SphericalEarth {
    public static Bitmap Render(Bitmap map, int size) {
        Bitmap sphere = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        double radius = size * 0.5;
        double longitudeOffset = 30.0 * Math.PI / 180.0;
        for (int py = 0; py < size; py++) {
            double y = (py + 0.5 - radius) / radius;
            for (int px = 0; px < size; px++) {
                double x = (px + 0.5 - radius) / radius;
                double rr = x * x + y * y;
                if (rr > 1.0) continue;
                double z = Math.Sqrt(1.0 - rr);
                double latitude = Math.Asin(-y);
                double longitude = Math.Atan2(x, z) + longitudeOffset;
                double u = (longitude + Math.PI) / (Math.PI * 2.0);
                u -= Math.Floor(u);
                double v = 0.5 - latitude / Math.PI;
                int sx = Math.Min(map.Width - 1, (int)(u * map.Width));
                int sy = Math.Max(0, Math.Min(map.Height - 1, (int)(v * map.Height)));
                Color source = map.GetPixel(sx, sy);
                double incidence = Math.Max(0.0, -0.24 * x - 0.28 * y + 0.93 * z);
                double light = 0.28 + 0.72 * incidence;
                double atmosphere = Math.Pow(1.0 - z, 3.0) * 0.26;
                int red = Math.Min(255, (int)(source.R * light + 95 * atmosphere));
                int green = Math.Min(255, (int)(source.G * light + 154 * atmosphere));
                int blue = Math.Min(255, (int)(source.B * light + 255 * atmosphere));
                sphere.SetPixel(px, py, Color.FromArgb(255, red, green, blue));
            }
        }
        return sphere;
    }
}
'@

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outputRoot = Join-Path $projectRoot $OutputDir
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

function Color([string]$Hex, [int]$Alpha = 255) {
    $value = $Hex.TrimStart('#')
    [System.Drawing.Color]::FromArgb(
        $Alpha,
        [Convert]::ToInt32($value.Substring(0, 2), 16),
        [Convert]::ToInt32($value.Substring(2, 2), 16),
        [Convert]::ToInt32($value.Substring(4, 2), 16)
    )
}

function FontResource([string]$File, [float]$Size) {
    $collection = [System.Drawing.Text.PrivateFontCollection]::new()
    $collection.AddFontFile((Join-Path $projectRoot "assets/fonts/$File"))
    [pscustomobject]@{
        Collection = $collection
        Font = [System.Drawing.Font]::new($collection.Families[0], $Size,
            [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    }
}

function Save-Preview(
    [System.Drawing.Bitmap]$Source,
    [string]$Path,
    [int]$Width,
    [int]$Height,
    [System.Drawing.Rectangle]$SourceRect
) {
    $bitmap = [System.Drawing.Bitmap]::new($Width, $Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.DrawImage($Source, [System.Drawing.Rectangle]::new(0, 0, $Width, $Height),
            $SourceRect, [System.Drawing.GraphicsUnit]::Pixel)
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Draw-Earth([System.Drawing.Graphics]$Graphics, [System.Collections.Generic.List[System.IDisposable]]$Owned) {
    $cx = 540.0
    $cy = 840.0
    $r = 176.0
    $glowPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $glowPath.AddEllipse([System.Drawing.RectangleF]::new($cx - 260, $cy - 260, 520, 520))
    $Owned.Add($glowPath)
    $glow = [System.Drawing.Drawing2D.PathGradientBrush]::new($glowPath)
    $glow.CenterColor = Color '#5AAFFF' 65
    $glow.SurroundColors = @((Color '#5AAFFF' 0))
    $Owned.Add($glow)
    $Graphics.FillEllipse($glow, $cx - 260, $cy - 260, 520, 520)
    $earthBounds = [System.Drawing.RectangleF]::new($cx - $r, $cy - $r, $r * 2, $r * 2)
    $rim = [System.Drawing.Pen]::new((Color '#89C4FF' 135), 4)
    $Owned.Add($rim)
    $Graphics.DrawImage($script:earthSphere, $earthBounds)
    $Graphics.DrawEllipse($rim, $earthBounds)
}

function Draw-Orbit([System.Drawing.Graphics]$Graphics, [System.Collections.Generic.List[System.IDisposable]]$Owned) {
    # A graphic Earth-fixed loop, not a scale diagram or mission trajectory.
    $orbit = [System.Drawing.RectangleF]::new(92, 275, 900, 1060)
    $under = [System.Drawing.Pen]::new((Color '#F28B55' 60), 28)
    $core = [System.Drawing.Pen]::new((Color '#F59A67' 240), 10)
    $flare = [System.Drawing.Pen]::new((Color '#FFC08F' 245), 5)
    $Owned.Add($under)
    $Owned.Add($core)
    $Owned.Add($flare)
    foreach ($pen in @($under, $core, $flare)) {
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    }
    $Graphics.DrawEllipse($under, $orbit)
    $Graphics.DrawEllipse($core, $orbit)
    $Graphics.DrawArc($flare, $orbit, 264, 48)

    # Asteroid occupies the same point as the bright arc's end.
    $angle = 312.0 * [Math]::PI / 180.0
    $ax = 542.0 + 450.0 * [Math]::Cos($angle)
    $ay = 805.0 + 530.0 * [Math]::Sin($angle)
    foreach ($halo in @(
        @{ Radius = 92.0; Alpha = 12 },
        @{ Radius = 66.0; Alpha = 22 },
        @{ Radius = 48.0; Alpha = 39 }
    )) {
        $brush = [System.Drawing.SolidBrush]::new((Color '#FF955B' $halo.Alpha))
        $Owned.Add($brush)
        $Graphics.FillEllipse($brush, $ax - $halo.Radius, $ay - $halo.Radius,
            $halo.Radius * 2, $halo.Radius * 2)
    }
    $asteroid = [System.Drawing.SolidBrush]::new((Color '#FF9A62'))
    $Owned.Add($asteroid)
    $Graphics.FillPolygon($asteroid, [System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new($ax - 37, $ay - 19),
        [System.Drawing.PointF]::new($ax - 13, $ay - 42),
        [System.Drawing.PointF]::new($ax + 27, $ay - 30),
        [System.Drawing.PointF]::new($ax + 41, $ay + 5),
        [System.Drawing.PointF]::new($ax + 15, $ay + 39),
        [System.Drawing.PointF]::new($ax - 34, $ay + 25)
    ))
}

$fontIdentity = FontResource 'SarasaGothicSC-SemiBold.ttf' 74
$fontKicker = FontResource 'SarasaGothicSC-SemiBold.ttf' 65
$fontHero = FontResource 'SmileySans-Oblique.ttf' 212
$fontHeroLong = FontResource 'SmileySans-Oblique.ttf' 177
$ownedFonts = @($fontIdentity, $fontKicker, $fontHero, $fontHeroLong)
$earthMap = [System.Drawing.Bitmap]::new((Join-Path $projectRoot 'assets/video/celestial/sources/earth_blue_marble_2048.jpg'))
$script:earthSphere = [SphericalEarth]::Render($earthMap, 720)
$earthMap.Dispose()
$colors = @{
    Background = Color '#06090D'
    White = Color '#F4F5F2'
    Orange = Color '#FF975B'
    Muted = Color '#A7B7C5'
    Blue = Color '#76B8FB'
}
$ownedBrushes = @{}
foreach ($key in $colors.Keys) { $ownedBrushes[$key] = [System.Drawing.SolidBrush]::new($colors[$key]) }

try {
    foreach ($direction in @(
        @{ Id = 'a-not-a-moon'; First = '绕地球？'; Second = '却不是月亮'; Long = $true },
        @{ Id = 'b-orbits-the-sun'; First = '绕地球？'; Second = '其实绕太阳！'; Long = $true }
    )) {
        $width = 2292
        $height = 1434
        $scale = 2.0
        $bitmap = [System.Drawing.Bitmap]::new(4584, 2868)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $owned = [System.Collections.Generic.List[System.IDisposable]]::new()
        try {
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.Clear($colors.Background)
            $graphics.ScaleTransform($scale, $scale)

            Draw-Orbit $graphics $owned
            Draw-Earth $graphics $owned

            $graphics.FillRectangle($ownedBrushes.Orange, 112, 106, 10, 54)
            $graphics.DrawString('物理实验室', $fontIdentity.Font, $ownedBrushes.White, 153, 92)
            $graphics.DrawString('天问二号拍到的准卫星', $fontKicker.Font,
                $ownedBrushes.Muted, 1190, 310)
            $graphics.DrawString($direction.First, $fontHero.Font,
                $ownedBrushes.White, 1170, 490)
            $graphics.DrawString($direction.Second, $fontHeroLong.Font,
                $ownedBrushes.Orange, 1170, 790)

            $base = "ep06-cover-$($direction.Id)"
            $master = Join-Path $outputRoot "$base-master-4584x2868.png"
            $bilibili = Join-Path $outputRoot "$base-bilibili-1146x717.png"
            $preview = Join-Path $outputRoot "$base-preview-320x200.png"
            $social = Join-Path $outputRoot "$base-social-1920x1080.png"
            $bitmap.Save($master, [System.Drawing.Imaging.ImageFormat]::Png)
            Save-Preview $bitmap $bilibili 1146 717 ([System.Drawing.Rectangle]::new(0, 0, 4584, 2868))
            Save-Preview $bitmap $preview 320 200 ([System.Drawing.Rectangle]::new(0, 0, 4584, 2868))
            $cropHeight = [int][Math]::Round(4584 / (16.0 / 9.0))
            Save-Preview $bitmap $social 1920 1080 ([System.Drawing.Rectangle]::new(
                0, [int]((2868 - $cropHeight) / 2), 4584, $cropHeight))
        } finally {
            $graphics.Dispose()
            $bitmap.Dispose()
            foreach ($item in $owned) { $item.Dispose() }
        }
    }
} finally {
    $script:earthSphere.Dispose()
    foreach ($brush in $ownedBrushes.Values) { $brush.Dispose() }
    foreach ($resource in $ownedFonts) {
        $resource.Font.Dispose()
        $resource.Collection.Dispose()
    }
}

$manifest = [ordered]@{
    schema_version = 1
    episode_id = 's01e06-earth-quasi-satellite'
    platform = 'bilibili'
    recommended = 'ep06-cover-b-orbits-the-sun'
    alternate = 'ep06-cover-a-not-a-moon'
    design_size = '2292x1434'
    exports = @('4584x2868 master', '1146x717 bilibili', '320x200 mobile preview', '1920x1080 social')
    source = 'assets/video/celestial/sources/earth_blue_marble_2048.jpg'
    source_credit = 'NASA Earth Observatory — Blue Marble: Next Generation'
    source_url = 'https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/'
    accuracy_note = 'The orange Earth-fixed loop is an editorial schematic, not a to-scale orbit or mission trajectory.'
    cnsa_photo_used = $false
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $outputRoot 'cover.manifest.json')
Write-Host "cover-export: $outputRoot"
