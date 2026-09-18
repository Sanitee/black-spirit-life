[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$engine = Join-Path $repository 'tool/release/workflow_state.ps1'
$runner = Join-Path $repository 'tool/release/run_release_workflow.ps1'
. $engine
$script:assertions = 0
function Assert-Fixture([bool]$Value, [string]$Message) {
    if (-not $Value) { throw "Workflow fixture failed: $Message" }; $script:assertions++
}
function Assert-Rejected([scriptblock]$Action, [string]$Pattern) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    Assert-Fixture ($null -ne $caught -and $caught -match $Pattern) "Expected $Pattern; received $caught"
}
function Write-Fixture([string]$Path, [string]$Text) {
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
    return $Path
}
function Save-Json([string]$Path, $Value) {
    $null = Write-Fixture $Path ($Value | ConvertTo-Json -Depth 60)
    return Get-WorkflowHash $Path
}
function File-Record([string]$Path) { return [pscustomobject]@{path = $Path; sha256 = Get-WorkflowHash $Path} }
function Save-Manifest($Fixture) {
    $Fixture.Hash = Save-Json $Fixture.Path $Fixture.Manifest
}
function Invoke-FixtureMode($Fixture, [string]$Mode, [hashtable]$Extra = @{}) {
    $args = @{ManifestPath = $Fixture.Path; ApprovedManifestSha256 = $Fixture.Hash; Mode = $Mode}
    & $runner @args @Extra | Out-Null
}
function New-WorkflowFixture {
    $root = Join-Path $fixtureRoot ([Guid]::NewGuid().ToString('N'))
    $source = Join-Path $root 'beta'
    $overlay = Join-Path $root 'overlay'
    $null = [IO.Directory]::CreateDirectory($source)
    $null = [IO.Directory]::CreateDirectory($overlay)
    $null = Write-Fixture (Join-Path $source 'lib/main.dart') 'synthetic approved source'
    $null = Write-Fixture (Join-Path $source 'test/first_test.dart') 'synthetic full test one'
    $null = Write-Fixture (Join-Path $source 'test/second_test.dart') 'synthetic full test two'
    $promotionPlan = [pscustomobject]@{schemaVersion = 1; approvalReference = 'synthetic approved complete source'; pruneDirectories = @(); omitFiles = @(); replaceFiles = @(); addFiles = @()}
    $promotionPlanPath = Join-Path $root 'promotion-plan.json'
    $promotionHash = Save-Json $promotionPlanPath $promotionPlan
    $promotionOutput = Join-Path $root 'promoted'
    $sourceHash = (Get-ReleasePromotionTree $source).fingerprintSha256
    $promotion = Invoke-ReleaseSourcePromotion -SourceRoot $source -OverlayRoot $overlay -PlanPath $promotionPlanPath -ExpectedPlanSha256 $promotionHash -ExpectedSourceFingerprint $sourceHash -OutputRoot $promotionOutput
    $candidateSource = Join-Path $promotionOutput 'source'
    $releasePlan = Get-Content -LiteralPath (Join-Path $repository 'docs/release-plan.v1.example.json') -Raw | ConvertFrom-Json
    $planPath = Join-Path $root 'release-plan.json'
    $null = Save-Json $planPath $releasePlan
    $commandScript = Join-Path $root 'synthetic-command.ps1'
    $null = Write-Fixture $commandScript @'
[CmdletBinding(PositionalBinding=$false)]
param([string]$Report, [string]$PlanHash, [string]$PackageHash, [string]$CandidateManifest, [string]$FailOnce, [string]$MutatePath, [switch]$NoReport, [switch]$BadReport, [switch]$Installed, [switch]$Build, [Parameter(Position=0,ValueFromRemainingArguments=$true)][string[]]$Tests)
$ErrorActionPreference = 'Stop'
$document = [ordered]@{schemaVersion=1; success=(-not $BadReport.IsPresent); releasePlanSha256=$PlanHash; tests=@($Tests)}
if ($Installed) {
    $document.purpose='installed-payload-parity'; $document.packageSha256=$PackageHash
    $document.expectedInventorySha256=('A'*64); $document.installedInventorySha256=('A'*64)
    $document.missing=@(); $document.unexpected=@(); $document.changed=@()
}
if ($Build) {
    $candidate=Get-Content -LiteralPath $CandidateManifest -Raw | ConvertFrom-Json
    $document.purpose='candidate-build'; $document.sourceCommit=$candidate.sourceCommit
    $document.version=$candidate.version; $document.buildNumber=$candidate.buildNumber
    $document.candidateManifest=[ordered]@{path=$CandidateManifest; sha256=(Get-FileHash -LiteralPath $CandidateManifest -Algorithm SHA256).Hash}
}
if (-not $NoReport) { [IO.File]::WriteAllText($Report, ($document | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false)) }
if ($MutatePath) { [IO.File]::WriteAllText($MutatePath, 'source changed during command') }
Write-Output 'Synthetic command executed; no application or network used.'
if ($FailOnce) { $marker=Join-Path $FailOnce 'transient.marker'; if (-not (Test-Path -LiteralPath $marker)) { [IO.File]::WriteAllText($marker, 'synthetic transient failure'); exit 7 } }
exit 0
'@
    $runtime = (Get-Process -Id $PID).Path
    $packagePath = Write-Fixture (Join-Path $root 'synthetic-package.bin') 'not a real application package'
    $files = @(@('workflow_state.ps1', 'run_release_workflow.ps1', 'source_promotion.ps1', 'source_inventory.ps1', 'release_plan.ps1', 'verified_input_cache.ps1') | ForEach-Object { File-Record (Join-Path $repository "tool/release/$_") })
    $files += @(File-Record $runtime; File-Record $commandScript)
    $planHash = Get-WorkflowHash $planPath
    $candidateArtifacts=@(@('velopack-setup','full-package','delta-package','update-feed') | ForEach-Object {
        $artifactFile=Write-Fixture (Join-Path $root ($_.ToString()+'.bin')) ('synthetic '+$_)
        [pscustomobject]@{role=$_; path=[IO.Path]::GetFileName($artifactFile); bytes=(Get-Item -LiteralPath $artifactFile).Length; sha256=Get-WorkflowHash $artifactFile}
    })
    $candidateManifestPath=Join-Path $root 'candidate-manifest.json'
    $null=Save-Json $candidateManifestPath ([pscustomobject]@{schemaVersion=2; publicCandidate=$true;
        version=$releasePlan.identity.version; buildNumber=$releasePlan.identity.buildNumber; sourceCommit=$releasePlan.source.expectedCommit;
        sourceTag=$releasePlan.source.expectedTag; packageId=$releasePlan.identity.packageId; channel=$releasePlan.identity.channel;
        updateSource=$releasePlan.identity.repository; releasePlan=[pscustomobject]@{sha256=$planHash}; artifacts=$candidateArtifacts})
    $gates = @($script:ReleaseWorkflowKinds | ForEach-Object {
        $kind = $_
        $validation = [pscustomobject]@{type='json'; reportPath='result.json'; checks=@([pscustomobject]@{field='success'; equals=$true}, [pscustomobject]@{field='releasePlanSha256'; equals=$planHash}); package=$null}
        $command = [pscustomobject]@{executable=(File-Record $runtime); workingDirectory=$candidateSource; arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$commandScript,'-Report','{reportPath}','-PlanHash',$planHash)}
        if ($kind -ceq 'installed-parity') { $validation.type='installed-payload'; $validation.package=File-Record $packagePath; $command.arguments+=@('-Installed','-PackageHash',(Get-WorkflowHash $packagePath)) }
        if ($kind -ceq 'build') { $validation.type='candidate-build'; $command.arguments+=@('-Build','-CandidateManifest',$candidateManifestPath) }
        if ($kind -cin @('ui-parity','themed-installer','publication')) { $command=$null; $validation=[pscustomobject]@{type='review'; reportPath=$null; checks=@(); package=$null} }
        $tests=@(); $discovery=$null
        if ($kind -ceq 'application-tests') {
            $discovery=[pscustomobject]@{root=(Join-Path $candidateSource 'test'); suffix='_test.dart'}
            $tests=@(File-Record (Join-Path $candidateSource 'test/first_test.dart'); File-Record (Join-Path $candidateSource 'test/second_test.dart'))
        }
        $inputs=@()
        if ($kind -ceq 'build') { $inputs=@(File-Record $candidateManifestPath) }
        [pscustomobject]@{id=$kind; kind=$kind; description='Synthetic '+$kind; command=$command; testDiscovery=$discovery; resolvedTests=$tests; inputs=$inputs; validation=$validation}
    })
    $manifest = [pscustomobject]@{
        schemaVersion=1; phase='acceptance'; approvalReference='Synthetic workflow fixture, no publication authority'; stateRoot=(Join-Path $root 'state')
        releasePlan=(File-Record $planPath); promotionEvidence=(File-Record (Join-Path $promotionOutput 'promotion-report.json'))
        source=[pscustomobject]@{root=$candidateSource; generatedDirectories=@(); fingerprintSha256=$promotion.candidate.fingerprintSha256}
        context=[pscustomobject]@{powershellVersion=$PSVersionTable.PSVersion.ToString(); osVersion=[Environment]::OSVersion.VersionString; files=$files; environment=@(@('PATH','PATHEXT','FLUTTER_ROOT','PUB_CACHE','BSL_WORKFLOW_TEST_CONTEXT') | ForEach-Object { [pscustomobject]@{name=$_; value=[Environment]::GetEnvironmentVariable($_,'Process')} })}
        gates=$gates
    }
    $fixture=[pscustomobject]@{Root=$root; Source=$candidateSource; Path=(Join-Path $root 'workflow.json'); Hash=''; Manifest=$manifest; Script=$commandScript; Package=$packagePath}
    Save-Manifest $fixture
    return $fixture
}
function Register-FixtureGate($Fixture, [string]$Gate, [string]$Outcome='passed') {
    $workflow=Read-ReleaseWorkflow $Fixture.Path $Fixture.Hash
    $proof=Write-Fixture (Join-Path $Fixture.Root ($Gate+'-external.txt')) 'synthetic independently reviewed evidence'
    $registration=[pscustomobject]@{schemaVersion=1; workflowSha256=$Fixture.Hash; gateId=$Gate; releasePlanSha256=$Fixture.Manifest.releasePlan.sha256;
        promotionEvidenceSha256=$Fixture.Manifest.promotionEvidence.sha256; contextSha256=$workflow.ContextSha256;
        outcome=$Outcome; reviewReference='Explicit synthetic review, not real acceptance'; evidence=@(File-Record $proof)}
    $path=Join-Path $Fixture.Root ($Gate+'-registration.json')
    $hash=Save-Json $path $registration
    Invoke-FixtureMode $Fixture RegisterEvidence @{StepId=$Gate; EvidenceRegistrationPath=$path; ApprovedEvidenceRegistrationSha256=$hash; ConfirmReviewedEvidence=$true}
}

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('bsl-workflow-fixture-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($fixtureRoot)
try {
    $fixture=New-WorkflowFixture
    Invoke-FixtureMode $fixture Preflight
    Assert-Fixture (-not (Test-Path -LiteralPath $fixture.Manifest.stateRoot)) 'Preflight creates no output and starts no commands.'
    Invoke-FixtureMode $fixture Initialize
    Assert-Rejected { Invoke-FixtureMode $fixture Initialize } 'already exists'
    $workflow=Read-ReleaseWorkflow $fixture.Path $fixture.Hash
    $lock=Open-WorkflowLock $workflow
    try { Assert-Rejected { Invoke-FixtureMode $fixture RunNext } 'owns this source' } finally { $lock.Dispose() }
    Assert-Rejected { Invoke-FixtureMode $fixture RunStep @{StepId='application-tests'} } 'first unmet gate'
    foreach ($gate in $fixture.Manifest.gates) {
        if ($gate.validation.type -ceq 'review') {
            Assert-Rejected { Invoke-FixtureMode $fixture RunNext } 'requires reviewed external evidence'
            Register-FixtureGate $fixture $gate.id
        } else { Invoke-FixtureMode $fixture RunNext }
        $state=Read-WorkflowState $workflow
        Assert-Fixture (@($state.gates | Where-Object { $_.id -ceq $gate.id -and $_.status -ceq 'passed' }).Count -eq 1) "Exact $($gate.id) gate accepted."
        if ($gate.kind -ceq 'upload') { Assert-Fixture ($state.phase -ceq 'uploaded' -and -not $state.complete) 'Uploaded never means published or verified.' }
        if ($gate.kind -ceq 'publication') { Assert-Fixture ($state.phase -ceq 'published' -and -not $state.complete) 'Published still requires real public verification.' }
    }
    $state=Read-WorkflowState $workflow
    Assert-Fixture ($state.complete -and $state.phase -ceq 'publicly-verified') 'Completion requires every distinct accepted gate.'
    Assert-Rejected { Invoke-FixtureMode $fixture RunNext } 'already accepted'
    $acceptedStateJson=$state | ConvertTo-Json -Depth 60
    $statePath=Join-Path $fixture.Manifest.stateRoot 'status.json'
    $damagedStates=@(
        @{pattern='nonempty successful evidence'; change={param($s) $s.gates[0].attempts[-1].evidence=@()}},
        @{pattern='explicit JSON arrays'; change={param($s) $s.gates[0].attempts[-1].evidence=$null}},
        @{pattern='explicit JSON arrays'; change={param($s) $s.gates[0].attempts[-1].evidence=$s.gates[0].attempts[-1].evidence[0]}},
        @{pattern='origin'; change={param($s) $s.gates[0].attempts[-1].origin='unverified'}},
        @{pattern='origin'; change={param($s) $s.gates[0].attempts[-1].origin='bound-evidence-validation'}},
        @{pattern='origin'; change={param($s) $s.gates[0].attempts[-1].origin='external-reviewed'}},
        @{pattern='integer zero exit'; change={param($s) $s.gates[0].attempts[-1].exitCode=$null}},
        @{pattern='integer zero exit'; change={param($s) $s.gates[0].attempts[-1].exitCode='0'}},
        @{pattern='integer zero exit'; change={param($s) $s.gates[0].attempts[-1].exitCode=$false}},
        @{pattern='integer zero exit'; change={param($s) $s.gates[0].attempts[-1].exitCode=7}},
        @{pattern='origin'; change={param($s) $s.gates[8].attempts[-1].origin='reviewed-command'}},
        @{pattern='non-command'; change={param($s) $s.gates[8].attempts[-1].exitCode=0}},
        @{pattern='unmet gate'; change={param($s) $s.gates[0].status='pending'}},
        @{pattern='unmet gate'; change={param($s) $s.gates[0].status='failed'}},
        @{pattern='unmet gate'; change={param($s) $s.gates[0].status='running'}}
    )
    foreach ($case in $damagedStates) {
        $damaged=$acceptedStateJson | ConvertFrom-Json
        & $case.change $damaged
        $null=Save-Json $statePath $damaged
        Assert-Rejected { Read-WorkflowState $workflow } $case.pattern
    }
    $null=Save-Json $statePath ($acceptedStateJson | ConvertFrom-Json)
    Assert-Fixture ((Read-WorkflowState $workflow).complete) 'Unmodified command and external-review origins remain valid.'
    $appRecord=@($state.gates | Where-Object id -CEQ 'application-tests')[0]
    $report=@($appRecord.attempts[-1].evidence | Where-Object path -Like '*result.json')[0]
    $actualReport=Get-Content -LiteralPath $report.path -Raw | ConvertFrom-Json
    Assert-Fixture ($actualReport.tests.Count -eq 2) 'Actual native invocation receives the full resolved test list.'
    $null=Write-Fixture $report.path '{}'
    Assert-Rejected { Invoke-FixtureMode $fixture Status } 'changed'

    $retry=New-WorkflowFixture
    $retry.Manifest.gates[0].command.arguments += @('-FailOnce',$retry.Manifest.stateRoot)
    Save-Manifest $retry
    Invoke-FixtureMode $retry Initialize
    Assert-Rejected { Invoke-FixtureMode $retry RunNext } 'nonzero'
    Assert-Rejected { Invoke-FixtureMode $retry RunStep @{StepId='application-tests'} } 'first unmet'
    Invoke-FixtureMode $retry RunNext
    $retryState=Read-WorkflowState (Read-ReleaseWorkflow $retry.Path $retry.Hash)
    Assert-Fixture ($retryState.gates[0].attempts.Count -eq 2 -and $retryState.gates[0].attempts[0].outcome -ceq 'failed' -and $retryState.gates[0].attempts[1].outcome -ceq 'passed') 'Complete rerun preserves failure history and uses fresh evidence.'
    Assert-Fixture (@(Get-ChildItem -LiteralPath $retry.Manifest.stateRoot -Filter 'status-history-*.json' -File).Count -ge 3) 'Atomic updates retain previous status evidence.'

    $bad=New-WorkflowFixture
    $bad.Manifest.gates[0].command.arguments += '-BadReport'; Save-Manifest $bad
    Invoke-FixtureMode $bad Initialize
    Assert-Rejected { Invoke-FixtureMode $bad RunNext } 'evidence.*assertion'
    $badState=Read-WorkflowState (Read-ReleaseWorkflow $bad.Path $bad.Hash)
    Assert-Fixture ($badState.gates[0].status -ceq 'failed') 'Exit zero alone never accepts bad evidence.'

    $missing=New-WorkflowFixture
    $missing.Manifest.gates[0].command.arguments += '-NoReport'; Save-Manifest $missing
    Invoke-FixtureMode $missing Initialize
    Assert-Rejected { Invoke-FixtureMode $missing RunNext } 'missing'
    $mutation=New-WorkflowFixture
    $mutation.Manifest.gates[0].command.arguments += @('-MutatePath',(Join-Path $mutation.Source 'lib/main.dart')); Save-Manifest $mutation
    Invoke-FixtureMode $mutation Initialize
    Assert-Rejected { Invoke-FixtureMode $mutation RunNext } 'complete source'

    $schema=New-WorkflowFixture
    $original=$schema.Manifest | ConvertTo-Json -Depth 60
    $mutations=@(
        @{pattern='schema'; change={param($m) $m.schemaVersion=$true}},
        @{pattern='distinct gate'; change={param($m) $m.gates=@($m.gates | Where-Object kind -CNE 'artifact-privacy')}},
        @{pattern='Duplicate|duplicate'; change={param($m) $m.gates[1].id=$m.gates[0].id}},
        @{pattern='Installed parity'; change={param($m) $m.gates[6].validation.type='json'; $m.gates[6].validation.package=$null}},
        @{pattern='Publication'; change={param($m) $m.gates[11].command=$m.gates[0].command; $m.gates[11].validation=$m.gates[0].validation}},
        @{pattern='overlap'; change={param($m) $m.stateRoot=Join-Path $m.source.root 'output'}},
        @{pattern='traversal|relative'; change={param($m) $m.stateRoot=$m.stateRoot+'\..\escape'}},
        @{pattern='safe relative'; change={param($m) $m.stateRoot=$m.stateRoot+':ads'}},
        @{pattern='aliases'; change={param($m) $m.stateRoot=$m.stateRoot+'.'}},
        @{pattern='runtime'; change={param($m) $m.context.powershellVersion='0.0'}},
        @{pattern='engine/helper'; change={param($m) $m.context.files=@($m.context.files | Where-Object path -NotLike '*workflow_state.ps1')}},
        @{pattern='full test|narrower'; change={param($m) $m.gates[2].resolvedTests=@($m.gates[2].resolvedTests[0])}},
        @{pattern='name-filtered'; change={param($m) $m.gates[2].command.arguments += '--name=subset'}},
        @{pattern='invocation prefix'; change={param($m) $m.gates[0].command.arguments=@('-Command','unsafe','-File',$m.gates[0].command.arguments[5],'-Report','{reportPath}')}},
        @{pattern='placeholder'; change={param($m) $m.gates[0].command.arguments += '{arbitrary}'}},
        @{pattern='traversal'; change={param($m) $m.gates[0].validation.reportPath='../report.json'}}
    )
    foreach ($case in $mutations) {
        $schema.Manifest=$original | ConvertFrom-Json
        & $case.change $schema.Manifest
        Save-Manifest $schema
        Assert-Rejected { Read-ReleaseWorkflow $schema.Path $schema.Hash } $case.pattern
    }
    $schema.Manifest=$original | ConvertFrom-Json; Save-Manifest $schema
    Assert-Rejected { Read-ReleaseWorkflow $schema.Path ('0'*64) } 'hash mismatch'
    $null=Write-Fixture (Join-Path $schema.Source 'new-untracked.dart') 'added production code'
    Assert-Rejected { Read-ReleaseWorkflow $schema.Path $schema.Hash } 'complete source'

    $context=New-WorkflowFixture
    $contextBefore=[Environment]::GetEnvironmentVariable('BSL_WORKFLOW_TEST_CONTEXT','Process')
    try {
        [Environment]::SetEnvironmentVariable('BSL_WORKFLOW_TEST_CONTEXT','changed','Process')
        Assert-Rejected { Read-ReleaseWorkflow $context.Path $context.Hash } 'environment changed'
    } finally { [Environment]::SetEnvironmentVariable('BSL_WORKFLOW_TEST_CONTEXT',$contextBefore,'Process') }
    $null=Write-Fixture $context.Script 'exit 0'
    Assert-Rejected { Read-ReleaseWorkflow $context.Path $context.Hash } 'changed'

    $interrupted=New-WorkflowFixture
    Invoke-FixtureMode $interrupted Initialize
    $interruptedWorkflow=Read-ReleaseWorkflow $interrupted.Path $interrupted.Hash
    $interruptedState=Read-WorkflowState $interruptedWorkflow
    $interruptedState.gates[0].status='running'
    $interruptedState.gates[0].attempts=@([pscustomobject]@{id='synthetic-crash'; outcome='running'; finishedAtUtc=$null; processId=$null; processStartedAtUtc=$null; evidence=@()})
    Update-WorkflowStatus $interruptedWorkflow $interruptedState
    Assert-Rejected { Invoke-FixtureMode $interrupted RunNext } 'Interrupted/running'
    $interruptedState.gates[0].attempts[0].processId=$PID
    $interruptedState.gates[0].attempts[0].processStartedAtUtc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
    Update-WorkflowStatus $interruptedWorkflow $interruptedState
    Assert-Rejected { Invoke-FixtureMode $interrupted RecoverInterrupted @{StepId='source-parity'; ConfirmPriorProcessStopped=$true} } 'still running'
    $interruptedState.gates[0].attempts[0].processStartedAtUtc='2000-01-01T00:00:00.0000000Z'
    Update-WorkflowStatus $interruptedWorkflow $interruptedState
    Invoke-FixtureMode $interrupted RecoverInterrupted @{StepId='source-parity'; ConfirmPriorProcessStopped=$true}
    $recovered=Read-WorkflowState $interruptedWorkflow
    Assert-Fixture ($recovered.gates[0].status -ceq 'failed' -and $recovered.gates[0].attempts[0].outcome -ceq 'interrupted') 'Recovery does not claim incomplete work passed or kill a PID.'

    $phased=New-WorkflowFixture
    $acceptance=$phased.Manifest | ConvertTo-Json -Depth 60
    $phased.Manifest.phase='prepare-build'; $phased.Manifest.gates=@($phased.Manifest.gates | Select-Object -First 4)
    $phased.Manifest.gates[0].command=$null
    $phased.Manifest.gates[0].validation=[pscustomobject]@{type='promotion'; reportPath=$null; checks=@(); package=$null}
    Save-Manifest $phased
    Invoke-FixtureMode $phased Initialize
    $oldPath=$phased.Path; $oldHash=$phased.Hash; $oldFirst=$phased.Manifest.gates[0]
    $newManifest=$acceptance | ConvertFrom-Json
    $newManifest.gates[0]=($oldFirst | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
    $newPath=Join-Path $phased.Root 'acceptance.json'
    $newHash=Save-Json $newPath $newManifest
    Assert-Rejected { & $runner -ManifestPath $newPath -ApprovedManifestSha256 $newHash -Mode ContinueManifest -PriorManifestPath $oldPath -ApprovedPriorManifestSha256 $oldHash } 'completely passed'
    for ($i=0;$i -lt 4;$i++) { Invoke-FixtureMode $phased RunNext }
    $oldState=Read-WorkflowState (Read-ReleaseWorkflow $oldPath $oldHash)
    Assert-Fixture (-not $oldState.complete -and $oldState.phase -ceq 'built' -and $oldState.nextAction -match 'ContinueManifest') 'Prepare/build completion is not release completion.'
    $unchangedAttempts=Get-WorkflowValueHash $oldState.gates
    $newManifest.gates[0].description='changed prior gate'
    $changedContinuationHash=Save-Json $newPath $newManifest
    Assert-Rejected { & $runner -ManifestPath $newPath -ApprovedManifestSha256 $changedContinuationHash -Mode ContinueManifest -PriorManifestPath $oldPath -ApprovedPriorManifestSha256 $oldHash } 'change, narrow'
    $newManifest.gates[0]=$phased.Manifest.gates[0]
    $newHash=Save-Json $newPath $newManifest
    & $runner -ManifestPath $newPath -ApprovedManifestSha256 $newHash -Mode ContinueManifest -PriorManifestPath $oldPath -ApprovedPriorManifestSha256 $oldHash | Out-Null
    $continued=Read-WorkflowState (Read-ReleaseWorkflow $newPath $newHash)
    Assert-Fixture ($continued.manifestHistory.Count -eq 2 -and $continued.gates.Count -eq 13 -and $continued.currentStage -ceq 'artifact-privacy') 'Continuation binds late artifact evidence and retains both reviewed manifest identities.'
    Assert-Fixture ((Get-WorkflowValueHash @($continued.gates | Select-Object -First 4)) -ceq $unchangedAttempts) 'Continuation preserves the exact earlier attempts.'
    $null=Write-Fixture $oldPath '{}'
    Assert-Rejected { & $runner -ManifestPath $newPath -ApprovedManifestSha256 $newHash -Mode Status } 'changed'

    $logs=New-WorkflowFixture
    $logGate=$logs.Manifest.gates[2]
    $logGate.validation.type='flutter-tests'; $logGate.validation.checks=@()
    $machinePath=Join-Path $logs.Root 'machine.jsonl'
    $logGate.validation.reportPath=$machinePath
    $events=@($logGate.resolvedTests | ForEach-Object { [pscustomobject]@{type='suite'; suite=[pscustomobject]@{path=$_.path}} })
    $events+=@([pscustomobject]@{type='testDone'; result='success'; skipped=$false}, [pscustomobject]@{type='done'; success=$true})
    $null=Write-Fixture $machinePath (($events | ForEach-Object { $_ | ConvertTo-Json -Depth 5 -Compress }) -join "`n")
    Assert-Fixture (@(Test-WorkflowEvidence $logGate).Count -eq 1) 'Native Flutter machine output accepts complete exact suite discovery.'
    $events[2].skipped=$true
    $null=Write-Fixture $machinePath (($events | ForEach-Object { $_ | ConvertTo-Json -Depth 5 -Compress }) -join "`n")
    Assert-Rejected { Test-WorkflowEvidence $logGate } 'skipped'
    $events=@($events[0],$events[-1])
    $null=Write-Fixture $machinePath (($events | ForEach-Object { $_ | ConvertTo-Json -Depth 5 -Compress }) -join "`n")
    Assert-Rejected { Test-WorkflowEvidence $logGate } 'discovery'

    $lifecycle=New-WorkflowFixture
    $lifecycleWorkflow=Read-ReleaseWorkflow $lifecycle.Path $lifecycle.Hash
    $candidateRecord=$lifecycle.Manifest.gates[3].inputs[0]
    $candidate=Read-WorkflowJson $candidateRecord.path $candidateRecord.sha256
    $full=@($candidate.artifacts | Where-Object role -CEQ 'full-package')[0]
    $parityRecords=@()
    foreach ($phase in @('upgrade','fresh','repair')) {
        $parity=[pscustomobject]@{schemaVersion=1; purpose='installed-payload-parity'; success=$true; packageSha256=$full.sha256;
            expectedInventorySha256=('C'*64); installedInventorySha256=('C'*64); missing=@(); unexpected=@(); changed=@()}
        $parityPath=Join-Path $lifecycle.Root ($phase+'-parity.json')
        $parityHash=Save-Json $parityPath $parity
        $parityRecords+=@([pscustomobject]@{phase=$phase; reportPath=[IO.Path]::GetFileName($parityPath); reportSha256=$parityHash;
            packageSha256=$full.sha256; expectedInventorySha256=('C'*64); installedInventorySha256=('C'*64); success=$true})
    }
    $summary=[pscustomobject]@{schemaVersion=1; success=$true; mode='LocalFeed'; releasePlanSha256=$lifecycle.Manifest.releasePlan.sha256;
        candidateManifestSha256=$candidateRecord.sha256; harnessSha256=$lifecycle.Manifest.context.files[0].sha256;
        restoration=[pscustomobject]@{errors=@()}; installedPayloadParity=$parityRecords}
    $summaryPath=Join-Path $lifecycle.Root 'lifecycle-summary.json'
    $summaryHash=Save-Json $summaryPath $summary
    $lifecycleGate=$lifecycle.Manifest.gates[7]
    $lifecycleGate.validation.type='lifecycle'; $lifecycleGate.validation.reportPath=$summaryPath; $lifecycleGate.inputs=@($candidateRecord)
    $bound=@(Test-WorkflowEvidence $lifecycleGate $lifecycleWorkflow)
    Assert-Fixture ($bound.Count -eq 5) 'Lifecycle validates and retains all three exhaustive parity reports without rescanning installation.'
    $summary.installedPayloadParity=@($parityRecords[0]); $null=Save-Json $summaryPath $summary
    Assert-Rejected { Test-WorkflowEvidence $lifecycleGate $lifecycleWorkflow } 'coverage'
    $summary.installedPayloadParity=$parityRecords; $summary.restoration.errors=@('synthetic failure'); $null=Save-Json $summaryPath $summary
    Assert-Rejected { Test-WorkflowEvidence $lifecycleGate $lifecycleWorkflow } 'restoration'
    $summary.restoration.errors=@(); $summaryHash=Save-Json $summaryPath $summary
    $lifecycleGate.validation.reportPath='lifecycle-summary.json'
    $lifecycleWorkflow.Manifest.gates[7]=$lifecycleGate
    $projection=$lifecycle.Manifest.gates[6]
    $projection.command=$null; $projection.validation=[pscustomobject]@{type='lifecycle-installed'; reportPath=$null; checks=@(); package=(File-Record (Join-Path $lifecycle.Root $full.path))}
    $projectionState=[pscustomobject]@{gates=@([pscustomobject]@{id=$lifecycleGate.id; kind='local-lifecycle'; status='passed'; attempts=@([pscustomobject]@{evidence=@(File-Record $summaryPath)})})}
    Assert-Fixture (@(Test-WorkflowEvidence $projection $lifecycleWorkflow $projectionState).Count -eq 5) 'Separate installed gate projects exact already-accepted lifecycle evidence, not another command.'
    $null=Write-Fixture (Join-Path $lifecycle.Root $parityRecords[0].reportPath) '{}'
    Assert-Rejected { Test-WorkflowEvidence $projection $lifecycleWorkflow $projectionState } 'hash mismatch'

    $junctionFixture=New-WorkflowFixture
    $junction=Join-Path $junctionFixture.Root 'junction'
    $null=New-Item -ItemType Junction -Path $junction -Target $junctionFixture.Source
    try {
        $junctionFixture.Manifest.stateRoot=Join-Path $junction 'escape'
        Save-Manifest $junctionFixture
        Assert-Rejected { Read-ReleaseWorkflow $junctionFixture.Path $junctionFixture.Hash } 'reparse'
    } finally { [IO.Directory]::Delete($junction) }

    $installed=New-WorkflowFixture
    $installedGate=$installed.Manifest.gates[6]
    $installedGate.validation.reportPath=Write-Fixture (Join-Path $installed.Root 'bad-installed.json') '{"schemaVersion":1,"purpose":"installed-payload-parity","success":true,"packageSha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","expectedInventorySha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","installedInventorySha256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","missing":[],"unexpected":[],"changed":[]}'
    $installedGate.validation.checks=@()
    Assert-Rejected { Test-WorkflowEvidence $installedGate } 'identity'
    Assert-Fixture ((ConvertTo-WorkflowArgument 'a b') -ceq '"a b"') 'Spaces are native argv, not shell source.'
    Assert-Fixture ((ConvertTo-WorkflowArgument 'x"y') -ceq '"x\"y"') 'Embedded quote uses Windows native argv quoting.'
    Write-Output "Release workflow fixtures passed: $script:assertions assertions; PowerShell $($PSVersionTable.PSVersion)."
} finally {
    $resolved=[IO.Path]::GetFullPath($fixtureRoot)
    $tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -cnotmatch '^bsl-workflow-fixture-[a-f0-9]{32}$') { throw 'Refusing cleanup outside the newly created synthetic fixture root.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
