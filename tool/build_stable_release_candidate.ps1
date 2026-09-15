[CmdletBinding()]
param(
    [string]$FlutterPath,
    [string]$CMakePath,

    [Parameter(Mandatory = $true)]
    [string]$PublicGitHubRepository,

    [Parameter(Mandatory = $true)]
    [switch]$ConfirmPublicCandidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfirmPublicCandidateOnly.IsPresent) {
    throw 'Supply -ConfirmPublicCandidateOnly. This script prepares artifacts but never publishes them.'
}
if ($PublicGitHubRepository -cnotmatch
    '^https://github\.com/[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})/[A-Za-z0-9._-]{1,100}$') {
    throw 'The public update source must be the permanent canonical repository base URL: https://github.com/OWNER/REPOSITORY'
}
$Version = '0.1.9'
$BuildNumber = '28'
$PreviousStableVersion = '0.1.7'
$PreviousStableCommit =
    '74e9b21887ce84d2c51d2ed82182acee4f8495ec'
$UpdateSource = $PublicGitHubRepository
$ReleaseNotesRelativePath = 'docs\releases\0.1.9.md'
$OutputDirectoryName = 'public-stable-candidate'
$ManifestName = 'public-candidate-manifest.json'
$RemainingBlockers = @(
    'verify an installed 0.1.7 updates to 0.1.9 through the in-app update bar with its selected personal-data root intact',
    'complete fresh install, repair, and uninstall lifecycle verification',
    'fresh-clone privacy and release-artifact scan'
)

$PackageId = 'BlackSpiritLife.App'
$UpdateChannel = 'win-x64-stable'
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
$PreviousFeedBytes = 16577L
$PreviousFeedSha256 =
    'C37C7B35BCD2F9E95D12FD227A9F2EC0D0365288E32F68605E02629F221B3A44'
$PreviousFullPackageBytes = 218802840L
$PreviousFullPackageSha256 =
    '6D42ECBF970A4549F2B32DC2C9069F96918250A938CF8CB54ADD1DDDD1AE29E6'
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

    $forbiddenPersonalFiles = @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File |
        Where-Object {
            $_.FullName -notmatch '\\(?:\.git|\.dart_tool|build|bin|obj)\\' -and
            $_.FullName -notmatch '\\windows\\flutter\\ephemeral\\' -and
            ($_.FullName -match $ForbiddenPackagedArtifactPattern -or
             (Test-SqliteFileHeader -Path $_.FullName))
        })
    if ($forbiddenPersonalFiles.Count -ne 0) {
        throw "The public source contains personal state, a database, or a debug symbol: $($forbiddenPersonalFiles[0].FullName)"
    }

    $generatedBrowserState = @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -Directory -Force |
        Where-Object {
            $_.FullName -notmatch '\\(?:\.git|\.dart_tool|build|bin|obj)\\' -and
            $_.FullName -notmatch '\\windows\\flutter\\ephemeral\\' -and
            $_.Name -match '(?i)^(?:webview2|video[ _-]*webview|webview[ _-]*profile|browser[ _-]*profile|user[ _-]*data|cookies?|local[ _-]*storage|BlackSpiritLife\.App\.Removal)$'
        })
    if ($generatedBrowserState.Count -ne 0) {
        throw "The public source contains generated browser-profile state: $($generatedBrowserState[0].FullName)"
    }
    $sessionImportInboxes = @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -Directory -Force |
        Where-Object {
            $_.FullName -notmatch '\\(?:\.git|\.dart_tool|build|bin|obj)\\' -and
            $_.FullName -notmatch '\\windows\\flutter\\ephemeral\\' -and
            $_.Name -ieq 'session-import-inbox'
        })
    if ($sessionImportInboxes.Count -ne 0) {
        throw "The public source contains generated Session Import receipts: $($sessionImportInboxes[0].FullName)"
    }
    $customIcons = @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Force |
        Where-Object {
            $_.FullName -notmatch '\\(?:\.git|\.dart_tool|build|bin|obj)\\' -and
            $_.FullName -notmatch '\\windows\\flutter\\ephemeral\\' -and
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
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $utf8 = [System.Text.Encoding]::UTF8.GetString($bytes)
    $utf16 = [System.Text.Encoding]::Unicode.GetString($bytes)
    foreach ($marker in $Markers) {
        if ([string]::IsNullOrWhiteSpace($marker)) {
            continue
        }
        if ($utf8.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $utf16.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "Packaged file contains a private-machine marker '$marker': $Path"
        }
    }
    # The pinned upstream Velopack runtime contains its own Windows compiler
    # path. Only its exact reviewed hash may bypass this generic path test;
    # the explicit project/user/private markers above still apply.
    $isPinnedVelopackRuntime =
        [System.IO.Path]::GetFileName($Path) -ceq 'velopack_libc.dll' -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash -ceq
            $VelopackRuntimeSha256
    # The pinned upstream Rust Setup engine retains its public GitHub Actions
    # .cargo/.rustup roots. Only those two prefixes may be ignored when the
    # caller opts in; explicit project/user markers above are never exempted.
    if (-not $isPinnedVelopackRuntime -and
        ((Test-UnreviewedAbsolutePath `
            -Text $utf8 `
            -AllowReviewedVelopackBuildPaths:$AllowReviewedVelopackBuildPaths) -or
         (Test-UnreviewedAbsolutePath `
            -Text $utf16 `
            -AllowReviewedVelopackBuildPaths:$AllowReviewedVelopackBuildPaths))) {
        throw "Packaged file contains an absolute user/private workspace path: $Path"
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
$fullPackageName = "$PackageId-$Version-$UpdateChannel-full.nupkg"
$deltaPackageName = "$PackageId-$Version-$UpdateChannel-delta.nupkg"
$previousFullPackageName =
    "$PackageId-$PreviousStableVersion-$UpdateChannel-full.nupkg"
$setupName = "$PackageId-$UpdateChannel-Setup.exe"
$feedIndexName = "releases.$UpdateChannel.json"

$sourceCommit = (& git -C $ProjectRoot rev-parse HEAD).Trim()
Assert-LastExitCode -Operation 'Git source identity check'
if ($sourceCommit -notmatch '^[0-9a-f]{40}$') {
    throw 'The committed source identity is invalid.'
}
$expectedSourceTag = "v$Version"
$sourceTags = @(& git -C $ProjectRoot tag --points-at HEAD)
Assert-LastExitCode -Operation 'Git source tag check'
if ($sourceTags.Count -ne 1 -or $sourceTags[0] -cne $expectedSourceTag) {
    throw "The public candidate must be built from the one exact source tag $expectedSourceTag."
}
$previousSourceTag = "v$PreviousStableVersion"
$previousTaggedCommit = (& git -C $ProjectRoot rev-parse "$previousSourceTag^{commit}").Trim()
Assert-LastExitCode -Operation 'Previous public source tag check'
$sourceParentCommit = (& git -C $ProjectRoot rev-parse 'HEAD^').Trim()
Assert-LastExitCode -Operation 'Public source parent check'
if ($sourceParentCommit -cne $PreviousStableCommit -or
    $sourceParentCommit -cne $previousTaggedCommit) {
    throw "The public candidate must be one sanitized source commit on top of $previousSourceTag."
}
$sourceCommitCount = (& git -C $ProjectRoot rev-list --count HEAD).Trim()
Assert-LastExitCode -Operation 'Git public history count check'
if ($sourceCommitCount -cne '7') {
    throw 'The public candidate must contain only the reviewed seven-commit public history through exact-Beta Stable 0.1.9.'
}
$sourceTag = $expectedSourceTag
Assert-CleanSource -ProjectRoot $ProjectRoot -ExpectedCommit $sourceCommit
Assert-PublicSourceBoundary -ProjectRoot $ProjectRoot
$productionVerifier = Join-Path $PSScriptRoot 'verify_production_source.ps1'
$null = Assert-OrdinaryFile -Path $productionVerifier
& $productionVerifier -ProjectRoot $ProjectRoot

$identity = Get-Content -Raw -LiteralPath $IdentityPath
$requiredIdentityFragments = @(
    "static const productName = 'Black Spirit Life';",
    "static const releaseChannel = 'win-x64-stable';",
    "static const applicationVersion = '$Version';",
    'static const importFormerProfilesOnFirstLaunch = false;',
    "static const installerPackageId = 'BlackSpiritLife.App';",
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
if (Test-Path -LiteralPath $RunRoot) {
    throw "The unique release-candidate output already exists: $RunRoot"
}
New-Item -ItemType Directory -Path $InputPath | Out-Null
New-Item -ItemType Directory -Path $FeedPath | Out-Null
New-Item -ItemType Directory -Path $ToolExpanded | Out-Null

$previousFeedUrl =
    "$UpdateSource/releases/download/v$PreviousStableVersion/$feedIndexName"
$previousPackageUrl =
    "$UpdateSource/releases/download/v$PreviousStableVersion/$previousFullPackageName"
$publishedPreviousFeed = Join-Path $InputPath $feedIndexName
$publishedPreviousPackage = Join-Path $InputPath $previousFullPackageName
$previousFullPackage = Join-Path $FeedPath $previousFullPackageName
Invoke-WebRequest -Uri $previousFeedUrl -OutFile $publishedPreviousFeed -UseBasicParsing
$publishedPreviousFeedItem = Assert-OrdinaryFile -Path $publishedPreviousFeed
$publishedPreviousFeedHash =
    (Get-FileHash -Algorithm SHA256 -LiteralPath $publishedPreviousFeed).Hash
if ($publishedPreviousFeedItem.Length -ne $PreviousFeedBytes -or
    $publishedPreviousFeedHash -cne $PreviousFeedSha256) {
    throw 'The published 0.1.7 feed changed from the reviewed release input.'
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
    throw 'The published 0.1.7 feed does not contain exactly the expected full package and reviewed asset set.'
}
Invoke-WebRequest `
    -Uri $previousPackageUrl `
    -OutFile $publishedPreviousPackage `
    -UseBasicParsing
$publishedPreviousPackageItem =
    Assert-OrdinaryFile -Path $publishedPreviousPackage
$publishedPreviousPackageHash =
    (Get-FileHash -Algorithm SHA256 -LiteralPath $publishedPreviousPackage).Hash
if ($publishedPreviousPackageItem.Length -ne $PreviousFullPackageBytes -or
    $publishedPreviousPackageHash -cne $PreviousFullPackageSha256) {
    throw 'The published 0.1.7 full package changed from the reviewed release input.'
}
if ([long]$publishedPreviousAssets[0].Size -ne $publishedPreviousPackageItem.Length -or
    -not $publishedPreviousPackageHash.Equals(
        [string]$publishedPreviousAssets[0].SHA256,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw 'The published 0.1.7 full package does not match its published feed.'
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

$toolRoot = Join-Path $ProjectRoot "build\release-tools\vpk-$VelopackVersion"
$toolPackage = Join-Path $toolRoot "vpk.$VelopackVersion.nupkg"
if (-not (Test-Path -LiteralPath $toolRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $toolRoot | Out-Null
}
if (-not (Test-Path -LiteralPath $toolPackage -PathType Leaf)) {
    $downloadPath = Join-Path $toolRoot "vpk.$VelopackVersion.download-$PID.nupkg"
    Invoke-WebRequest -Uri $VelopackPackageUrl -OutFile $downloadPath -UseBasicParsing
    $downloadHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $downloadPath).Hash
    if ($downloadHash -cne $VelopackPackageSha256) {
        throw "Downloaded Velopack package hash mismatch; retained at $downloadPath"
    }
    Move-Item -LiteralPath $downloadPath -Destination $toolPackage
}
$toolHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $toolPackage).Hash
if ($toolHash -cne $VelopackPackageSha256) {
    throw 'The pinned Velopack CLI package failed its SHA-256 check.'
}
& tar -xf $toolPackage -C $ToolExpanded
Assert-LastExitCode -Operation 'Pinned Velopack CLI extraction'
$vpkDll = Join-Path $ToolExpanded 'tools\net8.0\any\vpk.dll'
$null = Assert-OrdinaryFile -Path $vpkDll

if ([string]::IsNullOrWhiteSpace($FlutterPath)) {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    $FlutterPath = if ($null -ne $flutterCommand) {
        $flutterCommand.Source
    }
    else {
        Join-Path $env:USERPROFILE 'develop\flutter\bin\flutter.bat'
    }
}
$null = Assert-OrdinaryFile -Path $FlutterPath

if ([string]::IsNullOrWhiteSpace($CMakePath)) {
    $cmakeCommand = Get-Command cmake -ErrorAction SilentlyContinue
    if ($null -ne $cmakeCommand) {
        $CMakePath = $cmakeCommand.Source
    }
    else {
        $cmakeCandidates = @(
            (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'),
            (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'),
            (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\2022\Professional\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'),
            (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\2022\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe')
        )
        $CMakePath = @($cmakeCandidates | Where-Object {
            Test-Path -LiteralPath $_ -PathType Leaf
        }) | Select-Object -First 1
    }
}
$null = Assert-OrdinaryFile -Path $CMakePath
if ($null -eq (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'The .NET 8 runtime required by Velopack was not found.'
}

# Flutter's incremental Windows build does not guarantee removal of unrelated
# files already present at the bundle root. Recreate this exact verified output
# so no stale local file can be carried into the public full or delta package.
Reset-VerifiedWindowsBuildTree `
    -ProjectRoot $ProjectRoot `
    -BundleDirectory $BundleDirectory

Push-Location -LiteralPath $ProjectRoot
try {
    & $FlutterPath build windows --release --no-pub `
        "--dart-define=$UpdateSourceEnvironmentKey=$UpdateSource"
    Assert-LastExitCode -Operation 'Flutter Windows Release build'
}
finally {
    Pop-Location
}
Assert-CleanSource -ProjectRoot $ProjectRoot -ExpectedCommit $sourceCommit

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
$bundleNativePayloads = @(Get-ChildItem -LiteralPath $BundleDirectory -Recurse -File |
    Where-Object { $_.Extension -in @('.exe', '.dll') })
foreach ($payload in $bundleNativePayloads) {
    Assert-NoTextMarker -Path $payload.FullName -Markers $privateMarkers
}
$bundleTextPayloads = @(Get-ChildItem -LiteralPath $BundleDirectory -Recurse -File |
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
$forbiddenBundleFiles = @(Get-ChildItem -LiteralPath $BundleDirectory -Recurse -File |
    Where-Object {
        $_.FullName -match $ForbiddenPackagedArtifactPattern -or
        $_.Name -match '(?i)\.pdb(?:$|[.-])' -or
        (Test-SqliteFileHeader -Path $_.FullName)
    })
if ($forbiddenBundleFiles.Count -ne 0) {
    throw "The application bundle contains a personal, diagnostic, or temporary file: $($forbiddenBundleFiles[0].FullName)"
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
    & dotnet @vpkArguments
    Assert-LastExitCode -Operation 'Velopack release-candidate package generation'
}
finally {
    $env:DOTNET_PROCESSOR_COUNT = $previousProcessorCount
}

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
    throw 'Velopack changed the pinned published 0.1.7 full package.'
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
    throw 'The update feed does not contain exactly one 0.1.7 to 0.1.9 delta package.'
}
if ($matchingPreviousAssets.Count -ne 1) {
    throw 'The update feed does not retain exactly one published 0.1.7 full package.'
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
    throw 'The updated feed changed the published 0.1.7 full-package identity.'
}

$setupHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $generatedSetup).Hash
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
    packageId = $PackageId
    channel = $UpdateChannel
    updateSource = $UpdateSource
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

Write-Host ''
Write-Host 'Public Black Spirit Life release candidate created. Nothing was published.'
Write-Host "Version: $Version+$BuildNumber"
Write-Host "Source commit: $sourceCommit"
Write-Host "Package ID: $PackageId"
Write-Host "Channel: $UpdateChannel"
Write-Host "Installer: $candidateInstaller"
Write-Host "Delta: $deltaPackage"
Write-Host "Manifest: $ManifestPath"
