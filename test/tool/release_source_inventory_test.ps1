[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $projectRoot 'tool\release\source_inventory.ps1')
$verifierPath = Join-Path $projectRoot 'tool\verify_production_source.ps1'
$shellPath = (Get-Process -Id $PID).Path
$fixtureParent = Join-Path $projectRoot 'build\release-source-inventory-fixtures'
$fixtureRoot = Join-Path $fixtureParent ([guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixtureRoot -Force
$passed = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:passed++
}

function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    $message = $null
    try { & $Action | Out-Null }
    catch { $message = $_.Exception.Message }
    Assert-True ($null -ne $message -and $message -match $Pattern) `
        "Expected rejection matching '$Pattern'; received '$message'."
}

function Write-FixtureFile([string]$Root, [string]$Relative, [string]$Text = 'fixture') {
    $path = Join-Path $Root $Relative
    $null = [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
    [System.IO.File]::WriteAllText($path, $Text, [System.Text.UTF8Encoding]::new($false))
    return $path
}

function Invoke-FixtureGit([string]$Root, [string[]]$Arguments) {
    $output = @(& git -C $Root @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Fixture git failed: $($output -join ' ')" }
    return $output
}

function Invoke-FixtureVerifier([string]$Root) {
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $shellPath
    $start.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
        $verifierPath + '" -ProjectRoot "' + $Root + '"'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            # Windows PowerShell wraps formatted errors at the host width.
            Text = ("$stdout`n$stderr" -replace '\s+', ' ')
        }
    }
    finally { $process.Dispose() }
}

function Import-FixtureFunction([string]$Path, [string]$Name) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -ne 0) { throw "Cannot parse fixture function source: $Path" }
    $node = $ast.Find({ param($item)
        $item -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $item.Name -ceq $Name
    }.GetNewClosure(), $true)
    if ($null -eq $node) { throw "Missing fingerprint contract function: $Name" }
    $body = $node.Body.GetScriptBlock()
    if ($null -ne $node.Parameters -and $node.Parameters.Count -gt 0) {
        $parameterText = ($node.Parameters | ForEach-Object { $_.Extent.Text }) -join ', '
        $bodyText = $node.Body.Extent.Text
        $body = [scriptblock]::Create("param($parameterText)`n" + $bodyText.Substring(1, $bodyText.Length - 2))
    }
    Set-Item -LiteralPath "Function:script:$Name" -Value $body
}

try {
    $emptyRoot = Join-Path $fixtureRoot 'empty'
    $null = New-Item -ItemType Directory -Path $emptyRoot
    $emptyInventory = Get-ReleaseSourceInventory $emptyRoot ''
    Assert-True ($emptyInventory.Files.Count -eq 0 -and $emptyInventory.Directories.Count -eq 0 -and
        $emptyInventory.Metrics.VisitedDirectoryCount -eq 1) 'Empty source inventory has the wrong shape.'
    Assert-Throws { Get-ReleaseSourceInventory (Join-Path $fixtureRoot 'missing') '' } 'cannot enumerate directory'
    $narrowRoot = Join-Path $fixtureRoot 'narrow-policy'
    foreach ($terminalFile in @('build', 'bin', 'obj', 'windows/flutter/ephemeral')) {
        $null = Write-FixtureFile $narrowRoot $terminalFile ("SQLite format 3`0" + 'fixture')
    }
    $null = Write-FixtureFile $narrowRoot 'nested/build/omitted.txt'
    $narrowPattern = '(?i)(?:^|/)(?:\.git|\.dart_tool|build|bin|obj)/|(?:^|/)windows/flutter/ephemeral/'
    $narrowInventory = Get-ReleaseSourceInventory $narrowRoot $narrowPattern
    Assert-True ($narrowInventory.FilePaths.Count -eq 4 -and
        $narrowInventory.FilePaths -ccontains 'build' -and
        $narrowInventory.FilePaths -ccontains 'bin' -and
        $narrowInventory.FilePaths -ccontains 'obj' -and
        $narrowInventory.FilePaths -ccontains 'windows/flutter/ephemeral' -and
        $narrowInventory.Metrics.PrunedDirectoryCount -eq 1) 'Subtree exclusions hid same-named ordinary files or failed to prune generated directories.'
    Import-FixtureFunction $verifierPath 'Test-SqliteFileHeader'
    foreach ($terminalFile in $narrowInventory.Files) {
        Assert-True (Test-SqliteFileHeader $terminalFile.FullName) 'A terminal generated-looking filename bypassed SQLite inspection.'
    }
    $source = Join-Path $fixtureRoot 'source'
    $null = New-Item -ItemType Directory -Path $source
    $null = Write-FixtureFile $source 'tracked.txt' 'tracked'
    $dirtyPath = Write-FixtureFile $source 'dirty.txt' 'before'
    $null = Invoke-FixtureGit $source @('init', '--quiet')
    $null = Invoke-FixtureGit $source @('-c', 'core.autocrlf=false', 'add', '--', 'tracked.txt', 'dirty.txt')
    [System.IO.File]::WriteAllText($dirtyPath, 'after!')
    $null = Write-FixtureFile $source 'lib\untracked-helper.ps1'
    $null = Write-FixtureFile $source 'assets\untracked reference.json' '{"reference":true}'
    $null = Write-FixtureFile $source 'defaults.json' '{"mastery":0}'
    $hiddenPath = Write-FixtureFile $source '.hidden-personal.json' '{"private":true}'
    [System.IO.File]::SetAttributes($hiddenPath, [System.IO.FileAttributes]::Hidden)
    $unicodeRelative = 'assets/' + [char]0x00e4 + '-' + [char]0x65e5 + '.txt'
    $null = Write-FixtureFile $source $unicodeRelative
    $null = Write-FixtureFile $source 'assets\Z.txt'
    $null = Write-FixtureFile $source 'assets\I.txt'
    $null = Write-FixtureFile $source 'assets\i-lower.txt'
    $null = Write-FixtureFile $source 'nested\build\a\b\c\d\e\f\never.txt'
    $null = Write-FixtureFile $source 'nested\src\obj\a\b\c\never.txt'
    $null = Write-FixtureFile $source '.flutter-plugins-dependencies'
    $pattern = '(?i)(?:^|/)(?:\.git|build|obj|\.flutter-plugins-dependencies)(?:/|$)'

    $inventory = Get-ReleaseSourceInventory -RootPath $source -ExcludedPathPattern $pattern
    $legacyPaths = [System.Collections.Generic.List[string]]::new()
    Get-ChildItem -LiteralPath $source -Recurse -File -Force -ErrorAction Stop | ForEach-Object {
        $relative = $_.FullName.Substring($source.Length + 1).Replace('\', '/')
        if ($relative -notmatch $pattern) { $legacyPaths.Add($relative) }
    }
    $legacyPaths.Sort([System.StringComparer]::Ordinal)
    Assert-True (($inventory.FilePaths -join "`n") -ceq ($legacyPaths -join "`n")) 'The intended old and pruned inventories differ.'
    Assert-True ($inventory.SchemaVersion -eq 1) 'Inventory schema is not explicit.'
    Assert-True ($inventory.FilePaths -ccontains 'dirty.txt' -and
        $inventory.FilePaths -ccontains 'lib/untracked-helper.ps1' -and
        $inventory.FilePaths -ccontains 'assets/untracked reference.json' -and
        $inventory.FilePaths -ccontains 'defaults.json' -and
        $inventory.FilePaths -ccontains '.hidden-personal.json' -and
        $inventory.FilePaths -ccontains $unicodeRelative) 'Working-tree or hidden content was omitted.'
    Assert-True (@(Invoke-FixtureGit $source @('diff', '--name-only')).Count -eq 1) 'The fixture must have a dirty tracked file.'
    Assert-True (@(Invoke-FixtureGit $source @('ls-files', '--others', '--exclude-standard')).Count -gt 0) 'The fixture must have untracked production files.'
    Assert-True ($inventory.Metrics.PrunedDirectoryCount -eq 3 -and
        $inventory.Metrics.PrunedFileCount -eq 1 -and
        $inventory.Metrics.VisitedDirectoryCount -eq 5 -and
        $inventory.Metrics.VisitedFileCount -eq $inventory.Files.Count) 'Traversal/pruning metrics are wrong.'

    $originalEnumerator = (Get-Item Function:\Get-ReleaseInventoryDirectoryEntries).ScriptBlock
    $script:visitedFixturePaths = [System.Collections.Generic.List[string]]::new()
    try {
        Set-Item Function:\Get-ReleaseInventoryDirectoryEntries -Value {
            param([System.IO.DirectoryInfo]$Directory)
            $script:visitedFixturePaths.Add($Directory.FullName)
            if ($Directory.FullName.Substring($source.Length) -match '\\(?:build|obj|\.git)(?:\\|$)') {
                throw 'Unreadable excluded child was incorrectly visited.'
            }
            $Directory.GetFileSystemInfos()
        }
        $spyInventory = Get-ReleaseSourceInventory -RootPath $source -ExcludedPathPattern $pattern
        Assert-True ($script:visitedFixturePaths.Count -eq 5 -and
            $spyInventory.Metrics.VisitedDirectoryCount -eq 5) 'Traversal spy entered an excluded tree.'
    }
    finally { Set-Item Function:\Get-ReleaseInventoryDirectoryEntries -Value $originalEnumerator }
    try {
        Set-Item Function:\Get-ReleaseInventoryDirectoryEntries -Value {
            param([System.IO.DirectoryInfo]$Directory)
            [System.IO.FileInfo]::new((Join-Path $fixtureRoot 'outside.txt'))
        }
        Assert-Throws { Get-ReleaseSourceInventory $source $pattern } 'outside the enumerated directory'
    }
    finally { Set-Item Function:\Get-ReleaseInventoryDirectoryEntries -Value $originalEnumerator }

    $savedCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
    try {
        foreach ($culture in @('en-US', 'de-DE', 'tr-TR', 'sv-SE')) {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($culture)
            $localized = Get-ReleaseSourceInventory -RootPath $source.Replace('\', '/') -ExcludedPathPattern $pattern
            Assert-True (($localized.FilePaths -join "`n") -ceq ($inventory.FilePaths -join "`n")) "Ordinal path ordering changed under $culture."
            Assert-True (($localized.DirectoryPaths -join "`n") -ceq ($inventory.DirectoryPaths -join "`n")) "Ordinal directory ordering changed under $culture."
        }
    }
    finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $savedCulture }

    # Read the real producer and consumer functions without invoking either build.
    $producer = Join-Path $projectRoot 'windows\session_import\build-publish.ps1'
    foreach ($name in @('Get-FullDirectoryPath', 'Get-FileSha256', 'Get-InventoryFingerprint')) {
        Import-FixtureFunction $producer $name
    }
    Import-FixtureFunction (Join-Path $projectRoot 'tool\build_stable_release_candidate.ps1') 'Get-SourceInventoryFingerprint'
    $producerHash = Get-InventoryFingerprint $inventory.Files $source
    $consumerHash = Get-SourceInventoryFingerprint -Files $inventory.Files -RootPath $source
    Assert-True ($producerHash -ceq $consumerHash) 'Existing helper producer and consumer fingerprints diverged.'
    $savedTimestamp = [System.IO.File]::GetLastWriteTimeUtc($dirtyPath)
    [System.IO.File]::SetLastWriteTimeUtc($dirtyPath, $savedTimestamp.AddMinutes(-5))
    Assert-True ((Get-SourceInventoryFingerprint $inventory.Files $source) -ceq $consumerHash) 'Timestamp-only change altered the content fingerprint.'
    [System.IO.File]::WriteAllText($dirtyPath, 'other!')
    [System.IO.File]::SetLastWriteTimeUtc($dirtyPath, $savedTimestamp)
    Assert-True ((Get-SourceInventoryFingerprint $inventory.Files $source) -cne $consumerHash) 'Same-length bytes with restored timestamp did not change the fingerprint.'
    $addedPath = Write-FixtureFile $source 'late-production.txt'
    $changedInventory = Get-ReleaseSourceInventory $source $pattern
    Assert-True ($changedInventory.Files.Count -eq $inventory.Files.Count + 1) 'Fresh enumeration missed an added source file.'
    [System.IO.File]::Delete($addedPath)
    $changedInventory = Get-ReleaseSourceInventory $source $pattern
    Assert-True ($changedInventory.Files.Count -eq $inventory.Files.Count) 'Fresh enumeration missed a removed source file.'

    $locked = [System.IO.File]::Open($dirtyPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try { Assert-Throws { Get-ReleaseSourceInventory $source $pattern } 'cannot inspect.*dirty\.txt' }
    finally { $locked.Dispose() }
    try {
        Set-Item Function:\Get-ReleaseInventoryDirectoryEntries -Value {
            param([System.IO.DirectoryInfo]$Directory)
            if ($Directory.Name -ceq 'lib') { throw [System.UnauthorizedAccessException]::new('Fixture access denied.') }
            $Directory.GetFileSystemInfos()
        }
        Assert-Throws { Get-ReleaseSourceInventory $source $pattern } 'cannot enumerate directory.*lib.*access denied'
    }
    finally { Set-Item Function:\Get-ReleaseInventoryDirectoryEntries -Value $originalEnumerator }
    try {
        Set-Item Function:\Get-ReleaseInventoryDirectoryEntries -Value {
            param([System.IO.DirectoryInfo]$Directory)
            $Directory.GetFileSystemInfos()
            if ($Directory.Name -ceq 'source') { [System.IO.FileInfo]::new((Join-Path $Directory.FullName 'TRACKED.txt')) }
        }
        Assert-Throws { Get-ReleaseSourceInventory $source $pattern } 'case/path collision'
    }
    finally { Set-Item Function:\Get-ReleaseInventoryDirectoryEntries -Value $originalEnumerator }

    $reparseTarget = Join-Path $fixtureRoot 'outside-source'
    $null = New-Item -ItemType Directory -Path $reparseTarget
    $reparsePath = Join-Path $source 'escape'
    $null = New-Item -ItemType Junction -Path $reparsePath -Target $reparseTarget
    try {
        Assert-Throws { Get-ReleaseSourceInventory $source $pattern } 'reparse points'
        Assert-Throws { Get-ReleaseSourceInventory $reparsePath '' } 'reparse points'
    }
    finally { [System.IO.Directory]::Delete($reparsePath, $false) }
    $excludedReparsePath = Join-Path $source 'nested\build\broken'
    $null = New-Item -ItemType Junction -Path $excludedReparsePath -Target $reparseTarget
    [System.IO.Directory]::Delete($reparseTarget, $false)
    try {
        $prunedBroken = Get-ReleaseSourceInventory $source $pattern
        Assert-True ($prunedBroken.Metrics.VisitedDirectoryCount -eq 5) 'A broken junction inside a pruned tree was visited.'
    }
    finally { [System.IO.Directory]::Delete($excludedReparsePath, $false) }

    # Run the actual privacy gate against synthetic required paths and state.
    $verificationRoot = Join-Path $fixtureRoot 'verification'
    $null = New-Item -ItemType Directory -Path $verificationRoot
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($verifierPath, [ref]$tokens, [ref]$errors)
    $requiredAssignment = $ast.Find({ param($item)
        $item -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $item.Left.Extent.Text -ceq '$requiredPaths'
    }, $true)
    $requiredStrings = $requiredAssignment.Right.FindAll({ param($item)
        $item -is [System.Management.Automation.Language.StringConstantExpressionAst]
    }, $true)
    foreach ($requiredString in $requiredStrings) {
        $relative = $requiredString.Value
        if ($relative -match '(?:\.json|\.txt|LICENSE)$') { $null = Write-FixtureFile $verificationRoot $relative }
        else { $null = New-Item -ItemType Directory -Path (Join-Path $verificationRoot $relative) -Force }
    }
    $null = Invoke-FixtureGit $verificationRoot @('init', '--quiet')
    $cleanResult = Invoke-FixtureVerifier $verificationRoot
    Assert-True ($cleanResult.ExitCode -eq 0) "Clean synthetic source failed privacy verification: $($cleanResult.Text)"
    $hiddenPersonal = Write-FixtureFile $verificationRoot '.black-spirit-life-profile.json' '{}'
    [System.IO.File]::SetAttributes($hiddenPersonal, [System.IO.FileAttributes]::Hidden)
    $privateResult = Invoke-FixtureVerifier $verificationRoot
    Assert-True ($privateResult.ExitCode -ne 0 -and $privateResult.Text -match 'personal-data database or record') 'Hidden personal state bypassed the real privacy gate.'
    [System.IO.File]::Delete($hiddenPersonal)
    $sqlite = Write-FixtureFile $verificationRoot 'innocent.dat' ("SQLite format 3`0" + 'fixture')
    $sqliteResult = Invoke-FixtureVerifier $verificationRoot
    Assert-True ($sqliteResult.ExitCode -ne 0 -and $sqliteResult.Text -match 'SQLite content is forbidden') "Renamed SQLite content bypassed the real privacy gate: $($sqliteResult.Text)"
    [System.IO.File]::Delete($sqlite)
    $generated = Write-FixtureFile $verificationRoot 'build\tracked-generated.dll'
    $null = Invoke-FixtureGit $verificationRoot @('add', '-f', '--', 'build/tracked-generated.dll')
    $trackedResult = Invoke-FixtureVerifier $verificationRoot
    Assert-True ($trackedResult.ExitCode -ne 0 -and $trackedResult.Text -match 'tracked generated output is forbidden') 'Tracked generated output bypassed its independent gate.'
    $null = Invoke-FixtureGit $verificationRoot @('rm', '--cached', '--quiet', '--', 'build/tracked-generated.dll')
    $requiredFile = Join-Path $verificationRoot 'assets\opportunities\icon-provenance.json'
    [System.IO.File]::Delete($requiredFile)
    $missingResult = Invoke-FixtureVerifier $verificationRoot
    Assert-True ($missingResult.ExitCode -ne 0 -and $missingResult.Text -match 'required exact-Beta production path is missing') 'Missing required content bypassed the real privacy gate.'

    Write-Output "PASS: $passed source inventory assertions; PowerShell $($PSVersionTable.PSVersion); visited=$($inventory.Metrics.VisitedDirectoryCount); pruned=$($inventory.Metrics.PrunedDirectoryCount); producer/consumer=$consumerHash"
}
finally {
    # Only this invocation's synthetic fixture is removable; never a checkout,
    # source tree, accepted artifact, or arbitrary caller-selected directory.
    $resolvedParent = [System.IO.Path]::GetFullPath($fixtureParent).TrimEnd('\') + '\'
    $resolvedFixture = [System.IO.Path]::GetFullPath($fixtureRoot)
    if (-not $resolvedFixture.StartsWith($resolvedParent, [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetFileName($resolvedFixture) -notmatch '^[0-9a-f]{32}$') {
        throw 'Refusing cleanup outside the generated fixture directory.'
    }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force -ErrorAction Stop
}
