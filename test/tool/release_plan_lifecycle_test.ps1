[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$planLoader = Join-Path $repositoryRoot 'tool\release\release_plan.ps1'
$harness = Join-Path $repositoryRoot 'tool\release\run_lifecycle_rehearsal.ps1'
$lifecycleRoot = Join-Path $repositoryRoot 'tool\release\lifecycle'
$comparator = Join-Path $lifecycleRoot 'compare_nupkg.py'
$personalVerifier = Join-Path $lifecycleRoot 'verify_personal.py'
$freshVerifier = Join-Path $lifecycleRoot 'verify_fresh.py'
. $planLoader
. (Join-Path $repositoryRoot 'tool\release\prepared_dependencies.ps1')
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:assertions = 0
function Assert-Fixture([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Lifecycle fixture assertion failed: $Message" }
    $script:assertions++
}
function Assert-Rejected([scriptblock]$Action, [string]$Pattern) {
    $caught = $false
    try { & $Action | Out-Null }
    catch {
        $caught = $true
        Assert-Fixture ($_.Exception.Message -match $Pattern) "Unexpected rejection: $($_.Exception.Message)"
    }
    Assert-Fixture $caught "Expected rejection matching $Pattern."
}
function Set-FixtureFile([string]$Path, [string]$Text) {
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function Write-JsonFile([string]$Path, $Value) {
    Set-FixtureFile $Path ($Value | ConvertTo-Json -Depth 30 -Compress)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
function Copy-JsonObject($Value) {
    return (($Value | ConvertTo-Json -Depth 30 -Compress) | ConvertFrom-Json)
}
function New-ArtifactRecord([string]$Role, [string]$Path, [string]$Root) {
    $item = Get-Item -LiteralPath $Path
    return [ordered]@{
        role = $Role
        path = $item.FullName.Substring($Root.Length).TrimStart('\', '/')
        bytes = [long]$item.Length
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    }
}
function New-Zip([string]$Path, [object[]]$Entries) {
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    $archive = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($record in $Entries) {
            $entry = $archive.CreateEntry([string]$record.Name)
            if (-not [string]$record.Name.EndsWith('/') -and -not [string]$record.Name.EndsWith('\')) {
                $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
                try { $writer.Write([string]$record.Content) }
                finally { $writer.Dispose() }
            }
        }
    }
    finally { $archive.Dispose() }
}
function Invoke-Python([string[]]$Arguments) {
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $messages = @(& $script:python @Arguments 2>&1)
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($messages -join "`n") }
    }
    finally { $ErrorActionPreference = $savedPreference }
}

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\', '/'))
$fixtureRoot = Join-Path $tempParent ('bsl-release-plan-lifecycle-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($fixtureRoot)
$bundledPython = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
if (-not [string]::IsNullOrWhiteSpace($env:BSL_RELEASE_PYTHON)) {
    $script:python = [IO.Path]::GetFullPath($env:BSL_RELEASE_PYTHON)
    if (-not (Test-Path -LiteralPath $script:python -PathType Leaf)) {
        throw 'BSL_RELEASE_PYTHON does not name an available Python executable.'
    }
}
elseif (Test-Path -LiteralPath $bundledPython -PathType Leaf) {
    $script:python = $bundledPython
}
else {
    $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($null -eq $pythonCommand) { $pythonCommand = Get-Command python -ErrorAction Stop }
    $script:python = $pythonCommand.Source
}
$shellPath = (Get-Process -Id $PID).Path

try {
    $projectRoot = Join-Path $fixtureRoot 'project'
    Set-FixtureFile (Join-Path $projectRoot 'packages\bdo_gathering_companion\lib\src\services\stable_v017_migration.dart') '// synthetic migration source'
    Set-FixtureFile (Join-Path $projectRoot 'packages\bdo_gathering_companion\lib\src\services\session_store.dart') '// synthetic session store'
    Set-FixtureFile (Join-Path $projectRoot 'packages\bdo_gathering_companion\pubspec.lock') 'packages: {}'
    $gatherRoot = Join-Path $projectRoot 'packages\bdo_gathering_companion'
    Set-FixtureFile (Join-Path $gatherRoot 'pubspec.yaml') 'name: bdo_gathering_companion'
    Set-FixtureFile (Join-Path $gatherRoot '.dart_tool\package_config.json') '{"configVersion":2,"generator":"pub","generatorVersion":"3.12.2","packages":[{"name":"bdo_gathering_companion","rootUri":"../","packageUri":"lib/"}]}'
    $flutterPath = Join-Path $fixtureRoot 'sdk\bin\flutter.bat'
    Set-FixtureFile $flutterPath "@echo off`r`nexit /b 97`r`n"
    Set-FixtureFile (Join-Path $fixtureRoot 'sdk\bin\cache\flutter.version.json') '{"frameworkVersion":"3.44.0","dartSdkVersion":"3.12.2"}'
    Set-FixtureFile (Join-Path $fixtureRoot 'sdk\bin\cache\dart-sdk\bin\dart.exe') 'synthetic-dart'
    Set-FixtureFile (Join-Path $fixtureRoot 'sdk\bin\cache\flutter_tools.snapshot') 'synthetic-tools'
    $dependencyReceiptPath = Join-Path $fixtureRoot 'synthetic-dependency-receipt.json'
    $dependencyReceiptHash = Write-JsonFile $dependencyReceiptPath ([ordered]@{
        schemaVersion = 1; resolutionSucceeded = $true; command = 'flutter pub get --enforce-lockfile'
        snapshot = (Get-ReleaseDependencySnapshot $gatherRoot $flutterPath)
    })

    $historyRoot = Join-Path $fixtureRoot 'history'
    $previousSetup = Join-Path $historyRoot 'BlackSpiritLifeSetup-0.1.11.exe'
    Set-FixtureFile $previousSetup 'synthetic previous setup bytes'
    $candidateRoot = Join-Path $fixtureRoot 'candidate'
    $candidateSetup = Join-Path $candidateRoot 'feed\BlackSpiritLifeSetup.exe'
    $candidateFull = Join-Path $candidateRoot 'feed\BlackSpiritLife.App-0.1.12-full.nupkg'
    $candidateDelta = Join-Path $candidateRoot 'feed\BlackSpiritLife.App-0.1.12-delta.nupkg'
    $candidateFeed = Join-Path $candidateRoot 'feed\releases.win-x64-stable.json'
    $previousFull = Join-Path $candidateRoot 'published-inputs\BlackSpiritLife.App-0.1.11-full.nupkg'
    Set-FixtureFile $candidateSetup 'synthetic candidate setup'
    Set-FixtureFile $candidateFull ('F' * 400)
    Set-FixtureFile $candidateDelta ('D' * 100)
    Set-FixtureFile $candidateFeed '{"Assets":[]}'
    Set-FixtureFile $previousFull ('P' * 300)

    $plan = [ordered]@{
        schemaVersion = 1
        publicationAuthorizedByThisFile = $false
        identity = [ordered]@{
            repository = 'https://github.com/Sanitee/black-spirit-life'
            packageId = 'BlackSpiritLife.App'
            channel = 'win-x64-stable'
            version = '0.1.12'
            previousPublishedVersion = '0.1.11'
            buildNumber = 31
            releaseNotesRelativePath = 'docs/releases/0.1.12.md'
            outputDirectoryName = 'public-stable-v0.1.12'
            manifestName = 'public-stable-candidate-manifest.json'
        }
        source = [ordered]@{
            expectedCommit = ('1' * 40)
            expectedTag = 'v0.1.12'
            reviewedParentCommit = ('2' * 40)
            previousPublishedCommit = ('3' * 40)
            previousPublishedTag = 'v0.1.11'
        }
        historicalInputs = [ordered]@{
            previousFeed = [ordered]@{ bytes = 17; sha256 = ('A' * 64) }
            previousFullPackage = [ordered]@{
                bytes = [long](Get-Item -LiteralPath $previousFull).Length
                sha256 = (Get-FileHash -LiteralPath $previousFull -Algorithm SHA256).Hash
            }
        }
        lifecycle = [ordered]@{
            previousSetup = [ordered]@{
                fileName = [IO.Path]::GetFileName($previousSetup)
                bytes = [long](Get-Item -LiteralPath $previousSetup).Length
                sha256 = (Get-FileHash -LiteralPath $previousSetup -Algorithm SHA256).Hash
            }
            migrationSourceVersion = '0.1.7'
            syntheticFixtureSchemaVersion = 1
        }
        remainingBlockers = @('Synthetic lifecycle fixture only; publication is separately authorized.')
    }
    $planPath = Join-Path $fixtureRoot 'release-plan.json'
    $planHash = Write-JsonFile $planPath $plan
    $loaded = Read-ReleasePlan $planPath $planHash
    Assert-Fixture ($loaded.Version -ceq '0.1.12' -and $loaded.BuildNumber -eq 31) 'A valid plan loads with exact identity.'
    Assert-Fixture ($null -eq $loaded.PSObject.Properties['PublicationAuthorizedByThisFile']) 'The loader does not expose any publication-authority shortcut.'
    Assert-Rejected { Read-ReleasePlan $planPath ('0' * 64) } 'SHA-256 mismatch'

    $mutations = @(
        @{ Name = 'string boolean'; Pattern = 'schema 1'; Apply = { param($p) $p.publicationAuthorizedByThisFile = 'false' } },
        @{ Name = 'string schema'; Pattern = 'schema 1'; Apply = { param($p) $p.schemaVersion = '1' } },
        @{ Name = 'fractional build'; Pattern = 'JSON integer'; Apply = { param($p) $p.identity.buildNumber = 31.5 } },
        @{ Name = 'numeric version'; Pattern = 'JSON string'; Apply = { param($p) $p.identity.version = 12 } },
        @{ Name = 'unsupported package'; Pattern = 'not a supported'; Apply = { param($p) $p.identity.packageId = 'Other.App' } },
        @{ Name = 'unsupported channel'; Pattern = 'not a supported'; Apply = { param($p) $p.identity.channel = 'beta' } },
        @{ Name = 'scalar blockers'; Pattern = 'remaining verification blockers'; Apply = { param($p) $p.remainingBlockers = 'one scalar' } }
    )
    foreach ($mutation in $mutations) {
        $changed = Copy-JsonObject $plan
        & $mutation.Apply $changed
        $changedPath = Join-Path $fixtureRoot ("plan-$($mutation.Name.Replace(' ', '-')).json")
        $changedHash = Write-JsonFile $changedPath $changed
        Assert-Rejected { Read-ReleasePlan $changedPath $changedHash } $mutation.Pattern
    }
    foreach ($unsafe in @('..\evil.md', 'C:\evil.md', 'safe.md:stream', 'AUX.md', 'dir\.\file.md', 'dir\name.\file.md')) {
        $changed = Copy-JsonObject $plan
        $changed.identity.releaseNotesRelativePath = $unsafe
        $changedPath = Join-Path $fixtureRoot ('unsafe-' + [Guid]::NewGuid().ToString('N') + '.json')
        $changedHash = Write-JsonFile $changedPath $changed
        Assert-Rejected { Read-ReleasePlan $changedPath $changedHash } 'safe relative path|invalid Windows path segment'
    }

    $frozenPlan = Join-Path $candidateRoot 'approved-release-plan.json'
    [IO.File]::Copy($planPath, $frozenPlan, $false)
    $manifest = [ordered]@{
        schemaVersion = 2
        publicCandidate = $true
        localOnly = $false
        version = '0.1.12'
        buildNumber = 31
        sourceCommit = ('1' * 40)
        sourceTag = 'v0.1.12'
        packageId = 'BlackSpiritLife.App'
        channel = 'win-x64-stable'
        updateSource = 'https://github.com/Sanitee/black-spirit-life'
        releasePlan = [ordered]@{ path = 'approved-release-plan.json'; sha256 = $planHash; schemaVersion = 1 }
        artifacts = @(
            (New-ArtifactRecord 'velopack-setup' $candidateSetup $candidateRoot),
            (New-ArtifactRecord 'full-package' $candidateFull $candidateRoot),
            (New-ArtifactRecord 'delta-package' $candidateDelta $candidateRoot),
            (New-ArtifactRecord 'update-feed' $candidateFeed $candidateRoot)
        )
        delta = [ordered]@{
            publishedInputs = @((New-ArtifactRecord 'published-previous-full-package' $previousFull $candidateRoot))
        }
    }
    $manifestPath = Join-Path $candidateRoot 'public-stable-candidate-manifest.json'
    $manifestHash = Write-JsonFile $manifestPath $manifest
    $evidenceRoot = Join-Path $fixtureRoot 'outputs\evidence-local'
    $disposableRoot = Join-Path $fixtureRoot 'outputs\bsl-lifecycle-local'
    $arguments = @{
        ReleasePlanPath = $planPath
        ApprovedReleasePlanSha256 = $planHash
        CandidateManifestPath = $manifestPath
        ApprovedCandidateManifestSha256 = $manifestHash
        PreviousSetupPath = $previousSetup
        ProjectRoot = $projectRoot
        EvidenceRoot = $evidenceRoot
        DisposableBase = $disposableRoot
        PythonPath = $script:python
        FlutterPath = $flutterPath
        GatheringDependencyReceiptPath = $dependencyReceiptPath
        ApprovedGatheringDependencyReceiptSha256 = $dependencyReceiptHash
        EdgePath = $shellPath
        Mode = 'LocalFeed'
        PreflightOnly = $true
    }
    $preflightText = @(& $harness @arguments) -join "`n"
    $preflight = $preflightText | ConvertFrom-Json
    Assert-Fixture ($preflight.status -ceq 'preflight-passed' -and $preflight.installExecuted -eq $false) 'LocalFeed preflight passes without executing an install.'
    Assert-Fixture (-not (Test-Path -LiteralPath $evidenceRoot) -and -not (Test-Path -LiteralPath $disposableRoot)) 'Preflight creates no evidence or disposable directories.'
    Set-FixtureFile (Join-Path $gatherRoot 'pubspec.lock') 'packages: {changed: true}'
    Assert-Rejected { & $harness @arguments } 'dependency receipt is stale'
    Set-FixtureFile (Join-Path $gatherRoot 'pubspec.lock') 'packages: {}'
    $badDependency = $arguments.Clone()
    $badDependency.ApprovedGatheringDependencyReceiptSha256 = ('0' * 64)
    Assert-Rejected { & $harness @badDependency } 'dependency receipt SHA-256'

    $existingEvidence = Join-Path $fixtureRoot 'outputs\already-exists'
    $null = [IO.Directory]::CreateDirectory($existingEvidence)
    $badArguments = $arguments.Clone()
    $badArguments.EvidenceRoot = $existingEvidence
    Assert-Rejected { & $harness @badArguments } 'must be new paths'
    $badArguments = $arguments.Clone()
    $badArguments.EvidenceRoot = Join-Path $candidateRoot 'nested-evidence'
    Assert-Rejected { & $harness @badArguments } 'must be disjoint'
    $badArguments = $arguments.Clone()
    $badArguments.DisposableBase = Join-Path $projectRoot 'bsl-lifecycle-overlap'
    Assert-Rejected { & $harness @badArguments } 'must be disjoint'

    $publicArguments = $arguments.Clone()
    $publicArguments.Mode = 'PublicRoute'
    $publicArguments.EvidenceRoot = Join-Path $fixtureRoot 'outputs\evidence-public'
    $publicArguments.DisposableBase = Join-Path $fixtureRoot 'outputs\bsl-lifecycle-public'
    Assert-Rejected { & $harness @publicArguments } 'requires an approved passed LocalFeed receipt'
    $parityRecords = @()
    foreach ($phase in @('upgrade', 'fresh', 'repair')) {
        $relative = "installed-payload-$phase.json"
        $syntheticParity = [ordered]@{
            schemaVersion = 1; purpose = 'installed-payload-parity'; success = $true
            scope = 'exhaustive-current-plus-two-exact-relocated-root-tools'
            packageSha256 = (Get-FileHash -LiteralPath $candidateFull -Algorithm SHA256).Hash
            verifierSha256 = (Get-FileHash -LiteralPath (Join-Path $lifecycleRoot 'verify_installed_payload.py') -Algorithm SHA256).Hash
            archiveNamePolicySha256 = (Get-FileHash -LiteralPath $comparator -Algorithm SHA256).Hash
            expectedInventorySha256 = ('E' * 64); installedInventorySha256 = ('E' * 64)
            expectedFileCount = 6; installedFileCount = 6
            missing = @(); unexpected = @(); changed = @(); excludedCurrentFiles = @()
        }
        $reportHash = Write-JsonFile (Join-Path $fixtureRoot $relative) $syntheticParity
        $parityRecords += [ordered]@{
            phase = $phase; reportPath = $relative; reportSha256 = $reportHash
            packageSha256 = $syntheticParity.packageSha256; expectedInventorySha256 = ('E' * 64)
            installedInventorySha256 = ('E' * 64); success = $true
        }
    }
    $receipt = [ordered]@{
        schemaVersion = 1
        success = $true
        mode = 'LocalFeed'
        releasePlanSha256 = $preflight.releasePlanSha256
        candidateManifestSha256 = $preflight.candidateManifestSha256
        harnessSha256 = $preflight.harnessSha256
        syntheticFixtureSha256 = $preflight.syntheticFixtureSha256
        lifecycleContextSha256 = $preflight.lifecycleContextSha256
        restoration = [ordered]@{ errors = @() }
        installedPayloadParity = $parityRecords
    }
    $receiptPath = Join-Path $fixtureRoot 'local-feed-receipt.json'
    $receiptHash = Write-JsonFile $receiptPath $receipt
    $publicArguments.LocalFeedReceiptPath = $receiptPath
    $publicArguments.ApprovedLocalFeedReceiptSha256 = $receiptHash
    $publicText = @(& $harness @publicArguments) -join "`n"
    $publicPreflight = $publicText | ConvertFrom-Json
    Assert-Fixture ($publicPreflight.localReceiptReused -eq $true -and $publicPreflight.mode -ceq 'PublicRoute') 'PublicRoute accepts only the exact matching passed receipt.'
    $heldReport = Join-Path $fixtureRoot 'installed-payload-repair.json'
    [IO.File]::Move($heldReport, ($heldReport + '.held'))
    Assert-Rejected { & $harness @publicArguments } 'does not exist|cannot find|unavailable'
    [IO.File]::Move(($heldReport + '.held'), $heldReport)
    $parityOriginal = [IO.File]::ReadAllText($heldReport)
    Set-FixtureFile $heldReport ($parityOriginal + ' ')
    Assert-Rejected { & $harness @publicArguments } 'SHA-256 does not match'
    Set-FixtureFile $heldReport $parityOriginal
    $shortReceipt = Copy-JsonObject $receipt
    $shortReceipt.installedPayloadParity = @($shortReceipt.installedPayloadParity[0])
    $shortReceiptPath = Join-Path $fixtureRoot 'missing-parity-local.json'
    $shortHash = Write-JsonFile $shortReceiptPath $shortReceipt
    $shortArgs = $publicArguments.Clone()
    $shortArgs.LocalFeedReceiptPath = $shortReceiptPath; $shortArgs.ApprovedLocalFeedReceiptSha256 = $shortHash
    Assert-Rejected { & $harness @shortArgs } 'parity reports are incomplete'
    $publicArguments.ApprovedLocalFeedReceiptSha256 = ('0' * 64)
    Assert-Rejected { & $harness @publicArguments } 'SHA-256 does not match|SHA-256 mismatch'
    $wrongReceipt = Copy-JsonObject $receipt
    $wrongReceipt.harnessSha256 = ('0' * 64)
    $wrongReceiptPath = Join-Path $fixtureRoot 'wrong-local-feed-receipt.json'
    $wrongReceiptHash = Write-JsonFile $wrongReceiptPath $wrongReceipt
    $publicArguments.LocalFeedReceiptPath = $wrongReceiptPath
    $publicArguments.ApprovedLocalFeedReceiptSha256 = $wrongReceiptHash
    Assert-Rejected { & $harness @publicArguments } 'not a passed result for these exact inputs'

    foreach ($verifier in @($personalVerifier, $freshVerifier, $comparator)) {
        $optimized = Invoke-Python @('-O', $verifier)
        Assert-Fixture ($optimized.ExitCode -ne 0 -and $optimized.Output -match 'assertions to be enabled') "Optimized Python is rejected by $([IO.Path]::GetFileName($verifier))."
    }

    $zipRoot = Join-Path $fixtureRoot 'archives'
    $validLeft = Join-Path $zipRoot 'valid-left.zip'
    $validRight = Join-Path $zipRoot 'valid-right.zip'
    $validEntries = @(
        [pscustomobject]@{ Name = 'lib/'; Content = '' },
        [pscustomobject]@{ Name = 'lib/app.txt'; Content = 'same bytes' }
    )
    New-Zip $validLeft $validEntries
    New-Zip $validRight $validEntries
    $validComparison = Join-Path $zipRoot 'valid-comparison.json'
    $compared = Invoke-Python @('-I', '-E', '-B', $comparator, $validLeft, $validRight, $validComparison)
    Assert-Fixture ($compared.ExitCode -eq 0 -and (Test-Path -LiteralPath $validComparison)) 'Equivalent safe archives compare successfully.'
    Assert-Fixture ((Get-Content -LiteralPath $validComparison -Raw | ConvertFrom-Json).equivalent -eq $true) 'Equivalent archive result is explicit.'

    $unsafeArchives = @(
        @{ Name = 'traversal'; Entries = @([pscustomobject]@{ Name = '../evil.txt'; Content = 'x' }) },
        @{ Name = 'rooted'; Entries = @([pscustomobject]@{ Name = '/evil.txt'; Content = 'x' }) },
        @{ Name = 'ads'; Entries = @([pscustomobject]@{ Name = 'safe.txt:stream'; Content = 'x' }) },
        @{ Name = 'case-collision'; Entries = @([pscustomobject]@{ Name = 'A.txt'; Content = 'x' }, [pscustomobject]@{ Name = 'a.TXT'; Content = 'y' }) },
        @{ Name = 'file-directory-alias'; Entries = @([pscustomobject]@{ Name = 'node'; Content = 'x' }, [pscustomobject]@{ Name = 'node/'; Content = '' }) },
        @{ Name = 'parent-file'; Entries = @([pscustomobject]@{ Name = 'parent'; Content = 'x' }, [pscustomobject]@{ Name = 'parent/child.txt'; Content = 'y' }) }
    )
    foreach ($case in $unsafeArchives) {
        $unsafeZip = Join-Path $zipRoot ("unsafe-$($case.Name).zip")
        New-Zip $unsafeZip $case.Entries
        $unsafeResult = Invoke-Python @('-I', '-E', '-B', $comparator, $unsafeZip, $validRight, (Join-Path $zipRoot ("unsafe-$($case.Name).json")))
        Assert-Fixture ($unsafeResult.ExitCode -ne 0 -and $unsafeResult.Output -match 'archive entry|duplicate|alias|parent') "Unsafe archive $($case.Name) is rejected before comparison."
    }

    $fixtureText = Get-Content -LiteralPath (Join-Path $lifecycleRoot 'fixtures\planner-state.v1.json') -Raw
    $fixture = $fixtureText | ConvertFrom-Json
    Assert-Fixture ($fixture.applicationVersion -ceq '0.1.7' -and $fixture.alchemy.alchemyMastery -eq 1234) 'Maintained Planner migration fixture remains explicit and synthetic.'
    Assert-Fixture ($fixtureText -notmatch '(?i)(?:[A-Z]:[\\/](?:Users|Codex)[\\/]|cookie|credential|browser.profile|session-import)') 'Maintained fixture has no private path or credential/profile marker.'

    Write-Host "PASS: $script:assertions release-plan/lifecycle assertions on PowerShell $($PSVersionTable.PSVersion)."
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixtureRoot)
    if ($resolved.StartsWith($tempParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolved) -match '^bsl-release-plan-lifecycle-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
    }
    else { throw 'Refusing cleanup outside the validated release-plan/lifecycle fixture directory.' }
}
