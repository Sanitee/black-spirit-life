[CmdletBinding()]
param(
    [string]$FlutterPath,
    [string]$CMakePath,
    [string]$ReleaseInputCacheRoot,
    [string]$PreviousFeedPath,
    [string]$PreviousPackagePath,
    [switch]$OfflinePinnedInputs,
    [ValidateRange(0, [long]::MaxValue)][long]$MinimumFreeBytes = 0,

    [Parameter(Mandatory = $true)]
    [string]$PublicGitHubRepository,

    [Parameter(Mandatory = $true)]
    [switch]$ConfirmPublicCandidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfirmPublicCandidateOnly.IsPresent) {
    throw 'Supply -ConfirmPublicCandidateOnly. This script prepares artifacts but never publishes them.'
}

$arguments = @{
    ConfirmPublicCandidateOnly = $true
    PublicGitHubRepository = $PublicGitHubRepository
    OfflinePinnedInputs = $OfflinePinnedInputs
    MinimumFreeBytes = $MinimumFreeBytes
}
foreach ($name in @('ReleaseInputCacheRoot', 'PreviousFeedPath', 'PreviousPackagePath')) {
    $value = Get-Variable -Name $name -ValueOnly
    if (-not [string]::IsNullOrWhiteSpace($value)) { $arguments[$name] = $value }
}
if (-not [string]::IsNullOrWhiteSpace($FlutterPath)) {
    $arguments.FlutterPath = $FlutterPath
}
if (-not [string]::IsNullOrWhiteSpace($CMakePath)) {
    $arguments.CMakePath = $CMakePath
}

& (Join-Path $PSScriptRoot 'build_stable_release_candidate.ps1') @arguments
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
