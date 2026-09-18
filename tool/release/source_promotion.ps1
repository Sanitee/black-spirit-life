# Reviewed, file-level source promotion only. No builds, Git mutations, rollback
# rotation, privacy-policy inference, deletion, or publication happens here.
. (Join-Path $PSScriptRoot 'source_inventory.ps1')

function Assert-ReleasePromotionHash {
    param([string]$Value)
    if ($Value -cnotmatch '^[A-Fa-f0-9]{64}$') { throw 'Expected a complete SHA-256 fingerprint.' }
    return $Value.ToUpperInvariant()
}

function Resolve-ReleasePromotionPath {
    param([string]$Path, [ValidateSet('Directory', 'File', 'NewDirectory')][string]$Kind)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:[\\/]' -or
        $Path -match '[*?]') { throw 'Promotion requires an absolute local filesystem path.' }
    # Validate the supplied spelling before GetFullPath can normalize aliases.
    $null = ConvertTo-ReleasePromotionRelativePath $Path.Substring(3)
    $resolved = [IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
    if (($resolved + '\') -eq [IO.Path]::GetPathRoot($resolved)) { throw 'A drive root is not a promotion target.' }
    $exists = $true
    try { $attributes = [IO.File]::GetAttributes($resolved) }
    catch [IO.FileNotFoundException] { $exists = $false }
    catch [IO.DirectoryNotFoundException] { $exists = $false }
    if ($Kind -eq 'NewDirectory') {
        if ($exists) { throw 'Promotion output already exists; it will not be overwritten.' }
    }
    elseif (-not $exists) { throw "Required promotion $Kind is missing." }
    elseif (($Kind -eq 'Directory') -ne (($attributes -band [IO.FileAttributes]::Directory) -ne 0)) {
        throw "Expected an ordinary promotion $Kind."
    }
    $current = $resolved
    if (-not $exists) { $current = [IO.Path]::GetDirectoryName($resolved) }
    while (-not [string]::IsNullOrEmpty($current)) {
        $attributes = [IO.File]::GetAttributes($current)
        if (($attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Device)) -ne 0) {
            throw 'Promotion paths and their ancestors cannot be reparse points or devices.'
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
    return $resolved
}

function ConvertTo-ReleasePromotionRelativePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or
        $Path -match '[\x00-\x1f<>:"|?*]') { throw 'Expected an exact, safe relative promotion path.' }
    $relative = $Path.Replace('\', '/')
    foreach ($part in $relative.Split('/')) {
        if ($part -in @('', '.', '..') -or $part -match '[. ]$' -or
            $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
            throw 'Promotion paths cannot contain traversal, aliases, or reserved names.'
        }
    }
    return $relative
}

function Assert-ReleasePromotionSeparateRoots {
    param([string[]]$Roots)
    for ($left = 0; $left -lt $Roots.Count; $left++) {
        for ($right = $left + 1; $right -lt $Roots.Count; $right++) {
            if ($Roots[$left].Equals($Roots[$right], [StringComparison]::OrdinalIgnoreCase) -or
                $Roots[$left].StartsWith($Roots[$right] + '\', [StringComparison]::OrdinalIgnoreCase) -or
                $Roots[$right].StartsWith($Roots[$left] + '\', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Source, overlay, and output roots must not overlap.'
            }
        }
    }
}

function Assert-ReleasePromotionProperties {
    param($Value, [string[]]$Names)
    if ($Value -isnot [pscustomobject]) { throw 'Promotion plan entries must be JSON objects.' }
    $actual = @($Value.PSObject.Properties.Name)
    if ($actual.Count -ne $Names.Count -or @($actual | Where-Object { $_ -cnotin $Names }).Count -ne 0) {
        throw 'Promotion plan has missing or unsupported properties.'
    }
}

function Read-ReleasePromotionPlan {
    param([string]$PlanPath, [string]$ExpectedPlanSha256)
    $path = Resolve-ReleasePromotionPath $PlanPath File
    $expected = Assert-ReleasePromotionHash $ExpectedPlanSha256
    $bytes = [IO.File]::ReadAllBytes($path)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $actual = [BitConverter]::ToString($hasher.ComputeHash($bytes)).Replace('-', '') }
    finally { $hasher.Dispose() }
    if ($actual -cne $expected) { throw 'Reviewed promotion plan SHA-256 does not match.' }
    $plan = [Text.UTF8Encoding]::new($false, $true).GetString($bytes) | ConvertFrom-Json
    Assert-ReleasePromotionProperties $plan @('schemaVersion', 'approvalReference', 'pruneDirectories', 'omitFiles', 'replaceFiles', 'addFiles')
    if (($plan.schemaVersion -isnot [int] -and $plan.schemaVersion -isnot [long]) -or $plan.schemaVersion -ne 1) {
        throw 'Unsupported promotion plan schemaVersion; expected integer 1.'
    }
    if ($plan.approvalReference -isnot [string] -or [string]::IsNullOrWhiteSpace($plan.approvalReference)) {
        throw 'Promotion plan must identify its explicit approval/review.'
    }
    $targets = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($category in @('pruneDirectories', 'omitFiles', 'replaceFiles', 'addFiles')) {
        if ($plan.$category -isnot [array]) { throw 'Promotion plan collections must be explicit JSON arrays.' }
        foreach ($entry in $plan.$category) {
            $properties = @('path', 'reason')
            if ($category -in @('omitFiles', 'replaceFiles')) { $properties += 'expectedSha256' }
            if ($category -in @('replaceFiles', 'addFiles')) { $properties += @('overlayPath', 'overlaySha256') }
            Assert-ReleasePromotionProperties $entry $properties
            if ($entry.path -isnot [string] -or $entry.reason -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.reason)) {
                throw 'Every promotion change needs an exact path and reviewed reason.'
            }
            $entry.path = ConvertTo-ReleasePromotionRelativePath $entry.path
            if (-not $targets.Add($entry.path)) { throw 'Promotion plan has duplicate/case-colliding targets.' }
            if ($category -in @('omitFiles', 'replaceFiles')) {
                $entry.expectedSha256 = Assert-ReleasePromotionHash $entry.expectedSha256
            }
            if ($category -in @('replaceFiles', 'addFiles')) {
                $entry.overlayPath = ConvertTo-ReleasePromotionRelativePath $entry.overlayPath
                $entry.overlaySha256 = Assert-ReleasePromotionHash $entry.overlaySha256
            }
        }
    }
    foreach ($prune in $plan.pruneDirectories) {
        foreach ($target in $targets) {
            if ($target.StartsWith($prune.path + '/', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Promotion plan paths cannot overlap a pruned directory.'
            }
        }
    }
    return [pscustomobject]@{ Path = $path; Sha256 = $actual; Plan = $plan }
}

function Get-ReleasePromotionFingerprint {
    param([object[]]$Entries)
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $header = [Text.Encoding]::UTF8.GetBytes("release-promotion-inventory-v1`n")
        $null = $hash.TransformBlock($header, 0, $header.Length, $header, 0)
        foreach ($entry in $Entries) {
            $encodedPath = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($entry.path))
            $line = $encodedPath + "`t" + ([long]$entry.bytes).ToString([Globalization.CultureInfo]::InvariantCulture) + "`t" + $entry.sha256 + "`n"
            $block = [Text.Encoding]::UTF8.GetBytes($line)
            $null = $hash.TransformBlock($block, 0, $block.Length, $block, 0)
        }
        $null = $hash.TransformFinalBlock([byte[]]@(), 0, 0)
        return [BitConverter]::ToString($hash.Hash).Replace('-', '')
    }
    finally { $hash.Dispose() }
}

function Get-ReleasePromotionTree {
    param([string]$Root, [object[]]$PruneDirectories = @())
    $pattern = (@($PruneDirectories | ForEach-Object { '^' + [regex]::Escape($_.path) + '/' }) -join '|')
    $inventory = Get-ReleaseSourceInventory -RootPath $Root -ExcludedPathPattern $pattern
    $entries = [Collections.Generic.List[object]]::new()
    $total = 0L
    foreach ($relative in $inventory.FilePaths) {
        $null = ConvertTo-ReleasePromotionRelativePath $relative
        $path = Resolve-ReleasePromotionPath (Join-Path $Root $relative) File
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $hash = [Security.Cryptography.SHA256]::Create()
        try {
            $length = $stream.Length
            $digest = [BitConverter]::ToString($hash.ComputeHash($stream)).Replace('-', '')
        }
        finally { $hash.Dispose(); $stream.Dispose() }
        $entries.Add([pscustomobject][ordered]@{ path = $relative; bytes = $length; sha256 = $digest })
        $total += $length
    }
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        root = $Root
        files = $entries.Count
        bytes = $total
        fingerprintSha256 = Get-ReleasePromotionFingerprint $entries.ToArray()
        entries = @($entries.ToArray())
        discovery = $inventory.Metrics
    }
}

function Get-ReleasePromotionContext {
    param([string]$SourceRoot, [string]$OverlayRoot, [string]$PlanPath, [string]$ExpectedPlanSha256)
    $source = Resolve-ReleasePromotionPath $SourceRoot Directory
    $overlay = Resolve-ReleasePromotionPath $OverlayRoot Directory
    Assert-ReleasePromotionSeparateRoots @($source, $overlay)
    $review = Read-ReleasePromotionPlan $PlanPath $ExpectedPlanSha256
    $sourceTree = Get-ReleasePromotionTree $source $review.Plan.pruneDirectories
    $overlayTree = Get-ReleasePromotionTree $overlay
    return [pscustomobject]@{ Review = $review; Source = $sourceTree; Overlay = $overlayTree }
}

function Get-ReleasePromotionInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$OverlayRoot,
        [Parameter(Mandatory = $true)][string]$PlanPath,
        [Parameter(Mandatory = $true)][string]$ExpectedPlanSha256
    )
    $context = Get-ReleasePromotionContext @PSBoundParameters
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        purpose = 'promotion-review-only'
        planSha256 = $context.Review.Sha256
        approvalReference = $context.Review.Plan.approvalReference
        pruneDirectories = @($context.Review.Plan.pruneDirectories)
        source = $context.Source
        overlay = $context.Overlay
    }
}

function Copy-ReleasePromotionFile {
    param([string]$From, [string]$To)
    $null = Resolve-ReleasePromotionPath $From File
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($To))
    $null = Resolve-ReleasePromotionPath ([IO.Path]::GetDirectoryName($To)) Directory
    [IO.File]::Copy($From, $To, $false)
}

function Write-ReleasePromotionJson {
    param([string]$Path, $Value)
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 24))
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length) }
    finally { $stream.Dispose() }
}

function Invoke-ReleaseSourcePromotion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$OverlayRoot,
        [Parameter(Mandatory = $true)][string]$PlanPath,
        [Parameter(Mandatory = $true)][string]$ExpectedPlanSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedSourceFingerprint,
        [Parameter(Mandatory = $true)][string]$OutputRoot
    )
    $started = [DateTime]::UtcNow
    $output = Resolve-ReleasePromotionPath $OutputRoot NewDirectory
    $source = Resolve-ReleasePromotionPath $SourceRoot Directory
    $overlay = Resolve-ReleasePromotionPath $OverlayRoot Directory
    Assert-ReleasePromotionSeparateRoots @($source, $overlay, $output)
    $expectedSource = Assert-ReleasePromotionHash $ExpectedSourceFingerprint
    $context = Get-ReleasePromotionContext $source $overlay $PlanPath $ExpectedPlanSha256
    if ($context.Source.fingerprintSha256 -cne $expectedSource) { throw 'Approved source fingerprint does not match the complete current source.' }
    $plan = $context.Review.Plan
    $sourceMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    $overlayMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    $copies = [Collections.Generic.SortedDictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($entry in $context.Source.entries) {
        $sourceMap.Add($entry.path, $entry)
        $copies.Add($entry.path, [pscustomobject]@{ Root = $source; Relative = $entry.path; Entry = $entry })
    }
    foreach ($entry in $context.Overlay.entries) { $overlayMap.Add($entry.path, $entry) }
    $changes = [Collections.Generic.List[object]]::new()
    foreach ($category in @('omitFiles', 'replaceFiles', 'addFiles')) {
        foreach ($entry in $plan.$category) {
            $before = $null
            $after = $null
            if ($category -eq 'addFiles') {
                if ($sourceMap.ContainsKey($entry.path)) { throw "Added file already exists in source: $($entry.path)" }
            }
            else {
                if (-not $sourceMap.ContainsKey($entry.path) -or $sourceMap[$entry.path].sha256 -cne $entry.expectedSha256) {
                    throw "File-level source hash guard failed: $($entry.path)"
                }
                $before = $sourceMap[$entry.path]
                if ($before.path -cne $entry.path) { throw 'Promotion change path casing must match the source inventory.' }
                $null = $copies.Remove($entry.path)
            }
            if ($category -ne 'omitFiles') {
                if (-not $overlayMap.ContainsKey($entry.overlayPath) -or $overlayMap[$entry.overlayPath].sha256 -cne $entry.overlaySha256) {
                    throw "File-level overlay hash guard failed: $($entry.overlayPath)"
                }
                $input = $overlayMap[$entry.overlayPath]
                if ($input.path -cne $entry.overlayPath) { throw 'Overlay path casing must match its inventory.' }
                $after = [pscustomobject][ordered]@{ path = $entry.path; bytes = $input.bytes; sha256 = $input.sha256 }
                $copies.Add($entry.path, [pscustomobject]@{ Root = $overlay; Relative = $entry.overlayPath; Entry = $after })
            }
            $changes.Add([pscustomobject][ordered]@{ action = $category; path = $entry.path; reason = $entry.reason; before = $before; after = $after })
        }
    }
    # Reject file/directory conflicts and aliases before any staging write.
    $candidatePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $copies.Keys) {
        if (-not $candidatePaths.Add($path)) { throw 'Candidate has a case/path collision.' }
    }
    foreach ($path in $copies.Keys) {
        $parent = $path
        while ($parent.Contains('/')) {
            $parent = $parent.Substring(0, $parent.LastIndexOf('/'))
            if ($candidatePaths.Contains($parent)) { throw 'Candidate file/directory paths collide.' }
        }
    }
    $expectedEntries = @($copies.Values | ForEach-Object { $_.Entry })
    $expectedCandidate = Get-ReleasePromotionFingerprint $expectedEntries
    $stage = Join-Path ([IO.Path]::GetDirectoryName($output)) ('.promotion-staging-' + [Guid]::NewGuid().ToString('N'))
    $null = Resolve-ReleasePromotionPath $stage NewDirectory
    Assert-ReleasePromotionSeparateRoots @($source, $overlay, $output, $stage)
    $null = [IO.Directory]::CreateDirectory($stage)
    try {
        $stagedSource = Join-Path $stage 'source'
        $null = [IO.Directory]::CreateDirectory($stagedSource)
        foreach ($path in $copies.Keys) {
            $copy = $copies[$path]
            Copy-ReleasePromotionFile (Join-Path $copy.Root $copy.Relative) (Join-Path $stagedSource $path)
        }
        $candidate = Get-ReleasePromotionTree $stagedSource
        if ($candidate.fingerprintSha256 -cne $expectedCandidate) { throw 'Staged candidate file set or content does not match the reviewed promotion.' }
        $finalSource = Get-ReleasePromotionTree $source $plan.pruneDirectories
        if ($finalSource.fingerprintSha256 -cne $context.Source.fingerprintSha256) { throw 'Source changed during promotion; candidate cannot be accepted.' }
        $finalOverlay = Get-ReleasePromotionTree $overlay
        if ($finalOverlay.fingerprintSha256 -cne $context.Overlay.fingerprintSha256) { throw 'Overlay changed during promotion; candidate cannot be accepted.' }
        $null = Read-ReleasePromotionPlan $context.Review.Path $context.Review.Sha256
        $null = Resolve-ReleasePromotionPath $output NewDirectory
        $null = Resolve-ReleasePromotionPath $stage Directory
        $candidate.root = Join-Path $output 'source'
        $report = [pscustomobject][ordered]@{
            schemaVersion = 1
            status = 'Passed'
            isReleaseVerification = $false
            startedAtUtc = $started.ToString('o')
            verifiedAtUtc = [DateTime]::UtcNow.ToString('o')
            outputRoot = $output
            approvalReference = $plan.approvalReference
            planSha256 = $context.Review.Sha256
            plan = $plan
            source = $finalSource
            overlay = $finalOverlay
            candidate = $candidate
            changes = @($changes.ToArray())
            sourceAndOverlayStable = $true
            previousOutputsModified = $false
        }
        Write-ReleasePromotionJson (Join-Path $stage 'promotion-report.json') $report
        # Only a fully verified new tree is exposed. Directory.Move never replaces
        # an existing candidate. A failure retains staging and failure evidence.
        [IO.Directory]::Move($stage, $output)
        return $report
    }
    catch {
        $failure = $_
        if ([IO.Directory]::Exists($stage)) {
            $null = Resolve-ReleasePromotionPath $stage Directory
            Write-ReleasePromotionJson (Join-Path $stage 'promotion-failure.json') ([ordered]@{
                schemaVersion = 1; status = 'Failed'; outputRoot = $output
                failedAtUtc = [DateTime]::UtcNow.ToString('o'); stagedOutputRetained = $true
            })
        }
        throw "Promotion failed; staging retained at '$stage'. $($failure.Exception.Message)"
    }
}
