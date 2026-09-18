Set-StrictMode -Version Latest

if ($null -eq (Get-Command Assert-ReleaseOrdinaryPath -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'verified_input_cache.ps1')
}

function Get-ReleasePlanProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Context
    )
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        throw "$Context is missing required property '$Name'."
    }
    if ($property.Value -is [array]) {
        return ,$property.Value
    }
    return $property.Value
}

function Get-ReleasePlanStringProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Context
    )
    $value = Get-ReleasePlanProperty $Object $Name $Context
    if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
        throw "$Context property '$Name' must be a non-empty JSON string."
    }
    return $value
}

function Assert-ReleasePlanSha256 {
    param([Parameter(Mandatory = $true)][string]$Value, [string]$Context = 'SHA-256')
    if ($Value -cnotmatch '^[0-9A-F]{64}$') {
        throw "$Context must be an uppercase 64-character SHA-256 value."
    }
}

function Assert-ReleasePlanRelativePath {
    param([Parameter(Mandatory = $true)][string]$Value, [Parameter(Mandatory = $true)][string]$Context)
    if ([string]::IsNullOrWhiteSpace($Value) -or
        [IO.Path]::IsPathRooted($Value) -or
        $Value.Contains(':') -or
        $Value -match '(^|[\\/])\.{1,2}([\\/]|$)') {
        throw "$Context must be a safe relative path."
    }
    $segments = @($Value -split '[\\/]')
    foreach ($segment in $segments) {
        if ([string]::IsNullOrWhiteSpace($segment) -or
            $segment -match '[\x00-\x1F"<>|?*:]' -or
            $segment -match '[. ]$' -or
            $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
            throw "$Context contains an invalid Windows path segment."
        }
    }
}

function Assert-ReleasePlanFileName {
    param([Parameter(Mandatory = $true)][string]$Value, [Parameter(Mandatory = $true)][string]$Context)
    Assert-ReleasePlanRelativePath $Value $Context
    if ([IO.Path]::GetFileName($Value) -cne $Value) {
        throw "$Context must be one filename."
    }
}

function Test-ReleasePlanJsonInteger {
    param($Value)
    return $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function ConvertTo-ReleaseVersion {
    param([Parameter(Mandatory = $true)][string]$Value, [Parameter(Mandatory = $true)][string]$Context)
    if ($Value -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
        throw "$Context must be a three-part numeric version."
    }
    return [version]$Value
}

function Read-ReleasePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    $expectedHash = $ExpectedSha256.ToUpperInvariant()
    Assert-ReleasePlanSha256 $expectedHash 'Approved release-plan SHA-256'
    $fullPath = Assert-ReleaseOrdinaryPath -Path $Path
    $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
    if ($item.PSIsContainer -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'The approved release plan must be one ordinary file.'
    }
    $bytes = [IO.File]::ReadAllBytes($item.FullName)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $actualHash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    }
    finally { $sha.Dispose() }
    if ($actualHash -cne $expectedHash) {
        throw "Approved release-plan SHA-256 mismatch. Expected $expectedHash; got $actualHash."
    }
    try {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        $plan = $text | ConvertFrom-Json
    }
    catch {
        throw "The approved release plan is not valid UTF-8 JSON: $($_.Exception.Message)"
    }

    $schemaVersion = Get-ReleasePlanProperty $plan 'schemaVersion' 'Release plan'
    $publicationAuthorization = Get-ReleasePlanProperty $plan 'publicationAuthorizedByThisFile' 'Release plan'
    if (-not (Test-ReleasePlanJsonInteger $schemaVersion) -or
        [int64]$schemaVersion -ne 1 -or
        $publicationAuthorization -isnot [bool] -or
        $publicationAuthorization -ne $false) {
        throw 'The release plan must be schema 1 and cannot authorize publication.'
    }
    $identity = Get-ReleasePlanProperty $plan 'identity' 'Release plan'
    $source = Get-ReleasePlanProperty $plan 'source' 'Release plan'
    $historical = Get-ReleasePlanProperty $plan 'historicalInputs' 'Release plan'
    $lifecycle = Get-ReleasePlanProperty $plan 'lifecycle' 'Release plan'

    $repository = Get-ReleasePlanStringProperty $identity 'repository' 'Release identity'
    if ($repository -cnotmatch '^https://github\.com/[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})/[A-Za-z0-9._-]{1,100}$') {
        throw 'Release identity repository must be the exact canonical GitHub base URL.'
    }
    $packageId = Get-ReleasePlanStringProperty $identity 'packageId' 'Release identity'
    $channel = Get-ReleasePlanStringProperty $identity 'channel' 'Release identity'
    if ($packageId -cne 'BlackSpiritLife.App' -or
        $channel -cne 'win-x64-stable') {
        throw 'Release packageId or channel is not a supported Black Spirit Life identity.'
    }
    $version = Get-ReleasePlanStringProperty $identity 'version' 'Release identity'
    $previousVersion = Get-ReleasePlanStringProperty $identity 'previousPublishedVersion' 'Release identity'
    $parsedVersion = ConvertTo-ReleaseVersion $version 'Release version'
    $parsedPrevious = ConvertTo-ReleaseVersion $previousVersion 'Previous published version'
    if ($parsedVersion -le $parsedPrevious) {
        throw 'Release version must be newer than the previous published version.'
    }
    $rawBuildNumber = Get-ReleasePlanProperty $identity 'buildNumber' 'Release identity'
    if (-not (Test-ReleasePlanJsonInteger $rawBuildNumber) -or
        [uint64]$rawBuildNumber -eq 0 -or
        [uint64]$rawBuildNumber -gt [int]::MaxValue) {
        throw 'Release buildNumber must be a positive JSON integer within Int32 range.'
    }
    $buildNumber = [int]$rawBuildNumber
    $releaseNotes = Get-ReleasePlanStringProperty $identity 'releaseNotesRelativePath' 'Release identity'
    $outputDirectoryName = Get-ReleasePlanStringProperty $identity 'outputDirectoryName' 'Release identity'
    $manifestName = Get-ReleasePlanStringProperty $identity 'manifestName' 'Release identity'
    Assert-ReleasePlanRelativePath $releaseNotes 'Release notes path'
    Assert-ReleasePlanFileName $outputDirectoryName 'Output directory name'
    Assert-ReleasePlanFileName $manifestName 'Manifest name'
    if ([IO.Path]::GetExtension($releaseNotes) -cne '.md' -or
        [IO.Path]::GetExtension($manifestName) -cne '.json') {
        throw 'Release notes must be Markdown and manifestName must be one JSON filename.'
    }

    $expectedCommit = Get-ReleasePlanStringProperty $source 'expectedCommit' 'Release source'
    $reviewedParentCommit = Get-ReleasePlanStringProperty $source 'reviewedParentCommit' 'Release source'
    $previousCommit = Get-ReleasePlanStringProperty $source 'previousPublishedCommit' 'Release source'
    foreach ($commitRecord in @(
        @{ Value = $expectedCommit; Name = 'expectedCommit' },
        @{ Value = $reviewedParentCommit; Name = 'reviewedParentCommit' },
        @{ Value = $previousCommit; Name = 'previousPublishedCommit' }
    )) {
        if ($commitRecord.Value -cnotmatch '^[0-9a-f]{40}$') {
            throw "Release source $($commitRecord.Name) must be an exact lowercase commit."
        }
    }
    if ($expectedCommit -ceq $reviewedParentCommit -or
        $expectedCommit -ceq $previousCommit) {
        throw 'Release source commits do not describe a new release checkpoint.'
    }
    $expectedTag = Get-ReleasePlanStringProperty $source 'expectedTag' 'Release source'
    $previousTag = Get-ReleasePlanStringProperty $source 'previousPublishedTag' 'Release source'
    if ($expectedTag -cne "v$version" -or $previousTag -cne "v$previousVersion") {
        throw 'Release source tags do not match the release versions.'
    }

    $previousFeed = Get-ReleasePlanProperty $historical 'previousFeed' 'Historical inputs'
    $previousFull = Get-ReleasePlanProperty $historical 'previousFullPackage' 'Historical inputs'
    foreach ($record in @(
        @{ Object = $previousFeed; Name = 'previousFeed' },
        @{ Object = $previousFull; Name = 'previousFullPackage' }
    )) {
        $rawRecordBytes = Get-ReleasePlanProperty $record.Object 'bytes' "Historical $($record.Name)"
        $recordSha = (Get-ReleasePlanStringProperty $record.Object 'sha256' "Historical $($record.Name)").ToUpperInvariant()
        if (-not (Test-ReleasePlanJsonInteger $rawRecordBytes) -or
            [uint64]$rawRecordBytes -eq 0 -or
            [uint64]$rawRecordBytes -gt [long]::MaxValue) {
            throw "Historical $($record.Name) bytes must be a positive JSON integer."
        }
        Assert-ReleasePlanSha256 $recordSha "Historical $($record.Name) SHA-256"
    }

    $previousSetup = Get-ReleasePlanProperty $lifecycle 'previousSetup' 'Lifecycle plan'
    $previousSetupName = Get-ReleasePlanStringProperty $previousSetup 'fileName' 'Lifecycle previous setup'
    Assert-ReleasePlanFileName $previousSetupName 'Lifecycle previous setup filename'
    if ([IO.Path]::GetExtension($previousSetupName) -cne '.exe') {
        throw 'Lifecycle previous setup must name one EXE.'
    }
    $rawPreviousSetupBytes = Get-ReleasePlanProperty $previousSetup 'bytes' 'Lifecycle previous setup'
    $previousSetupSha = (Get-ReleasePlanStringProperty $previousSetup 'sha256' 'Lifecycle previous setup').ToUpperInvariant()
    if (-not (Test-ReleasePlanJsonInteger $rawPreviousSetupBytes) -or
        [uint64]$rawPreviousSetupBytes -eq 0 -or
        [uint64]$rawPreviousSetupBytes -gt [long]::MaxValue) {
        throw 'Lifecycle previous setup bytes must be a positive JSON integer.'
    }
    $previousSetupBytes = [long]$rawPreviousSetupBytes
    Assert-ReleasePlanSha256 $previousSetupSha 'Lifecycle previous setup SHA-256'
    $migrationSourceVersion = Get-ReleasePlanStringProperty $lifecycle 'migrationSourceVersion' 'Lifecycle plan'
    $parsedMigration = ConvertTo-ReleaseVersion $migrationSourceVersion 'Lifecycle migration source version'
    if ($parsedMigration -gt $parsedPrevious -or $migrationSourceVersion -cne '0.1.7') {
        throw 'Lifecycle migration source version is not the supported stable 0.1.7 migration contract.'
    }
    $fixtureSchema = Get-ReleasePlanProperty $lifecycle 'syntheticFixtureSchemaVersion' 'Lifecycle plan'
    if (-not (Test-ReleasePlanJsonInteger $fixtureSchema) -or
        [int64]$fixtureSchema -ne 1) {
        throw 'Only lifecycle synthetic fixture schema 1 is supported.'
    }

    $rawRemainingBlockers = Get-ReleasePlanProperty $plan 'remainingBlockers' 'Release plan'
    $remainingBlockers = @($rawRemainingBlockers)
    if ($rawRemainingBlockers -isnot [array] -or
        $remainingBlockers.Count -eq 0 -or
        @($remainingBlockers | Where-Object {
            $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_)
        }).Count -ne 0) {
        throw 'Release plan must name its remaining verification blockers.'
    }

    return [pscustomobject]@{
        Path = $item.FullName
        Sha256 = $actualHash
        Raw = $plan
        Repository = $repository
        PackageId = $packageId
        Channel = $channel
        Version = $version
        BuildNumber = $buildNumber
        PreviousVersion = $previousVersion
        ReleaseNotesRelativePath = $releaseNotes
        OutputDirectoryName = $outputDirectoryName
        ManifestName = $manifestName
        ExpectedCommit = $expectedCommit
        ExpectedTag = $expectedTag
        ReviewedParentCommit = $reviewedParentCommit
        PreviousCommit = $previousCommit
        PreviousTag = $previousTag
        PreviousFeedBytes = [long]$previousFeed.bytes
        PreviousFeedSha256 = ([string]$previousFeed.sha256).ToUpperInvariant()
        PreviousFullPackageBytes = [long]$previousFull.bytes
        PreviousFullPackageSha256 = ([string]$previousFull.sha256).ToUpperInvariant()
        PreviousSetupFileName = $previousSetupName
        PreviousSetupBytes = $previousSetupBytes
        PreviousSetupSha256 = $previousSetupSha
        MigrationSourceVersion = $migrationSourceVersion
        RemainingBlockers = @($remainingBlockers)
    }
}
