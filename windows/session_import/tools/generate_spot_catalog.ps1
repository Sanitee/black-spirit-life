param([string]$InputPath = (Join-Path $PSScriptRoot '..\catalog_sources\spot_catalog_input.json'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# Emits deterministic JSON to stdout. Apply the output as a reviewed file edit;
# this generator never overwrites source, assets, profiles or external data.
$inputFile = [IO.Path]::GetFullPath($InputPath)
$inputData = Get-Content -LiteralPath $inputFile -Raw | ConvertFrom-Json -AsHashtable
if ($inputData.schemaVersion -ne 1) { throw 'Unsupported spot source schema.' }
$methodMap = @{}
foreach ($method in $inputData.methods) { $methodMap[$method.id] = $method.activity }
$spots = [Collections.Generic.List[object]]::new()
foreach ($zone in $inputData.zones) {
    $spots.Add([ordered]@{
        id = 'client-zone:' + $zone.id; name = $zone.name; activity = 'grinding'
        sourceKind = 'client-zone'; sourceId = $zone.id; aliases = @(); methodIds = @()
        dropItemIds = @($zone.lootItemIds | Sort-Object -Unique)
        commonDropItemIds = @('1','28' | Where-Object { $_ -in $zone.lootItemIds })
        garmothSpotId = $null
    })
}
foreach ($spot in $inputData.companionSpots) {
    $activities = @($spot.methodIds | ForEach-Object {
        if (-not $methodMap.ContainsKey($_)) { throw 'Unknown companion method.' }
        if ($methodMap[$_] -eq 'sniper') { 'hunting' } else { $methodMap[$_] }
    } | Sort-Object -Unique)
    if ($activities.Count -ne 1) { throw 'A companion spot needs one explicit protocol activity.' }
    $commonIds = @($inputData.commonLoot | Where-Object {
        $sharedMethods = @($_.methodIds | Where-Object { $_ -in $spot.methodIds })
        $sharedMethods.Count -gt 0 -and $spot.id -notin $_.excludedSpotIds
    } | ForEach-Object { $_.itemId })
    $directIds = @($spot.materials | Where-Object {
        @($_.methodIds | Where-Object { $_ -in $spot.methodIds }).Count -gt 0 -and
            $spot.id -notin $_.excludedSpotIds
    } | ForEach-Object { $_.itemId })
    $spots.Add([ordered]@{
        id = 'companion:' + $spot.id; name = $spot.name; activity = $activities[0]
        sourceKind = 'companion-spot'; sourceId = $spot.id
        aliases = @($spot.displayName | Where-Object { $_ -and $_ -ne $spot.name })
        methodIds = @($spot.methodIds); dropItemIds = @(@($directIds) + @($commonIds) | Sort-Object -Unique)
        commonDropItemIds = @($commonIds | Sort-Object -Unique); garmothSpotId = $null
    })
}
$knownIds = @{}; foreach ($item in $inputData.items) { $knownIds[$item.id] = $true }
foreach ($spot in $spots) {
    foreach ($id in $spot.dropItemIds) {
        if (-not $knownIds.ContainsKey($id)) { throw "Missing item identity $id in $($spot.id)." }
    }
}
$outputData = [ordered]@{
    schemaVersion = 1; datasetVersion = 'client-2026-09-10-companion-2026-09-14-v1'
    coverage = [ordered]@{
        clientGrindingZones = $inputData.zones.Count; companionSpots = $inputData.companionSpots.Count
        completeGameOrGarmothCatalog = $false
        description = 'All 112 records from the preserved client zone snapshot and all 37 curated companion spots. Not an exhaustive game/Garmoth catalog; drop lists are positive evidence, not guaranteed or complete outcomes.'
    }
    provenance = [ordered]@{
        input = 'catalog_sources/spot_catalog_input.json'
        inputSha256 = (Get-FileHash -LiteralPath $inputFile -Algorithm SHA256).Hash
        sources = $inputData.sources
        aliases = 'Exact source display names and item names only; no inferred Garmoth aliases, IDs, account routes or slugs.'
    }
    items = @($inputData.items); spots = @($spots)
}
$outputData | ConvertTo-Json -Depth 12
