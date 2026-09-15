[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $OutputPath,

    [ValidateSet('Release', 'Debug')]
    [string] $Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-FullDirectoryPath([string] $Path) {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootPath = [System.IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Equals($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $rootPath
    }
    return $fullPath.TrimEnd([char[]]@('\', '/'))
}

function Assert-ContainedPath(
    [string] $ParentPath,
    [string] $CandidatePath,
    [string] $Purpose
) {
    $parent = Get-FullDirectoryPath $ParentPath
    $candidate = Get-FullDirectoryPath $CandidatePath
    $prefix = $parent.TrimEnd([char[]]@('\', '/')) +
        [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to $Purpose outside $parent`: $candidate"
    }
}

function Invoke-Checked([string] $Description, [scriptblock] $Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

function Get-FileSha256([string] $Path) {
    $stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
        $stream.Dispose()
    }
}

function ConvertTo-JsonString([AllowNull()] [string] $Value) {
    if ($null -eq $Value) {
        return 'null'
    }

    $builder = [System.Text.StringBuilder]::new()
    [void] $builder.Append('"')
    foreach ($character in $Value.ToCharArray()) {
        switch ([int] $character) {
            8 { [void] $builder.Append('\b'); break }
            9 { [void] $builder.Append('\t'); break }
            10 { [void] $builder.Append('\n'); break }
            12 { [void] $builder.Append('\f'); break }
            13 { [void] $builder.Append('\r'); break }
            34 { [void] $builder.Append('\"'); break }
            92 { [void] $builder.Append('\\'); break }
            default {
                if ([int] $character -lt 32) {
                    [void] $builder.Append(('\u{0:x4}' -f [int] $character))
                }
                else {
                    [void] $builder.Append($character)
                }
            }
        }
    }
    [void] $builder.Append('"')
    return $builder.ToString()
}

function Write-PayloadManifest(
    [string] $Path,
    [string] $Configuration,
    [int] $SourceFileCount,
    [string] $SourceFingerprint,
    [string[]] $ExtensionFiles,
    [object[]] $PayloadEntries
) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('{')
    $lines.Add('  "schemaVersion": 1,')
    $lines.Add('  "source": {')
    $lines.Add(('    "path": {0},' -f (ConvertTo-JsonString 'windows/session_import')))
    $lines.Add(('    "fileCount": {0},' -f $SourceFileCount))
    $lines.Add(('    "fingerprintSha256": {0}' -f (ConvertTo-JsonString $SourceFingerprint)))
    $lines.Add('  },')
    $lines.Add('  "build": {')
    $lines.Add(('    "configuration": {0},' -f (ConvertTo-JsonString $Configuration)))
    $lines.Add(('    "runtimeIdentifier": {0},' -f (ConvertTo-JsonString 'win-x64')))
    $lines.Add('    "frameworkDependent": true,')
    $lines.Add('    "productionExtensionFiles": [')
    for ($index = 0; $index -lt $ExtensionFiles.Count; $index++) {
        $suffix = if ($index -lt $ExtensionFiles.Count - 1) { ',' } else { '' }
        $lines.Add(('      {0}{1}' -f (ConvertTo-JsonString $ExtensionFiles[$index]), $suffix))
    }
    $lines.Add('    ]')
    $lines.Add('  },')
    $lines.Add('  "payload": {')
    $lines.Add(('    "fileCount": {0},' -f $PayloadEntries.Count))
    $lines.Add('    "files": [')
    for ($index = 0; $index -lt $PayloadEntries.Count; $index++) {
        $entry = $PayloadEntries[$index]
        $suffix = if ($index -lt $PayloadEntries.Count - 1) { ',' } else { '' }
        $lines.Add('      {')
        $lines.Add(('        "path": {0},' -f (ConvertTo-JsonString $entry.path)))
        $lines.Add(('        "bytes": {0},' -f $entry.bytes))
        $lines.Add(('        "sha256": {0}' -f (ConvertTo-JsonString $entry.sha256)))
        $lines.Add("      }$suffix")
    }
    $lines.Add('    ]')
    $lines.Add('  }')
    $lines.Add('}')

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, ($lines -join "`n") + "`n", $encoding)
}

function Get-InventoryFingerprint([System.IO.FileInfo[]] $Files, [string] $RootPath) {
    $root = Get-FullDirectoryPath $RootPath
    $records = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $Files) {
        $relativePath = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
        $fileHash = Get-FileSha256 $file.FullName
        $records.Add("$relativePath`t$($file.Length)`t$fileHash`n")
    }
    $records.Sort([System.StringComparer]::Ordinal)

    $builder = [System.Text.StringBuilder]::new()
    foreach ($record in $records) {
        [void] $builder.Append($record)
    }

    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
        return ([System.BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }
}

$projectRoot = Get-FullDirectoryPath (Split-Path -Parent $MyInvocation.MyCommand.Path)
$resolvedOutput = Get-FullDirectoryPath $OutputPath
$volumeRoot = Get-FullDirectoryPath ([System.IO.Path]::GetPathRoot($resolvedOutput))
if ($resolvedOutput.Equals($volumeRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to publish over a volume root: $resolvedOutput"
}

$sourcePrefix = $projectRoot + [System.IO.Path]::DirectorySeparatorChar
if ($resolvedOutput.Equals($projectRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
    $resolvedOutput.StartsWith($sourcePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must be outside the Session Import source tree: $resolvedOutput"
}

$outputParent = Get-FullDirectoryPath (Split-Path -Parent $resolvedOutput)
$outputLeaf = Split-Path -Leaf $resolvedOutput
if ([string]::IsNullOrWhiteSpace($outputLeaf)) {
    throw "OutputPath must name a payload directory: $resolvedOutput"
}

[System.IO.Directory]::CreateDirectory($outputParent) | Out-Null
$uniqueSuffix = "$PID-$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"
$stagingOutput = Join-Path $outputParent ".si-s-$uniqueSuffix"
$previousOutput = Join-Path $outputParent ".si-p-$uniqueSuffix"
$intermediateRoot = Join-Path $outputParent ".si-i-$uniqueSuffix"
Assert-ContainedPath $outputParent $stagingOutput 'create a staging payload'
Assert-ContainedPath $outputParent $previousOutput 'create a rollback payload'
Assert-ContainedPath $outputParent $intermediateRoot 'create build intermediates'
[System.IO.Directory]::CreateDirectory($stagingOutput) | Out-Null

$generatedHeaders = Join-Path $intermediateRoot 'cppwinrt'
$nativeOutputDirectory = Join-Path $intermediateRoot 'native'
$nativeBinary = Join-Path $nativeOutputDirectory 'SummaryOcrNative.exe'
$nativeObject = Join-Path $nativeOutputDirectory 'SummaryOcrNative.obj'
$dotnetArtifacts = Join-Path $intermediateRoot 'dotnet'
$hostOutput = Join-Path $stagingOutput 'browser_helper'
$extensionOutput = Join-Path $stagingOutput 'browser_extension\tracker_helper'
$payloadManifestPath = Join-Path $stagingOutput 'payload-manifest.json'

$movedCurrentOutput = $false
$installedNewOutput = $false
try {
    foreach ($directory in @(
        $generatedHeaders,
        $nativeOutputDirectory,
        $dotnetArtifacts,
        $hostOutput,
        $extensionOutput
    )) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    $programFilesX86 = [System.Environment]::GetFolderPath(
        [System.Environment+SpecialFolder]::ProgramFilesX86)
    $vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
        throw 'Visual Studio Build Tools were not found.'
    }

    $visualStudio = @(& $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath) | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($visualStudio)) {
        throw 'The Visual C++ x64 build tools were not found.'
    }
    $vcvars = Join-Path $visualStudio 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not (Test-Path -LiteralPath $vcvars -PathType Leaf)) {
        throw "The Visual C++ environment script is missing: $vcvars"
    }

    $sdkRoot = Join-Path $programFilesX86 'Windows Kits\10'
    $sdkVersion = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'Include') -Directory |
        Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName 'cppwinrt')) -and
            (Test-Path -LiteralPath (Join-Path $sdkRoot "bin\$($_.Name)\x64\cppwinrt.exe"))
        } |
        Sort-Object { [version] $_.Name } -Descending |
        Select-Object -First 1 -ExpandProperty Name
    if (-not $sdkVersion) {
        throw 'A Windows SDK with C++/WinRT was not found.'
    }
    $cppwinrt = Join-Path $sdkRoot "bin\$sdkVersion\x64\cppwinrt.exe"

    Invoke-Checked 'C++/WinRT header generation' {
        & $cppwinrt `
            -input $sdkVersion `
            -output $generatedHeaders `
            -include Windows.Foundation `
            -include Windows.Globalization `
            -include Windows.Graphics.Imaging `
            -include Windows.Media.Ocr `
            -include Windows.Storage `
            -include Windows.Storage.Streams `
            -overwrite
    }

    $environmentLines = & $env:ComSpec /d /s /c "call `"$vcvars`" >nul && set"
    if ($LASTEXITCODE -ne 0) {
        throw "Visual C++ environment initialization failed with exit code $LASTEXITCODE."
    }
    $originalEnvironment = @{}
    foreach ($line in $environmentLines) {
        $separator = $line.IndexOf('=')
        if ($separator -gt 0) {
            $name = $line.Substring(0, $separator)
            $value = $line.Substring($separator + 1)
            if (-not $originalEnvironment.ContainsKey($name)) {
                $originalEnvironment[$name] =
                    [System.Environment]::GetEnvironmentVariable($name, 'Process')
            }
            [System.Environment]::SetEnvironmentVariable($name, $value, 'Process')
        }
    }

    try {
        $compiler = Get-Command cl.exe -CommandType Application -ErrorAction Stop
        $nativeSource = Join-Path $projectRoot 'src\SummaryOcr\native\SummaryOcrNative.cpp'
        $compileArguments = [System.Collections.Generic.List[string]]::new()
        foreach ($argument in @(
            '/nologo',
            '/std:c++20',
            '/EHsc',
            '/permissive-',
            '/W4',
            '/WX',
            '/sdl',
            '/Zc:__cplusplus',
            '/external:W0',
            "/external:I$generatedHeaders",
            '/DUNICODE',
            '/D_UNICODE'
        )) {
            $compileArguments.Add($argument)
        }
        if ($Configuration -eq 'Release') {
            foreach ($argument in @(
                '/O1',
                '/GL',
                '/Gy',
                '/Gw',
                '/MT',
                '/DNDEBUG',
                '/experimental:deterministic',
                "/pathmap:$projectRoot=bsl-src",
                "/pathmap:$intermediateRoot=bsl-build"
            )) {
                $compileArguments.Add($argument)
            }
        }
        else {
            foreach ($argument in @('/Od', '/MTd', '/Zi')) {
                $compileArguments.Add($argument)
            }
        }
        $compileArguments.Add($nativeSource)
        $compileArguments.Add("/Fo:$nativeObject")
        $compileArguments.Add("/Fe:$nativeBinary")
        $compileArguments.Add('/link')
        $compileArguments.Add('/INCREMENTAL:NO')
        $compileArguments.Add('/Brepro')
        if ($Configuration -eq 'Release') {
            foreach ($argument in @('/LTCG', '/OPT:REF', '/OPT:ICF')) {
                $compileArguments.Add($argument)
            }
        }
        else {
            $compileArguments.Add('/DEBUG')
        }
        foreach ($library in @('windowsapp.lib', 'crypt32.lib')) {
            $compileArguments.Add($library)
        }

        Invoke-Checked 'Native Summary OCR build' {
            & $compiler.Source @compileArguments
        }
    }
    finally {
        foreach ($name in $originalEnvironment.Keys) {
            [System.Environment]::SetEnvironmentVariable(
                $name,
                $originalEnvironment[$name],
                'Process')
        }
    }

    # C# compilation does not consume the native LIB search path. Some Visual
    # Studio custom-build environments provide stale LIB entries that Roslyn
    # reports as warnings, so do not pass those entries into dotnet publish.
    [System.Environment]::SetEnvironmentVariable('LIB', $null, 'Process')

    $nativeHostProject = Join-Path $projectRoot 'src\SessionImport.NativeHost\SessionImport.NativeHost.csproj'
    Invoke-Checked 'Native messaging host publish' {
        & dotnet publish $nativeHostProject `
            -c $Configuration `
            -r win-x64 `
            --self-contained false `
            --artifacts-path $dotnetArtifacts `
            -o $hostOutput `
            -p:DebugType=none `
            -p:DebugSymbols=false
    }

    $applicationProject = Join-Path $projectRoot 'src\SessionImport.App\SessionImport.App.csproj'
    Invoke-Checked 'Session Import application publish' {
        & dotnet publish $applicationProject `
            -c $Configuration `
            -r win-x64 `
            --self-contained false `
            --artifacts-path $dotnetArtifacts `
            -o $stagingOutput `
            -p:DebugType=none `
            -p:DebugSymbols=false
    }

    Copy-Item -LiteralPath $nativeBinary `
        -Destination (Join-Path $stagingOutput 'SummaryOcrNative.exe') -Force

    $extensionSource = Join-Path $projectRoot 'browser_extension\tracker_helper'
    $extensionFiles = @(
        'manifest.json',
        'background.js',
        'content.js',
        'protocol.js',
        'bridge.html',
        'bridge.js',
        'bridge.css'
    )
    foreach ($fileName in $extensionFiles) {
        $sourceFile = Join-Path $extensionSource $fileName
        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
            throw "Production browser-extension file is missing: $sourceFile"
        }
        Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $extensionOutput $fileName) -Force
    }

    Get-ChildItem -LiteralPath $stagingOutput -Recurse -File -Filter '*.pdb' |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

    Assert-ContainedPath $outputParent $intermediateRoot 'remove build intermediates'
    if (Test-Path -LiteralPath $intermediateRoot) {
        Remove-Item -LiteralPath $intermediateRoot -Recurse -Force
    }

    $requiredFiles = @(
        'Session Import.exe',
        'SummaryOcrNative.exe',
        'WebView2Loader.dll',
        'browser_helper\BlackSpiritSessionImportHost.exe',
        'browser_extension\tracker_helper\manifest.json',
        'Assets\loot_catalog.json',
        'Assets\spot_catalog.json',
        'Assets\garmoth_spot_catalog.json'
    )
    foreach ($relativePath in $requiredFiles) {
        $requiredFile = Join-Path $stagingOutput $relativePath
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "Published Session Import payload is incomplete: $relativePath"
        }
    }
    $debugSymbols = @(Get-ChildItem -LiteralPath $stagingOutput -Recurse -File -Filter '*.pdb')
    if ($debugSymbols.Count -ne 0) {
        throw 'Published Session Import payload still contains debug symbols.'
    }

    $sourceFiles = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File |
        Where-Object { $_.FullName -notmatch '\\(bin|obj|build|artifacts|tests)\\' })
    $payloadFiles = @(Get-ChildItem -LiteralPath $stagingOutput -Recurse -File |
        Where-Object { $_.FullName -ne $payloadManifestPath } |
        Sort-Object FullName)
    $payloadEntries = foreach ($file in $payloadFiles) {
        [pscustomobject]@{
            path = $file.FullName.Substring($stagingOutput.Length + 1).Replace('\', '/')
            bytes = $file.Length
            sha256 = Get-FileSha256 $file.FullName
        }
    }
    Write-PayloadManifest `
        -Path $payloadManifestPath `
        -Configuration $Configuration `
        -SourceFileCount $sourceFiles.Count `
        -SourceFingerprint (Get-InventoryFingerprint $sourceFiles $projectRoot) `
        -ExtensionFiles $extensionFiles `
        -PayloadEntries @($payloadEntries)

    if (Test-Path -LiteralPath $resolvedOutput) {
        Assert-ContainedPath $outputParent $resolvedOutput 'rotate the previous payload'
        Move-Item -LiteralPath $resolvedOutput -Destination $previousOutput
        $movedCurrentOutput = $true
    }
    Move-Item -LiteralPath $stagingOutput -Destination $resolvedOutput
    $installedNewOutput = $true

    if ($movedCurrentOutput -and (Test-Path -LiteralPath $previousOutput)) {
        Assert-ContainedPath $outputParent $previousOutput 'remove the previous payload'
        Remove-Item -LiteralPath $previousOutput -Recurse -Force
        $movedCurrentOutput = $false
    }
}
catch {
    if (-not $installedNewOutput -and $movedCurrentOutput -and
        -not (Test-Path -LiteralPath $resolvedOutput) -and
        (Test-Path -LiteralPath $previousOutput)) {
        Move-Item -LiteralPath $previousOutput -Destination $resolvedOutput
        $movedCurrentOutput = $false
    }
    throw
}
finally {
    if (Test-Path -LiteralPath $intermediateRoot) {
        Assert-ContainedPath $outputParent $intermediateRoot 'remove failed build intermediates'
        Remove-Item -LiteralPath $intermediateRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $stagingOutput) {
        Assert-ContainedPath $outputParent $stagingOutput 'remove the failed staging payload'
        Remove-Item -LiteralPath $stagingOutput -Recurse -Force
    }
}

Get-Item -LiteralPath (Join-Path $resolvedOutput 'Session Import.exe') |
    Select-Object FullName, Length, LastWriteTime
