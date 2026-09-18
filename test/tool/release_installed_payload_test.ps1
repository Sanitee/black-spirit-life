[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$python = $env:BSL_RELEASE_PYTHON
if ([string]::IsNullOrWhiteSpace($python)) {
    $bundled = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    if (Test-Path -LiteralPath $bundled -PathType Leaf) { $python = $bundled }
    else { $python = (Get-Command 'python.exe' -CommandType Application -ErrorAction Stop).Source }
}
$priorPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $messages = @(& $python -I -E -B (Join-Path $repository 'test\tool\test_installed_payload.py') 2>&1)
    $exitCode = $LASTEXITCODE
}
finally { $ErrorActionPreference = $priorPreference }
$messages | ForEach-Object { Write-Host ([string]$_) }
if ($null -eq $exitCode -or $exitCode -ne 0) { throw 'Installed-payload parity synthetic tests failed.' }
Write-Host "PASS: installed-payload parity synthetic tests on PowerShell $($PSVersionTable.PSVersion)."
