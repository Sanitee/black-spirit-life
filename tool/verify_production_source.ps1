[CmdletBinding()]
param(
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release\source_inventory.ps1')

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
$projectPrefix = "$project\"

$requiredPaths = @(
    'assets\opportunities\icon-provenance.json',
    'lib',
    'lib\features\gathering',
    'lib\features\fishing',
    'windows\runner',
    'packages\bdo_map_core\lib',
    'packages\bdo_fishing_core\lib',
    'packages\bdo_fishing_core\assets\fish_companion\backend',
    'packages\bdo_fishing_core\assets\fish_companion\data\cache',
    'packages\bdo_fishing_core\assets\fish_companion\recognizer\reference-icons',
    'packages\bdo_fishing_core\assets\fish_companion\runtime',
    'packages\bdo_fishing_core\assets\fish_companion\static',
    'packages\bdo_gathering_companion\lib',
    'packages\bdo_gathering_companion\assets',
    'packages\webview_flutter_windows\lib',
    'packages\webview_flutter_windows\windows',
    'packages\webview_flutter_windows\LICENSE',
    'windows\session_import\src',
    'windows\session_import\browser_extension',
    'windows\session_import\SOURCE-NOTICE.txt'
)

$excludedRelativePaths = @(
    'packages/bdo_map_core/tool/seeds/bdocodex_worldmap_2026_07_29_private_seed.json',
    'packages/bdo_map_core/tool/seeds/bdocodex_worldmap_2026_08_15_private_seed.json',
    'packages/bdo_map_core/tool/seeds/rusalka_coral_bdocodex_2026_07_28_private_seed.json',
    'packages/bdo_map_core/tool/seeds/stillcoral_coastal_gathering_bdocodex_2026_08_01_private_seed.json',
    'packages/bdo_map_core/tool/seeds/vendor_npcs_bdocodex_2026_08_15_private_seed.json',
    'packages/bdo_map_core/tool/seeds/vendor_npc_portraits_2026_08_16_private_manifest.json',
    'packages/bdo_fishing_core/assets/fish_companion/data/fish-journal.sqlite3',
    'packages/bdo_fishing_core/assets/fish_companion/data/fish-journal.sqlite3-wal',
    'packages/bdo_fishing_core/assets/fish_companion/data/fish-journal.sqlite3-shm',
    'packages/bdo_fishing_core/assets/fish_companion/data/fish-journal.before-sale-redesign.sqlite3',
    'packages/bdo_fishing_core/assets/fish_companion/data/fish-journal.before-sale-redesign.sqlite3-wal',
    'packages/bdo_fishing_core/assets/fish_companion/data/fish-journal.before-sale-redesign.sqlite3-shm',
    'packages/bdo_gathering_companion/assets/rotations/luneye_matchlock_buffs_1424.png',
    'packages/bdo_gathering_companion/assets/rotations/luneye_matchlock_crystals_1321.png',
    'packages/bdo_gathering_companion/assets/rotations/luneye_sniper_buffs_1505.png',
    'packages/bdo_gathering_companion/assets/rotations/tshira_evil_2024_rotation.jpg'
)

$generatedPathPattern =
    '(?i)(?:^|/)(?:\.git|\.dart_tool|\.flutter-plugins-dependencies|build|public-stable-candidate|bin|obj|\.pytest_cache|test/failures|test/features/opportunities/failures|windows/flutter/ephemeral|doc/api)(?:/|$)'
$browserStatePathPattern =
    '(?i)(?:^|/)(?:webview2|video[ _-]*webview|webview[ _-]*profile|browser[ _-]*profile|user[ _-]*data|cookies?|local[ _-]*storage)(?:/|$)'
$sessionImportReceiptPathPattern =
    '(?i)(?:^|/)(?:session-import-inbox|BlackSpiritLife\.App\.Removal)(?:/|$)'
$customIconPathPattern = '(?i)(?:^|/)icons/[0-9a-f]{64}\.png$'
$personalDataFilePattern =
    '(?i)^(?:planner-state\.json(?:[.-][^/]*)?|bdo-craft-planner-backup\.json(?:[.-][^/]*)?|sessions\.json(?:[.-][^/]*)?|personal-data-(?:location(?:\.committed)?|move-journal)\.json(?:[.-][^/]*)?|connection\.json(?:[.-][^/]*)?|\.black-spirit-life-(?:profile|intentional-reset|move-(?:manifest|source|stage))\.json(?:[.-][^/]*)?|pending-personal-data-removal(?:\.committed)?\.journal(?:[.-][^/]*)?|(?:map-candidate-native|avalonia-v1)-[0-9a-f]{64}\.json(?:[.-][^/]*)?|(?:opportunity-market-(?:cache|observations)|market-request-(?:pauses|window))\.json(?:[.-][^/]*)?|fish-journal(?:\.before-sale-redesign)?\.sqlite3(?:(?:-(?:wal|shm|journal))|\.(?:bak|backup)(?:-[^/]*)?)?|[^/]*(?:saved[ _-]*sessions?|journals?|loadouts?|saved[ _-]*imports?|receipts?|drafts?|user[ _-]*settings|app[ _-]*settings|opportunities[ _-]*settings|gathering[ _-]*state|fishing[ _-]*state|fishing[ _-]*profiles?|fishing[ _-]*setups?)[^/]*\.(?:json|csv|tsv|txt|ya?ml|toml|ini|config|dat|bin|db|sqlite3?)(?:(?:-(?:wal|shm|journal))|[.-][^/]*)?)$'
$databaseOrSidecarPattern =
    '(?i)(?:\.(?:db|sqlite3?)(?:(?:-(?:wal|shm|journal))|\.(?:bak|backup)(?:-[^/]*)?)?|-(?:wal|shm|journal))$'
$temporaryArtifactPattern =
    '(?i)(?:\.(?:pyc|pyo|dmp|log|tmp|bak)$|\.pdb(?:[.-][^/]*)?$)'
$secretPattern =
    '(?<![A-Za-z0-9_])(?-i:github_pat_[A-Za-z0-9_]{20,}|gh[oprsu]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})(?![A-Za-z0-9_])'
$machinePathPattern =
    ('(?i)[A-Z]:(?:\\{1,2}|/)(?:' +
        'Users(?:\\{1,2}|/)|' +
        'Codex(?:\\{1,2}|/))')
$privateMachineMarkers = @(
    $env:USERPROFILE
)
$machinePathFixtureAllowlist = @(
    # This integration test uses a fixed, non-personal Windows path while
    # verifying that map navigation does not depend on a machine-specific root.
    'test/app/workspace/resource_map_tab_integration_test.dart',
    # This upstream conversion test intentionally contains a non-personal,
    # escaped Windows path to exercise Unicode string conversion.
    'packages/webview_flutter_windows/windows/test/string_converter_test.cc'
)
$textExtensions = @(
    '.dart', '.yaml', '.yml', '.json', '.md', '.txt', '.ps1', '.cmake',
    '.cpp', '.cc', '.c', '.h', '.hpp', '.rc', '.manifest', '.cs', '.csproj',
    '.xaml', '.py', '.html', '.css', '.js', '.mjs', '.toml', '.ini', '.config'
)
$violations = [System.Collections.Generic.List[string]]::new()

foreach ($relativePath in $requiredPaths) {
    if (-not (Test-Path -LiteralPath (Join-Path $project $relativePath))) {
        $violations.Add("$relativePath`: required exact-Beta production path is missing")
    }
}
foreach ($relativePath in $excludedRelativePaths) {
    if (Test-Path -LiteralPath (Join-Path $project $relativePath)) {
        $violations.Add("$relativePath`: excluded personal, private-research, or machine-specific path")
    }
}
$trackedGeneratedOutputs = @(& git -C $project ls-files -- 2>$null |
    Where-Object {
        $_ -match '(?i)(?:^|/)(?:\.dart_tool|build|bin|obj)(?:/|$)' -or
        $_ -match '(?i)^windows/flutter/ephemeral(?:/|$)'
    })
if ($LASTEXITCODE -ne 0) {
    $violations.Add('Git failed while checking for tracked generated output')
}
else {
    foreach ($relativePath in $trackedGeneratedOutputs) {
        $violations.Add("$relativePath`: tracked generated output is forbidden")
    }
}

function Get-RelativeProductionPath {
    param([Parameter(Mandatory = $true)][string]$FullName)
    if ($FullName.StartsWith(
        $projectPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        return $FullName.Substring($projectPrefix.Length).Replace('\', '/')
    }
    return $FullName.Replace('\', '/')
}

function Test-SqliteFileHeader {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        if ($stream.Length -lt 16) {
            return $false
        }
        $header = [byte[]]::new(16)
        if ($stream.Read($header, 0, $header.Length) -ne $header.Length) {
            return $false
        }
        return [System.Text.Encoding]::ASCII.GetString($header) -ceq
            "SQLite format 3`0"
    }
    finally {
        $stream.Dispose()
    }
}

$sourceInventory = Get-ReleaseSourceInventory -RootPath $project `
    -ExcludedPathPattern $generatedPathPattern
$projectFiles = $sourceInventory.Files

foreach ($file in $projectFiles) {
    $relative = Get-RelativeProductionPath -FullName $file.FullName
    $name = $file.Name
    $extension = $file.Extension.ToLowerInvariant()

    if ($relative -match $browserStatePathPattern) {
        $violations.Add("$relative`: generated browser-profile state is forbidden")
    }
    if ($relative -match $sessionImportReceiptPathPattern) {
        $violations.Add("$relative`: generated Session Import receipt is forbidden")
    }
    if ($relative -match $customIconPathPattern) {
        $violations.Add("$relative`: generated personal custom icon is forbidden")
    }
    if ($name -match $personalDataFilePattern -or
        $name -match $databaseOrSidecarPattern) {
        $violations.Add("$relative`: bundled personal-data database or record is forbidden")
    }
    elseif (Test-SqliteFileHeader -Path $file.FullName) {
        $violations.Add("$relative`: SQLite content is forbidden regardless of file name")
    }
    if ($name -match $temporaryArtifactPattern) {
        $violations.Add("$relative`: generated, diagnostic, temporary, backup, or debug artifact")
    }

    if ($textExtensions -contains $extension -and $file.Length -le 128MB) {
        foreach ($marker in $privateMachineMarkers) {
            if ([string]::IsNullOrWhiteSpace($marker)) {
                continue
            }
            $markerMatches = Select-String -LiteralPath $file.FullName -SimpleMatch $marker
            foreach ($match in $markerMatches) {
                $violations.Add("$relative`:$($match.LineNumber): private machine path")
            }
        }
        $secretMatches = Select-String -LiteralPath $file.FullName -Pattern $secretPattern
        foreach ($match in $secretMatches) {
            $violations.Add("$relative`:$($match.LineNumber): credential-like secret marker")
        }
        if ($machinePathFixtureAllowlist -cnotcontains $relative) {
            $pathMatches = Select-String -LiteralPath $file.FullName -Pattern $machinePathPattern
            foreach ($match in $pathMatches) {
                $violations.Add("$relative`:$($match.LineNumber): absolute user/private workspace path")
            }
        }
    }
}

if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Output 'Production source verification passed for exact-Beta Stable 0.1.12.'
