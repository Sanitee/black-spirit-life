[CmdletBinding()]
param([string]$PowerShellPath = (Get-Process -Id $PID).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'release/verified_input_cache.ps1')
. (Join-Path $PSScriptRoot 'release/preflight.ps1')
. (Join-Path $PSScriptRoot 'release/stage_metrics.ps1')
$null = Assert-ReleasePreflightFile -Path $PowerShellPath -Label 'PowerShell test runtime'
$testNames = @(
    'release_input_cache_test.ps1',
    'release_source_inventory_test.ps1',
    'release_preflight_metrics_test.ps1',
    'release_builder_integration_test.ps1',
    'release_payload_scan_test.ps1',
    'publish_verified_release_test.ps1'
)
$runId = 'self-tests-' + [Guid]::NewGuid().ToString('N')
$output = Join-Path $project "build/release-tooling-tests/$runId"
$null = Assert-ReleaseOrdinaryPath -Path $output
$null = [IO.Directory]::CreateDirectory($output)
$metrics = New-ReleaseStageMetrics -RunId $runId
$manifest = [Collections.Generic.List[object]]::new()
try {
    foreach ($testName in $testNames) {
        $testPath = Join-Path $project "test/tool/$testName"
        $stage = Start-ReleaseStage -Metrics $metrics -Name ([IO.Path]::GetFileNameWithoutExtension($testName))
        try {
            $null = Assert-ReleasePreflightFile -Path $testPath -Label $testName
            $parseErrors = $null
            $null = [Management.Automation.Language.Parser]::ParseFile($testPath, [ref]$null, [ref]$parseErrors)
            if ($parseErrors.Count -ne 0) { throw "Test syntax failed: $testName" }
            $manifest.Add([ordered]@{
                file = "test/tool/$testName"
                sha256 = (Get-FileHash -LiteralPath $testPath -Algorithm SHA256).Hash
            })
            # Only this child process gets the local-script execution setting;
            # no machine/user policy or other Windows setting is modified.
            $PSNativeCommandUseErrorActionPreference = $false
            $global:LASTEXITCODE = $null
            $savedPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $lines = @(& $PowerShellPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $testPath 2>&1)
                $testExitCode = $global:LASTEXITCODE
            }
            finally { $ErrorActionPreference = $savedPreference }
            $text = ($lines | ForEach-Object { [string]$_ }) -join "`r`n"
            [IO.File]::WriteAllText((Join-Path $output "$testName.log"), $text, [Text.UTF8Encoding]::new($false))
            Write-Host $text
            Assert-ReleaseCommandExit -Operation $testName -ExitCode $testExitCode
            Complete-ReleaseStage -Metrics $metrics -Stage $stage -Outcome Passed -CacheState NotApplicable
        }
        catch {
            Complete-ReleaseStage -Metrics $metrics -Stage $stage -Outcome Failed -FailureCode 'tooling-test-failed'
            throw
        }
        finally { Save-ReleaseStageMetrics -Metrics $metrics -Path (Join-Path $output 'stage-metrics.json') }
    }
}
finally {
    $document = [ordered]@{
        schemaVersion = 1; purpose = 'release-tooling-self-tests'
        isApplicationAcceptance = $false; isReleaseVerification = $false
        tests = @($manifest.ToArray())
    }
    [IO.File]::WriteAllText((Join-Path $output 'test-manifest.json'),
        ($document | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    Write-Host "Tooling test evidence: $output"
}
