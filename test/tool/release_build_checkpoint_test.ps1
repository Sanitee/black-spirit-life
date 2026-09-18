[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $project 'tool/release/build_checkpoint.ps1')
$root = Join-Path $project ('build/release-tooling-tests/checkpoint-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($root)
$script:count = 0
function Check([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message }; $script:count++ }
function Reject([scriptblock]$Action) { $failed = $false; try { & $Action | Out-Null } catch { $failed = $true }; Check $failed 'Expected rejection.' }
function Put([string]$Path, [string]$Value) { $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)); [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false)) }
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
$source = Join-Path $root 'source'
Put (Join-Path $source 'lib/app.dart') 'approved source'
Put (Join-Path $source 'assets/icon.txt') 'approved asset'
Put (Join-Path $source 'assets/bin/catalog.json') 'approved nested asset'
Put (Join-Path $source '.dart_tool/package_config.json') '{"configVersion":2,"packages":[{"name":"fixture","rootUri":"../"}]}'
$buildLock = Open-ReleaseSourceBuildLock -ProjectRoot $source
try {
    Check ($buildLock.Name -ceq (Join-Path $source 'build\release-builder.lock')) 'Build lock must be independent of plan output directory.'
    Reject { Open-ReleaseSourceBuildLock -ProjectRoot $source }
} finally { $buildLock.Dispose() }
$nextLock = Open-ReleaseSourceBuildLock -ProjectRoot $source
Check $nextLock.CanWrite 'Released OS ownership did not permit a retry.'
$nextLock.Dispose()
$profile = [ordered]@{ schemaVersion = 1; purpose = 'same-candidate-build-retry'; approvalReference = 'synthetic fixture'
    completeExternalInputsReviewed = $true; inputTrees = @(); inputFiles = @() }
foreach ($role in @('flutter-sdk','native-toolchain','windows-sdk','dotnet-sdk','package-cache')) {
    $path = Join-Path $root $role
    Put (Join-Path $path 'input.txt') ('fixed-' + $role)
    $profile.inputTrees += [ordered]@{ role = $role; path = $path }
}
$profilePath = Join-Path $root 'inputs.json'
Put $profilePath ($profile | ConvertTo-Json -Depth 8)
$tool = Join-Path $root 'compiler.exe'; Put $tool 'synthetic tool'
$args = @{ ProjectRoot = $source; ReleasePlanSha256 = ('A' * 64); ProfilePath = $profilePath
    ApprovedProfileSha256 = Hash $profilePath; Tools = [ordered]@{ compiler = $tool }; BuildArguments = @('build','--release') }
$context = Get-ReleaseBuildRetryContext @args
Check ($context.Fingerprint -cmatch '^[A-F0-9]{64}$') 'Context hash invalid.'
Check ((Get-ReleaseBuildRetryContext @args).Fingerprint -ceq $context.Fingerprint) 'Stable context changed.'
$ocrRoot = Join-Path $source 'windows/storage_ocr/BlackSpiritStorageOcr'
Put (Join-Path $ocrRoot 'BlackSpiritStorageOcr.csproj') 'synthetic producer source'
$context = Get-ReleaseBuildRetryContext @args
Put (Join-Path $ocrRoot 'obj/generated.cache') 'synthetic generated output'
Put (Join-Path $ocrRoot 'bin/generated.exe') 'synthetic generated output'
Check ((Get-ReleaseBuildRetryContext @args).Fingerprint -ceq $context.Fingerprint) 'Exact OCR intermediates invalidated checkpoint.'
$bundle = Join-Path $source 'build/runner/Release'
Put (Join-Path $bundle 'App.exe') 'synthetic app'
Put (Join-Path $bundle 'data/resource.txt') 'synthetic resource'
$null = [IO.Directory]::CreateDirectory((Join-Path $bundle 'empty'))
$checkpoint = New-ReleaseBundleCheckpoint -BundlePath $bundle -OutputRoot (Join-Path $root 'accepted') -Context $context -ConfirmPayloadVerified
Check (Test-Path -LiteralPath $checkpoint.Path) 'Receipt missing.'
$restoreArgs = @{ ReceiptPath = $checkpoint.Path; ApprovedReceiptSha256 = $checkpoint.Sha256; Context = $context; Destination = Join-Path $root 'restored' }
$restored = Restore-ReleaseBundleCheckpoint @restoreArgs
Check ($restored.Fingerprint -ceq $checkpoint.Fingerprint) 'Restored output differs.'
Check (Test-Path -LiteralPath (Join-Path $restored.Root 'empty') -PathType Container) 'Empty directory lost.'
Reject { Restore-ReleaseBundleCheckpoint @restoreArgs }
Reject { New-ReleaseBundleCheckpoint -BundlePath $bundle -OutputRoot (Join-Path $root 'accepted') -Context $context -ConfirmPayloadVerified }
$restoreArgs.Destination = Join-Path $root 'rejected'
foreach ($mutation in @(
    @{path = (Join-Path $source 'lib/app.dart'); value = 'changed source'},
    @{path = (Join-Path $source 'assets/icon.txt'); value = 'changed asset'},
    @{path = (Join-Path $source 'assets/bin/catalog.json'); value = 'changed nested asset'},
    @{path = (Join-Path $source '.dart_tool/package_config.json'); value = '{"configVersion":2,"different":true,"packages":[{"name":"fixture","rootUri":"../"}]}'},
    @{path = $tool; value = 'changed tool'},
    @{path = (Join-Path $root 'windows-sdk/input.txt'); value = 'changed SDK'},
    @{path = (Join-Path $root 'package-cache/input.txt'); value = 'changed dependency'}
)) {
    $old = Get-Content -LiteralPath $mutation.path -Raw
    Put $mutation.path $mutation.value
    $changed = Get-ReleaseBuildRetryContext @args
    Check ($changed.Fingerprint -cne $context.Fingerprint) 'Input mutation went undetected.'
    $restoreArgs.Context = $changed
    Reject { Restore-ReleaseBundleCheckpoint @restoreArgs }
    Put $mutation.path $old
}
$restoreArgs.Context = $context
$oldEnv = $env:BSL_CHECKPOINT_FIXTURE
try {
    $env:BSL_CHECKPOINT_FIXTURE = [Guid]::NewGuid().ToString()
    Check ((Get-ReleaseBuildRetryContext @args).Fingerprint -cne $context.Fingerprint) 'Environment mutation went undetected.'
} finally { $env:BSL_CHECKPOINT_FIXTURE = $oldEnv }
$args.ReleasePlanSha256 = 'B' * 64
Check ((Get-ReleaseBuildRetryContext @args).Fingerprint -cne $context.Fingerprint) 'Version/plan mutation went undetected.'
$args.ReleasePlanSha256 = 'A' * 64
$args.BuildArguments = @('build','--debug')
Check ((Get-ReleaseBuildRetryContext @args).Fingerprint -cne $context.Fingerprint) 'Flags mutation went undetected.'
$args.BuildArguments = @('build','--release')
Put (Join-Path $source 'untracked.dart') 'new code'
Check ((Get-ReleaseBuildRetryContext @args).Fingerprint -cne $context.Fingerprint) 'New untracked source omitted.'
# Test fixture changes are retained; use original reviewed context for rejection cases.
$originalReceipt = Get-Content -LiteralPath $checkpoint.Path -Raw
Put $checkpoint.Path '{'
Reject { Restore-ReleaseBundleCheckpoint @restoreArgs }
Put $checkpoint.Path $originalReceipt
$payloadFile = Join-Path $checkpoint.BundlePath 'App.exe'
Put $payloadFile 'changed app'
Reject { Restore-ReleaseBundleCheckpoint @restoreArgs }
Put $payloadFile 'synthetic app'
Put (Join-Path $checkpoint.BundlePath 'extra.txt') 'injection'
Reject { Restore-ReleaseBundleCheckpoint @restoreArgs }
Check (-not (Test-Path -LiteralPath $restoreArgs.Destination)) 'Rejected restore created destination.'
Put $profilePath (($profile | ConvertTo-Json -Depth 8) + ' ')
Reject { Get-ReleaseBuildRetryContext @args }
Reject { New-ReleaseBundleCheckpoint -BundlePath $bundle -OutputRoot (Join-Path $bundle 'nested') -Context $context -ConfirmPayloadVerified }
Reject { New-ReleaseBundleCheckpoint -BundlePath $bundle -OutputRoot (Join-Path $root 'unverified') -Context $context -ConfirmPayloadVerified:$false }
$profile.completeExternalInputsReviewed = $false
Put $profilePath ($profile | ConvertTo-Json -Depth 8); $args.ApprovedProfileSha256 = Hash $profilePath
Reject { Get-ReleaseBuildRetryContext @args }
$profile.completeExternalInputsReviewed = $true; $profile.inputTrees = @($profile.inputTrees | Where-Object { $_.role -cne 'windows-sdk' })
Put $profilePath ($profile | ConvertTo-Json -Depth 8); $args.ApprovedProfileSha256 = Hash $profilePath
Reject { Get-ReleaseBuildRetryContext @args }
$profile.inputTrees += [ordered]@{ role = 'windows-sdk'; path = Join-Path $root 'windows-sdk' }
Put $profilePath ($profile | ConvertTo-Json -Depth 8); $args.ApprovedProfileSha256 = Hash $profilePath
$args.RequiredExternalInputs = @([pscustomobject]@{role='windows-sdk';path=(Join-Path $root 'windows-sdk')})
$null = Get-ReleaseBuildRetryContext @args
Check $true 'Whole selected SDK root covered.'
$args.RequiredExternalInputs = @([pscustomobject]@{role='native-toolchain';path=(Join-Path $root 'windows-sdk')})
Reject { Get-ReleaseBuildRetryContext @args }
$args.RequiredExternalInputs = @([pscustomobject]@{role='native-toolchain';path=$root})
Reject { Get-ReleaseBuildRetryContext @args }
$args.RequiredExternalInputs = @()
$configFile = Join-Path $source '.dart_tool/package_config.json'
Put (Join-Path $source 'build/hidden_package/lib.txt') 'generated dependency'
Put $configFile '{"configVersion":2,"packages":[{"name":"fixture","rootUri":"../build/hidden_package/"}]}'
Reject { Get-ReleaseBuildRetryContext @args }
Put $configFile '{"configVersion":2,"packages":[{"name":"fixture","rootUri":"../windows/storage_ocr/BlackSpiritStorageOcr/obj/"}]}'
Reject { Get-ReleaseBuildRetryContext @args }
Put (Join-Path $root 'uncovered-package/lib.txt') 'external dependency'
Put $configFile '{"configVersion":2,"packages":[{"name":"fixture","rootUri":"../../uncovered-package/"}]}'
Reject { Get-ReleaseBuildRetryContext @args }
Put (Join-Path $source 'packages/local/lib.txt') 'source-owned dependency'
Put $configFile '{"configVersion":2,"packages":[{"name":"fixture","rootUri":"../packages/local/"}]}'
$null = Get-ReleaseBuildRetryContext @args
Check $true 'Ordinary source-owned dependency covered.'
Write-Host "Build checkpoint tests passed: $script:count assertions. Synthetic evidence retained: $root"
