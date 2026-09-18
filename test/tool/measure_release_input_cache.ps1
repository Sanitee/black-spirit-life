[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PreviousFeedPath,
    [Parameter(Mandatory = $true)][string]$PreviousPackagePath,
    [Parameter(Mandatory = $true)][string]$ReleasePlanPath,
    [Parameter(Mandatory = $true)][string]$ApprovedReleasePlanSha256
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $project 'tool/release/verified_input_cache.ps1')
. (Join-Path $project 'tool/release/release_plan.ps1')
$releasePlan = Read-ReleasePlan `
    -Path $ReleasePlanPath `
    -ExpectedSha256 $ApprovedReleasePlanSha256
$builder = Join-Path $project 'tool/build_stable_release_candidate.ps1'
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($builder, [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'Builder syntax is invalid.' }

# Read only policy constants and validators from the actual builder. Release
# identity and historical hashes come from the same reviewed plan as a build.
$constantNames = @('DisplayName', 'ExecutableName', 'UpdaterHelperName',
    'ForbiddenPackagedArtifactPattern')
foreach ($name in $constantNames) {
    $assignment = @($ast.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.AssignmentStatementAst] -and
        $_.Left -is [Management.Automation.Language.VariableExpressionAst] -and
        $_.Left.VariablePath.UserPath -ceq $name
    })
    if ($assignment.Count -ne 1) { throw "Expected exactly one reviewed constant: $name" }
    . ([scriptblock]::Create($assignment[0].Extent.Text))
}
$PackageId = $releasePlan.PackageId
$PreviousStableVersion = $releasePlan.PreviousVersion
$UpdateChannel = $releasePlan.Channel
$PreviousFeedBytes = $releasePlan.PreviousFeedBytes
$PreviousFeedSha256 = $releasePlan.PreviousFeedSha256
$PreviousFullPackageBytes = $releasePlan.PreviousFullPackageBytes
$PreviousFullPackageSha256 = $releasePlan.PreviousFullPackageSha256
$packageFunction = @($ast.EndBlock.Statements | Where-Object {
    $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -ceq 'Assert-VelopackPackage'
})
if ($packageFunction.Count -ne 1) { throw 'Package validator is ambiguous.' }
. ([scriptblock]::Create($packageFunction[0].Extent.Text))
$validators = @($ast.FindAll({ param($node)
    $node -is [Management.Automation.Language.ScriptBlockExpressionAst] -and
    $node.Parent -is [Management.Automation.Language.CommandAst] -and
    $node.Parent.GetCommandName() -ceq 'Get-VerifiedReleaseInput'
}, $true))
if ($validators.Count -ne 2) { throw 'Expected the two builder content validators.' }
$feedValidator = $validators[0].ScriptBlock.GetScriptBlock()
$packageValidator = $validators[1].ScriptBlock.GetScriptBlock()
$previousFullPackageName = "$PackageId-$PreviousStableVersion-$UpdateChannel-full.nupkg"
$feedIndexName = "releases.$UpdateChannel.json"
$run = Join-Path $project ('build/release-tooling-tests/input-cache-' + [Guid]::NewGuid().ToString('N'))
$cache = Join-Path $run 'cache'
$null = Assert-ReleaseOrdinaryPath -Path $run
$null = [IO.Directory]::CreateDirectory($run)
$records = [Collections.Generic.List[object]]::new()
foreach ($phase in @('import', 'warm')) {
    $destination = Join-Path $run $phase
    $null = [IO.Directory]::CreateDirectory($destination)
    foreach ($kind in @('feed', 'package')) {
        $argsForInput = @{
            CacheRoot = $cache; Repository = $releasePlan.Repository
            ReleaseTag = $releasePlan.PreviousTag; Channel = $UpdateChannel
            Offline = $true; Download = { throw 'Measurement must never download.' }
        }
        if ($kind -eq 'feed') {
            $argsForInput.Role = 'previous-feed'
            $argsForInput.ArtifactName = $feedIndexName
            $argsForInput.ExpectedBytes = $PreviousFeedBytes
            $argsForInput.ExpectedSha256 = $PreviousFeedSha256
            $argsForInput.ValidateContent = $feedValidator
            if ($phase -eq 'import') { $argsForInput.ExistingFile = $PreviousFeedPath }
        }
        else {
            $argsForInput.Role = 'previous-full'
            $argsForInput.ArtifactName = $previousFullPackageName
            $argsForInput.ExpectedBytes = $PreviousFullPackageBytes
            $argsForInput.ExpectedSha256 = $PreviousFullPackageSha256
            $argsForInput.ValidateContent = $packageValidator
            if ($phase -eq 'import') { $argsForInput.ExistingFile = $PreviousPackagePath }
        }
        $argsForInput.Destination = Join-Path $destination $argsForInput.ArtifactName
        $result = Get-VerifiedReleaseInput @argsForInput
        if ($result.downloadedBytes -ne 0 -or $result.attempts -ne 0 -or
            ($phase -eq 'warm' -and $result.cacheStatus -cne 'hit')) {
            throw 'Offline historical-input measurement did not prove verified reuse.'
        }
        $records.Add([ordered]@{ phase = $phase; input = $result })
    }
}
$report = [ordered]@{
    schemaVersion = 1; purpose = 'offline-historical-input-measurement'
    powershell = $PSVersionTable.PSVersion.ToString()
    isReleaseVerification = $false
    builderSha256 = (Get-FileHash -LiteralPath $builder -Algorithm SHA256).Hash
    releasePlanSha256 = $releasePlan.Sha256
    avoidedWarmDownloadBytes = $PreviousFullPackageBytes + $PreviousFeedBytes
    records = @($records.ToArray())
}
$reportPath = Join-Path $run 'measurement.json'
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
$report | ConvertTo-Json -Depth 8
Write-Host "Measurement retained at: $reportPath"
