[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ReleasePlanPath,
    [Parameter(Mandatory = $true)][string]$ApprovedReleasePlanSha256,
    [Parameter(Mandatory = $true)][string]$CandidateManifestPath,
    [Parameter(Mandatory = $true)][string]$ApprovedCandidateManifestSha256,
    [Parameter(Mandatory = $true)][string]$PreviousSetupPath,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$EvidenceRoot,
    [Parameter(Mandatory = $true)][string]$DisposableBase,
    [Parameter(Mandatory = $true)][string]$PythonPath,
    [Parameter(Mandatory = $true)][string]$FlutterPath,
    [Parameter(Mandatory = $true)][string]$EdgePath,
    [ValidateSet('LocalFeed', 'PublicRoute')][string]$Mode = 'LocalFeed',
    [string]$LocalFeedReceiptPath,
    [string]$ApprovedLocalFeedReceiptSha256,
    [switch]$PreflightOnly,
    [switch]$ConfirmDisposableLifecycle
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'verified_input_cache.ps1')
. (Join-Path $PSScriptRoot 'release_plan.ps1')

function Get-LifecycleFileSha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Read-LifecycleJsonFile([string]$Path, [string]$ExpectedSha256, [string]$Context) {
    $expected = $ExpectedSha256.ToUpperInvariant()
    Assert-ReleasePlanSha256 $expected "$Context SHA-256"
    $ordinary = Assert-ReleaseOrdinaryPath -Path $Path
    $item = Get-Item -LiteralPath $ordinary -Force -ErrorAction Stop
    if ($item.PSIsContainer -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Context must be one ordinary file."
    }
    $bytes = [IO.File]::ReadAllBytes($item.FullName)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $actual = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
    if ($actual -cne $expected) {
        throw "$Context SHA-256 does not match its reviewed value."
    }
    try {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        return $text | ConvertFrom-Json
    }
    catch { throw "$Context is not valid JSON: $($_.Exception.Message)" }
}

function Resolve-LifecycleArtifact($Record, [string]$Root, [string]$Context) {
    $role = Get-ReleasePlanStringProperty $Record 'role' $Context
    $relative = Get-ReleasePlanStringProperty $Record 'path' $Context
    Assert-ReleasePlanRelativePath $relative "$Context path"
    $rootPrefix = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $full = [IO.Path]::GetFullPath((Join-Path $Root $relative))
    if (-not $full.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Context escaped the candidate run."
    }
    $ordinary = Assert-ReleaseOrdinaryPath -Path $full
    $item = Get-Item -LiteralPath $ordinary -Force -ErrorAction Stop
    $rawBytes = Get-ReleasePlanProperty $Record 'bytes' $Context
    if (-not (Test-ReleasePlanJsonInteger $rawBytes) -or
        [uint64]$rawBytes -eq 0 -or
        [uint64]$rawBytes -gt [long]::MaxValue) {
        throw "$Context bytes must be a positive JSON integer."
    }
    $expectedBytes = [long]$rawBytes
    $expectedHash = (Get-ReleasePlanStringProperty $Record 'sha256' $Context).ToUpperInvariant()
    Assert-ReleasePlanSha256 $expectedHash "$Context SHA-256"
    if ($item.PSIsContainer -or $item.Length -ne $expectedBytes -or
        (Get-LifecycleFileSha256 $item.FullName) -cne $expectedHash) {
        throw "$Context does not match its candidate-manifest identity."
    }
    return [pscustomobject]@{
        Role = $role
        Path = $item.FullName
        Bytes = $expectedBytes
        Sha256 = $expectedHash
    }
}

function Read-LifecycleCandidate([string]$Path, [string]$ExpectedSha256, $Plan) {
    $manifest = Read-LifecycleJsonFile $Path $ExpectedSha256 'Candidate manifest'
    if (-not (Test-ReleasePlanJsonInteger $manifest.schemaVersion) -or
        [int64]$manifest.schemaVersion -ne 2 -or
        $manifest.publicCandidate -isnot [bool] -or $manifest.publicCandidate -ne $true -or
        $manifest.localOnly -isnot [bool] -or $manifest.localOnly -ne $false) {
        throw 'Candidate manifest is not a schema-2 public candidate.'
    }
    if ((Get-ReleasePlanStringProperty $manifest 'version' 'Candidate manifest') -cne $Plan.Version -or
        -not (Test-ReleasePlanJsonInteger $manifest.buildNumber) -or
        [int64]$manifest.buildNumber -ne $Plan.BuildNumber -or
        (Get-ReleasePlanStringProperty $manifest 'sourceCommit' 'Candidate manifest') -cne $Plan.ExpectedCommit -or
        (Get-ReleasePlanStringProperty $manifest 'sourceTag' 'Candidate manifest') -cne $Plan.ExpectedTag -or
        (Get-ReleasePlanStringProperty $manifest 'packageId' 'Candidate manifest') -cne $Plan.PackageId -or
        (Get-ReleasePlanStringProperty $manifest 'channel' 'Candidate manifest') -cne $Plan.Channel -or
        (Get-ReleasePlanStringProperty $manifest 'updateSource' 'Candidate manifest') -cne $Plan.Repository) {
        throw 'Candidate manifest does not match the approved release identity.'
    }
    if ($null -eq $manifest.releasePlan -or
        (Get-ReleasePlanStringProperty $manifest.releasePlan 'sha256' 'Candidate release-plan binding') -cne $Plan.Sha256 -or
        -not (Test-ReleasePlanJsonInteger $manifest.releasePlan.schemaVersion) -or
        [int64]$manifest.releasePlan.schemaVersion -ne 1) {
        throw 'Candidate manifest is not bound to the approved release plan.'
    }
    $manifestItem = Get-Item -LiteralPath (Assert-ReleaseOrdinaryPath -Path $Path)
    $root = $manifestItem.Directory.FullName
    $frozenPlanRelative = Get-ReleasePlanStringProperty $manifest.releasePlan 'path' 'Candidate release-plan binding'
    Assert-ReleasePlanRelativePath $frozenPlanRelative 'Frozen release-plan path'
    $rootPrefix = [IO.Path]::GetFullPath($root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $frozenPlan = [IO.Path]::GetFullPath((Join-Path $root $frozenPlanRelative))
    if (-not $frozenPlan.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Frozen release-plan path escaped the candidate run.'
    }
    $null = Read-LifecycleJsonFile $frozenPlan $Plan.Sha256 'Frozen release plan'

    $artifacts = @{}
    foreach ($record in @($manifest.artifacts)) {
        $resolved = Resolve-LifecycleArtifact $record $root "Candidate artifact $($record.role)"
        if ($artifacts.ContainsKey($resolved.Role)) { throw "Duplicate candidate artifact role $($resolved.Role)." }
        $artifacts[$resolved.Role] = $resolved
    }
    foreach ($requiredRole in @('velopack-setup', 'full-package', 'delta-package', 'update-feed')) {
        if (-not $artifacts.ContainsKey($requiredRole)) { throw "Candidate manifest is missing $requiredRole." }
    }
    $publishedInputs = @{}
    foreach ($record in @($manifest.delta.publishedInputs)) {
        $resolved = Resolve-LifecycleArtifact $record $root "Published input $($record.role)"
        if ($publishedInputs.ContainsKey($resolved.Role)) { throw "Duplicate published input role $($resolved.Role)." }
        $publishedInputs[$resolved.Role] = $resolved
    }
    if (-not $publishedInputs.ContainsKey('published-previous-full-package')) {
        throw 'Candidate manifest is missing its pinned previous full package.'
    }
    if ($publishedInputs['published-previous-full-package'].Bytes -ne $Plan.PreviousFullPackageBytes -or
        $publishedInputs['published-previous-full-package'].Sha256 -cne $Plan.PreviousFullPackageSha256) {
        throw 'Candidate manifest previous package does not match the approved release plan.'
    }
    return [pscustomobject]@{
        Manifest = $manifest
        Path = $manifestItem.FullName
        Sha256 = $ExpectedSha256.ToUpperInvariant()
        Root = $root
        Artifacts = $artifacts
        PublishedInputs = $publishedInputs
    }
}

function Assert-SyntheticPlannerFixture([string]$Path, [string]$MigrationSourceVersion) {
    $ordinary = Assert-ReleaseOrdinaryPath -Path $Path
    $fixtureText = Get-Content -LiteralPath $ordinary -Raw
    if ($fixtureText -match '(?i)(?:[A-Z]:[\\/](?:Users|Codex)[\\/]|cookie|credential|browser.profile|session-import)') {
        throw 'Synthetic Planner fixture contains a private-path or credential/profile marker.'
    }
    $fixture = $fixtureText | ConvertFrom-Json
    if ([int64]$fixture.schemaVersion -ne 1 -or
        [string]$fixture.applicationVersion -cne $MigrationSourceVersion -or
        [int]$fixture.alchemy.alchemyMastery -ne 1234 -or
        [int]$fixture.cooking.cookingMastery -ne 1567 -or
        [int]$fixture.processing.processingMastery -ne 1789 -or
        [bool]$fixture.marketTax.merchantRing -ne $true -or
        [string]$fixture.extensions.syntheticFairyProfile -cne 'Radiant Fairy - Morning Star V' -or
        @($fixture.alchemy.customIcons.PSObject.Properties).Count -ne 0 -or
        @($fixture.alchemy.market.prices.PSObject.Properties).Count -ne 0) {
        throw 'Synthetic Planner fixture does not match its explicit non-personal fixture contract.'
    }
    return $ordinary
}

function Get-LifecycleContext([hashtable]$RolePaths) {
    $records = @()
    foreach ($role in @($RolePaths.Keys | Sort-Object)) {
        $path = Assert-ReleaseOrdinaryPath -Path ([string]$RolePaths[$role])
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if ($item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Lifecycle context input $role is not one ordinary file."
        }
        $records += [ordered]@{
            role = $role
            bytes = $item.Length
            sha256 = Get-LifecycleFileSha256 $item.FullName
        }
    }
    $context = [ordered]@{
        schemaVersion = 1
        powershell = $PSVersionTable.PSVersion.ToString()
        os = [Environment]::OSVersion.VersionString
        files = $records
    }
    $json = $context | ConvertTo-Json -Compress -Depth 5
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
    return [pscustomobject]@{ Sha256 = $hash; Evidence = $context }
}

function Test-LifecyclePathOverlap([string]$Left, [string]$Right) {
    $leftFull = [IO.Path]::GetFullPath($Left).TrimEnd('\', '/')
    $rightFull = [IO.Path]::GetFullPath($Right).TrimEnd('\', '/')
    return $leftFull.Equals($rightFull, [StringComparison]::OrdinalIgnoreCase) -or
        $leftFull.StartsWith($rightFull + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $rightFull.StartsWith($leftFull + '\', [StringComparison]::OrdinalIgnoreCase)
}

$ReleasePlan = Read-ReleasePlan $ReleasePlanPath $ApprovedReleasePlanSha256
$Candidate = Read-LifecycleCandidate $CandidateManifestPath $ApprovedCandidateManifestSha256 $ReleasePlan
$Repo = Assert-ReleaseOrdinaryPath -Path $ProjectRoot
if (-not (Test-Path -LiteralPath $Repo -PathType Container)) { throw 'ProjectRoot is unavailable.' }
$Run = $Candidate.Root
$Feed = Split-Path -Parent $Candidate.Artifacts['update-feed'].Path
$PublishedInputs = Split-Path -Parent $Candidate.PublishedInputs['published-previous-full-package'].Path
$PublishedSetup = Assert-ReleaseOrdinaryPath -Path $PreviousSetupPath
$publishedSetupItem = Get-Item -LiteralPath $PublishedSetup -Force -ErrorAction Stop
if ($publishedSetupItem.PSIsContainer -or
    $publishedSetupItem.Name -cne $ReleasePlan.PreviousSetupFileName -or
    $publishedSetupItem.Length -ne $ReleasePlan.PreviousSetupBytes -or
    (Get-LifecycleFileSha256 $PublishedSetup) -cne $ReleasePlan.PreviousSetupSha256) {
    throw 'Previous published Setup does not match the approved lifecycle input.'
}
$CandidateSetup = $Candidate.Artifacts['velopack-setup'].Path
$CandidateFull = $Candidate.Artifacts['full-package'].Path
$CandidateDelta = $Candidate.Artifacts['delta-package'].Path
$UpdateSource = if ($Mode -ceq 'PublicRoute') { $ReleasePlan.Repository } else { $Feed }
$Evidence = Assert-ReleaseOrdinaryPath -Path $EvidenceRoot
$DisposableBase = Assert-ReleaseOrdinaryPath -Path $DisposableBase
if ([IO.Path]::GetFileName($DisposableBase) -cnotmatch '^bsl-lifecycle-[A-Za-z0-9-]+$') {
    throw 'DisposableBase must use a dedicated bsl-lifecycle-* leaf directory.'
}
if ($Evidence.Equals($DisposableBase, [StringComparison]::OrdinalIgnoreCase) -or
    $Evidence.StartsWith($DisposableBase.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
    $DisposableBase.StartsWith($Evidence.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'EvidenceRoot and DisposableBase must be separate non-nested paths.'
}
$Python = Assert-ReleaseOrdinaryPath -Path $PythonPath
$Flutter = Assert-ReleaseOrdinaryPath -Path $FlutterPath
$Edge = Assert-ReleaseOrdinaryPath -Path $EdgePath
$LifecycleRoot = Join-Path $PSScriptRoot 'lifecycle'
$PersonalVerifier = Join-Path $LifecycleRoot 'verify_personal.py'
$FreshVerifier = Join-Path $LifecycleRoot 'verify_fresh.py'
$PackageComparator = Join-Path $LifecycleRoot 'compare_nupkg.py'
$PriorSyntheticPlanner = Assert-SyntheticPlannerFixture `
    (Join-Path $LifecycleRoot 'fixtures\planner-state.v1.json') `
    $ReleasePlan.MigrationSourceVersion
$HarnessSha256 = Get-LifecycleFileSha256 $MyInvocation.MyCommand.Path
$FixtureSha256 = Get-LifecycleFileSha256 $PriorSyntheticPlanner
$GatherPackage = Join-Path $Repo 'packages\bdo_gathering_companion'
$GatherMigrationGate = Join-Path $LifecycleRoot 'gathering_lazy_migration_gate_test.dart'
foreach ($requiredPath in @(
    $Python, $Flutter, $Edge, $PersonalVerifier, $FreshVerifier,
    $PackageComparator, $GatherMigrationGate
)) { $null = Get-Item -LiteralPath (Assert-ReleaseOrdinaryPath -Path $requiredPath) -Force -ErrorAction Stop }
if (-not (Test-Path -LiteralPath $GatherPackage -PathType Container)) { throw 'Gathering package is unavailable.' }
$LifecycleContext = Get-LifecycleContext @{
    'release-plan-loader' = (Join-Path $PSScriptRoot 'release_plan.ps1')
    'lifecycle-harness' = $MyInvocation.MyCommand.Path
    'personal-verifier' = $PersonalVerifier
    'fresh-verifier' = $FreshVerifier
    'package-comparator' = $PackageComparator
    'gathering-gate' = $GatherMigrationGate
    'synthetic-planner' = $PriorSyntheticPlanner
    'python-runtime' = $Python
    'flutter-launcher' = $Flutter
    'edge-runtime' = $Edge
    'gathering-migration-source' = (Join-Path $GatherPackage 'lib\src\services\stable_v017_migration.dart')
    'gathering-session-store' = (Join-Path $GatherPackage 'lib\src\services\session_store.dart')
    'gathering-package-lock' = (Join-Path $GatherPackage 'pubspec.lock')
}
if ($Candidate.Artifacts['delta-package'].Bytes -ge $Candidate.Artifacts['full-package'].Bytes) {
    throw 'Candidate delta is not smaller than its full package.'
}

if ((Test-Path -LiteralPath $Evidence) -or (Test-Path -LiteralPath $DisposableBase)) {
    throw 'EvidenceRoot and DisposableBase must be new paths for a lifecycle run.'
}
$protectedRoots = [System.Collections.Generic.List[string]]::new()
foreach ($protectedRoot in @($Repo, $Run, $PSScriptRoot, $LifecycleRoot)) {
    $protectedRoots.Add([IO.Path]::GetFullPath($protectedRoot))
}
foreach ($personalRoot in @(
    $(if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) { Join-Path $env:APPDATA 'Black Spirit Life' }),
    $(if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { Join-Path $env:LOCALAPPDATA 'Black Spirit Life' }),
    'C:\Black Spirit Life'
)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$personalRoot)) {
        $protectedRoots.Add([IO.Path]::GetFullPath([string]$personalRoot))
    }
}
foreach ($target in @($Evidence, $DisposableBase)) {
    foreach ($protectedRoot in $protectedRoots) {
        if (Test-LifecyclePathOverlap $target $protectedRoot) {
            throw 'Lifecycle output paths must be disjoint from source, candidate, tooling, and personal-data roots.'
        }
    }
}

$LocalFeedReceipt = $null
if ($Mode -ceq 'PublicRoute') {
    if ([string]::IsNullOrWhiteSpace($LocalFeedReceiptPath) -or
        [string]::IsNullOrWhiteSpace($ApprovedLocalFeedReceiptSha256)) {
        throw 'PublicRoute requires an approved passed LocalFeed receipt.'
    }
    $LocalFeedReceipt = Read-LifecycleJsonFile `
        $LocalFeedReceiptPath $ApprovedLocalFeedReceiptSha256 'LocalFeed lifecycle receipt'
    if (-not (Test-ReleasePlanJsonInteger $LocalFeedReceipt.schemaVersion) -or
        [int64]$LocalFeedReceipt.schemaVersion -ne 1 -or
        $LocalFeedReceipt.success -isnot [bool] -or
        $LocalFeedReceipt.success -ne $true -or
        [string]$LocalFeedReceipt.mode -cne 'LocalFeed' -or
        [string]$LocalFeedReceipt.releasePlanSha256 -cne $ReleasePlan.Sha256 -or
        [string]$LocalFeedReceipt.candidateManifestSha256 -cne $Candidate.Sha256 -or
        [string]$LocalFeedReceipt.harnessSha256 -cne $HarnessSha256 -or
        [string]$LocalFeedReceipt.syntheticFixtureSha256 -cne $FixtureSha256 -or
        [string]$LocalFeedReceipt.lifecycleContextSha256 -cne $LifecycleContext.Sha256 -or
        @($LocalFeedReceipt.restoration.errors).Count -ne 0) {
        throw 'LocalFeed lifecycle receipt is not a passed result for these exact inputs.'
    }
}
elseif (-not [string]::IsNullOrWhiteSpace($LocalFeedReceiptPath) -or
    -not [string]::IsNullOrWhiteSpace($ApprovedLocalFeedReceiptSha256)) {
    throw 'LocalFeed mode does not accept a prior lifecycle receipt.'
}

if ($PreflightOnly.IsPresent) {
    [pscustomobject]@{
        schemaVersion = 1
        status = 'preflight-passed'
        mode = $Mode
        releasePlanSha256 = $ReleasePlan.Sha256
        candidateManifestSha256 = $Candidate.Sha256
        harnessSha256 = $HarnessSha256
        syntheticFixtureSha256 = $FixtureSha256
        lifecycleContextSha256 = $LifecycleContext.Sha256
        version = $ReleasePlan.Version
        previousVersion = $ReleasePlan.PreviousVersion
        localReceiptReused = $null -ne $LocalFeedReceipt
        installExecuted = $false
    } | ConvertTo-Json -Depth 4
    return
}
if (-not $ConfirmDisposableLifecycle.IsPresent) {
    throw 'Supply -ConfirmDisposableLifecycle to permit the isolated install/update/uninstall rehearsal.'
}
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'The full lifecycle rehearsal requires PowerShell 7 or newer; PreflightOnly remains compatible with Windows PowerShell 5.1.'
}
$repoHead = (& git -C $Repo rev-parse HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]$repoHead -cne $ReleasePlan.ExpectedCommit) {
    throw 'ProjectRoot is not checked out at the release-plan source commit.'
}
$repoChanges = @(& git -C $Repo status --porcelain=v1 --untracked-files=all 2>$null)
if ($LASTEXITCODE -ne 0 -or $repoChanges.Count -ne 0) {
    throw 'ProjectRoot must be a clean release-plan source checkout for a full lifecycle rehearsal.'
}

$UpgradeInstall = Join-Path $DisposableBase ("upgrade-install\$($ReleasePlan.PackageId)")
$FreshInstall = Join-Path $DisposableBase ("fresh-install\$($ReleasePlan.PackageId)")
$UpgradeRoaming = Join-Path $DisposableBase 'upgrade-env\Roaming'
$UpgradeLocal = Join-Path $DisposableBase 'upgrade-env\Local'
$UpgradeTemp = Join-Path $DisposableBase 'upgrade-env\Temp'
$FreshRoaming = Join-Path $DisposableBase 'fresh-env\Roaming'
$FreshLocal = Join-Path $DisposableBase 'fresh-env\Local'
$FreshTemp = Join-Path $DisposableBase 'fresh-env\Temp'
$StressRoaming = Join-Path $DisposableBase 'stress-env\Roaming'
$StressLocal = Join-Path $DisposableBase 'stress-env\Local'
$StressTemp = Join-Path $DisposableBase 'stress-env\Temp'
$SelectedRoot = Join-Path $DisposableBase 'upgrade-personal-selected'
$FreshPersonalRoot = Join-Path $FreshRoaming 'Black Spirit Life'
$StressPersonalRoot = Join-Path $DisposableBase 'stress-personal-selected'
$CompositePersonalRoot = Join-Path $DisposableBase 'composite-personal-copy'
$EdgeUserData = Join-Path $DisposableBase 'edge-profile'
$OsBackup = Join-Path $Evidence 'os-backup'
$TranscriptPath = Join-Path $Evidence 'lifecycle-transcript.log'
$SummaryPath = Join-Path $Evidence 'lifecycle-summary.json'
$UninstallRegistryPs = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($ReleasePlan.PackageId)"
$UninstallRegistryNative = "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($ReleasePlan.PackageId)"
$StartMenuShortcut = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\Black Spirit Life.lnk'
$Results = [ordered]@{
    schemaVersion = 1
    startedAtUtc = [DateTime]::UtcNow.ToString('o')
    candidateRun = $Run
    mode = $Mode
    releasePlanSha256 = $ReleasePlan.Sha256
    candidateManifestSha256 = $Candidate.Sha256
    harnessSha256 = $HarnessSha256
    syntheticFixtureSha256 = $FixtureSha256
    lifecycleContextSha256 = $LifecycleContext.Sha256
    lifecycleContext = $LifecycleContext.Evidence
    localFeedReceiptSha256 = if ($null -eq $LocalFeedReceipt) { $null } else { $ApprovedLocalFeedReceiptSha256.ToUpperInvariant() }
    success = $false
    steps = [System.Collections.Generic.List[string]]::new()
}
$Fatal = $null
$RestorationErrors = [System.Collections.Generic.List[string]]::new()
$TranscriptStarted = $false

function Write-Step([string]$Message) {
    $line = '{0} {1}' -f [DateTime]::UtcNow.ToString('o'), $Message
    $Results.steps.Add($line)
    Write-Host $line
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Get-Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-JsonNoBom([string]$Path, [object]$Value) {
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $json = $Value | ConvertTo-Json -Depth 100 -Compress
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Wait-Until([scriptblock]$Condition, [int]$TimeoutSeconds, [string]$Description) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        try { if (& $Condition) { return } } catch { }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timed out waiting for $Description."
}

function Set-TestEnvironment([string]$Roaming, [string]$Local, [string]$Temporary) {
    foreach ($directory in @($Roaming, $Local, $Temporary)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $env:APPDATA = $Roaming
    $env:LOCALAPPDATA = $Local
    $env:TEMP = $Temporary
    $env:TMP = $Temporary
}

function Get-InstalledVersion([string]$InstallRoot) {
    $manifest = Join-Path $InstallRoot 'current\sq.version'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { return $null }
    [xml]$xml = Get-Content -LiteralPath $manifest -Raw
    [string]$xml.package.metadata.version
}

function Invoke-Setup([string]$SetupPath, [string]$InstallRoot, [string]$LogPath) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $InstallRoot) -Force | Out-Null
    $arguments = "--silent --log `"$LogPath`" --installto `"$InstallRoot`""
    $process = Start-Process -FilePath $SetupPath -ArgumentList $arguments -PassThru -Wait -WindowStyle Hidden
    Assert-True ($process.ExitCode -eq 0) "Setup failed with exit code $($process.ExitCode): $LogPath"
}

function New-UpdaterRequest(
    [string]$Path,
    [uint32]$Operation,
    [uint32]$PlannerPid,
    [string]$Source,
    [string]$CurrentVersion,
    [string]$TargetVersion
) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $writer = [IO.BinaryWriter]::new($stream, [Text.UTF8Encoding]::new($false), $true)
        try {
            $writer.Write([Text.Encoding]::ASCII.GetBytes("BSLUPD1`0"))
            $writer.Write([uint32]1)
            $writer.Write($Operation)
            $writer.Write($PlannerPid)
            foreach ($text in @(
                $Source, $ReleasePlan.PackageId, $ReleasePlan.Channel,
                $CurrentVersion, $TargetVersion
            )) {
                $bytes = [Text.Encoding]::UTF8.GetBytes($text)
                $writer.Write([uint32]$bytes.Length)
                $writer.Write($bytes)
            }
        } finally {
            $writer.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Invoke-Updater(
    [string]$InstallRoot,
    [uint32]$Operation,
    [uint32]$PlannerPid,
    [string]$CurrentVersion,
    [string]$TargetVersion,
    [string]$Label
) {
    $helper = Join-Path $InstallRoot 'current\BlackSpiritLifeUpdater.exe'
    Assert-True (Test-Path -LiteralPath $helper -PathType Leaf) "Updater helper is missing for $Label."
    $requestDirectory = Join-Path $env:TEMP 'requests'
    New-Item -ItemType Directory -Path $requestDirectory -Force | Out-Null
    $request = Join-Path $requestDirectory ("$Label-$([Guid]::NewGuid().ToString('N')).bin")
    New-UpdaterRequest -Path $request -Operation $Operation -PlannerPid $PlannerPid -Source $UpdateSource -CurrentVersion $CurrentVersion -TargetVersion $TargetVersion
    $stdout = Join-Path $Evidence "$Label.stdout.jsonl"
    $stderr = Join-Path $Evidence "$Label.stderr.log"
    if (Test-Path -LiteralPath $stdout) { Remove-Item -LiteralPath $stdout -Force }
    if (Test-Path -LiteralPath $stderr) { Remove-Item -LiteralPath $stderr -Force }
    $arguments = "--request `"$request`""
    # Start-Process -Wait follows the whole descendant tree on Windows. Apply
    # deliberately restarts the app, so wait on the helper process itself.
    $process = Start-Process -FilePath $helper -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $process.WaitForExit()
    Assert-True ($process.ExitCode -eq 0) "Updater helper exited $($process.ExitCode) for $Label."
    $snapshots = @(
        Get-Content -LiteralPath $stdout |
            Where-Object { $_.TrimStart().StartsWith('{') } |
            ForEach-Object { $_ | ConvertFrom-Json -Depth 40 }
    )
    Assert-True ($snapshots.Count -gt 0) "Updater helper emitted no protocol snapshot for $Label."
    $last = $snapshots[-1]
    Write-Step ("UPDATER {0} status={1} current={2} target={3} deltaCount={4} download={5} full={6}" -f $Label,$last.status,$last.currentVersion,$last.targetVersion,$last.deltaCount,$last.downloadSizeBytes,$last.fullSizeBytes)
    $last
}

function Get-TestProcessRecords([string]$InstallRoot) {
    $prefix = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\') + '\'
    @(
        Get-CimInstance Win32_Process |
            Where-Object {
                $_.ExecutablePath -and
                ([IO.Path]::GetFullPath([string]$_.ExecutablePath).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))
            }
    )
}

function Get-TestFishListener([string]$InstallRoot) {
    $records = @(Get-TestProcessRecords $InstallRoot | Where-Object Name -eq 'fish_companion_service.exe')
    foreach ($record in $records) {
        $listeners = @(Get-NetTCPConnection -OwningProcess $record.ProcessId -State Listen -ErrorAction SilentlyContinue)
        foreach ($listener in $listeners) {
            if ($listener.LocalAddress -eq '127.0.0.1') {
                if ($record.CommandLine -notmatch '--api-token') { continue }
                return [pscustomobject]@{
                    ListenerPid = [int]$record.ProcessId
                    Port = [int]$listener.LocalPort
                    CommandLine = [string]$record.CommandLine
                }
            }
        }
    }
    $null
}

function Invoke-TestFishHealth([pscustomobject]$Service) {
    $match = [regex]::Match($Service.CommandLine, '--api-token\s+(?:"([A-Za-z0-9_-]+)"|([A-Za-z0-9_-]+))')
    Assert-True ($match.Success) 'Disposable Fish service command line has no API token.'
    $token = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
    Invoke-WebRequest -Uri "http://127.0.0.1:$($Service.Port)/api/health" -Headers @{ 'X-BSL-API-Token' = $token } -UseBasicParsing -TimeoutSec 5
}

function Get-TestFishToken([pscustomobject]$Service) {
    $match = [regex]::Match($Service.CommandLine, '--api-token\s+(?:"([A-Za-z0-9_-]+)"|([A-Za-z0-9_-]+))')
    Assert-True ($match.Success) 'Disposable Fish service command line has no API token.'
    if ($match.Groups[1].Success) { return $match.Groups[1].Value }
    $match.Groups[2].Value
}

function Get-TestEdgeRecords {
    @(
        Get-CimInstance Win32_Process |
            Where-Object {
                $_.Name -ieq 'msedge.exe' -and $_.CommandLine -and
                ([string]$_.CommandLine).Contains([IO.Path]::GetFullPath($EdgeUserData), [StringComparison]::OrdinalIgnoreCase)
            }
    )
}

function Stop-TestEdge {
    foreach ($record in @(Get-TestEdgeRecords)) {
        Assert-True (([string]$record.CommandLine).Contains([IO.Path]::GetFullPath($EdgeUserData), [StringComparison]::OrdinalIgnoreCase)) 'Refused to stop an Edge process outside the disposable profile.'
        Stop-Process -Id $record.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Wait-Until { @(Get-TestEdgeRecords).Count -eq 0 } 30 'disposable headless Edge processes to stop'
}

function Get-TestWebViewRecords {
    $needle = [IO.Path]::GetFullPath($DisposableBase)
    @(
        Get-CimInstance Win32_Process |
            Where-Object {
                $_.Name -ieq 'msedgewebview2.exe' -and $_.CommandLine -and
                ([string]$_.CommandLine).Contains($needle, [StringComparison]::OrdinalIgnoreCase)
            }
    )
}

function Stop-TestWebViews {
    $needle = [IO.Path]::GetFullPath($DisposableBase)
    foreach ($record in @(Get-TestWebViewRecords)) {
        Assert-True (([string]$record.CommandLine).Contains($needle, [StringComparison]::OrdinalIgnoreCase)) 'Refused to stop a WebView process outside the disposable profile.'
        Stop-Process -Id $record.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Wait-Until { @(Get-TestWebViewRecords).Count -eq 0 } 30 'disposable WebView2 processes to stop'
}

function Invoke-FishRender([pscustomobject]$Service, [string]$Path) {
    Assert-True (Test-Path -LiteralPath $Edge -PathType Leaf) 'Microsoft Edge is unavailable for the installed Fish render gate.'
    New-Item -ItemType Directory -Path $EdgeUserData -Force | Out-Null
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
    $token = Get-TestFishToken $Service
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Edge
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    foreach ($argument in @(
        '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run', '--disable-default-apps',
        "--user-data-dir=$EdgeUserData", '--window-size=1575,985', '--virtual-time-budget=12000',
        "--screenshot=$Path", "http://127.0.0.1:$($Service.Port)/#apiToken=$token"
    )) { [void]$start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    Assert-True $process.WaitForExit(45000) 'Headless Edge timed out while rendering the installed Fish Map.'
    Assert-True ($process.ExitCode -eq 0) "Headless Edge exited $($process.ExitCode) while rendering Fish Map."
    Wait-Until { Test-Path -LiteralPath $Path -PathType Leaf } 10 'Fish Map screenshot'
    Assert-True ((Get-Item -LiteralPath $Path).Length -gt 100000) 'Installed Fish Map screenshot is unexpectedly small.'
    Stop-TestEdge
}

function Get-TestCrashEvents([datetime]$StartTime) {
    @(
        Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $StartTime } -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ProviderName -in @('Application Error', 'Windows Error Reporting', 'Application Hang') -and
                ($_.Message -match 'BlackSpiritLife\.exe' -or
                 $_.Message -match 'fish_companion_service\.exe' -or
                 $_.Message -match 'msedgewebview2\.exe' -or
                 $_.Message -match 'webview_windows' -or
                 $_.Message -match [regex]::Escape($UpgradeInstall) -or
                 $_.Message -match [regex]::Escape($FreshInstall))
            }
    )
}

function Stop-TestProcesses([string]$InstallRoot) {
    $records = @(Get-TestProcessRecords $InstallRoot)
    foreach ($record in $records) {
        if ($record.Name -ieq 'BlackSpiritLife.exe') {
            try {
                $process = Get-Process -Id $record.ProcessId -ErrorAction Stop
                [void]$process.CloseMainWindow()
            } catch { }
        }
    }
    if ($records.Count -gt 0) { Start-Sleep -Seconds 4 }
    foreach ($record in @(Get-TestProcessRecords $InstallRoot)) {
        $resolved = [IO.Path]::GetFullPath([string]$record.ExecutablePath)
        $prefix = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\') + '\'
        Assert-True ($resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) "Refused to stop an out-of-scope process: $resolved"
        Stop-Process -Id $record.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Wait-Until { @(Get-TestProcessRecords $InstallRoot).Count -eq 0 } 30 "disposable processes below $InstallRoot to stop"
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LifecycleNativeClose {
  [DllImport("user32.dll", SetLastError = true)] public static extern bool PostMessage(IntPtr hWnd, uint msg, UIntPtr wParam, IntPtr lParam);
}
'@

function Invoke-NativeClose([System.Diagnostics.Process]$Process, [int]$TimeoutSeconds = 45) {
    $Process.Refresh()
    Assert-True (-not $Process.HasExited -and $Process.MainWindowHandle -ne 0) 'Disposable app has no closable window.'
    Assert-True ([LifecycleNativeClose]::PostMessage($Process.MainWindowHandle, 0x0010, [UIntPtr]::Zero, [IntPtr]::Zero)) 'WM_CLOSE could not be posted to the disposable app.'
    Assert-True $Process.WaitForExit($TimeoutSeconds * 1000) 'Disposable app did not exit after WM_CLOSE.'
    $exitCode = $Process.ExitCode
    if ($null -ne $exitCode) {
        Assert-True ($exitCode -eq 0) "Disposable app exited $exitCode after WM_CLOSE."
    }
}

function Start-DisposableApp([string]$InstallRoot) {
    $executable = Join-Path $InstallRoot 'current\BlackSpiritLife.exe'
    Assert-True (Test-Path -LiteralPath $executable -PathType Leaf) "Disposable app executable is missing."
    Start-Process -FilePath $executable -PassThru
}

function Invoke-Uninstall([string]$InstallRoot, [string]$Label) {
    Stop-TestProcesses $InstallRoot
    $updater = Join-Path $InstallRoot 'Update.exe'
    Assert-True (Test-Path -LiteralPath $updater -PathType Leaf) "Uninstall engine is missing for $Label."
    $process = Start-Process -FilePath $updater -ArgumentList '--uninstall --silent' -PassThru -Wait -WindowStyle Hidden
    Assert-True ($process.ExitCode -eq 0) "Uninstall failed with exit code $($process.ExitCode) for $Label."
    Wait-Until { -not (Test-Path -LiteralPath (Join-Path $InstallRoot 'current')) } 120 "$Label installation to be removed"
    Write-Step "UNINSTALL_COMPLETE label=$Label"
}

$OriginalEnvironment = @{
    APPDATA = $env:APPDATA
    LOCALAPPDATA = $env:LOCALAPPDATA
    TEMP = $env:TEMP
    TMP = $env:TMP
}
$RegistryExisted = $false
$RegistryQueryBefore = @()
$ShortcutExisted = $false
$ShortcutHashBefore = $null
$OldInstallLocation = $null
$OldInstallMoved = $false
$OldInstallBackup = Join-Path $OsBackup 'preexisting-install'
$ApplicationEventStart = [DateTime]::Now
$OsStateCaptured = $false
$BaselineFishListeners = @(
    Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -ge 8765 -and $_.LocalPort -le 8795 } |
        ForEach-Object { "$($_.LocalAddress):$($_.LocalPort):$($_.OwningProcess)" }
)

try {
    New-Item -ItemType Directory -Path $OsBackup -Force | Out-Null
    Start-Transcript -LiteralPath $TranscriptPath -Force | Out-Null
    $TranscriptStarted = $true

    Assert-True (Test-Path -LiteralPath $Run -PathType Container) 'Candidate run is missing.'
    Assert-True ((Get-LifecycleFileSha256 $PublishedSetup) -ceq $ReleasePlan.PreviousSetupSha256) 'Previous Setup changed after preflight.'
    Assert-True ((Get-LifecycleFileSha256 $CandidateSetup) -ceq $Candidate.Artifacts['velopack-setup'].Sha256) 'Candidate Setup changed after preflight.'
    Assert-True ((Get-LifecycleFileSha256 $CandidateFull) -ceq $Candidate.Artifacts['full-package'].Sha256) 'Candidate full package changed after preflight.'
    Assert-True ((Get-LifecycleFileSha256 $CandidateDelta) -ceq $Candidate.Artifacts['delta-package'].Sha256) 'Candidate delta package changed after preflight.'
    Assert-True ((Get-LifecycleFileSha256 $Candidate.PublishedInputs['published-previous-full-package'].Path) -ceq $ReleasePlan.PreviousFullPackageSha256) 'Previous full package changed after preflight.'
    Assert-True (Test-Path -LiteralPath $Python -PathType Leaf) 'Isolated verification Python is unavailable.'
    Assert-True (Test-Path -LiteralPath $FreshVerifier -PathType Leaf) 'Fresh-profile verifier is unavailable.'
    Assert-True (Test-Path -LiteralPath $PackageComparator -PathType Leaf) 'Logical package comparator is unavailable.'
    Assert-True (Test-Path -LiteralPath $PriorSyntheticPlanner -PathType Leaf) 'Synthetic Planner fixture is unavailable.'
    Assert-True (Test-Path -LiteralPath $Edge -PathType Leaf) 'Microsoft Edge is unavailable.'
    Assert-True (Test-Path -LiteralPath $Flutter -PathType Leaf) 'Flutter runtime is unavailable.'
    Assert-True (Test-Path -LiteralPath $GatherMigrationGate -PathType Leaf) 'Gathering composite migration gate is unavailable.'
    Assert-True (Test-Path -LiteralPath $GatherPackage -PathType Container) 'Gathering package is unavailable.'
    Assert-True (-not (Test-Path -LiteralPath $DisposableBase)) 'Disposable short-path base unexpectedly already exists.'
    Write-Step "INPUT_HASHES_VERIFIED plan=$($ReleasePlan.Sha256) manifest=$($Candidate.Sha256)"

    $RegistryExisted = Test-Path -LiteralPath $UninstallRegistryPs
    if ($RegistryExisted) {
        $RegistryQueryBefore = @(& reg.exe query $UninstallRegistryNative /s)
        Assert-True ($LASTEXITCODE -eq 0) 'Could not snapshot the existing uninstall registry key.'
        & reg.exe export $UninstallRegistryNative (Join-Path $OsBackup 'uninstall-before.reg') /y | Out-Null
        Assert-True ($LASTEXITCODE -eq 0) 'Could not export the existing uninstall registry key.'
        $OldInstallLocation = [string](Get-ItemProperty -LiteralPath $UninstallRegistryPs).InstallLocation
    }
    $ShortcutExisted = Test-Path -LiteralPath $StartMenuShortcut -PathType Leaf
    if ($ShortcutExisted) {
        $ShortcutHashBefore = Get-Sha256 $StartMenuShortcut
        Copy-Item -LiteralPath $StartMenuShortcut -Destination (Join-Path $OsBackup 'Black Spirit Life-before.lnk') -Force
    }
    $OsStateCaptured = $true
    Write-Step "OS_STATE_SNAPSHOTTED registry=$RegistryExisted shortcut=$ShortcutExisted"

    if ($OldInstallLocation -and (Test-Path -LiteralPath $OldInstallLocation -PathType Container)) {
        $resolvedOld = Assert-ReleaseOrdinaryPath -Path $OldInstallLocation
        $allowedOld = [IO.Path]::GetFullPath((Join-Path $Repo 'build\release-lifecycle-test')).TrimEnd('\') + '\'
        if ($resolvedOld.StartsWith($allowedOld, [StringComparison]::OrdinalIgnoreCase)) {
            Assert-True (@(Get-TestProcessRecords $resolvedOld).Count -eq 0) 'The prior disposable install still has a running process.'
            Assert-True (-not (Test-Path -LiteralPath $OldInstallBackup)) 'Preexisting install backup path already exists.'
            Move-Item -LiteralPath $resolvedOld -Destination $OldInstallBackup
            $OldInstallMoved = $true
            Write-Step "PREEXISTING_DISPOSABLE_INSTALL_MOVED from=$resolvedOld"
        } else {
            Assert-True (@(Get-TestProcessRecords $resolvedOld).Count -eq 0) 'The protected real install currently has a running process.'
            Write-Step "PROTECTED_REAL_INSTALL_LEFT_UNCHANGED path=$resolvedOld"
        }
    }
    if (Test-Path -LiteralPath $UninstallRegistryPs) { Remove-Item -LiteralPath $UninstallRegistryPs -Recurse -Force }
    if (Test-Path -LiteralPath $StartMenuShortcut) { Remove-Item -LiteralPath $StartMenuShortcut -Force }

    Set-TestEnvironment $UpgradeRoaming $UpgradeLocal $UpgradeTemp
    Invoke-Setup $PublishedSetup $UpgradeInstall (Join-Path $Evidence "install-v$($ReleasePlan.PreviousVersion).log")
    Assert-True ((Get-InstalledVersion $UpgradeInstall) -eq $ReleasePlan.PreviousVersion) "Exact v$($ReleasePlan.PreviousVersion) did not install."
    Write-Step "INSTALLED_EXACT_V$($ReleasePlan.PreviousVersion)"

    New-Item -ItemType Directory -Path $SelectedRoot -Force | Out-Null
    $marker = [ordered]@{
        schemaVersion = 1
        packageId = $ReleasePlan.PackageId
        releaseChannel = $ReleasePlan.Channel
        profile = $true
        profileId = 'profile-abcdef-0123456789abcdef0123456789abcdef'
        transactionId = 'move-abcdef-fedcba9876543210fedcba9876543210'
    }
    $markerPath = Join-Path $SelectedRoot '.black-spirit-life-profile.json'
    Write-JsonNoBom $markerPath $marker
    $markerCheck = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
    Assert-True ($markerCheck.profile -eq $true) 'Selected-root marker profile flag is invalid.'
    Assert-True ([regex]::IsMatch([string]$markerCheck.profileId, '^[a-z]+-[a-f0-9]+-[a-f0-9]{32}$')) 'Selected-root profile identity is invalid.'
    Assert-True ([regex]::IsMatch([string]$markerCheck.transactionId, '^[a-z]+-[a-f0-9]+-[a-f0-9]{32}$')) 'Selected-root transaction identity is invalid.'
    Write-Step 'PROFILE_MARKER_VALIDATED_BEFORE_LOCATOR'

    $control = Join-Path $UpgradeLocal 'Black Spirit Life\Bootstrap'
    New-Item -ItemType Directory -Path $control -Force | Out-Null
    $locator = [ordered]@{
        schemaVersion = 1
        packageId = $ReleasePlan.PackageId
        releaseChannel = $ReleasePlan.Channel
        applicationDirectory = [IO.Path]::GetFullPath($SelectedRoot)
    }
    Write-JsonNoBom (Join-Path $control 'personal-data-location.committed.json') $locator
    Write-JsonNoBom (Join-Path $control 'personal-data-location.json') $locator
    Write-Step 'LOCATORS_WRITTEN_AFTER_VALID_MARKER'

    Copy-Item -LiteralPath $PriorSyntheticPlanner -Destination (Join-Path $SelectedRoot 'planner-state.json')
    $planner = Get-Content -LiteralPath (Join-Path $SelectedRoot 'planner-state.json') -Raw | ConvertFrom-Json -Depth 100
    $planner.applicationVersion = $ReleasePlan.PreviousVersion
    $planner.lastSuccessfulWriteUtc = [DateTime]::UtcNow.ToString('o')
    $planner.extensions | Add-Member -NotePropertyName blackSpiritLifeSetup -NotePropertyValue ([ordered]@{
        setupCompleted = $true
        setupSchemaVersion = 2
        completedBetaVersions = [ordered]@{}
    }) -Force
    Write-JsonNoBom (Join-Path $SelectedRoot 'planner-state.json') $planner

    $fishDirectory = Join-Path $SelectedRoot 'fishing'
    New-Item -ItemType Directory -Path $fishDirectory -Force | Out-Null
    $fishFixture = [ordered]@{
        version = 1
        loadouts = @([ordered]@{
            id = 'synthetic-fishing-profile-1'; name = 'Synthetic AFK Balenos'; method = 'fishing'; mastery = 2230
            tool = 'Balenos Fishing Rod'; notes = 'Synthetic lifecycle profile'
            createdAtUtc = '2026-09-14T08:00:00.000Z'; updatedAtUtc = '2026-09-14T08:00:00.000Z'
        })
        sessions = @([ordered]@{
            id = 'synthetic-fishing-haul-1'; startedAtUtc = '2026-09-14T08:15:00.000Z'; durationMinutes = 480
            location = 'Velia Beach'; method = 'fishing'; loadoutId = 'synthetic-fishing-profile-1'
            loadoutName = 'Synthetic AFK Balenos'; mastery = 2230; tool = 'Balenos Fishing Rod'
            retainedFishCount = 81; silverReceived = 2240000000; notes = 'Synthetic journal/haul preservation record'
            createdAtUtc = '2026-09-14T16:15:00.000Z'; updatedAtUtc = '2026-09-14T16:15:00.000Z'
        })
    }
    Write-JsonNoBom (Join-Path $fishDirectory 'fishing-journal.json') $fishFixture

    $gatherDirectory = Join-Path $SelectedRoot 'gathering'
    New-Item -ItemType Directory -Path $gatherDirectory -Force | Out-Null
    $gatherFixture = [ordered]@{
        version = 1
        profile = [ordered]@{ mastery = 2111; loadoutNotes = 'Synthetic Manos gathering loadout' }
        sessions = @([ordered]@{
            id = 'synthetic-gathering-session-1'; recordedAtUtc = '2026-09-14T10:30:00.000Z'
            method = 'Butchering'; location = 'Behr'; durationMinutes = 60; mastery = 2111
            notes = 'Synthetic lifecycle preservation record'
        })
    }
    Write-JsonNoBom (Join-Path $gatherDirectory 'gathering-state.json') $gatherFixture
    $sentinel = Join-Path $SelectedRoot 'lifecycle-personal-sentinel.txt'
    [IO.File]::WriteAllText($sentinel, 'synthetic-personal-sentinel-upgrade-9a67c1', [Text.UTF8Encoding]::new($false))
    $upgradeBaseline = [ordered]@{
        plannerSha256 = Get-Sha256 (Join-Path $SelectedRoot 'planner-state.json')
        fishSha256 = Get-Sha256 (Join-Path $fishDirectory 'fishing-journal.json')
        gatherSha256 = Get-Sha256 (Join-Path $gatherDirectory 'gathering-state.json')
        sentinelSha256 = Get-Sha256 $sentinel
    }
    $Results.upgradeBaseline = $upgradeBaseline
    Write-Step "SYNTHETIC_PERSONAL_STATE_SEEDED_ON_V$($ReleasePlan.PreviousVersion) fish=$($upgradeBaseline.fishSha256) gathering=$($upgradeBaseline.gatherSha256)"

    $previousLabel = 'v' + ($ReleasePlan.PreviousVersion -replace '\.', '')
    $targetLabel = 'v' + ($ReleasePlan.Version -replace '\.', '')
    $check = Invoke-Updater $UpgradeInstall 2 0 $ReleasePlan.PreviousVersion '' "$previousLabel-check"
    Assert-True ($check.status -eq 'available') "v$($ReleasePlan.PreviousVersion) helper did not report an available update."
    Assert-True ($check.currentVersion -eq $ReleasePlan.PreviousVersion -and $check.targetVersion -eq $ReleasePlan.Version) 'Updater helper reported the wrong version transition.'
    Assert-True ($check.deltaCount -eq 1) 'Updater helper did not select exactly one delta.'
    Assert-True ([uint64]$check.downloadSizeBytes -eq [uint64]$Candidate.Artifacts['delta-package'].Bytes) 'Updater helper selected an unexpected update payload size.'
    Assert-True ([uint64]$check.fullSizeBytes -eq [uint64]$Candidate.Artifacts['full-package'].Bytes) 'Updater helper reported an unexpected full-package size.'
    Assert-True ([uint64]$check.downloadSizeBytes -lt [uint64]$check.fullSizeBytes) 'Selected delta is not smaller than the full release.'
    $Results.updateCheck = $check

    $download = Invoke-Updater $UpgradeInstall 3 0 $ReleasePlan.PreviousVersion '' "$previousLabel-download"
    Assert-True ($download.status -eq 'ready') 'Updater helper did not finish the delta download.'
    $reconstructed = Join-Path (Join-Path $UpgradeInstall 'packages') ([IO.Path]::GetFileName($CandidateFull))
    Assert-True (Test-Path -LiteralPath $reconstructed -PathType Leaf) 'The delta did not produce a reconstructed full package.'
    $reconstructedHash = Get-Sha256 $reconstructed
    $comparisonPath = Join-Path $Evidence 'reconstructed-content-comparison.json'
    & $Python -I -E -B $PackageComparator $reconstructed $CandidateFull $comparisonPath
    Assert-True ($LASTEXITCODE -eq 0) 'Reconstructed full package payload differs from the sealed candidate payload.'
    $comparison = Get-Content -LiteralPath $comparisonPath -Raw | ConvertFrom-Json
    Assert-True ([bool]$comparison.equivalent) 'Logical package comparator did not report equivalence.'
    Assert-True ($comparison.left.entries -gt 9000) 'Unexpectedly small reconstructed package entry count.'
    Assert-True ($comparison.left.entries -eq $comparison.right.entries) 'Reconstructed and sealed package entry counts differ.'
    Assert-True ($comparison.left.aggregateSha256 -eq $comparison.right.aggregateSha256) 'Reconstructed package logical aggregate differs.'
    $Results.reconstructedFull = [ordered]@{
        bytes = (Get-Item -LiteralPath $reconstructed).Length
        sha256 = $reconstructedHash
        sealedBytes = (Get-Item -LiteralPath $CandidateFull).Length
        sealedSha256 = Get-Sha256 $CandidateFull
        logicalEntries = $comparison.left.entries
        logicalAggregateSha256 = $comparison.left.aggregateSha256
    }
    Write-Step "DELTA_RECONSTRUCTED_CONTENT_MATCH entries=$($comparison.left.entries) aggregate=$($comparison.left.aggregateSha256) reconstructedOuterSha256=$reconstructedHash sealedOuterSha256=$($Results.reconstructedFull.sealedSha256)"

    $oldApp = Start-DisposableApp $UpgradeInstall
    Wait-Until { $oldApp.Refresh(); -not $oldApp.HasExited -and $oldApp.MainWindowHandle -ne 0 } 45 "v$($ReleasePlan.PreviousVersion) disposable window"
    $apply = Invoke-Updater $UpgradeInstall 4 ([uint32]$oldApp.Id) $ReleasePlan.PreviousVersion $ReleasePlan.Version "$previousLabel-apply"
    Assert-True ($apply.status -eq 'applying') 'Updater helper did not begin applying the update.'
    Wait-Until { (Get-InstalledVersion $UpgradeInstall) -eq $ReleasePlan.Version } 240 "installed version $($ReleasePlan.Version)"
    Write-Step "UPDATE_APPLIED_TO_V$($ReleasePlan.Version)"

    Wait-Until { @(Get-TestProcessRecords $UpgradeInstall | Where-Object Name -eq 'BlackSpiritLife.exe').Count -gt 0 } 90 "restarted v$($ReleasePlan.Version) application"
    $newRecord = @(Get-TestProcessRecords $UpgradeInstall | Where-Object Name -eq 'BlackSpiritLife.exe')[0]
    $newApp = Get-Process -Id $newRecord.ProcessId
    Wait-Until { $newApp.Refresh(); -not $newApp.HasExited -and $newApp.MainWindowHandle -ne 0 } 60 "v$($ReleasePlan.Version) main window"
    Wait-Until { Test-Path -LiteralPath (Join-Path $fishDirectory 'fish-journal.sqlite3') -PathType Leaf } 120 "Fishing v$($ReleasePlan.MigrationSourceVersion) migration"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $gatherDirectory 'sessions.json'))) 'Gathering unexpectedly instantiated without visiting its lazy workspace.'
    Assert-True ((Get-Sha256 (Join-Path $gatherDirectory 'gathering-state.json')) -eq $upgradeBaseline.gatherSha256) 'Lazy Gathering source changed before first open.'
    Write-Step 'FISHING_MIGRATION_OBSERVED_GATHERING_CONFIRMED_LAZY_AND_BYTE_EXACT'

    $normalCloseRuns = [System.Collections.Generic.List[object]]::new()
    for ($normalIndex = 1; $normalIndex -le 1; $normalIndex++) {
        if ($normalIndex -gt 1) {
            $newApp = Start-DisposableApp $UpgradeInstall
            Wait-Until { $newApp.Refresh(); -not $newApp.HasExited -and $newApp.MainWindowHandle -ne 0 } 60 "normal Fish close run $normalIndex main window"
        }
        $fishService = $null
        $fishDeadline = [DateTime]::UtcNow.AddSeconds(60)
        do {
            $fishService = Get-TestFishListener $UpgradeInstall
            if ($null -ne $fishService) { break }
            Start-Sleep -Milliseconds 100
        } while ([DateTime]::UtcNow -lt $fishDeadline)
        Assert-True ($null -ne $fishService) "Normal Fish close run $normalIndex exposed no localhost service."
        Assert-True ($fishService.Port -ge 8765 -and $fishService.Port -le 8795) 'The Fish service selected an unexpected port.'
        Assert-True ($fishService.CommandLine.Contains([IO.Path]::GetFullPath($SelectedRoot), [StringComparison]::OrdinalIgnoreCase)) 'Fish service is not using the selected disposable personal root.'
        Assert-True ($fishService.CommandLine.Contains([IO.Path]::GetFullPath($UpgradeLocal), [StringComparison]::OrdinalIgnoreCase)) 'Fish service is not using the disposable local cache root.'
        Wait-Until { @(Get-TestWebViewRecords).Count -gt 0 } 60 "normal Fish close run $normalIndex embedded WebView2 startup"
        $fishWebViewPids = @(Get-TestWebViewRecords | ForEach-Object { [int]$_.ProcessId })
        if ($normalIndex -eq 1) {
            $newApp.Refresh()
            Assert-True (-not $newApp.HasExited -and $newApp.Responding) 'The installed app did not stay responsive while its Fish service and embedded WebView started.'
            $Results.fishTab = [ordered]@{
                listenerPid = $fishService.ListenerPid
                port = $fishService.Port
                embeddedWebViewPids = @($fishWebViewPids)
            }
            Write-Step "FISH_SERVICE_AND_EMBEDDED_WEBVIEW_STARTED pid=$($fishService.ListenerPid) port=$($fishService.Port)"
        }
        Start-Sleep -Seconds 3
        $closeStarted = [DateTime]::UtcNow
        Invoke-NativeClose $newApp 60
        Wait-Until { @(Get-TestProcessRecords $UpgradeInstall).Count -eq 0 } 60 "normal Fish close run $normalIndex process teardown"
        Wait-Until { @(Get-TestWebViewRecords).Count -eq 0 } 60 "normal Fish close run $normalIndex WebView2 teardown"
        $normalCloseRuns.Add([ordered]@{
            run = $normalIndex
            servicePort = $fishService.Port
            servicePid = $fishService.ListenerPid
            closeMilliseconds = [int]([DateTime]::UtcNow - $closeStarted).TotalMilliseconds
            exitCode = $newApp.ExitCode
        })
        Write-Step "NORMAL_FISH_CLOSE_PASS run=$normalIndex port=$($fishService.Port)"
    }
    $Results.normalFishCloseStress = @($normalCloseRuns)

    $postCheck = Invoke-Updater $UpgradeInstall 2 0 $ReleasePlan.Version '' "$targetLabel-check"
    Assert-True ($postCheck.status -eq 'upToDate') 'Updated helper did not report up-to-date.'
    Assert-True ($postCheck.currentVersion -eq $ReleasePlan.Version) 'Updated helper reported the wrong installed version.'
    $Results.postUpdateCheck = $postCheck

    Assert-True ((Get-Sha256 (Join-Path $fishDirectory 'fishing-journal.json')) -eq $upgradeBaseline.fishSha256) "Fishing v$($ReleasePlan.MigrationSourceVersion) source bytes changed."
    Assert-True ((Get-Sha256 (Join-Path $gatherDirectory 'gathering-state.json')) -eq $upgradeBaseline.gatherSha256) "Gathering v$($ReleasePlan.MigrationSourceVersion) source bytes changed."
    Assert-True ((Get-Sha256 $sentinel) -eq $upgradeBaseline.sentinelSha256) 'Upgrade personal sentinel changed.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $gatherDirectory 'sessions.json'))) 'Installed lazy Gathering unexpectedly created current state without opening its workspace.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $SelectedRoot "migration-archive\v$($ReleasePlan.MigrationSourceVersion)\gathering-state.$($upgradeBaseline.gatherSha256).json"))) 'Installed lazy Gathering unexpectedly archived before first open.'

    Assert-True (-not (Test-Path -LiteralPath $CompositePersonalRoot)) 'Composite personal-data copy already exists.'
    Copy-Item -LiteralPath $SelectedRoot -Destination $CompositePersonalRoot -Recurse
    Assert-True ((Get-Sha256 (Join-Path $CompositePersonalRoot 'gathering\gathering-state.json')) -eq $upgradeBaseline.gatherSha256) 'Composite Gathering copy differs before migration.'
    $gatherGateStdout = Join-Path $Evidence 'gathering-lazy-migration.stdout.log'
    $gatherGateStderr = Join-Path $Evidence 'gathering-lazy-migration.stderr.log'
    $gatherGateResultPath = Join-Path $Evidence 'gathering-lazy-migration-result.json'
    $previousGatherRoot = $env:BSL_GATHERING_GATE_ROOT
    $previousGatherResult = $env:BSL_GATHERING_GATE_RESULT
    try {
        $env:BSL_GATHERING_GATE_ROOT = Join-Path $CompositePersonalRoot 'gathering'
        $env:BSL_GATHERING_GATE_RESULT = $gatherGateResultPath
        $gatherArguments = "test `"$GatherMigrationGate`" --reporter expanded"
        $gatherProcess = Start-Process -FilePath $Flutter -ArgumentList $gatherArguments -WorkingDirectory $GatherPackage -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $gatherGateStdout -RedirectStandardError $gatherGateStderr
    } finally {
        $env:BSL_GATHERING_GATE_ROOT = $previousGatherRoot
        $env:BSL_GATHERING_GATE_RESULT = $previousGatherResult
    }
    Assert-True ($gatherProcess.ExitCode -eq 0) "Composite Gathering migration service failed; see $gatherGateStderr"
    Assert-True (Test-Path -LiteralPath $gatherGateResultPath -PathType Leaf) 'Composite Gathering migration result is missing.'
    $gatherGateResult = Get-Content -LiteralPath $gatherGateResultPath -Raw | ConvertFrom-Json
    Assert-True ($gatherGateResult.migrated -eq $true -and $gatherGateResult.sessions -eq 1) 'Composite Gathering first-open result is invalid.'

    $verifyOutput = Join-Path $Evidence 'personal-migration-verification.json'
    $verifyStdout = Join-Path $Evidence 'personal-migration-verification.stdout.log'
    $verifyStderr = Join-Path $Evidence 'personal-migration-verification.stderr.log'
    $verifyArguments = "-I -E `"$PersonalVerifier`" `"$CompositePersonalRoot`" `"$verifyOutput`" --expected-planner-version `"$($ReleasePlan.PreviousVersion)`" --migration-source-version `"$($ReleasePlan.MigrationSourceVersion)`""
    $verifyProcess = Start-Process -FilePath $Python -ArgumentList $verifyArguments -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $verifyStdout -RedirectStandardError $verifyStderr
    Assert-True ($verifyProcess.ExitCode -eq 0) "Composite semantic personal-data verification failed; see $verifyStderr"
    $Results.personalMigration = [ordered]@{
        installed = [ordered]@{
            plannerPreserved = $true
            fishingMigratedAndArchived = $true
            gatheringLazy = $true
            gatheringSourceSha256 = $upgradeBaseline.gatherSha256
            sentinelSha256 = $upgradeBaseline.sentinelSha256
        }
        compositeFirstOpen = Get-Content -LiteralPath $verifyOutput -Raw | ConvertFrom-Json -Depth 100
        migrationServiceSha256 = Get-Sha256 (Join-Path $Repo 'packages\bdo_gathering_companion\lib\src\services\stable_v017_migration.dart')
        gate = $gatherGateResult
    }
    Write-Step 'INSTALLED_FISH_AND_COMPOSITE_LAZY_GATHERING_SEMANTICS_ARCHIVES_VERIFIED'

    Invoke-Uninstall $UpgradeInstall 'upgraded-install'
    Assert-True (Test-Path -LiteralPath $SelectedRoot -PathType Container) 'Uninstall removed the selected personal root.'
    Assert-True ((Get-Sha256 $sentinel) -eq $upgradeBaseline.sentinelSha256) 'Uninstall changed the selected personal sentinel.'
    Write-Step 'UPGRADED_INSTALL_UNINSTALL_PRESERVED_PERSONAL_ROOT'

    if ($Mode -ceq 'LocalFeed') {
    Set-TestEnvironment $FreshRoaming $FreshLocal $FreshTemp
    Assert-True (-not (Test-Path -LiteralPath $FreshPersonalRoot)) 'Fresh personal root exists before installation.'
    Invoke-Setup $CandidateSetup $FreshInstall (Join-Path $Evidence "install-v$($ReleasePlan.Version)-fresh.log")
    Assert-True ((Get-InstalledVersion $FreshInstall) -eq $ReleasePlan.Version) "Fresh candidate did not install as v$($ReleasePlan.Version)."
    Assert-True (-not (Test-Path -LiteralPath $FreshPersonalRoot)) 'Fresh install populated the personal root before first launch.'
    Write-Step 'FRESH_INSTALL_PRELAUNCH_PERSONAL_ROOT_CLEAN'

    $freshApp = Start-DisposableApp $FreshInstall
    $freshPlanner = Join-Path $FreshPersonalRoot 'planner-state.json'
    Wait-Until { Test-Path -LiteralPath $freshPlanner -PathType Leaf } 90 'fresh default Planner state'
    Wait-Until { $freshApp.Refresh(); -not $freshApp.HasExited -and $freshApp.MainWindowHandle -ne 0 } 60 "fresh v$($ReleasePlan.Version) main window"
    Wait-Until { @(Get-TestWebViewRecords).Count -gt 0 } 60 'fresh embedded WebView2 startup'
    Start-Sleep -Seconds 3
    Invoke-NativeClose $freshApp 60
    Wait-Until { @(Get-TestProcessRecords $FreshInstall).Count -eq 0 } 60 'fresh launch process teardown'
    Wait-Until { @(Get-TestWebViewRecords).Count -eq 0 } 60 'fresh WebView2 teardown'
    $freshState = Get-Content -LiteralPath $freshPlanner -Raw | ConvertFrom-Json -Depth 100
    Assert-True ($freshState.applicationVersion -eq $ReleasePlan.Version) 'Fresh Planner state has the wrong application version.'
    Assert-True ($freshState.alchemy.alchemyMastery -eq 0 -and $freshState.cooking.cookingMastery -eq 0 -and $freshState.processing.processingMastery -eq 0) 'Fresh Planner masteries are not neutral.'
    Assert-True (@($freshState.alchemy.inventory.PSObject.Properties).Count -eq 0 -and @($freshState.cooking.inventory.PSObject.Properties).Count -eq 0 -and @($freshState.processing.inventory.PSObject.Properties).Count -eq 0) 'Fresh Planner inventory is not empty.'
    Assert-True ($freshState.marketTax.valuePack -eq $false -and $freshState.marketTax.merchantRing -eq $false -and $freshState.marketTax.familyFameBonus -eq 0) 'Fresh market settings are not neutral.'
    Assert-True ($freshState.afkWeightProfile.maximumWeightLt -eq 0) 'Fresh AFK weight is not neutral.'
    $freshSentinel = Join-Path $FreshPersonalRoot 'fresh-personal-sentinel.txt'
    [IO.File]::WriteAllText($freshSentinel, 'synthetic-fresh-personal-sentinel-fbba8d0', [Text.UTF8Encoding]::new($false))
    $freshSentinelHash = Get-Sha256 $freshSentinel
    $freshVerifyOutput = Join-Path $Evidence 'fresh-personal-verification.json'
    $freshVerifyStdout = Join-Path $Evidence 'fresh-personal-verification.stdout.log'
    $freshVerifyStderr = Join-Path $Evidence 'fresh-personal-verification.stderr.log'
    $freshVerifyArguments = "-I -E `"$FreshVerifier`" `"$FreshPersonalRoot`" `"$freshVerifyOutput`""
    $freshVerifyProcess = Start-Process -FilePath $Python -ArgumentList $freshVerifyArguments -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $freshVerifyStdout -RedirectStandardError $freshVerifyStderr
    Assert-True ($freshVerifyProcess.ExitCode -eq 0) "Fresh personal-data verification failed; see $freshVerifyStderr"
    $Results.freshPersonal = Get-Content -LiteralPath $freshVerifyOutput -Raw | ConvertFrom-Json
    Assert-True ((Get-Sha256 $freshSentinel) -eq $freshSentinelHash) 'Fresh app launch changed the personal sentinel.'
    Write-Step "FRESH_V$($ReleasePlan.Version)_PROFILE_NEUTRAL_AND_EMPTY"

    $coldCloseRuns = [System.Collections.Generic.List[object]]::new()
    for ($coldIndex = 1; $coldIndex -le 1; $coldIndex++) {
        $coldBase = Join-Path $DisposableBase "independent-cold-$coldIndex"
        Assert-True (-not (Test-Path -LiteralPath $coldBase)) "Independent cold root $coldIndex already exists."
        $coldRoaming = Join-Path $coldBase 'Roaming'
        $coldLocal = Join-Path $coldBase 'Local'
        $coldTemp = Join-Path $coldBase 'Temp'
        Set-TestEnvironment $coldRoaming $coldLocal $coldTemp
        $coldStartedAt = [DateTime]::UtcNow
        $coldApp = Start-DisposableApp $FreshInstall
        $deadline = [DateTime]::UtcNow.AddSeconds(45)
        do {
            $coldApp.Refresh()
            if ($coldApp.HasExited) { throw "Independent cold-close run $coldIndex exited before presenting a window." }
            if ($coldApp.MainWindowHandle -ne 0) { break }
            Start-Sleep -Milliseconds 10
        } while ([DateTime]::UtcNow -lt $deadline)
        Assert-True ($coldApp.MainWindowHandle -ne 0) "Independent cold-close run $coldIndex exposed no window."
        $visibleAt = [DateTime]::UtcNow
        Invoke-NativeClose $coldApp 60
        Wait-Until { @(Get-TestProcessRecords $FreshInstall).Count -eq 0 } 60 "independent cold-close run $coldIndex process teardown"
        Wait-Until { @(Get-TestWebViewRecords).Count -eq 0 } 60 "independent cold-close run $coldIndex WebView2 teardown"
        $coldCloseRuns.Add([ordered]@{
            run = $coldIndex
            exitCode = $coldApp.ExitCode
            startupMilliseconds = [int]($visibleAt - $coldStartedAt).TotalMilliseconds
            closeMilliseconds = [int]([DateTime]::UtcNow - $visibleAt).TotalMilliseconds
        })
        Write-Step "INDEPENDENT_COLD_STARTUP_CLOSE_PASS run=$coldIndex"
    }
    $Results.independentColdStartupCloseStress = @($coldCloseRuns)
    Write-Step 'INDEPENDENT_COLD_STARTUP_CLOSE_PASS runs=1'

    Set-TestEnvironment $StressRoaming $StressLocal $StressTemp
    New-Item -ItemType Directory -Path $StressPersonalRoot -Force | Out-Null
    $stressMarker = [ordered]@{
        schemaVersion = 1; packageId = $ReleasePlan.PackageId; releaseChannel = $ReleasePlan.Channel; profile = $true
        profileId = 'profile-acde-0123456789abcdef0123456789abcdef'
        transactionId = 'move-acde-fedcba9876543210fedcba9876543210'
    }
    $stressMarkerPath = Join-Path $StressPersonalRoot '.black-spirit-life-profile.json'
    Write-JsonNoBom $stressMarkerPath $stressMarker
    $stressMarkerCheck = Get-Content -LiteralPath $stressMarkerPath -Raw | ConvertFrom-Json
    Assert-True ($stressMarkerCheck.profile -eq $true) 'Stress selected-root marker profile flag is invalid.'
    Assert-True ([regex]::IsMatch([string]$stressMarkerCheck.profileId, '^[a-z]+-[a-f0-9]+-[a-f0-9]{32}$')) 'Stress selected-root profile identity is invalid.'
    Assert-True ([regex]::IsMatch([string]$stressMarkerCheck.transactionId, '^[a-z]+-[a-f0-9]+-[a-f0-9]{32}$')) 'Stress selected-root transaction identity is invalid.'
    $stressControl = Join-Path $StressLocal 'Black Spirit Life\Bootstrap'
    New-Item -ItemType Directory -Path $stressControl -Force | Out-Null
    $stressLocator = [ordered]@{
        schemaVersion = 1; packageId = $ReleasePlan.PackageId; releaseChannel = $ReleasePlan.Channel
        applicationDirectory = [IO.Path]::GetFullPath($StressPersonalRoot)
    }
    Write-JsonNoBom (Join-Path $stressControl 'personal-data-location.committed.json') $stressLocator
    Write-JsonNoBom (Join-Path $stressControl 'personal-data-location.json') $stressLocator
    $stressSentinel = Join-Path $StressPersonalRoot 'stress-personal-sentinel.txt'
    [IO.File]::WriteAllText($stressSentinel, 'synthetic-stress-sentinel-fbba8d0', [Text.UTF8Encoding]::new($false))
    $stressSentinelHash = Get-Sha256 $stressSentinel
    Write-Step 'EARLY_CLOSE_STRESS_MARKER_VALIDATED_BEFORE_LOCATOR'

    $earlyCloseRuns = [System.Collections.Generic.List[object]]::new()
    for ($earlyIndex = 1; $earlyIndex -le 3; $earlyIndex++) {
        $earlyApp = Start-DisposableApp $FreshInstall
        $deadline = [DateTime]::UtcNow.AddSeconds(45)
        do {
            $earlyApp.Refresh()
            if ($earlyApp.HasExited) { throw "Early-close run $earlyIndex exited before presenting a window." }
            if ($earlyApp.MainWindowHandle -ne 0) { break }
            Start-Sleep -Milliseconds 10
        } while ([DateTime]::UtcNow -lt $deadline)
        Assert-True ($earlyApp.MainWindowHandle -ne 0) "Early-close run $earlyIndex exposed no window."
        $visibleAt = [DateTime]::UtcNow
        Invoke-NativeClose $earlyApp 60
        Wait-Until { @(Get-TestProcessRecords $FreshInstall).Count -eq 0 } 60 "early-close run $earlyIndex process teardown"
        Wait-Until { @(Get-TestWebViewRecords).Count -eq 0 } 60 "early-close run $earlyIndex WebView2 teardown"
        $earlyCloseRuns.Add([ordered]@{
            run = $earlyIndex
            exitCode = $earlyApp.ExitCode
            closeMilliseconds = [int]([DateTime]::UtcNow - $visibleAt).TotalMilliseconds
        })
        Write-Step "EARLY_STARTUP_CLOSE_PASS run=$earlyIndex"
    }
    Assert-True ((Get-Sha256 $stressSentinel) -eq $stressSentinelHash) 'Early-close stress changed the disposable personal sentinel.'
    $Results.earlyStartupCloseStress = @($earlyCloseRuns)
    Write-Step 'EARLY_STARTUP_CLOSE_STRESS_PASS runs=3'

    Set-TestEnvironment $FreshRoaming $FreshLocal $FreshTemp

    $managedFile = Join-Path $FreshInstall 'current\BlackSpiritLifeUpdater.exe'
    $managedHash = Get-Sha256 $managedFile
    $freshPlannerHashBeforeRepair = Get-Sha256 $freshPlanner
    [IO.File]::WriteAllBytes($managedFile, [Text.Encoding]::UTF8.GetBytes('synthetic managed-file corruption'))
    Assert-True ((Get-Sha256 $managedFile) -ne $managedHash) 'Managed-file corruption did not take effect.'
    Invoke-Setup $CandidateSetup $FreshInstall (Join-Path $Evidence "repair-v$($ReleasePlan.Version).log")
    Assert-True ((Get-InstalledVersion $FreshInstall) -eq $ReleasePlan.Version) 'Same-version repair changed the installed version.'
    Assert-True ((Get-Sha256 $managedFile) -eq $managedHash) 'Same-version repair did not restore the managed file.'
    Assert-True ((Get-Sha256 $freshPlanner) -eq $freshPlannerHashBeforeRepair) 'Same-version repair changed Planner personal state.'
    Assert-True ((Get-Sha256 $freshSentinel) -eq $freshSentinelHash) 'Same-version repair changed the personal sentinel.'
    $Results.repair = [ordered]@{ file = 'current/BlackSpiritLifeUpdater.exe'; restoredSha256 = $managedHash; personalSentinelSha256 = $freshSentinelHash }
    Write-Step "SAME_VERSION_REPAIR_CONVERGED managedSha256=$managedHash"

    Invoke-Uninstall $FreshInstall 'fresh-repaired-install'
    Assert-True (Test-Path -LiteralPath $FreshPersonalRoot -PathType Container) 'Fresh uninstall removed the personal root.'
    Assert-True ((Get-Sha256 $freshSentinel) -eq $freshSentinelHash) 'Fresh uninstall changed the personal sentinel.'
    Assert-True (Test-Path -LiteralPath $freshPlanner -PathType Leaf) 'Fresh uninstall removed Planner personal state.'
    Assert-True ((Get-Sha256 $stressSentinel) -eq $stressSentinelHash) 'Fresh uninstall changed the selected stress personal sentinel.'
    Write-Step 'FRESH_UNINSTALL_PRESERVED_PERSONAL_ROOT'
    }

    $testCrashEvents = @(Get-TestCrashEvents $ApplicationEventStart)
    $Results.applicationCrashEvents = @(
        $testCrashEvents | ForEach-Object {
            [ordered]@{
                timeCreated = $_.TimeCreated.ToString('o')
                id = $_.Id
                provider = $_.ProviderName
                recordId = $_.RecordId
                message = $_.Message
            }
        }
    )
    Assert-True ($testCrashEvents.Count -eq 0) 'Windows recorded an Application Error/WER/Hang event for a disposable installed app.'
    Write-Step 'NO_INSTALLED_APP_APPLICATION_ERROR_WER_OR_HANG'

    $Results.success = $true
    $Results.finishedAtUtc = [DateTime]::UtcNow.ToString('o')
} catch {
    $Fatal = $_
    $Results.error = $_.Exception.ToString()
    Write-Host "LIFECYCLE FAILURE: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    try { Stop-TestEdge } catch { $RestorationErrors.Add("Edge cleanup: $($_.Exception.Message)") }
    try { Stop-TestWebViews } catch { $RestorationErrors.Add("WebView cleanup: $($_.Exception.Message)") }
    foreach ($installRoot in @($UpgradeInstall, $FreshInstall)) {
        try {
            if (Test-Path -LiteralPath $installRoot -PathType Container) { Stop-TestProcesses $installRoot }
        } catch { $RestorationErrors.Add("process cleanup: $($_.Exception.Message)") }
    }
    if ($OsStateCaptured) {
        try {
            if (Test-Path -LiteralPath $UninstallRegistryPs) { Remove-Item -LiteralPath $UninstallRegistryPs -Recurse -Force }
        } catch { $RestorationErrors.Add("registry cleanup: $($_.Exception.Message)") }
        try {
            if (Test-Path -LiteralPath $StartMenuShortcut) { Remove-Item -LiteralPath $StartMenuShortcut -Force }
        } catch { $RestorationErrors.Add("shortcut cleanup: $($_.Exception.Message)") }
    }

    try {
        if ($OldInstallMoved) {
            Assert-True (Test-Path -LiteralPath $OldInstallBackup -PathType Container) 'Preexisting disposable install backup disappeared.'
            Assert-True (-not (Test-Path -LiteralPath $OldInstallLocation)) 'Preexisting disposable install destination was unexpectedly recreated.'
            New-Item -ItemType Directory -Path (Split-Path -Parent $OldInstallLocation) -Force | Out-Null
            Move-Item -LiteralPath $OldInstallBackup -Destination $OldInstallLocation
        }
    } catch { $RestorationErrors.Add("preexisting install restore: $($_.Exception.Message)") }
    try {
        if ($OsStateCaptured -and $RegistryExisted) {
            & reg.exe import (Join-Path $OsBackup 'uninstall-before.reg') | Out-Null
            Assert-True ($LASTEXITCODE -eq 0) 'Registry import failed.'
        }
    } catch { $RestorationErrors.Add("registry restore: $($_.Exception.Message)") }
    try {
        if ($OsStateCaptured -and $ShortcutExisted) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $StartMenuShortcut) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $OsBackup 'Black Spirit Life-before.lnk') -Destination $StartMenuShortcut -Force
        }
    } catch { $RestorationErrors.Add("shortcut restore: $($_.Exception.Message)") }

    foreach ($name in $OriginalEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $OriginalEnvironment[$name], [EnvironmentVariableTarget]::Process)
    }

    $registryRestored = $false
    try {
        if (-not $OsStateCaptured) {
            $registryRestored = $true
        } elseif ($RegistryExisted) {
            $queryAfter = @(& reg.exe query $UninstallRegistryNative /s)
            $registryRestored = $LASTEXITCODE -eq 0 -and (($RegistryQueryBefore -join "`n") -eq ($queryAfter -join "`n"))
        } else {
            $registryRestored = -not (Test-Path -LiteralPath $UninstallRegistryPs)
        }
    } catch { $RestorationErrors.Add("registry verification: $($_.Exception.Message)") }
    $shortcutRestored = $false
    try {
        $shortcutRestored = if (-not $OsStateCaptured) {
            $true
        } elseif ($ShortcutExisted) {
            (Test-Path -LiteralPath $StartMenuShortcut -PathType Leaf) -and ((Get-Sha256 $StartMenuShortcut) -eq $ShortcutHashBefore)
        } else {
            -not (Test-Path -LiteralPath $StartMenuShortcut)
        }
    } catch { $RestorationErrors.Add("shortcut verification: $($_.Exception.Message)") }
    $oldInstallRestored = if ($OldInstallMoved) { Test-Path -LiteralPath $OldInstallLocation -PathType Container } else { $true }
    $testProcessesGone = (@(Get-TestProcessRecords $UpgradeInstall).Count -eq 0) -and (@(Get-TestProcessRecords $FreshInstall).Count -eq 0)
    $testEdgeGone = @(Get-TestEdgeRecords).Count -eq 0
    $testWebViewsGone = @(Get-TestWebViewRecords).Count -eq 0
    $Results.restoration = [ordered]@{
        registryRestored = $registryRestored
        shortcutRestored = $shortcutRestored
        preexistingDisposableInstallRestored = $oldInstallRestored
        testProcessesGone = $testProcessesGone
        disposableEdgeGone = $testEdgeGone
        disposableWebViewsGone = $testWebViewsGone
        baselineFishListeners = @($BaselineFishListeners)
        errors = @($RestorationErrors)
    }
    if (-not $registryRestored) { $RestorationErrors.Add('uninstall registry key did not restore byte-semantically') }
    if (-not $shortcutRestored) { $RestorationErrors.Add('Start Menu shortcut hash did not restore') }
    if (-not $oldInstallRestored) { $RestorationErrors.Add('preexisting disposable install did not restore') }
    if (-not $testProcessesGone) { $RestorationErrors.Add('disposable Black Spirit Life processes remain') }
    if (-not $testEdgeGone) { $RestorationErrors.Add('disposable headless Edge processes remain') }
    if (-not $testWebViewsGone) { $RestorationErrors.Add('disposable WebView2 processes remain') }
    $Results.restoration.errors = @($RestorationErrors)
    try { Write-JsonNoBom $SummaryPath $Results } catch { }
    if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch { } }
}

if ($RestorationErrors.Count -gt 0) {
    throw "Lifecycle restoration failed: $($RestorationErrors -join '; ')"
}
if ($null -ne $Fatal) { throw $Fatal }
Write-Host "LIFECYCLE PASS summary=$SummaryPath"
