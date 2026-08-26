[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$recipeBookRoot = Join-Path $projectRoot 'Assets\RecipeBook'
$upstreamRoot = Join-Path $projectRoot 'Tools\PlannerCatalog\Upstream'

function ConvertTo-LowerHex {
    param([byte[]]$Bytes)

    return ([BitConverter]::ToString($Bytes) -replace '-', '').ToLowerInvariant()
}

function Get-Sha256Hex {
    param([string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ConvertTo-LowerHex -Bytes $sha.ComputeHash($stream)
    }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

$expectedHashes = [ordered]@{
    'NOTICE.txt' = '765E750B48AE8118A643907B30F685B50871BB8FE7BCBA4B41393139052E5A44'
    'ocr\icon-atlas.png' = '3B45B5BD1AE85AD1101A7A145C421A1F15991E8ABBFF65809ABF5CE69DC522BE'
    'ocr\icon-index.json' = '62FD5ECA32D4E82CDA13BB93316F8DE2DC3F0C5AF72675D7323F8A17DDC7FD17'
    'ocr\client-catalog-atlas.png' = '9CE6482D439B2522E17B3609FF0BA2FC177F3FAC158457FAA67752E054BF9E84'
    'ocr\client-catalog-index.json' = '9F362C37D9BD598BB89EDA2106B0638F01C2F7066C0DF837E2B9D164271425B3'
    'ocr\ppocrv5\en_PP-OCRv5_mobile_rec.onnx' = 'C3461ADD59BB4323ECBA96A492AB75E06DDA42467C9E3D0C18DB5D1D21924BE8'
    'recipes.json' = '07C2F076C1EC0E36CF3D67A35D9B22DC5B042A610FBBDD919561373A23BD3520'
    'manifest.json' = '1A9E6132603D148B66D9F92339780CEF444591E80C65F77747EC4B3ABE2B227E'
}

$expectedUpstreamHashes = [ordered]@{
    'recipes.json' = $expectedHashes['recipes.json']
    'manifest.json' = $expectedHashes['manifest.json']
    'ocr\icon-index.json' = $expectedHashes['ocr\icon-index.json']
    'ocr\icon-atlas.png' = $expectedHashes['ocr\icon-atlas.png']
}

$expectedEngineHashes = [ordered]@{
    'Engine\RecipeBookScreenshotService.cs' = '6A4C7A48E01DC556E0BA7296ACBB4631DA5DEEA2D809B958D196ECF498B335F8'
    'Engine\PpOcrv5QuantityRecognizer.cs' = 'B2E550755924F4349483B7F8ED5240A125734029B62BFD2008AD439E42AFD8BD'
    'Engine\RecipeBookOcrFixtureRunner.cs' = '7B631F5508EB0E6488763DA550F35E323AD8C208003533EA34506EFF93FF5B03'
}

$expectedAppMatcherHashes = [ordered]@{
    'AppMatcher\inventory-ocr-templates.json' = '91F2D1B116A165A4C24BCA8816F1846C440F7304B1520398ADC92DDAC06C6FB7'
    'AppMatcher\inventory-ocr-templates.rgb' = 'A7E19ED26C6E7B3D4FF847FE3A438CEA8C9E896C27B90BF202FDB92E8E1CC9B0'
}

foreach ($entry in $expectedHashes.GetEnumerator()) {
    $path = Join-Path $recipeBookRoot $entry.Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required sealed OCR asset is missing: $($entry.Key)"
    }
    if ((Get-Sha256Hex -Path $path) -ne $entry.Value.ToLowerInvariant()) {
        throw "Sealed OCR asset hash mismatch: $($entry.Key)"
    }
}

foreach ($entry in $expectedUpstreamHashes.GetEnumerator()) {
    $path = Join-Path $upstreamRoot $entry.Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Preserved upstream OCR asset is missing: $($entry.Key)"
    }
    if ((Get-Sha256Hex -Path $path) -ne $entry.Value.ToLowerInvariant()) {
        throw "Preserved upstream OCR asset hash mismatch: $($entry.Key)"
    }
}

foreach ($entry in $expectedEngineHashes.GetEnumerator()) {
    $path = Join-Path $projectRoot $entry.Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required native source is missing: $($entry.Key)"
    }
    if ((Get-Sha256Hex -Path $path) -ne $entry.Value.ToLowerInvariant()) {
        throw "Native OCR source differs from the approved Black Spirit Life snapshot: $($entry.Key)"
    }
}

foreach ($entry in $expectedAppMatcherHashes.GetEnumerator()) {
    $path = Join-Path $recipeBookRoot $entry.Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required app matcher cache is missing: $($entry.Key)"
    }
    if ((Get-Sha256Hex -Path $path) -ne $entry.Value.ToLowerInvariant()) {
        throw "App matcher cache differs from the generated source artwork: $($entry.Key)"
    }
}

$requiredNotices = @(
    'NOTICE.txt',
    'ocr\LICENSE-PADDLEOCR.txt',
    'ocr\MODEL-NOTICE-PPOCRV5.txt',
    'ocr\LICENSE-ONNXRUNTIME.txt',
    'ocr\THIRD-PARTY-NOTICES-ONNXRUNTIME.txt'
)
foreach ($relativePath in $requiredNotices) {
    $noticePath = Join-Path $recipeBookRoot $relativePath
    if (-not (Test-Path -LiteralPath $noticePath -PathType Leaf) -or (Get-Item -LiteralPath $noticePath).Length -le 0) {
        throw "Required OCR notice is missing or empty: $relativePath"
    }
}

if (Test-Path -LiteralPath (Join-Path $recipeBookRoot 'planner-overlay.json')) {
    throw 'The inactive planner overlay must not be present in the sealed runtime assets.'
}

$iconFiles = @(Get-ChildItem -LiteralPath (Join-Path $recipeBookRoot 'icons\items') -File)
if ($iconFiles.Count -ne 3897) {
    throw "Sealed Recipe Book icon count mismatch: expected 3897, found $($iconFiles.Count)."
}

function Assert-AtlasContract {
    param(
        [string]$RelativePath,
        [int]$ExpectedIcons,
        [int]$ExpectedMaterials,
        [int]$ExpectedNonMaterials,
        [int]$ExpectedUncertain
    )

    $index = Get-Content -LiteralPath (Join-Path $recipeBookRoot $RelativePath) -Raw | ConvertFrom-Json
    $materials = @($index.icons | Where-Object materialEligible -eq $true).Count
    $nonMaterials = @($index.icons | Where-Object materialEligible -eq $false).Count
    $uncertain = @($index.icons | Where-Object { $null -eq $_.materialEligible }).Count
    if ($index.schemaVersion -ne 2 -or $index.tileSize -ne 20 -or $index.columns -ne 64 `
        -or $index.icons.Count -ne $ExpectedIcons -or $materials -ne $ExpectedMaterials `
        -or $nonMaterials -ne $ExpectedNonMaterials -or $uncertain -ne $ExpectedUncertain) {
        throw "OCR atlas contract mismatch: $RelativePath"
    }
}

Assert-AtlasContract -RelativePath 'ocr\icon-index.json' -ExpectedIcons 3897 `
    -ExpectedMaterials 1526 -ExpectedNonMaterials 2062 -ExpectedUncertain 309
Assert-AtlasContract -RelativePath 'ocr\client-catalog-index.json' -ExpectedIcons 19418 `
    -ExpectedMaterials 1526 -ExpectedNonMaterials 17583 -ExpectedUncertain 309

$projectText = Get-Content -LiteralPath (Join-Path $projectRoot 'BlackSpiritStorageOcr.csproj') -Raw
if ($projectText -notmatch '(?s)<None Update="tests\\\*\*\\\*".*?CopyToOutputDirectory="Never".*?CopyToPublishDirectory="Never"') {
    throw 'OCR fixture files are not explicitly excluded from build and publish output.'
}

Write-Host 'Approved OCR source, frozen asset hashes, app matcher cache, atlas contracts, fixture exclusions, and notices are valid.'
