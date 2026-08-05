[CmdletBinding()]
param(
    [string]$StartTime = '2010-01-01',
    [string]$StopTime = '2051-01-01',
    [string]$StepSize = '10d',
    [string]$Output = 'data\ephemerides\2016-ho3-earth-2010-2050.json'
)

. (Join-Path $PSScriptRoot 'common.ps1')

$apiBase = 'https://ssd.jpl.nasa.gov/api/horizons.api'
$queryTemplate = [ordered]@{
    format = 'json'
    OBJ_DATA = 'NO'
    MAKE_EPHEM = 'YES'
    EPHEM_TYPE = 'VECTORS'
    CENTER = '500@10'
    START_TIME = $StartTime
    STOP_TIME = $StopTime
    STEP_SIZE = $StepSize
    VEC_TABLE = '2'
    CSV_FORMAT = 'YES'
    OUT_UNITS = 'AU-D'
    REF_PLANE = 'ECLIPTIC'
    REF_SYSTEM = 'ICRF'
    VEC_CORR = 'NONE'
}

function Get-HorizonsVectorTable {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $query = [ordered]@{ COMMAND = $Command }
    foreach ($entry in $queryTemplate.GetEnumerator()) {
        $query[$entry.Key] = $entry.Value
    }
    $pairs = foreach ($entry in $query.GetEnumerator()) {
        [uri]::EscapeDataString([string]$entry.Key) + '=' +
            [uri]::EscapeDataString([string]$entry.Value)
    }
    $uri = $apiBase + '?' + ($pairs -join '&')
    Write-Host "horizons: fetch $Label command=$Command range=$StartTime..$StopTime step=$StepSize"
    $response = Invoke-RestMethod -Uri $uri -Method Get
    $errorProperty = $response.PSObject.Properties['error']
    if ($null -ne $errorProperty -and -not [string]::IsNullOrWhiteSpace([string]$errorProperty.Value)) {
        throw "Horizons error for ${Label}: $($errorProperty.Value)"
    }
    $raw = [string]$response.result
    $lines = $raw -split "`r?`n"
    $start = [Array]::IndexOf($lines, '$$SOE')
    $stop = [Array]::IndexOf($lines, '$$EOE')
    if ($start -lt 0 -or $stop -le $start) {
        throw "Horizons response for $Label does not contain a vector table."
    }
    $rows = @()
    for ($index = $start + 1; $index -lt $stop; $index++) {
        $parts = @($lines[$index].Split(',') | ForEach-Object { $_.Trim() })
        if ($parts.Count -lt 8) { continue }
        $rows += ,@(
            [double]::Parse($parts[0], [Globalization.CultureInfo]::InvariantCulture),
            $parts[1],
            [double]::Parse($parts[2], [Globalization.CultureInfo]::InvariantCulture),
            [double]::Parse($parts[3], [Globalization.CultureInfo]::InvariantCulture),
            [double]::Parse($parts[4], [Globalization.CultureInfo]::InvariantCulture),
            [double]::Parse($parts[5], [Globalization.CultureInfo]::InvariantCulture),
            [double]::Parse($parts[6], [Globalization.CultureInfo]::InvariantCulture),
            [double]::Parse($parts[7], [Globalization.CultureInfo]::InvariantCulture)
        )
    }
    if ($rows.Count -lt 2) { throw "Horizons returned too few rows for $Label." }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $rawBytes = [Text.Encoding]::UTF8.GetBytes($raw)
        $rawHash = ([BitConverter]::ToString($sha.ComputeHash($rawBytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
    [pscustomobject]@{
        label = $Label
        command = $Command
        query_url = $uri
        raw_response_sha256 = $rawHash
        rows = $rows
    }
}

$asteroid = Get-HorizonsVectorTable -Command '469219' -Label '469219 Kamoalewa (2016 HO3)'
$earth = Get-HorizonsVectorTable -Command '399' -Label 'Earth geocenter'
if ($asteroid.rows.Count -ne $earth.rows.Count) {
    throw "Horizons row counts differ: asteroid=$($asteroid.rows.Count) earth=$($earth.rows.Count)"
}
for ($index = 0; $index -lt $asteroid.rows.Count; $index++) {
    if ([Math]::Abs([double]$asteroid.rows[$index][0] - [double]$earth.rows[$index][0]) -gt 1e-9) {
        throw "Horizons epochs differ at row $index."
    }
}

$payload = [ordered]@{
    schema_version = 1
    id = 'jpl-horizons-2016-ho3-earth-2010-2050'
    generated_at_utc = [DateTime]::UtcNow.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    source = [ordered]@{
        provider = 'NASA/JPL Solar System Dynamics'
        service = 'Horizons API'
        documentation = 'https://ssd.jpl.nasa.gov/horizons/'
        center = 'Sun center (500@10)'
        reference_system = 'ICRF'
        reference_plane = 'Ecliptic of J2000'
        vector_correction = 'NONE'
        units = 'AU and AU/day'
        start_time = $StartTime
        stop_time = $StopTime
        step_size = $StepSize
    }
    columns = @('jd_tdb', 'calendar_tdb', 'x_au', 'y_au', 'z_au', 'vx_au_d', 'vy_au_d', 'vz_au_d')
    asteroid = $asteroid
    earth = $earth
}

$outputPath = if ([IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path $script:ProjectRoot $Output }
$outputParent = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
Write-SlingshotUtf8 $outputPath ($payload | ConvertTo-Json -Depth 12 -Compress)
Write-Host "horizons: wrote $outputPath rows=$($asteroid.rows.Count)"
