using System.IO;
using System.Reflection;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using BlackSpiritLife.SessionImport;
using BlackSpiritLife.SessionImport.App;

internal static class SessionHistoryFlowChecks
{
    internal static void Run(Action<string, Action> run)
    {
        run("successful Send records every exact loot row including Notes and unentered items", () =>
        {
            var browser = new HistoryBrowser(); var writer = new HistoryWriter(); var window = Create(browser, writer);
            try
            {
                Control<TextBox>(window, "DurationBox").Text = "00:15";
                Control<ComboBox>(window, "AgrisActiveBox").SelectedIndex = 0;
                Control<TextBox>(window, "AdditionalDropRateBox").Text = "0";
                Control<TextBox>(window, "AdditionalDropAmountBox").Text = "0";
                Send(window);
                var receipt = writer.Successful.Single();
                Assert(receipt.Revision == 1 && Guid.TryParseExact(receipt.ImportId, "N", out _), "stable new import identity and first revision");
                Assert(receipt.Draft.Items.SequenceEqual(ExpectedItems), "local history contains all exact identities/counts, not just numeric Garmoth columns");
                Assert(receipt.Draft.DurationSeconds == 900 && receipt.Draft.AgrisActive == false &&
                    receipt.Draft.AdditionalDropRate == 0m && receipt.Draft.AdditionalDropAmount == 0m,
                    "explicit false and zero metadata are retained, not treated as absent");
                Assert(receipt.Draft.SpotId == "186" && receipt.Draft.SpotName == "Rusalka's Coral" && receipt.Draft.Activity == "gathering",
                    "receipt carries canonical destination and activity");
                var spot = SpotCatalog.Load().Entries.Single(item => item.GarmothSpotId == "186");
                Assert(receipt.MethodIds.SequenceEqual(spot.MethodIds) && receipt.LinkedSourceIds.SequenceEqual(spot.LinkedSourceIds),
                    "canonical source links/methods accompany the receipt");
                Assert(receipt.MatchedCount == 1 && receipt.NotesCount == 1 && receipt.SkippedCount == 3,
                    "structured, Notes and skipped counts remain distinct");
                Assert(browser.Requests.SequenceEqual(new[] { "status", "prepare" }) &&
                    browser.Drafts.Single()["behavior"]?["submit"]?.GetValue<bool>() == false,
                    "one normal Send, no automatic review or Save in this inactive fixture");
                Assert(Action(window) == "Review inputs" && window.LootRows.Count == 4 && Status(window).StartsWith("Incomplete"),
                    "local receipt does not hide Garmoth omissions or remove native loot");
                Assert(!window.IsVisible && !window.IsActive, "no native window is shown");
            }
            finally { window.Close(); }
        });
        run("Review is idempotent for local history and never resends a draft", () =>
        {
            var browser = new HistoryBrowser(); var writer = new HistoryWriter(); var window = Create(browser, writer);
            try
            {
                Send(window); var first = writer.Successful.Single();
                Send(window); Send(window);
                Assert(writer.Attempts.Count == 1 && ReferenceEquals(first, writer.Successful.Single()), "successful receipt is not written again on Review");
                Assert(browser.Requests.Count(type => type == "prepare") == 1 && browser.Requests.Count(type => type == "review") == 2,
                    "repeated primary Review only opens the existing draft");
                Assert(browser.ReviewIds.All(id => id == first.Draft.DraftId), "every Review uses the already prepared draft identity");
            }
            finally { window.Close(); }
        });
        run("edited successful Send updates the same import with a new revision and immutable prior receipt", () =>
        {
            var browser = new HistoryBrowser(); var writer = new HistoryWriter(); var window = Create(browser, writer);
            try
            {
                Send(window); var first = writer.Successful.Single();
                window.LootRows[0].Quantity = "2345";
                Assert(Action(window) == "Send to Garmoth", "editing requires a fresh Send");
                Send(window); var second = writer.Successful.Last();
                Assert(writer.Successful.Count == 2 && second.ImportId == first.ImportId && second.Revision == 2 &&
                    second.ImportedAtUtc == first.ImportedAtUtc, "edited import replaces its original history identity, not a duplicate session");
                Assert(second.Draft.DraftId != first.Draft.DraftId && second.Draft.Items[0].Quantity == 2345 && first.Draft.Items[0].Quantity == 1005,
                    "new Garmoth draft and updated values do not mutate the previous receipt");
                Assert(second.Draft.AdditionalDropRate is null && second.Draft.AdditionalDropAmount is null && second.Draft.DurationSeconds == 3600,
                    "screenshot-only defaults preserve omitted percentages and one-hour duration");
            }
            finally { window.Close(); }
        });
        run("a new screenshot starts a distinct local import rather than revising the prior one", () =>
        {
            var browser = new HistoryBrowser(); var writer = new HistoryWriter(); var window = Create(browser, writer);
            try
            {
                Send(window); var first = writer.Successful.Single();
                NewScreenshot(window); Send(window); var second = writer.Successful.Last();
                Assert(second.ImportId != first.ImportId && second.Revision == 1 && writer.Successful.Count == 2,
                    "new screenshot receives a new identity and first revision");
            }
            finally { window.Close(); }
        });
        run("local disk failure is truthful and Review retries the same receipt without another Send", () =>
        {
            var browser = new HistoryBrowser(); var writer = new HistoryWriter { FailuresRemaining = 1 }; var window = Create(browser, writer);
            try
            {
                Send(window); var failedReceipt = writer.Attempts.Single();
                Assert(writer.Successful.Count == 0 && Status(window).Contains("Local history could not be updated") && Action(window) == "Review inputs",
                    "local failure warns while preserving usable prepared inputs");
                Send(window);
                Assert(writer.Attempts.Count == 2 && ReferenceEquals(writer.Attempts[1], failedReceipt) && ReferenceEquals(writer.Successful.Single(), failedReceipt),
                    "Review retry uses the same immutable import/revision/draft receipt");
                Assert(browser.Requests.Count(type => type == "prepare") == 1 && browser.Requests.Count(type => type == "review") == 1,
                    "retrying local persistence does not resend to Garmoth");
                Assert(!Status(window).Contains("Local history could not be updated") && Status(window).StartsWith("Incomplete"),
                    "successful retry removes only the local warning, not Garmoth omissions");
            }
            finally { window.Close(); }
        });
        run("failed local receipt survives an edit and failed Send until a successful replacement revision", () =>
        {
            var browser = new HistoryBrowser(); var writer = new HistoryWriter { FailuresRemaining = 1 }; var window = Create(browser, writer);
            try
            {
                Send(window); var original = writer.Attempts.Single();
                window.LootRows[0].Quantity = "2345"; browser.PrepareFails = true; Send(window);
                Assert(writer.Attempts.Count == 1 && Pending(window).Values.Single() == original,
                    "failed edited Send neither writes a false receipt nor drops the prior pending receipt");
                browser.PrepareFails = false; Send(window);
                var replacement = writer.Successful.Single();
                Assert(replacement.ImportId == original.ImportId && replacement.Revision == 2 && replacement.Draft.Items[0].Quantity == 2345,
                    "successful edited Send supersedes only the matching import with its newest revision");
                Assert(Pending(window).Count == 0, "successful replacement clears pending history");
            }
            finally { window.Close(); }
        });
        run("new screenshot success retries older failed local imports without losing either session", () =>
        {
            var browser = new HistoryBrowser(); var writer = new HistoryWriter { FailuresRemaining = 1 }; var window = Create(browser, writer);
            try
            {
                Send(window); var old = writer.Attempts.Single();
                NewScreenshot(window);
                Assert(Pending(window).Values.Single() == old, "new screenshot does not clear the older failed local receipt");
                Send(window);
                Assert(writer.Successful.Count == 2 && writer.Successful.Any(item => ReferenceEquals(item, old)) &&
                    writer.Successful.Select(item => item.ImportId).Distinct().Count() == 2 && Pending(window).Count == 0,
                    "later success flushes distinct pending imports without duplicate local identities");
            }
            finally { window.Close(); }
        });
        run("failed, zero-row and mismatched preparation responses never create history receipts", () =>
        {
            foreach (var mode in new[] { "failure", "zero", "wrong-draft" })
            {
                var browser = new HistoryBrowser { PrepareFails = mode == "failure", Matched = mode == "zero" ? 0 : 1, WrongDraft = mode == "wrong-draft" };
                var writer = new HistoryWriter(); var window = Create(browser, writer);
                try
                {
                    Send(window);
                    Assert(writer.Attempts.Count == 0 && Pending(window).Count == 0 && Action(window) == "Send to Garmoth",
                        mode + " cannot persist an unconfirmed send");
                }
                finally { window.Close(); }
            }
        });
        run("receipt write in progress keeps the primary action busy and prevents duplicate sends or writes", () =>
        {
            var browser = new HistoryBrowser(); var held = new TaskCompletionSource<bool>();
            var writer = new HistoryWriter { Held = held.Task }; var window = Create(browser, writer);
            try
            {
                Send(window); Send(window);
                Assert(!Control<Button>(window, "PrepareButton").IsEnabled && writer.Attempts.Count == 1 && browser.Requests.Count(type => type == "prepare") == 1,
                    "double click cannot overlap an in-flight receipt and preparation");
                held.SetResult(true); Drain();
                Assert(writer.Successful.Count == 1 && Control<Button>(window, "PrepareButton").IsEnabled,
                    "completed write restores the primary Review action once");
            }
            finally { held.TrySetResult(true); Drain(); window.Close(); }
        });
        run("history remains opt-in at the internal fixture boundary and never guesses a real output path", () =>
        {
            var browser = new HistoryBrowser(); var window = Create(browser, null);
            try
            {
                Send(window); Send(window);
                Assert(Action(window) == "Review inputs" && Pending(window).Count == 0 && browser.Requests.Count(type => type == "prepare") == 1,
                    "null injected writer performs the existing browser workflow with no history side effects");
            }
            finally { window.Close(); }
        });
    }

    private static readonly SessionItem[] ExpectedItems =
    [new("4006", 0, "Rough Stone", 1005), new("6511", 0, "Lobster", 38),
        new("4477", 0, "Blue Coral", 5), new("821350", 0, "Cracked Terrashard", 2)];
    private static MainWindow Create(HistoryBrowser browser, HistoryWriter? writer)
    {
        var window = new MainWindow(browser, monitorConnection: false, autoReviewAllowed: () => false, historyWriter: writer);
        AddRows(window); return window;
    }
    private static void AddRows(MainWindow window)
    {
        foreach (var item in ExpectedItems) window.LootRows.Add(new LootRowViewModel(item.Name, item.Quantity, item.ItemId));
        Control<ComboBox>(window, "SpotBox").Text = "Rusalka's Coral";
        typeof(MainWindow).GetMethod("ShowReview", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(window, null);
    }
    private static void NewScreenshot(MainWindow window)
    {
        typeof(MainWindow).GetMethod("ResetButton_Click", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(window, [null, new RoutedEventArgs()]);
        AddRows(window);
    }
    private static Dictionary<string, SessionHistoryReceipt> Pending(MainWindow window) =>
        (Dictionary<string, SessionHistoryReceipt>)typeof(MainWindow).GetField("_pendingHistoryReceipts", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(window)!;
    private static T Control<T>(MainWindow window, string name) where T : FrameworkElement => (T)window.FindName(name);
    private static string Action(MainWindow window) => (string)Control<Button>(window, "PrepareButton").Content;
    private static string Status(MainWindow window) => Control<TextBlock>(window, "StatusText").Text;
    private static void Send(MainWindow window) => Control<Button>(window, "PrepareButton").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    private static void Drain() => Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ContextIdle);
    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private sealed class HistoryWriter : ISessionHistoryReceiptWriter
    {
        internal readonly List<SessionHistoryReceipt> Attempts = [];
        internal readonly List<SessionHistoryReceipt> Successful = [];
        internal int FailuresRemaining;
        internal Task? Held;
        public async Task WriteAsync(SessionHistoryReceipt receipt, CancellationToken cancellationToken = default)
        {
            Attempts.Add(receipt);
            if (FailuresRemaining > 0) { FailuresRemaining--; throw new IOException("Isolated disk failure"); }
            if (Held is not null) await Held.WaitAsync(cancellationToken);
            Successful.Add(receipt);
        }
    }
    private sealed class HistoryBrowser : IAppManagedSessionImportBrowser
    {
        internal readonly List<string> Requests = [];
        internal readonly List<JsonObject> Drafts = [];
        internal readonly List<string> ReviewIds = [];
        internal bool PrepareFails;
        internal bool WrongDraft;
        internal int Matched = 1;
        public RegistrationResult Registration => new(true, "isolated-history-fixture", "fixture only");
        public Task<JsonObject> SendAsync(JsonObject request, TimeSpan timeout)
        {
            var type = request["type"]!.GetValue<string>(); Requests.Add(type);
            if (type == "status") return Task.FromResult(new JsonObject
            { ["type"] = "statusResult", ["protocolVersion"] = 1, ["ok"] = true, ["connected"] = true, ["canPrepare"] = true, ["state"] = "tracker_ready" });
            if (type == "review")
            {
                var id = request["draftId"]!.GetValue<string>(); ReviewIds.Add(id);
                return Task.FromResult(new JsonObject { ["type"] = "reviewResult", ["protocolVersion"] = 1, ["ok"] = true, ["draftId"] = id, ["revealed"] = false });
            }
            var draft = (JsonObject)request["draft"]!.DeepClone(); Drafts.Add(draft);
            var note = (JsonObject)draft["session"]!["items"]![1]!.DeepClone(); note["index"] = 1;
            return Task.FromResult(new JsonObject
            {
                ["type"] = "prepareResult", ["protocolVersion"] = 1, ["ok"] = !PrepareFails,
                ["draftId"] = WrongDraft ? "unrelated-draft" : draft["draftId"]!.GetValue<string>(), ["matched"] = Matched,
                ["message"] = "Isolated preparation failure", ["warnings"] = new JsonArray("item_values_not_accepted"),
                ["skipped"] = new JsonArray(new JsonObject { ["index"] = 1, ["reason"] = "item_not_found" },
                    new JsonObject { ["index"] = 2, ["reason"] = "value_not_accepted" }, new JsonObject { ["index"] = 3, ["reason"] = "item_not_found" }),
                ["notesStatus"] = "verified", ["notesVerified"] = new JsonArray(note)
            });
        }
        public Task OpenAsync(Window? owner = null) => throw new InvalidOperationException("History fixture must not open a browser.");
        public Task OpenForPreparationAsync(Window? owner = null) => throw new InvalidOperationException("History fixture is already ready; no browser is allowed.");
        public Task CloseAsync() => Task.CompletedTask;
        public Task ForgetAsync() => Task.CompletedTask;
        public void OpenSetup() => throw new InvalidOperationException("No setup in history flow tests.");
        public void CopyExtensionPath() => throw new InvalidOperationException("No clipboard in history flow tests.");
    }
}
