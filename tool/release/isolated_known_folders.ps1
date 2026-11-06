Set-StrictMode -Version Latest

# This guard is deliberately independent of app environment overrides. Windows
# native Documents resolution must see the disposable phase, not the operator.
# Native LocalAppData remains in the approved test account (Windows prohibits
# redirecting it); the existing per-process LOCALAPPDATA cache tests stay separate.
function Assert-IsolatedOrdinaryPath([string]$Path) {
    if (-not [IO.Path]::IsPathRooted($Path)) { throw 'Isolation paths must be absolute.' }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Isolation paths must not traverse a reparse point.'
            }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
    return $full
}

function Initialize-IsolatedKnownFolders([string]$ReceiptPath, [string]$ApprovedSha256) {
    if ($ApprovedSha256 -cnotmatch '^[A-Fa-f0-9]{64}$' -or [string]::IsNullOrWhiteSpace($ReceiptPath)) {
        throw 'Shared-profile lifecycle requires an approved isolated Windows account receipt.'
    }
    $ordinary = Assert-IsolatedOrdinaryPath $ReceiptPath
    $bytes = [IO.File]::ReadAllBytes($ordinary)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $actual = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
    if ($actual -cne $ApprovedSha256.ToUpperInvariant()) { throw 'Isolated account receipt hash differs.' }
    $receipt = [Text.UTF8Encoding]::new($false, $true).GetString($bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($receipt.schemaVersion -ne 1 -or $receipt.administrator -isnot [bool] -or $receipt.administrator -or
        $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
        $identity.User.Value -cne [string]$receipt.sid -or
        $identity.Name -notmatch '\\BSLRelease_[A-Za-z0-9_-]+$' -or
        [IO.Path]::GetFileName([string]$receipt.profile) -notmatch '^BSLRelease_[A-Za-z0-9_-]+$') {
        throw 'Lifecycle must run as the approved standard disposable Windows account, never the operator.'
    }
    if (-not ('BslReleaseKnownFolders' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BslReleaseKnownFolders {
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
    static extern int SHGetKnownFolderPath(ref Guid id, uint flags, IntPtr token, out IntPtr path);
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
    static extern int SHSetKnownFolderPath(ref Guid id, uint flags, IntPtr token, string path);
    public static string Get(string key) {
        Guid id = new Guid(key); IntPtr value;
        Marshal.ThrowExceptionForHR(SHGetKnownFolderPath(ref id, 0, IntPtr.Zero, out value));
        try { return Marshal.PtrToStringUni(value); } finally { Marshal.FreeCoTaskMem(value); }
    }
    public static void Set(string key, string path) {
        Guid id = new Guid(key);
        Marshal.ThrowExceptionForHR(SHSetKnownFolderPath(ref id, 0, IntPtr.Zero, path));
    }
}
'@
    }
    $ids = [ordered]@{
        profile = '5E6C858F-0E22-4760-9AFE-EA3317B67173'
        documents = 'FDD39AD0-238F-46AF-ADB4-6C85480369C7'
        roaming = '3EB685DB-65F9-4CF6-A03A-E3EF65729F3D'
        local = 'F1B32785-6FBA-4FCF-9D55-7B8E7F157091'
    }
    $original = [ordered]@{}
    $profile = Assert-IsolatedOrdinaryPath ([string]$receipt.profile)
    foreach ($key in $ids.Keys) {
        $observed = Assert-IsolatedOrdinaryPath ([BslReleaseKnownFolders]::Get($ids[$key]))
        $expected = Assert-IsolatedOrdinaryPath ([string]$receipt.$key)
        if (-not $observed.Equals($expected, [StringComparison]::OrdinalIgnoreCase) -or
            ($key -ne 'profile' -and -not $observed.StartsWith($profile + '\', [StringComparison]::OrdinalIgnoreCase))) {
            throw "Native $key does not match the approved isolated account."
        }
        $original[$key] = $observed
    }
    return [pscustomobject]@{ Sid = $identity.User.Value; ReceiptSha256 = $actual; Ids = $ids; Original = $original }
}

function Set-IsolatedKnownFolders($Context, [string]$DisposableBase, [string]$Documents, [string]$Roaming, [string]$Local) {
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne $Context.Sid) { throw 'Isolation identity changed.' }
    $root = Assert-IsolatedOrdinaryPath $DisposableBase
    if ([IO.Path]::GetFileName($root) -cnotmatch '^bsl-lifecycle-[A-Za-z0-9-]+$') { throw 'Invalid isolated lifecycle root.' }
    $paths = [ordered]@{ documents = $Documents; roaming = $Roaming }
    $localTarget = Assert-IsolatedOrdinaryPath $Local
    if (-not $localTarget.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Local cache target escaped the isolated lifecycle root.' }
    foreach ($key in $paths.Keys) {
        $path = Assert-IsolatedOrdinaryPath $paths[$key]
        if (-not $path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Known-folder target escaped the isolated lifecycle root.' }
    }
    foreach ($key in $paths.Keys) {
        $path = Assert-IsolatedOrdinaryPath $paths[$key]
        $null = New-Item -ItemType Directory -Path $path -Force
        try { [BslReleaseKnownFolders]::Set($Context.Ids[$key], $path) }
        catch { throw "Native $key redirection: $($_.Exception.Message)" }
        if (-not ([BslReleaseKnownFolders]::Get($Context.Ids[$key])).Equals($path, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Native $key redirection failed."
        }
    }
}

function Restore-IsolatedKnownFolders($Context) {
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne $Context.Sid) { throw 'Isolation identity changed before restoration.' }
    $errors = [Collections.Generic.List[string]]::new()
    foreach ($key in @('documents', 'roaming')) {
        try {
            [BslReleaseKnownFolders]::Set($Context.Ids[$key], $Context.Original[$key])
            if (-not ([BslReleaseKnownFolders]::Get($Context.Ids[$key])).Equals($Context.Original[$key], [StringComparison]::OrdinalIgnoreCase)) {
                throw "Native $key restoration failed."
            }
        } catch { $errors.Add("$key restoration: $($_.Exception.Message)") }
    }
    if ($errors.Count -gt 0) { throw ($errors -join '; ') }
}
