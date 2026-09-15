using System.IO;
using System.Text.Json.Nodes;
using BlackSpiritLife.SessionImport;
using BlackSpiritLife.SessionImport.App;

internal static class SessionHistoryReceiptChecks
{
    internal static void Run(Action<string, Action> run, string? evidenceDirectory = null)
    {
        run("local history output is disabled unless the app explicitly supplies its inbox", () =>
        {
            Assert(SessionHistoryReceiptWriter.FromCommandLine([]) is null, "no implicit profile path");
            foreach (var value in new[] { "relative/session-import-inbox", @"\\server\share\session-import-inbox", "C:\\", "C:\\history" })
                Throws<ArgumentException>(() => new SessionHistoryReceiptWriter(value));
        });
        run("local receipt preserves reviewed loot, zero metadata and unsaved preparation counts", () =>
        {
            var receipt = Fixture() with { MatchedCount = 2, NotesCount = 1, SkippedCount = 1 };
            var json = JsonNode.Parse(SessionHistoryReceiptWriter.Encode(receipt))!.AsObject();
            Assert(json["session"]!["items"]!.AsArray().Count == 3, "all rows retained");
            Assert(json["session"]!["items"]![0]!["quantity"]!.GetValue<long>() == 45678, "exact original amount");
            Assert(json["session"]!["agrisActive"]!.GetValue<bool>() == false && json["session"]!["additionalDropRate"]!.GetValue<decimal>() == 0, "false/zero retained");
            Assert(json["preparation"]!["matchedCount"]!.GetValue<int>() == 2 && json["preparation"]!["notesCount"]!.GetValue<int>() == 1, "Notes not structured");
            Assert(!json["preparation"]!["submitted"]!.GetValue<bool>(), "not a site Save claim");
            var text = json.ToJsonString();
            Assert(!text.Contains("expiresAt") && !text.Contains("draftId") && !text.Contains("http") && !text.Contains("cookie"), "no browser/transport content");
        });
        run("local receipt rejects failed or contradictory preparation and invalid inputs", () =>
        {
            var original = Fixture();
            foreach (var bad in new[] {
                original with { MatchedCount = 0 }, original with { NotesCount = 1 },
                original with { Revision = 0 }, original with { ImportId = "../../history" },
                original with { Draft = original.Draft with { DurationSeconds = 0 } },
                original with { Draft = original.Draft with { AdditionalDropAmount = 1.001m } },
                original with { Draft = original.Draft with { Items = [new(null, 0, "Unknown", 0)] }, MatchedCount = 1 },
                original with { Draft = original.Draft with { Items = [original.Draft.Items[0], original.Draft.Items[0]] }, MatchedCount = 2 },
            }) Throws<InvalidDataException>(() => SessionHistoryReceiptWriter.Encode(bad));
        });
        run("local receipt writes atomically, repeated retries are identical and revisions remain separate", () => WithInbox(path =>
        {
            var writer = new SessionHistoryReceiptWriter(path);
            var original = Fixture();
            writer.WriteAsync(original).GetAwaiter().GetResult();
            var file = Directory.GetFiles(path).Single();
            var bytes = File.ReadAllBytes(file);
            writer.WriteAsync(original).GetAwaiter().GetResult();
            Assert(Directory.GetFiles(path).Length == 1 && bytes.SequenceEqual(File.ReadAllBytes(file)), "idempotent retry");
            var changed = original with { Draft = original.Draft with { DurationSeconds = 1800 } };
            Throws<IOException>(() => writer.WriteAsync(changed).GetAwaiter().GetResult());
            writer.WriteAsync(changed with { Revision = 2 }).GetAwaiter().GetResult();
            Assert(Directory.GetFiles(path, "*.json").Length == 2 && Directory.GetFiles(path, "*.tmp").Length == 0, "immutable revisions");
        }));
        run("cancelled or blocked local writes keep existing receipt bytes untouched", () => WithInbox(path =>
        {
            var writer = new SessionHistoryReceiptWriter(path);
            using var cancelled = new CancellationTokenSource();
            cancelled.Cancel();
            Throws<OperationCanceledException>(() => writer.WriteAsync(Fixture(), cancelled.Token).GetAwaiter().GetResult());
            Assert(!Directory.Exists(path), "cancellation before disk writes");
            File.WriteAllText(path, "blocked directory fixture");
            Throws<IOException>(() => writer.WriteAsync(Fixture()).GetAwaiter().GetResult());
            Assert(File.ReadAllText(path) == "blocked directory fixture", "no overwrite");
        }));
        if (evidenceDirectory is not null)
        {
            run("cross-language receipt comes from the concrete native writer in an isolated evidence inbox", () =>
            {
                var writer = new SessionHistoryReceiptWriter(Path.Combine(evidenceDirectory, "cross-language", "session-import-inbox"));
                writer.WriteAsync(Fixture()).GetAwaiter().GetResult();
            });
        }
    }

    private static SessionHistoryReceipt Fixture() => new(
        "749a2f13-0ee9-4a35-8aaa-b9313624357f", 1,
        DateTimeOffset.Parse("2026-09-14T12:00:00Z"),
        new SessionDraft("test-transport-only", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddMinutes(5),
            "17", "Orc Camp", "grinding", 3600,
            [new("44482", 0, "Oily Orange Mushroom", 45678), new("8135", 0, "Heart of the Arid Forest", 9), new("8145", 0, "Shard of the Furious Night", 234)],
            AgrisActive: false, AdditionalDropRate: 0),
        ["garmoth:grinding"], [], 3, 0, 0);

    private static void WithInbox(Action<string> test)
    {
        var root = Path.Combine(Path.GetTempPath(), "bsl-receipt-check-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try { test(Path.Combine(root, "session-import-inbox")); }
        finally { Directory.Delete(root, recursive: true); }
    }
    private static void Throws<T>(Action test) where T : Exception
    {
        try { test(); } catch (T) { return; }
        throw new Exception("Expected " + typeof(T).Name);
    }
    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }
}
