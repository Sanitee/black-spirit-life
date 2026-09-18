# Same content rules as Assert-NoTextMarker, with bounded decoder windows.
# This helper does not cache pass results or replace scans across artifact stages.
if ($null -eq ('BlackSpiritLife.Release.StreamingMarkerScannerV1' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace BlackSpiritLife.Release {
    public sealed class MarkerScanResult {
        public int MarkerIndex = -1;
        public bool UnreviewedAbsolutePath;
        public long Bytes;
        public string Sha256;
        public double ElapsedMilliseconds;
    }

    public static class StreamingMarkerScannerV1 {
        // A finite lookahead is valid only for this exact reviewed bounded rule.
        private const string SupportedPattern = @"(?i)[A-Z]:(?:\\{1,2}|/)(?:Users|Codex)(?:\\{1,2}|/)";
        private const string ReviewedPattern = @"(?i)^C:" + @"\\Users\\runneradmin\\(?:\.cargo|\.rustup)\\";
        private static readonly Dictionary<string, Regex[]> Patterns = new Dictionary<string, Regex[]>();

        private static Regex[] GetPatterns(string pattern) {
            if (!String.Equals(pattern, SupportedPattern, StringComparison.Ordinal))
                throw new ArgumentException("Streaming scanner does not support the changed path policy.");
            string key = CultureInfo.CurrentCulture.Name + "\n" + pattern;
            lock (Patterns) {
                Regex[] value;
                if (!Patterns.TryGetValue(key, out value)) {
                    value = new Regex[] {
                        new Regex(pattern, RegexOptions.Compiled),
                        new Regex(ReviewedPattern, RegexOptions.Compiled)
                    };
                    Patterns.Add(key, value);
                }
                return value;
            }
        }

        private static void CheckOrdinaryPath(string path) {
            string current = Path.GetFullPath(path);
            FileAttributes attributes = File.GetAttributes(current);
            if ((attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint | FileAttributes.Device)) != 0)
                throw new IOException("The scan input must be an ordinary file.");
            DirectoryInfo directory = Directory.GetParent(current);
            while (directory != null) {
                if ((directory.Attributes & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("The scan input crosses a reparse point.");
                directory = directory.Parent;
            }
        }

        private sealed class Window {
            private readonly Decoder decoder;
            private readonly char[] characters;
            private readonly string[] markers;
            private readonly Regex generic;
            private readonly Regex reviewed;
            private readonly bool allowReviewed;
            private readonly int overlap;
            private string tail = "";

            public Window(Encoding encoding, int chunkBytes, string[] markers, Regex[] patterns, bool allowReviewed) {
                decoder = encoding.GetDecoder();
                characters = new char[encoding.GetMaxCharCount(chunkBytes)];
                this.markers = markers;
                generic = patterns[0];
                reviewed = patterns[1];
                this.allowReviewed = allowReviewed;
                overlap = 127;
                foreach (string marker in markers)
                    if (!String.IsNullOrWhiteSpace(marker)) overlap = Math.Max(overlap, marker.Length - 1);
                // Keep an additional UTF-16 unit so a supplementary ordinal-case
                // comparison cannot lose its surrogate partner at the boundary.
                overlap = checked(overlap + 1);
            }

            public void Feed(byte[] bytes, int count, bool final, MarkerScanResult result) {
                int length = decoder.GetChars(bytes, 0, count, characters, 0, final);
                string text = tail + new string(characters, 0, length);
                int limit = result.MarkerIndex < 0 ? markers.Length : result.MarkerIndex;
                for (int index = 0; index < limit; index++) {
                    if (!String.IsNullOrWhiteSpace(markers[index]) &&
                        text.IndexOf(markers[index], StringComparison.OrdinalIgnoreCase) >= 0) {
                        result.MarkerIndex = index;
                        break;
                    }
                }
                if (!result.UnreviewedAbsolutePath) {
                    // Every supported-policy match contains a literal colon
                    // followed by a slash. Find those candidates with the
                    // runtime's ordinal search before invoking the unchanged
                    // culture-sensitive Regex on its maximum 11-character span.
                    // This avoids a very slow full-string Regex search on .NET
                    // Framework without replacing its casing/path decisions.
                    int colon = -1;
                    while ((colon = text.IndexOf(':', colon + 1)) >= 0) {
                        if (colon == 0 || colon + 1 >= text.Length ||
                                (text[colon + 1] != '\\' && text[colon + 1] != '/')) continue;
                        int start = colon - 1;
                        Match match = generic.Match(text, start, Math.Min(11, text.Length - start));
                        if (!match.Success || match.Index != start) continue;
                        // The reference inspects up to 128 characters beginning
                        // at the match. Do not judge a partial reviewed prefix.
                        if (!final && match.Index + 128 > text.Length) break;
                        int tailLength = Math.Min(128, text.Length - match.Index);
                        if (allowReviewed && reviewed.IsMatch(text.Substring(match.Index, tailLength))) continue;
                        result.UnreviewedAbsolutePath = true;
                        break;
                    }
                }
                tail = final ? "" : text.Substring(Math.Max(0, text.Length - overlap));
            }
        }

        public static MarkerScanResult Scan(string path, string[] markers, string pathPattern,
                string pinnedRuntimeSha256, bool allowReviewed, int chunkBytes) {
            if (markers == null) throw new ArgumentNullException("markers");
            if (chunkBytes < 1 || chunkBytes > 16 * 1024 * 1024) throw new ArgumentOutOfRangeException("chunkBytes");
            Regex[] patterns = GetPatterns(pathPattern);
            CheckOrdinaryPath(path);
            bool namedRuntime = String.Equals(Path.GetFileName(path), "velopack_libc.dll", StringComparison.Ordinal);
            Stopwatch clock = Stopwatch.StartNew();
            MarkerScanResult result = new MarkerScanResult();
            byte[] buffer = new byte[chunkBytes];
            Window utf8 = new Window(Encoding.UTF8, chunkBytes, markers, patterns, allowReviewed);
            Window utf16 = new Window(Encoding.Unicode, chunkBytes, markers, patterns, allowReviewed);
            using (SHA256 hash = namedRuntime ? SHA256.Create() : null)
            using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read,
                    FileShare.Read, chunkBytes, FileOptions.SequentialScan)) {
                CheckOrdinaryPath(path);
                long expectedLength = stream.Length;
                // The reference ReadAllBytes cannot accept files beyond Int32.
                if (expectedLength > Int32.MaxValue) throw new IOException("The scan input exceeds the reference size limit.");
                int count;
                while ((count = stream.Read(buffer, 0, buffer.Length)) != 0) {
                    if (hash != null) hash.TransformBlock(buffer, 0, count, buffer, 0);
                    result.Bytes += count;
                    utf8.Feed(buffer, count, false, result);
                    utf16.Feed(buffer, count, false, result);
                }
                utf8.Feed(buffer, 0, true, result);
                utf16.Feed(buffer, 0, true, result);
                if (result.Bytes != expectedLength || stream.Length != expectedLength)
                    throw new IOException("The scan input changed length.");
                if (hash != null) {
                    hash.TransformFinalBlock(buffer, 0, 0);
                    result.Sha256 = BitConverter.ToString(hash.Hash).Replace("-", "");
                    if (String.Equals(result.Sha256, pinnedRuntimeSha256, StringComparison.Ordinal))
                        result.UnreviewedAbsolutePath = false;
                }
            }
            clock.Stop();
            result.ElapsedMilliseconds = clock.Elapsed.TotalMilliseconds;
            return result;
        }
    }
}
'@
}

function Get-StreamingMarkerScanResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Markers,
        [Parameter(Mandatory = $true)][string]$PrivateMachinePathPattern,
        [Parameter(Mandatory = $true)][string]$VelopackRuntimeSha256,
        [switch]$AllowReviewedVelopackBuildPaths,
        [ValidateRange(1, 16777216)][int]$ChunkBytes = 1048576
    )
    [BlackSpiritLife.Release.StreamingMarkerScannerV1]::Scan(
        $Path, $Markers, $PrivateMachinePathPattern, $VelopackRuntimeSha256,
        $AllowReviewedVelopackBuildPaths.IsPresent, $ChunkBytes)
}

function Test-StreamingMarkerEmptyTextBinding {
    param([Parameter(Mandatory = $true)][string]$Text)
    # Preserve the reference Test-UnreviewedAbsolutePath parameter contract.
    return $false
}

function Assert-NoStreamingTextMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Markers,
        [Parameter(Mandatory = $true)][string]$PrivateMachinePathPattern,
        [Parameter(Mandatory = $true)][string]$VelopackRuntimeSha256,
        [switch]$AllowReviewedVelopackBuildPaths,
        [ValidateRange(1, 16777216)][int]$ChunkBytes = 1048576,
        [switch]$PassThru
    )
    $arguments = @{} + $PSBoundParameters
    $null = $arguments.Remove('PassThru')
    $result = Get-StreamingMarkerScanResult @arguments
    if ($result.MarkerIndex -ge 0) {
        $marker = $Markers[$result.MarkerIndex]
        throw "Packaged file contains a private-machine marker '$marker': $Path"
    }
    if ($result.Bytes -eq 0 -and $result.Sha256 -cne $VelopackRuntimeSha256) {
        $null = Test-StreamingMarkerEmptyTextBinding -Text ''
    }
    if ($result.UnreviewedAbsolutePath) {
        throw "Packaged file contains an absolute user/private workspace path: $Path"
    }
    if ($PassThru) { $result }
}
