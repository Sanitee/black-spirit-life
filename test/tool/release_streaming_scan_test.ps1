[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $project 'tool\release\streaming_marker_scan.ps1')
# Frozen whole-file reference from adopted f08b2730. Do not delegate this to the
# production scanner: integration must not make the equivalence test circular.
function Test-ReferenceUnreviewedAbsolutePath {
    param([Parameter(Mandatory = $true)][string]$Text,
          [switch]$AllowReviewedVelopackBuildPaths)
    foreach ($match in [regex]::Matches($Text, $PrivateMachinePathPattern)) {
        if ($AllowReviewedVelopackBuildPaths.IsPresent) {
            $tailLength = [Math]::Min(128, $Text.Length - $match.Index)
            $pathTail = $Text.Substring($match.Index, $tailLength)
            $reviewedVelopackBuildRootPattern = '(?i)^C:' + '\\Users\\runneradmin\\(?:\.cargo|\.rustup)\\'
            if ([regex]::IsMatch($pathTail, $reviewedVelopackBuildRootPattern)) { continue }
        }
        return $true
    }
    return $false
}

function Assert-ReferenceNoTextMarker {
    param([Parameter(Mandatory = $true)][string]$Path,
          [Parameter(Mandatory = $true)][string[]]$Markers,
          [switch]$AllowReviewedVelopackBuildPaths)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $utf8 = [Text.Encoding]::UTF8.GetString($bytes)
    $utf16 = [Text.Encoding]::Unicode.GetString($bytes)
    foreach ($marker in $Markers) {
        if ([string]::IsNullOrWhiteSpace($marker)) { continue }
        if ($utf8.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $utf16.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "Packaged file contains a private-machine marker '$marker': $Path"
        }
    }
    $isPinnedVelopackRuntime = [IO.Path]::GetFileName($Path) -ceq 'velopack_libc.dll' -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash -ceq $VelopackRuntimeSha256
    if (-not $isPinnedVelopackRuntime -and
        ((Test-ReferenceUnreviewedAbsolutePath -Text $utf8 -AllowReviewedVelopackBuildPaths:$AllowReviewedVelopackBuildPaths) -or
         (Test-ReferenceUnreviewedAbsolutePath -Text $utf16 -AllowReviewedVelopackBuildPaths:$AllowReviewedVelopackBuildPaths))) {
        throw "Packaged file contains an absolute user/private workspace path: $Path"
    }
}
$PrivateMachinePathPattern = '(?i)[A-Z]:(?:\\{1,2}|/)(?:Users|Codex)(?:\\{1,2}|/)'
$VelopackRuntimeSha256 = 'C36D8B984639A8AF9D3397088D3FFB8213FE1BD0917F555CF0C6E33F014403EC'
$base = Join-Path ([IO.Path]::GetTempPath()) ('bsl-stream-test-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($base)
$caseFile = Join-Path $base 'fixture.bin'
$script:assertions = 0

function Assert-True([bool]$Condition, [string]$Code) {
    $script:assertions++
    if (-not $Condition) { throw "Streaming marker assertion failed: $Code" }
}

function Compare-Scan {
    param([byte[]]$Bytes, [string[]]$Markers, [int]$Chunk = 31, [bool]$Allow = $false,
          [string]$File = $caseFile, [string]$Expected = '')
    [IO.File]::WriteAllBytes($File, $Bytes)
    $referenceError = ''
    try { Assert-ReferenceNoTextMarker -Path $File -Markers $Markers -AllowReviewedVelopackBuildPaths:$Allow }
    catch { $referenceError = $_.Exception.Message }
    $streamError = ''
    try {
        Assert-NoStreamingTextMarker -Path $File -Markers $Markers -ChunkBytes $Chunk `
            -PrivateMachinePathPattern $PrivateMachinePathPattern `
            -VelopackRuntimeSha256 $VelopackRuntimeSha256 -AllowReviewedVelopackBuildPaths:$Allow
    }
    catch { $streamError = $_.Exception.Message }
    $referenceClass = if (-not $referenceError) { 'pass' } elseif ($referenceError.Contains('private-machine marker')) { 'marker' } elseif ($referenceError.Contains('absolute user/private')) { 'path' } else { 'other' }
    $streamClass = if (-not $streamError) { 'pass' } elseif ($streamError.Contains('private-machine marker')) { 'marker' } elseif ($streamError.Contains('absolute user/private')) { 'path' } else { 'other' }
    Assert-True ($referenceError -ceq $streamError) "reference-equivalence-case$script:assertions-chunk$Chunk-size$($Bytes.Length)-$referenceClass-$streamClass"
    if ($Expected -eq 'pass') { Assert-True ($streamError.Length -eq 0) 'expected-pass' }
    if ($Expected -eq 'fail') { Assert-True ($streamError.Length -gt 0) 'expected-failure' }
}

try {
    $marker = 'synthetic-' + 'private-marker'
    $unicodeMarker = 'marker-' + [char]0xe4 + [char]0x3a3 + [char]::ConvertFromUtf32(0x10400)
    $generic = 'Q:' + '\Users\' + 'SyntheticOnly\file'
    $workspace = 'R:' + '/Codex/' + 'synthetic/file'
    $reviewed = 'C:' + '\Users\runneradmin\' + '.cargo\library'
    $reviewedOther = 'C:' + '\Users\runneradmin\' + '.rustup\tool'
    $markers = @($marker, $unicodeMarker)
    $values = @($marker, $unicodeMarker, $generic, $reviewed, ($reviewed + ' ' + $workspace))
    # All byte offsets modulo each tested chunk size, for both reference decoders.
    foreach ($chunk in @(1, 2, 3, 7, 31, 64)) {
        foreach ($encoding in @([Text.Encoding]::UTF8, [Text.Encoding]::Unicode)) {
            foreach ($value in $values) {
                $encoded = $encoding.GetBytes($value)
                for ($offset = 0; $offset -lt $chunk; $offset++) {
                    $prefix = [byte[]]::new($offset)
                    $bytes = [byte[]]($prefix + $encoded + [byte[]]@(0, 0, 255))
                    Compare-Scan -Bytes $bytes -Markers $markers -Chunk $chunk -Allow $true
                }
            }
        }
    }
    # Marker priority remains array order, not earliest stream position/encoding.
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($unicodeMarker + ('x' * 200) + $marker)) `
        -Markers $markers -Chunk 7 -Expected fail
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($generic + ('x' * 200) + $marker)) `
        -Markers $markers -Chunk 7 -Expected fail
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($reviewed)) -Markers $markers -Allow $true -Expected pass
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($reviewedOther)) -Markers $markers -Allow $true -Expected pass
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($reviewed)) -Markers $markers -Expected fail
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($reviewed)) -Markers @('runneradmin') -Allow $true -Expected fail
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes(('D:' + $reviewed.Substring(2)))) -Markers $markers -Allow $true -Expected fail
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($reviewed.Replace('.cargo', '.cargo2'))) -Markers $markers -Allow $true -Expected fail
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($generic.Replace('\', '\\'))) -Markers $markers -Expected fail
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($generic.Replace('\', '/'))) -Markers $markers -Expected fail
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($generic.Replace('\', '\\\'))) -Markers $markers -Expected pass
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($marker.ToUpperInvariant())) -Markers $markers -Expected fail
    Compare-Scan -Bytes ([byte[]]@()) -Markers $markers -Expected fail
    Compare-Scan -Bytes ([byte[]]@(0, 0, 0, 255, 192, 128, 226, 130)) -Markers @('unused') -Chunk 1 -Expected pass
    Compare-Scan -Bytes ([byte[]]@(255, 192, 128, 226, 130)) -Markers @([string][char]0xfffd) -Chunk 1 -Expected fail
    # BOMs are decoded as characters, not stripped; big endian has no special mode.
    foreach ($encoding in @([Text.Encoding]::UTF8, [Text.Encoding]::Unicode, [Text.Encoding]::BigEndianUnicode)) {
        Compare-Scan -Bytes ([byte[]]($encoding.GetPreamble() + $encoding.GetBytes($marker))) -Markers $markers -Chunk 3
        Compare-Scan -Bytes ([byte[]](@(0) + $encoding.GetBytes($marker))) -Markers $markers -Chunk 3
    }
    foreach ($tail in @([byte[]]@(0xd8), [byte[]]@(0, 0xd8), [byte[]]@(0, 0xdc), [byte[]]@(0xf0, 0x90, 0x80))) {
        Compare-Scan -Bytes $tail -Markers @([string][char]0xfffd) -Chunk 1
    }
    # Markers longer than a chunk and generic matches within the final lookahead.
    $longMarker = ('a' * 500) + 'z'
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes('prefix' + $longMarker)) -Markers @($longMarker) -Chunk 1 -Expected fail
    foreach ($tailCount in @(0, 1, 126, 127, 128, 129, 257)) {
        Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($reviewed + ('x' * $tailCount))) -Markers $markers -Chunk 7 -Allow $true -Expected pass
        Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($generic + ('x' * $tailCount))) -Markers $markers -Chunk 7 -Allow $true -Expected fail
    }
    # Candidate-colon filtering must leave the Regex verdict untouched, including
    # non-ASCII case mappings and a full 11-character double-slash match.
    foreach ($drive in @([char]0, [char]58, [char]64, [char]65, [char]90, [char]91,
                         [char]96, [char]97, [char]122, [char]123,
                         [char]0x130, [char]0x131, [char]0x17f, [char]0x212a)) {
        foreach ($slashes in @('/', '\', '\\')) {
            $candidate = [string]$drive + ':' + $slashes + 'Users' + $slashes + 'fixture'
            foreach ($encoding in @([Text.Encoding]::UTF8, [Text.Encoding]::Unicode)) {
                Compare-Scan -Bytes ($encoding.GetBytes('::/' + $candidate)) -Markers $markers -Chunk 3
            }
        }
    }
    # Culture-sensitive Regex and culture-insensitive ordinal markers match reference.
    $oldCulture = [Globalization.CultureInfo]::CurrentCulture
    try {
        foreach ($cultureName in @('en-US', 'tr-TR', 'de-DE')) {
            [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo($cultureName)
            Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($reviewed.ToUpperInvariant())) -Markers $markers -Allow $true
            Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($unicodeMarker.ToLowerInvariant())) -Markers $markers
        }
    }
    finally { [Globalization.CultureInfo]::CurrentCulture = $oldCulture }
    # Hash-pinned exception applies only to exact-case runtime basename; markers win.
    $runtime = Join-Path $base 'velopack_libc.dll'
    [IO.File]::WriteAllBytes($runtime, [Text.Encoding]::UTF8.GetBytes($generic))
    $oldPin = $VelopackRuntimeSha256
    $VelopackRuntimeSha256 = (Get-FileHash -LiteralPath $runtime -Algorithm SHA256).Hash
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($generic)) -Markers $markers -File $runtime -Expected pass
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($generic)) -Markers @('SyntheticOnly') -File $runtime -Expected fail
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($generic)) -Markers $markers -File (Join-Path $base 'VELOPACK_LIBC.DLL') -Expected fail
    $VelopackRuntimeSha256 = $VelopackRuntimeSha256.ToLowerInvariant()
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($generic)) -Markers $markers -File $runtime -Expected fail
    $VelopackRuntimeSha256 = $oldPin
    Compare-Scan -Bytes ([Text.Encoding]::UTF8.GetBytes($generic)) -Markers $markers -File $runtime -Expected fail
    # Deterministic malformed-input corpus compares actual decoder fallbacks.
    $random = [Random]::new(80231)
    foreach ($size in @(1, 2, 3, 15, 63, 64, 65, 127, 255, 4097)) {
        for ($iteration = 0; $iteration -lt 8; $iteration++) {
            $bytes = [byte[]]::new($size)
            $random.NextBytes($bytes)
            Compare-Scan -Bytes $bytes -Markers @($marker, [string][char]0xfffd, 'A') -Chunk (1 + $iteration)
        }
    }
    # Path safety is stricter than the old reader: never follow a junction.
    $target = Join-Path $base 'target'
    $null = [IO.Directory]::CreateDirectory($target)
    [IO.File]::WriteAllBytes((Join-Path $target 'safe.bin'), [byte[]]@(1, 2, 3))
    $junction = Join-Path $base 'junction'
    $null = New-Item -ItemType Junction -Path $junction -Target $target
    $failed = $false
    try {
        Assert-NoStreamingTextMarker -Path (Join-Path $junction 'safe.bin') -Markers $markers `
            -PrivateMachinePathPattern $PrivateMachinePathPattern -VelopackRuntimeSha256 $VelopackRuntimeSha256
    }
    catch { $failed = $true }
    Assert-True $failed 'junction-rejected'
    # Remove the junction itself, never recurse through its target.
    [IO.Directory]::Delete($junction)
    $failed = $false
    try {
        Assert-NoStreamingTextMarker -Path $caseFile -Markers $markers `
            -PrivateMachinePathPattern '(?i)different-policy' -VelopackRuntimeSha256 $VelopackRuntimeSha256
    }
    catch { $failed = $true }
    Assert-True $failed 'changed-policy-rejected'
    Write-Output "Streaming scan tests passed: $script:assertions assertions."
}
finally {
    $resolvedBase = [IO.Path]::GetFullPath($base)
    $temporaryPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedBase.StartsWith($temporaryPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolvedBase) -notlike 'bsl-stream-test-*') {
        throw 'Refusing to remove an unexpected synthetic test root.'
    }
    $junctionPath = Join-Path $resolvedBase 'junction'
    if ([IO.Directory]::Exists($junctionPath)) { [IO.Directory]::Delete($junctionPath) }
    Remove-Item -LiteralPath $resolvedBase -Recurse -Force
}
