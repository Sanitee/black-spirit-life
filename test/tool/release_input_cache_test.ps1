[CmdletBinding()]
param([string]$ResultsPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../tool/release/verified_input_cache.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('bsl-release-cache-tests-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($testRoot)
$results = [Collections.Generic.List[object]]::new()

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Reject([scriptblock]$Action, [string]$Pattern) {
    $rejected = $false
    try { & $Action | Out-Null }
    catch {
        $rejected = $true
        if ($_.Exception.Message -notmatch $Pattern) { throw "Wrong rejection: $($_.Exception.Message)" }
    }
    Assert-True $rejected "Expected rejection: $Pattern"
}
function New-Case([string]$Name) {
    $root = Join-Path $testRoot $Name
    $null = [IO.Directory]::CreateDirectory($root)
    $bytes = [Text.Encoding]::UTF8.GetBytes('verified-release-fixture')
    $source = Join-Path $root 'source.bin'
    [IO.File]::WriteAllBytes($source, $bytes)
    return @{
        CacheRoot = Join-Path $root 'cache'
        Repository = 'https://github.com/example/release-fixture'
        ReleaseTag = 'v1.0.0'
        Channel = 'win-x64-stable'
        Role = 'previous-full'
        ArtifactName = 'Example-1.0.0-win-x64-stable-full.nupkg'
        ExpectedBytes = $bytes.Length
        ExpectedSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
        Destination = Join-Path $root 'destination.bin'
        ExistingFile = $source
        ValidateContent = { param($Path)
            if ([IO.File]::ReadAllText($Path) -cne 'verified-release-fixture') { throw 'Wrong payload identity' }
        }
        RetryDelaySeconds = 0
    }
}
function Run-Case([string]$Name, [scriptblock]$Body) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    & $Body
    $watch.Stop()
    $results.Add([ordered]@{ name = $Name; outcome = 'passed'; milliseconds = $watch.ElapsedMilliseconds })
    Write-Output "PASS $Name"
}

try {
    Run-Case 'import then warm offline reuse; zero downloads' {
        $p = New-Case 'warm'
        $p.Download = { throw 'NETWORK MUST NOT RUN' }
        $first = Get-VerifiedReleaseInput @p -Offline
        Assert-True ($first.cacheStatus -eq 'imported' -and $first.downloadedBytes -eq 0) 'Import was not offline'
        $p.Remove('ExistingFile')
        $p.Destination = Join-Path (Split-Path $p.Destination) 'second.bin'
        $second = Get-VerifiedReleaseInput @p -Offline
        Assert-True ($second.cacheStatus -eq 'hit' -and $second.attempts -eq 0) 'Warm input downloaded again'
        Assert-True ((Get-FileHash -LiteralPath $p.Destination).Hash -eq $p.ExpectedSha256) 'Independent copy differs'
    }
    Run-Case 'same-size cached corruption is rejected and retained' {
        $p = New-Case 'corrupt'
        $result = Get-VerifiedReleaseInput @p -Offline
        $entry = Join-Path $p.CacheRoot ($result.cacheKey + '.input')
        $changed = [IO.File]::ReadAllBytes($entry); $changed[0] = 88
        [IO.File]::WriteAllBytes($entry, $changed)
        $p.Download = { throw 'NETWORK MUST NOT RUN' }
        Assert-Reject { Get-VerifiedReleaseInput @p } 'SHA-256 mismatch'
        Assert-True ([IO.File]::ReadAllBytes($entry)[0] -eq 88) 'Corruption silently overwritten'
    }
    Run-Case 'repository tag channel role and name partition the cache' {
        $p = New-Case 'identity'
        Get-VerifiedReleaseInput @p -Offline | Out-Null
        $p.Remove('ExistingFile')
        foreach ($key in @('Repository', 'ReleaseTag', 'Channel', 'Role', 'ArtifactName')) {
            $q = $p.Clone()
            $q[$key] = if ($key -eq 'Repository') { 'https://github.com/another/release-fixture' } else { $q[$key] + '-different' }
            $q.Destination = Join-Path (Split-Path $p.Destination) ($key + '.bin')
            Assert-Reject { Get-VerifiedReleaseInput @q -Offline } 'not cached'
        }
    }
    Run-Case 'transport failure retries only download and never consumes partial' {
        $p = New-Case 'retry'
        $source = $p.ExistingFile; $p.Remove('ExistingFile')
        $counter = @{ calls = 0 }
        $p.Download = {
            param($Uri, $Path)
            $counter.calls++
            if ($counter.calls -eq 1) {
                [IO.File]::WriteAllText($Path, 'partial')
                throw [TimeoutException]::new('Injected timeout')
            }
            [IO.File]::Copy($source, $Path)
        }.GetNewClosure()
        $r = Get-VerifiedReleaseInput @p
        Assert-True ($r.attempts -eq 2 -and $counter.calls -eq 2) 'Retry count wrong'
        Assert-True ($r.downloadedBytes -eq ($p.ExpectedBytes + 7)) 'Transfer accounting wrong'
        Assert-True (@(Get-ChildItem -LiteralPath $p.CacheRoot -Filter '*.input').Count -eq 1) 'Partial accepted as complete'
    }
    Run-Case 'successful truncated download is integrity failure not retry' {
        $p = New-Case 'truncated'; $p.Remove('ExistingFile')
        $counter = @{ calls = 0 }
        $p.Download = { param($Uri, $Path) $counter.calls++; [IO.File]::WriteAllText($Path, 'short') }.GetNewClosure()
        Assert-Reject { Get-VerifiedReleaseInput @p } 'size/type mismatch'
        Assert-True ($counter.calls -eq 1) 'Integrity failure was retried'
        Assert-True (@(Get-ChildItem -LiteralPath $p.CacheRoot -Filter '*.input').Count -eq 0) 'Corrupt content committed'
    }
    Run-Case 'changed validator rejects a hash-valid cached item' {
        $p = New-Case 'policy'
        Get-VerifiedReleaseInput @p -Offline | Out-Null
        $p.ValidateContent = { param($Path) throw 'Wrong channel inside package' }
        Assert-Reject { Get-VerifiedReleaseInput @p -Offline } 'Wrong channel'
    }
    Run-Case 'content identity failure cannot populate cache' {
        $p = New-Case 'content'
        $p.ValidateContent = { param($Path) throw 'Wrong package version' }
        Assert-Reject { Get-VerifiedReleaseInput @p -Offline } 'Wrong package version'
        Assert-True (@(Get-ChildItem -LiteralPath $p.CacheRoot -Filter '*.input').Count -eq 0) 'Identity failure cached'
    }
    Run-Case 'competing key writer is excluded' {
        $p = New-Case 'concurrent'
        $source = $p.ExistingFile; $p.Remove('ExistingFile')
        $nested = $p.Clone()
        $nested.Destination = Join-Path (Split-Path $p.Destination) 'nested.bin'
        $nested.Download = { throw 'Nested transport must not run' }
        $p.Download = {
            param($Uri, $Path)
            Assert-Reject { Get-VerifiedReleaseInput @nested } 'locked or unavailable'
            [IO.File]::Copy($source, $Path)
        }.GetNewClosure()
        Get-VerifiedReleaseInput @p | Out-Null
    }
    Run-Case 'invalid identity and redirected cache paths fail before writes' {
        $p = New-Case 'paths'
        $q = $p.Clone(); $q.ArtifactName = '../outside.bin'
        Assert-Reject { Get-VerifiedReleaseInput @q } 'traversal'
        Assert-True (-not (Test-Path -LiteralPath $p.CacheRoot)) 'Invalid identity wrote cache'
        $outside = Join-Path (Split-Path $p.Destination) 'outside'
        $null = [IO.Directory]::CreateDirectory($outside)
        $link = Join-Path (Split-Path $p.Destination) 'link'
        New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
        $p.CacheRoot = Join-Path $link 'cache'
        Assert-Reject { Get-VerifiedReleaseInput @p } 'reparse point'
        Assert-True (@(Get-ChildItem -LiteralPath $outside).Count -eq 0) 'Wrote through redirected path'
    }
    Run-Case 'existing destination conflict is never overwritten' {
        $p = New-Case 'destination'
        [IO.File]::WriteAllText($p.Destination, 'keep-me')
        Assert-Reject { Get-VerifiedReleaseInput @p -Offline } 'size/type mismatch'
        Assert-True ([IO.File]::ReadAllText($p.Destination) -eq 'keep-me') 'Existing destination changed'
    }
    Run-Case 'retry exhaustion leaves no complete cache input' {
        $p = New-Case 'exhaustion'; $p.Remove('ExistingFile')
        $counter = @{ calls = 0 }
        $p.Download = { param($Uri, $Path) $counter.calls++; throw [TimeoutException]::new('Injected timeout') }.GetNewClosure()
        Assert-Reject { Get-VerifiedReleaseInput @p } 'Injected timeout'
        Assert-True ($counter.calls -eq 3) 'Transport retry bound changed'
        Assert-True (@(Get-ChildItem -LiteralPath $p.CacheRoot -Filter '*.input').Count -eq 0) 'Incomplete entry committed'
    }
    Run-Case 'nontransient transport error is not retried' {
        $p = New-Case 'permanent'; $p.Remove('ExistingFile')
        $counter = @{ calls = 0 }
        $p.Download = { param($Uri, $Path) $counter.calls++; throw 'Permanent request rejection' }.GetNewClosure()
        Assert-Reject { Get-VerifiedReleaseInput @p } 'Permanent request rejection'
        Assert-True ($counter.calls -eq 1) 'Permanent error retried'
    }
    if (-not [string]::IsNullOrWhiteSpace($ResultsPath)) {
        [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultsPath), ([ordered]@{
            schemaVersion = 1; shell = $PSVersionTable.PSVersion.ToString()
            tests = $results.ToArray(); passed = $true; fixtureRoot = $testRoot
        } | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    }
    Write-Output "$($results.Count) cache tests passed; fixtures retained at $testRoot"
}
catch { Write-Error $_; exit 1 }
