[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$FlutterPath,
    [Parameter(Mandatory = $true)][string]$ReceiptPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
. (Join-Path $PSScriptRoot 'prepared_dependencies.ps1')
$destination = [IO.Path]::GetFullPath($ReceiptPath)
if (Test-Path -LiteralPath $destination) { throw 'Dependency preparation requires a new receipt file.' }
if (-not (Test-Path -LiteralPath (Split-Path -Parent $destination) -PathType Container)) { throw 'Dependency receipt parent must already exist.' }
$before = @('pubspec.yaml', 'pubspec.lock', 'pubspec_overrides.yaml') | ForEach-Object {
    $file = Join-Path $PackageRoot $_
    if (Test-Path -LiteralPath $file) { Get-ReleaseDependencyFilePin $file $_ }
    elseif ($_ -cne 'pubspec_overrides.yaml') { throw "Dependency preparation requires $_." }
}
$null = Get-ReleaseDependencyFilePin $FlutterPath 'Flutter launcher'
Push-Location -LiteralPath $PackageRoot
try {
    $global:LASTEXITCODE = $null
    & $FlutterPath pub get --enforce-lockfile | Out-Host
    if ($null -eq $global:LASTEXITCODE -or $global:LASTEXITCODE -ne 0) { throw 'Lock-enforced dependency preparation failed; no receipt was written.' }
}
finally { Pop-Location }
$snapshot = Get-ReleaseDependencySnapshot $PackageRoot $FlutterPath
$after = @($snapshot.files | Where-Object { $_.role -in @('pubspec.yaml', 'pubspec.lock', 'pubspec_overrides.yaml') })
if (($before | ConvertTo-Json -Depth 5 -Compress) -cne ($after | ConvertTo-Json -Depth 5 -Compress)) { throw 'Dependency preparation changed a source pubspec/lock/override; review it before freezing. No receipt was written.' }
$receipt = [ordered]@{ schemaVersion = 1; resolutionSucceeded = $true; command = 'flutter pub get --enforce-lockfile'; snapshot = $snapshot; isReleaseVerification = $false }
$partial = $destination + '.partial-' + [Guid]::NewGuid().ToString('N')
[IO.File]::WriteAllText($partial, ($receipt | ConvertTo-Json -Depth 8) + "`n", [Text.UTF8Encoding]::new($false))
[IO.File]::Move($partial, $destination)
[pscustomobject]@{ receiptPath = $destination; sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash; status = 'prepared-not-release-verified' }
