[CmdletBinding()]
param(
    [string]$DotnetPath,
    [string]$OutputPath,
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$projectPath = Join-Path $projectRoot 'BlackSpiritStorageOcr.csproj'
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $projectRoot '..\..\..')).Path

function Resolve-DotnetExecutable {
    param([string]$ExplicitPath)

    $candidate = $ExplicitPath
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = $env:DOTNET_EXE
    }
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Container)) {
        $candidate = Join-Path $candidate 'dotnet.exe'
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $workspaceRoot = Split-Path -Path $repositoryRoot -Parent
        $workspaceSdkRoot = Join-Path $workspaceRoot 'tmp'
        if (Test-Path -LiteralPath $workspaceSdkRoot -PathType Container) {
            $workspaceSdk = Get-ChildItem -LiteralPath $workspaceSdkRoot -Directory -Filter 'dotnet-sdk-*' -ErrorAction SilentlyContinue |
                Sort-Object -Property Name -Descending |
                ForEach-Object { Join-Path $_.FullName 'dotnet.exe' } |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
                Select-Object -First 1
            if (-not [string]::IsNullOrWhiteSpace($workspaceSdk)) {
                $candidate = $workspaceSdk
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $command = Get-Command 'dotnet.exe' -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $candidate = $command.Source
        }
    }
    if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw 'A .NET SDK executable was not found. Pass -DotnetPath or set DOTNET_EXE.'
    }
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Get-Sha256Hex {
    param([string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '')
    }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

$dotnetExecutable = Resolve-DotnetExecutable -ExplicitPath $DotnetPath
$sdkVersion = (& $dotnetExecutable --version).Trim()
if ($LASTEXITCODE -ne 0 -or $sdkVersion -notmatch '^(?<major>\d+)\.') {
    throw 'The selected dotnet executable did not report a valid SDK version.'
}
if ([int]$Matches.major -lt 8) {
    throw "The OCR helper requires .NET SDK 8 or newer; found $sdkVersion."
}

& (Join-Path $projectRoot 'verify-assets.ps1')
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repositoryRoot 'build\windows\x64\storage_ocr'
}
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
$defaultOutput = [IO.Path]::GetFullPath((Join-Path $repositoryRoot 'build\windows\x64\storage_ocr'))
if (Test-Path -LiteralPath $resolvedOutput) {
    $existingEntries = @(Get-ChildItem -LiteralPath $resolvedOutput -Force)
    if ($existingEntries.Count -gt 0) {
        if (-not [string]::Equals($resolvedOutput, $defaultOutput, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'A custom OCR publish directory must be empty before publishing.'
        }
        Remove-Item -LiteralPath $resolvedOutput -Recurse -Force
    }
}
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null

$publishArguments = @(
    'publish', $projectPath,
    '--configuration', $Configuration,
    '--runtime', 'win-x64',
    '--self-contained', 'true',
    '--nologo',
    '-m:4',
    '-p:PublishSingleFile=false',
    '-p:PublishReadyToRun=false',
    '-p:PublishTrimmed=false',
    '-p:RestoreDisableParallel=true',
    '--output', $resolvedOutput
)
if ($Configuration -ceq 'Release') {
    $publishArguments += @(
        '-p:DebugSymbols=false',
        '-p:DebugType=None'
    )
}

& $dotnetExecutable @publishArguments
if ($LASTEXITCODE -ne 0) {
    throw "OCR helper publish failed with exit code $LASTEXITCODE."
}

$debugSymbols = @(Get-ChildItem -LiteralPath $resolvedOutput -Recurse -File -Filter '*.pdb')
if ($Configuration -ceq 'Release' -and $debugSymbols.Count -ne 0) {
    throw "Release OCR helper publish contains debug symbols: $($debugSymbols[0].FullName)"
}

$requiredRuntimeFiles = @(
    'BlackSpiritStorageOcr.exe',
    'BlackSpiritStorageOcr.deps.json',
    'BlackSpiritStorageOcr.runtimeconfig.json',
    'Microsoft.ML.OnnxRuntime.dll',
    'onnxruntime.dll',
    'onnxruntime_providers_shared.dll'
)
foreach ($fileName in $requiredRuntimeFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $resolvedOutput $fileName) -PathType Leaf)) {
        throw "OCR helper publish is missing required runtime file: $fileName"
    }
}

$expectedRuntimeHashes = @{
    'Microsoft.ML.OnnxRuntime.dll' = '4E55E8695BB4C858B969580746F23F1C058D340D48DB8B5B65072155B3C7F032'
    'onnxruntime.dll' = '69D8E6D3879A3B4001CDC74C8ED9CCC7E7F799A5B847059738323404519EC471'
    'onnxruntime_providers_shared.dll' = '87F6878CDC1F80B3A9AFA5B0C84663315030B4957F5BBB6B66470557CB2F48D8'
}
foreach ($entry in $expectedRuntimeHashes.GetEnumerator()) {
    $actualHash = Get-Sha256Hex -Path (Join-Path $resolvedOutput $entry.Key)
    if ($actualHash -ne $entry.Value) {
        throw "OCR helper runtime hash mismatch for $($entry.Key)."
    }
}

Write-Host "Published BlackSpiritStorageOcr to $resolvedOutput"
