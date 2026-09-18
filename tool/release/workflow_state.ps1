# Thin, reviewed release sequencing. This is an acceptance index, not a build cache.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'source_promotion.ps1')
. (Join-Path $PSScriptRoot 'release_plan.ps1')

$script:ReleaseWorkflowKinds = @('source-parity', 'source-privacy', 'application-tests', 'build',
    'artifact-privacy', 'package-integrity', 'installed-parity', 'local-lifecycle',
    'ui-parity', 'themed-installer', 'upload', 'publication', 'public-verification')

function Get-WorkflowHash([string]$Path) {
    return (Get-FileHash -LiteralPath (Resolve-ReleasePromotionPath $Path File) -Algorithm SHA256).Hash
}
function Get-WorkflowValueHash($Value) {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 50 -Compress))
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($hash.ComputeHash($bytes)).Replace('-', '') }
    finally { $hash.Dispose() }
}
function Assert-WorkflowObject($Value, [string[]]$Fields) {
    Assert-ReleasePromotionProperties $Value $Fields
}
function Assert-WorkflowString($Value) {
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) { throw 'Workflow requires a nonempty string.' }
}
function Assert-WorkflowArray($Value) {
    if ($Value -isnot [array]) { throw 'Workflow collections must be explicit JSON arrays.' }
}
function Read-WorkflowJson([string]$Path, [string]$ExpectedSha256) {
    $file = Resolve-ReleasePromotionPath $Path File
    $expected = Assert-ReleasePromotionHash $ExpectedSha256
    $bytes = [IO.File]::ReadAllBytes($file)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $actual = [BitConverter]::ToString($hash.ComputeHash($bytes)).Replace('-', '') }
    finally { $hash.Dispose() }
    if ($actual -cne $expected) { throw 'Reviewed workflow/evidence hash mismatch.' }
    return ([Text.UTF8Encoding]::new($false, $true).GetString($bytes) | ConvertFrom-Json)
}
function Assert-WorkflowFile($Record) {
    Assert-WorkflowObject $Record @('path', 'sha256')
    Assert-WorkflowString $Record.path
    $null = Assert-ReleasePromotionHash $Record.sha256
    if ((Get-WorkflowHash $Record.path) -cne $Record.sha256.ToUpperInvariant()) { throw 'Workflow input/evidence changed.' }
}
function Test-WorkflowOverlap([string]$Left, [string]$Right) {
    return $Left.Equals($Right, [StringComparison]::OrdinalIgnoreCase) -or
        $Left.StartsWith($Right + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $Right.StartsWith($Left + '\', [StringComparison]::OrdinalIgnoreCase)
}
function Resolve-WorkflowFutureFile([string]$Path) {
    # A report may not exist until its command completes. Its parent must already
    # be an ordinary directory; never normalize traversal/ADS/Windows aliases.
    if ($Path -notmatch '^[A-Za-z]:[\\/]') { throw 'Workflow report paths must be absolute local paths.' }
    $null = ConvertTo-ReleasePromotionRelativePath $Path.Substring(3)
    $full = [IO.Path]::GetFullPath($Path)
    $null = Resolve-ReleasePromotionPath ([IO.Path]::GetDirectoryName($full)) Directory
    if (Test-Path -LiteralPath $full) { $null = Resolve-ReleasePromotionPath $full File }
    return $full
}
function Get-WorkflowField($Document, [string]$Field) {
    if ($Field -cnotmatch '^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z][A-Za-z0-9]*)*$') { throw 'Unsupported evidence field path.' }
    $current = $Document
    foreach ($part in $Field.Split('.')) {
        if ($null -eq $current -or $current -isnot [pscustomobject]) { throw 'Evidence field is missing.' }
        $property = @($current.PSObject.Properties | Where-Object Name -CEQ $part)
        if ($property.Count -ne 1) { throw 'Evidence field is missing.' }
        $current = $property[0].Value
    }
    return $current
}

function Read-ReleaseWorkflow([string]$ManifestPath, [string]$ApprovedManifestSha256) {
    $manifest = Read-WorkflowJson $ManifestPath $ApprovedManifestSha256
    Assert-WorkflowObject $manifest @('schemaVersion', 'phase', 'approvalReference', 'stateRoot', 'releasePlan',
        'promotionEvidence', 'source', 'context', 'gates')
    if (-not (Test-ReleasePlanJsonInteger $manifest.schemaVersion) -or $manifest.schemaVersion -ne 1) { throw 'Unsupported workflow schema.' }
    if ($manifest.phase -cnotin @('prepare-build', 'acceptance')) { throw 'Workflow phase must be prepare-build or acceptance.' }
    Assert-WorkflowString $manifest.approvalReference
    Assert-WorkflowFile $manifest.releasePlan
    Assert-WorkflowFile $manifest.promotionEvidence
    $plan = Read-ReleasePlan $manifest.releasePlan.path $manifest.releasePlan.sha256.ToUpperInvariant()
    $promotion = Read-WorkflowJson $manifest.promotionEvidence.path $manifest.promotionEvidence.sha256
    if ($promotion.schemaVersion -ne 1 -or $promotion.status -cne 'Passed' -or
        $promotion.sourceAndOverlayStable -isnot [bool] -or -not $promotion.sourceAndOverlayStable -or
        $promotion.previousOutputsModified -isnot [bool] -or $promotion.previousOutputsModified) {
        throw 'Workflow needs passed, stable Beta promotion evidence.'
    }
    Assert-WorkflowObject $manifest.source @('root', 'generatedDirectories', 'fingerprintSha256')
    $sourceRoot = Resolve-ReleasePromotionPath $manifest.source.root Directory
    Assert-WorkflowArray $manifest.source.generatedDirectories
    $prunes = @($manifest.source.generatedDirectories | ForEach-Object {
        Assert-WorkflowObject $_ @('path', 'reason')
        Assert-WorkflowString $_.reason
        $null = ConvertTo-ReleasePromotionRelativePath $_.path
        $_
    })
    $tree = Get-ReleasePromotionTree $sourceRoot $prunes
    if ($tree.fingerprintSha256 -cne $manifest.source.fingerprintSha256 -or
        $tree.fingerprintSha256 -cne $promotion.candidate.fingerprintSha256) {
        throw 'Current complete source does not match the approved promotion/workflow fingerprint.'
    }
    $stateRoot = if (Test-Path -LiteralPath $manifest.stateRoot) {
        Resolve-ReleasePromotionPath $manifest.stateRoot Directory
    } else { Resolve-ReleasePromotionPath $manifest.stateRoot NewDirectory }
    if (Test-WorkflowOverlap $stateRoot $sourceRoot) { throw 'Workflow output cannot overlap source.' }
    foreach ($protected in @($manifest.releasePlan.path, $manifest.promotionEvidence.path, $ManifestPath)) {
        if (Test-WorkflowOverlap $stateRoot ([IO.Path]::GetFullPath($protected))) { throw 'Workflow output overlaps reviewed inputs.' }
    }
    Assert-WorkflowObject $manifest.context @('powershellVersion', 'osVersion', 'files', 'environment')
    if ($manifest.context.powershellVersion -cne $PSVersionTable.PSVersion.ToString() -or
        $manifest.context.osVersion -cne [Environment]::OSVersion.VersionString) { throw 'Workflow runtime context changed.' }
    Assert-WorkflowArray $manifest.context.files
    Assert-WorkflowArray $manifest.context.environment
    $contextPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $manifest.context.files) {
        Assert-WorkflowFile $file
        $path = [IO.Path]::GetFullPath($file.path)
        if (-not $contextPaths.Add($path)) { throw 'Duplicate workflow context path.' }
        if (Test-WorkflowOverlap $stateRoot $path) { throw 'Workflow output overlaps context inputs.' }
    }
    foreach ($required in @('workflow_state.ps1', 'run_release_workflow.ps1', 'source_promotion.ps1',
        'source_inventory.ps1', 'release_plan.ps1', 'verified_input_cache.ps1')) {
        if (-not $contextPaths.Contains((Join-Path $PSScriptRoot $required))) { throw 'Workflow context must pin every engine/helper file.' }
    }
    if (-not $contextPaths.Contains((Get-Process -Id $PID).Path)) { throw 'Workflow context must pin the executing PowerShell runtime.' }
    $null = $contextPaths.Add([IO.Path]::GetFullPath($manifest.releasePlan.path))
    $null = $contextPaths.Add([IO.Path]::GetFullPath($manifest.promotionEvidence.path))
    $environmentNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $manifest.context.environment) {
        Assert-WorkflowObject $entry @('name', 'value')
        if ($entry.name -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or -not $environmentNames.Add($entry.name) -or
            $entry.name -match '(?i)token|password|secret|credential|cookie') { throw 'Unsafe or duplicate workflow environment binding.' }
        if ($entry.value -isnot [string] -and $null -ne $entry.value) { throw 'Environment binding must be string or null.' }
        if ([Environment]::GetEnvironmentVariable($entry.name, 'Process') -cne $entry.value) { throw 'Workflow environment changed.' }
    }
    foreach ($name in @('PATH', 'PATHEXT', 'FLUTTER_ROOT', 'PUB_CACHE')) {
        if (-not $environmentNames.Contains($name)) { throw 'Workflow must bind PATH/PATHEXT/FLUTTER_ROOT/PUB_CACHE, including absent values.' }
    }
    Assert-WorkflowArray $manifest.gates
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $kinds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($gate in $manifest.gates) {
        Assert-WorkflowObject $gate @('id', 'kind', 'description', 'command', 'testDiscovery', 'resolvedTests', 'inputs', 'validation')
        if ($gate.id -cnotmatch '^[a-z][a-z0-9-]{0,63}$' -or -not $ids.Add($gate.id)) { throw 'Invalid/duplicate workflow gate ID.' }
        if ($gate.kind -cnotin $script:ReleaseWorkflowKinds) { throw 'Unknown required gate kind.' }
        $null = $kinds.Add($gate.kind)
        Assert-WorkflowString $gate.description
        Assert-WorkflowArray $gate.inputs
        foreach ($file in $gate.inputs) { Assert-WorkflowFile $file }
        Assert-WorkflowArray $gate.resolvedTests
        if ($gate.kind -ceq 'application-tests' -and $gate.resolvedTests.Count -eq 0) { throw 'Application gate needs its complete resolved test list.' }
        if ($gate.resolvedTests.Count -gt 0) {
            Assert-WorkflowObject $gate.testDiscovery @('root', 'suffix')
            $testRoot = Resolve-ReleasePromotionPath $gate.testDiscovery.root Directory
            if (-not $testRoot.StartsWith($sourceRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Tests must be inside promoted source.' }
            if ($gate.testDiscovery.suffix -cnotmatch '^_[a-z]+\.(dart|ps1|py)$') { throw 'Unsupported exact test-discovery suffix.' }
            $discovered = @((Get-ReleasePromotionTree $testRoot).entries | Where-Object { $_.path.EndsWith($gate.testDiscovery.suffix, [StringComparison]::Ordinal) } | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $testRoot $_.path)) })
            $declared = @($gate.resolvedTests | ForEach-Object { Assert-WorkflowFile $_; [IO.Path]::GetFullPath($_.path) })
            if ($declared.Count -ne $discovered.Count -or
                @($declared | Select-Object -Unique).Count -ne $declared.Count -or
                @(Compare-Object ($declared | Sort-Object) ($discovered | Sort-Object) -CaseSensitive).Count -ne 0) {
                throw 'Resolved tests do not equal current discovery; narrower coverage cannot satisfy this gate.'
            }
        } elseif ($null -ne $gate.testDiscovery) { throw 'Unexpected test-discovery declaration.' }
        Assert-WorkflowObject $gate.validation @('type', 'reportPath', 'checks', 'package')
        if ($gate.validation.type -cnotin @('review', 'promotion', 'source-privacy', 'flutter-tests', 'lifecycle', 'lifecycle-installed', 'json', 'installed-payload', 'candidate-build')) { throw 'Unknown workflow evidence validator.' }
        Assert-WorkflowArray $gate.validation.checks
        if ($gate.validation.type -ceq 'review') {
            if ($null -ne $gate.command -or $null -ne $gate.validation.reportPath -or $gate.validation.checks.Count -ne 0 -or $null -ne $gate.validation.package) { throw 'Manual gate cannot invoke a command or invent automated validation.' }
        } elseif ($gate.validation.type -ceq 'promotion') {
            if ($gate.kind -cne 'source-parity' -or $null -ne $gate.command -or $null -ne $gate.validation.reportPath -or
                $gate.validation.checks.Count -ne 0 -or $null -ne $gate.validation.package) { throw 'Promotion gate uses only the already reviewed stable promotion evidence.' }
        } elseif ($gate.validation.type -ceq 'lifecycle-installed') {
            if ($gate.kind -cne 'installed-parity' -or $null -ne $gate.command -or $null -ne $gate.validation.reportPath -or
                $gate.validation.checks.Count -ne 0) { throw 'Lifecycle parity projection cannot invoke another scan.' }
            Assert-WorkflowFile $gate.validation.package
        } else {
            if ($null -eq $gate.command) { throw 'Automatic gate requires its reviewed command.' }
            $reportName = ConvertTo-ReleasePromotionRelativePath $gate.validation.reportPath
            if ($gate.validation.type -ceq 'json' -and $gate.validation.checks.Count -eq 0) { throw 'JSON evidence needs explicit reviewed checks.' }
            if ($gate.validation.type -cin @('source-privacy', 'flutter-tests') -and $gate.validation.reportPath -cne 'stdout.log') { throw 'Native log validators use the exact captured stdout.log.' }
            if ($gate.validation.type -ceq 'source-privacy' -and $gate.kind -cne 'source-privacy') { throw 'Source privacy validator cannot satisfy another gate.' }
            if ($gate.validation.type -ceq 'flutter-tests' -and $gate.kind -cne 'application-tests') { throw 'Flutter test validator cannot satisfy another gate.' }
            if ($gate.validation.type -ceq 'lifecycle' -and $gate.kind -cnotin @('local-lifecycle', 'public-verification')) { throw 'Lifecycle validator cannot satisfy installed parity or publication.' }
            if ($gate.validation.type -ceq 'candidate-build' -and $gate.kind -cne 'build') { throw 'Candidate build cannot satisfy a different acceptance gate.' }
            if ($gate.validation.type -ceq 'installed-payload' -and $gate.kind -cne 'installed-parity') { throw 'Installed payload comparison cannot satisfy a different gate.' }
            foreach ($check in $gate.validation.checks) {
                Assert-WorkflowObject $check @('field', 'equals')
                if ($check.field -cnotmatch '^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z][A-Za-z0-9]*)*$' -or
                    ($null -ne $check.equals -and $check.equals -isnot [string] -and $check.equals -isnot [bool] -and -not (Test-ReleasePlanJsonInteger $check.equals))) { throw 'Evidence checks require an exact scalar field/value.' }
            }
            if ($gate.validation.type -ceq 'installed-payload') { Assert-WorkflowFile $gate.validation.package }
            elseif ($null -ne $gate.validation.package) { throw 'Only installed-payload validation accepts package identity.' }
        }
        if ($gate.kind -ceq 'installed-parity' -and $gate.validation.type -cnotin @('installed-payload', 'lifecycle-installed')) { throw 'Installed parity requires dedicated complete inventory validation.' }
        if ($gate.kind -ceq 'build' -and $gate.validation.type -cne 'candidate-build') { throw 'Build requires dedicated sealed candidate validation.' }
        if ($gate.kind -ceq 'publication' -and $gate.validation.type -cne 'review') { throw 'Publication is an externally reviewed operation, never automatic.' }
        if ($null -ne $gate.command) { Assert-WorkflowCommand $gate $sourceRoot $contextPaths }
    }
    $requiredKinds = if ($manifest.phase -ceq 'prepare-build') { @('source-parity', 'source-privacy', 'application-tests', 'build') } else { $script:ReleaseWorkflowKinds }
    foreach ($kind in $requiredKinds) {
        if (-not $kinds.Contains($kind)) { throw "Required distinct gate is missing: $kind" }
    }
    if ($manifest.phase -ceq 'prepare-build' -and @($manifest.gates | Where-Object { $_.kind -cnotin $requiredKinds }).Count -gt 0) { throw 'Prepare/build manifest cannot preclaim later acceptance.' }
    if ($manifest.phase -ceq 'acceptance') {
    $publicationIndex = @($manifest.gates.kind).IndexOf('publication')
    $uploadIndex = @($manifest.gates.kind).IndexOf('upload')
    if (@($manifest.gates.kind).IndexOf('upload') -gt $publicationIndex -or
        @($manifest.gates.kind).IndexOf('public-verification') -lt $publicationIndex) { throw 'Upload, publication and public verification must be ordered distinctly.' }
    for ($i = $uploadIndex; $i -lt $manifest.gates.Count; $i++) {
        if ($manifest.gates[$i].kind -cnotin @('upload', 'publication', 'public-verification')) { throw 'Every local acceptance gate must precede upload/publication.' }
        if ($i -gt $uploadIndex -and
            @('upload','publication','public-verification').IndexOf($manifest.gates[$i].kind) -lt
            @('upload','publication','public-verification').IndexOf($manifest.gates[$i-1].kind)) { throw 'Publication phases cannot move backward.' }
    }
    }
    return [pscustomobject]@{ Manifest = $manifest; Path = [IO.Path]::GetFullPath($ManifestPath);
        Sha256 = $ApprovedManifestSha256.ToUpperInvariant(); SourceRoot = $sourceRoot; StateRoot = $stateRoot;
        Plan = $plan; ContextSha256 = Get-WorkflowValueHash $manifest.context }
}

function Assert-WorkflowCommand($Gate, [string]$SourceRoot, $ContextPaths) {
    $command = $Gate.command
    Assert-WorkflowObject $command @('executable', 'arguments', 'workingDirectory')
    Assert-WorkflowFile $command.executable
    $executable = Resolve-ReleasePromotionPath $command.executable.path File
    if (-not $ContextPaths.Contains($executable) -or [IO.Path]::GetExtension($executable) -ine '.exe' -or
        [IO.Path]::GetFileName($executable) -match '^(?i:cmd|bash|sh|wscript|cscript|gh)\.exe$') { throw 'Command must use a pinned native tool, never an implicit shell/publisher.' }
    $null = Resolve-ReleasePromotionPath $command.workingDirectory Directory
    Assert-WorkflowArray $command.arguments
    foreach ($argument in $command.arguments) {
        if ($argument -isnot [string] -or $argument -match '[\x00\r\n]') { throw 'Command arguments must be literal strings without control characters.' }
        if (($argument.Replace('{reportPath}', '').Replace('{attemptRoot}', '')) -match '[{}]') { throw 'Unknown command placeholder.' }
        if ($argument -match '^[A-Za-z]:[\\/]' -and (Test-Path -LiteralPath $argument -PathType Leaf) -and
            -not $argument.StartsWith($SourceRoot + '\', [StringComparison]::OrdinalIgnoreCase) -and
            -not $ContextPaths.Contains([IO.Path]::GetFullPath($argument)) -and
            @($Gate.inputs | Where-Object { [IO.Path]::GetFullPath($_.path).Equals([IO.Path]::GetFullPath($argument), [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
            throw 'Existing command file argument must be source-owned or hash-bound as context/input.'
        }
    }
    if ($Gate.validation.type -cnotin @('source-privacy', 'flutter-tests') -and
        @($command.arguments | Where-Object { $_.Contains('{reportPath}') -or $_.Contains('{attemptRoot}') }).Count -eq 0) { throw 'Command must write its declared fresh report path.' }
    if ([IO.Path]::GetFileName($executable) -match '^(?i:powershell|pwsh)\.exe$') {
        $fileIndex = [Array]::IndexOf([string[]]$command.arguments, '-File')
        if ($fileIndex -lt 1 -or $fileIndex + 1 -ge $command.arguments.Count) { throw 'PowerShell commands require explicit -File, not command strings.' }
        foreach ($prefix in @($command.arguments | Select-Object -First $fileIndex)) {
            if ($prefix -cnotin @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass')) { throw 'Unsupported PowerShell invocation prefix.' }
        }
        $scriptPath = Resolve-ReleasePromotionPath $command.arguments[$fileIndex + 1] File
        if ([IO.Path]::GetExtension($scriptPath) -ine '.ps1' -or -not $ContextPaths.Contains($scriptPath)) { throw 'PowerShell helper must be hash-pinned in workflow context.' }
        if ($Gate.validation.type -ceq 'source-privacy') {
            $projectIndex = [Array]::IndexOf([string[]]$command.arguments, '-ProjectRoot')
            if ([IO.Path]::GetFileName($scriptPath) -cne 'verify_production_source.ps1' -or $projectIndex -lt 0 -or
                $projectIndex + 1 -ge $command.arguments.Count -or $command.arguments[$projectIndex + 1] -cne $SourceRoot) { throw 'Source privacy must invoke the pinned maintained verifier on this exact promoted root.' }
        }
    } elseif (@($command.arguments | Where-Object { $_ -match '^(?i:-c|-command|-encodedcommand|/c|/k)$' }).Count -gt 0) {
        throw 'Inline shell/interpreter command strings are not supported.'
    }
    if ($Gate.resolvedTests.Count -gt 0 -and @($command.arguments | Where-Object { $_ -match '^--(plain-name|name)(=|$)' }).Count -gt 0) { throw 'A name-filtered subset cannot satisfy the resolved full test gate.' }
    if ($Gate.validation.type -ceq 'flutter-tests' -and
        (@($command.arguments | Where-Object { $_ -ceq '--machine' }).Count -ne 1 -or
        @($command.arguments | Where-Object { $_ -ceq '--no-pub' }).Count -ne 1)) { throw 'Flutter gates require machine results and prepared dependencies (--no-pub).' }
}

function Write-WorkflowAtomicJson([string]$Path, $Value) {
    $null = Resolve-WorkflowFutureFile $Path
    $temporary = Join-Path ([IO.Path]::GetDirectoryName($Path)) ('.status-' + [Guid]::NewGuid().ToString('N') + '.partial')
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 60))
    $stream = [IO.FileStream]::new($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    if (Test-Path -LiteralPath $Path) {
        $backup = Join-Path ([IO.Path]::GetDirectoryName($Path)) ('status-history-' + [Guid]::NewGuid().ToString('N') + '.json')
        [IO.File]::Replace($temporary, $Path, $backup)
    } else { [IO.File]::Move($temporary, $Path) }
}
function Open-WorkflowLock($Workflow) {
    # Source-derived shared lock also excludes a competing manifest with a different
    # status root. No PID-based killing or stale-lock-file deletion is performed.
    $key = Get-WorkflowValueHash $Workflow.SourceRoot.ToUpperInvariant()
    $path = Join-Path ([IO.Path]::GetDirectoryName($Workflow.SourceRoot)) ('.release-workflow-' + $key + '.lock')
    $null = Resolve-WorkflowFutureFile $path
    try { return [IO.FileStream]::new($path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
    catch { throw 'Another workflow owns this source; no command was started.' }
}
function Read-WorkflowState($Workflow) {
    $path = Join-Path $Workflow.StateRoot 'status.json'
    $state = Read-WorkflowJson $path (Get-WorkflowHash $path)
    Assert-WorkflowObject $state @('schemaVersion', 'workflowSha256', 'releasePlanSha256', 'promotionEvidenceSha256',
        'contextSha256', 'manifestHistory', 'createdAtUtc', 'updatedAtUtc', 'phase', 'currentStage', 'blocker', 'nextAction', 'complete', 'gates')
    if ($state.schemaVersion -ne 1 -or $state.workflowSha256 -cne $Workflow.Sha256 -or
        $state.releasePlanSha256 -cne $Workflow.Manifest.releasePlan.sha256 -or
        $state.promotionEvidenceSha256 -cne $Workflow.Manifest.promotionEvidence.sha256 -or
        $state.contextSha256 -cne $Workflow.ContextSha256 -or $state.gates.Count -ne $Workflow.Manifest.gates.Count) { throw 'Workflow status has a stale or different identity.' }
    Assert-WorkflowArray $state.manifestHistory
    if ($state.manifestHistory.Count -eq 0 -or $state.manifestHistory[-1].sha256 -cne $Workflow.Sha256) { throw 'Workflow manifest history is incomplete.' }
    foreach ($manifestRecord in $state.manifestHistory) { Assert-WorkflowFile $manifestRecord }
    $unmetGateSeen = $false
    for ($i = 0; $i -lt $state.gates.Count; $i++) {
        $record = $state.gates[$i]
        $gate = $Workflow.Manifest.gates[$i]
        if ($record.id -cne $Workflow.Manifest.gates[$i].id -or $record.kind -cne $Workflow.Manifest.gates[$i].kind -or
            $record.status -cnotin @('pending', 'running', 'failed', 'passed')) { throw 'Workflow gate state is malformed.' }
        Assert-WorkflowArray $record.attempts
        if ($record.status -ceq 'passed') {
            if ($unmetGateSeen) { throw 'Passed gate follows an unmet gate; workflow state cannot skip a required gate.' }
            if ($record.attempts.Count -eq 0 -or $record.attempts[-1].outcome -cne 'passed') { throw 'Passed gate lacks its successful evidence.' }
            $attempt = $record.attempts[-1]
            Assert-WorkflowArray $attempt.evidence
            if ($attempt.evidence.Count -eq 0) { throw 'Passed gate requires nonempty successful evidence.' }
            $expectedOrigin = if ($gate.validation.type -ceq 'review') { 'external-reviewed' }
                elseif ($gate.validation.type -cin @('promotion', 'lifecycle-installed')) { 'bound-evidence-validation' }
                else { 'reviewed-command' }
            if ($attempt.origin -cne $expectedOrigin) { throw 'Passed gate origin disagrees with its reviewed validator.' }
            if ($expectedOrigin -ceq 'reviewed-command') {
                if (-not (Test-ReleasePlanJsonInteger $attempt.exitCode) -or $attempt.exitCode -ne 0) { throw 'Passed command gate requires an integer zero exit code.' }
            } elseif ($null -ne $attempt.exitCode) { throw 'Passed non-command gate cannot claim a command exit code.' }
            foreach ($file in $attempt.evidence) { Assert-WorkflowFile $file }
        } else { $unmetGateSeen = $true }
    }
    $expectedComplete = @($state.gates | Where-Object status -CNE 'passed').Count -eq 0 -and $Workflow.Manifest.phase -ceq 'acceptance'
    if ($state.complete -isnot [bool] -or $state.complete -ne $expectedComplete) { throw 'Workflow completion flag disagrees with its required gates.' }
    return $state
}
function Update-WorkflowStatus($Workflow, $State) {
    $first = @($State.gates | Where-Object status -CNE 'passed' | Select-Object -First 1)
    $State.complete = $first.Count -eq 0 -and $Workflow.Manifest.phase -ceq 'acceptance'
    $State.currentStage = if ($first.Count) { $first[0].id } else { $null }
    $State.blocker = if ($first.Count) { $first[0].status } else { $null }
    $State.nextAction = if (-not $first.Count) {
        if ($Workflow.Manifest.phase -ceq 'prepare-build') { 'Review sealed artifact hashes and ContinueManifest with the acceptance phase; release is not yet verified.' }
        else { 'All reviewed required gates passed; retain final evidence.' }
    } elseif ($first[0].status -ceq 'running') {
        'Prior operation is incomplete/interrupted. Confirm its process and outputs are safe before explicit recovery; never infer success.'
    } else {
        $gate = @($Workflow.Manifest.gates | Where-Object id -CEQ $first[0].id)[0]
        if ($gate.validation.type -ceq 'review') { 'Review and register external evidence for ' + $gate.id } else { 'Run the complete reviewed gate ' + $gate.id }
    }
    $State.phase = 'prepared'
    $passedPrefix = @()
    foreach ($entry in $State.gates) { if ($entry.status -cne 'passed') { break }; $passedPrefix += $entry.kind }
    if ($passedPrefix -ccontains 'build') { $State.phase = 'built' }
    $localCount = @($State.gates | Where-Object { $_.kind -cnotin @('upload', 'publication', 'public-verification') }).Count
    if ($Workflow.Manifest.phase -ceq 'acceptance' -and $passedPrefix.Count -ge $localCount) { $State.phase = 'locally-verified' }
    foreach ($transition in @(@('upload', 'uploaded'), @('publication', 'published'), @('public-verification', 'publicly-verified'))) {
        $total = @($State.gates | Where-Object kind -CEQ $transition[0]).Count
        if ($total -gt 0 -and @($passedPrefix | Where-Object { $_ -ceq $transition[0] }).Count -eq $total) { $State.phase = $transition[1] }
    }
    $State.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    Write-WorkflowAtomicJson (Join-Path $Workflow.StateRoot 'status.json') $State
}
function Test-WorkflowInstalledReport($Document, [string]$PackageSha256) {
    if (-not (Test-ReleasePlanJsonInteger $Document.schemaVersion) -or $Document.schemaVersion -ne 1 -or $Document.purpose -cne 'installed-payload-parity' -or
        $Document.success -isnot [bool] -or -not $Document.success -or
        $Document.packageSha256 -ine $PackageSha256 -or
        $Document.expectedInventorySha256 -cnotmatch '^[A-Fa-f0-9]{64}$' -or
        $Document.installedInventorySha256 -ine $Document.expectedInventorySha256) { throw 'Installed parity identity or complete inventory comparison failed.' }
    foreach ($name in @('missing', 'unexpected', 'changed')) {
        Assert-WorkflowArray $Document.$name
        if ($Document.$name.Count -ne 0) { throw 'Installed payload has missing, unexpected or changed files.' }
    }
}
function Get-WorkflowLifecycleParityEvidence($Document, [string]$SummaryPath, [string]$PackageSha256) {
    Assert-WorkflowArray $Document.installedPayloadParity
    $expectedPhases = if ($Document.mode -ceq 'LocalFeed') { @('upgrade','fresh','repair') } elseif ($Document.mode -ceq 'PublicRoute') { @('upgrade') } else { throw 'Unknown lifecycle mode.' }
    if ($Document.installedPayloadParity.Count -ne $expectedPhases.Count) { throw 'Lifecycle installed parity coverage is incomplete.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($record in $Document.installedPayloadParity) {
        if ($record.phase -cnotin $expectedPhases -or -not $seen.Add($record.phase) -or $record.success -isnot [bool] -or -not $record.success -or
            $record.packageSha256 -ine $PackageSha256 -or $record.expectedInventorySha256 -ine $record.installedInventorySha256) { throw 'Lifecycle installed parity identity/phase is invalid.' }
        $relative = ConvertTo-ReleasePromotionRelativePath $record.reportPath
        $path = Join-Path ([IO.Path]::GetDirectoryName($SummaryPath)) $relative
        $proof = Read-WorkflowJson $path $record.reportSha256
        Test-WorkflowInstalledReport $proof $PackageSha256
        if ($proof.expectedInventorySha256 -ine $record.expectedInventorySha256 -or $proof.installedInventorySha256 -ine $record.installedInventorySha256) { throw 'Lifecycle parity report inventory binding changed.' }
        [pscustomobject]@{path=$path; sha256=$record.reportSha256.ToUpperInvariant()}
    }
}
function Test-WorkflowEvidence($Gate, $Workflow, $State) {
    if ($Gate.validation.type -ceq 'promotion') { return @($Workflow.Manifest.releasePlan, $Workflow.Manifest.promotionEvidence) }
    if ($Gate.validation.type -ceq 'lifecycle-installed') {
        $local = @($State.gates | Where-Object { $_.kind -ceq 'local-lifecycle' -and $_.status -ceq 'passed' })
        if ($local.Count -eq 0) { throw 'Installed parity needs an earlier passed local lifecycle.' }
        $accepted = @()
        foreach ($record in $local) {
            $manifestGate = @($Workflow.Manifest.gates | Where-Object id -CEQ $record.id)[0]
            if ($manifestGate.validation.type -cne 'lifecycle') { throw 'Installed parity projection requires the dedicated lifecycle validator.' }
            $reports = @($record.attempts[-1].evidence | Where-Object { $_.path.EndsWith($manifestGate.validation.reportPath.Replace('/', '\'), [StringComparison]::OrdinalIgnoreCase) })
            if ($reports.Count -ne 1) { throw 'Accepted lifecycle summary binding is missing/ambiguous.' }
            $summary = Read-WorkflowJson $reports[0].path $reports[0].sha256
            $accepted += $reports[0]
            $accepted += @(Get-WorkflowLifecycleParityEvidence $summary $reports[0].path $Gate.validation.package.sha256)
        }
        Assert-WorkflowFile $Gate.validation.package
        return @($accepted) + @($Gate.validation.package)
    }
    $path = Resolve-ReleasePromotionPath $Gate.validation.reportPath File
    $hash = Get-WorkflowHash $path
    if ($Gate.validation.type -ceq 'source-privacy') {
        $log = [IO.File]::ReadAllText($path)
        if ($log -notmatch '(?m)^Production source verification passed for exact-Beta Stable [^\r\n]+\.$') { throw 'Maintained source verifier did not emit its successful completion marker.' }
        return [pscustomobject]@{path=$path; sha256=$hash}
    }
    if ($Gate.validation.type -ceq 'flutter-tests') {
        $messages = @([IO.File]::ReadAllLines($path) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
        $done = @($messages | Where-Object type -CEQ 'done')
        if ($done.Count -ne 1 -or $done[0].success -isnot [bool] -or -not $done[0].success -or $messages[-1].type -cne 'done') { throw 'Flutter machine report is incomplete or failed.' }
        $suites = @($messages | Where-Object type -CEQ 'suite' | ForEach-Object { [IO.Path]::GetFullPath($_.suite.path) } | Sort-Object -Unique)
        $expected = @($Gate.resolvedTests | ForEach-Object { [IO.Path]::GetFullPath($_.path) } | Sort-Object -Unique)
        if ($suites.Count -ne $expected.Count -or @(Compare-Object $expected $suites -CaseSensitive).Count -ne 0) { throw 'Actual Flutter suite discovery differs from the resolved reviewed list.' }
        if (@($messages | Where-Object { $_.type -ceq 'testDone' -and ($_.result -cne 'success' -or $_.skipped -eq $true) }).Count -gt 0) { throw 'Failed or skipped Flutter tests cannot silently satisfy the full gate.' }
        return [pscustomobject]@{path=$path; sha256=$hash}
    }
    $document = Read-WorkflowJson $path $hash
    foreach ($check in $Gate.validation.checks) {
        $actual = Get-WorkflowField $document $check.field
        if ((Get-WorkflowValueHash $actual) -cne (Get-WorkflowValueHash $check.equals)) { throw 'Command evidence did not satisfy the reviewed assertion.' }
    }
    $evidence = @([pscustomobject]@{path = $path; sha256 = $hash})
    if ($Gate.validation.type -ceq 'lifecycle') {
        $mode = if ($Gate.kind -ceq 'local-lifecycle') { 'LocalFeed' } else { 'PublicRoute' }
        if (-not (Test-ReleasePlanJsonInteger $document.schemaVersion) -or $document.schemaVersion -ne 1 -or
            $document.success -isnot [bool] -or -not $document.success -or $document.mode -cne $mode -or
            $document.releasePlanSha256 -cne $Workflow.Plan.Sha256 -or
            @($Gate.inputs | Where-Object sha256 -CEQ $document.candidateManifestSha256).Count -ne 1 -or
            @($Workflow.Manifest.context.files | Where-Object sha256 -CEQ $document.harnessSha256).Count -ne 1) { throw 'Lifecycle report has wrong mode, candidate, harness or plan identity.' }
        Assert-WorkflowArray $document.restoration.errors
        if ($document.restoration.errors.Count -ne 0) { throw 'Lifecycle restoration errors block acceptance.' }
        $candidateRecord = @($Gate.inputs | Where-Object sha256 -CEQ $document.candidateManifestSha256)[0]
        $candidate = Read-WorkflowJson $candidateRecord.path $candidateRecord.sha256
        $packages = @($candidate.artifacts | Where-Object role -CEQ 'full-package')
        if ($packages.Count -ne 1) { throw 'Lifecycle lacks a unique sealed full-package binding.' }
        $evidence += @(Get-WorkflowLifecycleParityEvidence $document $path $packages[0].sha256)
        $evidence += @($Gate.inputs)
    }
    if ($Gate.validation.type -ceq 'candidate-build') {
        $plan = $Workflow.Plan
        if (-not (Test-ReleasePlanJsonInteger $document.schemaVersion) -or $document.schemaVersion -ne 1 -or
            $document.purpose -cne 'candidate-build' -or $document.success -isnot [bool] -or -not $document.success -or
            $document.sourceCommit -cne $plan.ExpectedCommit -or $document.releasePlanSha256 -cne $plan.Sha256 -or
            $document.version -cne $plan.Version -or $document.buildNumber -ne $plan.BuildNumber) { throw 'Candidate build report has mismatched release identity.' }
        Assert-WorkflowFile $document.candidateManifest
        $candidate = Read-WorkflowJson $document.candidateManifest.path $document.candidateManifest.sha256
        if (-not (Test-ReleasePlanJsonInteger $candidate.schemaVersion) -or $candidate.schemaVersion -ne 2 -or
            $candidate.publicCandidate -isnot [bool] -or -not $candidate.publicCandidate -or
            $candidate.version -cne $plan.Version -or $candidate.buildNumber -ne $plan.BuildNumber -or
            $candidate.sourceCommit -cne $plan.ExpectedCommit -or $candidate.sourceTag -cne $plan.ExpectedTag -or
            $candidate.packageId -cne $plan.PackageId -or $candidate.channel -cne $plan.Channel -or
            $candidate.updateSource -cne $plan.Repository -or $candidate.releasePlan.sha256 -cne $plan.Sha256) { throw 'Sealed candidate manifest does not match the approved release.' }
        Assert-WorkflowArray $candidate.artifacts
        $roles = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $candidateRoot = [IO.Path]::GetDirectoryName($document.candidateManifest.path)
        $evidence += $document.candidateManifest
        foreach ($artifact in $candidate.artifacts) {
            $relative = ConvertTo-ReleasePromotionRelativePath $artifact.path
            if (-not $roles.Add($artifact.role) -or -not $paths.Add($relative)) { throw 'Candidate artifact roles/paths collide.' }
            $artifactPath = Resolve-ReleasePromotionPath (Join-Path $candidateRoot $relative) File
            if (-not (Test-ReleasePlanJsonInteger $artifact.bytes) -or $artifact.bytes -le 0 -or
                (Get-Item -LiteralPath $artifactPath).Length -ne $artifact.bytes) { throw 'Candidate artifact length mismatch.' }
            $record = [pscustomobject]@{path = $artifactPath; sha256 = $artifact.sha256}
            Assert-WorkflowFile $record
            $evidence += $record
        }
        foreach ($role in @('velopack-setup', 'full-package', 'delta-package', 'update-feed')) { if (-not $roles.Contains($role)) { throw 'Candidate manifest lacks a required artifact role.' } }
    }
    if ($Gate.validation.type -ceq 'installed-payload') {
        Test-WorkflowInstalledReport $document $Gate.validation.package.sha256
        Assert-WorkflowFile $Gate.validation.package
        $evidence += $Gate.validation.package
    }
    return $evidence
}
function ConvertTo-WorkflowArgument([string]$Value) {
    # Windows CommandLineToArgvW / CRT quoting. No cmd.exe, expression evaluation,
    # interpolated shell source, or PowerShell command-string interpretation.
    return '"' + ([regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
}
function Invoke-WorkflowProcess($Gate, [string]$StdoutPath, [string]$StderrPath, [string]$AttemptRoot, [scriptblock]$OnStarted) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Gate.command.executable.path
    $info.WorkingDirectory = $Gate.command.workingDirectory
    $arguments = @($Gate.command.arguments | ForEach-Object { $_.Replace('{reportPath}', $Gate.validation.reportPath).Replace('{attemptRoot}', $AttemptRoot) }) + @($Gate.resolvedTests | ForEach-Object path)
    $info.Arguments = (@($arguments | ForEach-Object { ConvertTo-WorkflowArgument $_ }) -join ' ')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'Reviewed command could not start.' }
        if ($null -ne $OnStarted) { & $OnStarted ([int]$process.Id) ($process.StartTime.ToUniversalTime().ToString('o')) }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [IO.File]::WriteAllText($StdoutPath, $stdout.GetAwaiter().GetResult(), [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($StderrPath, $stderr.GetAwaiter().GetResult(), [Text.UTF8Encoding]::new($false))
        return $process.ExitCode
    } finally { $process.Dispose() }
}
