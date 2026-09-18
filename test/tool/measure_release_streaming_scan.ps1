[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('Reference', 'Streaming')][string]$Mode,
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9-]+$')][string]$Role,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedSha256,
    [Parameter(Mandatory = $true)][string[]]$Markers,
    [switch]$AllowReviewedVelopackBuildPaths,
    [ValidateRange(1, 16777216)][int]$ChunkBytes = 1048576
)

# Run each mode in its own fresh process, serially. Read-only retained artifacts.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$startup = [Diagnostics.Stopwatch]::StartNew()
. (Join-Path $project 'tool\release\streaming_marker_scan.ps1')
$referenceFile = Join-Path $PSScriptRoot 'release_streaming_scan_test.ps1'
$tokens = $null
$errors = $null
$referenceAst = [Management.Automation.Language.Parser]::ParseFile($referenceFile, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) { throw 'Reference scanner parse failed.' }
foreach ($name in @('Test-ReferenceUnreviewedAbsolutePath', 'Assert-ReferenceNoTextMarker')) {
    $definitions = @($referenceAst.FindAll({ param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name
    }, $true))
    if ($definitions.Count -ne 1) { throw 'Reference scanner definition is not unique.' }
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}
$PrivateMachinePathPattern = '(?i)[A-Z]:(?:\\{1,2}|/)(?:Users|Codex)(?:\\{1,2}|/)'
$VelopackRuntimeSha256 = 'C36D8B984639A8AF9D3397088D3FFB8213FE1BD0917F555CF0C6E33F014403EC'
$actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
if ($actualHash -cne $ExpectedSha256.ToUpperInvariant()) { throw 'Benchmark input hash does not match approved bytes.' }
$length = (Get-Item -LiteralPath $Path).Length
$startup.Stop()
[GC]::Collect()
[GC]::WaitForPendingFinalizers()
[GC]::Collect()
$process = [Diagnostics.Process]::GetCurrentProcess()
$process.Refresh()
$initialWorkingSet = $process.WorkingSet64
$initialPrivate = $process.PrivateMemorySize64
$initialManaged = [GC]::GetTotalMemory($false)
$timer = [Diagnostics.Stopwatch]::StartNew()
$passed = $false
try {
    if ($Mode -eq 'Reference') {
        Assert-ReferenceNoTextMarker -Path $Path -Markers $Markers -AllowReviewedVelopackBuildPaths:$AllowReviewedVelopackBuildPaths
    }
    else {
        Assert-NoStreamingTextMarker -Path $Path -Markers $Markers -ChunkBytes $ChunkBytes `
            -PrivateMachinePathPattern $PrivateMachinePathPattern -VelopackRuntimeSha256 $VelopackRuntimeSha256 `
            -AllowReviewedVelopackBuildPaths:$AllowReviewedVelopackBuildPaths
    }
    $passed = $true
}
catch {
    # Original errors include marker values/paths; benchmark records never do.
    throw 'Benchmark scanner rejected the retained input; equivalence needs investigation.'
}
finally { $timer.Stop() }
$process.Refresh()
$result = [ordered]@{
    schemaVersion = 1; role = $Role; mode = $Mode; passed = $passed
    powershell = $PSVersionTable.PSVersion.ToString(); runtime = [Environment]::Version.ToString()
    inputSha256 = $actualHash; bytes = $length; chunkBytes = $ChunkBytes
    scanMilliseconds = $timer.Elapsed.TotalMilliseconds
    initializationAndInputHashMilliseconds = $startup.Elapsed.TotalMilliseconds
    initialWorkingSetBytes = $initialWorkingSet; initialPrivateBytes = $initialPrivate
    initialManagedBytes = $initialManaged; managedBytesAfterScan = [GC]::GetTotalMemory($false)
    peakWorkingSetBytes = $process.PeakWorkingSet64; privateBytesAfterScan = $process.PrivateMemorySize64
    memoryMeasurement = 'fresh-process-os-peak-working-set-including-runtime-and-initialization'
}
# A separate final read proves the retained file was not modified by benchmarking.
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash -cne $actualHash) {
    throw 'Benchmark input changed during the measurement.'
}
$result | ConvertTo-Json -Depth 4 -Compress
