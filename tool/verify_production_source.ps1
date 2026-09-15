[CmdletBinding()]
param(
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $project = Split-Path -Parent $PSScriptRoot
}
else {
    $project = [System.IO.Path]::GetFullPath($ProjectRoot)
}
if (-not (Test-Path -LiteralPath $project -PathType Container)) {
    throw "Production source root is missing: $project"
}
$project = (Get-Item -LiteralPath $project).FullName.TrimEnd('\')
$productionRoots = @(
    (Join-Path $project 'lib'),
    (Join-Path $project 'windows\runner'),
    (Join-Path $project 'packages\bdo_map_core\lib')
)
$nativeFeatureRoots = @(
    (Join-Path $project 'lib\features\gathering'),
    (Join-Path $project 'lib\features\fishing')
)
$forbiddenRelativePaths = @(
    'packages\bdo_fishing_core',
    'packages\bdo_gathering_companion',
    'windows\session_import'
)
$sourceExtensions = @('.dart', '.cc', '.cpp', '.h', '.rc', '.manifest', '.cmake', '.txt')
$rejectionPattern = '(?i)\b(TODO|FIXME|placeholder|lorem|sample|mock|fake|not[ -]implemented|coming[ -]soon)\b'
$emptyCallbackPattern = 'on[A-Za-z]+\s*:\s*\([^)]*\)\s*\{\s*\}'
$legacyVisualPattern = '(?i)(abyssal|tideglass|moonstone|astrarium)'
$embeddedWebPattern = '(?i)(webview2|webview_flutter|flutter_inappwebview|microsoft\.web\.webview2|cefsharp|embedded[ -]?chromium|browser[ -]?hosted)'
$pythonRuntimePattern = '(?i)(\bpython(?:3(?:\.\d+)*)?\b|cpython|pyinstaller|\.pyd\b|fish[_ -]?companion[_ -]?service)'
$excludedFeaturePattern = '(?i)(fishy[ _-]*stuff|garmoth|bairog|fish[_ -]?companion|bdo[_ -]?fishing[_ -]?core|bdo[_ -]?gathering[_ -]?companion)'
$personalDataFilePattern = '(?i)^(?:planner-state\.json(?:\..*)?|personal-data-(?:location(?:\.committed)?|move-journal)\.json(?:\..*)?|connection\.json(?:\..*)?|[^\\/]*(?:sessions?|journals?|loadouts?|user[ _-]?settings|app[ _-]?settings|opportunities[ _-]?settings|gathering[ _-]?state|fishing[ _-]?state|fishing[ _-]?profiles?|fishing[ _-]?setups?)[^\\/]*\.(?:json|csv|tsv|txt|ya?ml|toml|ini|config|dat|bin|db|sqlite3?)(?:-(?:wal|shm))?)$'
$sqliteFilePattern = '(?i)\.(?:db|sqlite3?)(?:-(?:wal|shm))?$'
$browserArtifactExtensions = @('.html', '.css', '.js')
$pythonArtifactExtensions = @('.py', '.pyc', '.pyo', '.pyd')

$violations = [System.Collections.Generic.List[string]]::new()
foreach ($root in @($productionRoots) + @($nativeFeatureRoots)) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        $violations.Add("$root`: required native production source directory is missing")
    }
}
foreach ($relativePath in $forbiddenRelativePaths) {
    $path = Join-Path $project $relativePath
    if (Test-Path -LiteralPath $path) {
        $violations.Add("$path`: excluded companion/runtime source tree")
    }
}

$projectPrefix = "$project\"
$projectFiles = @(Get-ChildItem -LiteralPath $project -Recurse -File | Where-Object {
    $_.FullName -notlike "$project\.git\*" -and
    $_.FullName -notlike "$project\.dart_tool\*" -and
    $_.FullName -notlike "$project\build\*" -and
    $_.FullName -notlike "$project\public-stable-candidate\*"
})
foreach ($file in $projectFiles) {
    $relative = if ($file.FullName.StartsWith(
        $projectPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        $file.FullName.Substring($projectPrefix.Length).Replace('\', '/')
    }
    else {
        $file.FullName.Replace('\', '/')
    }
    $extension = $file.Extension.ToLowerInvariant()
    if ($browserArtifactExtensions -contains $extension) {
        $violations.Add("$($file.FullName): browser-runtime artifact is forbidden")
    }
    if ($pythonArtifactExtensions -contains $extension -or
        $file.Name -match '(?i)^python(?:3(?:\d+)*)?\.(?:exe|dll)$') {
        $violations.Add("$($file.FullName): Python runtime/source artifact is forbidden")
    }
    if ($relative -match $excludedFeaturePattern) {
        $violations.Add("$($file.FullName): excluded WebView/FishyStuff/Garmoth/Bairog companion artifact")
    }
    if ($file.Name -match $personalDataFilePattern -or
        $file.Name -match $sqliteFilePattern) {
        $violations.Add("$($file.FullName): bundled personal-data artifact is forbidden")
    }
    if (($relative.StartsWith('lib/features/gathering/', [System.StringComparison]::OrdinalIgnoreCase) -or
         $relative.StartsWith('lib/features/fishing/', [System.StringComparison]::OrdinalIgnoreCase)) -and
        $extension -cne '.dart') {
        $violations.Add("$($file.FullName): native feature directories may contain Dart source only")
    }
}

foreach ($root in $productionRoots) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        continue
    }
    Get-ChildItem -LiteralPath $root -Recurse -File |
        Where-Object { $sourceExtensions -contains $_.Extension } |
        ForEach-Object {
            $matches = Select-String -LiteralPath $_.FullName -Pattern $rejectionPattern, $emptyCallbackPattern
            foreach ($match in $matches) {
                $violations.Add("$($match.Path):$($match.LineNumber): $($match.Line.Trim())")
            }

            $isMigrationFile = $_.FullName -like '*\lib\domain\migration\*'
            if (-not $isMigrationFile) {
                $legacyMatches = Select-String -LiteralPath $_.FullName -Pattern $legacyVisualPattern
                foreach ($match in $legacyMatches) {
                    $violations.Add("$($match.Path):$($match.LineNumber): excluded visual identifier outside migration")
                }
            }

            $runtimeMatches = Select-String -LiteralPath $_.FullName -Pattern $pythonRuntimePattern, $excludedFeaturePattern
            foreach ($match in $runtimeMatches) {
                $violations.Add("$($match.Path):$($match.LineNumber): excluded companion/Python runtime reference")
            }
        }
}

$assetRoot = Join-Path $project 'assets'
$legacyAsset = if (Test-Path -LiteralPath $assetRoot -PathType Container) {
    @(Get-ChildItem -LiteralPath $assetRoot -Recurse -File |
        Where-Object { $_.FullName -match $legacyVisualPattern })
}
else {
    @()
}
foreach ($file in $legacyAsset) {
    $violations.Add("$($file.FullName): excluded visual asset")
}

$dependencyFiles = @(
    (Join-Path $project 'pubspec.yaml'),
    (Join-Path $project 'pubspec.lock'),
    (Join-Path $project 'packages\bdo_map_core\pubspec.yaml')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
$embeddedWebFiles = @($dependencyFiles) + @(
    foreach ($root in $productionRoots) {
        Get-ChildItem -LiteralPath $root -Recurse -File |
            Where-Object { $sourceExtensions -contains $_.Extension }
    }
)
foreach ($file in $embeddedWebFiles) {
    $matches = Select-String -LiteralPath $file -Pattern $embeddedWebPattern, $pythonRuntimePattern, $excludedFeaturePattern
    foreach ($match in $matches) {
        $violations.Add("$($match.Path):$($match.LineNumber): embedded WebView/Python/companion dependency is forbidden")
    }
}

if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output 'Production source verification passed.'
