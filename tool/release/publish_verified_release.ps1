[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$ApprovedManifestSha256,
    [string]$ExpectedRepository,
    [string]$ExpectedTag,
    [string]$ExpectedSourceCommit,
    [string]$ReceiptPath,
    [string]$GitHubToken = $env:GITHUB_TOKEN,
    [ValidateRange(1, 8)][int]$MaxUploadAttempts = 3,
    [ValidateRange(0, 60)][int]$RetryDelaySeconds = 2,
    [ValidateRange(10, 300)][int]$JsonTimeoutSeconds = 60,
    [ValidateRange(30, 1800)][int]$UploadTimeoutSeconds = 300,
    [switch]$ConfirmReviewedArtifactReadiness,
    [switch]$ConfirmDraftAssetUpload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'verified_input_cache.ps1')

$script:RequiredUploadRoles = @(
    'themed-installer',
    'full-package',
    'delta-package',
    'update-feed'
)
$script:RoleLabels = @{
    'themed-installer' = 'Black Spirit Life Installer'
    'full-package' = 'Automatic updater package - do not install manually'
    'delta-package' = 'Automatic update patch - do not install manually'
    'update-feed' = 'Automatic updater manifest - do not download manually'
}

function Get-Sha256HexFromBytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Get-Sha256HexFromStream {
    param([Parameter(Mandatory = $true)][System.IO.Stream]$Stream)

    $Stream.Position = 0
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $result = ([System.BitConverter]::ToString($sha.ComputeHash($Stream))).Replace('-', '')
        $Stream.Position = 0
        return $result
    }
    finally {
        $sha.Dispose()
    }
}

function Get-RequiredProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        throw "$Context is missing required property '$Name'."
    }
    return $property.Value
}

function Assert-HexSha256 {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ($Value -cnotmatch '^[0-9A-F]{64}$') {
        throw "$Context must be an uppercase 64-character SHA-256 value."
    }
}

function Get-ArtifactLabel {
    param([Parameter(Mandatory = $true)]$Record)

    $labelProperty = $Record.PSObject.Properties['label']
    if ($null -ne $labelProperty -and
        -not [string]::IsNullOrWhiteSpace([string]$labelProperty.Value)) {
        return [string]$labelProperty.Value
    }
    return [string]$script:RoleLabels[[string]$Record.role]
}

function Read-ApprovedManifest {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Tag,
        [Parameter(Mandatory = $true)][string]$SourceCommit
    )

    $expectedManifestHash = $ExpectedSha256.ToUpperInvariant()
    Assert-HexSha256 -Value $expectedManifestHash -Context 'Approved manifest SHA-256'
    if ($Repository -cnotmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})/[A-Za-z0-9._-]{1,100}$') {
        throw 'ExpectedRepository must be an exact OWNER/REPOSITORY identity.'
    }
    if ($Tag -cnotmatch '^v[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$') {
        throw 'ExpectedTag must be an explicit version tag such as v0.1.12.'
    }
    if ($SourceCommit -cnotmatch '^[0-9a-f]{40}$') {
        throw 'ExpectedSourceCommit must be an exact lowercase 40-character commit.'
    }

    $ordinaryManifestPath = Assert-ReleaseOrdinaryPath -Path $Path
    $manifestItem = Get-Item -LiteralPath $ordinaryManifestPath -Force -ErrorAction Stop
    if (-not $manifestItem.PSIsContainer -and
        ($manifestItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
        $manifestBytes = [System.IO.File]::ReadAllBytes($manifestItem.FullName)
    }
    else {
        throw 'The approved manifest must be one ordinary file, not a directory or reparse point.'
    }
    $actualManifestHash = Get-Sha256HexFromBytes -Bytes $manifestBytes
    if ($actualManifestHash -cne $expectedManifestHash) {
        throw "Approved manifest SHA-256 mismatch. Expected $expectedManifestHash; got $actualManifestHash."
    }

    try {
        $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
        $manifest = $utf8.GetString($manifestBytes) | ConvertFrom-Json
    }
    catch {
        throw "The approved manifest is not valid UTF-8 JSON: $($_.Exception.Message)"
    }

    if ([int](Get-RequiredProperty $manifest 'schemaVersion' 'Manifest') -ne 2 -or
        (Get-RequiredProperty $manifest 'localOnly' 'Manifest') -ne $false -or
        (Get-RequiredProperty $manifest 'publicCandidate' 'Manifest') -ne $true -or
        (Get-RequiredProperty $manifest 'published' 'Manifest') -ne $false) {
        throw 'The manifest is not an unpublished schema-2 public candidate.'
    }
    $delta = Get-RequiredProperty $manifest 'delta' 'Manifest'
    if ((Get-RequiredProperty $delta 'expected' 'Manifest delta') -ne $true -or
        (Get-RequiredProperty $delta 'generated' 'Manifest delta') -ne $true -or
        (Get-RequiredProperty $delta 'verificationRequiredBeforePublication' 'Manifest delta') -ne $true) {
        throw 'The manifest does not retain the required verified-delta contract.'
    }
    $expectedUpdateSource = "https://github.com/$Repository"
    if ([string](Get-RequiredProperty $manifest 'updateSource' 'Manifest') -cne $expectedUpdateSource -or
        [string](Get-RequiredProperty $manifest 'sourceTag' 'Manifest') -cne $Tag -or
        [string](Get-RequiredProperty $manifest 'sourceCommit' 'Manifest') -cne $SourceCommit) {
        throw 'The manifest repository, tag, or source commit does not match the reviewed identity.'
    }

    $records = @(Get-RequiredProperty $manifest 'publicUploadArtifacts' 'Manifest')
    if ($records.Count -ne $script:RequiredUploadRoles.Count) {
        throw 'The manifest must declare exactly four public upload artifacts.'
    }
    $manifestRoot = $manifestItem.Directory.FullName
    $rootPrefix = $manifestRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $artifacts = @()
    $seenRoles = @{}
    $seenNames = @{}
    foreach ($record in $records) {
        $role = [string](Get-RequiredProperty $record 'role' 'Upload artifact')
        if ($script:RequiredUploadRoles -cnotcontains $role -or $seenRoles.ContainsKey($role)) {
            throw "The manifest contains an unexpected or duplicate upload role: $role"
        }
        $seenRoles[$role] = $true

        $relativePath = [string](Get-RequiredProperty $record 'path' "Upload artifact $role")
        if ([string]::IsNullOrWhiteSpace($relativePath) -or
            [System.IO.Path]::IsPathRooted($relativePath) -or
            $relativePath.Contains(':') -or
            $relativePath -match '(^|[\\/])\.{1,2}([\\/]|$)') {
            throw "Upload artifact $role has an invalid relative path."
        }
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $manifestRoot $relativePath))
        if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Upload artifact $role escapes the accepted manifest directory."
        }
        $ordinaryArtifactPath = Assert-ReleaseOrdinaryPath -Path $fullPath
        $item = Get-Item -LiteralPath $ordinaryArtifactPath -Force -ErrorAction Stop
        if ($item.PSIsContainer -or
            ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Upload artifact $role is not one ordinary file."
        }

        $name = $item.Name
        if ($seenNames.ContainsKey($name)) {
            throw "The manifest maps multiple artifacts to remote asset name $name."
        }
        $seenNames[$name] = $true
        $expectedBytes = [long](Get-RequiredProperty $record 'bytes' "Upload artifact $role")
        if ($expectedBytes -le 0) {
            throw "Upload artifact $role has an invalid byte length."
        }
        $expectedHash = ([string](Get-RequiredProperty $record 'sha256' "Upload artifact $role")).ToUpperInvariant()
        Assert-HexSha256 -Value $expectedHash -Context "Upload artifact $role SHA-256"

        switch ($role) {
            'themed-installer' {
                if ($name -cnotmatch '\.exe$') { throw 'The installer upload must be an .exe.' }
            }
            'full-package' {
                if ($name -cnotmatch '-full\.nupkg$') { throw 'The full package has the wrong asset name.' }
            }
            'delta-package' {
                if ($name -cnotmatch '-delta\.nupkg$') { throw 'The delta package has the wrong asset name.' }
            }
            'update-feed' {
                if ($name -cnotmatch '^releases\.[A-Za-z0-9.-]+\.json$') { throw 'The update feed has the wrong asset name.' }
            }
        }
        $artifacts += [pscustomobject]@{
            Role = $role
            Path = $item.FullName
            Name = $name
            Label = Get-ArtifactLabel -Record $record
            Bytes = $expectedBytes
            Sha256 = $expectedHash
        }
    }
    foreach ($role in $script:RequiredUploadRoles) {
        if (-not $seenRoles.ContainsKey($role)) {
            throw "The manifest is missing required upload role $role."
        }
    }

    return [pscustomobject]@{
        Path = $manifestItem.FullName
        Sha256 = $actualManifestHash
        Repository = $Repository
        Tag = $Tag
        SourceCommit = $SourceCommit
        Manifest = $manifest
        Artifacts = $artifacts
    }
}

function Assert-AllLocalArtifacts {
    param([Parameter(Mandatory = $true)]$ApprovedManifest)

    # Every local byte set is opened without write/delete sharing and hashed before
    # the first network request. Uploads repeat this check on their own locked handle.
    foreach ($artifact in $ApprovedManifest.Artifacts) {
        $stream = [System.IO.File]::Open(
            $artifact.Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        try {
            if ($stream.Length -ne $artifact.Bytes) {
                throw "Local artifact size mismatch for $($artifact.Name)."
            }
            $actualHash = Get-Sha256HexFromStream -Stream $stream
            if ($actualHash -cne $artifact.Sha256) {
                throw "Local artifact SHA-256 mismatch for $($artifact.Name)."
            }
        }
        finally {
            $stream.Dispose()
        }
    }
}

function Get-ApiUri {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Suffix
    )
    return "https://api.github.com/repos/$Repository/$Suffix"
}

function ConvertTo-RemoteAsset {
    param([Parameter(Mandatory = $true)]$Asset)

    $digest = [string](Get-RequiredProperty $Asset 'digest' 'Remote release asset')
    if ($digest -cnotmatch '^sha256:([0-9a-fA-F]{64})$') {
        throw "Remote release asset '$([string]$Asset.name)' has no trustworthy SHA-256 digest."
    }
    $stateProperty = $Asset.PSObject.Properties['state']
    if ($null -eq $stateProperty -or [string]$stateProperty.Value -cne 'uploaded') {
        throw "Remote release asset '$([string]$Asset.name)' is not in uploaded state."
    }
    return [pscustomobject]@{
        Id = [long](Get-RequiredProperty $Asset 'id' 'Remote release asset')
        Name = [string](Get-RequiredProperty $Asset 'name' 'Remote release asset')
        Label = [string]$Asset.label
        Bytes = [long](Get-RequiredProperty $Asset 'size' 'Remote release asset')
        Sha256 = $Matches[1].ToUpperInvariant()
    }
}

function Get-VerifiedDraftContext {
    param(
        [Parameter(Mandatory = $true)]$ApprovedManifest,
        [Parameter(Mandatory = $true)][scriptblock]$JsonRequest,
        $ExpectedReleaseId = $null
    )

    $encodedTag = [System.Uri]::EscapeDataString($ApprovedManifest.Tag)
    $release = & $JsonRequest ([pscustomobject]@{
        Kind = 'GetReleaseByTag'
        Method = 'GET'
        Uri = Get-ApiUri $ApprovedManifest.Repository "releases/tags/$encodedTag"
        Body = $null
    })
    if ($null -eq $release -or
        [string](Get-RequiredProperty $release 'tag_name' 'Draft release') -cne $ApprovedManifest.Tag -or
        (Get-RequiredProperty $release 'draft' 'Draft release') -ne $true) {
        throw 'The reviewed tag does not resolve to an existing draft release.'
    }
    $releaseId = [long](Get-RequiredProperty $release 'id' 'Draft release')
    if ($null -ne $ExpectedReleaseId -and $releaseId -ne [long]$ExpectedReleaseId) {
        throw 'The draft release identity changed during synchronization.'
    }

    $commit = & $JsonRequest ([pscustomobject]@{
        Kind = 'GetTagCommit'
        Method = 'GET'
        Uri = Get-ApiUri $ApprovedManifest.Repository "commits/$encodedTag"
        Body = $null
    })
    if ($null -eq $commit -or
        [string](Get-RequiredProperty $commit 'sha' 'Tag commit') -cne $ApprovedManifest.SourceCommit) {
        throw 'The remote tag does not resolve to the reviewed source commit.'
    }

    $assetsResponse = & $JsonRequest ([pscustomobject]@{
        Kind = 'GetReleaseAssets'
        Method = 'GET'
        Uri = Get-ApiUri $ApprovedManifest.Repository "releases/$releaseId/assets?per_page=100"
        Body = $null
    })
    $assets = @($assetsResponse)
    if ($assets.Count -ge 100) {
        throw 'The draft contains too many assets for an exact bounded identity check.'
    }
    $remoteAssets = @()
    foreach ($asset in $assets) {
        $remoteAssets += ConvertTo-RemoteAsset -Asset $asset
    }

    $uploadTemplate = [string](Get-RequiredProperty $release 'upload_url' 'Draft release')
    $uploadBase = $uploadTemplate -replace '\{.*$', ''
    $expectedUploadBase = "https://uploads.github.com/repos/$($ApprovedManifest.Repository)/releases/$releaseId/assets"
    if ($uploadBase -cne $expectedUploadBase) {
        throw 'The draft release returned an unexpected upload endpoint.'
    }
    return [pscustomobject]@{
        ReleaseId = $releaseId
        UploadBase = $uploadBase
        Assets = $remoteAssets
    }
}

function Get-TemporaryAssetPrefix {
    param(
        [Parameter(Mandatory = $true)]$ApprovedManifest,
        [Parameter(Mandatory = $true)]$Artifact
    )
    return ".bsl-$($ApprovedManifest.Sha256.Substring(0, 12))-$($Artifact.Sha256.Substring(0, 12))-"
}

function Test-AssetMatchesArtifact {
    param(
        [Parameter(Mandatory = $true)]$RemoteAsset,
        [Parameter(Mandatory = $true)]$Artifact
    )
    return $RemoteAsset.Bytes -eq $Artifact.Bytes -and
        $RemoteAsset.Sha256 -ceq $Artifact.Sha256
}

function Get-UploadFailureClassification {
    param([Parameter(Mandatory = $true)]$ErrorRecord)

    $exception = $ErrorRecord.Exception
    $effectiveException = $exception
    if (($effectiveException -is [System.Management.Automation.MethodInvocationException] -or
        $effectiveException -is [System.Reflection.TargetInvocationException]) -and
        $null -ne $effectiveException.InnerException) {
        $effectiveException = $effectiveException.InnerException
    }
    elseif ($effectiveException -is [System.AggregateException] -and
        $effectiveException.InnerExceptions.Count -eq 1) {
        $effectiveException = $effectiveException.InnerExceptions[0]
    }
    $statusCode = $null
    if ($null -ne $exception -and $exception.Data.Contains('StatusCode')) {
        $statusCode = [int]$exception.Data['StatusCode']
    }
    elseif ($null -ne $effectiveException -and
        $effectiveException.Data.Contains('StatusCode')) {
        $statusCode = [int]$effectiveException.Data['StatusCode']
    }
    $transient = $false
    if ($null -ne $statusCode) {
        $transient = $statusCode -in @(408, 425, 429) -or $statusCode -ge 500
    }
    elseif ($effectiveException -is [System.TimeoutException] -or
        $effectiveException -is [System.Threading.Tasks.TaskCanceledException] -or
        $effectiveException.GetType().FullName -ceq 'System.Net.Http.HttpRequestException' -or
        $effectiveException -is [System.IO.IOException]) {
        $transient = $true
    }
    return [pscustomobject]@{
        StatusCode = $statusCode
        Transient = $transient
        Kind = if ($null -ne $statusCode) { "http-$statusCode" } else { $effectiveException.GetType().Name }
    }
}

function New-UploadReceiptWriter {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$ApprovedManifest
    )

    $fullPath = Assert-ReleaseOrdinaryPath -Path $Path
    $parent = Split-Path -Parent $fullPath
    $null = Assert-ReleaseOrdinaryPath -Path $parent
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw 'The upload receipt parent directory must already exist.'
    }
    $protectedPaths = @($ApprovedManifest.Path) + @($ApprovedManifest.Artifacts | ForEach-Object Path)
    foreach ($protectedPath in $protectedPaths) {
        if ($fullPath.Equals(
            [System.IO.Path]::GetFullPath($protectedPath),
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw 'The upload receipt cannot overwrite the approved manifest or an artifact.'
        }
    }
    if (Test-Path -LiteralPath $fullPath) {
        $existingReceipt = Get-Item -LiteralPath $fullPath -Force
        if ($existingReceipt.PSIsContainer -or
            ($existingReceipt.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'The upload receipt destination must be one ordinary file.'
        }
    }
    return {
        param($Record)
        $entry = [ordered]@{
            timestampUtc = [DateTime]::UtcNow.ToString('o')
            tag = [string]$Record.tag
            releaseId = [long]$Record.releaseId
            manifestSha256 = [string]$Record.manifestSha256
            role = [string]$Record.role
            name = [string]$Record.name
            attempt = [int]$Record.attempt
            status = [string]$Record.status
            assetId = if ($null -eq $Record.assetId) { $null } else { [long]$Record.assetId }
            bytes = [long]$Record.bytes
            sha256 = [string]$Record.sha256
            failureKind = if ($null -eq $Record.failureKind) { $null } else { [string]$Record.failureKind }
        }
        $line = ($entry | ConvertTo-Json -Compress -Depth 3) + "`r`n"
        $stream = [System.IO.File]::Open(
            $fullPath,
            [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::Read
        )
        try {
            $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($line)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        }
        finally {
            $stream.Dispose()
        }
    }.GetNewClosure()
}

function Write-ArtifactReceipt {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ReceiptWriter,
        [Parameter(Mandatory = $true)]$ApprovedManifest,
        [Parameter(Mandatory = $true)]$Artifact,
        [Parameter(Mandatory = $true)][long]$ReleaseId,
        [Parameter(Mandatory = $true)][int]$Attempt,
        [Parameter(Mandatory = $true)][string]$Status,
        $AssetId = $null,
        $FailureKind = $null
    )
    & $ReceiptWriter ([pscustomobject]@{
        tag = $ApprovedManifest.Tag
        releaseId = $ReleaseId
        manifestSha256 = $ApprovedManifest.Sha256
        role = $Artifact.Role
        name = $Artifact.Name
        attempt = $Attempt
        status = $Status
        assetId = $AssetId
        bytes = $Artifact.Bytes
        sha256 = $Artifact.Sha256
        failureKind = $FailureKind
    })
}

function Assert-KnownRemoteAssetSet {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$ApprovedManifest
    )

    foreach ($remote in $Context.Assets) {
        $known = $false
        foreach ($artifact in $ApprovedManifest.Artifacts) {
            if ($remote.Name -ceq $artifact.Name -or
                $remote.Name.StartsWith(
                    (Get-TemporaryAssetPrefix $ApprovedManifest $artifact),
                    [System.StringComparison]::Ordinal
                )) {
                $known = $true
                break
            }
        }
        if (-not $known) {
            throw "The draft contains unrelated asset '$($remote.Name)'. It was retained; synchronization stopped."
        }
    }
}

function Get-ArtifactRemoteState {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$ApprovedManifest,
        [Parameter(Mandatory = $true)]$Artifact
    )

    Assert-KnownRemoteAssetSet -Context $Context -ApprovedManifest $ApprovedManifest
    $final = @($Context.Assets | Where-Object { $_.Name -ceq $Artifact.Name })
    $prefix = Get-TemporaryAssetPrefix $ApprovedManifest $Artifact
    $temporary = @($Context.Assets | Where-Object {
        $_.Name.StartsWith($prefix, [System.StringComparison]::Ordinal)
    })
    if ($final.Count -gt 1 -or $temporary.Count -gt 1 -or
        ($final.Count -eq 1 -and $temporary.Count -ne 0)) {
        throw "The draft has ambiguous duplicate assets for $($Artifact.Name)."
    }
    foreach ($asset in @($final + $temporary)) {
        if (-not (Test-AssetMatchesArtifact $asset $Artifact)) {
            throw "The draft contains a conflicting byte identity for $($Artifact.Name)."
        }
    }
    return [pscustomobject]@{
        Final = if ($final.Count -eq 1) { $final[0] } else { $null }
        Temporary = if ($temporary.Count -eq 1) { $temporary[0] } else { $null }
    }
}

function Set-VerifiedAssetMetadata {
    param(
        [Parameter(Mandatory = $true)]$ApprovedManifest,
        [Parameter(Mandatory = $true)]$Artifact,
        [Parameter(Mandatory = $true)][long]$AssetId,
        [Parameter(Mandatory = $true)][long]$ReleaseId,
        [Parameter(Mandatory = $true)][scriptblock]$JsonRequest
    )

    # Re-read and bind the complete remote identity immediately before mutation.
    $context = Get-VerifiedDraftContext `
        -ApprovedManifest $ApprovedManifest `
        -JsonRequest $JsonRequest `
        -ExpectedReleaseId $ReleaseId
    $remote = @($context.Assets | Where-Object { $_.Id -eq $AssetId })
    if ($remote.Count -ne 1 -or -not (Test-AssetMatchesArtifact $remote[0] $Artifact)) {
        throw "Remote asset identity changed before metadata update for $($Artifact.Name)."
    }
    $finalConflict = @($context.Assets | Where-Object {
        $_.Name -ceq $Artifact.Name -and $_.Id -ne $AssetId
    })
    if ($finalConflict.Count -ne 0) {
        throw "The final remote name is already occupied for $($Artifact.Name)."
    }

    $null = & $JsonRequest ([pscustomobject]@{
        Kind = 'PatchReleaseAsset'
        Method = 'PATCH'
        Uri = Get-ApiUri $ApprovedManifest.Repository "releases/assets/$AssetId"
        Body = [ordered]@{ name = $Artifact.Name; label = $Artifact.Label }
    })

    $verified = Get-VerifiedDraftContext `
        -ApprovedManifest $ApprovedManifest `
        -JsonRequest $JsonRequest `
        -ExpectedReleaseId $ReleaseId
    $state = Get-ArtifactRemoteState $verified $ApprovedManifest $Artifact
    if ($null -eq $state.Final -or
        $state.Final.Id -ne $AssetId -or
        $state.Final.Label -cne $Artifact.Label) {
        throw "Remote metadata verification failed for $($Artifact.Name)."
    }
    return $state.Final
}

function Sync-OneDraftAsset {
    param(
        [Parameter(Mandatory = $true)]$ApprovedManifest,
        [Parameter(Mandatory = $true)]$Artifact,
        [Parameter(Mandatory = $true)][long]$ReleaseId,
        [Parameter(Mandatory = $true)][scriptblock]$JsonRequest,
        [Parameter(Mandatory = $true)][scriptblock]$UploadRequest,
        [Parameter(Mandatory = $true)][scriptblock]$Delay,
        [Parameter(Mandatory = $true)][scriptblock]$ReceiptWriter,
        [Parameter(Mandatory = $true)][int]$MaximumAttempts
    )

    $initial = Get-VerifiedDraftContext $ApprovedManifest $JsonRequest $ReleaseId
    $state = Get-ArtifactRemoteState $initial $ApprovedManifest $Artifact
    if ($null -ne $state.Final) {
        if ($state.Final.Label -cne $Artifact.Label) {
            $state.Final = Set-VerifiedAssetMetadata $ApprovedManifest $Artifact `
                $state.Final.Id $ReleaseId $JsonRequest
        }
        Write-ArtifactReceipt $ReceiptWriter $ApprovedManifest $Artifact `
            $ReleaseId 0 'reused' $state.Final.Id
        return 'reused'
    }
    if ($null -ne $state.Temporary) {
        $finalAsset = Set-VerifiedAssetMetadata $ApprovedManifest $Artifact `
            $state.Temporary.Id $ReleaseId $JsonRequest
        Write-ArtifactReceipt $ReceiptWriter $ApprovedManifest $Artifact `
            $ReleaseId 0 'resumed' $finalAsset.Id
        return 'resumed'
    }

    $lastFailure = $null
    foreach ($attempt in 1..$MaximumAttempts) {
        $stream = [System.IO.File]::Open(
            $Artifact.Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        try {
            if ($stream.Length -ne $Artifact.Bytes -or
                (Get-Sha256HexFromStream $stream) -cne $Artifact.Sha256) {
                throw "Local artifact changed before upload: $($Artifact.Name)."
            }

            # This identity read occurs while the accepted local bytes are locked.
            $before = Get-VerifiedDraftContext $ApprovedManifest $JsonRequest $ReleaseId
            $beforeState = Get-ArtifactRemoteState $before $ApprovedManifest $Artifact
            if ($null -ne $beforeState.Final) {
                if ($beforeState.Final.Label -cne $Artifact.Label) {
                    $beforeState.Final = Set-VerifiedAssetMetadata $ApprovedManifest $Artifact `
                        $beforeState.Final.Id $ReleaseId $JsonRequest
                }
                Write-ArtifactReceipt $ReceiptWriter $ApprovedManifest $Artifact `
                    $ReleaseId $attempt 'reused-after-inspection' $beforeState.Final.Id
                return 'reused-after-inspection'
            }
            if ($null -ne $beforeState.Temporary) {
                $finalAsset = Set-VerifiedAssetMetadata $ApprovedManifest $Artifact `
                    $beforeState.Temporary.Id $ReleaseId $JsonRequest
                Write-ArtifactReceipt $ReceiptWriter $ApprovedManifest $Artifact `
                    $ReleaseId $attempt 'resumed-after-inspection' $finalAsset.Id
                return 'resumed-after-inspection'
            }

            $tempName = (Get-TemporaryAssetPrefix $ApprovedManifest $Artifact) +
                "$attempt-$([Guid]::NewGuid().ToString('N').Substring(0, 12))-$($Artifact.Name)"
            $uploadUri = $before.UploadBase + '?name=' +
                [System.Uri]::EscapeDataString($tempName) + '&label=' +
                [System.Uri]::EscapeDataString($Artifact.Label)
            Write-ArtifactReceipt $ReceiptWriter $ApprovedManifest $Artifact `
                $ReleaseId $attempt 'attempt-started'
            $failureClassification = $null
            try {
                $stream.Position = 0
                $null = & $UploadRequest ([pscustomobject]@{
                    Kind = 'UploadReleaseAsset'
                    Method = 'POST'
                    Uri = $uploadUri
                    Name = $tempName
                    Label = $Artifact.Label
                    Stream = $stream
                    Length = $Artifact.Bytes
                    Sha256 = $Artifact.Sha256
                })
                $lastFailure = $null
                Write-ArtifactReceipt $ReceiptWriter $ApprovedManifest $Artifact `
                    $ReleaseId $attempt 'upload-request-returned'
            }
            catch {
                $lastFailure = $_
                $failureClassification = Get-UploadFailureClassification $_
                $failureStatus = if ($failureClassification.Transient) {
                    'upload-error-transient'
                }
                else {
                    'upload-error-nonretryable'
                }
                Write-ArtifactReceipt $ReceiptWriter $ApprovedManifest $Artifact `
                    $ReleaseId $attempt $failureStatus $null $failureClassification.Kind
            }
        }
        finally {
            $stream.Dispose()
        }

        # A timeout/5xx may still have committed the upload. Inspect before retrying.
        if ($null -eq $failureClassification -or $failureClassification.Transient) {
            & $Delay
        }
        $after = Get-VerifiedDraftContext $ApprovedManifest $JsonRequest $ReleaseId
        $afterState = Get-ArtifactRemoteState $after $ApprovedManifest $Artifact
        if ($null -ne $afterState.Final) {
            if ($afterState.Final.Label -cne $Artifact.Label) {
                $afterState.Final = Set-VerifiedAssetMetadata $ApprovedManifest $Artifact `
                    $afterState.Final.Id $ReleaseId $JsonRequest
            }
            Write-ArtifactReceipt $ReceiptWriter $ApprovedManifest $Artifact `
                $ReleaseId $attempt 'reused-after-upload' $afterState.Final.Id
            return 'reused-after-upload'
        }
        if ($null -ne $afterState.Temporary) {
            $finalAsset = Set-VerifiedAssetMetadata $ApprovedManifest $Artifact `
                $afterState.Temporary.Id $ReleaseId $JsonRequest
            if ($null -ne $lastFailure) {
                Write-ArtifactReceipt $ReceiptWriter $ApprovedManifest $Artifact `
                    $ReleaseId $attempt 'recovered-uncertain-upload' $finalAsset.Id
                return 'recovered-uncertain-upload'
            }
            Write-ArtifactReceipt $ReceiptWriter $ApprovedManifest $Artifact `
                $ReleaseId $attempt 'uploaded' $finalAsset.Id
            return 'uploaded'
        }
        if ($null -ne $failureClassification -and -not $failureClassification.Transient) {
            Write-ArtifactReceipt $ReceiptWriter $ApprovedManifest $Artifact `
                $ReleaseId $attempt 'stopped-nonretryable' $null $failureClassification.Kind
            throw "Non-retryable upload failure for $($Artifact.Name): $($failureClassification.Kind)"
        }
        Write-ArtifactReceipt $ReceiptWriter $ApprovedManifest $Artifact `
            $ReleaseId $attempt 'retry-pending' $null `
            $(if ($null -eq $failureClassification) { 'asset-not-visible' } else { $failureClassification.Kind })
    }
    if ($null -ne $lastFailure) {
        throw "Upload attempts were exhausted for $($Artifact.Name): $($lastFailure.Exception.Message)"
    }
    throw "Upload attempts were exhausted for $($Artifact.Name) without a verified remote asset."
}

function Invoke-VerifiedDraftAssetSync {
    param(
        [Parameter(Mandatory = $true)]$ApprovedManifest,
        [Parameter(Mandatory = $true)][scriptblock]$JsonRequest,
        [Parameter(Mandatory = $true)][scriptblock]$UploadRequest,
        [Parameter(Mandatory = $true)][scriptblock]$Delay,
        [Parameter(Mandatory = $true)][scriptblock]$ReceiptWriter,
        [ValidateRange(1, 8)][int]$MaximumAttempts = 3
    )

    Assert-AllLocalArtifacts -ApprovedManifest $ApprovedManifest
    $initial = Get-VerifiedDraftContext $ApprovedManifest $JsonRequest
    Assert-KnownRemoteAssetSet $initial $ApprovedManifest
    # Validate every expected final/temp byte identity before the first mutation.
    foreach ($artifact in $ApprovedManifest.Artifacts) {
        $null = Get-ArtifactRemoteState $initial $ApprovedManifest $artifact
    }
    $results = @()
    foreach ($artifact in $ApprovedManifest.Artifacts) {
        $outcome = Sync-OneDraftAsset $ApprovedManifest $artifact $initial.ReleaseId `
            $JsonRequest $UploadRequest $Delay $ReceiptWriter $MaximumAttempts
        $results += [pscustomobject]@{
            role = $artifact.Role
            name = $artifact.Name
            outcome = $outcome
            bytes = $artifact.Bytes
            sha256 = $artifact.Sha256
        }
    }

    $final = Get-VerifiedDraftContext $ApprovedManifest $JsonRequest $initial.ReleaseId
    Assert-KnownRemoteAssetSet $final $ApprovedManifest
    if ($final.Assets.Count -ne $ApprovedManifest.Artifacts.Count) {
        throw 'The draft does not contain the exact reviewed asset set after synchronization.'
    }
    foreach ($artifact in $ApprovedManifest.Artifacts) {
        $state = Get-ArtifactRemoteState $final $ApprovedManifest $artifact
        if ($null -eq $state.Final -or
            $null -ne $state.Temporary -or
            $state.Final.Label -cne $artifact.Label) {
            throw "Final draft asset verification failed for $($artifact.Name)."
        }
    }
    return [pscustomobject]@{
        status = 'draft-assets-synchronized'
        published = $false
        repository = $ApprovedManifest.Repository
        tag = $ApprovedManifest.Tag
        sourceCommit = $ApprovedManifest.SourceCommit
        releaseId = $initial.ReleaseId
        manifestSha256 = $ApprovedManifest.Sha256
        artifacts = $results
    }
}

function New-ProductionJsonRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    return {
        param($Request)
        $headers = @{
            Accept = 'application/vnd.github+json'
            Authorization = "Bearer $Token"
            'X-GitHub-Api-Version' = '2022-11-28'
            'User-Agent' = 'black-spirit-life-release-tooling'
        }
        $arguments = @{
            Method = $Request.Method
            Uri = $Request.Uri
            Headers = $headers
            TimeoutSec = $TimeoutSeconds
            ErrorAction = 'Stop'
        }
        if ($null -ne $Request.Body) {
            $arguments['ContentType'] = 'application/json'
            $arguments['Body'] = ($Request.Body | ConvertTo-Json -Compress -Depth 5)
        }
        return Invoke-RestMethod @arguments
    }.GetNewClosure()
}

function New-ProductionUploadRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    return {
        param($Request)
        Add-Type -AssemblyName System.Net.Http
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $client = [System.Net.Http.HttpClient]::new($handler)
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
        $message = [System.Net.Http.HttpRequestMessage]::new(
            [System.Net.Http.HttpMethod]::Post,
            [System.Uri]$Request.Uri
        )
        $content = [System.Net.Http.StreamContent]::new($Request.Stream)
        $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new(
            'application/octet-stream'
        )
        $content.Headers.ContentLength = [long]$Request.Length
        $message.Content = $content
        $message.Headers.Accept.ParseAdd('application/vnd.github+json')
        $message.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new(
            'Bearer', $Token
        )
        $message.Headers.Add('X-GitHub-Api-Version', '2022-11-28')
        $message.Headers.UserAgent.ParseAdd('black-spirit-life-release-tooling')
        try {
            $response = $client.SendAsync(
                $message,
                [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
            ).GetAwaiter().GetResult()
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if (-not $response.IsSuccessStatusCode) {
                $failure = [System.Net.Http.HttpRequestException]::new(
                    "GitHub upload returned HTTP $([int]$response.StatusCode)."
                )
                $failure.Data['StatusCode'] = [int]$response.StatusCode
                throw $failure
            }
            if ([string]::IsNullOrWhiteSpace($body)) { return $null }
            return $body | ConvertFrom-Json
        }
        finally {
            $message.Dispose()
            $client.Dispose()
            $handler.Dispose()
        }
    }.GetNewClosure()
}

if ($MyInvocation.InvocationName -ne '.') {
    foreach ($required in @{
        ManifestPath = $ManifestPath
        ApprovedManifestSha256 = $ApprovedManifestSha256
        ExpectedRepository = $ExpectedRepository
        ExpectedTag = $ExpectedTag
        ExpectedSourceCommit = $ExpectedSourceCommit
    }.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$required.Value)) {
            throw "-$($required.Key) is required."
        }
    }
    if (-not $ConfirmReviewedArtifactReadiness.IsPresent) {
        throw 'Supply -ConfirmReviewedArtifactReadiness only after the non-upload release gates are reviewed.'
    }
    if (-not $ConfirmDraftAssetUpload.IsPresent) {
        throw 'Supply -ConfirmDraftAssetUpload to permit writes to an existing draft release.'
    }
    if ([string]::IsNullOrWhiteSpace($GitHubToken)) {
        throw 'Set GITHUB_TOKEN or supply -GitHubToken for the existing draft release.'
    }

    $approved = Read-ApprovedManifest `
        -Path $ManifestPath `
        -ExpectedSha256 $ApprovedManifestSha256 `
        -Repository $ExpectedRepository `
        -Tag $ExpectedTag `
        -SourceCommit $ExpectedSourceCommit
    if ([string]::IsNullOrWhiteSpace($ReceiptPath)) {
        $ReceiptPath = Join-Path (
            Split-Path -Parent $approved.Path
        ) 'draft-upload-receipts.jsonl'
    }
    elseif (-not [System.IO.Path]::IsPathRooted($ReceiptPath)) {
        throw '-ReceiptPath must be absolute when supplied.'
    }
    $receiptWriter = New-UploadReceiptWriter `
        -Path $ReceiptPath `
        -ApprovedManifest $approved
    $jsonRequest = New-ProductionJsonRequest `
        -Token $GitHubToken `
        -TimeoutSeconds $JsonTimeoutSeconds
    $uploadRequest = New-ProductionUploadRequest `
        -Token $GitHubToken `
        -TimeoutSeconds $UploadTimeoutSeconds
    $delay = { Start-Sleep -Seconds $RetryDelaySeconds }.GetNewClosure()
    Invoke-VerifiedDraftAssetSync `
        -ApprovedManifest $approved `
        -JsonRequest $jsonRequest `
        -UploadRequest $uploadRequest `
        -Delay $delay `
        -ReceiptWriter $receiptWriter `
        -MaximumAttempts $MaxUploadAttempts | ConvertTo-Json -Depth 6
}
