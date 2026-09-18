$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $projectRoot 'tool\release\publish_verified_release.ps1')

$script:Assertions = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:Assertions++
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    $script:Assertions++
    if ($Actual -cne $Expected) {
        throw "Assertion failed: $Message. Expected '$Expected'; got '$Actual'."
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern, [string]$Message)
    $script:Assertions++
    try {
        & $Action
    }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            throw "Assertion failed: $Message. Unexpected error: $($_.Exception.Message)"
        }
        return
    }
    throw "Assertion failed: $Message. No exception was thrown."
}

function Write-TestBytes {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent
    }
    [System.IO.File]::WriteAllBytes(
        $Path,
        [System.Text.Encoding]::UTF8.GetBytes($Text)
    )
}

function New-ManifestFixture {
    param([string]$Root)

    $repository = 'ExampleOrg/black-spirit-life'
    $tag = 'v0.1.12'
    $commit = '1234567890abcdef1234567890abcdef12345678'
    $definitions = @(
        @{ role = 'themed-installer'; path = 'BlackSpiritLifeInstaller.exe'; content = 'installer-bytes' },
        @{ role = 'full-package'; path = 'feed\BlackSpiritLife.App-0.1.12-win-x64-stable-full.nupkg'; content = 'full-package-bytes' },
        @{ role = 'delta-package'; path = 'feed\BlackSpiritLife.App-0.1.12-win-x64-stable-delta.nupkg'; content = 'delta-package-bytes' },
        @{ role = 'update-feed'; path = 'feed\releases.win-x64-stable.json'; content = '{"Assets":[]}' }
    )
    $records = @()
    foreach ($definition in $definitions) {
        $path = Join-Path $Root $definition.path
        Write-TestBytes -Path $path -Text $definition.content
        $item = Get-Item -LiteralPath $path
        $records += [ordered]@{
            role = $definition.role
            path = $definition.path
            bytes = $item.Length
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
        }
    }
    $manifest = [ordered]@{
        schemaVersion = 2
        localOnly = $false
        publicCandidate = $true
        published = $false
        sourceTag = $tag
        sourceCommit = $commit
        updateSource = "https://github.com/$repository"
        publicUploadArtifacts = $records
        delta = [ordered]@{
            expected = $true
            generated = $true
            verificationRequiredBeforePublication = $true
        }
        remainingBlockers = @('reviewed outside the upload helper')
    }
    $manifestPath = Join-Path $Root 'public-candidate-manifest.json'
    [System.IO.File]::WriteAllText(
        $manifestPath,
        (($manifest | ConvertTo-Json -Depth 6) + "`r`n"),
        [System.Text.UTF8Encoding]::new($false)
    )
    $manifestHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash
    $approved = Read-ApprovedManifest `
        -Path $manifestPath `
        -ExpectedSha256 $manifestHash `
        -Repository $repository `
        -Tag $tag `
        -SourceCommit $commit
    return [pscustomobject]@{
        Approved = $approved
        ManifestPath = $manifestPath
        ManifestHash = $manifestHash
        Repository = $repository
        Tag = $tag
        Commit = $commit
    }
}

function New-RemoteAsset {
    param(
        [long]$Id,
        [string]$Name,
        [string]$Label,
        [long]$Bytes,
        [AllowNull()][string]$Sha256
    )
    return [pscustomobject]@{
        id = $Id
        name = $Name
        label = $Label
        size = $Bytes
        digest = if ($null -eq $Sha256) { $null } else { "sha256:$($Sha256.ToLowerInvariant())" }
        state = 'uploaded'
    }
}

function New-MockTransport {
    param(
        [Parameter(Mandatory = $true)]$Fixture,
        [object[]]$InitialAssets = @(),
        [switch]$FailFirstUploadAfterCommit,
        [switch]$AlwaysFailUpload,
        [int]$AlwaysFailStatusCode = 503,
        [string]$RemoteCommit
    )

    if ([string]::IsNullOrWhiteSpace($RemoteCommit)) {
        $RemoteCommit = $Fixture.Commit
    }
    $state = @{
        Assets = [System.Collections.ArrayList]::new()
        NextId = 9000L
        JsonCalls = 0
        UploadCalls = 0
        PatchCalls = 0
        DelayCalls = 0
        FailedAfterCommit = $false
        AlwaysFail = $AlwaysFailUpload.IsPresent
        AlwaysFailStatusCode = $AlwaysFailStatusCode
        FailFirstAfterCommit = $FailFirstUploadAfterCommit.IsPresent
        Mutations = [System.Collections.ArrayList]::new()
        Receipts = [System.Collections.ArrayList]::new()
    }
    foreach ($asset in $InitialAssets) { $null = $state.Assets.Add($asset) }

    $jsonRequest = {
        param($Request)
        $state.JsonCalls++
        switch ($Request.Kind) {
            'GetReleaseByTag' {
                return [pscustomobject]@{
                    id = 777L
                    tag_name = $Fixture.Tag
                    draft = $true
                    upload_url = "https://uploads.github.com/repos/$($Fixture.Repository)/releases/777/assets{?name,label}"
                }
            }
            'GetTagCommit' {
                return [pscustomobject]@{ sha = $RemoteCommit }
            }
            'GetReleaseAssets' {
                return @($state.Assets)
            }
            'PatchReleaseAsset' {
                $state.PatchCalls++
                $null = $state.Mutations.Add($Request.Method)
                $assetId = [long]([regex]::Match($Request.Uri, '/assets/([0-9]+)$').Groups[1].Value)
                $matches = @($state.Assets | Where-Object { [long]$_.id -eq $assetId })
                if ($matches.Count -ne 1) { throw "Mock could not find asset $assetId." }
                $matches[0].name = [string]$Request.Body.name
                $matches[0].label = [string]$Request.Body.label
                return $matches[0]
            }
            default { throw "Unexpected mock JSON request kind: $($Request.Kind)" }
        }
    }.GetNewClosure()

    $uploadRequest = {
        param($Request)
        $state.UploadCalls++
        $null = $state.Mutations.Add($Request.Method)
        if ($Request.Method -cne 'POST') { throw 'Mock upload was not POST.' }
        if ([long]$Request.Length -ne [long]$Request.Stream.Length) {
            throw 'Mock upload did not receive the known content length.'
        }
        if ((Get-Sha256HexFromStream $Request.Stream) -cne $Request.Sha256) {
            throw 'Mock upload stream did not match the accepted SHA-256.'
        }
        if ($state.AlwaysFail) {
            $failure = [System.Exception]::new('simulated transport failure')
            $failure.Data['StatusCode'] = $state.AlwaysFailStatusCode
            throw $failure
        }

        $asset = New-RemoteAsset `
            -Id $state.NextId `
            -Name $Request.Name `
            -Label $Request.Label `
            -Bytes $Request.Length `
            -Sha256 $Request.Sha256
        $state.NextId++
        $null = $state.Assets.Add($asset)
        if ($state.FailFirstAfterCommit -and -not $state.FailedAfterCommit) {
            $state.FailedAfterCommit = $true
            $failure = [System.Exception]::new('simulated uncertain HTTP 500 after server commit')
            $failure.Data['StatusCode'] = 500
            throw $failure
        }
        return $asset
    }.GetNewClosure()

    $delay = {
        $state.DelayCalls++
    }.GetNewClosure()
    $receipt = {
        param($Record)
        $copy = [pscustomobject]@{
            tag = $Record.tag
            releaseId = $Record.releaseId
            manifestSha256 = $Record.manifestSha256
            role = $Record.role
            name = $Record.name
            attempt = $Record.attempt
            status = $Record.status
            assetId = $Record.assetId
            bytes = $Record.bytes
            sha256 = $Record.sha256
            failureKind = $Record.failureKind
        }
        $null = $state.Receipts.Add($copy)
    }.GetNewClosure()
    return [pscustomobject]@{
        State = $state
        Json = $jsonRequest
        Upload = $uploadRequest
        Delay = $delay
        Receipt = $receipt
    }
}

$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$testRoot = Join-Path $tempBase ("bsl-publish-test-" + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot
$junctionPath = $null
try {
    # A correct existing asset is reused. Missing assets are uploaded with locked,
    # known-length streams. An uncertain 500 is recovered by inspecting the draft.
    $happyRoot = Join-Path $testRoot 'happy'
    $null = New-Item -ItemType Directory -Path $happyRoot
    $happyFixture = New-ManifestFixture -Root $happyRoot
    $installer = @($happyFixture.Approved.Artifacts | Where-Object Role -ceq 'themed-installer')[0]
    $existingInstaller = New-RemoteAsset 8001 $installer.Name 'old label' $installer.Bytes $installer.Sha256
    $happyTransport = New-MockTransport `
        -Fixture $happyFixture `
        -InitialAssets @($existingInstaller) `
        -FailFirstUploadAfterCommit
    $result = Invoke-VerifiedDraftAssetSync `
        -ApprovedManifest $happyFixture.Approved `
        -JsonRequest $happyTransport.Json `
        -UploadRequest $happyTransport.Upload `
        -Delay $happyTransport.Delay `
        -ReceiptWriter $happyTransport.Receipt `
        -MaximumAttempts 3
    Assert-Equal $result.status 'draft-assets-synchronized' 'happy path reports draft synchronization only'
    Assert-Equal $result.published $false 'helper never claims publication'
    Assert-Equal $happyTransport.State.UploadCalls 3 'only three missing assets are uploaded'
    Assert-Equal $happyTransport.State.Assets.Count 4 'draft ends with exactly four assets'
    Assert-True ($happyTransport.State.PatchCalls -ge 4) 'temporary names and stale label are normalized'
    Assert-True ($happyTransport.State.Mutations -cnotcontains 'DELETE') 'helper never deletes an asset'
    Assert-True ($happyTransport.State.Mutations -cnotcontains 'PUT') 'helper never creates or replaces a release'
    Assert-True (@($result.artifacts | Where-Object outcome -ceq 'recovered-uncertain-upload').Count -eq 1) 'uncertain success is inspected and recovered'
    Assert-True (@($happyTransport.State.Receipts | Where-Object status -ceq 'attempt-started').Count -eq 3) 'every upload attempt has a durable-start receipt'
    Assert-True (@($happyTransport.State.Receipts | Where-Object status -ceq 'recovered-uncertain-upload').Count -eq 1) 'uncertain success has a recovery receipt'
    foreach ($artifact in $happyFixture.Approved.Artifacts) {
        $remote = @($happyTransport.State.Assets | Where-Object name -ceq $artifact.Name)
        Assert-Equal $remote.Count 1 "one final asset exists for $($artifact.Role)"
        Assert-Equal ([string]$remote[0].digest) ("sha256:" + $artifact.Sha256.ToLowerInvariant()) "remote digest matches $($artifact.Role)"
        Assert-Equal ([long]$remote[0].size) $artifact.Bytes "remote size matches $($artifact.Role)"
    }

    # Local validation is completed for all four files before the first network read.
    $localRoot = Join-Path $testRoot 'local-mismatch'
    $null = New-Item -ItemType Directory -Path $localRoot
    $localFixture = New-ManifestFixture -Root $localRoot
    $delta = @($localFixture.Approved.Artifacts | Where-Object Role -ceq 'delta-package')[0]
    $bytes = [System.IO.File]::ReadAllBytes($delta.Path)
    $bytes[0] = $bytes[0] -bxor 1
    [System.IO.File]::WriteAllBytes($delta.Path, $bytes)
    $localTransport = New-MockTransport -Fixture $localFixture
    Assert-Throws {
        Invoke-VerifiedDraftAssetSync $localFixture.Approved $localTransport.Json `
            $localTransport.Upload $localTransport.Delay $localTransport.Receipt 2
    } 'Local artifact SHA-256 mismatch' 'tampered local bytes fail before network'
    Assert-Equal $localTransport.State.JsonCalls 0 'tampered local bytes cause zero network reads'
    Assert-Equal $localTransport.State.UploadCalls 0 'tampered local bytes cause zero uploads'

    # A GitHub asset without a digest is never reused, overwritten, or deleted.
    $digestRoot = Join-Path $testRoot 'missing-digest'
    $null = New-Item -ItemType Directory -Path $digestRoot
    $digestFixture = New-ManifestFixture -Root $digestRoot
    $digestInstaller = @($digestFixture.Approved.Artifacts | Where-Object Role -ceq 'themed-installer')[0]
    $digestless = New-RemoteAsset 8100 $digestInstaller.Name $digestInstaller.Label $digestInstaller.Bytes $null
    $digestTransport = New-MockTransport -Fixture $digestFixture -InitialAssets @($digestless)
    Assert-Throws {
        Invoke-VerifiedDraftAssetSync $digestFixture.Approved $digestTransport.Json `
            $digestTransport.Upload $digestTransport.Delay $digestTransport.Receipt 2
    } 'no trustworthy SHA-256 digest' 'missing remote digest fails closed'
    Assert-Equal $digestTransport.State.UploadCalls 0 'missing digest never triggers an upload'
    Assert-Equal $digestTransport.State.PatchCalls 0 'missing digest never triggers a patch'

    # Unrelated draft state is retained and causes a conflict instead of cleanup.
    $unrelatedRoot = Join-Path $testRoot 'unrelated'
    $null = New-Item -ItemType Directory -Path $unrelatedRoot
    $unrelatedFixture = New-ManifestFixture -Root $unrelatedRoot
    $unrelatedAsset = New-RemoteAsset 8200 'notes.txt' 'unrelated' 5 ('A' * 64)
    $unrelatedTransport = New-MockTransport -Fixture $unrelatedFixture -InitialAssets @($unrelatedAsset)
    Assert-Throws {
        Invoke-VerifiedDraftAssetSync $unrelatedFixture.Approved $unrelatedTransport.Json `
            $unrelatedTransport.Upload $unrelatedTransport.Delay $unrelatedTransport.Receipt 2
    } 'unrelated asset' 'unrelated remote state stops synchronization'
    Assert-Equal $unrelatedTransport.State.Assets.Count 1 'unrelated asset is retained'
    Assert-Equal $unrelatedTransport.State.UploadCalls 0 'unrelated state never triggers upload'
    Assert-Equal $unrelatedTransport.State.PatchCalls 0 'unrelated state never triggers mutation'

    # Retry count is bounded and each uncertain failure is inspected before retry.
    $retryRoot = Join-Path $testRoot 'bounded-retry'
    $null = New-Item -ItemType Directory -Path $retryRoot
    $retryFixture = New-ManifestFixture -Root $retryRoot
    $retryTransport = New-MockTransport -Fixture $retryFixture -AlwaysFailUpload
    Assert-Throws {
        Invoke-VerifiedDraftAssetSync $retryFixture.Approved $retryTransport.Json `
            $retryTransport.Upload $retryTransport.Delay $retryTransport.Receipt 2
    } 'Upload attempts were exhausted' 'upload failures stop at the configured bound'
    Assert-Equal $retryTransport.State.UploadCalls 2 'bounded retry performs exactly two attempts'
    Assert-Equal $retryTransport.State.DelayCalls 2 'each uncertain attempt is followed by inspection delay'
    Assert-Equal $retryTransport.State.Assets.Count 0 'failed uploads do not fabricate remote success'

    # The remote tag is rebound to the reviewed commit before any mutation.
    $sourceRoot = Join-Path $testRoot 'source-mismatch'
    $null = New-Item -ItemType Directory -Path $sourceRoot
    $sourceFixture = New-ManifestFixture -Root $sourceRoot
    $sourceTransport = New-MockTransport `
        -Fixture $sourceFixture `
        -RemoteCommit 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    Assert-Throws {
        Invoke-VerifiedDraftAssetSync $sourceFixture.Approved $sourceTransport.Json `
            $sourceTransport.Upload $sourceTransport.Delay $sourceTransport.Receipt 2
    } 'remote tag does not resolve' 'source identity mismatch fails closed'
    Assert-Equal $sourceTransport.State.UploadCalls 0 'source mismatch causes no upload'
    Assert-Equal $sourceTransport.State.PatchCalls 0 'source mismatch causes no patch'

    # All four remote identities are checked before even an earlier asset label
    # can be normalized. A conflict in the fourth record causes zero mutations.
    $preflightRoot = Join-Path $testRoot 'remote-preflight'
    $null = New-Item -ItemType Directory -Path $preflightRoot
    $preflightFixture = New-ManifestFixture -Root $preflightRoot
    $preflightAssets = @()
    $preflightId = 8300L
    foreach ($artifact in $preflightFixture.Approved.Artifacts) {
        $hash = if ($artifact.Role -ceq 'update-feed') { 'C' * 64 } else { $artifact.Sha256 }
        $label = if ($artifact.Role -ceq 'themed-installer') { 'stale label' } else { $artifact.Label }
        $preflightAssets += New-RemoteAsset $preflightId $artifact.Name $label $artifact.Bytes $hash
        $preflightId++
    }
    $preflightTransport = New-MockTransport -Fixture $preflightFixture -InitialAssets $preflightAssets
    Assert-Throws {
        Invoke-VerifiedDraftAssetSync $preflightFixture.Approved $preflightTransport.Json `
            $preflightTransport.Upload $preflightTransport.Delay $preflightTransport.Receipt 2
    } 'conflicting byte identity' 'all remote identities are checked before mutation'
    Assert-Equal $preflightTransport.State.UploadCalls 0 'later remote conflict causes no upload'
    Assert-Equal $preflightTransport.State.PatchCalls 0 'later remote conflict causes no earlier label patch'

    # Missing state is not interpreted as an uploaded GitHub asset.
    $stateRoot = Join-Path $testRoot 'missing-state'
    $null = New-Item -ItemType Directory -Path $stateRoot
    $stateFixture = New-ManifestFixture -Root $stateRoot
    $stateInstaller = @($stateFixture.Approved.Artifacts | Where-Object Role -ceq 'themed-installer')[0]
    $missingState = New-RemoteAsset 8400 $stateInstaller.Name $stateInstaller.Label $stateInstaller.Bytes $stateInstaller.Sha256
    $missingState.PSObject.Properties.Remove('state')
    $stateTransport = New-MockTransport -Fixture $stateFixture -InitialAssets @($missingState)
    Assert-Throws {
        Invoke-VerifiedDraftAssetSync $stateFixture.Approved $stateTransport.Json `
            $stateTransport.Upload $stateTransport.Delay $stateTransport.Receipt 2
    } 'not in uploaded state' 'missing remote state fails closed'
    Assert-Equal $stateTransport.State.UploadCalls 0 'missing state causes no upload'

    # Permanent HTTP failures are inspected once but never retried.
    $authRoot = Join-Path $testRoot 'nonretryable'
    $null = New-Item -ItemType Directory -Path $authRoot
    $authFixture = New-ManifestFixture -Root $authRoot
    $authTransport = New-MockTransport `
        -Fixture $authFixture `
        -AlwaysFailUpload `
        -AlwaysFailStatusCode 401
    Assert-Throws {
        Invoke-VerifiedDraftAssetSync $authFixture.Approved $authTransport.Json `
            $authTransport.Upload $authTransport.Delay $authTransport.Receipt 3
    } 'Non-retryable upload failure.*http-401' 'authentication failure is not retried'
    Assert-Equal $authTransport.State.UploadCalls 1 'nonretryable HTTP error performs one request'
    Assert-Equal $authTransport.State.DelayCalls 0 'nonretryable HTTP error has no retry delay'
    Assert-True (@($authTransport.State.Receipts | Where-Object status -ceq 'stopped-nonretryable').Count -eq 1) 'nonretryable stop is receipted'

    # Artifact paths cannot hide traversal or alternate data streams.
    foreach ($invalidPath in @(
        'feed\..\BlackSpiritLifeInstaller.exe',
        'BlackSpiritLifeInstaller.exe:payload'
    )) {
        $pathRoot = Join-Path $testRoot ("invalid-path-" + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $pathRoot
        $pathFixture = New-ManifestFixture -Root $pathRoot
        $manifestObject = Get-Content -Raw -LiteralPath $pathFixture.ManifestPath | ConvertFrom-Json
        @($manifestObject.publicUploadArtifacts | Where-Object role -ceq 'themed-installer')[0].path = $invalidPath
        [System.IO.File]::WriteAllText(
            $pathFixture.ManifestPath,
            (($manifestObject | ConvertTo-Json -Depth 6) + "`r`n"),
            [System.Text.UTF8Encoding]::new($false)
        )
        $pathHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $pathFixture.ManifestPath).Hash
        Assert-Throws {
            Read-ApprovedManifest $pathFixture.ManifestPath $pathHash `
                $pathFixture.Repository $pathFixture.Tag $pathFixture.Commit
        } 'invalid relative path' "invalid artifact path is rejected: $invalidPath"
    }

    # The manifest and every ancestor must also be ordinary paths. A junction in
    # the middle of an otherwise valid absolute path is rejected.
    $junctionTarget = Join-Path $testRoot 'junction-target'
    $null = New-Item -ItemType Directory -Path $junctionTarget
    $junctionFixture = New-ManifestFixture -Root $junctionTarget
    $junctionPath = Join-Path $testRoot 'manifest-junction'
    $null = New-Item -ItemType Junction -Path $junctionPath -Target $junctionTarget
    $junctionManifest = Join-Path $junctionPath 'public-candidate-manifest.json'
    Assert-Throws {
        Read-ApprovedManifest $junctionManifest $junctionFixture.ManifestHash `
            $junctionFixture.Repository $junctionFixture.Tag $junctionFixture.Commit
    } 'crosses a reparse point' 'intermediate junction is rejected'
    [System.IO.Directory]::Delete($junctionPath)
    $junctionPath = $null
    Assert-True (Test-Path -LiteralPath $junctionTarget -PathType Container) 'junction target is retained after link cleanup'

    # File-backed receipts contain only the bounded, sanitized attempt record.
    $receiptPath = Join-Path $testRoot 'receipts.jsonl'
    $receiptWriter = New-UploadReceiptWriter `
        -Path $receiptPath `
        -ApprovedManifest $happyFixture.Approved
    Write-ArtifactReceipt $receiptWriter $happyFixture.Approved $installer `
        777 1 'attempt-started'
    $receiptLines = @(Get-Content -LiteralPath $receiptPath)
    Assert-Equal $receiptLines.Count 1 'receipt is flushed as one JSON line'
    $receiptObject = $receiptLines[0] | ConvertFrom-Json
    Assert-Equal $receiptObject.role 'themed-installer' 'receipt identifies the artifact role'
    Assert-Equal $receiptObject.sha256 $installer.Sha256 'receipt records accepted artifact digest'
    Assert-Equal $receiptObject.manifestSha256 $happyFixture.ManifestHash 'receipt is attributed to the accepted manifest'
    Assert-True ($receiptLines[0] -notmatch 'Bearer|GITHUB_TOKEN|\\Users\\') 'receipt contains no token or machine path'
    Assert-Throws {
        New-UploadReceiptWriter $happyFixture.ManifestPath $happyFixture.Approved
    } 'cannot overwrite' 'receipt cannot append to the accepted manifest'
    Assert-Throws {
        New-UploadReceiptWriter $installer.Path $happyFixture.Approved
    } 'cannot overwrite' 'receipt cannot append to an accepted artifact'

    # Real PowerShell method calls wrap .NET timeouts. The retry classifier must
    # unwrap only the known reflection/invocation wrapper used by SendAsync.
    Add-Type -TypeDefinition @'
using System;
namespace BslPublisherFixture {
  public static class Thrower {
    public static void Timeout() { throw new TimeoutException("fixture timeout"); }
  }
}
'@
    $wrappedTimeout = $null
    try { [BslPublisherFixture.Thrower]::Timeout() }
    catch { $wrappedTimeout = Get-UploadFailureClassification $_ }
    Assert-True ($null -ne $wrappedTimeout) 'method invocation timeout is captured'
    Assert-Equal $wrappedTimeout.Transient $true 'wrapped .NET timeout is transient'
    Assert-Equal $wrappedTimeout.Kind 'TimeoutException' 'wrapped timeout reports its effective type'

    # The accepted manifest itself is a required immutable reviewed input.
    Assert-Throws {
        Read-ApprovedManifest $sourceFixture.ManifestPath ('B' * 64) `
            $sourceFixture.Repository $sourceFixture.Tag $sourceFixture.Commit
    } 'Approved manifest SHA-256 mismatch' 'wrong accepted-manifest digest is rejected'

    Write-Output "publish_verified_release_test.ps1: PASS ($script:Assertions assertions)"
}
finally {
    if ($null -ne $junctionPath -and (Test-Path -LiteralPath $junctionPath)) {
        [System.IO.Directory]::Delete($junctionPath)
    }
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    if (-not $resolvedTestRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetFileName($resolvedTestRoot) -cnotmatch '^bsl-publish-test-[0-9a-f]{32}$') {
        throw "Refusing to remove unexpected test path: $resolvedTestRoot"
    }
    if (Test-Path -LiteralPath $resolvedTestRoot) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
