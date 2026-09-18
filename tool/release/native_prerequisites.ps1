# Mirror the current producer selection contracts, not the builder's unrelated
# .NET path used for Velopack. Changes to a producer require an explicit review.
. (Join-Path $PSScriptRoot 'preflight.ps1')

function Invoke-ReleaseNativePrerequisiteChecks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        # Override only for isolated synthetic tests; production callers omit it.
        [string]$ProgramFilesX86 = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)
    )
    $contracts = [ordered]@{
        'windows/session_import/build-publish.ps1' = '292474676B155E5C14E1EAB49684232505241D8A245589F35C30514BE45B72D3'
        'windows/storage_ocr/BlackSpiritStorageOcr/build-publish.ps1' = '7C3214F69652101140440F4B95E41D49EA45945A88D3B8F738566FDA34FAC311'
        'windows/installer/CMakeLists.txt' = '1E861E045ADF98C8043AE5E9F1A7575C15A453861B27F29206EC3BB3082B8EB3'
        'windows/CMakeLists.txt' = 'E416E4370D6AFFC4A187175E13D3667B0C695A2DFC136C23B92817D4146BD09F'
    }
    foreach ($relative in $contracts.Keys) {
        $pin = Get-ReleaseDependencyFilePin (Join-Path $ProjectRoot $relative) $relative
        if ($pin.sha256 -cne $contracts[$relative]) { throw "Native producer contract changed; review prerequisite selection before building: $relative." }
    }
    $artwork = [ordered]@{
        'windows/installer/assets/blackened-cedar-installer.jpg' = '4D614522B41BF8AAD766E95516BEB086E96C4516DDA58ACF564D3912931E563E'
        'windows/installer/assets/charcoal-plum-lacquer-installer.jpg' = 'D0A6AB9F4DB69A34B3070AD0FF2A169F3C62A491B1E928718B1D042BC0A796A3'
        'windows/runner/resources/app_icon.ico' = $null
        'assets/sakura/botanicals/title-sprig.png' = $null
    }
    $artworkPins = @()
    foreach ($relative in $artwork.Keys) {
        $pin = Get-ReleaseDependencyFilePin (Join-Path $ProjectRoot $relative) $relative
        if ($null -ne $artwork[$relative] -and $pin.sha256 -cne $artwork[$relative]) { throw "Installer artwork failed the producer's required hash: $relative." }
        $artworkPins += $pin
    }
    $sessionCommand = Get-Command 'dotnet' -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $sessionDotnet = $sessionCommand.Source
    # Exact OCR precedence with no explicit override in windows/CMakeLists.txt.
    $ocrDotnet = $env:DOTNET_EXE
    if (-not [string]::IsNullOrWhiteSpace($ocrDotnet) -and (Test-Path -LiteralPath $ocrDotnet -PathType Container)) { $ocrDotnet = Join-Path $ocrDotnet 'dotnet.exe' }
    if ([string]::IsNullOrWhiteSpace($ocrDotnet)) {
        $workspaceSdkRoot = Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($ProjectRoot))) 'tmp'
        if (Test-Path -LiteralPath $workspaceSdkRoot -PathType Container) {
            $ocrDotnet = Get-ChildItem -LiteralPath $workspaceSdkRoot -Directory -Filter 'dotnet-sdk-*' |
                Sort-Object -Property Name -Descending | ForEach-Object { Join-Path $_.FullName 'dotnet.exe' } |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        }
    }
    if ([string]::IsNullOrWhiteSpace($ocrDotnet)) {
        $ocrCommand = Get-Command 'dotnet.exe' -ErrorAction Stop | Select-Object -First 1
        $ocrDotnet = $ocrCommand.Source
    }
    $dotnetEvidence = @()
    Push-Location -LiteralPath $ProjectRoot
    try {
        foreach ($role in @(@('session-import', $sessionDotnet), @('storage-ocr', $ocrDotnet))) {
            $pin = Get-ReleaseDependencyFilePin $role[1] ($role[0] + '-dotnet')
            $sdk = (Invoke-ReleaseVersionCommand -Path $role[1] -Operation ($role[0] + ' SDK selection')).Trim()
            if ($sdk -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$' -or [int]$sdk.Split('.')[0] -lt 8) {
                throw "Native producer $($role[0]) requires a selected .NET SDK 8 or newer."
            }
            $dotnetEvidence += [ordered]@{ role = $role[0]; sdk = $sdk; executableSha256 = $pin.sha256 }
        }
    }
    finally { Pop-Location }
    $vswhere = Join-Path $ProgramFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
    $null = Assert-ReleasePreflightFile $vswhere 'vswhere'
    $visualStudio = (Invoke-ReleaseVersionCommand -Path $vswhere -Operation 'Visual C++ selection' `
        -Arguments @('-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath')).Split("`n")[0].Trim()
    if ([string]::IsNullOrWhiteSpace($visualStudio)) { throw 'The producer-selected Visual C++ x64 build tools were not found.' }
    $vcvars = Join-Path $visualStudio 'VC\Auxiliary\Build\vcvars64.bat'
    $vcvarsPin = Get-ReleaseDependencyFilePin $vcvars 'vcvars64'
    $sdkRoot = Join-Path $ProgramFilesX86 'Windows Kits\10'
    $sdkVersion = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'Include') -Directory |
        Where-Object { (Test-Path -LiteralPath (Join-Path $_.FullName 'cppwinrt')) -and (Test-Path -LiteralPath (Join-Path $sdkRoot "bin\$($_.Name)\x64\cppwinrt.exe")) } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1 -ExpandProperty Name
    if (-not $sdkVersion) { throw 'The producer-selected Windows SDK with C++/WinRT is unavailable.' }
    $cppwinrtPin = Get-ReleaseDependencyFilePin (Join-Path $sdkRoot "bin\$sdkVersion\x64\cppwinrt.exe") 'cppwinrt'
    # Probe in a child cmd only; never import vcvars into the agent's environment.
    $probe = Invoke-ReleaseVersionCommand -Path $env:ComSpec -Operation 'Visual C++ environment probe' `
        -Arguments @('/d', '/s', '/c', "call `"$vcvars`" >nul && where cl.exe && set WindowsSdkDir && set WindowsSDKVersion")
    $compiler = ($probe.Split("`n") | Where-Object { $_.Trim() -match '(?i)\\cl\.exe$' } | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($compiler)) { throw 'The producer-selected Visual C++ environment has no cl.exe.' }
    $compilerPin = Get-ReleaseDependencyFilePin $compiler.Trim() 'cl.exe'
    $compilerSdk = [regex]::Match($probe, '(?m)^WindowsSDKVersion=([^\r\n]+)').Groups[1].Value.Trim().TrimEnd('\')
    if ($compilerSdk -notmatch '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$') { throw 'The Visual C++ environment did not identify its selected Windows SDK.' }
    $compilerSdkRoot = [regex]::Match($probe, '(?m)^WindowsSdkDir=([^\r\n]+)').Groups[1].Value.Trim().TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($compilerSdkRoot) -or -not (Test-Path -LiteralPath $compilerSdkRoot -PathType Container)) {
        throw 'The Visual C++ environment selected an unavailable Windows SDK directory.'
    }
    return [ordered]@{
        schemaVersion = 1; producerContracts = $contracts; dotnet = $dotnetEvidence
        cppwinrtSdk = $sdkVersion; compilerWindowsSdk = $compilerSdk
        cppwinrtSha256 = $cppwinrtPin.sha256; compilerSha256 = $compilerPin.sha256; vcvarsSha256 = $vcvarsPin.sha256
        installerArtwork = $artworkPins; isBuildVerification = $false
        # Local release/checkpoint evidence only; do not print these paths in public logs.
        selectedInputPaths = @(
            [ordered]@{ role = 'dotnet-sdk'; path = Split-Path -Parent ([IO.Path]::GetFullPath($sessionDotnet)) },
            [ordered]@{ role = 'dotnet-sdk'; path = Split-Path -Parent ([IO.Path]::GetFullPath($ocrDotnet)) },
            [ordered]@{ role = 'native-toolchain'; path = [IO.Path]::GetFullPath($visualStudio) },
            [ordered]@{ role = 'windows-sdk'; path = [IO.Path]::GetFullPath($sdkRoot) },
            [ordered]@{ role = 'windows-sdk'; path = [IO.Path]::GetFullPath($compilerSdkRoot) }
        )
        syntheticProbeRoot = $PSBoundParameters.ContainsKey('ProgramFilesX86')
    }
}
