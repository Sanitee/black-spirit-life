$ErrorActionPreference = 'Stop'

$project = Split-Path -Parent $PSScriptRoot
$productionRoots = @(
    (Join-Path $project 'lib'),
    (Join-Path $project 'windows\runner'),
    (Join-Path $project 'packages\bdo_map_core\lib')
)
$sourceExtensions = @('.dart', '.cc', '.cpp', '.h', '.rc', '.manifest', '.cmake', '.txt')
$rejectionPattern = '(?i)\b(TODO|FIXME|placeholder|lorem|sample|mock|fake|not[ -]implemented|coming[ -]soon)\b'
$emptyCallbackPattern = 'on[A-Za-z]+\s*:\s*\([^)]*\)\s*\{\s*\}'
$legacyVisualPattern = '(?i)(abyssal|tideglass|moonstone|astrarium)'
$embeddedWebPattern = '(?i)(webview2|webview_flutter|flutter_inappwebview|microsoft\.web\.webview2|cefsharp|embedded[ -]?chromium|browser[ -]?hosted)'

$violations = [System.Collections.Generic.List[string]]::new()
foreach ($root in $productionRoots) {
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
        }
}

$legacyAsset = Get-ChildItem -LiteralPath (Join-Path $project 'assets') -Recurse -File |
    Where-Object { $_.FullName -match $legacyVisualPattern }
foreach ($file in $legacyAsset) {
    $violations.Add("$($file.FullName): excluded visual asset")
}

$webRemnants = Get-ChildItem -LiteralPath $project -Recurse -File |
    Where-Object {
        $_.FullName -notlike '*\.dart_tool\*' -and
        $_.FullName -notlike '*\build\*' -and
        $_.Extension -in @('.html', '.css', '.js')
    }
foreach ($file in $webRemnants) {
    $violations.Add("$($file.FullName): browser-runtime remnant")
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
    $matches = Select-String -LiteralPath $file -Pattern $embeddedWebPattern
    foreach ($match in $matches) {
        $violations.Add("$($match.Path):$($match.LineNumber): embedded web surface/dependency is forbidden")
    }
}

if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output 'Production source verification passed.'
