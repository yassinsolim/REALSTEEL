param(
    [long]$UniverseId = 0,
    [long]$PlaceId = 0,
    [switch]$SkipValidate,
    [switch]$DryRun
)

# Publishes build/REALSTEEL.rbxlx to a private test experience through Open Cloud. The IDs are remembered for the
# current Windows user after the first run, so later runs need no arguments. The full validation gate runs first, so
# only a formatted, linted, type-checked, freshly built place ships. The checks place is never published.
#
# One-time setup:
#   1. Creator Hub > Create experience (it stays private until you change it). Note its Universe ID and Place ID.
#   2. Creator Hub > Open Cloud > API Keys: add the "universe-places" API with Write access for that experience.
#   3. ./scripts/api-key.ps1 -Set          (paste the key at the hidden prompt; it never touches the repository)
#   4. ./scripts/publish.ps1 -UniverseId <id> -PlaceId <id>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'api-key.ps1')

$targetFile = Join-Path $env:LOCALAPPDATA 'REALSTEEL\publish-target.json'
if ($UniverseId -eq 0 -and $PlaceId -eq 0 -and (Test-Path $targetFile)) {
    $saved = Get-Content $targetFile -Raw | ConvertFrom-Json
    $UniverseId = [long]$saved.UniverseId
    $PlaceId = [long]$saved.PlaceId
}
if ($UniverseId -le 0 -or $PlaceId -le 0) {
    throw 'Pass -UniverseId and -PlaceId of your test experience (see the setup notes at the top of this script).'
}

if (-not $SkipValidate) {
    & (Join-Path $PSScriptRoot 'dev.ps1') validate
}
$placeFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'build/REALSTEEL.rbxlx'
if (-not (Test-Path $placeFile)) {
    throw "$placeFile is missing; run ./scripts/dev.ps1 validate first."
}
$sizeKb = [math]::Round((Get-Item $placeFile).Length / 1KB)
$url = "https://apis.roblox.com/universes/v1/$UniverseId/places/$PlaceId/versions?versionType=Published"

if ($DryRun) {
    Write-Output "DRY RUN: would publish $placeFile ($sizeKb KB) to universe $UniverseId, place $PlaceId"
    Write-Output "         POST $url"
    return
}

Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(300)
$client.DefaultRequestHeaders.Add('x-api-key', (Get-RobloxApiKey))
$content = New-Object System.Net.Http.ByteArrayContent(, [System.IO.File]::ReadAllBytes($placeFile))
$content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/xml')
$response = $client.PostAsync($url, $content).Result
$body = $response.Content.ReadAsStringAsync().Result
if (-not $response.IsSuccessStatusCode) {
    throw "Publish failed: HTTP $([int]$response.StatusCode) $body"
}

New-Item -ItemType Directory -Force -Path (Split-Path $targetFile) | Out-Null
@{ UniverseId = $UniverseId; PlaceId = $PlaceId } | ConvertTo-Json | Set-Content -Path $targetFile
$version = ($body | ConvertFrom-Json).versionNumber
Write-Output "PASS: published REALSTEEL version $version (universe $UniverseId, place $PlaceId)"
