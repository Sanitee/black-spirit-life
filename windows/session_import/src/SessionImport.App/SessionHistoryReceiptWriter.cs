using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BlackSpiritLife.SessionImport.App;

internal sealed record SessionHistoryReceipt(
    string ImportId,
    int Revision,
    DateTimeOffset ImportedAtUtc,
    SessionDraft Draft,
    IReadOnlyList<string> MethodIds,
    IReadOnlyList<string> LinkedSourceIds,
    int MatchedCount,
    int NotesCount,
    int SkippedCount);

internal interface ISessionHistoryReceiptWriter
{
    Task WriteAsync(SessionHistoryReceipt receipt, CancellationToken cancellationToken = default);
}

/// Writes only a durable handoff. Flutter alone owns session history; preparing
/// a Garmoth form is not evidence that its final Save has been pressed.
internal sealed class SessionHistoryReceiptWriter : ISessionHistoryReceiptWriter
{
    internal const int MaximumReceiptBytes = 64 * 1024;
    internal string DirectoryPath { get; }

    internal SessionHistoryReceiptWriter(string directoryPath)
    {
        if (directoryPath.Length > 4096 || !Path.IsPathFullyQualified(directoryPath) ||
            directoryPath.StartsWith(@"\\", StringComparison.Ordinal) ||
            directoryPath.Any(c => char.IsControl(c) || c == '"'))
            throw new ArgumentException("The local session inbox path is invalid.", nameof(directoryPath));
        DirectoryPath = Path.TrimEndingDirectorySeparator(Path.GetFullPath(directoryPath));
        if (!string.Equals(Path.GetFileName(DirectoryPath), "session-import-inbox", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("The local session inbox must be an app-owned session-import-inbox directory.", nameof(directoryPath));
    }

    internal static SessionHistoryReceiptWriter? FromCommandLine(IEnumerable<string> arguments)
    {
        const string prefix = "--receipt-directory=";
        var matches = arguments.Where(value => value.StartsWith(prefix, StringComparison.Ordinal)).ToArray();
        if (matches.Length == 0) return null;
        if (matches.Length != 1) throw new ArgumentException("Only one local session inbox may be supplied.");
        return new SessionHistoryReceiptWriter(matches[0][prefix.Length..]);
    }

    public async Task WriteAsync(SessionHistoryReceipt receipt, CancellationToken cancellationToken = default)
    {
        var payload = Encode(receipt);
        cancellationToken.ThrowIfCancellationRequested();
        Directory.CreateDirectory(DirectoryPath);
        if ((File.GetAttributes(DirectoryPath) & FileAttributes.ReparsePoint) != 0)
            throw new IOException("The local session inbox cannot be a link.");
        var name = Guid.Parse(receipt.ImportId).ToString("N") + "-" + receipt.Revision.ToString("D10") + ".json";
        var destination = Path.Combine(DirectoryPath, name);
        var temporary = Path.Combine(DirectoryPath, ".pending-" + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                4096, FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                await stream.WriteAsync(payload, cancellationToken).ConfigureAwait(false);
                await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
                stream.Flush(flushToDisk: true);
            }
            cancellationToken.ThrowIfCancellationRequested();
            try { File.Move(temporary, destination, overwrite: false); }
            catch (IOException) when (File.Exists(destination))
            {
                if ((File.GetAttributes(destination) & FileAttributes.ReparsePoint) != 0 ||
                    new FileInfo(destination).Length > MaximumReceiptBytes ||
                    !(await File.ReadAllBytesAsync(destination, cancellationToken).ConfigureAwait(false)).SequenceEqual(payload))
                    throw new IOException("A different local session receipt already uses this revision.");
            }
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    internal static byte[] Encode(SessionHistoryReceipt receipt)
    {
        var draft = receipt.Draft;
        static void Require(bool condition)
        {
            if (!condition) throw new InvalidDataException("The prepared local session receipt is invalid.");
        }
        static bool Text(string? value, int limit) => value is { Length: > 0 } && value.Length <= limit &&
            value == value.Trim() && !value.Any(char.IsControl);
        static bool Rate(decimal? value) => value is null ||
            (value >= 0 && value <= 10000 && decimal.Round(value.Value, 2) == value);
        Require(Guid.TryParse(receipt.ImportId, out var importId) && importId != Guid.Empty && receipt.Revision > 0);
        Require(receipt.ImportedAtUtc != default && Text(draft.SpotId, 160) && Text(draft.SpotName, 240));
        Require(draft.Activity is "gathering" or "hunting" or "grinding");
        Require(draft.DurationSeconds is > 0 and <= 604800 && draft.Items.Count is > 0 and <= 160);
        Require(receipt.MatchedCount > 0 && receipt.SkippedCount >= 0 && receipt.NotesCount >= 0 &&
            receipt.NotesCount <= receipt.SkippedCount && receipt.MatchedCount + receipt.SkippedCount == draft.Items.Count);
        Require(draft.AgrisUsed is null or >= 0 and <= 10000000000L && Rate(draft.AdditionalDropRate) && Rate(draft.AdditionalDropAmount));
        Require(receipt.MethodIds.Count <= 16 && receipt.LinkedSourceIds.Count <= 32 &&
            receipt.MethodIds.Concat(receipt.LinkedSourceIds).All(value => Text(value, 160)));
        var identities = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in draft.Items)
        {
            Require(Text(item.Name, 160) && (item.ItemId is null || Text(item.ItemId, 80)) &&
                item.SubKey is >= 0 and <= 1000000 && item.Quantity is > 0 and <= 9007199254740991L);
            Require(identities.Add((item.ItemId is null ? "name:" + item.Name.ToLowerInvariant() : "id:" + item.ItemId) + ":" + item.SubKey));
        }
        // Use a whitelist, not a browser response or screenshot/protocol dump.
        var session = new JsonObject
        {
            ["durationSeconds"] = draft.DurationSeconds,
            ["items"] = new JsonArray(draft.Items.Select(item => (JsonNode)new JsonObject
            {
                ["itemId"] = item.ItemId, ["subKey"] = item.SubKey,
                ["name"] = item.Name, ["quantity"] = item.Quantity,
            }).ToArray()),
        };
        if (draft.AgrisActive is { } active) session["agrisActive"] = active;
        if (draft.AgrisUsed is { } agris) session["agrisUsed"] = agris;
        if (draft.AdditionalDropRate is { } rate) session["additionalDropRate"] = rate;
        if (draft.AdditionalDropAmount is { } amount) session["additionalDropAmount"] = amount;
        var json = new JsonObject
        {
            ["schemaVersion"] = 1, ["provider"] = "garmoth", ["status"] = "prepared",
            ["importId"] = importId.ToString("D"), ["revision"] = receipt.Revision,
            ["importedAtUtc"] = receipt.ImportedAtUtc.ToUniversalTime().ToString("O"),
            ["target"] = new JsonObject
            {
                ["spotId"] = draft.SpotId, ["spotName"] = draft.SpotName, ["activity"] = draft.Activity,
                ["methodIds"] = new JsonArray(receipt.MethodIds.Select(value => (JsonNode)JsonValue.Create(value)!).ToArray()),
                ["linkedSourceIds"] = new JsonArray(receipt.LinkedSourceIds.Select(value => (JsonNode)JsonValue.Create(value)!).ToArray()),
            },
            ["session"] = session,
            ["preparation"] = new JsonObject
            {
                ["matchedCount"] = receipt.MatchedCount, ["notesCount"] = receipt.NotesCount,
                ["skippedCount"] = receipt.SkippedCount, ["submitted"] = false,
            },
        };
        var result = JsonSerializer.SerializeToUtf8Bytes(json);
        Require(result.Length <= MaximumReceiptBytes);
        return result;
    }
}
