[CmdletBinding()]
param(
    [string]$FlutterPath,
    [string]$CMakePath,
    [string]$ReleaseInputCacheRoot,
    [string]$PreviousFeedPath,
    [string]$PreviousPackagePath,
    [Parameter(Mandatory = $true)][string]$DependencyReceiptPath,
    [Parameter(Mandatory = $true)][string]$ApprovedDependencyReceiptSha256,
    [string]$BuildRetryProfilePath,
    [string]$ApprovedBuildRetryProfileSha256,
    [string]$ResumeBundleReceiptPath,
    [string]$ApprovedResumeBundleReceiptSha256,
    [string]$WorkflowReportPath,
    [switch]$OfflinePinnedInputs,
    [ValidateRange(0, [long]::MaxValue)][long]$MinimumFreeBytes = 0,

    [Parameter(Mandatory = $true)]
    [string]$ReleasePlanPath,

    [Parameter(Mandatory = $true)]
    [string]$ApprovedReleasePlanSha256,

    [Parameter(Mandatory = $true)]
    [switch]$ConfirmPublicCandidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release\verified_input_cache.ps1')
. (Join-Path $PSScriptRoot 'release\source_inventory.ps1')
. (Join-Path $PSScriptRoot 'release\preflight.ps1')
. (Join-Path $PSScriptRoot 'release\stage_metrics.ps1')
. (Join-Path $PSScriptRoot 'release\release_plan.ps1')
. (Join-Path $PSScriptRoot 'release\build_checkpoint.ps1')
. (Join-Path $PSScriptRoot 'release\native_prerequisites.ps1')
. (Join-Path $PSScriptRoot 'release\streaming_marker_scan.ps1')

if (-not $ConfirmPublicCandidateOnly.IsPresent) {
    throw 'Supply -ConfirmPublicCandidateOnly. This script prepares artifacts but never publishes them.'
}
$ReleasePlan = Read-ReleasePlan `
    -Path $ReleasePlanPath `
    -ExpectedSha256 $ApprovedReleasePlanSha256
$Version = $ReleasePlan.Version
$BuildNumber = [string]$ReleasePlan.BuildNumber
$PreviousStableVersion = $ReleasePlan.PreviousVersion
$PreviousStableCommit = $ReleasePlan.PreviousCommit
$ReviewedReleaseParentCommit = $ReleasePlan.ReviewedParentCommit
$UpdateSource = $ReleasePlan.Repository
$ReleaseNotesRelativePath = $ReleasePlan.ReleaseNotesRelativePath
$OutputDirectoryName = $ReleasePlan.OutputDirectoryName
$ManifestName = $ReleasePlan.ManifestName
$RemainingBlockers = @($ReleasePlan.RemainingBlockers)

$PackageId = $ReleasePlan.PackageId
$UpdateChannel = $ReleasePlan.Channel
$DisplayName = 'Black Spirit Life'
$InstallerProductName = 'Black Spirit Life Installer'
$ExecutableName = 'BlackSpiritLife.exe'
$UpdaterHelperName = 'BlackSpiritLifeUpdater.exe'
$FishHostHelperName = 'BlackSpiritLifeFishHost.exe'
$BuiltInstallerName = 'BlackSpiritLifeInstaller.exe'
$InstallerName = 'BlackSpiritLifeInstaller.exe'
$UpdateSourceEnvironmentKey = 'BLACK_SPIRIT_LIFE_UPDATE_SOURCE'
$VelopackVersion = '1.2.0'
$VelopackPackageSha256 =
    '3E458A676BE46D1122E522312DB18411F36EA8C70E586F81A676695D43F89DBC'
$VelopackRuntimeSha256 =
    'C36D8B984639A8AF9D3397088D3FFB8213FE1BD0917F555CF0C6E33F014403EC'
$VelopackPackageUrl =
    'https://github.com/velopack/velopack/releases/download/1.2.0/vpk.1.2.0.nupkg'
$PreviousFeedBytes = $ReleasePlan.PreviousFeedBytes
$PreviousFeedSha256 = $ReleasePlan.PreviousFeedSha256
$PreviousFullPackageBytes = $ReleasePlan.PreviousFullPackageBytes
$PreviousFullPackageSha256 = $ReleasePlan.PreviousFullPackageSha256
$PrivateMachinePathPattern =
    '(?i)[A-Z]:(?:\\{1,2}|/)(?:Users|Codex)(?:\\{1,2}|/)'
$ForbiddenPackagedArtifactPattern = @(
    '(?i)(?:^|[\\/])(?:webview2|video[ _-]*webview|webview[ _-]*profile|browser[ _-]*profile|user[ _-]*data|cookies?|local[ _-]*storage)(?:[\\/]|$)',
    '(?i)(?:^|[\\/])(?:session-import-inbox|BlackSpiritLife\.App\.Removal)(?:[\\/]|$)',
    '(?i)(?:^|[\\/])(?:planner-state\.json(?:[.-][^\\/]*)?|bdo-craft-planner-backup\.json(?:[.-][^\\/]*)?|sessions\.json(?:[.-][^\\/]*)?|personal-data-(?:location(?:\.committed)?|move-journal)\.json(?:[.-][^\\/]*)?|connection\.json(?:[.-][^\\/]*)?|\.black-spirit-life-(?:profile|intentional-reset|move-(?:manifest|source|stage))\.json(?:[.-][^\\/]*)?|pending-personal-data-removal(?:\.committed)?\.journal(?:[.-][^\\/]*)?|(?:map-candidate-native|avalonia-v1)-[0-9a-f]{64}\.json(?:[.-][^\\/]*)?|(?:opportunity-market-(?:cache|observations)|market-request-(?:pauses|window))\.json(?:[.-][^\\/]*)?)$',
    '(?i)(?:^|[\\/])icons[\\/][0-9a-f]{64}\.png$',
    '(?i)(?:^|[\\/])[^\\/]*(?:saved[ _-]*sessions?|journals?|loadouts?|saved[ _-]*imports?|receipts?|drafts?|user[ _-]*settings|app[ _-]*settings|opportunities[ _-]*settings|gathering[ _-]*state|fishing[ _-]*state|fishing[ _-]*profiles?|fishing[ _-]*setups?)[^\\/]*\.(?:json|csv|tsv|txt|ya?ml|toml|ini|config|dat|bin|db|sqlite3?)(?:(?:-(?:wal|shm|journal))|[.-][^\\/]*)?$',
    '(?i)(?:^|[\\/])fish-journal(?:\.before-sale-redesign)?\.sqlite3(?:(?:-(?:wal|shm|journal))|\.(?:bak|backup)(?:-[^\\/]*)?)?$',
    '(?i)\.(?:db|sqlite3?)(?:(?:-(?:wal|shm|journal))|\.(?:bak|backup)(?:-[^\\/]*)?)?$',
    '(?i)(?:^|[\\/])__pycache__(?:[\\/]|$)|\.(?:pyc|pyo|dmp|log|tmp|bak)$|\.pdb(?:[.-][^\\/]*)?$',
    '(?i)(?:^|[\\/])(?:luneye_(?:matchlock_buffs_1424|matchlock_crystals_1321|sniper_buffs_1505)\.png|tshira_evil_2024_rotation\.jpg)$'
) -join '|'

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Operation)
    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed with exit code $LASTEXITCODE."
    }
}

function Assert-OrdinaryFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file is missing: $Path"
    }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $item.Length -le 0) {
        throw "Required file is not an ordinary non-empty file: $Path"
    }
    return $item
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

function Get-ArtifactRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RelativeTo
    )
    $item = Assert-OrdinaryFile -Path $Path
    $relativeRoot = [System.IO.Path]::GetFullPath($RelativeTo).TrimEnd('\') + '\'
    if (-not $item.FullName.StartsWith(
        $relativeRoot,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Artifact escaped the release-candidate run directory: $($item.FullName)"
    }
    return [ordered]@{
        role = $Role
        path = $item.FullName.Substring($relativeRoot.Length)
        bytes = $item.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $item.FullName).Hash
    }
}

function Assert-CleanSource {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedCommit
    )
    $commit = (& git -C $ProjectRoot rev-parse HEAD).Trim()
    Assert-LastExitCode -Operation 'Git source identity check'
    if ($commit -cne $ExpectedCommit) {
        throw 'The source commit changed during release-candidate packaging.'
    }
    $changes = @(& git -C $ProjectRoot status --porcelain --untracked-files=all)
    Assert-LastExitCode -Operation 'Git worktree check'
    if ($changes.Count -ne 0) {
        throw 'The installer must be built from a clean, committed checkpoint.'
    }
}

function Reset-VerifiedWindowsBuildTree {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$BundleDirectory
    )
    $resolvedBuildRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $ProjectRoot 'build')
    )
    $resolvedWindowsBuildRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $resolvedBuildRoot 'windows\x64')
    )
    $resolvedRunnerRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $resolvedWindowsBuildRoot 'runner')
    )
    $expectedBundle = [System.IO.Path]::GetFullPath(
        (Join-Path $resolvedRunnerRoot 'Release')
    )
    $resolvedBundle = [System.IO.Path]::GetFullPath($BundleDirectory)
    $buildPrefix = $resolvedBuildRoot.TrimEnd('\') + '\'
    $runnerPrefix = $resolvedRunnerRoot.TrimEnd('\') + '\'
    if ($resolvedBundle -cne $expectedBundle -or
        -not $resolvedWindowsBuildRoot.StartsWith(
            $buildPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or
        -not $resolvedBundle.StartsWith(
            $runnerPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw 'Refusing to clean an unexpected Flutter Windows build directory.'
    }
    $pathToInspect = $resolvedBuildRoot
    foreach ($segment in @('windows', 'x64')) {
        if (Test-Path -LiteralPath $pathToInspect) {
            $pathItem = Get-Item -LiteralPath $pathToInspect -Force
            if (($pathItem.Attributes -band
                [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Refusing to clean through a reparse-point Flutter build directory.'
            }
        }
        $pathToInspect = Join-Path $pathToInspect $segment
    }
    if (Test-Path -LiteralPath $resolvedWindowsBuildRoot) {
        $buildItem = Get-Item -LiteralPath $resolvedWindowsBuildRoot -Force
        if (($buildItem.Attributes -band
            [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Refusing to clean a reparse-point Flutter Windows build directory.'
        }
        Remove-Item -LiteralPath $resolvedWindowsBuildRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $resolvedWindowsBuildRoot) {
        throw 'The previous Flutter Windows build tree could not be removed.'
    }
}

function Assert-PublicSourceBoundary {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $trackedGeneratedOutputs = @(& git -C $ProjectRoot ls-files -- 2>$null |
        Where-Object {
            $_ -match '(?i)(?:^|/)(?:\.dart_tool|build|bin|obj)(?:/|$)' -or
            $_ -match '(?i)^windows/flutter/ephemeral(?:/|$)'
        })
    Assert-LastExitCode -Operation 'Tracked generated-output boundary check'
    if ($trackedGeneratedOutputs.Count -ne 0) {
        throw "The public source tracks generated output that source scanning would exclude: $($trackedGeneratedOutputs[0])"
    }

    $forbiddenRelativePaths = @(
        'packages\bdo_map_core\tool\seeds\bdocodex_worldmap_2026_07_29_private_seed.json',
        'packages\bdo_map_core\tool\seeds\bdocodex_worldmap_2026_08_15_private_seed.json',
        'packages\bdo_map_core\tool\seeds\rusalka_coral_bdocodex_2026_07_28_private_seed.json',
        'packages\bdo_map_core\tool\seeds\stillcoral_coastal_gathering_bdocodex_2026_08_01_private_seed.json',
        'packages\bdo_map_core\tool\seeds\vendor_npcs_bdocodex_2026_08_15_private_seed.json',
        'packages\bdo_map_core\tool\seeds\vendor_npc_portraits_2026_08_16_private_manifest.json',
        'packages\bdo_fishing_core\assets\fish_companion\data\fish-journal.sqlite3',
        'packages\bdo_fishing_core\assets\fish_companion\data\fish-journal.sqlite3-wal',
        'packages\bdo_fishing_core\assets\fish_companion\data\fish-journal.sqlite3-shm',
        'packages\bdo_fishing_core\assets\fish_companion\data\fish-journal.before-sale-redesign.sqlite3',
        'packages\bdo_fishing_core\assets\fish_companion\data\fish-journal.before-sale-redesign.sqlite3-wal',
        'packages\bdo_fishing_core\assets\fish_companion\data\fish-journal.before-sale-redesign.sqlite3-shm',
        'packages\bdo_gathering_companion\assets\rotations\luneye_matchlock_buffs_1424.png',
        'packages\bdo_gathering_companion\assets\rotations\luneye_matchlock_crystals_1321.png',
        'packages\bdo_gathering_companion\assets\rotations\luneye_sniper_buffs_1505.png',
        'packages\bdo_gathering_companion\assets\rotations\tshira_evil_2024_rotation.jpg'
    )
    foreach ($relativePath in $forbiddenRelativePaths) {
        if (Test-Path -LiteralPath (Join-Path $ProjectRoot $relativePath)) {
            throw "The public source contains an excluded private path: $relativePath"
        }
    }

    $requiredProductionPaths = @(
        'assets\opportunities\icon-provenance.json',
        'lib\features\gathering',
        'lib\features\fishing',
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
    foreach ($relativePath in $requiredProductionPaths) {
        if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $relativePath))) {
            throw "The public source is missing a required exact-Beta production path: $relativePath"
        }
    }

    # Enumerate once, pruning generated directories before descent. Preserve
    # this gate's narrower exclusions; the independent verifier has its own.
    $inventory = Get-ReleaseSourceInventory -RootPath $ProjectRoot `
        -ExcludedPathPattern '(?i)(?:^|/)(?:\.git|\.dart_tool|build|bin|obj)/|(?:^|/)windows/flutter/ephemeral/'
    $forbiddenPersonalFiles = @($inventory.Files |
        Where-Object {
            ($_.FullName -match $ForbiddenPackagedArtifactPattern -or
             (Test-SqliteFileHeader -Path $_.FullName))
        })
    if ($forbiddenPersonalFiles.Count -ne 0) {
        throw "The public source contains personal state, a database, or a debug symbol: $($forbiddenPersonalFiles[0].FullName)"
    }

    $generatedBrowserState = @($inventory.Directories |
        Where-Object {
            $_.Name -match '(?i)^(?:webview2|video[ _-]*webview|webview[ _-]*profile|browser[ _-]*profile|user[ _-]*data|cookies?|local[ _-]*storage|BlackSpiritLife\.App\.Removal)$'
        })
    if ($generatedBrowserState.Count -ne 0) {
        throw "The public source contains generated browser-profile state: $($generatedBrowserState[0].FullName)"
    }
    $sessionImportInboxes = @($inventory.Directories |
        Where-Object {
            $_.Name -ieq 'session-import-inbox'
        })
    if ($sessionImportInboxes.Count -ne 0) {
        throw "The public source contains generated Session Import receipts: $($sessionImportInboxes[0].FullName)"
    }
    $customIcons = @($inventory.Files |
        Where-Object {
            $_.FullName -match '(?i)[\\/]icons[\\/][0-9a-f]{64}\.png$'
        })
    if ($customIcons.Count -ne 0) {
        throw "The public source contains a generated personal custom icon: $($customIcons[0].FullName)"
    }
}

function Get-SourceInventoryFingerprint {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo[]]$Files,
        [Parameter(Mandatory = $true)][string]$RootPath
    )

    $root = [System.IO.Path]::GetFullPath($RootPath).TrimEnd([char[]]@('\', '/'))
    $records = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $Files) {
        $relativePath = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
        $fileHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
        $records.Add("$relativePath`t$($file.Length)`t$fileHash`n")
    }
    $records.Sort([System.StringComparer]::Ordinal)

    $builder = [System.Text.StringBuilder]::new()
    foreach ($record in $records) {
        [void]$builder.Append($record)
    }

    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
        return ([System.BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }
}

function Assert-SessionImportPayload {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$SourceDirectory
    )

    $requiredFiles = @(
        # The WPF app is deliberately published as one framework-dependent
        # executable; its managed assemblies and runtime metadata are bundled.
        'Session Import.exe',
        'SummaryOcrNative.exe',
        'WebView2Loader.dll',
        'browser_helper\BlackSpiritSessionImportHost.exe',
        'browser_extension\tracker_helper\manifest.json',
        'Assets\loot_catalog.json',
        'Assets\spot_catalog.json',
        'Assets\garmoth_spot_catalog.json'
    )
    foreach ($relativePath in $requiredFiles) {
        $null = Assert-OrdinaryFile -Path (Join-Path $Directory $relativePath)
    }

    $manifestPath = Join-Path $Directory 'payload-manifest.json'
    $null = Assert-OrdinaryFile -Path $manifestPath
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or
        $manifest.source.path -cne 'windows/session_import' -or
        $manifest.build.configuration -cne 'Release' -or
        $manifest.build.runtimeIdentifier -cne 'win-x64' -or
        $manifest.build.frameworkDependent -ne $true) {
        throw 'The Session Import payload manifest has the wrong production identity.'
    }

    $sourceFiles = @(Get-ChildItem -LiteralPath $SourceDirectory -Recurse -File |
        Where-Object { $_.FullName -notmatch '\\(bin|obj|build|artifacts|tests)\\' })
    $sourceFingerprint = Get-SourceInventoryFingerprint `
        -Files $sourceFiles `
        -RootPath $SourceDirectory
    if ([int]$manifest.source.fileCount -ne $sourceFiles.Count -or
        -not ([string]$manifest.source.fingerprintSha256).Equals(
            $sourceFingerprint,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw 'The Session Import payload was not built from the current tagged source.'
    }

    $records = @($manifest.payload.files)
    $actualPayloadFiles = @(Get-ChildItem -LiteralPath $Directory -Recurse -File |
        Where-Object { $_.FullName -cne $manifestPath })
    if ([int]$manifest.payload.fileCount -ne $records.Count -or
        $records.Count -ne $actualPayloadFiles.Count) {
        throw 'The Session Import payload manifest has an unexpected file set.'
    }
    foreach ($file in $actualPayloadFiles) {
        if ($file.Name -match '(?i)\.pdb(?:$|[.-])') {
            throw "The Session Import payload contains a debug symbol: $($file.FullName)"
        }
        $relativePath = $file.FullName.Substring($Directory.Length + 1).Replace('\', '/')
        $matches = @($records | Where-Object { $_.path -ceq $relativePath })
        if ($matches.Count -ne 1 -or
            [long]$matches[0].bytes -ne $file.Length -or
            -not $matches[0].sha256.Equals(
                (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            throw "The Session Import payload manifest does not match $relativePath."
        }
    }
}

function Test-UnreviewedAbsolutePath {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [switch]$AllowReviewedVelopackBuildPaths
    )

    foreach ($match in [regex]::Matches($Text, $PrivateMachinePathPattern)) {
        if ($AllowReviewedVelopackBuildPaths.IsPresent) {
            $tailLength = [Math]::Min(128, $Text.Length - $match.Index)
            $pathTail = $Text.Substring($match.Index, $tailLength)
            $reviewedVelopackBuildRootPattern =
                '(?i)^C:' +
                '\\Users\\runneradmin\\(?:\.cargo|\.rustup)\\'
            if ([regex]::IsMatch(
                $pathTail,
                $reviewedVelopackBuildRootPattern
            )) {
                continue
            }
        }
        return $true
    }
    return $false
}

function Assert-NoTextMarker {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Markers,
        [switch]$AllowReviewedVelopackBuildPaths
    )
    $result = Assert-NoStreamingTextMarker -Path $Path -Markers $Markers `
        -PrivateMachinePathPattern $PrivateMachinePathPattern -VelopackRuntimeSha256 $VelopackRuntimeSha256 `
        -AllowReviewedVelopackBuildPaths:$AllowReviewedVelopackBuildPaths -PassThru
    $measurementList = Get-Variable -Name ReleaseMarkerScanMeasurements -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $measurementList) {
        $measurementList.Value.Add([ordered]@{
            fileName = [IO.Path]::GetFileName($Path); bytes = $result.Bytes
            durationMilliseconds = $result.ElapsedMilliseconds; policy = 'utf8-utf16-marker-v1'
        })
    }
}

function Assert-VelopackPackage {
    param(
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)][string]$ExpectedPackageId,
        [Parameter(Mandatory = $true)][string]$ExpectedVersion,
        [Parameter(Mandatory = $true)][string]$ExpectedChannel,
        [Parameter(Mandatory = $true)][string]$ExpectedTitle,
        [Parameter(Mandatory = $true)][string]$ExpectedExecutable,
        [Parameter(Mandatory = $true)][string]$ExpectedUpdater,
        [string[]]$ExpectedPayloads = @()
    )
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        $nuspecEntries = @($archive.Entries | Where-Object {
            $_.Name.EndsWith('.nuspec', [System.StringComparison]::OrdinalIgnoreCase)
        })
        if ($nuspecEntries.Count -ne 1) {
            throw 'The full package must contain exactly one nuspec.'
        }
        $reader = [System.IO.StreamReader]::new($nuspecEntries[0].Open())
        try {
            [xml]$nuspec = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
        foreach ($requiredName in @(
            $ExpectedExecutable,
            $ExpectedUpdater
        ) + $ExpectedPayloads) {
            $matches = @($archive.Entries | Where-Object {
                $_.Name -ceq $requiredName -and $_.Length -gt 0
            })
            if ($matches.Count -ne 1) {
                throw "The full package must contain exactly one $requiredName."
            }
        }
        $forbiddenEntries = @($archive.Entries | Where-Object {
            $_.FullName -match $ForbiddenPackagedArtifactPattern
        })
        if ($forbiddenEntries.Count -ne 0) {
            throw "The package contains a personal, diagnostic, or temporary file: $($forbiddenEntries[0].FullName)"
        }
    }
    finally {
        $archive.Dispose()
    }

    $metadataPath = "/*[local-name()='package']/*[local-name()='metadata']"
    $expected = [ordered]@{
        id = $ExpectedPackageId
        version = $ExpectedVersion
        channel = $ExpectedChannel
        title = $ExpectedTitle
        mainExe = $ExpectedExecutable
    }
    foreach ($name in $expected.Keys) {
        $node = $nuspec.SelectSingleNode(
            "$metadataPath/*[local-name()='$name']"
        )
        if ($null -eq $node -or $node.InnerText -cne $expected[$name]) {
            throw "The full package has the wrong $name identity."
        }
    }
}

$ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($ReleaseInputCacheRoot)) {
    $ReleaseInputCacheRoot = Join-Path $ProjectRoot 'build\release-input-cache'
}
$IdentityPath = Join-Path $ProjectRoot 'lib\app_identity.dart'
$PubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'
$ReleaseNotesPath = Join-Path $ProjectRoot $ReleaseNotesRelativePath
$BundleDirectory = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
$RunnerIcon = Join-Path $ProjectRoot 'windows\runner\resources\app_icon.ico'
$InstallerSourceDirectory = Join-Path $ProjectRoot 'windows\installer'
$CandidateRoot = Join-Path $ProjectRoot "build\$OutputDirectoryName"
$RunId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') +
    "-$PID-$([Guid]::NewGuid().ToString('N').Substring(0, 12))"
$RunRoot = Join-Path (Join-Path $CandidateRoot 'runs') $RunId
$InputPath = Join-Path $RunRoot 'published-inputs'
$FeedPath = Join-Path $RunRoot 'feed'
$ToolExpanded = Join-Path $RunRoot 'vpk'
$InstallerBuildDirectory = Join-Path (
    Join-Path $ProjectRoot 'build\rc-i'
) "$PID-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
$ManifestPath = Join-Path $RunRoot $ManifestName
$ApprovedPlanCopy = Join-Path $RunRoot 'approved-release-plan.json'
$fullPackageName = "$PackageId-$Version-$UpdateChannel-full.nupkg"
$deltaPackageName = "$PackageId-$Version-$UpdateChannel-delta.nupkg"
$previousFullPackageName =
    "$PackageId-$PreviousStableVersion-$UpdateChannel-full.nupkg"
$setupName = "$PackageId-$UpdateChannel-Setup.exe"
$feedIndexName = "releases.$UpdateChannel.json"

$metricsPath = Join-Path $RunRoot 'stage-metrics.json'
if (Test-Path -LiteralPath $RunRoot) { throw 'The unique candidate run already exists.' }
$null = Assert-ReleaseOrdinaryPath -Path $RunRoot
$null = [IO.Directory]::CreateDirectory($RunRoot)
$builderLock = Open-ReleaseSourceBuildLock -ProjectRoot $ProjectRoot
$metrics = New-ReleaseStageMetrics -RunId $RunId -AutoSavePath $metricsPath
$checkpoint = $null
$script:ReleaseMarkerScanMeasurements = [Collections.Generic.List[object]]::new()
$buildRetryContext = $null
$buildRetryArguments = $null
$activeStage = $null
try {
$activeStage = Start-ReleaseStage -Metrics $metrics -Name 'source-preflight'
if (-not [string]::IsNullOrWhiteSpace($WorkflowReportPath)) {
    $WorkflowReportPath = Assert-ReleaseOrdinaryPath -Path $WorkflowReportPath
    if (Test-Path -LiteralPath $WorkflowReportPath) { throw 'Workflow report must be a new file.' }
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $WorkflowReportPath) -PathType Container)) {
        throw 'Workflow report requires an existing ordinary evidence directory.'
    }
    if ($WorkflowReportPath.StartsWith($ProjectRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Workflow report must be outside the frozen source checkout.'
    }
}
# This is only a conservative floor for historical-input staging. Compilation,
# new packages and installer outputs need additional room; operators may raise it.
$effectiveMinimumFreeBytes = [Math]::Max($MinimumFreeBytes,
    [long](3 * $PreviousFullPackageBytes + 3 * $PreviousFeedBytes))
$preflight = Invoke-ReleasePreflight -ProjectRoot $ProjectRoot -Version $Version `
    -BuildNumber $BuildNumber -PublicGitHubRepository $UpdateSource `
    -MinimumFreeBytes $effectiveMinimumFreeBytes `
    -DependencyReceiptPath $DependencyReceiptPath -ApprovedDependencyReceiptSha256 $ApprovedDependencyReceiptSha256 `
    -FlutterPath $FlutterPath -CMakePath $CMakePath -RequiredRelativeFiles @(
        $ReleaseNotesRelativePath, 'lib/app_identity.dart',
        'windows/runner/resources/app_icon.ico',
        'tool/build_stable_release_candidate.ps1', 'tool/verify_production_source.ps1',
        'tool/release/verified_input_cache.ps1', 'tool/release/source_inventory.ps1',
        'tool/release/preflight.ps1', 'tool/release/stage_metrics.ps1',
        'tool/release/release_plan.ps1'
    )
$FlutterPath = $preflight.FlutterPath
$CMakePath = $preflight.CMakePath
$DotnetPath = $preflight.DotnetPath
$TarPath = $preflight.TarPath
$nativePrerequisites = Invoke-ReleaseNativePrerequisiteChecks -ProjectRoot $ProjectRoot
if ([string]::IsNullOrWhiteSpace($BuildRetryProfilePath) -ne [string]::IsNullOrWhiteSpace($ApprovedBuildRetryProfileSha256) -or
    [string]::IsNullOrWhiteSpace($ResumeBundleReceiptPath) -ne [string]::IsNullOrWhiteSpace($ApprovedResumeBundleReceiptSha256)) {
    throw 'Build retry inputs require both reviewed paths and hashes.'
}
if (-not [string]::IsNullOrWhiteSpace($ResumeBundleReceiptPath) -and [string]::IsNullOrWhiteSpace($BuildRetryProfilePath)) {
    throw 'A bundle retry requires the complete reviewed external-input profile.'
}
if (-not [string]::IsNullOrWhiteSpace($BuildRetryProfilePath)) {
    $buildRetryArguments = @{
        ProjectRoot = $ProjectRoot; ReleasePlanSha256 = $ReleasePlan.Sha256
        ProfilePath = $BuildRetryProfilePath; ApprovedProfileSha256 = $ApprovedBuildRetryProfileSha256
        Tools = [ordered]@{ flutter = $FlutterPath; cmake = $CMakePath; dotnet = $DotnetPath; tar = $TarPath; shell = (Get-Process -Id $PID).Path }
        BuildArguments = @('build', 'windows', '--release', '--no-pub', "--dart-define=$UpdateSourceEnvironmentKey=$UpdateSource")
        RequiredExternalInputs = $nativePrerequisites.selectedInputPaths
        NativePrerequisiteEvidence = $nativePrerequisites
    }
    $buildRetryContext = Get-ReleaseBuildRetryContext @buildRetryArguments
}

$sourceCommit = (& git -C $ProjectRoot rev-parse HEAD).Trim()
Assert-LastExitCode -Operation 'Git source identity check'
if ($sourceCommit -notmatch '^[0-9a-f]{40}$') {
    throw 'The committed source identity is invalid.'
}
if ($sourceCommit -cne $ReleasePlan.ExpectedCommit) {
    throw 'The current source commit does not match the approved release plan.'
}
$expectedSourceTag = $ReleasePlan.ExpectedTag
$sourceTags = @(& git -C $ProjectRoot tag --points-at HEAD)
Assert-LastExitCode -Operation 'Git source tag check'
if ($sourceTags.Count -ne 1 -or $sourceTags[0] -cne $expectedSourceTag) {
    throw "The public candidate must be built from the one exact source tag $expectedSourceTag."
}
$previousSourceTag = $ReleasePlan.PreviousTag
$previousTaggedCommit = (& git -C $ProjectRoot rev-parse "$previousSourceTag^{commit}").Trim()
Assert-LastExitCode -Operation 'Previous public source tag check'
$sourceParentCommit = (& git -C $ProjectRoot rev-parse 'HEAD^').Trim()
Assert-LastExitCode -Operation 'Public source parent check'
if ($previousTaggedCommit -cne $PreviousStableCommit) {
    throw "The reviewed $previousSourceTag tag no longer resolves to its pinned commit."
}
if ($sourceParentCommit -cne $ReviewedReleaseParentCommit) {
    throw 'The public candidate is not one release commit on top of the reviewed installer/tooling baseline.'
}
& git -C $ProjectRoot merge-base --is-ancestor $previousTaggedCommit HEAD
if ($LASTEXITCODE -ne 0) {
    throw "The public candidate does not descend from $previousSourceTag."
}
$sourceCommitCount = (& git -C $ProjectRoot rev-list --count HEAD).Trim()
Assert-LastExitCode -Operation 'Git public history count check'
if ($sourceCommitCount -notmatch '^[1-9][0-9]*$') {
    throw 'The public candidate history count is invalid.'
}
$sourceTag = $expectedSourceTag
Assert-CleanSource -ProjectRoot $ProjectRoot -ExpectedCommit $sourceCommit
Assert-PublicSourceBoundary -ProjectRoot $ProjectRoot
$productionVerifier = Join-Path $PSScriptRoot 'verify_production_source.ps1'
$null = Assert-OrdinaryFile -Path $productionVerifier
& $productionVerifier -ProjectRoot $ProjectRoot
Assert-LastExitCode -Operation 'Production source verification'

$identity = Get-Content -Raw -LiteralPath $IdentityPath
$requiredIdentityFragments = @(
    "static const productName = 'Black Spirit Life';",
    "static const releaseChannel = '$UpdateChannel';",
    "static const applicationVersion = '$Version';",
    'static const importFormerProfilesOnFirstLaunch = false;',
    "static const installerPackageId = '$PackageId';",
    "static const stateDirectoryName = 'Black Spirit Life';",
    "static const windowsExecutableName = 'BlackSpiritLife.exe';",
    "static const windowsUpdaterHelperName = 'BlackSpiritLifeUpdater.exe';"
)
foreach ($fragment in $requiredIdentityFragments) {
    if ($identity.IndexOf($fragment, [System.StringComparison]::Ordinal) -lt 0) {
        throw "AppIdentity is not approved for this release candidate: $fragment"
    }
}
$pubspec = Get-Content -Raw -LiteralPath $PubspecPath
$expectedPubspecVersion = [regex]::Escape("$Version+$BuildNumber")
if ($pubspec -notmatch "(?m)^version:\s*$expectedPubspecVersion\s*`$") {
    throw "pubspec.yaml must identify release candidate version $Version+$BuildNumber."
}

foreach ($required in @($ReleaseNotesPath, $RunnerIcon)) {
    $null = Assert-OrdinaryFile -Path $required
}
$null = Assert-ReleaseOrdinaryPath -Path $RunRoot
New-Item -ItemType Directory -Path $InputPath | Out-Null
New-Item -ItemType Directory -Path $FeedPath | Out-Null
New-Item -ItemType Directory -Path $ToolExpanded | Out-Null
[IO.File]::Copy($ReleasePlan.Path, $ApprovedPlanCopy, $false)
if ((Get-FileHash -LiteralPath $ApprovedPlanCopy -Algorithm SHA256).Hash -cne $ReleasePlan.Sha256) {
    throw 'The frozen release-plan copy does not match the reviewed input.'
}
Complete-ReleaseStage -Metrics $metrics -Stage $activeStage -Outcome Passed -CacheState NotApplicable

$previousFeedUrl =
    "$UpdateSource/releases/download/v$PreviousStableVersion/$feedIndexName"
$previousPackageUrl =
    "$UpdateSource/releases/download/v$PreviousStableVersion/$previousFullPackageName"
$publishedPreviousFeed = Join-Path $InputPath $feedIndexName
$publishedPreviousPackage = Join-Path $InputPath $previousFullPackageName
$previousFullPackage = Join-Path $FeedPath $previousFullPackageName
$activeStage = Start-ReleaseStage -Metrics $metrics -Name 'previous-feed' -InputBytes $PreviousFeedBytes
$feedAcquisition = Get-VerifiedReleaseInput `
    -CacheRoot $ReleaseInputCacheRoot -Repository $UpdateSource `
    -ReleaseTag $previousSourceTag -Channel $UpdateChannel -Role 'previous-feed' `
    -ArtifactName $feedIndexName -ExpectedBytes $PreviousFeedBytes `
    -ExpectedSha256 $PreviousFeedSha256 -Destination $publishedPreviousFeed `
    -ExistingFile $PreviousFeedPath -Offline:$OfflinePinnedInputs `
    -ValidateContent {
        param($Path)
        $inputFeed = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
        $inputAssets = @($inputFeed.Assets | Where-Object {
            $_.PackageId -ceq $PackageId -and $_.Version -ceq $PreviousStableVersion -and
            $_.Type -ceq 'Full' -and $_.FileName -ceq $previousFullPackageName
        })
        if (@($inputFeed.Assets).Count -ne 3 -or $inputAssets.Count -ne 1 -or
            [long]$inputAssets[0].Size -ne $PreviousFullPackageBytes -or
            -not ([string]$inputAssets[0].SHA256).Equals($PreviousFullPackageSha256, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'The historical feed does not describe the pinned previous package.'
        }
    }
$publishedPreviousFeedItem = Assert-OrdinaryFile -Path $publishedPreviousFeed
$publishedPreviousFeedHash =
    (Get-FileHash -Algorithm SHA256 -LiteralPath $publishedPreviousFeed).Hash
if ($publishedPreviousFeedItem.Length -ne $PreviousFeedBytes -or
    $publishedPreviousFeedHash -cne $PreviousFeedSha256) {
    throw "The published $PreviousStableVersion feed changed from the reviewed release input."
}
$publishedPreviousFeedJson =
    Get-Content -Raw -LiteralPath $publishedPreviousFeed | ConvertFrom-Json
$publishedPreviousAssets = @($publishedPreviousFeedJson.Assets | Where-Object {
    $_.PackageId -ceq $PackageId -and
    $_.Version -ceq $PreviousStableVersion -and
    $_.Type -ceq 'Full' -and
    $_.FileName -ceq $previousFullPackageName
})
if ($publishedPreviousAssets.Count -ne 1 -or
    @($publishedPreviousFeedJson.Assets).Count -ne 3) {
    throw "The published $PreviousStableVersion feed does not contain exactly the expected full package and reviewed asset set."
}
$cacheState = if ($feedAcquisition.cacheStatus -eq 'hit') { 'Hit' } else { 'Miss' }
$cacheReason = if ($cacheState -eq 'Miss') { 'not-cached-' + $feedAcquisition.cacheStatus } else { $null }
Complete-ReleaseStage -Metrics $metrics -Stage $activeStage -Outcome Passed `
    -OutputBytes $PreviousFeedBytes -TransferredBytes $feedAcquisition.downloadedBytes `
    -CacheState $cacheState -CacheMissReason $cacheReason
$activeStage = Start-ReleaseStage -Metrics $metrics -Name 'previous-package' -InputBytes $PreviousFullPackageBytes
$packageAcquisition = Get-VerifiedReleaseInput `
    -CacheRoot $ReleaseInputCacheRoot -Repository $UpdateSource `
    -ReleaseTag $previousSourceTag -Channel $UpdateChannel -Role 'previous-full' `
    -ArtifactName $previousFullPackageName -ExpectedBytes $PreviousFullPackageBytes `
    -ExpectedSha256 $PreviousFullPackageSha256 -Destination $publishedPreviousPackage `
    -ExistingFile $PreviousPackagePath -Offline:$OfflinePinnedInputs `
    -ValidateContent {
        param($Path)
        Assert-VelopackPackage -PackagePath $Path -ExpectedPackageId $PackageId `
            -ExpectedVersion $PreviousStableVersion -ExpectedChannel $UpdateChannel `
            -ExpectedTitle $DisplayName -ExpectedExecutable $ExecutableName `
            -ExpectedUpdater $UpdaterHelperName
    }
$publishedPreviousPackageItem =
    Assert-OrdinaryFile -Path $publishedPreviousPackage
$publishedPreviousPackageHash =
    (Get-FileHash -Algorithm SHA256 -LiteralPath $publishedPreviousPackage).Hash
if ($publishedPreviousPackageItem.Length -ne $PreviousFullPackageBytes -or
    $publishedPreviousPackageHash -cne $PreviousFullPackageSha256) {
    throw "The published $PreviousStableVersion full package changed from the reviewed release input."
}
if ([long]$publishedPreviousAssets[0].Size -ne $publishedPreviousPackageItem.Length -or
    -not $publishedPreviousPackageHash.Equals(
        [string]$publishedPreviousAssets[0].SHA256,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw "The published $PreviousStableVersion full package does not match its published feed."
}
Assert-VelopackPackage `
    -PackagePath $publishedPreviousPackage `
    -ExpectedPackageId $PackageId `
    -ExpectedVersion $PreviousStableVersion `
    -ExpectedChannel $UpdateChannel `
    -ExpectedTitle $DisplayName `
    -ExpectedExecutable $ExecutableName `
    -ExpectedUpdater $UpdaterHelperName
Copy-Item -LiteralPath $publishedPreviousPackage -Destination $previousFullPackage
$previousFullItem = Assert-OrdinaryFile -Path $previousFullPackage
$previousFullHash =
    (Get-FileHash -Algorithm SHA256 -LiteralPath $previousFullPackage).Hash
$cacheState = if ($packageAcquisition.cacheStatus -eq 'hit') { 'Hit' } else { 'Miss' }
$cacheReason = if ($cacheState -eq 'Miss') { 'not-cached-' + $packageAcquisition.cacheStatus } else { $null }
Complete-ReleaseStage -Metrics $metrics -Stage $activeStage -Outcome Passed `
    -OutputBytes $PreviousFullPackageBytes -TransferredBytes $packageAcquisition.downloadedBytes `
    -CacheState $cacheState -CacheMissReason $cacheReason
$activeStage = Start-ReleaseStage -Metrics $metrics -Name 'velopack-tool'

$toolRoot = Join-Path $ProjectRoot "build\release-tools\vpk-$VelopackVersion"
$toolPackage = Join-Path $toolRoot "vpk.$VelopackVersion.nupkg"
$toolPreparation = [ordered]@{ downloadMilliseconds = 0; hashMilliseconds = 0; extractionMilliseconds = 0; downloadedBytes = 0 }
if (-not (Test-Path -LiteralPath $toolRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $toolRoot | Out-Null
}
if (-not (Test-Path -LiteralPath $toolPackage -PathType Leaf)) {
    $downloadPath = Join-Path $toolRoot "vpk.$VelopackVersion.download-$PID.nupkg"
    $toolTimer = [Diagnostics.Stopwatch]::StartNew()
    Invoke-WebRequest -Uri $VelopackPackageUrl -OutFile $downloadPath -UseBasicParsing
    $toolTimer.Stop(); $toolPreparation.downloadMilliseconds = $toolTimer.Elapsed.TotalMilliseconds
    $toolPreparation.downloadedBytes = (Get-Item -LiteralPath $downloadPath).Length
    $downloadHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $downloadPath).Hash
    if ($downloadHash -cne $VelopackPackageSha256) {
        throw "Downloaded Velopack package hash mismatch; retained at $downloadPath"
    }
    Move-Item -LiteralPath $downloadPath -Destination $toolPackage
}
$toolTimer = [Diagnostics.Stopwatch]::StartNew()
$toolHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $toolPackage).Hash
$toolTimer.Stop(); $toolPreparation.hashMilliseconds = $toolTimer.Elapsed.TotalMilliseconds
if ($toolHash -cne $VelopackPackageSha256) {
    throw 'The pinned Velopack CLI package failed its SHA-256 check.'
}
$toolTimer = [Diagnostics.Stopwatch]::StartNew()
& $TarPath -xf $toolPackage -C $ToolExpanded
Assert-LastExitCode -Operation 'Pinned Velopack CLI extraction'
$toolTimer.Stop(); $toolPreparation.extractionMilliseconds = $toolTimer.Elapsed.TotalMilliseconds
$vpkDll = Join-Path $ToolExpanded 'tools\net8.0\any\vpk.dll'
$null = Assert-OrdinaryFile -Path $vpkDll

Complete-ReleaseStage -Metrics $metrics -Stage $activeStage -Outcome Passed -CacheState NotApplicable
$activeStage = Start-ReleaseStage -Metrics $metrics -Name 'application-build'

# Flutter's incremental Windows build does not guarantee removal of unrelated
# files already present at the bundle root. Recreate this exact verified output
# so no stale local file can be carried into the public full or delta package.
if (-not [string]::IsNullOrWhiteSpace($ResumeBundleReceiptPath)) {
    $restored = Restore-ReleaseBundleCheckpoint -ReceiptPath $ResumeBundleReceiptPath `
        -ApprovedReceiptSha256 $ApprovedResumeBundleReceiptSha256 -Context $buildRetryContext `
        -Destination (Join-Path $RunRoot 'verified-bundle-staging')
    $BundleDirectory = $restored.Root
}
else {
    Reset-VerifiedWindowsBuildTree -ProjectRoot $ProjectRoot -BundleDirectory $BundleDirectory
    Push-Location -LiteralPath $ProjectRoot
    try {
        & $FlutterPath build windows --release --no-pub `
            "--dart-define=$UpdateSourceEnvironmentKey=$UpdateSource"
        Assert-LastExitCode -Operation 'Flutter Windows Release build'
    }
    finally { Pop-Location }
}
Assert-CleanSource -ProjectRoot $ProjectRoot -ExpectedCommit $sourceCommit
Complete-ReleaseStage -Metrics $metrics -Stage $activeStage -Outcome Passed -CacheState $(if ([string]::IsNullOrWhiteSpace($ResumeBundleReceiptPath)) { 'NotApplicable' } else { 'Hit' })
$activeStage = Start-ReleaseStage -Metrics $metrics -Name 'payload-verification'

$bundleExecutable = Join-Path $BundleDirectory $ExecutableName
$bundleUpdater = Join-Path $BundleDirectory $UpdaterHelperName
$bundleFishHost = Join-Path $BundleDirectory $FishHostHelperName
$bundleRuntime = Join-Path $BundleDirectory 'velopack_libc.dll'
foreach ($required in @(
    $bundleExecutable,
    $bundleUpdater,
    $bundleFishHost,
    $bundleRuntime
)) {
    $null = Assert-OrdinaryFile -Path $required
}
$requiredBundleRelativeFiles = @(
    'webview_flutter_windows_plugin.dll',
    'WebView2Loader.dll',
    'session_import\Session Import.exe',
    'session_import\SummaryOcrNative.exe',
    'session_import\browser_helper\BlackSpiritSessionImportHost.exe',
    'session_import\browser_extension\tracker_helper\manifest.json',
    'session_import\Assets\garmoth_spot_catalog.json',
    'session_import\payload-manifest.json',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion\runtime\fish_companion_service.exe',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion\runtime\runtime-sbom.json',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion\runtime\THIRD_PARTY_NOTICES.md',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion\runtime\licenses\CPython-LICENSE.txt',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion\runtime\licenses\libffi-LICENSE.txt',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion\runtime\licenses\NumPy-LICENSE.txt',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion\runtime\licenses\OpenSSL-LICENSE.txt',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion\runtime\licenses\Pillow-LICENSE.txt',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion\runtime\licenses\PyInstaller-COPYING.txt',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion\runtime\licenses\zlib-LICENSE.txt',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion\data\install-critical-manifest.v1.json',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion\data\cache\source-state.json',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion\static\index.html',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion\static\node-icons\NOTICE.md',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion\data\cache\fish.json',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion\data\cache\zones.json',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion\recognizer\reference-icons\catalog.json',
    'data\flutter_assets\packages\bdo_fishing_core\assets\fish_companion_integrity.json',
    'data\flutter_assets\packages\bdo_gathering_companion\assets\data\loot_catalog.json',
    'data\flutter_assets\packages\bdo_gathering_companion\assets\rotations\NOTICE.md',
    'data\flutter_assets\packages\bdo_gathering_companion\assets\rotations\provenance.json'
)
foreach ($relativePath in $requiredBundleRelativeFiles) {
    $null = Assert-OrdinaryFile -Path (Join-Path $BundleDirectory $relativePath)
}
Assert-SessionImportPayload `
    -Directory (Join-Path $BundleDirectory 'session_import') `
    -SourceDirectory (Join-Path $ProjectRoot 'windows\session_import')
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $bundleRuntime).Hash -cne
    $VelopackRuntimeSha256) {
    throw 'The bundled Velopack runtime failed its pinned SHA-256 check.'
}
$productInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
    $bundleExecutable
)
if ($productInfo.ProductName -cne $DisplayName -or
    $productInfo.ProductVersion -cne "$Version+$BuildNumber") {
    throw 'The compiled application does not have the plain Stable product identity.'
}
$privateMarkers = @(
    $ProjectRoot,
    $env:USERPROFILE,
    ('private-' + 'beta-releases')
)
Assert-NoTextMarker -Path $bundleExecutable -Markers $privateMarkers
$appLibrary = Join-Path $BundleDirectory 'data\app.so'
if (Test-Path -LiteralPath $appLibrary -PathType Leaf) {
    Assert-NoTextMarker -Path $appLibrary -Markers $privateMarkers
}
# This phase has no payload writers. Enumerate once for all three independent
# rule sets; the main EXE was explicitly scanned above, including when hidden.
# This inventory is local to this phase, not reused after packaging/installing.
$bundlePayloadFiles = @(Get-ChildItem -LiteralPath $BundleDirectory -Recurse -File)
$bundleNativePayloads = @($bundlePayloadFiles |
    Where-Object {
        $_.Extension -in @('.exe', '.dll') -and
        $_.FullName -ine $bundleExecutable
    })
foreach ($payload in $bundleNativePayloads) {
    Assert-NoTextMarker -Path $payload.FullName -Markers $privateMarkers
}
$bundleTextPayloads = @($bundlePayloadFiles |
    Where-Object {
        $_.Length -le 32MB -and
        $_.Extension -in @(
            '.json', '.md', '.txt', '.html', '.css', '.js', '.mjs', '.py',
            '.yaml', '.yml', '.xml', '.config', '.ini', '.toml'
        )
    })
foreach ($payload in $bundleTextPayloads) {
    Assert-NoTextMarker -Path $payload.FullName -Markers $privateMarkers
}
$forbiddenBundleFiles = @($bundlePayloadFiles |
    Where-Object {
        $_.FullName -match $ForbiddenPackagedArtifactPattern -or
        $_.Name -match '(?i)\.pdb(?:$|[.-])' -or
        (Test-SqliteFileHeader -Path $_.FullName)
    })
if ($forbiddenBundleFiles.Count -ne 0) {
    throw "The application bundle contains a personal, diagnostic, or temporary file: $($forbiddenBundleFiles[0].FullName)"
}
Complete-ReleaseStage -Metrics $metrics -Stage $activeStage -Outcome Passed -CacheState NotApplicable
$activeStage = Start-ReleaseStage -Metrics $metrics -Name 'full-delta-packaging'

if ($null -ne $buildRetryContext) {
    if ((Get-ReleaseBuildRetryContext @buildRetryArguments).Fingerprint -cne $buildRetryContext.Fingerprint) {
        throw 'Build inputs changed during compilation/verification; no reusable checkpoint can be accepted.'
    }
    if ([string]::IsNullOrWhiteSpace($ResumeBundleReceiptPath)) {
        $checkpoint = New-ReleaseBundleCheckpoint -BundlePath $BundleDirectory `
            -OutputRoot (Join-Path $RunRoot 'build-checkpoint') -Context $buildRetryContext -ConfirmPayloadVerified
        Write-Host "Verified bundle retry receipt: $($checkpoint.Path) SHA256=$($checkpoint.Sha256)"
        # Keep the retained bundle out of mutable packaging outputs.
        $staging = Restore-ReleaseBundleCheckpoint -ReceiptPath $checkpoint.Path -ApprovedReceiptSha256 $checkpoint.Sha256 `
            -Context $buildRetryContext -Destination (Join-Path $RunRoot 'verified-bundle-staging')
        $BundleDirectory = $staging.Root
    }
}

$vpkArguments = @(
    $vpkDll,
    'pack',
    '--outputDir', $FeedPath,
    '--channel', $UpdateChannel,
    '--runtime', 'win-x64',
    '--packId', $PackageId,
    '--packVersion', $Version,
    '--packDir', $BundleDirectory,
    '--packTitle', $DisplayName,
    '--mainExe', $ExecutableName,
    '--icon', $RunnerIcon,
    '--shortcuts', 'StartMenuRoot',
    '--noPortable',
    '--releaseNotes', $ReleaseNotesPath
)
$previousProcessorCount = $env:DOTNET_PROCESSOR_COUNT
try {
    $env:DOTNET_PROCESSOR_COUNT = '4'
    & $DotnetPath @vpkArguments
    Assert-LastExitCode -Operation 'Velopack release-candidate package generation'
}
finally {
    $env:DOTNET_PROCESSOR_COUNT = $previousProcessorCount
}
Complete-ReleaseStage -Metrics $metrics -Stage $activeStage -Outcome Passed -CacheState NotApplicable
$activeStage = Start-ReleaseStage -Metrics $metrics -Name 'feed-verification'

$fullPackage = Join-Path $FeedPath $fullPackageName
$deltaPackage = Join-Path $FeedPath $deltaPackageName
$generatedSetup = Join-Path $FeedPath $setupName
$feedIndex = Join-Path $FeedPath $feedIndexName
foreach ($required in @(
    $previousFullPackage,
    $fullPackage,
    $deltaPackage,
    $generatedSetup,
    $feedIndex
)) {
    $null = Assert-OrdinaryFile -Path $required
}
Assert-VelopackPackage `
    -PackagePath $fullPackage `
    -ExpectedPackageId $PackageId `
    -ExpectedVersion $Version `
    -ExpectedChannel $UpdateChannel `
    -ExpectedTitle $DisplayName `
    -ExpectedExecutable $ExecutableName `
    -ExpectedUpdater $UpdaterHelperName `
    -ExpectedPayloads @($FishHostHelperName)

$feed = Get-Content -Raw -LiteralPath $feedIndex | ConvertFrom-Json
$previousFullItem = Assert-OrdinaryFile -Path $previousFullPackage
$previousFullHash =
    (Get-FileHash -Algorithm SHA256 -LiteralPath $previousFullPackage).Hash
if ($previousFullItem.Length -ne $PreviousFullPackageBytes -or
    $previousFullHash -cne $PreviousFullPackageSha256) {
    throw "Velopack changed the pinned published $PreviousStableVersion full package."
}
$feedAssets = @($feed.Assets)
if ($feedAssets.Count -ne 3) {
    throw 'The update feed must contain exactly the previous full package, current full package, and current delta package.'
}
$matchingFullAssets = @($feedAssets | Where-Object {
    $_.PackageId -ceq $PackageId -and
    $_.Version -ceq $Version -and
    $_.Type -ceq 'Full' -and
    $_.FileName -ceq $fullPackageName
})
$matchingDeltaAssets = @($feedAssets | Where-Object {
    $_.PackageId -ceq $PackageId -and
    $_.Version -ceq $Version -and
    $_.Type -ceq 'Delta' -and
    $_.FileName -ceq $deltaPackageName
})
$matchingPreviousAssets = @($feedAssets | Where-Object {
    $_.PackageId -ceq $PackageId -and
    $_.Version -ceq $PreviousStableVersion -and
    $_.Type -ceq 'Full' -and
    $_.FileName -ceq $previousFullPackageName
})
if ($matchingFullAssets.Count -ne 1) {
    throw 'The update feed does not contain exactly one expected full package.'
}
if ($matchingDeltaAssets.Count -ne 1) {
    throw "The update feed does not contain exactly one $PreviousStableVersion to $Version delta package."
}
if ($matchingPreviousAssets.Count -ne 1) {
    throw "The update feed does not retain exactly one published $PreviousStableVersion full package."
}
$fullItem = Get-Item -LiteralPath $fullPackage
$fullHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $fullPackage).Hash
if ([long]$matchingFullAssets[0].Size -ne $fullItem.Length -or
    -not $fullHash.Equals(
        [string]$matchingFullAssets[0].SHA256,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw 'The update feed checksum does not match the full package.'
}
$deltaItem = Get-Item -LiteralPath $deltaPackage
$deltaHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $deltaPackage).Hash
if ($deltaItem.Length -ge $fullItem.Length) {
    throw 'The generated delta package must be smaller than the full package.'
}
if ([long]$matchingDeltaAssets[0].Size -ne $deltaItem.Length -or
    -not $deltaHash.Equals(
        [string]$matchingDeltaAssets[0].SHA256,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw 'The update feed checksum does not match the delta package.'
}
if ([long]$matchingPreviousAssets[0].Size -ne $previousFullItem.Length -or
    -not $previousFullHash.Equals(
        [string]$matchingPreviousAssets[0].SHA256,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw "The updated feed changed the published $PreviousStableVersion full-package identity."
}

$setupHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $generatedSetup).Hash
Complete-ReleaseStage -Metrics $metrics -Stage $activeStage -Outcome Passed `
    -OutputBytes ($fullItem.Length + $deltaItem.Length) -CacheState NotApplicable
$activeStage = Start-ReleaseStage -Metrics $metrics -Name 'installer-build'
$cmakeConfigure = @(
    '-S', $InstallerSourceDirectory,
    '-B', $InstallerBuildDirectory,
    '-G', 'Visual Studio 17 2022',
    '-A', 'x64',
    "-DBSL_INSTALLER_VERSION=$Version",
    "-DBSL_INSTALLER_BUILD_NUMBER=$BuildNumber",
    "-DBSL_INSTALLER_PACKAGE_ID=$PackageId",
    "-DBSL_INSTALLER_CHANNEL=$UpdateChannel",
    "-DBSL_INSTALLER_ENGINE=$generatedSetup",
    "-DBSL_INSTALLER_ENGINE_SHA256=$setupHash"
)
& $CMakePath @cmakeConfigure
Assert-LastExitCode -Operation 'Themed installer configuration'
& $CMakePath --build $InstallerBuildDirectory --config Release --parallel 4
Assert-LastExitCode -Operation 'Themed installer build'
Complete-ReleaseStage -Metrics $metrics -Stage $activeStage -Outcome Passed -CacheState NotApplicable
$activeStage = Start-ReleaseStage -Metrics $metrics -Name 'installer-verification'

$builtInstaller = Join-Path $InstallerBuildDirectory "Release\$BuiltInstallerName"
$null = Assert-OrdinaryFile -Path $builtInstaller
$payloadCheck = Start-Process `
    -FilePath $builtInstaller `
    -ArgumentList '--verify-payload' `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
if ($payloadCheck.ExitCode -ne 0) {
    throw 'The themed installer rejected its embedded Velopack payload.'
}
$candidateInstaller = Join-Path $RunRoot $InstallerName
Copy-Item -LiteralPath $builtInstaller -Destination $candidateInstaller
$null = Assert-OrdinaryFile -Path $candidateInstaller
$installerInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
    $candidateInstaller
)
if ($installerInfo.ProductName -cne $InstallerProductName -or
    $installerInfo.ProductVersion -cne "$Version+$BuildNumber" -or
    $installerInfo.FileVersion -cne "$Version.$BuildNumber") {
    throw 'The themed installer does not have the plain product identity.'
}
Assert-NoTextMarker `
    -Path $candidateInstaller `
    -Markers $privateMarkers `
    -AllowReviewedVelopackBuildPaths
Assert-CleanSource -ProjectRoot $ProjectRoot -ExpectedCommit $sourceCommit

Complete-ReleaseStage -Metrics $metrics -Stage $activeStage -Outcome Passed -CacheState NotApplicable
$activeStage = Start-ReleaseStage -Metrics $metrics -Name 'candidate-manifest'
$installerRecord = Get-ArtifactRecord `
    -Role 'themed-installer' -Path $candidateInstaller -RelativeTo $RunRoot
$setupRecord = Get-ArtifactRecord `
    -Role 'velopack-setup' -Path $generatedSetup -RelativeTo $RunRoot
$fullPackageRecord = Get-ArtifactRecord `
    -Role 'full-package' -Path $fullPackage -RelativeTo $RunRoot
$deltaPackageRecord = Get-ArtifactRecord `
    -Role 'delta-package' -Path $deltaPackage -RelativeTo $RunRoot
$feedRecord = Get-ArtifactRecord `
    -Role 'update-feed' -Path $feedIndex -RelativeTo $RunRoot
$publishedPreviousFeedRecord = Get-ArtifactRecord `
    -Role 'published-previous-feed' `
    -Path $publishedPreviousFeed `
    -RelativeTo $RunRoot
$previousFullPackageRecord = Get-ArtifactRecord `
    -Role 'published-previous-full-package' `
    -Path $publishedPreviousPackage `
    -RelativeTo $RunRoot
$publishedPreviousFeedRecord['releaseTag'] = $previousSourceTag
$publishedPreviousFeedRecord['sourceUrl'] = $previousFeedUrl
$previousFullPackageRecord['releaseTag'] = $previousSourceTag
$previousFullPackageRecord['sourceUrl'] = $previousPackageUrl
$artifacts = @(
    $installerRecord,
    $setupRecord,
    $fullPackageRecord,
    $deltaPackageRecord,
    $feedRecord
)
$manifest = [ordered]@{
    schemaVersion = 2
    localOnly = $false
    publicCandidate = $true
    published = $false
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    displayName = $DisplayName
    version = $Version
    buildNumber = [int]$BuildNumber
    sourceCommit = $sourceCommit
    sourceTag = $sourceTag
    releasePlan = [ordered]@{
        path = [IO.Path]::GetFileName($ApprovedPlanCopy)
        sha256 = $ReleasePlan.Sha256
        schemaVersion = [int]$ReleasePlan.Raw.schemaVersion
    }
    packageId = $PackageId
    channel = $UpdateChannel
    updateSource = $UpdateSource
    pinnedInputAcquisition = @($feedAcquisition, $packageAcquisition)
    preflight = $preflight.Evidence
    nativePrerequisites = $nativePrerequisites
    buildRetry = [ordered]@{
        enabled = ($null -ne $buildRetryContext)
        reusedBundle = (-not [string]::IsNullOrWhiteSpace($ResumeBundleReceiptPath))
        contextFingerprint = if ($null -ne $buildRetryContext) { $buildRetryContext.Fingerprint } else { $null }
        newCheckpointSha256 = if ($null -ne $checkpoint) { $checkpoint.Sha256 } else { $null }
    }
    stageMeasurements = 'stage-metrics.json'
    toolPreparationMeasurements = $toolPreparation
    markerScanMeasurements = @($script:ReleaseMarkerScanMeasurements.ToArray())
    publicSourceHistory = [ordered]@{
        previousTag = $previousSourceTag
        previousCommit = $previousTaggedCommit
        previousReleaseCommit = $sourceParentCommit
        currentTag = $sourceTag
        currentCommit = $sourceCommit
        reachableCommitCount = [int]$sourceCommitCount
    }
    cleanProfile = [ordered]@{
        stateDirectory = '%APPDATA%\Black Spirit Life'
        selectedRootIsMovable = $true
        autoImportsFormerProfiles = $false
        initialMasteries = 0
        initialInventoryEntries = 0
        initialGatheringLoadouts = 0
        initialGatheringSessions = 0
        initialFishingProfiles = 0
        initialFishingJournalEntries = 0
        initialSessionImportDrafts = 0
        bundledPersonalDataFiles = 0
        generatedBrowserProfilesBundled = 0
        fishReferenceSnapshotIsPersonalData = $false
    }
    artifacts = $artifacts
    publicUploadArtifacts = @(
        $installerRecord,
        $fullPackageRecord,
        $deltaPackageRecord,
        $feedRecord
    )
    delta = [ordered]@{
        previousStableVersion = $PreviousStableVersion
        expected = $true
        generated = $true
        publishedInputs = @(
            $publishedPreviousFeedRecord,
            $previousFullPackageRecord
        )
        artifacts = @($deltaPackageRecord)
        verificationRequiredBeforePublication = $true
    }
    remainingBlockers = $RemainingBlockers
}
$manifestJson = $manifest | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText(
    $ManifestPath,
    "$manifestJson`r`n",
    [System.Text.UTF8Encoding]::new($false)
)
$null = Assert-OrdinaryFile -Path $ManifestPath
if (-not [string]::IsNullOrWhiteSpace($WorkflowReportPath)) {
    $workflowSummary = [ordered]@{
        schemaVersion = 1; purpose = 'candidate-build'; success = $true
        sourceCommit = $sourceCommit; releasePlanSha256 = $ReleasePlan.Sha256
        version = $Version; buildNumber = [int]$BuildNumber
        candidateManifest = [ordered]@{ path = $ManifestPath; sha256 = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash }
        isReleaseVerification = $false; published = $false
    }
    $partial = $WorkflowReportPath + '.partial-' + [Guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($partial, ($workflowSummary | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($partial, $WorkflowReportPath)
}
Complete-ReleaseStage -Metrics $metrics -Stage $activeStage -Outcome Passed -CacheState NotApplicable
$activeStage = $null

Write-Host ''
Write-Host 'Public Black Spirit Life release candidate created. Nothing was published.'
Write-Host "Version: $Version+$BuildNumber"
Write-Host "Source commit: $sourceCommit"
Write-Host "Package ID: $PackageId"
Write-Host "Channel: $UpdateChannel"
Write-Host "Installer: $candidateInstaller"
Write-Host "Delta: $deltaPackage"
Write-Host "Manifest: $ManifestPath"
}
catch {
    if ($null -eq $activeStage -or $activeStage.Outcome -ne 'Running') {
        $activeStage = Start-ReleaseStage -Metrics $metrics -Name 'candidate-orchestration'
    }
    Complete-ReleaseStage -Metrics $metrics -Stage $activeStage -Outcome Failed `
        -FailureCode 'stage-failed'
    throw
}
finally {
    # These timing records are deliberately not build-reuse or publication
    # receipts. A failed prerequisite must remain a failed invocation.
    try {
        $null = Assert-ReleaseOrdinaryPath -Path $RunRoot
        $null = [IO.Directory]::CreateDirectory($RunRoot)
        Save-ReleaseStageMetrics -Metrics $metrics -Path $metricsPath
        Write-Host "Stage measurements: $metricsPath"
    }
    catch { Write-Warning 'Could not save release stage measurements.' }
    finally { if ($null -ne $builderLock) { $builderLock.Dispose() } }
}
