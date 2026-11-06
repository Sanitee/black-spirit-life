[CmdletBinding()]
param([string]$ReceiptPath, [string]$ApprovedReceiptSha256, [string]$DisposableBase)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../tool/release/isolated_known_folders.ps1')
$checks = 0
function Expect-Rejected([scriptblock]$Action, [string]$Pattern) {
    $caught = $null
    try { & $Action } catch { $caught = $_.Exception.Message }
    if (-not $caught -or $caught -notmatch $Pattern) { throw "Expected rejection /$Pattern/, got: $caught" }
    $script:checks++
}
Expect-Rejected { Initialize-IsolatedKnownFolders '' '' } 'approved isolated'
Expect-Rejected { Assert-IsolatedOrdinaryPath 'relative/path' } 'absolute'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('bsl-known-folder-contract-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temp
$fake = Join-Path $temp 'wrong-account.json'
$fakeReceipt = @{ schemaVersion = 1; administrator = $false; sid = 'S-1-0-0'; profile = (Join-Path $temp 'BSLRelease_Fixture') }
[IO.File]::WriteAllText($fake, ($fakeReceipt | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Expect-Rejected { Initialize-IsolatedKnownFolders $fake ('0' * 64) } 'hash differs'
$fakeHash = (Get-FileHash -LiteralPath $fake -Algorithm SHA256).Hash
Expect-Rejected { Initialize-IsolatedKnownFolders $fake $fakeHash } 'approved standard disposable'
[IO.File]::WriteAllText($fake, ($fakeReceipt | ConvertTo-Json), [Text.UTF8Encoding]::new($true))
$fakeHash = (Get-FileHash -LiteralPath $fake -Algorithm SHA256).Hash
Expect-Rejected { Initialize-IsolatedKnownFolders $fake $fakeHash } 'approved standard disposable'
if ($ReceiptPath) {
    $context = Initialize-IsolatedKnownFolders $ReceiptPath $ApprovedReceiptSha256
    if (-not $DisposableBase -or (Test-Path -LiteralPath $DisposableBase)) { throw 'Integration needs a new dedicated root.' }
    try {
        $outside = Join-Path (Split-Path -Parent $DisposableBase) 'outside-refused'
        Expect-Rejected { Set-IsolatedKnownFolders $context $DisposableBase $outside $outside $outside } 'escaped'
        foreach ($phase in @('first', 'second')) {
            $base = Join-Path $DisposableBase $phase
            Set-IsolatedKnownFolders $context $DisposableBase (Join-Path $base 'Documents') (Join-Path $base 'Roaming') (Join-Path $base 'Local')
            foreach ($key in @('documents', 'roaming')) {
                $observed = [BslReleaseKnownFolders]::Get($context.Ids[$key])
                if (-not $observed.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Phase leaked across known folders.' }
                $checks++
            }
            if ([BslReleaseKnownFolders]::Get($context.Ids.local) -ine $context.Original.local) { throw 'Native LocalAppData must remain in the test account.' }
            $checks++
        }
    } finally { Restore-IsolatedKnownFolders $context }
    foreach ($key in @('documents', 'roaming', 'local')) {
        if ([BslReleaseKnownFolders]::Get($context.Ids[$key]) -ine $context.Original[$key]) { throw 'Original known folders not restored.' }
        $checks++
    }
}
Write-Output "PASS isolated known-folder checks=$checks integration=$([bool]$ReceiptPath)"
