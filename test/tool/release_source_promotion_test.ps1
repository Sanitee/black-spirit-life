[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $repositoryRoot 'tool/release/source_promotion.ps1')
$script:assertions = 0
function Assert-Fixture([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Promotion assertion failed: $Message" }
    $script:assertions++
}
function Assert-Rejected([scriptblock]$Action, [string]$Pattern) {
    $message = $null
    try { & $Action | Out-Null }
    catch { $message = $_.Exception.Message }
    Assert-Fixture ($null -ne $message -and $message -match $Pattern) "Expected '$Pattern'; got '$message'."
}
function Write-FixtureFile([string]$Root, [string]$Relative, [string]$Text) {
    $path = Join-Path $Root $Relative
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    [IO.File]::WriteAllText($path, $Text, [Text.UTF8Encoding]::new($false))
    return $path
}
function Get-FixtureHash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Save-FixturePlan($Fixture) {
    [IO.File]::WriteAllText($Fixture.PlanPath, ($Fixture.Plan | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    $Fixture.Inputs.ExpectedPlanSha256 = Get-FixtureHash $Fixture.PlanPath
}
function New-PromotionFixture {
    $root = Join-Path $fixtureRoot ([Guid]::NewGuid().ToString('N'))
    $source = Join-Path $root 'source'
    $overlay = Join-Path $root 'overlay'
    $null = [IO.Directory]::CreateDirectory($source)
    $null = [IO.Directory]::CreateDirectory($overlay)
    $null = Write-FixtureFile $source 'lib/main.dart' 'beta identity'
    $null = Write-FixtureFile $source 'lib/tracked.dart' 'dirty!'
    $null = Write-FixtureFile $source 'lib/untracked helper.dart' 'untracked production helper'
    $null = Write-FixtureFile $source 'assets/cache/reference.json' '{"reference":true}'
    $null = Write-FixtureFile $source 'assets/data/reference.bin' 'reference bytes'
    $null = Write-FixtureFile $source 'defaults.json' '{"mastery":0}'
    $null = Write-FixtureFile $source 'private/internal-note.txt' 'synthetic internal release note'
    $null = Write-FixtureFile $source 'same-name/build' 'ordinary file, not a generated directory'
    $null = Write-FixtureFile $source ('assets/' + [char]0x00e4 + '-' + [char]0x65e5 + '.txt') 'unicode reference'
    $hidden = Write-FixtureFile $source '.hidden-source.txt' 'hidden production content'
    [IO.File]::SetAttributes($hidden, [IO.FileAttributes]::Hidden)
    foreach ($relative in @('build/deep/not-source.bin', 'nested/generated/not-source.bin', 'windows/helper/bin/not-source.bin', 'tools/GeneratedOverlayBackup/not-source.bin')) {
        $null = Write-FixtureFile $source $relative 'transient output'
    }
    $null = Write-FixtureFile $overlay 'main.dart' 'stable identity'
    $null = Write-FixtureFile $overlay 'release.txt' 'reviewed release-only addition'
    $plan = [pscustomobject][ordered]@{
        schemaVersion = 1
        approvalReference = 'Synthetic reviewed fixture; not release authorization'
        pruneDirectories = @(@('.git', 'build', 'nested/generated', 'windows/helper/bin', 'tools/GeneratedOverlayBackup', 'same-name/build') | ForEach-Object {
            [pscustomobject]@{ path = $_; reason = 'Reviewed exact transient directory fixture' }
        })
        omitFiles = @([pscustomobject]@{ path = 'private/internal-note.txt'; expectedSha256 = Get-FixtureHash (Join-Path $source 'private/internal-note.txt'); reason = 'Explicit synthetic source-only omission' })
        replaceFiles = @([pscustomobject]@{ path = 'lib/main.dart'; expectedSha256 = Get-FixtureHash (Join-Path $source 'lib/main.dart'); overlayPath = 'main.dart'; overlaySha256 = Get-FixtureHash (Join-Path $overlay 'main.dart'); reason = 'Synthetic release identity only' })
        addFiles = @([pscustomobject]@{ path = 'docs/release.txt'; overlayPath = 'release.txt'; overlaySha256 = Get-FixtureHash (Join-Path $overlay 'release.txt'); reason = 'Synthetic reviewed release-only addition' })
    }
    $planPath = Join-Path $root 'plan.json'
    $fixture = [pscustomobject]@{
        Root = $root; Source = $source; Overlay = $overlay; Output = Join-Path $root 'new-candidate'
        Plan = $plan; PlanPath = $planPath
        Inputs = @{ SourceRoot = $source; OverlayRoot = $overlay; PlanPath = $planPath; ExpectedPlanSha256 = '' }
        Fingerprint = ''
    }
    Save-FixturePlan $fixture
    $arguments = $fixture.Inputs
    $fixture.Fingerprint = (Get-ReleasePromotionInventory @arguments).source.fingerprintSha256
    return $fixture
}
function Invoke-FixturePromotion($Fixture) {
    $arguments = $Fixture.Inputs
    Invoke-ReleaseSourcePromotion @arguments -ExpectedSourceFingerprint $Fixture.Fingerprint -OutputRoot $Fixture.Output
}
function Get-FixtureStages($Fixture) {
    return @(Get-ChildItem -LiteralPath $Fixture.Root -Directory -Force | Where-Object Name -like '.promotion-staging-*')
}
function Invoke-FixtureCli([hashtable]$Inputs, [string]$Mode, [string[]]$Extra = @()) {
    $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
        (Join-Path $repositoryRoot 'tool/release/promote_source.ps1'), '-Mode', $Mode)
    foreach ($key in $Inputs.Keys) { $arguments += @(('-' + $key), [string]$Inputs[$key]) }
    $arguments += $Extra
    $shell = (Get-Process -Id $PID).Path
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $text = @(& $shell @arguments 2>&1) -join "`n"
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $savedPreference }
    return [pscustomobject]@{ ExitCode = $code; Text = $text }
}

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\', '/'))
$fixtureRoot = Join-Path $tempParent ('bsl-source-promotion-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($fixtureRoot)
try {
    $positive = New-PromotionFixture
    # Actual Git index state proves discovery is the working tree, not Git HEAD.
    & git -C $positive.Source init --quiet
    Assert-Fixture ($LASTEXITCODE -eq 0) 'Synthetic Git initialization failed.'
    $trackedPath = Join-Path $positive.Source 'lib/tracked.dart'
    [IO.File]::WriteAllText($trackedPath, 'before', [Text.UTF8Encoding]::new($false))
    & git -C $positive.Source -c core.autocrlf=false add -- lib/tracked.dart
    Assert-Fixture ($LASTEXITCODE -eq 0) 'Synthetic Git staging failed.'
    [IO.File]::WriteAllText($trackedPath, 'dirty!', [Text.UTF8Encoding]::new($false))
    Assert-Fixture (@(& git -C $positive.Source diff --name-only).Count -eq 1) 'Fixture must contain a dirty tracked file.'
    Assert-Fixture (@(& git -C $positive.Source ls-files --others --exclude-standard).Count -gt 0) 'Fixture must contain untracked production files.'
    $arguments = $positive.Inputs
    $review = Get-ReleasePromotionInventory @arguments
    Assert-Fixture ($review.source.fingerprintSha256 -ceq $positive.Fingerprint) 'Git metadata must not change explicitly pruned source identity.'
    Assert-Fixture ($review.source.files -eq 10) 'Complete retained source set must include hidden, dirty, untracked and same-named ordinary files.'
    Assert-Fixture ($review.source.discovery.PrunedDirectoryCount -eq 5) 'Exactly the reviewed existing directories must be pruned.'
    $enumerator = (Get-Item Function:\Get-ReleaseInventoryDirectoryEntries).ScriptBlock
    try {
        function Get-ReleaseInventoryDirectoryEntries {
            param([IO.DirectoryInfo]$Directory)
            if ($Directory.FullName -match '[\\/](?:build|generated|bin|GeneratedOverlayBackup|\.git)(?:[\\/]|$)') {
                throw 'Fixture spy: pruned child must never be descended into.'
            }
            & $enumerator $Directory
        }
        $null = Get-ReleasePromotionInventory @arguments
        Assert-Fixture $true 'Unreadable/pruned child traversal spy stayed untouched.'
    }
    finally { Set-Item Function:\Get-ReleaseInventoryDirectoryEntries -Value $enumerator }
    $oldCulture = [Threading.Thread]::CurrentThread.CurrentCulture
    try {
        [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('tr-TR')
        $turkish = Get-ReleasePromotionInventory @arguments
        Assert-Fixture ($turkish.source.fingerprintSha256 -ceq $review.source.fingerprintSha256) 'Source fingerprint must be culture-independent.'
    }
    finally { [Threading.Thread]::CurrentThread.CurrentCulture = $oldCulture }
    $originalTimestamp = [IO.File]::GetLastWriteTimeUtc($trackedPath)
    [IO.File]::SetLastWriteTimeUtc($trackedPath, $originalTimestamp.AddDays(-1))
    Assert-Fixture ((Get-ReleasePromotionInventory @arguments).source.fingerprintSha256 -ceq $positive.Fingerprint) 'Timestamp-only changes must not change source identity.'
    $report = Invoke-FixturePromotion $positive
    Assert-Fixture ($report.status -ceq 'Passed' -and $report.sourceAndOverlayStable -and -not $report.isReleaseVerification) 'Promotion receipt must describe only source promotion.'
    Assert-Fixture ($report.changes.Count -eq 3 -and $report.candidate.files -eq 10) 'Complete before/after changes and candidate inventory must be reported.'
    Assert-Fixture (Test-Path -LiteralPath (Join-Path $positive.Output 'promotion-report.json')) 'Completed report must be exposed with the new candidate.'
    foreach ($relative in @('lib/tracked.dart', 'lib/untracked helper.dart', 'assets/cache/reference.json', 'assets/data/reference.bin', 'defaults.json', '.hidden-source.txt', 'same-name/build')) {
        Assert-Fixture ((Get-FixtureHash (Join-Path $positive.Source $relative)) -ceq (Get-FixtureHash (Join-Path $positive.Output ('source/' + $relative)))) "Exact retained bytes missing: $relative."
    }
    Assert-Fixture ((Get-FixtureHash (Join-Path $positive.Output 'source/lib/main.dart')) -ceq $positive.Plan.replaceFiles[0].overlaySha256) 'Replacement output must match approved overlay bytes.'
    Assert-Fixture (-not (Test-Path -LiteralPath (Join-Path $positive.Output 'source/private/internal-note.txt'))) 'Explicit omission must not be copied.'
    Assert-Fixture (-not (Test-Path -LiteralPath (Join-Path $positive.Output 'source/build'))) 'Transient output must not be copied.'
    Assert-Rejected { Invoke-FixturePromotion $positive } 'already exists'
    Assert-Fixture ((Get-FixtureHash (Join-Path $positive.Output 'source/lib/main.dart')) -ceq $positive.Plan.replaceFiles[0].overlaySha256) 'Existing candidate must remain unchanged.'

    foreach ($change in @('add', 'remove', 'same-size')) {
        $fixture = New-PromotionFixture
        $path = Join-Path $fixture.Source 'lib/tracked.dart'
        if ($change -eq 'add') { $null = Write-FixtureFile $fixture.Source 'lib/new.dart' 'new source' }
        elseif ($change -eq 'remove') { [IO.File]::Delete($path) }
        else {
            $stamp = [IO.File]::GetLastWriteTimeUtc($path)
            [IO.File]::WriteAllText($path, 'DIRTY!', [Text.UTF8Encoding]::new($false))
            [IO.File]::SetLastWriteTimeUtc($path, $stamp)
        }
        Assert-Rejected { Invoke-FixturePromotion $fixture } 'Approved source fingerprint'
        Assert-Fixture (-not (Test-Path -LiteralPath $fixture.Output)) 'Changed source must not expose a candidate.'
    }
    foreach ($kind in @('source-hash', 'overlay-hash', 'plan-hash', 'schema', 'boolean-schema', 'unknown-field', 'duplicate', 'traversal', 'absolute', 'wildcard', 'reserved', 'prune-overlap', 'source-add-collision', 'file-directory-collision')) {
        $fixture = New-PromotionFixture
        $pattern = 'hash guard'
        switch ($kind) {
            'source-hash' { $fixture.Plan.replaceFiles[0].expectedSha256 = ('0' * 64) }
            'overlay-hash' { $fixture.Plan.replaceFiles[0].overlaySha256 = ('0' * 64) }
            'plan-hash' { $fixture.Inputs.ExpectedPlanSha256 = ('0' * 64); $pattern = 'plan SHA-256' }
            'schema' { $fixture.Plan.schemaVersion = 2; $pattern = 'schemaVersion' }
            'boolean-schema' { $fixture.Plan.schemaVersion = $true; $pattern = 'schemaVersion' }
            'unknown-field' { $fixture.Plan | Add-Member Unexpected 'not supported'; $pattern = 'unsupported properties' }
            'duplicate' { $fixture.Plan.addFiles[0].path = 'LIB/MAIN.DART'; $pattern = 'duplicate/case-colliding' }
            'traversal' { $fixture.Plan.addFiles[0].overlayPath = '../escape.txt'; $pattern = 'traversal' }
            'absolute' { $fixture.Plan.addFiles[0].path = 'C:\escape.txt'; $pattern = 'safe relative' }
            'wildcard' { $fixture.Plan.pruneDirectories[0].path = 'lib/*'; $pattern = 'safe relative' }
            'reserved' { $fixture.Plan.addFiles[0].path = 'docs/NUL.txt'; $pattern = 'reserved' }
            'prune-overlap' { $fixture.Plan.addFiles[0].path = 'build/injected.txt'; $pattern = 'overlap a pruned' }
            'source-add-collision' { $fixture.Plan.addFiles[0].path = 'defaults.json'; $pattern = 'already exists in source' }
            'file-directory-collision' { $fixture.Plan.addFiles[0].path = 'defaults.json/child.txt'; $pattern = 'file/directory' }
        }
        if ($kind -ne 'plan-hash') { Save-FixturePlan $fixture }
        Assert-Rejected { Invoke-FixturePromotion $fixture } $pattern
        Assert-Fixture (-not (Test-Path -LiteralPath $fixture.Output)) 'Invalid plan must not expose output.'
    }
    foreach ($kind in @('source-output', 'overlay-output', 'source-overlay')) {
        $fixture = New-PromotionFixture
        if ($kind -eq 'source-output') { $fixture.Output = Join-Path $fixture.Source 'new-candidate' }
        elseif ($kind -eq 'overlay-output') { $fixture.Output = Join-Path $fixture.Overlay 'new-candidate' }
        else { $fixture.Inputs.OverlayRoot = $fixture.Source }
        Assert-Rejected { Invoke-FixturePromotion $fixture } 'must not overlap'
    }
    foreach ($alias in @('new-candidate:stream', 'new-candidate.', 'new-candidate ', 'escape/../new-candidate')) {
        $fixture = New-PromotionFixture
        $fixture.Output = Join-Path $fixture.Root $alias
        Assert-Rejected { Invoke-FixturePromotion $fixture } 'safe relative|traversal|aliases'
    }
    $fixture = New-PromotionFixture
    [IO.File]::WriteAllBytes($fixture.PlanPath, [byte[]]@(0x7b, 0x22, 0xff, 0x22, 0x7d))
    $fixture.Inputs.ExpectedPlanSha256 = Get-FixtureHash $fixture.PlanPath
    Assert-Rejected { Invoke-FixturePromotion $fixture } 'translate bytes|Unable to translate'
    $fixture = New-PromotionFixture
    $outside = Join-Path $fixture.Root 'ordinary-target'
    $null = [IO.Directory]::CreateDirectory($outside)
    $junction = Join-Path $fixture.Source 'escape'
    $null = New-Item -ItemType Junction -Path $junction -Target $outside
    try { Assert-Rejected { Invoke-FixturePromotion $fixture } 'reparse points' }
    finally { [IO.Directory]::Delete($junction, $false) }
    $junction = Join-Path $fixture.Root 'linked-parent'
    $null = New-Item -ItemType Junction -Path $junction -Target $outside
    try {
        $fixture.Output = Join-Path $junction 'new-candidate'
        Assert-Rejected { Invoke-FixturePromotion $fixture } 'reparse points'
    }
    finally { [IO.Directory]::Delete($junction, $false) }

    $originalCopy = (Get-Item Function:\Copy-ReleasePromotionFile).ScriptBlock
    foreach ($mutation in @('source-addition', 'source-change', 'source-removal', 'overlay-change', 'overlay-addition', 'plan-change', 'candidate-injection')) {
        $fixture = New-PromotionFixture
        $script:injected = $false
        try {
            function Copy-ReleasePromotionFile {
                param([string]$From, [string]$To)
                & $originalCopy $From $To
                if (-not $script:injected) {
                    $script:injected = $true
                    switch ($mutation) {
                        'source-addition' { $null = Write-FixtureFile $fixture.Source 'new-after-copy.dart' 'unexpected source' }
                        'source-change' { $null = Write-FixtureFile $fixture.Source 'defaults.json' 'changed defaults' }
                        'source-removal' { [IO.File]::Delete((Join-Path $fixture.Source 'defaults.json')) }
                        'overlay-change' { $null = Write-FixtureFile $fixture.Overlay 'main.dart' 'changed overlay' }
                        'overlay-addition' { $null = Write-FixtureFile $fixture.Overlay 'new-after-copy.txt' 'unexpected overlay' }
                        'plan-change' { [IO.File]::AppendAllText($fixture.PlanPath, ' ') }
                        'candidate-injection' { $null = Write-FixtureFile ([IO.Path]::GetDirectoryName($To)) 'injected.bin' 'unexpected candidate' }
                    }
                }
            }
            Assert-Rejected { Invoke-FixturePromotion $fixture } 'Promotion failed; staging retained'
            Assert-Fixture (-not (Test-Path -LiteralPath $fixture.Output)) 'Interrupted/mutated staging must not expose a completed candidate.'
            $stages = @(Get-FixtureStages $fixture)
            Assert-Fixture ($stages.Count -eq 1) 'Failed staging must be preserved.'
            Assert-Fixture (Test-Path -LiteralPath (Join-Path $stages[0].FullName 'promotion-failure.json')) 'Failed staging needs an explicit failure record.'
        }
        finally { Set-Item Function:\Copy-ReleasePromotionFile -Value $originalCopy }
    }
    $fixture = New-PromotionFixture
    $cliReview = Invoke-FixtureCli $fixture.Inputs Inventory
    Assert-Fixture ($cliReview.ExitCode -eq 0 -and ($cliReview.Text | ConvertFrom-Json).source.fingerprintSha256 -ceq $fixture.Fingerprint) "Executable inventory mode must return the same fingerprint without writes: $($cliReview.Text)"
    Assert-Fixture (-not (Test-Path -LiteralPath $fixture.Output)) 'Inventory mode must not create a candidate.'
    $cliPromotion = Invoke-FixtureCli $fixture.Inputs Promote @('-OutputRoot', $fixture.Output, '-ExpectedSourceFingerprint', $fixture.Fingerprint)
    Assert-Fixture ($cliPromotion.ExitCode -eq 0 -and ($cliPromotion.Text | ConvertFrom-Json).status -ceq 'Passed') 'Executable promotion mode must produce a verified candidate.'
    $cliRejected = Invoke-FixtureCli $fixture.Inputs Promote @('-OutputRoot', $fixture.Output, '-ExpectedSourceFingerprint', $fixture.Fingerprint)
    Assert-Fixture ($cliRejected.ExitCode -ne 0) 'Executable rejection must return nonzero.'
    Write-Host "PASS: $script:assertions source promotion assertions on PowerShell $($PSVersionTable.PSVersion); fingerprint=$($positive.Fingerprint)."
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixtureRoot)
    if ($resolved.StartsWith($tempParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolved) -match '^bsl-source-promotion-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
    }
    else { throw 'Refusing cleanup outside the synthetic promotion fixture root.' }
}
