# Explicit same-candidate retry only. Not an incremental build cache, release
# acceptance, or permission to reuse a different source/version/toolchain.
. (Join-Path $PSScriptRoot 'verified_input_cache.ps1')
. (Join-Path $PSScriptRoot 'source_inventory.ps1')

function Open-ReleaseSourceBuildLock {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)
    $project = Assert-ReleaseOrdinaryPath -Path $ProjectRoot
    if (-not (Test-Path -LiteralPath $project -PathType Container)) { throw 'Builder source directory is missing.' }
    # All plans for this checkout share build/windows. Output-directory names
    # must never partition ownership of that shared compiler/reset target.
    $buildRoot = Assert-ReleaseOrdinaryPath -Path (Join-Path $project 'build')
    $null = [IO.Directory]::CreateDirectory($buildRoot)
    $lockPath = Assert-ReleaseOrdinaryPath -Path (Join-Path $buildRoot 'release-builder.lock')
    try { return [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
    catch { throw 'Another candidate builder owns this source; no competing build was started.' }
}

function Get-CheckpointObjectHash {
    param([Parameter(Mandatory = $true)]$Value)
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Value | ConvertTo-Json -Depth 20 -Compress))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Get-CheckpointGeneratedPathPattern {
    # OCR's pinned producer uses the SDK-default intermediate directories.
    # These two exact paths are generated; unrelated assets/bin remain inputs.
    return '(?i)^(?:\.git|\.dart_tool|build)(?:/|$)|^windows/flutter/ephemeral(?:/|$)|^windows/storage_ocr/BlackSpiritStorageOcr/(?:bin|obj)(?:/|$)'
}

function Get-CheckpointTree {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Exclude = '')
    $root = Assert-ReleaseOrdinaryPath -Path $Path
    $inventory = Get-ReleaseSourceInventory -RootPath $root -ExcludedPathPattern $Exclude
    $records = @(
        for ($i = 0; $i -lt $inventory.FilePaths.Count; $i++) {
            $item = Get-Item -LiteralPath $inventory.Files[$i].FullName -Force
            [ordered]@{ path = $inventory.FilePaths[$i]; bytes = $item.Length
                sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash }
        }
    )
    $value = [ordered]@{ directories = @($inventory.DirectoryPaths); files = $records }
    [pscustomobject]@{ Root = $root; Inventory = $value; Fingerprint = Get-CheckpointObjectHash $value }
}

function Assert-CheckpointDisjoint {
    param([string]$Left, [string]$Right)
    $a = [IO.Path]::GetFullPath($Left).TrimEnd('\', '/')
    $b = [IO.Path]::GetFullPath($Right).TrimEnd('\', '/')
    if ($a.Equals($b, [StringComparison]::OrdinalIgnoreCase) -or
        $a.StartsWith($b + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $b.StartsWith($a + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Checkpoint input and output roots must not overlap.'
    }
}

function Get-ReleaseBuildRetryContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$ReleasePlanSha256,
        [Parameter(Mandatory = $true)][string]$ProfilePath,
        [Parameter(Mandatory = $true)][string]$ApprovedProfileSha256,
        [Parameter(Mandatory = $true)][Collections.IDictionary]$Tools,
        [Parameter(Mandatory = $true)][string[]]$BuildArguments,
        [object[]]$RequiredExternalInputs = @(),
        $NativePrerequisiteEvidence = $null
    )
    foreach ($hash in @($ReleasePlanSha256, $ApprovedProfileSha256)) {
        if ($hash -cnotmatch '^[A-F0-9]{64}$') { throw 'Checkpoint requires reviewed uppercase SHA-256 identities.' }
    }
    $profileFile = Assert-ReleaseOrdinaryPath -Path $ProfilePath
    if ((Get-FileHash -LiteralPath $profileFile -Algorithm SHA256).Hash -cne $ApprovedProfileSha256) {
        throw 'Build-input profile changed from its reviewed identity.'
    }
    $profile = Get-Content -LiteralPath $profileFile -Raw | ConvertFrom-Json
    if (($profile.schemaVersion -isnot [int] -and $profile.schemaVersion -isnot [long]) -or $profile.schemaVersion -ne 1 -or
        $profile.purpose -cne 'same-candidate-build-retry' -or
        [string]::IsNullOrWhiteSpace($profile.approvalReference) -or
        $profile.completeExternalInputsReviewed -isnot [bool] -or
        -not $profile.completeExternalInputsReviewed -or $profile.inputTrees -isnot [array] -or
        $profile.inputFiles -isnot [array]) {
        throw 'Build-input profile must explicitly review the complete external build inputs.'
    }
    $requiredRoles = @('flutter-sdk', 'native-toolchain', 'windows-sdk', 'dotnet-sdk', 'package-cache')
    $seenRoles = @{}
    $trees = [Collections.Generic.List[object]]::new()
    foreach ($entry in $profile.inputTrees) {
        if ($entry.role -isnot [string] -or $entry.role -cnotmatch '^[a-z][a-z0-9-]+$' -or
            $entry.path -isnot [string] -or -not [IO.Path]::IsPathRooted($entry.path)) {
            throw 'Build-input tree requires an explicit role and absolute directory.'
        }
        $treeRoot = Assert-ReleaseOrdinaryPath -Path $entry.path
        Assert-CheckpointDisjoint $treeRoot $ProjectRoot
        foreach ($broad in @([IO.Path]::GetPathRoot($treeRoot), $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA)) {
            if (-not [string]::IsNullOrWhiteSpace($broad) -and
                $treeRoot.TrimEnd('\', '/').Equals($broad.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Build-input trees must name specific toolchain/package directories, never broad personal/drive roots.'
            }
        }
        $tree = Get-CheckpointTree -Path $treeRoot
        # No caller-supplied exclusions: new/hidden inputs and changes are visible.
        $trees.Add([ordered]@{ role = $entry.role; path = $tree.Root; fingerprint = $tree.Fingerprint })
        $seenRoles[$entry.role] = $true
    }
    foreach ($role in $requiredRoles) {
        if (-not $seenRoles.ContainsKey($role)) { throw "Build-input profile is missing the $role tree." }
    }
    $coverage = [Collections.Generic.List[object]]::new()
    foreach ($inputPath in $RequiredExternalInputs) { $coverage.Add($inputPath) }
    foreach ($mapping in @(@('flutter','flutter-sdk'), @('cmake','native-toolchain'), @('dotnet','dotnet-sdk'))) {
        if ($Tools.Contains($mapping[0])) { $coverage.Add([pscustomobject]@{ role = $mapping[1]; path = $Tools[$mapping[0]] }) }
    }
    if ($Tools.Contains('flutter')) {
        $coverage.Add([pscustomobject]@{ role = 'flutter-sdk'; path = Split-Path -Parent (Split-Path -Parent $Tools['flutter']) })
    }
    $configPath = Join-Path $ProjectRoot '.dart_tool/package_config.json'
    $null = Assert-ReleaseOrdinaryPath -Path $configPath
    $packageConfig = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if ($packageConfig.packages -isnot [array] -or $packageConfig.packages.Count -eq 0) {
        throw 'Checkpoint needs the actual populated dependency configuration.'
    }
    foreach ($package in $packageConfig.packages) {
        $uri = [Uri]::new([Uri]::new($configPath), [string]$package.rootUri)
        if (-not $uri.IsFile -or $uri.IsUnc -or $uri.Query -or $uri.Fragment) { throw 'Checkpoint package roots must be ordinary local directories.' }
        $packageRoot = (Assert-ReleaseOrdinaryPath -Path $uri.LocalPath).TrimEnd('\', '/')
        $candidateRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
        if ($packageRoot.Equals($candidateRoot, [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($packageRoot.StartsWith($candidateRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $relativePackage = $packageRoot.Substring($candidateRoot.Length + 1).Replace('\', '/')
            if ($relativePackage -match (Get-CheckpointGeneratedPathPattern)) {
                throw 'A local dependency is inside an excluded generated tree; build reuse is not supported for this layout.'
            }
            continue
        }
        # Flutter SDK packages are covered by the SDK role, all other external
        # dependencies must be within an explicitly inventoried external tree.
        $coverage.Add([pscustomobject]@{ role = '*'; path = $packageRoot })
    }
    foreach ($inputPath in $coverage) {
        $covered = $false
        $full = (Assert-ReleaseOrdinaryPath -Path ([string]$inputPath.path)).TrimEnd('\', '/')
        foreach ($tree in $trees) {
            $prefix = $tree.path.TrimEnd('\', '/')
            if (($inputPath.role -ceq '*' -or $tree.role -ceq $inputPath.role) -and
                ($full.Equals($prefix, [StringComparison]::OrdinalIgnoreCase) -or
                 $full.StartsWith($prefix + '\', [StringComparison]::OrdinalIgnoreCase))) { $covered = $true; break }
        }
        if (-not $covered) { throw 'Selected SDK/tool/package is not covered by the reviewed external-input profile.' }
    }
    $files = [Collections.Generic.List[object]]::new()
    foreach ($path in $profile.inputFiles) {
        if ($path -isnot [string] -or -not [IO.Path]::IsPathRooted($path)) { throw 'Build input files require absolute paths.' }
        $file = Assert-ReleaseOrdinaryPath -Path $path
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'Build input file is missing.' }
        $files.Add([ordered]@{ path = $file; sha256 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash })
    }
    # Exact checkout-owned generated roots only. An asset directory named bin,
    # obj or build is still a production input and must not disappear from keys.
    $source = Get-CheckpointTree -Path $ProjectRoot -Exclude (Get-CheckpointGeneratedPathPattern)
    $configs = [Collections.Generic.List[object]]::new()
    # Source generators/build caches are not build inputs. The actual prepared
    # dependency configurations and plugin graph are, even though Git ignores them.
    foreach ($relative in @('.dart_tool/package_config.json', '.flutter-plugins-dependencies')) {
        $path = Join-Path $source.Root $relative
        if (Test-Path -LiteralPath $path) {
            $null = Assert-ReleaseOrdinaryPath -Path $path
            $configs.Add([ordered]@{ path = $relative; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash })
        }
        elseif ($relative -eq '.dart_tool/package_config.json') { throw 'Prepared dependency configuration is required for build reuse.' }
    }
    $toolRecords = [Collections.Generic.List[object]]::new()
    foreach ($name in @($Tools.Keys | Sort-Object)) {
        $path = Assert-ReleaseOrdinaryPath -Path ([string]$Tools[$name])
        $toolRecords.Add([ordered]@{ name = $name; path = $path; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash })
    }
    $environment = [ordered]@{}
    $environmentValues = [Environment]::GetEnvironmentVariables('Process')
    foreach ($name in @($environmentValues.Keys | Sort-Object)) { $environment[[string]$name] = [string]$environmentValues[$name] }
    $value = [ordered]@{
        schemaVersion = 1; releasePlanSha256 = $ReleasePlanSha256
        inputProfileSha256 = $ApprovedProfileSha256; projectRoot = $source.Root
        sourceFingerprint = $source.Fingerprint; preparedConfigurations = @($configs.ToArray())
        externalTrees = @($trees.ToArray()); externalFiles = @($files.ToArray()); tools = @($toolRecords.ToArray())
        buildArguments = @($BuildArguments); shell = $PSVersionTable.PSVersion.ToString()
        nativePrerequisites = $NativePrerequisiteEvidence
        operatingSystem = [Environment]::OSVersion.VersionString
        # Do not write raw environment values/secrets into evidence.
        environmentSha256 = Get-CheckpointObjectHash $environment
    }
    if ((Get-FileHash -LiteralPath $profileFile -Algorithm SHA256).Hash -cne $ApprovedProfileSha256) {
        throw 'Build-input profile mutated while capturing context.'
    }
    [pscustomobject]@{ Fingerprint = Get-CheckpointObjectHash $value; Evidence = $value }
}

function Copy-CheckpointTree {
    param($Tree, [string]$Destination)
    $target = Assert-ReleaseOrdinaryPath -Path $Destination
    if (Test-Path -LiteralPath $target) { throw 'Checkpoint staging destination must be new.' }
    Assert-CheckpointDisjoint $Tree.Root $target
    $null = [IO.Directory]::CreateDirectory($target)
    foreach ($relative in $Tree.Inventory.directories) {
        $null = [IO.Directory]::CreateDirectory((Join-Path $target $relative))
    }
    foreach ($record in $Tree.Inventory.files) {
        [IO.File]::Copy((Join-Path $Tree.Root $record.path), (Join-Path $target $record.path), $false)
    }
    $copied = Get-CheckpointTree $target
    if ($copied.Fingerprint -cne $Tree.Fingerprint -or
        (Get-CheckpointTree $Tree.Root).Fingerprint -cne $Tree.Fingerprint) {
        throw 'Checkpoint payload changed during copy.'
    }
    return $copied
}

function New-ReleaseBundleCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BundlePath,
        [Parameter(Mandatory = $true)][string]$OutputRoot,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][switch]$ConfirmPayloadVerified
    )
    if (-not $ConfirmPayloadVerified -or $Context.Fingerprint -cnotmatch '^[A-F0-9]{64}$') { throw 'A passed payload/context is required.' }
    $root = Assert-ReleaseOrdinaryPath -Path $OutputRoot
    if (Test-Path -LiteralPath $root) { throw 'Checkpoint output must be new; existing evidence is never overwritten.' }
    $tree = Get-CheckpointTree $BundlePath
    if ($tree.Inventory.files.Count -eq 0) { throw 'Cannot checkpoint an empty bundle.' }
    Assert-CheckpointDisjoint $tree.Root $root
    $null = [IO.Directory]::CreateDirectory($root)
    $copy = Copy-CheckpointTree $tree (Join-Path $root 'bundle')
    $record = [ordered]@{
        schemaVersion = 1; purpose = 'verified-build-bundle-retry'; payloadVerificationPassed = $true
        isReleaseVerification = $false; createdAtUtc = [DateTime]::UtcNow.ToString('o')
        contextFingerprint = $Context.Fingerprint; context = $Context.Evidence
        bundleFingerprint = $copy.Fingerprint; bundle = $copy.Inventory
    }
    $path = Join-Path $root 'bundle-checkpoint.json'
    $partial = $path + '.partial'
    [IO.File]::WriteAllText($partial, ($record | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($partial, $path)
    [pscustomobject]@{ Path = $path; Sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        BundlePath = $copy.Root; Fingerprint = $copy.Fingerprint }
}

function Restore-ReleaseBundleCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ReceiptPath,
        [Parameter(Mandatory = $true)][string]$ApprovedReceiptSha256,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    $receipt = Assert-ReleaseOrdinaryPath -Path $ReceiptPath
    if ($ApprovedReceiptSha256 -cnotmatch '^[A-F0-9]{64}$' -or
        (Get-FileHash -LiteralPath $receipt -Algorithm SHA256).Hash -cne $ApprovedReceiptSha256) {
        throw 'Checkpoint receipt differs from its reviewed identity.'
    }
    $value = Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
    if (($value.schemaVersion -isnot [int] -and $value.schemaVersion -isnot [long]) -or $value.schemaVersion -ne 1 -or
        $value.purpose -cne 'verified-build-bundle-retry' -or
        $value.payloadVerificationPassed -isnot [bool] -or -not $value.payloadVerificationPassed -or
        $value.contextFingerprint -cne $Context.Fingerprint -or
        (Get-CheckpointObjectHash $value.context) -cne $Context.Fingerprint -or
        (Get-CheckpointObjectHash $value.bundle) -cne $value.bundleFingerprint) {
        throw 'Checkpoint context, schema or passed evidence does not match this build.'
    }
    $tree = Get-CheckpointTree (Join-Path (Split-Path -Parent $receipt) 'bundle')
    if ($tree.Fingerprint -cne $value.bundleFingerprint) { throw 'Checkpoint bundle was changed, truncated or injected with extra files.' }
    $copy = Copy-CheckpointTree $tree $Destination
    if ((Get-FileHash -LiteralPath $receipt -Algorithm SHA256).Hash -cne $ApprovedReceiptSha256) { throw 'Checkpoint receipt changed during restore.' }
    $copy
}
