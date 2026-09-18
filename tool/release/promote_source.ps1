[CmdletBinding()]
param(
    [ValidateSet('Inventory', 'Promote')][string]$Mode = 'Inventory',
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [Parameter(Mandatory = $true)][string]$OverlayRoot,
    [Parameter(Mandatory = $true)][string]$PlanPath,
    [Parameter(Mandatory = $true)][string]$ExpectedPlanSha256,
    [string]$ExpectedSourceFingerprint,
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'source_promotion.ps1')
$inputs = @{
    SourceRoot = $SourceRoot; OverlayRoot = $OverlayRoot
    PlanPath = $PlanPath; ExpectedPlanSha256 = $ExpectedPlanSha256
}
if ($Mode -eq 'Inventory') {
    if ($OutputRoot -or $ExpectedSourceFingerprint) { throw 'Inventory mode writes no output; omit promotion-only arguments.' }
    Get-ReleasePromotionInventory @inputs | ConvertTo-Json -Depth 24
}
else {
    if (-not $OutputRoot -or -not $ExpectedSourceFingerprint) { throw 'Promote mode requires OutputRoot and ExpectedSourceFingerprint.' }
    Invoke-ReleaseSourcePromotion @inputs -OutputRoot $OutputRoot -ExpectedSourceFingerprint $ExpectedSourceFingerprint |
        ConvertTo-Json -Depth 24
}
