# Source discovery only: callers retain their own exclusion and fingerprint rules.
# Re-enumerate and rehash whenever a writable source may have changed.

function Get-ReleaseInventoryDirectoryEntries {
    param([Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$Directory)

    # A single level includes hidden/system entries and fails on access errors.
    # This small boundary also permits deterministic traversal-failure fixtures.
    $Directory.GetFileSystemInfos()
}

function Get-ReleaseSourceInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$ExcludedPathPattern
    )

    $root = [System.IO.Path]::GetFullPath($RootPath)
    $rootDirectory = [System.IO.DirectoryInfo]::new($root)
    $root = $rootDirectory.FullName
    $rootPrefix = $root.TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
    $excluded = [System.Text.RegularExpressions.Regex]::new(
        $ExcludedPathPattern,
        ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
    )
    $filesByPath = [System.Collections.Generic.Dictionary[string, System.IO.FileInfo]]::new(
        [System.StringComparer]::Ordinal
    )
    $directoriesByPath = [System.Collections.Generic.Dictionary[string, System.IO.DirectoryInfo]]::new(
        [System.StringComparer]::Ordinal
    )
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $pending = [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
    $pending.Push($rootDirectory)
    $metrics = [pscustomobject]@{
        VisitedDirectoryCount = 0
        VisitedFileCount = 0
        PrunedDirectoryCount = 0
        PrunedFileCount = 0
        EnumeratedEntryCount = 0
    }

    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        $directoryRelative = '.'
        if (-not $directory.FullName.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            $directoryRelative = $directory.FullName.Substring($rootPrefix.Length).Replace('\', '/')
        }
        try {
            # Recheck queued directories before descent; never follow a reparse point.
            $attributes = [System.IO.File]::GetAttributes($directory.FullName)
            if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
                ($attributes -band [System.IO.FileAttributes]::Directory) -eq 0) {
                throw 'Expected an ordinary directory; reparse points are forbidden.'
            }
            $metrics.VisitedDirectoryCount++
            # Keep comparisons inside .NET: a PowerShell comparison callback
            # performs interpreter work for every O(n log n) sort comparison.
            $entriesByPath = [System.Collections.Generic.SortedDictionary[string, System.IO.FileSystemInfo]]::new(
                [System.StringComparer]::Ordinal
            )
            foreach ($entry in @(Get-ReleaseInventoryDirectoryEntries -Directory $directory -ErrorAction Stop)) {
                if ($entry -isnot [System.IO.FileSystemInfo]) {
                    throw 'Expected an ordinary filesystem entry.'
                }
                if ($entriesByPath.ContainsKey($entry.FullName)) {
                    throw 'Source inventory has a case/path collision.'
                }
                $entriesByPath.Add($entry.FullName, $entry)
            }
        }
        catch {
            throw "Source inventory cannot enumerate directory '$directoryRelative': $($_.Exception.Message)"
        }

        foreach ($entry in $entriesByPath.Values) {
            $metrics.EnumeratedEntryCount++
            if ($entry -isnot [System.IO.FileSystemInfo] -or
                -not $entry.FullName.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
                -not [System.IO.Path]::GetDirectoryName($entry.FullName).TrimEnd([char[]]@('\', '/')).Equals(
                    $directory.FullName.TrimEnd([char[]]@('\', '/')),
                    [System.StringComparison]::OrdinalIgnoreCase
                )) {
                throw "Source inventory encountered a path outside the enumerated directory '$directoryRelative'."
            }
            $relative = $entry.FullName.Substring($rootPrefix.Length).Replace('\', '/')
            # Match the caller's existing relative-path policy BEFORE inspecting
            # or descending into excluded children, including broken junctions.
            # Subtree-only policies end with '/'. Test that boundary for a
            # directory before descent, without excluding a same-named file.
            $isDirectoryEntry = $entry -is [System.IO.DirectoryInfo]
            if ($ExcludedPathPattern.Length -gt 0 -and
                ($excluded.IsMatch($relative) -or
                    ($isDirectoryEntry -and $excluded.IsMatch($relative + '/')))) {
                if ($isDirectoryEntry) {
                    $metrics.PrunedDirectoryCount++
                }
                else {
                    $metrics.PrunedFileCount++
                }
                continue
            }
            if (-not $seenPaths.Add($relative)) {
                throw "Source inventory has a case/path collision: '$relative'."
            }
            try {
                $attributes = [System.IO.File]::GetAttributes($entry.FullName)
                if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
                    ($attributes -band [System.IO.FileAttributes]::Device) -ne 0) {
                    throw 'Expected an ordinary path; reparse points and devices are forbidden.'
                }
                if (($attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
                    if ($entry -isnot [System.IO.DirectoryInfo]) {
                        throw 'Path changed from file to directory during enumeration.'
                    }
                    $directoriesByPath.Add($relative, $entry)
                    $pending.Push($entry)
                }
                else {
                    if ($entry -isnot [System.IO.FileInfo]) {
                        throw 'Path changed from directory to file during enumeration.'
                    }
                    # Enumeration alone does not prove that a file is readable.
                    # Do not cache this as proof of later source/content stability.
                    $stream = [System.IO.File]::Open(
                        $entry.FullName,
                        [System.IO.FileMode]::Open,
                        [System.IO.FileAccess]::Read,
                        ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
                    )
                    $stream.Dispose()
                    $metrics.VisitedFileCount++
                    $filesByPath.Add($relative, $entry)
                }
            }
            catch {
                throw "Source inventory cannot inspect '$relative': $($_.Exception.Message)"
            }
        }
    }

    $filePaths = [System.Collections.Generic.List[string]]::new($filesByPath.Keys)
    $directoryPaths = [System.Collections.Generic.List[string]]::new($directoriesByPath.Keys)
    $filePaths.Sort([System.StringComparer]::Ordinal)
    $directoryPaths.Sort([System.StringComparer]::Ordinal)
    [pscustomobject]@{
        SchemaVersion = 1
        RootPath = $root
        FilePaths = [string[]]$filePaths.ToArray()
        DirectoryPaths = [string[]]$directoryPaths.ToArray()
        Files = [System.IO.FileInfo[]]@(foreach ($path in $filePaths) { $filesByPath[$path] })
        Directories = [System.IO.DirectoryInfo[]]@(foreach ($path in $directoryPaths) { $directoriesByPath[$path] })
        Metrics = $metrics
    }
}
