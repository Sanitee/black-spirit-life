[CmdletBinding()]
param()

# Execute the actual trusted builder's contiguous build/verify/checkpoint/pack
# branch. No application compiler, packager, network or installer is invoked.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $repositoryRoot 'tool/release/build_checkpoint.ps1')
$builderPath = Join-Path $repositoryRoot 'tool/build_stable_release_candidate.ps1'
$builderText = Get-Content -LiteralPath $builderPath -Raw
$tokens = $null; $errors = $null
$builderAst = [Management.Automation.Language.Parser]::ParseFile($builderPath, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) { throw 'Builder must parse before checkpoint branch fixtures run.' }
$script:assertions = 0
function Check([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Checkpoint builder assertion failed: $Message" }
    $script:assertions++
}
function Find-StageStatement([string]$Name) {
    $commands = @($builderAst.FindAll({ param($node)
        if ($node -isnot [Management.Automation.Language.CommandAst] -or $node.GetCommandName() -cne 'Start-ReleaseStage') { return $false }
        for ($index = 0; $index -lt $node.CommandElements.Count - 1; $index++) {
            $element = $node.CommandElements[$index]
            if ($element -is [Management.Automation.Language.CommandParameterAst] -and $element.ParameterName -ceq 'Name') {
                return $node.CommandElements[$index + 1].Value -ceq $Name
            }
        }
        return $false
    }, $true))
    Check ($commands.Count -eq 1) "Expected one actual stage boundary: $Name."
    $statement = $commands[0]
    while ($null -ne $statement.Parent -and $statement.Parent -isnot [Management.Automation.Language.StatementBlockAst]) { $statement = $statement.Parent }
    if ($null -eq $statement.Parent) { throw 'Builder stage was not in its execution block.' }
    return $statement
}
function Find-Assignment([string]$Name) {
    $assignments = @($builderAst.FindAll({ param($node)
        $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and
        $node.Left.VariablePath.UserPath -ceq $Name
    }, $true))
    Check ($assignments.Count -eq 1) "Expected one actual fixture input assignment: $Name."
    return $assignments[0]
}
$start = Find-StageStatement 'application-build'
$end = Find-StageStatement 'feed-verification'
Check ($end.Extent.StartOffset -gt $start.Extent.EndOffset) 'Actual build-to-package stage order changed.'
$flowText = $builderText.Substring($start.Extent.StartOffset, $end.Extent.StartOffset - $start.Extent.StartOffset)
# PowerShell cannot mock a static .NET call. Replace only this AST-identified
# metadata read with an explicit fixture boundary; retain its real conditional
# identity gate and every build/validation/checkpoint/packaging branch unchanged.
$identityAssignment = Find-Assignment 'productInfo'
$identityCalls = @($identityAssignment.FindAll({ param($node)
    $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
    $node.Static -and $node.Member.Value -ceq 'GetVersionInfo' -and
    $node.Expression.TypeName.FullName -ceq 'System.Diagnostics.FileVersionInfo' -and
    $node.Arguments.Count -eq 1 -and $node.Arguments[0].VariablePath.UserPath -ceq 'bundleExecutable'
}, $true))
Check ($identityCalls.Count -eq 1) 'Expected the actual static file-version metadata boundary.'
$identityOffset = $identityAssignment.Extent.StartOffset - $start.Extent.StartOffset
$flowText = $flowText.Remove($identityOffset, $identityAssignment.Extent.Text.Length).Insert(
    $identityOffset, '$productInfo = Get-FixtureVersionInfo -Path $bundleExecutable')
$flow = [scriptblock]::Create($flowText)
foreach ($name in @('requiredBundleRelativeFiles', 'ForbiddenPackagedArtifactPattern')) {
    $assignment = Find-Assignment $name
    . ([scriptblock]::Create($assignment.Extent.Text))
}
$exitFunctions = @($builderAst.FindAll({ param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Assert-LastExitCode'
}, $true))
Check ($exitFunctions.Count -eq 1) 'Expected actual native exit-code assertion.'
. ([scriptblock]::Create($exitFunctions[0].Extent.Text))

# Keep the synthetic root short enough for .NET Framework's legacy path limit,
# including the real nested packaged-license paths copied into the checkpoint.
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('bsl-cb-' + [Guid]::NewGuid().ToString('N').Substring(0, 16))
if (Test-Path -LiteralPath $fixtureRoot) { throw 'Synthetic checkpoint root must be new.' }
$null = [IO.Directory]::CreateDirectory($fixtureRoot)
function Put([string]$Path, [string]$Text) {
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
$ProjectRoot = Join-Path $fixtureRoot 'source'
Put (Join-Path $ProjectRoot 'lib/fixture.dart') 'synthetic source only'
$ExecutableName = 'Fixture.exe'; $UpdaterHelperName = 'FixtureUpdater.exe'; $FishHostHelperName = 'FixtureHost.exe'
$DisplayName = 'Checkpoint Fixture'; $Version = '2.0.0'; $BuildNumber = '7'
$identityFile = Join-Path $fixtureRoot 'synthetic-identity.bin'
Put $identityFile 'synthetic executable bytes, never executed'
$runtimeFile = Join-Path $fixtureRoot 'synthetic-runtime.dll'
Put $runtimeFile 'synthetic runtime bytes'
$VelopackRuntimeSha256 = Hash $runtimeFile
$sourceCommit = 'a' * 40
$UpdateSourceEnvironmentKey = 'FIXTURE_SOURCE'; $UpdateSource = 'https://example.invalid/fixture'
$UpdateChannel = 'fixture-channel'; $PackageId = 'Fixture.App'
$RunnerIcon = Join-Path $fixtureRoot 'fixture.ico'; Put $RunnerIcon 'synthetic icon'
$ReleaseNotesPath = Join-Path $fixtureRoot 'fixture-notes.md'; Put $ReleaseNotesPath 'synthetic notes'
$vpkDll = Join-Path $fixtureRoot 'fixture-vpk.dll'
$FlutterPath = 'Invoke-FixtureCompiler'; $DotnetPath = 'Invoke-FixturePackager'
$script:events = [Collections.Generic.List[string]]::new()
$script:validationPaths = [Collections.Generic.List[string]]::new()
$script:packagePaths = [Collections.Generic.List[string]]::new()
$script:failPackaging = $false; $script:failPayload = $false
$script:badIdentity = $false
$script:compileCount = 0; $script:resetCount = 0; $script:packageCount = 0
$script:sessionValidationCount = 0; $script:textValidationCount = 0; $script:sqliteValidationCount = 0
$stableEvidence = [ordered]@{ schemaVersion = 1; fixture = 'approved-context' }
$stableContext = [pscustomobject]@{ Evidence = $stableEvidence; Fingerprint = Get-CheckpointObjectHash $stableEvidence }
$changedEvidence = [ordered]@{ schemaVersion = 1; fixture = 'changed-context' }
$changedContext = [pscustomobject]@{ Evidence = $changedEvidence; Fingerprint = Get-CheckpointObjectHash $changedEvidence }
$script:recapturedContext = $stableContext

# These are explicit external-boundary mocks. Actual inventory/copy/receipt
# implementations and the builder's stage/if/foreach/exit-code branches execute.
function Start-ReleaseStage { param($Metrics, [string]$Name)
    $script:events.Add('start:' + $Name)
    [pscustomobject]@{ Name = $Name; Outcome = 'Running' }
}
function Complete-ReleaseStage { param($Metrics, $Stage, [string]$Outcome, [string]$CacheState)
    $Stage.Outcome = $Outcome; $script:events.Add('complete:' + $Stage.Name)
}
function Assert-CleanSource { param([string]$ProjectRoot, [string]$ExpectedCommit)
    $script:events.Add('source-check')
}
function Reset-VerifiedWindowsBuildTree { param([string]$ProjectRoot, [string]$BundleDirectory)
    $script:resetCount++; $script:events.Add('reset')
    if (Test-Path -LiteralPath $BundleDirectory) { throw 'Synthetic compilation output must be new.' }
}
function Invoke-FixtureCompiler {
    $script:compileCount++; $script:events.Add('compile')
    foreach ($relative in @($requiredBundleRelativeFiles) + @($UpdaterHelperName, $FishHostHelperName, 'data/app.so')) {
        Put (Join-Path $BundleDirectory $relative) 'synthetic fixture payload'
    }
    [IO.File]::Copy($identityFile, (Join-Path $BundleDirectory $ExecutableName), $false)
    [IO.File]::Copy($runtimeFile, (Join-Path $BundleDirectory 'velopack_libc.dll'), $false)
    $global:LASTEXITCODE = 0
}
function Assert-OrdinaryFile { param([string]$Path)
    $script:validationPaths.Add($Path)
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer) { throw 'Fixture expected an ordinary file.' }
    return $item
}
function Assert-SessionImportPayload { param([string]$Directory, [string]$SourceDirectory)
    $script:sessionValidationCount++; $script:events.Add('session-check')
}
function Assert-NoTextMarker { param([string]$Path, [string[]]$Markers)
    $script:textValidationCount++; $script:validationPaths.Add($Path); $script:events.Add('text-check')
    if ($script:failPayload) { throw 'Synthetic payload validation failure.' }
}
function Get-FixtureVersionInfo { param([string]$Path)
    $script:validationPaths.Add($Path)
    [pscustomobject]@{ ProductName = if ($script:badIdentity) { 'Incorrect fixture product' } else { $DisplayName }; ProductVersion = "$Version+$BuildNumber" }
}
function Test-SqliteFileHeader { param([string]$Path)
    $script:sqliteValidationCount++; $script:validationPaths.Add($Path)
    return $false
}
function Get-ReleaseBuildRetryContext { $script:recapturedContext }
function Invoke-FixturePackager {
    $script:packageCount++; $script:events.Add('package')
    $packIndex = [array]::IndexOf([object[]]$args, '--packDir')
    if ($packIndex -lt 0 -or $packIndex + 1 -ge $args.Count) { throw 'Actual packaging call lost its bundle input.' }
    $packDirectory = [string]$args[$packIndex + 1]
    $script:packagePaths.Add($packDirectory)
    # A packager is allowed to mutate its own staging. This must not poison the
    # previously accepted receipt or its independently copied immutable bundle.
    Put (Join-Path $packDirectory 'packager-staging-only.txt') 'synthetic mutation'
    $global:LASTEXITCODE = if ($script:failPackaging) { 53 } else { 0 }
}
function Invoke-FixtureRun([string]$Name, [string]$Receipt, [string]$ReceiptHash, $Context) {
    $RunRoot = Join-Path $fixtureRoot $Name
    $null = [IO.Directory]::CreateDirectory($RunRoot)
    $FeedPath = Join-Path $RunRoot 'feed'
    $BundleDirectory = Join-Path $RunRoot 'compiler-output'
    $ResumeBundleReceiptPath = $Receipt
    $ApprovedResumeBundleReceiptSha256 = $ReceiptHash
    $buildRetryContext = $Context; $buildRetryArguments = @{}
    $metrics = [pscustomobject]@{}; $activeStage = $null
    $failure = ''
    try { . $flow }
    catch { $failure = $_.Exception.Message }
    [pscustomobject]@{ Error = $failure; RunRoot = $RunRoot; BundleDirectory = $BundleDirectory }
}

$savedExitCode = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
$savedExitCodeValue = if ($null -eq $savedExitCode) { $null } else { $savedExitCode.Value }
try {
    $script:failPackaging = $true
    $first = Invoke-FixtureRun 'first-package-failure' '' '' $stableContext
    Check ($first.Error -match 'Velopack release-candidate package generation failed with exit code 53') ('Forced native packaging failure was not propagated: ' + $first.Error)
    Check ($script:compileCount -eq 1 -and $script:resetCount -eq 1 -and $script:packageCount -eq 1) 'First run did not compile/reset/package exactly once.'
    Check ($script:sessionValidationCount -eq 1 -and $script:textValidationCount -gt 0 -and $script:sqliteValidationCount -gt 0) 'First run omitted payload checks.'
    $receipt = Join-Path $first.RunRoot 'build-checkpoint/bundle-checkpoint.json'
    Check (Test-Path -LiteralPath $receipt -PathType Leaf) 'Packaging failure lost the completed checkpoint receipt.'
    $receiptHash = Hash $receipt
    $checkpointBundle = Join-Path (Split-Path -Parent $receipt) 'bundle'
    $checkpointTree = Get-CheckpointTree $checkpointBundle
    Check ((Hash (Join-Path $checkpointBundle $ExecutableName)) -ceq (Hash $identityFile)) 'Checkpoint application bytes changed.'
    Check (-not (Test-Path -LiteralPath (Join-Path $checkpointBundle 'packager-staging-only.txt'))) 'Packager mutation reached retained checkpoint.'
    Check ($script:packagePaths[0] -ceq (Join-Path $first.RunRoot 'verified-bundle-staging')) 'First packager did not receive independent verified staging.'
    $verifiedIndex = [array]::IndexOf($script:events.ToArray(), 'complete:payload-verification')
    $packageIndex = [array]::IndexOf($script:events.ToArray(), 'package')
    Check ($verifiedIndex -ge 0 -and $packageIndex -gt $verifiedIndex) 'Packaging ran before verified payload.'

    $beforeText = $script:textValidationCount; $beforeSqlite = $script:sqliteValidationCount
    $beforePaths = $script:validationPaths.Count
    $script:failPackaging = $false
    $second = Invoke-FixtureRun 'valid-resume' $receipt $receiptHash $stableContext
    Check ($second.Error.Length -eq 0) 'Valid resume failed.'
    Check ($script:compileCount -eq 1 -and $script:resetCount -eq 1) 'Resume repeated compilation or reset.'
    Check ($script:packageCount -eq 2 -and $script:sessionValidationCount -eq 2) 'Resume omitted packaging/helper validation.'
    Check ($script:textValidationCount -eq 2 * $beforeText -and $script:sqliteValidationCount -eq 2 * $beforeSqlite) 'Resume skipped privacy/payload validation.'
    Check ($script:validationPaths.Count -eq 2 * $beforePaths) 'Resume did not repeat the same file validation boundaries.'
    $resumePrefix = (Join-Path $second.RunRoot 'verified-bundle-staging') + [IO.Path]::DirectorySeparatorChar
    foreach ($path in @($script:validationPaths.ToArray())[$beforePaths..($script:validationPaths.Count - 1)]) {
        Check ($path.StartsWith($resumePrefix, [StringComparison]::OrdinalIgnoreCase)) 'Resume validated a different bundle from its fresh restored staging.'
    }
    Check ($script:packagePaths[1] -ceq $second.BundleDirectory) 'Resume packaged a different bundle than it validated.'
    Check ((Hash $receipt) -ceq $receiptHash -and (Get-CheckpointTree $checkpointBundle).Fingerprint -ceq $checkpointTree.Fingerprint) 'Resume changed accepted checkpoint evidence.'

    $beforeText = $script:textValidationCount
    $changed = Invoke-FixtureRun 'changed-context' $receipt $receiptHash $changedContext
    Check ($changed.Error -match 'context, schema or passed evidence') 'Changed build key was not refused.'
    Check ($script:compileCount -eq 1 -and $script:resetCount -eq 1 -and $script:packageCount -eq 2 -and $script:textValidationCount -eq $beforeText) 'Changed-key restore ran downstream work.'
    Check (-not (Test-Path -LiteralPath (Join-Path $changed.RunRoot 'verified-bundle-staging'))) 'Changed-key restore created staging.'

    $script:failPayload = $true
    $failedValidation = Invoke-FixtureRun 'resume-payload-failure' $receipt $receiptHash $stableContext
    Check ($failedValidation.Error -match 'Synthetic payload validation failure') 'Resumed payload failure was suppressed.'
    Check ($script:packageCount -eq 2 -and $script:compileCount -eq 1) 'Failed resumed validation reached packaging/compiler.'
    Check ((Hash $receipt) -ceq $receiptHash) 'Resumed validation failure damaged retained receipt.'
    $script:failPayload = $false

    $script:badIdentity = $true
    $wrongIdentity = Invoke-FixtureRun 'resume-wrong-identity' $receipt $receiptHash $stableContext
    Check ($wrongIdentity.Error -match 'does not have the plain Stable product identity') 'Actual product-identity gate was bypassed.'
    Check ($script:packageCount -eq 2) 'Wrong restored product identity reached packaging.'
    $script:badIdentity = $false

    $script:recapturedContext = $changedContext
    $changedDuringBuild = Invoke-FixtureRun 'inputs-changed-during-build' '' '' $stableContext
    Check ($changedDuringBuild.Error -match 'Build inputs changed during compilation/verification') 'Prepackaging input recapture was bypassed.'
    Check ($script:packageCount -eq 2) 'Changed input context reached packaging.'
    Check (-not (Test-Path -LiteralPath (Join-Path $changedDuringBuild.RunRoot 'build-checkpoint'))) 'Changed inputs produced a reusable checkpoint.'
    Write-Host "Checkpoint builder tests passed: $script:assertions assertions. Synthetic evidence retained: $fixtureRoot"
}
finally {
    if ($null -eq $savedExitCode) { Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
    else { $global:LASTEXITCODE = $savedExitCodeValue }
}
