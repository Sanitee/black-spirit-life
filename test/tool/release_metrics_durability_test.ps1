[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $project 'tool/release/stage_metrics.ps1')
$root = Join-Path $project ('build/release-tooling-tests/metrics-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($root)
$path = Join-Path $root 'stage-metrics.json'
$metrics = New-ReleaseStageMetrics -RunId 'synthetic-durable' -AutoSavePath $path
$stage = Start-ReleaseStage -Metrics $metrics -Name 'build'
$started = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
if ($started.outcome -cne 'Incomplete' -or $started.currentStages[0] -cne 'build') { throw 'Running state not persisted before completion.' }
Complete-ReleaseStage -Metrics $metrics -Stage $stage -Outcome Passed -CacheState NotApplicable
$passed = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
if ($passed.outcome -cne 'Passed' -or $passed.stages[0].outcome -cne 'Passed') { throw 'Completion not persisted.' }
$failedStage = Start-ReleaseStage -Metrics $metrics -Name 'package'
$incomplete = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
if ($incomplete.outcome -cne 'Incomplete' -or $incomplete.stages[0].outcome -cne 'Passed') { throw 'A later interrupted stage lost completed evidence.' }
Complete-ReleaseStage -Metrics $metrics -Stage $failedStage -Outcome Failed -FailureCode 'fixture-failure'
$failed = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
if ($failed.outcome -cne 'Failed' -or $failed.failedStages[0] -cne 'package' -or $failed.isResumeReceipt -or $failed.isReleaseVerification) { throw 'Measurement claimed acceptance or lost failure.' }
if (@(Get-ChildItem -LiteralPath $root -Filter '*.partial-*').Count -ne 0) { throw 'Atomic save left partial files.' }
Write-Host 'PASS: 5 stage-boundary durability assertions.'
