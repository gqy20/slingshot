[CmdletBinding()]
param(
    [switch]$Check,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Episode = @()
)

. (Join-Path $PSScriptRoot 'common.ps1')

$typst = $null
if (-not $Check) {
    $typst = Find-SlingshotTool -Name 'typst' -Fallback @(
        (Join-Path $HOME '.local\bin\typst.exe'),
        'C:\Users\gqy17\.local\bin\typst.exe'
    )
    $version = (& $typst --version | Select-Object -First 1)
    if ($version -notmatch '^typst 0\.15\.1\b') {
        throw "Typst 0.15.1 is required; got: $version"
    }
}

if ($Episode.Count -eq 0) {
    $Episode = @(Get-ChildItem (Join-Path $script:ProjectRoot 'content\episodes') `
        -File -Filter 's??e??-*.json' | Sort-Object Name | ForEach-Object FullName)
}

$tempRoot = New-SlingshotRenderTempDirectory -Kind 'formula'
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$assetCount = 0
$cachedCount = 0

try {
    foreach ($episodeInput in $Episode) {
        $episodePath = (Resolve-Path -LiteralPath $episodeInput).Path
        $config = Get-Content -Raw -Encoding UTF8 $episodePath | ConvertFrom-Json
        $explanationProperty = $config.story.PSObject.Properties['explanation']
        if ($null -eq $explanationProperty -or $null -eq $explanationProperty.Value) { continue }
        $explanation = $explanationProperty.Value
        $steps = @($explanation.steps)
        $typstSteps = @($steps | Where-Object { $_.typst })
        if ($typstSteps.Count -eq 0) { continue }
        if ($typstSteps.Count -ne $steps.Count) {
            throw "Every explanation step must declare typst: $($config.id)"
        }

        $assetDir = [string]$explanation.asset_dir
        if (-not $assetDir.StartsWith('res://assets/generated/formulas/') -or $assetDir.Contains('..')) {
            throw "Unsafe formula asset_dir in $($config.id): $assetDir"
        }
        $themeRelative = ([string]$config.theme).Substring('res://'.Length).Replace('/', '\')
        $theme = Get-Content -Raw -Encoding UTF8 (Join-Path $script:ProjectRoot $themeRelative) | ConvertFrom-Json
        $color = [string]$theme.colors.text
        $outputDir = Join-Path $script:ProjectRoot $assetDir.Substring('res://'.Length).Replace('/', '\')
        New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

        $manifestLines = @(
            "episode=$($config.id)",
            'typst_version=0.15.1',
            'template_version=5',
            'math_font=New Computer Modern Math',
            'format=svg',
            'background=transparent'
        )

        for ($index = 0; $index -lt $steps.Count; $index++) {
            $number = $index + 1
            $name = 'step-{0:d2}' -f $number
            $formulaFontSize = if ($steps[$index].PSObject.Properties['formula_font_size_pt']) {
                [int]$steps[$index].formula_font_size_pt
            } else { 96 }
            if ($formulaFontSize -lt 48 -or $formulaFontSize -gt 120) {
                throw "formula_font_size_pt must be between 48 and 120: $($config.id)/$name"
            }
            $formulaCanvasHeight = if ($steps[$index].PSObject.Properties['formula_canvas_height_pt']) {
                [int]$steps[$index].formula_canvas_height_pt
            } else { 240 }
            if ($formulaCanvasHeight -lt 240 -or $formulaCanvasHeight -gt 480) {
                throw "formula_canvas_height_pt must be between 240 and 480: $($config.id)/$name"
            }
            $formulaCanvasWidth = if ($steps[$index].PSObject.Properties['formula_canvas_width_pt']) {
                [int]$steps[$index].formula_canvas_width_pt
            } else { 1200 }
            if ($formulaCanvasWidth -lt 1200 -or $formulaCanvasWidth -gt 2400) {
                throw "formula_canvas_width_pt must be between 1200 and 2400: $($config.id)/$name"
            }
            $sourceHashText = "typst_version=0.15.1`ntemplate_version=5`nfill=$color`nfont_size_pt=$formulaFontSize`nsource=$($steps[$index].typst)"
            if ($steps[$index].PSObject.Properties['formula_canvas_height_pt']) {
                $sourceHashText += "`ncanvas_height_pt=$formulaCanvasHeight"
            }
            if ($steps[$index].PSObject.Properties['formula_canvas_width_pt']) {
                $sourceHashText += "`ncanvas_width_pt=$formulaCanvasWidth"
            }
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $bytes = [Text.Encoding]::UTF8.GetBytes($sourceHashText)
                $sourceHash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
            } finally { $sha.Dispose() }

            $svgPath = Join-Path $outputDir "$name.svg"
            $hashPath = Join-Path $outputDir "$name.sha256"
            $cachedHash = if (Test-Path $hashPath) { (Get-Content -Raw $hashPath).Trim() } else { '' }
            if ($cachedHash -eq $sourceHash -and (Test-Path $svgPath) -and (Get-Item $svgPath).Length -gt 0) {
                $cachedCount++
            } elseif ($Check) {
                throw "Formula asset is stale or missing: $($config.id)/$name.svg"
            } else {
                $typPath = Join-Path $tempRoot "$($config.id)-$name.typ"
                $compiledPath = Join-Path $tempRoot "$($config.id)-$name.svg"
                $typSource = @"
#set page(width: ${formulaCanvasWidth}pt, height: ${formulaCanvasHeight}pt, margin: 0pt, fill: none)
#set text(fill: rgb("$color"), size: ${formulaFontSize}pt)
#show math.equation: set text(font: "New Computer Modern Math")
#align(center + horizon)[$ $($steps[$index].typst) $]
"@
                Write-SlingshotUtf8 $typPath $typSource
                Invoke-SlingshotNative $typst compile --ignore-system-fonts --creation-timestamp 0 $typPath $compiledPath
                $svgText = Get-Content -Raw -Encoding UTF8 $compiledPath
                if ($svgText -notmatch '<svg' -or $svgText -match '<text') {
                    throw "Typst generated an invalid/non-path SVG: $($config.id)/$name"
                }
                Move-Item -Force $compiledPath $svgPath
                Write-SlingshotUtf8 $hashPath ($sourceHash + "`n")
            }
            $manifestLines += "$name.svg typst_sha256=$sourceHash fallback=$($steps[$index].equation)"
            $assetCount++
        }

        $manifestPath = Join-Path $outputDir 'formulas.manifest.txt'
        if ($Check -and -not (Test-Path $manifestPath)) {
            throw "Formula manifest missing: $($config.id)"
        }
        if (-not $Check) {
            Write-SlingshotUtf8 $manifestPath (($manifestLines -join "`n") + "`n")
        }
    }
} finally {
    if (Test-Path $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

if ($Check) {
    Write-Host "formula-assets: verified assets=$assetCount"
} else {
    Write-Host "formula-assets: built assets=$assetCount cached=$cachedCount typst=0.15.1"
}
