[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$helper = Join-Path $repository 'tool\release'
. (Join-Path $helper 'native_prerequisites.ps1')
$script:assertions = 0
function Assert-Fixture([bool]$Value, [string]$Message) {
    if (-not $Value) { throw "Dependency/native fixture: $Message" }
    $script:assertions++
}
function Assert-Rejected([scriptblock]$Action, [string]$Pattern) {
    $caught = $false
    try { & $Action | Out-Null } catch {
        $caught = $true
        Assert-Fixture ($_.Exception.Message -match $Pattern) "Unexpected rejection: $($_.Exception.Message)"
    }
    Assert-Fixture $caught "Expected rejection: $Pattern"
}
function Put([string]$Path, [string]$Text) {
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$fixture = Join-Path $tempParent ('bsl-dependency-native-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($fixture)
$oldDotnet = $env:DOTNET_EXE
try {
    $package = Join-Path $fixture 'package'
    $flutter = Join-Path $fixture 'sdk\bin\flutter.bat'
    $validFlutter = "@echo off`r`nif not `"%1 %2 %3`"==`"pub get --enforce-lockfile`" exit /b 93`r`nexit /b 0`r`n"
    Put $flutter $validFlutter
    Put (Join-Path $fixture 'sdk\bin\cache\flutter.version.json') '{"frameworkVersion":"3.44.0","dartSdkVersion":"3.12.2"}'
    Put (Join-Path $fixture 'sdk\bin\cache\dart-sdk\bin\dart.exe') 'fake-sdk-executable'
    Put (Join-Path $fixture 'sdk\bin\cache\flutter_tools.snapshot') 'fake-tools'
    Put (Join-Path $package 'pubspec.yaml') 'name: fixture'
    Put (Join-Path $package 'pubspec.lock') 'packages: {}'
    Put (Join-Path $package 'lib\fixture.dart') '// synthetic'
    $configPath = Join-Path $package '.dart_tool\package_config.json'
    $validConfig = '{"configVersion":2,"generator":"pub","generatorVersion":"3.12.2","packages":[{"name":"fixture","rootUri":"../","packageUri":"lib/"}]}'
    Put $configPath $validConfig
    $receipt = Join-Path $fixture 'prepared.json'
    $prepared = & (Join-Path $helper 'prepare_dependencies.ps1') -PackageRoot $package -FlutterPath $flutter -ReceiptPath $receipt
    Assert-Fixture ($prepared.status -ceq 'prepared-not-release-verified') 'Preparation has a non-release success state.'
    $dependencyArgs = @{ PackageRoot = $package; FlutterPath = $flutter; ReceiptPath = $receipt; ApprovedReceiptSha256 = $prepared.sha256 }
    $validated = Assert-ReleasePreparedDependencies @dependencyArgs
    Assert-Fixture ($validated.packageCount -eq 1 -and $validated.isBuildCacheKey -eq $false) 'A real child stub accepted exactly the lock-enforced command and produced reusable preparation evidence.'
    Assert-Fixture (-not (Get-Content -LiteralPath $receipt -Raw).Contains($fixture)) 'Receipt does not expose local paths.'
    Assert-Rejected { & (Join-Path $helper 'prepare_dependencies.ps1') -PackageRoot $package -FlutterPath $flutter -ReceiptPath $receipt } 'new receipt'
    $bad = $dependencyArgs.Clone(); $bad.ApprovedReceiptSha256 = ('0' * 64)
    Assert-Rejected { Assert-ReleasePreparedDependencies @bad } 'SHA-256'
    foreach ($case in @(
        @('pubspec.yaml', 'name: changed'), @('pubspec.lock', 'packages: {changed: true}'),
        @('pubspec_overrides.yaml', 'dependency_overrides: {}'), @('.dart_tool\package_config.json', ($validConfig + ' '))
    )) {
        $path = Join-Path $package $case[0]
        $existing = Test-Path -LiteralPath $path
        $original = if ($existing) { [IO.File]::ReadAllText($path) } else { $null }
        Put $path $case[1]
        Assert-Rejected { Assert-ReleasePreparedDependencies @dependencyArgs } 'receipt is stale'
        if ($existing) { Put $path $original } else { [IO.File]::Delete($path) }
    }
    foreach ($changedConfig in @(
        '{"configVersion":2,"generator":"pub","generatorVersion":"3.12.2","packages":[]}',
        $validConfig.Replace('3.12.2', '3.11.0'),
        $validConfig.Replace('"rootUri":"../"', '"rootUri":"https://example.invalid/"'),
        $validConfig.Replace('"packageUri":"lib/"', '"packageUri":"../"')
    )) {
        Put $configPath $changedConfig
        Assert-Rejected { Assert-ReleasePreparedDependencies @dependencyArgs } 'populated|different Dart SDK|local file URI|reviewed lib'
    }
    Put $configPath $validConfig
    $dart = Join-Path $fixture 'sdk\bin\cache\dart-sdk\bin\dart.exe'
    Put $dart 'changed-sdk'
    Assert-Rejected { Assert-ReleasePreparedDependencies @dependencyArgs } 'receipt is stale'
    Put $dart 'fake-sdk-executable'
    $configHeld = $configPath + '.held'
    [IO.File]::Move($configPath, $configHeld)
    Assert-Rejected { Assert-ReleasePreparedDependencies @dependencyArgs } 'does not exist|cannot find'
    [IO.File]::Move($configHeld, $configPath)
    Put $flutter "@echo off`r`nexit /b 19`r`n"
    $failedReceipt = Join-Path $fixture 'failed.json'
    Assert-Rejected { & (Join-Path $helper 'prepare_dependencies.ps1') -PackageRoot $package -FlutterPath $flutter -ReceiptPath $failedReceipt } 'preparation failed'
    Assert-Fixture (-not (Test-Path -LiteralPath $failedReceipt)) 'Failed dependency preparation cannot leave a passed receipt.'
    Put $flutter "@echo off`r`necho changed>pubspec.lock`r`nexit /b 0`r`n"
    Assert-Rejected { & (Join-Path $helper 'prepare_dependencies.ps1') -PackageRoot $package -FlutterPath $flutter -ReceiptPath $failedReceipt } 'changed a source'
    Assert-Fixture (-not (Test-Path -LiteralPath $failedReceipt)) 'A changed source lock is rejected even when the child claims success.'
    Put (Join-Path $package 'pubspec.lock') 'packages: {}'
    Put $flutter $validFlutter
    $dependency = Join-Path $fixture 'dependency'
    Put (Join-Path $dependency 'pubspec.yaml') 'name: dependency'
    Put (Join-Path $dependency 'lib\dependency.dart') '// local path dependency'
    Put $configPath $validConfig.Replace('"packageUri":"lib/"}]}', '"packageUri":"lib/"},{"name":"dependency","rootUri":"../../dependency/","packageUri":"lib/"}]}')
    $pathReceipt = Join-Path $fixture 'path-dependency.json'
    $pathPrepared = & (Join-Path $helper 'prepare_dependencies.ps1') -PackageRoot $package -FlutterPath $flutter -ReceiptPath $pathReceipt
    $pathArgs = @{ PackageRoot=$package; FlutterPath=$flutter; ReceiptPath=$pathReceipt; ApprovedReceiptSha256=$pathPrepared.sha256 }
    Assert-Fixture ((Assert-ReleasePreparedDependencies @pathArgs).packageCount -eq 2) 'Resolved external/path package pubspec is part of the dependency receipt.'
    Put (Join-Path $dependency 'pubspec.yaml') 'name: dependency_changed'
    Assert-Rejected { Assert-ReleasePreparedDependencies @pathArgs } 'receipt is stale'

    # Native probes are entirely synthetic: source contracts/artwork are copied,
    # while process discovery/version output is mocked instead of compiling.
    $nativeRoot = Join-Path $fixture 'native'
    foreach ($relative in @(
        'windows/session_import/build-publish.ps1', 'windows/storage_ocr/BlackSpiritStorageOcr/build-publish.ps1',
        'windows/installer/CMakeLists.txt', 'windows/CMakeLists.txt',
        'windows/installer/assets/blackened-cedar-installer.jpg', 'windows/installer/assets/charcoal-plum-lacquer-installer.jpg',
        'windows/runner/resources/app_icon.ico', 'assets/sakura/botanicals/title-sprig.png'
    )) {
        $destination = Join-Path $nativeRoot $relative
        $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        [IO.File]::Copy((Join-Path $repository $relative), $destination)
    }
    $pf = Join-Path $fixture 'program-files-x86'
    $vswhere = Join-Path $pf 'Microsoft Visual Studio\Installer\vswhere.exe'
    $studio = Join-Path $fixture 'vs'
    $vcvars = Join-Path $studio 'VC\Auxiliary\Build\vcvars64.bat'
    $compiler = Join-Path $studio 'compiler\cl.exe'
    $sessionDotnet = Join-Path $fixture 'session-dotnet.exe'
    $ocrDotnet = Join-Path $fixture 'ocr-dotnet.exe'
    foreach ($file in @($vswhere, $vcvars, $compiler, $sessionDotnet, $ocrDotnet)) { Put $file 'synthetic-tool' }
    foreach ($sdk in @('10.0.19041.0', '10.0.26100.0')) {
        $null = [IO.Directory]::CreateDirectory((Join-Path $pf "Windows Kits\10\Include\$sdk\cppwinrt"))
        Put (Join-Path $pf "Windows Kits\10\bin\$sdk\x64\cppwinrt.exe") 'synthetic-winrt'
    }
    $env:DOTNET_EXE = $ocrDotnet
    $script:probePaths = [Collections.Generic.List[string]]::new()
    $script:sdkResponse = '8.0.400'
    function Get-Command { param([string]$Name, [object]$CommandType, [object]$ErrorAction) return [pscustomobject]@{ Source = $sessionDotnet } }
    function Invoke-ReleaseVersionCommand {
        param([string]$Path, [string]$Operation, [string[]]$Arguments)
        $script:probePaths.Add($Path)
        if ($Operation -ceq 'Visual C++ selection') { return $studio }
        if ($Operation -ceq 'Visual C++ environment probe') { return "$compiler`nWindowsSdkDir=$pf\Windows Kits\10\`nWindowsSDKVersion=10.0.19041.0\" }
        return $script:sdkResponse
    }
    $native = Invoke-ReleaseNativePrerequisiteChecks -ProjectRoot $nativeRoot -ProgramFilesX86 $pf
    Assert-Fixture ($native.cppwinrtSdk -ceq '10.0.26100.0' -and $native.compilerWindowsSdk -ceq '10.0.19041.0') 'C++/WinRT selection and actual vcvars SDK are recorded separately.'
    Assert-Fixture ($script:probePaths.Contains($sessionDotnet) -and $script:probePaths.Contains($ocrDotnet)) 'Each producer-selected .NET executable is probed independently.'
    Assert-Fixture ($native.isBuildVerification -eq $false -and $native.syntheticProbeRoot -eq $true) 'Synthetic prerequisites cannot claim compiled verification.'
    Assert-Fixture ($native.selectedInputPaths.Count -eq 5 -and $native.selectedInputPaths[0].path -ceq (Split-Path -Parent $sessionDotnet) -and $native.selectedInputPaths[2].path -ceq $studio -and $native.selectedInputPaths[3].path -ceq (Join-Path $pf 'Windows Kits\10')) 'Local-only selected whole installation roots include SDK headers/libraries and all VS toolchain inputs, not executable-only coverage.'
    $script:sdkResponse = '7.0.400'
    Assert-Rejected { Invoke-ReleaseNativePrerequisiteChecks -ProjectRoot $nativeRoot -ProgramFilesX86 $pf } 'selected .NET SDK 8'
    $script:sdkResponse = '8.0.400'
    $workspaceSdk = Join-Path $fixture 'tmp\dotnet-sdk-9.0.999\dotnet.exe'
    Put $workspaceSdk 'workspace-sdk'
    $env:DOTNET_EXE = ''
    $null = Invoke-ReleaseNativePrerequisiteChecks -ProjectRoot $nativeRoot -ProgramFilesX86 $pf
    Assert-Fixture ($script:probePaths.Contains($workspaceSdk)) 'OCR workspace-SDK precedence matches its producer rather than builder dotnet.'
    $env:DOTNET_EXE = Join-Path $fixture 'missing-dotnet.exe'
    Assert-Rejected { Invoke-ReleaseNativePrerequisiteChecks -ProjectRoot $nativeRoot -ProgramFilesX86 $pf } 'does not exist|cannot find'
    $env:DOTNET_EXE = $ocrDotnet
    [IO.File]::Move($vswhere, ($vswhere + '.held'))
    Assert-Rejected { Invoke-ReleaseNativePrerequisiteChecks -ProjectRoot $nativeRoot -ProgramFilesX86 $pf } 'missing: vswhere'
    [IO.File]::Move(($vswhere + '.held'), $vswhere)
    [IO.File]::Move($vcvars, ($vcvars + '.held'))
    Assert-Rejected { Invoke-ReleaseNativePrerequisiteChecks -ProjectRoot $nativeRoot -ProgramFilesX86 $pf } 'does not exist|cannot find'
    [IO.File]::Move(($vcvars + '.held'), $vcvars)
    foreach ($sdk in @('10.0.19041.0', '10.0.26100.0')) {
        $winrt = Join-Path $pf "Windows Kits\10\bin\$sdk\x64\cppwinrt.exe"
        [IO.File]::Move($winrt, ($winrt + '.held'))
    }
    Assert-Rejected { Invoke-ReleaseNativePrerequisiteChecks -ProjectRoot $nativeRoot -ProgramFilesX86 $pf } 'Windows SDK with C\+\+/WinRT is unavailable'
    foreach ($sdk in @('10.0.19041.0', '10.0.26100.0')) {
        $winrt = Join-Path $pf "Windows Kits\10\bin\$sdk\x64\cppwinrt.exe"
        [IO.File]::Move(($winrt + '.held'), $winrt)
    }
    $artPath = Join-Path $nativeRoot 'windows/installer/assets/blackened-cedar-installer.jpg'
    Put $artPath 'altered-artwork'
    Assert-Rejected { Invoke-ReleaseNativePrerequisiteChecks -ProjectRoot $nativeRoot -ProgramFilesX86 $pf } "artwork failed the producer"
    [IO.File]::Copy((Join-Path $repository 'windows/installer/assets/blackened-cedar-installer.jpg'), $artPath, $true)
    Put (Join-Path $nativeRoot 'windows/session_import/build-publish.ps1') '# changed selection'
    Assert-Rejected { Invoke-ReleaseNativePrerequisiteChecks -ProjectRoot $nativeRoot -ProgramFilesX86 $pf } 'producer contract changed'
    Write-Host "PASS: $script:assertions dependency/native prerequisite assertions on PowerShell $($PSVersionTable.PSVersion)."
}
finally {
    $env:DOTNET_EXE = $oldDotnet
    $resolved = [IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($tempParent + '\', [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolved) -notmatch '^bsl-dependency-native-[0-9a-f]{32}$') { throw 'Unsafe fixture cleanup target.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
