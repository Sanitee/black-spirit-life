# Read-only prerequisites for the existing Windows release builder. This does
# not replace source/parity/privacy gates and never prepares dependencies.
. (Join-Path $PSScriptRoot 'prepared_dependencies.ps1')

function Assert-ReleaseCommandExit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][AllowNull()][object]$ExitCode
    )
    if ($null -eq $ExitCode -or $ExitCode -isnot [int]) {
        throw "$Operation did not supply a native command exit code."
    }
    if ($ExitCode -ne 0) {
        throw "$Operation failed with exit code $ExitCode."
    }
}

function Assert-ReleasePreflightFile {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Label = 'input')
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Preflight required file is missing: $Label."
    }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.Length -le 0 -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Preflight requires an ordinary non-empty file: $Label."
    }
    return $item
}

function Resolve-ReleaseToolPath {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$ExplicitPath,
        [string[]]$FallbackPaths = @()
    )
    $resolved = $ExplicitPath
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command) {
            $resolved = $command.Source
        }
        else {
            $resolved = $FallbackPaths | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                (Test-Path -LiteralPath $_ -PathType Leaf)
            } | Select-Object -First 1
        }
    }
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        throw "Preflight required tool was not found: $Name."
    }
    $item = Assert-ReleasePreflightFile -Path $resolved -Label $Name
    return $item.FullName
}

function Invoke-ReleaseVersionCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Operation,
        [string[]]$Arguments = @('--version')
    )
    # Normalize native failure handling across Windows PowerShell and pwsh.
    $PSNativeCommandUseErrorActionPreference = $false
    # Windows PowerShell represents redirected stderr as ErrorRecord objects;
    # inspect the explicit exit code instead of letting stderr hide the stage.
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = $null
    try { $output = @(& $Path @Arguments 2>&1) }
    catch { throw "$Operation could not start." }
    Assert-ReleaseCommandExit -Operation $Operation -ExitCode $global:LASTEXITCODE
    return (($output | ForEach-Object { [string]$_ }) -join "`n")
}

function Get-ReleaseToolVersionEvidence {
    param([Parameter(Mandatory = $true)][object]$Tools)

    $gitOutput = Invoke-ReleaseVersionCommand -Path $Tools.GitPath -Operation 'Preflight git version'
    $tarOutput = Invoke-ReleaseVersionCommand -Path $Tools.TarPath -Operation 'Preflight tar version'
    $cmakeOutput = Invoke-ReleaseVersionCommand -Path $Tools.CMakePath -Operation 'Preflight CMake version'
    $sdkOutput = Invoke-ReleaseVersionCommand -Path $Tools.DotnetPath -Operation 'Preflight .NET SDK inventory' -Arguments @('--list-sdks')
    $runtimeOutput = Invoke-ReleaseVersionCommand -Path $Tools.DotnetPath -Operation 'Preflight .NET runtime inventory' -Arguments @('--list-runtimes')

    $gitMatch = [regex]::Match($gitOutput, '(?m)^git version ([0-9]+\.[0-9]+\.[0-9]+)')
    $tarMatch = [regex]::Match($tarOutput, '(?m)^(?:bsdtar |tar \(GNU tar\) )([0-9]+\.[0-9]+(?:\.[0-9]+)?)')
    $cmakeMatch = [regex]::Match($cmakeOutput, '(?m)^cmake version ([0-9]+\.[0-9]+\.[0-9]+)')
    if (-not $gitMatch.Success -or -not $tarMatch.Success -or -not $cmakeMatch.Success) {
        throw 'Preflight could not validate git, tar or CMake version output.'
    }
    if ([version]$cmakeMatch.Groups[1].Value -lt [version]'3.25.0') {
        throw 'Preflight requires CMake 3.25 or newer for the installer.'
    }
    $sdks = @([regex]::Matches($sdkOutput, '(?m)^([0-9]+\.[0-9]+\.[0-9]+)(?:[-+][^\s]+)?\s+\[') |
        ForEach-Object { $_.Groups[1].Value })
    $runtimes = @([regex]::Matches($runtimeOutput, '(?m)^Microsoft\.NETCore\.App (8\.0\.[0-9]+)\s+\[') |
        ForEach-Object { $_.Groups[1].Value })
    if (@($sdks | Where-Object { [version]$_ -ge [version]'8.0.100' }).Count -eq 0 -or $runtimes.Count -eq 0) {
        throw 'Preflight requires a .NET 8 or newer SDK and the .NET 8 runtime.'
    }

    # flutter --version can bootstrap/download its cache. Read the installed
    # cache metadata instead; a missing cache is an explicit preparation issue.
    $flutterBin = Split-Path -Parent $Tools.FlutterPath
    $flutterMetadataPath = Join-Path $flutterBin 'cache\flutter.version.json'
    $null = Assert-ReleasePreflightFile -Path $flutterMetadataPath -Label 'Flutter installed version metadata'
    try {
        $flutterMetadata = Get-Content -LiteralPath $flutterMetadataPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $flutterVersion = [string]$flutterMetadata.frameworkVersion
        $dartVersion = [string]$flutterMetadata.dartSdkVersion
    }
    catch {
        throw 'Preflight Flutter installed version metadata is invalid.'
    }
    if ($flutterVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$' -or
        $dartVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:[ -+].*)?$') {
        throw 'Preflight Flutter installed version metadata has unsupported version values.'
    }
    return [ordered]@{
        powershell = $PSVersionTable.PSVersion.ToString()
        git = $gitMatch.Groups[1].Value
        tar = $tarMatch.Groups[1].Value
        cmake = $cmakeMatch.Groups[1].Value
        dotnetSdks = $sdks
        dotnet8Runtimes = $runtimes
        flutter = $flutterVersion
        dart = ([regex]::Match($dartVersion, '^[0-9]+\.[0-9]+\.[0-9]+')).Value
        flutterVersionSource = 'installed-cache-metadata'
    }
}

function Invoke-ReleasePreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$BuildNumber,
        [Parameter(Mandatory = $true)][string]$PublicGitHubRepository,
        [string]$FlutterPath,
        [string]$CMakePath,
        [string]$DotnetPath,
        [string]$GitPath,
        [string]$TarPath,
        [string]$DependencyReceiptPath,
        [string]$ApprovedDependencyReceiptSha256,
        [string[]]$RequiredRelativeFiles = @(),
        [ValidateRange(0, [long]::MaxValue)][long]$MinimumFreeBytes = 0
    )
    if ($PSVersionTable.PSVersion -lt [version]'5.1') {
        throw 'Preflight requires PowerShell 5.1 or newer.'
    }
    if ($Version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' -or
        $BuildNumber -cnotmatch '^[1-9][0-9]*$') {
        throw 'Preflight release version/build metadata is invalid.'
    }
    if ($PublicGitHubRepository -cnotmatch '^https://github\.com/[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})/[A-Za-z0-9._-]{1,100}$') {
        throw 'Preflight requires the canonical GitHub repository base URL.'
    }
    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        throw 'Preflight project directory is missing.'
    }
    $root = (Get-Item -LiteralPath $ProjectRoot -Force -ErrorAction Stop).FullName.TrimEnd([char[]]@('\', '/'))
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    $required = @('pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json') + $RequiredRelativeFiles
    foreach ($relative in $required) {
        if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or
            $relative -match '(?:^|[\\/])\.\.(?:[\\/]|$)' -or $relative.Contains(':')) {
            throw 'Preflight required input must use a contained relative path.'
        }
        $path = [IO.Path]::GetFullPath((Join-Path $root $relative))
        if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Preflight required input escaped the project directory.'
        }
        $null = Assert-ReleasePreflightFile -Path $path -Label $relative
        if ([IO.Path]::GetExtension($path) -ieq '.ps1') {
            $tokens = $null
            $parseErrors = $null
            $null = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
            if ($parseErrors.Count -ne 0) {
                throw "Preflight PowerShell syntax check failed: $relative."
            }
        }
    }
    $pubspec = Get-Content -LiteralPath (Join-Path $root 'pubspec.yaml') -Raw -ErrorAction Stop
    $pubspecVersions = [regex]::Matches($pubspec, '(?m)^version:\s*([^\r\n]+)\s*$')
    if ($pubspecVersions.Count -ne 1 -or $pubspecVersions[0].Groups[1].Value.Trim() -cne "$Version+$BuildNumber") {
        throw 'Preflight pubspec.yaml does not match the requested version/build.'
    }
    try {
        $packageConfig = Get-Content -LiteralPath (Join-Path $root '.dart_tool/package_config.json') -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
        if ($packageConfig.configVersion -ne 2 -or $null -eq $packageConfig.packages) {
            throw 'Invalid package config.'
        }
    }
    catch {
        throw 'Preflight requires an existing valid package_config.json for the --no-pub build. Prepare dependencies separately.'
    }

    $flutterFallbacks = @()
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $flutterFallbacks += Join-Path $env:USERPROFILE 'develop\flutter\bin\flutter.bat'
    }
    $cmakeFallbacks = @()
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $cmakeFallbacks += Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        foreach ($edition in @('Community', 'Professional', 'Enterprise')) {
            $cmakeFallbacks += Join-Path $env:ProgramFiles "Microsoft Visual Studio\2022\$edition\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
        }
    }
    $tools = [pscustomobject]@{
        FlutterPath = Resolve-ReleaseToolPath -Name 'flutter' -ExplicitPath $FlutterPath -FallbackPaths $flutterFallbacks
        CMakePath = Resolve-ReleaseToolPath -Name 'cmake' -ExplicitPath $CMakePath -FallbackPaths $cmakeFallbacks
        DotnetPath = Resolve-ReleaseToolPath -Name 'dotnet' -ExplicitPath $DotnetPath
        GitPath = Resolve-ReleaseToolPath -Name 'git' -ExplicitPath $GitPath
        TarPath = Resolve-ReleaseToolPath -Name 'tar' -ExplicitPath $TarPath
    }
    $versions = Get-ReleaseToolVersionEvidence -Tools $tools
    $dependencyEvidence = $null
    if (-not [string]::IsNullOrWhiteSpace($DependencyReceiptPath) -or
        -not [string]::IsNullOrWhiteSpace($ApprovedDependencyReceiptSha256)) {
        $dependencyEvidence = Assert-ReleasePreparedDependencies -PackageRoot $root -FlutterPath $tools.FlutterPath `
            -ReceiptPath $DependencyReceiptPath -ApprovedReceiptSha256 $ApprovedDependencyReceiptSha256
    }
    $sdkConstraint = [regex]::Match($pubspec, '(?m)^\s+sdk:\s*\^([0-9]+\.[0-9]+\.[0-9]+)\s*$')
    if ($sdkConstraint.Success) {
        $minimumDart = [version]$sdkConstraint.Groups[1].Value
        $installedDart = [version]$versions.dart
        if ($installedDart -lt $minimumDart -or $installedDart.Major -ne $minimumDart.Major) {
            throw 'Preflight installed Dart does not satisfy the pubspec SDK constraint.'
        }
    }
    else {
        throw 'Preflight does not support this pubspec Dart SDK constraint; review the constraint before building.'
    }
    $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($root))
    $availableBytes = $drive.AvailableFreeSpace
    if ($availableBytes -lt $MinimumFreeBytes) {
        throw 'Preflight available disk space is below the requested minimum.'
    }
    $tools | Add-Member -NotePropertyName Evidence -NotePropertyValue ([ordered]@{
        schemaVersion = 1
        version = $Version
        buildNumber = $BuildNumber
        toolVersions = $versions
        requiredFileCount = $required.Count
        noPubPrerequisite = $(if ($null -eq $dependencyEvidence) { 'present-and-parsed' } else { $dependencyEvidence.noPubPrerequisite })
        preparedDependencies = $dependencyEvidence
        availableBytes = $availableBytes
        minimumFreeBytes = $MinimumFreeBytes
        isReleaseVerification = $false
    })
    return $tools
}
