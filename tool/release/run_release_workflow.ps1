[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$ApprovedManifestSha256,
    [ValidateSet('Preflight', 'Initialize', 'ContinueManifest', 'Status', 'RunNext', 'RunStep', 'RegisterEvidence', 'RecoverInterrupted')]
    [string]$Mode = 'Preflight',
    [string]$StepId,
    [string]$EvidenceRegistrationPath,
    [string]$ApprovedEvidenceRegistrationSha256,
    [string]$PriorManifestPath,
    [string]$ApprovedPriorManifestSha256,
    [switch]$ConfirmReviewedEvidence,
    [switch]$ConfirmPriorProcessStopped
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'workflow_state.ps1')

if ($Mode -ceq 'Preflight') {
    $workflow = Read-ReleaseWorkflow $ManifestPath $ApprovedManifestSha256
    [pscustomobject]@{ status = 'preflight-passed'; workflowSha256 = $workflow.Sha256; commandsExecuted = 0 } | ConvertTo-Json
    return
}
$lockManifest = Read-WorkflowJson $ManifestPath $ApprovedManifestSha256
$lockSource = Resolve-ReleasePromotionPath $lockManifest.source.root Directory
$ownership = Open-WorkflowLock ([pscustomobject]@{SourceRoot=$lockSource})
try {
    # Only the small approved manifest/path were read before ownership. Full
    # source/context validation happens once here, then again after a command.
    $workflow = Read-ReleaseWorkflow $ManifestPath $ApprovedManifestSha256
    if ($Mode -ceq 'Initialize') {
        if (Test-Path -LiteralPath $workflow.StateRoot) { throw 'Workflow state output already exists; it will not be overwritten.' }
        $null = [IO.Directory]::CreateDirectory($workflow.StateRoot)
        $state = [pscustomobject][ordered]@{
            schemaVersion = 1; workflowSha256 = $workflow.Sha256
            releasePlanSha256 = $workflow.Manifest.releasePlan.sha256
            promotionEvidenceSha256 = $workflow.Manifest.promotionEvidence.sha256
            contextSha256 = $workflow.ContextSha256
            manifestHistory = @([pscustomobject]@{path=$workflow.Path; sha256=$workflow.Sha256})
            createdAtUtc = [DateTime]::UtcNow.ToString('o'); updatedAtUtc = $null
            phase = 'prepared'; currentStage = $null; blocker = $null; nextAction = $null; complete = $false
            gates = @($workflow.Manifest.gates | ForEach-Object {
                [pscustomobject]@{id = $_.id; kind = $_.kind; status = 'pending'; attempts = @()}
            })
        }
        Update-WorkflowStatus $workflow $state
        $state | ConvertTo-Json -Depth 60
        return
    }
    if ($Mode -ceq 'ContinueManifest') {
        $prior = Read-ReleaseWorkflow $PriorManifestPath $ApprovedPriorManifestSha256
        $state = Read-WorkflowState $prior
        if ($prior.Manifest.phase -cne 'prepare-build' -or $workflow.Manifest.phase -cne 'acceptance' -or
            $prior.StateRoot -cne $workflow.StateRoot -or $prior.SourceRoot -cne $workflow.SourceRoot -or
            $prior.Manifest.releasePlan.sha256 -cne $workflow.Manifest.releasePlan.sha256 -or
            $prior.Manifest.promotionEvidence.sha256 -cne $workflow.Manifest.promotionEvidence.sha256 -or
            (Get-WorkflowValueHash $prior.Manifest.source) -cne (Get-WorkflowValueHash $workflow.Manifest.source) -or
            $prior.ContextSha256 -cne $workflow.ContextSha256 -or
            @($state.gates | Where-Object status -CNE 'passed').Count -ne 0 -or
            $workflow.Manifest.gates.Count -le $prior.Manifest.gates.Count) { throw 'Continuation requires the unchanged, completely passed prepare/build phase.' }
        for ($i=0; $i -lt $prior.Manifest.gates.Count; $i++) {
            if ((Get-WorkflowValueHash $prior.Manifest.gates[$i]) -cne (Get-WorkflowValueHash $workflow.Manifest.gates[$i])) { throw 'Continuation cannot change, narrow, reorder or erase an earlier gate.' }
        }
        $state.workflowSha256 = $workflow.Sha256
        $state.manifestHistory = @($state.manifestHistory) + @([pscustomobject]@{path=$workflow.Path; sha256=$workflow.Sha256})
        foreach ($gate in @($workflow.Manifest.gates | Select-Object -Skip $prior.Manifest.gates.Count)) {
            $state.gates = @($state.gates) + @([pscustomobject]@{id=$gate.id; kind=$gate.kind; status='pending'; attempts=@()})
        }
        Update-WorkflowStatus $workflow $state
        $state | ConvertTo-Json -Depth 60
        return
    }
    $state = Read-WorkflowState $workflow
    if ($Mode -ceq 'Status') { $state | ConvertTo-Json -Depth 60; return }
    $pending = @($state.gates | Where-Object status -CNE 'passed' | Select-Object -First 1)
    if ($pending.Count -eq 0) { throw 'All required gates are already accepted; no command was repeated.' }
    $record = $pending[0]
    if ($Mode -cne 'RunNext' -and $StepId -cne $record.id) { throw 'Only the first unmet gate may advance; a narrower/later pass cannot erase a failed gate.' }
    $gate = @($workflow.Manifest.gates | Where-Object id -CEQ $record.id)[0]
    if ($record.status -ceq 'running') {
        if ($Mode -cne 'RecoverInterrupted' -or -not $ConfirmPriorProcessStopped.IsPresent) { throw 'Interrupted/running gate blocks further work; explicit safe recovery is required.' }
        if ($null -ne $record.attempts[-1].processId) {
            $live = Get-Process -Id $record.attempts[-1].processId -ErrorAction SilentlyContinue
            if ($null -ne $live -and $live.StartTime.ToUniversalTime().Ticks -eq ([datetime]$record.attempts[-1].processStartedAtUtc).ToUniversalTime().Ticks) {
                throw 'The recorded command process is still running; recovery cannot override live ownership.'
            }
        }
        $record.status = 'failed'
        $record.attempts[-1].outcome = 'interrupted'
        $record.attempts[-1].finishedAtUtc = [DateTime]::UtcNow.ToString('o')
        Update-WorkflowStatus $workflow $state
        $state | ConvertTo-Json -Depth 60
        return
    }
    if ($Mode -ceq 'RecoverInterrupted') { throw 'No interrupted gate requires recovery.' }
    $attempt = [pscustomobject][ordered]@{ id = [Guid]::NewGuid().ToString('N');
        startedAtUtc = [DateTime]::UtcNow.ToString('o'); finishedAtUtc = $null;
        outcome = 'running'; origin = $null; processId = $null; processStartedAtUtc = $null;
        exitCode = $null; evidence = @(); failure = $null }
    if ($Mode -ceq 'RegisterEvidence') {
        if ($gate.validation.type -cne 'review' -or -not $ConfirmReviewedEvidence.IsPresent) { throw 'Only explicitly reviewed external/manual gates accept evidence registration.' }
        $registration = Read-WorkflowJson $EvidenceRegistrationPath $ApprovedEvidenceRegistrationSha256
        Assert-WorkflowObject $registration @('schemaVersion', 'workflowSha256', 'gateId', 'releasePlanSha256',
            'promotionEvidenceSha256', 'contextSha256', 'outcome', 'reviewReference', 'evidence')
        if (-not (Test-ReleasePlanJsonInteger $registration.schemaVersion) -or $registration.schemaVersion -ne 1 -or
            $registration.workflowSha256 -cne $workflow.Sha256 -or $registration.gateId -cne $gate.id -or
            $registration.releasePlanSha256 -cne $workflow.Manifest.releasePlan.sha256 -or
            $registration.promotionEvidenceSha256 -cne $workflow.Manifest.promotionEvidence.sha256 -or
            $registration.contextSha256 -cne $workflow.ContextSha256 -or $registration.outcome -cnotin @('passed', 'failed')) { throw 'External evidence registration has mismatched gate/input identity.' }
        Assert-WorkflowString $registration.reviewReference
        Assert-WorkflowArray $registration.evidence
        if ($registration.evidence.Count -eq 0) { throw 'A review alone without actual evidence cannot accept a gate.' }
        foreach ($file in $registration.evidence) { Assert-WorkflowFile $file }
        $registrationRoot = Join-Path $workflow.StateRoot $attempt.id
        $null = Resolve-ReleasePromotionPath $registrationRoot NewDirectory
        $null = [IO.Directory]::CreateDirectory($registrationRoot)
        $frozenRegistration = Join-Path $registrationRoot 'approved-registration.json'
        [IO.File]::Copy((Resolve-ReleasePromotionPath $EvidenceRegistrationPath File), $frozenRegistration, $false)
        $null = Read-WorkflowJson $frozenRegistration $ApprovedEvidenceRegistrationSha256
        $attempt.origin = 'external-reviewed'
        $attempt.outcome = $registration.outcome
        $attempt.evidence = @($registration.evidence) + @([pscustomobject]@{path = $frozenRegistration; sha256 = $ApprovedEvidenceRegistrationSha256.ToUpperInvariant()})
        $attempt.finishedAtUtc = [DateTime]::UtcNow.ToString('o')
        $record.attempts = @($record.attempts) + @($attempt)
        $record.status = $registration.outcome
        $null = Read-ReleaseWorkflow $ManifestPath $ApprovedManifestSha256
        Update-WorkflowStatus $workflow $state
        if ($record.status -ceq 'failed') { throw 'Reviewed external gate failed; acceptance remains blocked.' }
    } else {
        if ($gate.validation.type -ceq 'review') { throw 'Next gate requires reviewed external evidence; no publication/manual action was invoked.' }
        $attempt.origin = 'reviewed-command'
        $record.attempts = @($record.attempts) + @($attempt)
        $record.status = 'running'
        Update-WorkflowStatus $workflow $state
        try {
            $attemptRoot = Join-Path $workflow.StateRoot $attempt.id
            $null = Resolve-ReleasePromotionPath $attemptRoot NewDirectory
            $null = [IO.Directory]::CreateDirectory($attemptRoot)
            $runtimeGate = ($gate | ConvertTo-Json -Depth 50 -Compress) | ConvertFrom-Json
            if ($null -ne $gate.validation.reportPath) { $runtimeGate.validation.reportPath = Join-Path $attemptRoot $gate.validation.reportPath }
            $stdoutPath = Join-Path $attemptRoot 'stdout.log'
            $stderrPath = Join-Path $attemptRoot 'stderr.log'
            if ($gate.validation.type -cin @('promotion', 'lifecycle-installed')) {
                $attempt.origin = 'bound-evidence-validation'
            } else {
                $started = { param($commandId, $commandStart)
                    $attempt.processId = $commandId; $attempt.processStartedAtUtc = $commandStart
                    Update-WorkflowStatus $workflow $state
                }
                $attempt.exitCode = Invoke-WorkflowProcess $runtimeGate $stdoutPath $stderrPath $attemptRoot $started
                $attempt.evidence = @($stdoutPath, $stderrPath | ForEach-Object { [pscustomobject]@{path = $_; sha256 = Get-WorkflowHash $_} })
                if ($attempt.exitCode -ne 0) { throw 'Reviewed command returned nonzero; full gate failed.' }
            }
            $null = Read-ReleaseWorkflow $ManifestPath $ApprovedManifestSha256
            $attempt.evidence = @($attempt.evidence) + @(Test-WorkflowEvidence $runtimeGate $workflow $state)
            $attempt.outcome = 'passed'; $record.status = 'passed'
        } catch {
            $attempt.outcome = 'failed'; $record.status = 'failed'; $attempt.failure = 'command-or-evidence-rejected'
            throw
        } finally {
            $attempt.finishedAtUtc = [DateTime]::UtcNow.ToString('o')
            Update-WorkflowStatus $workflow $state
        }
    }
    $state | ConvertTo-Json -Depth 60
} finally { $ownership.Dispose() }
