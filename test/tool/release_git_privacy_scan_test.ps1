[CmdletBinding()]
param([string]$PythonPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($PythonPath)) {
    $PythonPath = $env:BSL_RELEASE_PYTHON
}
if ([string]::IsNullOrWhiteSpace($PythonPath)) {
    $command = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($null -eq $command) { $command = Get-Command python3 -ErrorAction SilentlyContinue }
    if ($null -eq $command) {
        throw 'Python 3.9+ is required. Supply -PythonPath or BSL_RELEASE_PYTHON.'
    }
    $PythonPath = $command.Source
}
if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
    throw 'The selected Python executable is missing.'
}
$python = (Get-Item -LiteralPath $PythonPath).FullName
& $python -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)'
if ($LASTEXITCODE -ne 0) { throw 'A working Python 3.9+ interpreter is required.' }
$previousShell = $env:BSL_PRIVACY_TEST_POWERSHELL
try {
    $env:BSL_PRIVACY_TEST_POWERSHELL = (Get-Process -Id $PID).Path
    & $python -B (Join-Path $PSScriptRoot 'test_git_object_privacy.py')
    if ($LASTEXITCODE -ne 0) { throw 'Git privacy synthetic tests failed.' }
}
finally {
    $env:BSL_PRIVACY_TEST_POWERSHELL = $previousShell
}
