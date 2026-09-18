[CmdletBinding()]
param()

# Execute only the trusted builder's payload-scan AST extent against disposable
# synthetic files. Never invoke the builder, application, installer, or network.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$builderPath = Join-Path $repositoryRoot 'tool/build_stable_release_candidate.ps1'
$builderText = Get-Content -LiteralPath $builderPath -Raw
$tokens = $null
$parseErrors = $null
$builderAst = [Management.Automation.Language.Parser]::ParseInput(
    $builderText, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'Builder syntax must parse before payload fixtures run.' }

$script:assertions = 0
function Assert-Fixture([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Payload scan assertion failed: $Message" }
    $script:assertions++
}
function Find-BuilderAssignment([string]$Name) {
    $nodes = @($builderAst.FindAll({
        param($Node)
        $Node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $Node.Left -is [Management.Automation.Language.VariableExpressionAst] -and
        $Node.Left.VariablePath.UserPath -ceq $Name
    }, $true))
    Assert-Fixture ($nodes.Count -eq 1) "Expected one builder assignment for $Name."
    return $nodes[0]
}
foreach ($functionName in @('Test-SqliteFileHeader', 'Test-UnreviewedAbsolutePath', 'Assert-NoTextMarker')) {
    $nodes = @($builderAst.FindAll({
        param($Node)
        $Node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $Node.Name -ceq $functionName
    }, $true))
    Assert-Fixture ($nodes.Count -eq 1) "Expected one actual builder function $functionName."
    . ([scriptblock]::Create($nodes[0].Extent.Text))
}
foreach ($variableName in @('PrivateMachinePathPattern', 'ForbiddenPackagedArtifactPattern', 'VelopackRuntimeSha256')) {
    . ([scriptblock]::Create((Find-BuilderAssignment $variableName).Extent.Text))
}

$scanStart = Find-BuilderAssignment 'privateMarkers'
$scanEnd = @($builderAst.FindAll({
    param($Node)
    $Node -is [Management.Automation.Language.IfStatementAst] -and
    $Node.Extent.Text -match '^if \(\$forbiddenBundleFiles\.Count -ne 0\)'
}, $true))
Assert-Fixture ($scanEnd.Count -eq 1) 'Expected one final forbidden-payload rejection.'
Assert-Fixture ($scanStart.Parent -eq $scanEnd[0].Parent) 'Scan boundaries must share the builder statement block.'
$scanText = $builderText.Substring($scanStart.Extent.StartOffset,
    $scanEnd[0].Extent.EndOffset - $scanStart.Extent.StartOffset)
$actualScan = [scriptblock]::Create($scanText)

# Keep this pre-optimization reference fixed: three independent enumerations and
# the separate main-EXE marker call. The real helpers/policies are shared so this
# tests scan coverage, not an alternate implementation of privacy validation.
$oldThreePassScan = {
    $privateMarkers = @($ProjectRoot, $env:USERPROFILE, ('private-' + 'beta-releases'))
    Assert-NoTextMarker -Path $bundleExecutable -Markers $privateMarkers
    $appLibrary = Join-Path $BundleDirectory 'data\app.so'
    if (Test-Path -LiteralPath $appLibrary -PathType Leaf) {
        Assert-NoTextMarker -Path $appLibrary -Markers $privateMarkers
    }
    $native = @(Get-ChildItem -LiteralPath $BundleDirectory -Recurse -File |
        Where-Object { $_.Extension -in @('.exe', '.dll') })
    foreach ($payload in $native) {
        Assert-NoTextMarker -Path $payload.FullName -Markers $privateMarkers
    }
    $text = @(Get-ChildItem -LiteralPath $BundleDirectory -Recurse -File |
        Where-Object {
            $_.Length -le 32MB -and $_.Extension -in @(
                '.json', '.md', '.txt', '.html', '.css', '.js', '.mjs', '.py',
                '.yaml', '.yml', '.xml', '.config', '.ini', '.toml')
        })
    foreach ($payload in $text) {
        Assert-NoTextMarker -Path $payload.FullName -Markers $privateMarkers
    }
    $forbidden = @(Get-ChildItem -LiteralPath $BundleDirectory -Recurse -File |
        Where-Object {
            $_.FullName -match $ForbiddenPackagedArtifactPattern -or
            $_.Name -match '(?i)\.pdb(?:$|[.-])' -or
            (Test-SqliteFileHeader -Path $_.FullName)
        })
    if ($forbidden.Count -ne 0) {
        throw "The application bundle contains a personal, diagnostic, or temporary file: $($forbidden[0].FullName)"
    }
}

# Wrap calls for evidence while retaining the actual builder check bodies.
$script:actualMarkerCheck = (Get-Item Function:\Assert-NoTextMarker).ScriptBlock
$script:actualSqliteCheck = (Get-Item Function:\Test-SqliteFileHeader).ScriptBlock
function Assert-NoTextMarker {
    param([string]$Path, [string[]]$Markers, [switch]$AllowReviewedVelopackBuildPaths)
    $script:markerPaths.Add([IO.Path]::GetFullPath($Path))
    & $script:actualMarkerCheck @PSBoundParameters
}
function Test-SqliteFileHeader {
    param([string]$Path)
    $script:sqlitePaths.Add([IO.Path]::GetFullPath($Path))
    & $script:actualSqliteCheck @PSBoundParameters
}
function Get-ChildItem {
    [CmdletBinding()]
    param([string]$LiteralPath, [switch]$Recurse, [switch]$File)
    Assert-Fixture ($LiteralPath -ceq $BundleDirectory -and $Recurse -and $File) 'Enumeration must remain limited to fixture bundle files.'
    $script:enumerations++
    Microsoft.PowerShell.Management\Get-ChildItem @PSBoundParameters
}
function Write-FixtureFile([string]$Path, [string]$Text, [switch]$Utf16) {
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    $encoding = [Text.UTF8Encoding]::new($false)
    if ($Utf16) { $encoding = [Text.UnicodeEncoding]::new($false, $false) }
    [IO.File]::WriteAllText($Path, $Text, $encoding)
}
function New-FixtureBundle([string]$Name) {
    $directory = Join-Path $fixtureRoot $Name
    $null = [IO.Directory]::CreateDirectory($directory)
    Write-FixtureFile (Join-Path $directory 'Fixture.exe') 'synthetic executable bytes'
    return $directory
}
function Set-FixtureLength([string]$Path, [long]$Length) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Write)
    try { $stream.SetLength($Length) }
    finally { $stream.Dispose() }
}
function Invoke-FixtureScan([scriptblock]$Scan, [string]$Directory) {
    $BundleDirectory = $Directory
    $bundleExecutable = Join-Path $Directory 'Fixture.exe'
    $ProjectRoot = Join-Path $fixtureRoot 'synthetic-project'
    $script:enumerations = 0
    $script:markerPaths = [Collections.Generic.List[string]]::new()
    $script:sqlitePaths = [Collections.Generic.List[string]]::new()
    $failure = $null
    try { & $Scan | Out-Null }
    catch { $failure = $_.Exception.Message }
    return [pscustomobject]@{
        Failure = $failure
        Enumerations = $script:enumerations
        MarkerPaths = @($script:markerPaths.ToArray())
        SqlitePaths = @($script:sqlitePaths.ToArray())
    }
}
function Get-UniquePaths([object[]]$Paths) {
    return (@($Paths | Sort-Object -Unique) -join "`n")
}
function Assert-BothScans([string]$Directory, [string]$RejectionPattern = '') {
    $oldResult = Invoke-FixtureScan $oldThreePassScan $Directory
    $newResult = Invoke-FixtureScan $actualScan $Directory
    if ($RejectionPattern) {
        Assert-Fixture ($null -ne $oldResult.Failure -and $oldResult.Failure -match $RejectionPattern) "Old scan must reject $Directory with $RejectionPattern; got $($oldResult.Failure)."
        Assert-Fixture ($null -ne $newResult.Failure -and $newResult.Failure -match $RejectionPattern) "Actual scan must reject $Directory with $RejectionPattern; got $($newResult.Failure)."
        Assert-Fixture ($newResult.Enumerations -le 1) 'Failing actual scan must never enumerate more than once.'
    }
    else {
        Assert-Fixture ($null -eq $oldResult.Failure) "Old scan must accept fixture: $($oldResult.Failure)."
        Assert-Fixture ($null -eq $newResult.Failure) "Actual scan must accept fixture: $($newResult.Failure)."
        Assert-Fixture ($oldResult.Enumerations -eq 3) 'Historical reference must enumerate three times.'
        Assert-Fixture ($newResult.Enumerations -eq 1) 'Actual scan must enumerate once.'
        Assert-Fixture ((Get-UniquePaths $oldResult.MarkerPaths) -ceq (Get-UniquePaths $newResult.MarkerPaths)) 'Unique private-marker coverage must match historical scan.'
        Assert-Fixture ((Get-UniquePaths $oldResult.SqlitePaths) -ceq (Get-UniquePaths $newResult.SqlitePaths)) 'Unique SQLite-header coverage must match historical scan.'
        $mainExe = Join-Path $Directory 'Fixture.exe'
        Assert-Fixture (@($oldResult.MarkerPaths | Where-Object { $_ -ceq $mainExe }).Count -eq 2) 'Historical main EXE must be checked twice.'
        Assert-Fixture (@($newResult.MarkerPaths | Where-Object { $_ -ceq $mainExe }).Count -eq 1) 'Actual main EXE must be checked once.'
    }
    return $newResult
}

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\', '/'))
$fixtureRoot = Join-Path $tempParent ('bsl-payload-scan-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($fixtureRoot)
try {
    $ordinary = New-FixtureBundle 'ordinary'
    $expectedMarkers = @('Fixture.exe', 'nested\helper.DLL', 'data\app.so')
    foreach ($relative in @('nested\helper.DLL', 'data\app.so', 'icons\ordinary.png', 'data\reference.bin', 'data\short.bin', 'data\empty.bin')) {
        Write-FixtureFile (Join-Path $ordinary $relative) 'synthetic product content'
    }
    Set-FixtureLength (Join-Path $ordinary 'data\short.bin') 3
    Set-FixtureLength (Join-Path $ordinary 'data\empty.bin') 0
    foreach ($extension in @('json', 'md', 'txt', 'html', 'css', 'js', 'mjs', 'py', 'yaml', 'yml', 'xml', 'config', 'ini', 'toml', 'JSON')) {
        $relative = 'content\record-' + $expectedMarkers.Count + '.' + $extension
        Write-FixtureFile (Join-Path $ordinary $relative) 'synthetic reference text'
        $expectedMarkers += $relative
    }
    $ordinaryResult = Assert-BothScans $ordinary
    $expectedMarkerPaths = @($expectedMarkers | ForEach-Object { Join-Path $ordinary $_ })
    Assert-Fixture ((Get-UniquePaths $ordinaryResult.MarkerPaths) -ceq (Get-UniquePaths $expectedMarkerPaths)) 'All 14 text extensions, uppercase extension, native files and app.so must be scanned.'
    Assert-Fixture ($ordinaryResult.SqlitePaths.Count -eq ($expectedMarkerPaths.Count + 4)) 'Every ordinary file, including binary, empty and short files, must get a SQLite-header check.'
    Assert-Fixture ($ordinaryResult.MarkerPaths.Count -eq $expectedMarkerPaths.Count) 'No marker-eligible ordinary file may be scanned twice.'

    foreach ($case in @(
        @{ Name = 'private-main'; Path = 'Fixture.exe'; Utf16 = $false },
        @{ Name = 'private-nested-dll'; Path = 'nested\helper.dll'; Utf16 = $true },
        @{ Name = 'private-app-library'; Path = 'data\app.so'; Utf16 = $false },
        @{ Name = 'private-text'; Path = 'content\catalog.json'; Utf16 = $true }
    )) {
        $directory = New-FixtureBundle $case.Name
        Write-FixtureFile (Join-Path $directory $case.Path) 'synthetic private-beta-releases marker' -Utf16:$case.Utf16
        $null = Assert-BothScans $directory 'private-machine marker'
    }
    $hiddenMain = New-FixtureBundle 'private-hidden-main'
    $hiddenExecutable = Join-Path $hiddenMain 'Fixture.exe'
    Write-FixtureFile $hiddenExecutable 'synthetic private-beta-releases marker'
    [IO.File]::SetAttributes($hiddenExecutable, ([IO.File]::GetAttributes($hiddenExecutable) -bor [IO.FileAttributes]::Hidden))
    $hiddenResult = Assert-BothScans $hiddenMain 'private-machine marker'
    Assert-Fixture (@($hiddenResult.MarkerPaths | Where-Object { $_ -ceq $hiddenExecutable }).Count -eq 1) 'Explicit main-EXE check must reject hidden main payloads exactly once.'
    $absolutePath = New-FixtureBundle 'absolute-machine-path'
    Write-FixtureFile (Join-Path $absolutePath 'content\catalog.txt') 'C:\Users\SyntheticPublisher\private-build'
    $null = Assert-BothScans $absolutePath 'absolute user/private workspace path'

    foreach ($relative in @('webview2\state.bin', 'session-import-inbox\receipt.bin', 'planner-state.json', 'helper.pdb', 'helper.pdb.backup', 'diagnostic.log', 'data\storage.sqlite3')) {
        $directory = New-FixtureBundle ('forbidden-' + [Guid]::NewGuid().ToString('N'))
        Write-FixtureFile (Join-Path $directory $relative) 'synthetic forbidden payload'
        $null = Assert-BothScans $directory 'personal, diagnostic, or temporary file'
    }
    $disguised = New-FixtureBundle 'disguised-sqlite'
    Write-FixtureFile (Join-Path $disguised 'images\ordinary.png') "SQLite format 3`0synthetic database"
    $null = Assert-BothScans $disguised 'personal, diagnostic, or temporary file'

    # Preserve the current <=32 MiB text policy, including its above-limit
    # exclusion; do not silently claim those larger text files are marker-scanned.
    foreach ($length in @((32MB - 1), 32MB, (32MB + 1))) {
        $directory = New-FixtureBundle ('text-size-' + $length)
        $largeText = Join-Path $directory 'content\large.txt'
        Write-FixtureFile $largeText 'private-beta-releases'
        Set-FixtureLength $largeText $length
        if ($length -le 32MB) {
            $null = Assert-BothScans $directory 'private-machine marker'
        }
        else {
            $aboveLimit = Assert-BothScans $directory
            Assert-Fixture (@($aboveLimit.MarkerPaths | Where-Object { $_ -ceq $largeText }).Count -eq 0) 'Above-limit text must retain historical marker-scan exclusion.'
            Assert-Fixture (@($aboveLimit.SqlitePaths | Where-Object { $_ -ceq $largeText }).Count -eq 1) 'Above-limit text must still get its SQLite-header check.'
            Write-FixtureFile $largeText "SQLite format 3`0synthetic database"
            Set-FixtureLength $largeText $length
            $null = Assert-BothScans $directory 'personal, diagnostic, or temporary file'
        }
    }
    Write-Host "PASS: $script:assertions payload scan assertions on PowerShell $($PSVersionTable.PSVersion)."
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixtureRoot)
    if ($resolved.StartsWith($tempParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolved) -match '^bsl-payload-scan-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
    }
    else { throw 'Refusing cleanup outside the validated payload fixture directory.' }
}
