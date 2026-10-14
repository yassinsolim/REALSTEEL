param(
    [long]$UniverseId = 0,
    [switch]$DryRun
)

# Creates the developer product for every Robux item in src/shared/Shop.luau and every case pack in src/shared/Cases.luau
# that has none yet (product = 0), and writes the product's ID back into the file. A product with the same name already in
# the experience is reused instead of creating a second one, so the script can be run again safely. The price is the
# item's or the pack's `robux`.
#
# The Open Cloud key needs the "developer-product" API with Read and Write for the experience (Creator Hub > Open Cloud >
# API Keys); store it with ./scripts/api-key.ps1 -Set. The universe is the one publish.ps1 remembers, or -UniverseId.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'api-key.ps1')

$root = Split-Path -Parent $PSScriptRoot
$catalog = Join-Path $root 'src/shared/Shop.luau'
$casesFile = Join-Path $root 'src/shared/Cases.luau'
$targetFile = Join-Path $env:LOCALAPPDATA 'REALSTEEL\publish-target.json'
if ($UniverseId -eq 0 -and (Test-Path $targetFile)) {
    $UniverseId = [long](Get-Content $targetFile -Raw | ConvertFrom-Json).UniverseId
}
if ($UniverseId -le 0) {
    throw 'Pass -UniverseId (or publish once with publish.ps1, which remembers it).'
}

# What is waiting for a product: each item block in Shop.Items with `product = 0` and a `robux` price, and each pack of a
# case in Cases.List with `product = 0`. A pack is named after its case ("FOUNDRY CASE", "FOUNDRY CASE x5").
$source = [System.IO.File]::ReadAllText($catalog)
$casesSource = [System.IO.File]::ReadAllText($casesFile)
$waiting = New-Object System.Collections.Generic.List[object]
$itemPattern = '(?s)\{\s*id = "(?<id>[^"]+)",\s*name = "(?<name>[^"]+)",\s*kind = "[^"]+",\s*blurb = "(?<blurb>[^"]*)",\s*product = (?<product>\d+),\s*robux = (?<robux>\d+),\s*\}'
foreach ($match in [regex]::Matches($source, $itemPattern)) {
    if ([long]$match.Groups['product'].Value -eq 0) {
        $waiting.Add([pscustomobject]@{
            File = 'shop'; Id = $match.Groups['id'].Value; Count = 0
            Name = $match.Groups['name'].Value; Description = $match.Groups['blurb'].Value
            Price = [long]$match.Groups['robux'].Value
        })
    }
}
$casePattern = '(?s)\{\s*id = "(?<id>[^"]+)",\s*name = "(?<name>[^"]+)",\s*blurb = "[^"]*",\s*coins = \d+,\s*packs = \{(?<packs>(?:\s*\{[^{}]*\},?)*)\s*\}'
$packPattern = '\{\s*product = (?<product>\d+),\s*count = (?<count>\d+),\s*robux = (?<robux>\d+),?\s*\}'
foreach ($case in [regex]::Matches($casesSource, $casePattern)) {
    $caseName = $case.Groups['name'].Value
    foreach ($pack in [regex]::Matches($case.Groups['packs'].Value, $packPattern)) {
        if ([long]$pack.Groups['product'].Value -ne 0) { continue }
        $count = [int]$pack.Groups['count'].Value
        $waiting.Add([pscustomobject]@{
            File = 'cases'; Id = $case.Groups['id'].Value; Count = $count
            Name = $(if ($count -eq 1) { $caseName } else { "$caseName x$count" })
            Description = "$(if ($count -eq 1) { "One $caseName" } else { "$count of the $caseName" }) to open in REALSTEEL. Every item and its odds are shown in the game before you buy."
            Price = [long]$pack.Groups['robux'].Value
        })
    }
}
if ($waiting.Count -eq 0) {
    Write-Output 'PASS: every Robux item and case pack has a product'
    return
}

$apiKey = Get-RobloxApiKey
Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient
$client.DefaultRequestHeaders.Add('x-api-key', $apiKey)
$base = "https://apis.roblox.com/developer-products/v2/universes/$UniverseId/developer-products"

function Read-Response($response) {
    $body = $response.Content.ReadAsStringAsync().Result
    if (-not $response.IsSuccessStatusCode) {
        $hint = if ([int]$response.StatusCode -eq 403 -or [int]$response.StatusCode -eq 401) {
            ' (does the key have the developer-product API with Read and Write for this experience?)'
        } else { '' }
        throw "Open Cloud answered $([int]$response.StatusCode)$hint`: $body"
    }
    return $body | ConvertFrom-Json
}

try {
    # The products the experience has, by name, so one made on an earlier run is reused.
    $existing = @{}
    $cursor = ''
    do {
        $url = "$base/creator?pageSize=50" + $(if ($cursor) { "&pageToken=$cursor" } else { '' })
        $page = Read-Response ($client.GetAsync($url).Result)
        $list = if ($page.PSObject.Properties.Name -contains 'developerProducts') { $page.developerProducts } else { @() }
        foreach ($product in $list) {
            $existing[$product.name] = [long]$product.productId
        }
        $cursor = if ($page.PSObject.Properties.Name -contains 'nextPageToken') { $page.nextPageToken } else { '' }
    } while ($cursor)

    foreach ($entry in $waiting) {
        $name = $entry.Name
        $price = $entry.Price
        if ($existing.ContainsKey($name)) {
            $productId = $existing[$name]
            Write-Output "$name`: reusing product $productId"
        } elseif ($DryRun) {
            Write-Output "$name`: would create a product for R$ $price"
            continue
        } else {
            $form = New-Object System.Net.Http.MultipartFormDataContent
            $form.Add((New-Object System.Net.Http.StringContent($name)), 'name')
            $form.Add((New-Object System.Net.Http.StringContent($entry.Description)), 'description')
            $form.Add((New-Object System.Net.Http.StringContent('true')), 'isForSale')
            $form.Add((New-Object System.Net.Http.StringContent([string]$price)), 'price')
            $created = Read-Response ($client.PostAsync($base, $form).Result)
            $productId = [long]$created.productId
            Write-Output "$name`: created product $productId for R$ $price"
        }
        if ($entry.File -eq 'shop') {
            $pattern = '(?s)(\{\s*id = "' + [regex]::Escape($entry.Id) + '",.*?product = )0(,)'
            $source = [regex]::Replace($source, $pattern, "`${1}$productId`${2}", 1)
        } else {
            $pattern = '(?s)(\{\s*id = "' + [regex]::Escape($entry.Id) + '",.*?packs = \{.*?\{\s*product = )0(,\s*count = ' + $entry.Count + ',)'
            $casesSource = [regex]::Replace($casesSource, $pattern, "`${1}$productId`${2}", 1)
        }
    }
}
finally {
    $client.Dispose()
}

if (-not $DryRun) {
    [System.IO.File]::WriteAllText($catalog, $source)
    [System.IO.File]::WriteAllText($casesFile, $casesSource)
    Write-Output 'PASS: products recorded; review src/shared/Shop.luau and src/shared/Cases.luau, then run ./scripts/dev.ps1 validate'
}
