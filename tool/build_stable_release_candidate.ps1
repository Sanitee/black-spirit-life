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
$Version = '0.1.4'
$BuildNumber = '23'
$PreviousStableVersion = '0.1.3'
$PreviousPublicMainCommit =
    'e0f241bf1a697caf8398e7da81a34aae426c8d64'
$UpdateSource = $PublicGitHubRepository
$ReleaseNotesRelativePath = 'docs\releases\0.1.4.md'
$OutputDirectoryName = 'public-stable-candidate'
$ManifestName = 'public-candidate-manifest.json'
$RemainingBlockers = @(
    'verify an installed 0.1.3 updates to 0.1.4 through the in-app update bar with its personal data intact',
    'complete fresh install, repair, and uninstall lifecycle verification',
    'fresh-clone privacy and release-artifact scan',
    'explicit final approval immediately before public GitHub publication'
)

$PackageId = 'BlackSpiritLife.App'
$UpdateChannel = 'win-x64-stable'
$DisplayName = 'Black Spirit Life'
$InstallerProductName = 'Black Spirit Life Installer'
$ExecutableName = 'BlackSpiritLife.exe'
$UpdaterHelperName = 'BlackSpiritLifeUpdater.exe'
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
$PreviousFeedBytes = 4867L
$PreviousFeedSha256 =
    '5601CF70C6165863843B59F7836517C0700FE5DA39B7270D3F9146E4F0EF10E2'
$PreviousFullPackageBytes = 75111193L
$PreviousFullPackageSha256 =
    '36AB8CDB27E885F677CAF3B1D5CD20A332A0C203DD17EE83B9D7B55900577110'

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

function Assert-NoTextMarker {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Markers
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
}

function Assert-VelopackPackage {
    param(
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)][string]$ExpectedPackageId,
        [Parameter(Mandatory = $true)][string]$ExpectedVersion,
        [Parameter(Mandatory = $true)][string]$ExpectedChannel,
        [Parameter(Mandatory = $true)][string]$ExpectedTitle,
        [Parameter(Mandatory = $true)][string]$ExpectedExecutable,
        [Parameter(Mandatory = $true)][string]$ExpectedUpdater
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
        foreach ($requiredName in @($ExpectedExecutable, $ExpectedUpdater)) {
            $matches = @($archive.Entries | Where-Object {
                $_.Name -ceq $requiredName -and $_.Length -gt 0
            })
            if ($matches.Count -ne 1) {
                throw "The full package must contain exactly one $requiredName."
            }
        }
        $forbiddenEntries = @($archive.Entries | Where-Object {
            $_.FullName -match '(?i)(planner-state|personal-data-location|\.dmp$|\.log$|\.tmp$|\.bak$|screenshot)'
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
$InstallerBuildDirectory = Join-Path $RunRoot 'installer-build'
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
$previousPublicMainCommit = (& git -C $ProjectRoot rev-parse 'HEAD^').Trim()
Assert-LastExitCode -Operation 'Public source parent check'
if ($previousPublicMainCommit -cne $PreviousPublicMainCommit) {
    throw 'The public candidate must be one release commit on top of the reviewed public main commit.'
}
$previousPublicMainParent = (& git -C $ProjectRoot rev-parse "$PreviousPublicMainCommit^").Trim()
Assert-LastExitCode -Operation 'Previous public main ancestry check'
if ($previousPublicMainParent -cne $previousTaggedCommit) {
    throw "The reviewed public main commit must be directly based on $previousSourceTag."
}
$sourceCommitCount = (& git -C $ProjectRoot rev-list --count HEAD).Trim()
Assert-LastExitCode -Operation 'Git public history count check'
if ($sourceCommitCount -cne '3') {
    throw 'The public candidate must contain only the sanitized 0.1.3 root, reviewed public README commit, and sanitized 0.1.4 release commit.'
}
$sourceTag = $expectedSourceTag
Assert-CleanSource -ProjectRoot $ProjectRoot -ExpectedCommit $sourceCommit

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
    throw 'The published 0.1.3 feed changed from the reviewed release input.'
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
    @($publishedPreviousFeedJson.Assets).Count -ne 1) {
    throw 'The published 0.1.3 feed does not contain exactly the expected full package.'
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
    throw 'The published 0.1.3 full package changed from the reviewed release input.'
}
if ([long]$publishedPreviousAssets[0].Size -ne $publishedPreviousPackageItem.Length -or
    -not $publishedPreviousPackageHash.Equals(
        [string]$publishedPreviousAssets[0].SHA256,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw 'The published 0.1.3 full package does not match its published feed.'
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
$bundleRuntime = Join-Path $BundleDirectory 'velopack_libc.dll'
foreach ($required in @($bundleExecutable, $bundleUpdater, $bundleRuntime)) {
    $null = Assert-OrdinaryFile -Path $required
}
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
$forbiddenBundleFiles = @(Get-ChildItem -LiteralPath $BundleDirectory -Recurse -File |
    Where-Object {
        $_.Name -match '(?i)(planner-state|personal-data-location|\.pdb$|\.dmp$|\.log$|\.tmp$|\.bak$|screenshot)'
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
    -ExpectedUpdater $UpdaterHelperName

$feed = Get-Content -Raw -LiteralPath $feedIndex | ConvertFrom-Json
$previousFullItem = Assert-OrdinaryFile -Path $previousFullPackage
$previousFullHash =
    (Get-FileHash -Algorithm SHA256 -LiteralPath $previousFullPackage).Hash
if ($previousFullItem.Length -ne $PreviousFullPackageBytes -or
    $previousFullHash -cne $PreviousFullPackageSha256) {
    throw 'Velopack changed the pinned published 0.1.3 full package.'
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
    throw 'The update feed does not contain exactly one 0.1.3 to 0.1.4 delta package.'
}
if ($matchingPreviousAssets.Count -ne 1) {
    throw 'The update feed does not retain exactly one published 0.1.3 full package.'
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
    throw 'The updated feed changed the published 0.1.3 full-package identity.'
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
Assert-NoTextMarker -Path $candidateInstaller -Markers $privateMarkers
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
        previousPublicMainCommit = $previousPublicMainCommit
        currentTag = $sourceTag
        currentCommit = $sourceCommit
        reachableCommitCount = [int]$sourceCommitCount
    }
    cleanProfile = [ordered]@{
        stateDirectory = '%APPDATA%\Black Spirit Life'
        autoImportsFormerProfiles = $false
        initialMasteries = 0
        initialInventoryEntries = 0
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
