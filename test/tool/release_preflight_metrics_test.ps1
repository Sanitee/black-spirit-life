[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$helpers = Join-Path $project 'tool\release'
. (Join-Path $helpers 'preflight.ps1')
. (Join-Path $helpers 'stage_metrics.ps1')

$script:checks = 0
function Assert-Fixture {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Fixture assertion failed: $Message" }
    $script:checks++
}
function Assert-FixtureThrows {
    param([scriptblock]$Action, [string]$MessagePattern)
    $caught = $false
    try { & $Action }
    catch {
        $caught = $true
        Assert-Fixture ($_.Exception.Message -match $MessagePattern) "Unexpected failure: $($_.Exception.Message)"
    }
    Assert-Fixture $caught 'Expected a terminating failure.'
}
function Set-FixtureFile {
    param([string]$Path, [string]$Content)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent
    }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\', '/'))
$fixtureRoot = Join-Path $tempParent ('bsl-preflight-metrics-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixtureRoot
try {
    $fixtureProject = Join-Path $fixtureRoot 'project with spaces'
    $toolDirectory = Join-Path $fixtureRoot 'tools with spaces'
    Set-FixtureFile (Join-Path $fixtureProject 'pubspec.yaml') "name: fixture`nversion: 1.2.3+4`nenvironment:`n  sdk: ^3.12.2`n"
    Set-FixtureFile (Join-Path $fixtureProject 'pubspec.lock') 'packages: {}'
    Set-FixtureFile (Join-Path $fixtureProject '.dart_tool/package_config.json') '{"configVersion":2,"packages":[]}'
    Set-FixtureFile (Join-Path $fixtureProject 'tool/check.ps1') '$fixtureValue = 1'
    $flutter = Join-Path $toolDirectory 'flutter.bat'
    $cmake = Join-Path $toolDirectory 'cmake.cmd'
    $dotnet = Join-Path $toolDirectory 'dotnet.cmd'
    $git = Join-Path $toolDirectory 'git.cmd'
    $tar = Join-Path $toolDirectory 'tar.cmd'
    # Running Flutter at preflight would be a bug: its launcher may download.
    Set-FixtureFile $flutter "@echo off`r`nexit /b 97`r`n"
    Set-FixtureFile (Join-Path $toolDirectory 'cache/flutter.version.json') '{"frameworkVersion":"3.44.0","dartSdkVersion":"3.12.2"}'
    Set-FixtureFile $cmake "@echo off`r`necho cmake version 3.31.0`r`nexit /b 0`r`n"
    Set-FixtureFile $git "@echo off`r`necho git version 2.49.0.windows.1`r`nexit /b 0`r`n"
    Set-FixtureFile $tar "@echo off`r`necho bsdtar 3.8.1 - libarchive`r`nexit /b 0`r`n"
    $validDotnet = "@echo off`r`nif `"%1`"==`"--list-sdks`" echo 8.0.400 [fixture-sdk]`r`nif `"%1`"==`"--list-runtimes`" echo Microsoft.NETCore.App 8.0.20 [fixture-runtime]`r`nexit /b 0`r`n"
    Set-FixtureFile $dotnet $validDotnet
    $options = @{
        ProjectRoot = $fixtureProject
        Version = '1.2.3'
        BuildNumber = '4'
        PublicGitHubRepository = 'https://github.com/example/fixture'
        FlutterPath = $flutter
        CMakePath = $cmake
        DotnetPath = $dotnet
        GitPath = $git
        TarPath = $tar
        RequiredRelativeFiles = @('tool/check.ps1')
    }
    $script:expensiveInvocations = 0
    function Invoke-FixtureWorkflow {
        param([hashtable]$PreflightOptions)
        $result = Invoke-ReleasePreflight @PreflightOptions
        $script:expensiveInvocations++
        return $result
    }
    $beforeFiles = @(Get-ChildItem -LiteralPath $fixtureRoot -Recurse -File | ForEach-Object {
        $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    })
    $result = Invoke-FixtureWorkflow -PreflightOptions $options
    Assert-Fixture ($script:expensiveInvocations -eq 1) 'Valid prerequisites allow the subsequent work.'
    Assert-Fixture ($result.FlutterPath -ceq $flutter) 'Explicit Flutter path is retained.'
    Assert-Fixture ($result.Evidence.toolVersions.cmake -ceq '3.31.0') 'CMake evidence is parsed.'
    Assert-Fixture ($result.Evidence.toolVersions.flutterVersionSource -ceq 'installed-cache-metadata') 'Flutter was not launched.'
    Assert-Fixture ($result.Evidence.toolVersions.dotnet8Runtimes[0] -ceq '8.0.20') '.NET runtime evidence excludes installation paths.'
    $evidenceJson = $result.Evidence | ConvertTo-Json -Depth 6
    Assert-Fixture (-not $evidenceJson.Contains($fixtureRoot) -and -not $evidenceJson.Contains('fixture-sdk')) 'Evidence does not disclose tool paths.'
    $afterFiles = @(Get-ChildItem -LiteralPath $fixtureRoot -Recurse -File | ForEach-Object {
        $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    })
    Assert-Fixture (($beforeFiles -join "`n") -ceq ($afterFiles -join "`n")) 'Preflight did not change fixture inputs.'
    $fallback = Resolve-ReleaseToolPath -Name 'bsl-fixture-command-not-installed' -FallbackPaths @((Join-Path $toolDirectory 'missing.cmd'), $cmake, $git)
    Assert-Fixture ($fallback -ceq $cmake) 'Tool resolution chooses the first existing fallback.'
    $explicit = Resolve-ReleaseToolPath -Name 'bsl-fixture-command-not-installed' -ExplicitPath $git -FallbackPaths @($cmake)
    Assert-Fixture ($explicit -ceq $git) 'An explicit tool path takes precedence over fallback paths.'
    Assert-FixtureThrows { Invoke-ReleaseVersionCommand -Path (Join-Path $toolDirectory 'missing.cmd') -Operation 'fixture-missing-command' } 'fixture-missing-command could not start'

    foreach ($name in @('FlutterPath', 'CMakePath', 'DotnetPath', 'GitPath', 'TarPath')) {
        $invalid = $options.Clone()
        $invalid[$name] = Join-Path $toolDirectory 'missing.cmd'
        Assert-FixtureThrows { Invoke-FixtureWorkflow $invalid } 'required file is missing'
    }
    foreach ($missing in @('missing.txt', '.dart_tool/missing.json')) {
        $invalid = $options.Clone()
        $invalid.RequiredRelativeFiles = @($missing)
        Assert-FixtureThrows { Invoke-FixtureWorkflow $invalid } 'required file is missing'
    }
    $invalid = $options.Clone()
    $invalid.ProjectRoot = Join-Path $fixtureRoot 'missing-project'
    Assert-FixtureThrows { Invoke-FixtureWorkflow $invalid } 'project directory is missing'
    $invalid = $options.Clone()
    $invalid.Version = '1.2.4'
    Assert-FixtureThrows { Invoke-FixtureWorkflow $invalid } 'does not match'
    $invalid.Version = '01.2.3'
    Assert-FixtureThrows { Invoke-FixtureWorkflow $invalid } 'metadata is invalid'
    $invalid = $options.Clone()
    $invalid.PublicGitHubRepository = 'https://github.com/example/fixture/releases'
    Assert-FixtureThrows { Invoke-FixtureWorkflow $invalid } 'canonical GitHub'
    $invalid = $options.Clone()
    $invalid.RequiredRelativeFiles = @('../outside.txt')
    Assert-FixtureThrows { Invoke-FixtureWorkflow $invalid } 'contained relative path'
    Set-FixtureFile (Join-Path $fixtureProject 'tool/bad.ps1') 'function Broken {'
    $invalid = $options.Clone()
    $invalid.RequiredRelativeFiles = @('tool/bad.ps1')
    Assert-FixtureThrows { Invoke-FixtureWorkflow $invalid } 'syntax check failed'
    $packageConfig = Join-Path $fixtureProject '.dart_tool/package_config.json'
    Move-Item -LiteralPath $packageConfig -Destination ($packageConfig + '.held')
    Assert-FixtureThrows { Invoke-FixtureWorkflow $options } 'required file is missing.*package_config'
    Move-Item -LiteralPath ($packageConfig + '.held') -Destination $packageConfig
    Set-FixtureFile $packageConfig '{invalid'
    Assert-FixtureThrows { Invoke-FixtureWorkflow $options } 'valid package_config'
    Set-FixtureFile $packageConfig '{"configVersion":2,"packages":[]}'
    Set-FixtureFile $cmake "@echo off`r`necho cmake version 3.24.4`r`nexit /b 0`r`n"
    Assert-FixtureThrows { Invoke-FixtureWorkflow $options } 'CMake 3.25'
    Set-FixtureFile $cmake "@echo off`r`necho cmake version 3.31.0`r`nexit /b 0`r`n"
    Set-FixtureFile $dotnet "@echo off`r`necho Microsoft.NETCore.App 9.0.1 [fixture-runtime]`r`nexit /b 0`r`n"
    Assert-FixtureThrows { Invoke-FixtureWorkflow $options } '\.NET 8 or newer SDK'
    Set-FixtureFile $dotnet $validDotnet
    Set-FixtureFile (Join-Path $toolDirectory 'cache/flutter.version.json') '{"frameworkVersion":"3.44.0","dartSdkVersion":"3.11.0"}'
    Assert-FixtureThrows { Invoke-FixtureWorkflow $options } 'Dart does not satisfy'
    Set-FixtureFile (Join-Path $toolDirectory 'cache/flutter.version.json') '{"frameworkVersion":"3.44.0","dartSdkVersion":"3.12.2"}'
    $invalid = $options.Clone()
    $invalid.MinimumFreeBytes = [long]::MaxValue
    Assert-FixtureThrows { Invoke-FixtureWorkflow $invalid } 'disk space'
    Set-FixtureFile $git "@echo off`r`necho fixture-probe-failed 1>&2`r`nexit /b 23`r`n"
    Assert-FixtureThrows { Invoke-FixtureWorkflow $options } 'Preflight git version failed with exit code 23'
    Assert-Fixture ($script:expensiveInvocations -eq 1) 'Every failed preflight stopped before expensive work.'

    Assert-FixtureThrows { Assert-ReleaseCommandExit -Operation 'fixture-child' -ExitCode $null } 'did not supply'
    Assert-ReleaseCommandExit -Operation 'fixture-child' -ExitCode 0
    # Prove a real failing child cannot exit zero or reach the next operation.
    $childScript = Join-Path $fixtureRoot 'child-exit.ps1'
    Set-FixtureFile $childScript @'
param([string]$Helper, [string]$Command, [string]$ReachedPath)
$ErrorActionPreference = 'Stop'
. $Helper
& $Command
Assert-ReleaseCommandExit -Operation 'fixture-child' -ExitCode $LASTEXITCODE
[IO.File]::WriteAllText($ReachedPath, 'unexpected')
'@
    $shell = (Get-Process -Id $PID).Path
    $reachedPath = Join-Path $fixtureRoot 'unexpected-expensive-operation.txt'
    $savedErrorPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $childOutput = @(& $shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $childScript -Helper (Join-Path $helpers 'preflight.ps1') -Command $git -ReachedPath $reachedPath 2>&1)
        $childExit = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $savedErrorPreference }
    Assert-Fixture ($childExit -ne 0) 'A failing required command produces a nonzero process result.'
    Assert-Fixture (($childOutput -join "`n") -match 'fixture-child failed with exit code 23') 'Child failure identifies the operation.'
    Assert-Fixture (-not (Test-Path -LiteralPath $reachedPath)) 'Child failure stops subsequent operations.'

    $metrics = New-ReleaseStageMetrics -RunId 'fixture-run'
    $metricsPath = Join-Path $fixtureRoot 'stage-metrics.json'
    Save-ReleaseStageMetrics -Metrics $metrics -Path $metricsPath
    $saved = Get-Content -LiteralPath $metricsPath -Raw | ConvertFrom-Json
    Assert-Fixture ($saved.outcome -ceq 'Incomplete') 'An empty run cannot pass.'
    $stage = Start-ReleaseStage -Metrics $metrics -Name 'preflight' -InputBytes 123
    Save-ReleaseStageMetrics -Metrics $metrics -Path $metricsPath
    $saved = Get-Content -LiteralPath $metricsPath -Raw | ConvertFrom-Json
    Assert-Fixture ($saved.outcome -ceq 'Incomplete' -and $saved.stages[0].outcome -ceq 'Running') 'An interrupted stage stays unfinished.'
    Assert-Fixture ($null -eq $saved.stages[0].endedAtUtc -and $null -eq $saved.stages[0].durationMilliseconds) 'An unfinished stage has no completion timestamp.'
    Complete-ReleaseStage -Metrics $metrics -Stage $stage -Outcome Passed -OutputBytes 45 -TransferredBytes 0 -CacheState NotApplicable
    Save-ReleaseStageMetrics -Metrics $metrics -Path $metricsPath
    $saved = Get-Content -LiteralPath $metricsPath -Raw | ConvertFrom-Json
    Assert-Fixture ($saved.outcome -ceq 'Passed') 'Explicit successful stages pass measurement.'
    Assert-Fixture ($saved.stages[0].inputBytes -eq 123 -and $saved.stages[0].outputBytes -eq 45 -and $saved.stages[0].transferredBytes -eq 0) 'Byte counts survive serialization.'
    Assert-Fixture ($saved.stages[0].durationMilliseconds -ge 0 -and $null -ne $saved.stages[0].endedAtUtc) 'Completed stage has timing evidence.'
    Assert-Fixture ($saved.isResumeReceipt -eq $false -and $saved.isReleaseVerification -eq $false) 'Measurement cannot be mistaken for release/resume proof.'
    Assert-FixtureThrows { Complete-ReleaseStage -Metrics $metrics -Stage $stage -Outcome Failed -FailureCode 'late-failure' } 'cannot be rewritten'
    Assert-FixtureThrows { Start-ReleaseStage -Metrics $metrics -Name 'preflight' } 'attempt already exists'

    $failed = Start-ReleaseStage -Metrics $metrics -Name 'packaging'
    Assert-FixtureThrows { Complete-ReleaseStage -Metrics $metrics -Stage $failed -Outcome Failed } 'requires a failure code'
    Assert-FixtureThrows { Complete-ReleaseStage -Metrics $metrics -Stage $failed -Outcome Failed -FailureCode $fixtureRoot } 'safe lowercase codes'
    Assert-FixtureThrows { Complete-ReleaseStage -Metrics $metrics -Stage $failed -Outcome Passed -CacheState Miss } 'miss requires a reason'
    Complete-ReleaseStage -Metrics $metrics -Stage $failed -Outcome Failed -FailureCode 'fixture-package-failed' -CacheState Miss -CacheMissReason 'not-cached' -TransferredBytes 17
    $retry = Start-ReleaseStage -Metrics $metrics -Name 'packaging' -Attempt 2
    Complete-ReleaseStage -Metrics $metrics -Stage $retry -Outcome Passed -CacheState Hit -TransferredBytes 0
    Save-ReleaseStageMetrics -Metrics $metrics -Path $metricsPath
    $saved = Get-Content -LiteralPath $metricsPath -Raw | ConvertFrom-Json
    Assert-Fixture ($saved.outcome -ceq 'Failed' -and $saved.failedStages[0] -ceq 'packaging') 'A passing retry does not erase an earlier failed attempt.'
    Assert-Fixture ($saved.stages[1].outcome -ceq 'Failed' -and $saved.stages[2].attempt -eq 2) 'Failure and retry are separate records.'
    Assert-Fixture ($null -eq $saved.stages[1].inputBytes) 'Unknown bytes are null, not invented zero.'
    Assert-Fixture ($saved.stages[1].cacheMissReason -ceq 'not-cached') 'Cache miss reason is retained.'
    Assert-Fixture (-not (Get-Content -LiteralPath $metricsPath -Raw).Contains($fixtureRoot)) 'Saved measurements contain no fixture path.'
    Assert-Fixture (@(Get-ChildItem -LiteralPath $fixtureRoot -Filter '*.partial-*').Count -eq 0) 'Atomic saves leave no successful-run partial files.'
    Write-Host "PASS: $script:checks preflight/metrics assertions on PowerShell $($PSVersionTable.PSVersion)."
}
finally {
    $resolvedFixtureRoot = [IO.Path]::GetFullPath($fixtureRoot)
    if ($resolvedFixtureRoot.StartsWith($tempParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedFixtureRoot) -match '^bsl-preflight-metrics-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $resolvedFixtureRoot -Recurse -Force -ErrorAction Stop
    }
    else {
        throw 'Refusing fixture cleanup outside the validated temporary test directory.'
    }
}
