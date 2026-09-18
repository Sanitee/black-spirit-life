[CmdletBinding()]
param()

# Executes selected trusted builder AST extents against synthetic inputs. The
# production script itself is never invoked; its tag/history gates stay intact.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$builderPath = Join-Path $repositoryRoot 'tool/build_stable_release_candidate.ps1'
$builderText = Get-Content -LiteralPath $builderPath -Raw
$tokens = $null
$parseErrors = $null
$builderAst = [Management.Automation.Language.Parser]::ParseFile($builderPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'Builder syntax must parse before integration fixtures run.' }
. (Join-Path $repositoryRoot 'tool/release/verified_input_cache.ps1')
. (Join-Path $repositoryRoot 'tool/release/preflight.ps1')
. (Join-Path $repositoryRoot 'tool/release/stage_metrics.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

$script:assertions = 0
function Assert-Fixture([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Integration assertion failed: $Message" }
    $script:assertions++
}
function Assert-Rejected([scriptblock]$Action, [string]$Pattern) {
    $caught = $false
    try { & $Action | Out-Null }
    catch {
        $caught = $true
        Assert-Fixture ($_.Exception.Message -match $Pattern) "Unexpected rejection: $($_.Exception.Message)"
    }
    Assert-Fixture $caught "Expected rejection: $Pattern"
}
function Find-BuilderFunction([string]$Name) {
    $nodes = @($builderAst.FindAll({
        param($Node)
        $Node -is [Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -ceq $Name
    }, $true))
    Assert-Fixture ($nodes.Count -eq 1) "Expected one builder function $Name."
    return $nodes[0]
}
function Find-BuilderCommands([string]$Name) {
    return @($builderAst.FindAll({
        param($Node)
        $Node -is [Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -ceq $Name
    }, $true))
}
function Get-CommandArgument($Command, [string]$Parameter) {
    for ($i = 0; $i -lt $Command.CommandElements.Count - 1; $i++) {
        $element = $Command.CommandElements[$i]
        if ($element -is [Management.Automation.Language.CommandParameterAst] -and $element.ParameterName -ceq $Parameter) {
            return $Command.CommandElements[$i + 1]
        }
    }
    throw "Builder command is missing parameter $Parameter."
}
function Get-BuilderStatement($Node) {
    $current = $Node
    while ($null -ne $current.Parent -and $current.Parent -isnot [Management.Automation.Language.StatementBlockAst]) {
        $current = $current.Parent
    }
    if ($null -eq $current.Parent) { throw 'Expected a builder statement inside its try block.' }
    return $current
}
function Set-FixtureFile([string]$Path, [string]$Text) {
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function New-FixturePackage([string]$Path, [Collections.IDictionary]$Metadata, [string[]]$Payloads) {
    $archive = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $fields = @($Metadata.Keys | ForEach-Object {
            '<' + $_ + '>' + [Security.SecurityElement]::Escape([string]$Metadata[$_]) + '</' + $_ + '>'
        }) -join ''
        $nuspec = $archive.CreateEntry('Fixture.nuspec')
        $writer = [IO.StreamWriter]::new($nuspec.Open())
        try { $writer.Write('<package><metadata>' + $fields + '</metadata></package>') }
        finally { $writer.Dispose() }
        foreach ($payload in $Payloads) {
            $entry = $archive.CreateEntry('lib/net45/' + $payload)
            $writer = [IO.StreamWriter]::new($entry.Open())
            try { $writer.Write('synthetic-byte-payload') }
            finally { $writer.Dispose() }
        }
    }
    finally { $archive.Dispose() }
}
function New-CacheArguments([string]$CaseRoot, [string]$Source, [scriptblock]$Validator, [string]$Role) {
    $null = [IO.Directory]::CreateDirectory($CaseRoot)
    return @{
        CacheRoot = Join-Path $CaseRoot 'cache'
        Repository = 'https://github.com/example/builder-fixture'
        ReleaseTag = 'v1.2.3'
        Channel = $UpdateChannel
        Role = $Role
        ArtifactName = [IO.Path]::GetFileName($Source)
        ExpectedBytes = (Get-Item -LiteralPath $Source).Length
        ExpectedSha256 = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
        Destination = Join-Path $CaseRoot 'accepted.input'
        ExistingFile = $Source
        Offline = $true
        ValidateContent = $Validator
        Download = { throw 'Integration fixtures must never use the network.' }
    }
}

foreach ($functionName in @('Assert-VelopackPackage', 'Assert-OrdinaryFile', 'Assert-LastExitCode')) {
    $functionAst = Find-BuilderFunction $functionName
    . ([scriptblock]::Create($functionAst.Extent.Text))
}
$patternAssignments = @($builderAst.FindAll({
    param($Node)
    $Node -is [Management.Automation.Language.AssignmentStatementAst] -and
    $Node.Left -is [Management.Automation.Language.VariableExpressionAst] -and
    $Node.Left.VariablePath.UserPath -ceq 'ForbiddenPackagedArtifactPattern'
}, $true))
Assert-Fixture ($patternAssignments.Count -eq 1) 'Expected one actual builder archive-exclusion pattern.'
. ([scriptblock]::Create($patternAssignments[0].Extent.Text))
$acquisitions = @(Find-BuilderCommands 'Get-VerifiedReleaseInput')
$feedCommand = @($acquisitions | Where-Object { (Get-CommandArgument $_ 'Role').Value -ceq 'previous-feed' })
$packageCommand = @($acquisitions | Where-Object { (Get-CommandArgument $_ 'Role').Value -ceq 'previous-full' })
Assert-Fixture ($feedCommand.Count -eq 1 -and $packageCommand.Count -eq 1) 'Expected actual historical feed/package acquisition commands.'
$feedValidator = (Get-CommandArgument $feedCommand[0] 'ValidateContent').ScriptBlock.GetScriptBlock()
$packageValidator = (Get-CommandArgument $packageCommand[0] 'ValidateContent').ScriptBlock.GetScriptBlock()

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\', '/'))
$fixtureRoot = Join-Path $tempParent ('bsl-builder-integration-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($fixtureRoot)
$shellPath = (Get-Process -Id $PID).Path
$PackageId = 'Fixture.App'
$PreviousStableVersion = '1.2.3'
$UpdateChannel = 'win-x64-stable'
$DisplayName = 'Fixture App'
$ExecutableName = 'Fixture.exe'
$UpdaterHelperName = 'FixtureUpdater.exe'
$previousFullPackageName = 'Fixture.App-1.2.3-win-x64-stable-full.nupkg'
$validMetadata = [ordered]@{
    id = $PackageId
    version = $PreviousStableVersion
    channel = $UpdateChannel
    title = $DisplayName
    mainExe = $ExecutableName
}
try {
    $validPackage = Join-Path $fixtureRoot $previousFullPackageName
    New-FixturePackage $validPackage $validMetadata @($ExecutableName, $UpdaterHelperName)
    & $packageValidator $validPackage
    $validCache = New-CacheArguments (Join-Path $fixtureRoot 'valid-package') $validPackage $packageValidator 'previous-full'
    $imported = Get-VerifiedReleaseInput @validCache
    Assert-Fixture ($imported.cacheStatus -ceq 'imported' -and $imported.downloadedBytes -eq 0) 'Actual package callback accepts a valid local package.'
    $validCache.Remove('ExistingFile')
    $validCache.Destination = Join-Path (Split-Path -Parent $validCache.Destination) 'warm.input'
    $warm = Get-VerifiedReleaseInput @validCache
    Assert-Fixture ($warm.cacheStatus -ceq 'hit' -and $warm.downloadedBytes -eq 0) 'Actual package callback revalidates a warm offline package.'

    foreach ($field in @('id', 'version', 'channel', 'title', 'mainExe')) {
        $wrongMetadata = [ordered]@{}
        foreach ($key in $validMetadata.Keys) { $wrongMetadata[$key] = $validMetadata[$key] }
        $wrongMetadata[$field] = [string]$wrongMetadata[$field] + '-wrong'
        $wrongPath = Join-Path $fixtureRoot ("wrong-$field.nupkg")
        New-FixturePackage $wrongPath $wrongMetadata @($ExecutableName, $UpdaterHelperName)
        Assert-Rejected { & $packageValidator $wrongPath } "wrong $field identity"
        # Expected size/hash deliberately match the wrong package's bytes:
        # only the production content callback can reject the wrong identity.
        $wrongCache = New-CacheArguments (Join-Path $fixtureRoot "cache-wrong-$field") $wrongPath $packageValidator 'previous-full'
        Assert-Rejected { Get-VerifiedReleaseInput @wrongCache } "wrong $field identity"
        Assert-Fixture (-not (Test-Path -LiteralPath $wrongCache.Destination)) 'Wrong identity did not reach candidate input.'
        Assert-Fixture (@(Get-ChildItem -LiteralPath $wrongCache.CacheRoot -Filter '*.input').Count -eq 0) 'Wrong identity was not registered as a complete cache entry.'
    }
    foreach ($missing in @($ExecutableName, $UpdaterHelperName)) {
        $missingPath = Join-Path $fixtureRoot ("missing-$missing.nupkg")
        New-FixturePackage $missingPath $validMetadata @(@($ExecutableName, $UpdaterHelperName) | Where-Object { $_ -cne $missing })
        Assert-Rejected { & $packageValidator $missingPath } ('exactly one ' + [regex]::Escape($missing))
    }
    # A valid cache entry must still be checked against the current requested
    # package identity; verified outer bytes do not replace content validation.
    $DisplayName = 'Different expected title'
    Assert-Rejected { Get-VerifiedReleaseInput @validCache } 'wrong title identity'
    $DisplayName = 'Fixture App'

    $PreviousFullPackageBytes = (Get-Item -LiteralPath $validPackage).Length
    $PreviousFullPackageSha256 = (Get-FileHash -LiteralPath $validPackage -Algorithm SHA256).Hash
    $validAsset = [ordered]@{
        PackageId = $PackageId
        Version = $PreviousStableVersion
        Type = 'Full'
        FileName = $previousFullPackageName
        Size = $PreviousFullPackageBytes
        SHA256 = $PreviousFullPackageSha256
    }
    $otherAssets = @(
        [ordered]@{ PackageId = 'Other.App'; Version = '0.9.0'; Type = 'Full'; FileName = 'other-full.nupkg'; Size = 1; SHA256 = ('a' * 64) },
        [ordered]@{ PackageId = 'Other.App'; Version = '0.9.0'; Type = 'Delta'; FileName = 'other-delta.nupkg'; Size = 1; SHA256 = ('b' * 64) }
    )
    $validFeed = Join-Path $fixtureRoot 'releases.fixture.json'
    Set-FixtureFile $validFeed ([ordered]@{ Assets = @($validAsset) + $otherAssets } | ConvertTo-Json -Depth 6)
    & $feedValidator $validFeed
    $feedCache = New-CacheArguments (Join-Path $fixtureRoot 'valid-feed') $validFeed $feedValidator 'previous-feed'
    $feedResult = Get-VerifiedReleaseInput @feedCache
    Assert-Fixture ($feedResult.cacheStatus -ceq 'imported') 'Actual feed callback accepts the pinned package relationship.'
    foreach ($field in @('PackageId', 'Version', 'Type', 'FileName', 'Size', 'SHA256', 'asset-count')) {
        $wrongAsset = [ordered]@{}
        foreach ($key in $validAsset.Keys) { $wrongAsset[$key] = $validAsset[$key] }
        if ($field -eq 'Size') { $wrongAsset.Size = $PreviousFullPackageBytes + 1 }
        elseif ($field -eq 'SHA256') { $wrongAsset.SHA256 = '0' * 64 }
        elseif ($field -ne 'asset-count') { $wrongAsset[$field] = [string]$wrongAsset[$field] + '-wrong' }
        $wrongAssets = @($wrongAsset) + $otherAssets
        if ($field -eq 'asset-count') { $wrongAssets = @($wrongAsset) }
        $wrongFeed = Join-Path $fixtureRoot ("feed-wrong-$field.json")
        Set-FixtureFile $wrongFeed ([ordered]@{ Assets = $wrongAssets } | ConvertTo-Json -Depth 6)
        $wrongFeedCache = New-CacheArguments (Join-Path $fixtureRoot "cache-feed-wrong-$field") $wrongFeed $feedValidator 'previous-feed'
        Assert-Rejected { Get-VerifiedReleaseInput @wrongFeedCache } 'does not describe the pinned previous package'
        Assert-Fixture (-not (Test-Path -LiteralPath $wrongFeedCache.Destination)) 'Hash-valid wrong feed did not reach candidate input.'
    }

    # Extract the actual call and its immediate next statement. Run those bytes
    # in a child shell, so nonzero exit and the downstream marker are observable.
    $verifierCommands = @($builderAst.FindAll({
        param($Node)
        $Node -is [Management.Automation.Language.CommandAst] -and
        $Node.CommandElements[0] -is [Management.Automation.Language.VariableExpressionAst] -and
        $Node.CommandElements[0].VariablePath.UserPath -ceq 'productionVerifier'
    }, $true))
    Assert-Fixture ($verifierCommands.Count -eq 1) 'Expected one actual production verifier invocation.'
    $verifierStatement = Get-BuilderStatement $verifierCommands[0]
    $siblings = @($verifierStatement.Parent.Statements)
    $statementIndex = [array]::IndexOf($siblings, $verifierStatement)
    $nextStatement = $siblings[$statementIndex + 1]
    $verifierSegment = $builderText.Substring($verifierStatement.Extent.StartOffset,
        $nextStatement.Extent.EndOffset - $verifierStatement.Extent.StartOffset)
    $exitFunction = (Find-BuilderFunction 'Assert-LastExitCode').Extent.Text
    $childRunner = Join-Path $fixtureRoot 'verifier-boundary.ps1'
    $childHeader = @'
param([string]$productionVerifier, [string]$ProjectRoot, [string]$DownstreamMarker)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
'@
    Set-FixtureFile $childRunner ($childHeader + "`n" + $exitFunction + "`n" + $verifierSegment + "`n" + '[IO.File]::WriteAllText($DownstreamMarker, "reached")')
    foreach ($code in @(23, 0)) {
        $verifier = Join-Path $fixtureRoot ("verifier-$code.ps1")
        $marker = Join-Path $fixtureRoot ("after-verifier-$code.txt")
        Set-FixtureFile $verifier ('param([string]$ProjectRoot)' + "`nexit $code`n")
        $savedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $childOutput = @(& $shellPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $childRunner -productionVerifier $verifier -ProjectRoot $fixtureRoot -DownstreamMarker $marker 2>&1)
            $childExit = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $savedPreference }
        if ($code -eq 23) {
            Assert-Fixture ($childExit -ne 0) 'Verifier failure makes the builder segment exit nonzero.'
            Assert-Fixture (-not (Test-Path -LiteralPath $marker)) 'Verifier failure blocks downstream work.'
            Assert-Fixture (($childOutput -join "`n") -match 'Production source verification failed with exit code 23') 'Immediate builder assertion identifies the failed verifier.'
        }
        else {
            Assert-Fixture ($childExit -eq 0 -and (Test-Path -LiteralPath $marker)) 'Successful verifier reaches downstream work.'
        }
    }

    # Execute real source-ordered preflight/stage/feed-acquisition extents. The
    # omitted source/history/parity gates are not simulated passes: this bounded
    # fixture proves only preflight-before-acquisition wiring, never a release.
    $preflightCommand = @(Find-BuilderCommands 'Invoke-ReleasePreflight')
    Assert-Fixture ($preflightCommand.Count -eq 1) 'Expected one builder preflight.'
    $preflightStatement = Get-BuilderStatement $preflightCommand[0]
    $starts = @(Find-BuilderCommands 'Start-ReleaseStage')
    $sourceStart = @($starts | Where-Object { (Get-CommandArgument $_ 'Name').Value -ceq 'source-preflight' })[0]
    $feedStart = @($starts | Where-Object { (Get-CommandArgument $_ 'Name').Value -ceq 'previous-feed' })[0]
    $packageStart = @($starts | Where-Object { (Get-CommandArgument $_ 'Name').Value -ceq 'previous-package' })[0]
    $sourceStartStatement = $sourceStart.Parent
    while ($sourceStartStatement -isnot [Management.Automation.Language.AssignmentStatementAst]) { $sourceStartStatement = $sourceStartStatement.Parent }
    $feedStartStatement = Get-BuilderStatement $feedStart
    $packageStartStatement = Get-BuilderStatement $packageStart
    $sourceCompletion = @(Find-BuilderCommands 'Complete-ReleaseStage' | Where-Object {
        $_.Extent.StartOffset -gt $preflightStatement.Extent.EndOffset -and $_.Extent.StartOffset -lt $feedStartStatement.Extent.StartOffset
    })
    Assert-Fixture ($sourceCompletion.Count -eq 1) 'Expected one source-preflight completion before feed acquisition.'
    $spaceAssignments = @($builderAst.FindAll({
        param($Node)
        $Node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $Node.Left -is [Management.Automation.Language.VariableExpressionAst] -and
        $Node.Left.VariablePath.UserPath -ceq 'effectiveMinimumFreeBytes'
    }, $true))
    Assert-Fixture ($spaceAssignments.Count -eq 1) 'Expected the actual historical-input disk-space floor calculation.'
    $flowParts = @(
        [pscustomobject]@{ Offset = $sourceStartStatement.Extent.StartOffset; Text = $sourceStartStatement.Extent.Text },
        [pscustomobject]@{ Offset = $spaceAssignments[0].Extent.StartOffset; Text = $spaceAssignments[0].Extent.Text },
        [pscustomobject]@{ Offset = $preflightStatement.Extent.StartOffset; Text = $preflightStatement.Extent.Text },
        [pscustomobject]@{ Offset = $sourceCompletion[0].Extent.StartOffset; Text = (Get-BuilderStatement $sourceCompletion[0]).Extent.Text },
        [pscustomobject]@{ Offset = $feedStartStatement.Extent.StartOffset; Text = $builderText.Substring($feedStartStatement.Extent.StartOffset, $packageStartStatement.Extent.StartOffset - $feedStartStatement.Extent.StartOffset) }
    )
    $flow = [scriptblock]::Create((@($flowParts | Sort-Object Offset | ForEach-Object { $_.Text }) -join "`n"))
    $ProjectRoot = Join-Path $fixtureRoot 'preflight-source'
    $Version = '2.0.0'
    $BuildNumber = '7'
    $MinimumFreeBytes = 0L
    $PublicGitHubRepository = 'https://github.com/example/builder-fixture'
    $ReleaseNotesRelativePath = 'docs/release.md'
    $requiredArgument = Get-CommandArgument $preflightCommand[0] 'RequiredRelativeFiles'
    $requiredFiles = @(& ([scriptblock]::Create($requiredArgument.Extent.Text)))
    foreach ($relative in $requiredFiles) { Set-FixtureFile (Join-Path $ProjectRoot $relative) '$fixtureValue = 1' }
    Set-FixtureFile (Join-Path $ProjectRoot 'pubspec.yaml') "name: fixture`nversion: 2.0.0+7`nenvironment:`n  sdk: ^3.12.2`n"
    Set-FixtureFile (Join-Path $ProjectRoot 'pubspec.lock') 'packages: {}'
    Set-FixtureFile (Join-Path $ProjectRoot '.dart_tool/package_config.json') '{"configVersion":2,"packages":[]}'
    $fixtureTools = Join-Path $fixtureRoot 'fixture-tools'
    $FlutterPath = Join-Path $fixtureTools 'flutter.bat'
    $CMakePath = Join-Path $fixtureTools 'cmake.cmd'
    Set-FixtureFile $FlutterPath "@echo off`r`nexit /b 97`r`n"
    Set-FixtureFile $CMakePath "@echo off`r`necho cmake version 3.31.0`r`nexit /b 0`r`n"
    Set-FixtureFile (Join-Path $fixtureTools 'git.cmd') "@echo off`r`necho git version 2.49.0`r`nexit /b 0`r`n"
    Set-FixtureFile (Join-Path $fixtureTools 'tar.cmd') "@echo off`r`necho bsdtar 3.8.1`r`nexit /b 0`r`n"
    Set-FixtureFile (Join-Path $fixtureTools 'dotnet.cmd') "@echo off`r`nif `"%1`"==`"--list-sdks`" echo 8.0.400 [fixture-sdk]`r`nif `"%1`"==`"--list-runtimes`" echo Microsoft.NETCore.App 8.0.20 [fixture-runtime]`r`nexit /b 0`r`n"
    Set-FixtureFile (Join-Path $fixtureTools 'cache/flutter.version.json') '{"frameworkVersion":"3.44.0","dartSdkVersion":"3.12.2"}'
    $PreviousFeedPath = $validFeed
    # This bounded fixture tests source-preflight/acquisition ordering only;
    # prepared-dependency receipt behavior has its own negative fixtures.
    $DependencyReceiptPath = ''
    $ApprovedDependencyReceiptSha256 = ''
    $PreviousFeedBytes = (Get-Item -LiteralPath $validFeed).Length
    $PreviousFeedSha256 = (Get-FileHash -LiteralPath $validFeed -Algorithm SHA256).Hash
    $UpdateSource = $PublicGitHubRepository
    $previousSourceTag = 'v1.2.3'
    $feedIndexName = 'releases.fixture.json'
    $OfflinePinnedInputs = $true
    $ReleaseInputCacheRoot = Join-Path $fixtureRoot 'ordered-flow-cache'
    $publishedPreviousFeed = Join-Path $fixtureRoot 'ordered-flow-feed.json'
    $savedPath = $env:PATH
    try {
        $env:PATH = $fixtureTools
        $metrics = New-ReleaseStageMetrics -RunId 'preflight-failure'
        $packageConfig = Join-Path $ProjectRoot '.dart_tool/package_config.json'
        Move-Item -LiteralPath $packageConfig -Destination ($packageConfig + '.held')
        Assert-Rejected { & $flow } 'required file is missing.*package_config'
        Assert-Fixture (-not (Test-Path -LiteralPath $ReleaseInputCacheRoot)) 'Actual preflight failure prevents cache/downloader entry.'
        Assert-Fixture ($metrics.Stages.Count -eq 1 -and $metrics.Stages[0].Name -ceq 'source-preflight') 'No acquisition stage starts after failed preflight.'
        Move-Item -LiteralPath ($packageConfig + '.held') -Destination $packageConfig
        $metrics = New-ReleaseStageMetrics -RunId 'preflight-success'
        & $flow
        Assert-Fixture ($metrics.Stages.Count -eq 2 -and $metrics.Stages[0].Name -ceq 'source-preflight' -and $metrics.Stages[1].Name -ceq 'previous-feed') 'Actual builder extents execute preflight before historical acquisition.'
        Assert-Fixture ($metrics.Stages[0].Outcome -ceq 'Passed' -and $metrics.Stages[1].Outcome -ceq 'Passed') 'Both bounded fixture stages complete successfully.'
        Assert-Fixture ($metrics.Stages[1].TransferredBytes -eq 0 -and (Test-Path -LiteralPath $publishedPreviousFeed)) 'Successful preflight permits validated offline feed acquisition.'
    }
    finally { $env:PATH = $savedPath }
    Write-Host "PASS: $script:assertions builder integration assertions on PowerShell $($PSVersionTable.PSVersion)."
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixtureRoot)
    if ($resolved.StartsWith($tempParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolved) -match '^bsl-builder-integration-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
    }
    else { throw 'Refusing cleanup outside the validated integration fixture directory.' }
}
