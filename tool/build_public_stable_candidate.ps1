[CmdletBinding()]
param(
    [string]$FlutterPath,
    [string]$CMakePath,

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
