Set-StrictMode -Version Latest

function Assert-ReleaseOrdinaryPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        throw 'Release input paths must be absolute.'
    }
    $full = [System.IO.Path]::GetFullPath($Path)
    $current = $full
    while (-not [string]::IsNullOrEmpty($current)) {
        try {
            $attributes = [System.IO.File]::GetAttributes($current)
            if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Release input path crosses a reparse point: $current"
            }
        }
        catch [System.IO.FileNotFoundException] { }
        catch [System.IO.DirectoryNotFoundException] { }
        $parent = [System.IO.Directory]::GetParent($current)
        $current = if ($null -eq $parent) { $null } else { $parent.FullName }
    }
    return $full
}

function Assert-ReleaseInputContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][long]$ExpectedBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][scriptblock]$ValidateContent
    )
    $full = Assert-ReleaseOrdinaryPath -Path $Path
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if ($item.PSIsContainer -or $item.Length -ne $ExpectedBytes) {
        throw "Release input size/type mismatch: $full"
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $full -ErrorAction Stop).Hash
    if (-not $hash.Equals($ExpectedSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Release input SHA-256 mismatch: $full"
    }
    & $ValidateContent $full | Out-Null
}

function Test-ReleaseTransientDownloadError {
    param([Parameter(Mandatory = $true)]$ErrorRecord)
    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        if ($exception -is [System.TimeoutException]) { return $true }
        if ($null -ne $exception.PSObject.Properties['Response'] -and
            $null -ne $exception.Response -and
            $null -ne $exception.Response.PSObject.Properties['StatusCode']) {
            $status = [int]$exception.Response.StatusCode
            return $status -eq 408 -or $status -eq 429 -or $status -ge 500
        }
        if ($exception -is [System.Net.WebException]) {
            return $exception.Status -in @(
                [System.Net.WebExceptionStatus]::Timeout,
                [System.Net.WebExceptionStatus]::ConnectFailure,
                [System.Net.WebExceptionStatus]::ConnectionClosed,
                [System.Net.WebExceptionStatus]::ReceiveFailure,
                [System.Net.WebExceptionStatus]::NameResolutionFailure
            )
        }
        if ($exception.GetType().FullName -eq 'System.Net.Http.HttpRequestException') { return $true }
        $exception = $exception.InnerException
    }
    return $false
}

function Get-VerifiedReleaseInput {
    <# Historical pinned inputs only. This is never a current public-feed check.
       Partial/corrupt files are retained, never consumed or silently replaced.
       Content validation is mandatory on cache hits, imports and downloads. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CacheRoot,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$ReleaseTag,
        [Parameter(Mandatory = $true)][string]$Channel,
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][string]$ArtifactName,
        [Parameter(Mandatory = $true)][long]$ExpectedBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][scriptblock]$ValidateContent,
        [string]$ExistingFile,
        [switch]$Offline,
        [ValidateRange(1, 5)][int]$MaxAttempts = 3,
        [ValidateRange(0, 10)][int]$RetryDelaySeconds = 2,
        [scriptblock]$Download = {
            param($Uri, $Path)
            Invoke-WebRequest -Uri $Uri -OutFile $Path -UseBasicParsing -ErrorAction Stop | Out-Null
        }
    )
    if ($Repository -cnotmatch '^https://github\.com/[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$') {
        throw 'The cache requires the canonical GitHub repository base URL.'
    }
    foreach ($part in @($ReleaseTag, $Channel, $Role, $ArtifactName)) {
        if ($part -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,179}$' -or $part.EndsWith('.')) {
            throw 'Invalid release input identity; directory traversal is not allowed.'
        }
    }
    if ($ExpectedBytes -le 0 -or $ExpectedSha256 -cnotmatch '^[0-9a-fA-F]{64}$') {
        throw 'Release input requires a positive byte count and complete SHA-256.'
    }
    $cache = Assert-ReleaseOrdinaryPath -Path $CacheRoot
    if ($cache.TrimEnd('\', '/') -eq [System.IO.Path]::GetPathRoot($cache).TrimEnd('\', '/')) {
        throw 'A volume root cannot be used as the release cache.'
    }
    $destinationPath = Assert-ReleaseOrdinaryPath -Path $Destination
    $destinationParent = Split-Path -Parent $destinationPath
    if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
        throw 'Create the isolated candidate input directory before acquiring inputs.'
    }
    # Length-prefixing avoids ambiguous tuple encodings; the case-sensitive tag
    # and artifact name remain distinct even though repository identity folds.
    $parts = @('release-input-cache-v1', $Repository.ToLowerInvariant(), $ReleaseTag,
        $Channel, $Role, $ArtifactName, $ExpectedBytes.ToString([cultureinfo]::InvariantCulture),
        $ExpectedSha256.ToLowerInvariant())
    $identity = ($parts | ForEach-Object { "$($_.Length):$_" }) -join ''
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $key = [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity))).Replace('-', '').ToLowerInvariant()
    }
    finally { $hasher.Dispose() }
    $null = [System.IO.Directory]::CreateDirectory($cache)
    $null = Assert-ReleaseOrdinaryPath -Path $cache
    $entry = Join-Path $cache "$key.input"
    $lockPath = Join-Path $cache "$key.lock"
    $null = Assert-ReleaseOrdinaryPath -Path $entry
    $null = Assert-ReleaseOrdinaryPath -Path $lockPath
    if ($destinationPath.Equals($entry, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The candidate input must be an independent copy outside the cache entry.'
    }
    try {
        $lease = [System.IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    }
    catch { throw "Release input is locked or unavailable; another run may own this cache key: $key" }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $status = 'hit'
    $attempts = 0
    $downloadedBytes = 0L
    $validation = @{
        ExpectedBytes = $ExpectedBytes
        ExpectedSha256 = $ExpectedSha256
        ValidateContent = $ValidateContent
    }
    try {
        if (Test-Path -LiteralPath $entry) {
            # Fail closed on corrupt entries. Never turn an integrity failure
            # into an automatic overwrite/retry under the same cache identity.
            Assert-ReleaseInputContent -Path $entry @validation
        }
        else {
            if (-not [string]::IsNullOrWhiteSpace($ExistingFile)) {
                $source = Assert-ReleaseOrdinaryPath -Path $ExistingFile
                Assert-ReleaseInputContent -Path $source @validation
                $partial = Join-Path $cache "$key.partial-$([Guid]::NewGuid().ToString('N'))"
                [IO.File]::Copy($source, $partial, $false)
                $status = 'imported'
            }
            else {
                if ($Offline) { throw 'Pinned release input is not cached; offline acquisition cannot continue.' }
                $uri = "$Repository/releases/download/$ReleaseTag/$ArtifactName"
                $status = 'downloaded'
                for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
                    $attempts = $attempt
                    $partial = Join-Path $cache "$key.partial-$([Guid]::NewGuid().ToString('N'))"
                    try { & $Download $uri $partial | Out-Null }
                    catch {
                        if (Test-Path -LiteralPath $partial -PathType Leaf) {
                            $downloadedBytes += (Get-Item -LiteralPath $partial -Force).Length
                        }
                        if ($attempt -ge $MaxAttempts -or -not (Test-ReleaseTransientDownloadError $_)) { throw }
                        if ($RetryDelaySeconds -gt 0) { Start-Sleep -Seconds $RetryDelaySeconds }
                        continue
                    }
                    if (Test-Path -LiteralPath $partial -PathType Leaf) {
                        $downloadedBytes += (Get-Item -LiteralPath $partial -Force).Length
                    }
                    break
                }
            }
            # Validation is deliberately outside the transport retry handler.
            Assert-ReleaseInputContent -Path $partial @validation
            $null = Assert-ReleaseOrdinaryPath -Path $entry
            [IO.File]::Move($partial, $entry)
        }
        $null = Assert-ReleaseOrdinaryPath -Path $destinationPath
        if (Test-Path -LiteralPath $destinationPath) {
            Assert-ReleaseInputContent -Path $destinationPath @validation
        }
        else {
            [IO.File]::Copy($entry, $destinationPath, $false)
            Assert-ReleaseInputContent -Path $destinationPath @validation
        }
        $watch.Stop()
        return [pscustomobject]@{
            schemaVersion = 1
            role = $Role
            cacheKey = $key
            cacheStatus = $status
            attempts = $attempts
            downloadedBytes = $downloadedBytes
            bytes = $ExpectedBytes
            sha256 = $ExpectedSha256.ToUpperInvariant()
            elapsedMilliseconds = $watch.ElapsedMilliseconds
        }
    }
    finally { $watch.Stop(); $lease.Dispose() }
}
