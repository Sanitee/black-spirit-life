# Measurement evidence only. These records do not prove artifact integrity,
# permit stage resume, or replace any release acceptance gate.

function New-ReleaseStageMetrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId,
        [string]$AutoSavePath
    )
    return [pscustomobject]@{
        SchemaVersion = 1
        RunId = $RunId
        AutoSavePath = $AutoSavePath
        StartedAtUtc = [DateTime]::UtcNow.ToString('o')
        Stages = [Collections.Generic.List[object]]::new()
    }
}

function Start-ReleaseStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Metrics,
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9][a-z0-9._-]*$')][string]$Name,
        [ValidateRange(1, [int]::MaxValue)][int]$Attempt = 1,
        [Nullable[long]]$InputBytes = $null
    )
    if ($Metrics.SchemaVersion -ne 1) { throw 'Unsupported release metrics schema.' }
    if ($null -ne $InputBytes -and $InputBytes -lt 0) { throw 'Stage input bytes cannot be negative.' }
    if (@($Metrics.Stages | Where-Object { $_.Name -ceq $Name -and $_.Attempt -eq $Attempt }).Count -ne 0) {
        throw 'A stage attempt already exists in this measurement run.'
    }
    $stage = [pscustomobject]@{
        Id = [Guid]::NewGuid().ToString('N')
        Name = $Name
        Attempt = $Attempt
        StartedAtUtc = [DateTime]::UtcNow.ToString('o')
        EndedAtUtc = $null
        DurationMilliseconds = $null
        InputBytes = $InputBytes
        OutputBytes = $null
        TransferredBytes = $null
        CacheState = 'Unknown'
        CacheMissReason = $null
        Outcome = 'Running'
        FailureCode = $null
        Stopwatch = [Diagnostics.Stopwatch]::StartNew()
    }
    $Metrics.Stages.Add($stage)
    if (-not [string]::IsNullOrWhiteSpace($Metrics.AutoSavePath)) {
        Save-ReleaseStageMetrics -Metrics $Metrics -Path $Metrics.AutoSavePath
    }
    Write-Host "Release stage started: $Name (attempt $Attempt)."
    return $stage
}

function Complete-ReleaseStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Metrics,
        [Parameter(Mandatory = $true)][object]$Stage,
        [Parameter(Mandatory = $true)][ValidateSet('Passed', 'Failed')][string]$Outcome,
        [Nullable[long]]$OutputBytes = $null,
        [Nullable[long]]$TransferredBytes = $null,
        [ValidateSet('Unknown', 'NotApplicable', 'Hit', 'Miss')][string]$CacheState = 'Unknown',
        [AllowNull()][AllowEmptyString()][string]$CacheMissReason,
        [AllowNull()][AllowEmptyString()][string]$FailureCode
    )
    if ($Metrics.SchemaVersion -ne 1) { throw 'Unsupported release metrics schema.' }
    if (@($Metrics.Stages | Where-Object { [object]::ReferenceEquals($_, $Stage) }).Count -ne 1) {
        throw 'Stage does not belong to this measurement run.'
    }
    if ($Stage.Outcome -cne 'Running') { throw 'A completed stage attempt cannot be rewritten.' }
    if (($null -ne $OutputBytes -and $OutputBytes -lt 0) -or
        ($null -ne $TransferredBytes -and $TransferredBytes -lt 0)) {
        throw 'Stage byte counts cannot be negative.'
    }
    # Only bounded public-safe reason codes are saved, never raw exceptions,
    # command lines, environment values or absolute paths.
    foreach ($code in @($FailureCode, $CacheMissReason)) {
        if (-not [string]::IsNullOrEmpty($code) -and $code -cnotmatch '^[a-z0-9][a-z0-9._-]{0,119}$') {
            throw 'Stage reasons must be safe lowercase codes, not raw diagnostic text.'
        }
    }
    if ($Outcome -ceq 'Failed' -and [string]::IsNullOrWhiteSpace($FailureCode)) {
        throw 'A failed stage requires a failure code.'
    }
    if ($Outcome -ceq 'Passed' -and -not [string]::IsNullOrWhiteSpace($FailureCode)) {
        throw 'A passed stage cannot have a failure code.'
    }
    if ($CacheState -ceq 'Miss' -and [string]::IsNullOrWhiteSpace($CacheMissReason)) {
        throw 'A cache miss requires a reason code.'
    }
    if ($CacheState -cne 'Miss' -and -not [string]::IsNullOrWhiteSpace($CacheMissReason)) {
        throw 'A cache miss reason requires cache state Miss.'
    }
    $Stage.Stopwatch.Stop()
    $Stage.EndedAtUtc = [DateTime]::UtcNow.ToString('o')
    $Stage.DurationMilliseconds = $Stage.Stopwatch.Elapsed.TotalMilliseconds
    $Stage.OutputBytes = $OutputBytes
    $Stage.TransferredBytes = $TransferredBytes
    $Stage.CacheState = $CacheState
    $Stage.CacheMissReason = $CacheMissReason
    $Stage.FailureCode = $FailureCode
    $Stage.Outcome = $Outcome
    if (-not [string]::IsNullOrWhiteSpace($Metrics.AutoSavePath)) {
        Save-ReleaseStageMetrics -Metrics $Metrics -Path $Metrics.AutoSavePath
    }
    Write-Host "Release stage ${Outcome}: $($Stage.Name)."
}

function Save-ReleaseStageMetrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Metrics,
        [Parameter(Mandatory = $true)][string]$Path
    )
    if ($Metrics.SchemaVersion -ne 1) { throw 'Unsupported release metrics schema.' }
    $records = @($Metrics.Stages | ForEach-Object {
        [ordered]@{
            name = $_.Name
            attempt = $_.Attempt
            startedAtUtc = $_.StartedAtUtc
            endedAtUtc = $_.EndedAtUtc
            durationMilliseconds = $_.DurationMilliseconds
            inputBytes = $_.InputBytes
            outputBytes = $_.OutputBytes
            transferredBytes = $_.TransferredBytes
            cacheState = $_.CacheState
            cacheMissReason = $_.CacheMissReason
            outcome = $_.Outcome
            failureCode = $_.FailureCode
        }
    })
    $outcome = 'Incomplete'
    if (@($Metrics.Stages | Where-Object { $_.Outcome -ceq 'Failed' }).Count -gt 0) {
        $outcome = 'Failed'
    }
    elseif ($records.Count -gt 0 -and @($Metrics.Stages | Where-Object { $_.Outcome -cne 'Passed' }).Count -eq 0) {
        $outcome = 'Passed'
    }
    $document = [ordered]@{
        schemaVersion = 1
        purpose = 'stage-measurement-only'
        isResumeReceipt = $false
        isReleaseVerification = $false
        runId = $Metrics.RunId
        startedAtUtc = $Metrics.StartedAtUtc
        savedAtUtc = [DateTime]::UtcNow.ToString('o')
        outcome = $outcome
        currentStages = @($Metrics.Stages | Where-Object { $_.Outcome -ceq 'Running' } | ForEach-Object { $_.Name })
        failedStages = @($Metrics.Stages | Where-Object { $_.Outcome -ceq 'Failed' } | ForEach-Object { $_.Name })
        stages = $records
    }
    $target = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw 'Create the intended evidence directory before saving stage metrics.'
    }
    $existingTarget = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    if ($null -ne $existingTarget -and
        (($existingTarget.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $existingTarget.PSIsContainer)) {
        throw 'Metrics target must be an ordinary file.'
    }
    $partial = $target + '.partial-' + [Guid]::NewGuid().ToString('N')
    $json = $document | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($partial, "$json`r`n", [Text.UTF8Encoding]::new($false))
    if ([IO.File]::Exists($target)) {
        [IO.File]::Replace($partial, $target, [Management.Automation.Language.NullString]::Value)
    }
    else {
        [IO.File]::Move($partial, $target)
    }
}
