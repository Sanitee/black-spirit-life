using System.Globalization;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using BlackSpiritLife.SessionImport;
using BlackSpiritLife.SessionImport.App;
using BlackSpiritLife.SessionImport.SummaryOcr;
using Microsoft.Web.WebView2.Core;

// Opt-in actual screenshot -> native OCR -> native review/Prepare -> production
// background Garmoth. Never run automatically. No Show, Activate, clipboard,
// OS input, login automation, profile copying or final Save is permitted.
internal static class LiveScreenshotPreparationChecks
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    // Authoritative quantities from the user's supplied sixteen-row example.
    // The one-hour duration and zero metadata below are UNSAVED test settings,
    // not assertions about the duration or buffs of the user's real session.
    private static readonly (string Name, long Quantity)[] Expected =
    [
        ("Rough Stone",1005), ("Black Gem Fragment",52), ("Sharp Black Crystal Shard",8),
        ("Lobster",38), ("Fairy's Breath",162), ("Caphras Stone",3), ("Coral Piece",413),
        ("Fairy Powder",132), ("Dim Heartvein Shard",26), ("Rusalka's Coral",59),
        ("Cracked Terrashard",2), ("Ancient Spirit Dust",37), ("Fruit of Nature",4),
        ("Blue Coral",5), ("Rough Translucent Crystal",5), ("Rough Blue Crystal",6)
    ];

    internal static Task RunAsync(string imagePath, string helperPath, string outputDirectory) =>
        RunCaseCoreAsync(new ScreenshotCase("real-rusalka-sixteen", "186", "gathering",
            Expected.Select(row => new ScreenshotRow(row.Name, row.Quantity)).ToArray(),
            new("01:00", false, 0m, 0m), Synthetic: false,
            NotesItemNames: ["Lobster", "Cracked Terrashard", "Blue Coral"]), imagePath, helperPath, outputDirectory);

    internal static Task RunCaseAsync(string caseId, string imagePath, string helperPath, string outputDirectory)
    {
        var value = SyntheticScreenshotCases.Get(caseId);
        if (value.SpotId is null) throw new InvalidOperationException("Ambiguous screenshots are tested offline only; never open a live browser to rescue them.");
        return RunCaseCoreAsync(value, imagePath, helperPath, outputDirectory);
    }

    private static async Task RunCaseCoreAsync(ScreenshotCase value, string imagePath, string helperPath, string outputDirectory)
    {
        imagePath = Path.GetFullPath(imagePath);
        helperPath = Path.GetFullPath(helperPath);
        outputDirectory = Path.GetFullPath(outputDirectory);
        if (!File.Exists(imagePath) || !File.Exists(helperPath)) throw new FileNotFoundException("The explicit screenshot or native OCR executable is missing.");
        if (Directory.Exists(outputDirectory) && Directory.EnumerateFileSystemEntries(outputDirectory).Any())
            throw new InvalidOperationException("Use a fresh output directory; previous evidence must remain unchanged.");
        Directory.CreateDirectory(outputDirectory);
        var preferences = new GarmothConnectionPreferences();
        if (!preferences.RememberConnection)
            throw new InvalidOperationException("An already opted-in remembered app connection is required; no preference was changed.");
        var service = new EmbeddedGarmothBrowser(preferences);
        var browser = new GuardedBrowser(service);
        var window = new MainWindow(browser, monitorConnection:false,
            firefoxFactory:() => throw new InvalidOperationException("Firefox is outside this test."));
        var report = new JsonObject
        {
            ["status"] = "pending", ["screenshotSha256"] = Convert.ToHexString(SHA256.HashData(await File.ReadAllBytesAsync(imagePath))),
            ["nativeOcrSha256"] = Convert.ToHexString(SHA256.HashData(await File.ReadAllBytesAsync(helperPath))),
            ["caseId"] = value.Id, ["syntheticScreenshot"] = value.Synthetic,
            ["expectedRows"] = value.Rows.Count,
            ["metadataControlsOverridden"] = value.Metadata is not null,
            ["explicitSyntheticMetadata"] = JsonSerializer.SerializeToNode(value.Metadata),
            ["saveRequested"] = false, ["noOsInputOrActivationRequested"] = true,
            ["automaticSpotChoiceOverridden"] = false
        };
        using var cancellation = new CancellationTokenSource(TimeSpan.FromMinutes(3));
        try
        {
            await WriteReportAsync(outputDirectory,report,"ocr_started");
            var actualOcr = await ReadAndReviewAsync(window, imagePath, helperPath, cancellation.Token);
            CheckNeverShown(window);
            report["ocrRows"] = new JsonArray(actualOcr.Rows.Select(row => (JsonNode?)new JsonObject
            {
                ["name"] = row.ItemName, ["quantity"] = row.Count
            }).ToArray());
            report["reviewRowsBefore"] = ReviewRows(window);
            var allExpected = ExpectedRows(window, value) && OcrRowsMatch(actualOcr, value);
            report["allExpectedRowsReviewedCorrectly"] = allExpected;
            if (!value.Synthetic) report["allSixteenReviewedCorrectly"] = allExpected;
            await WriteReportAsync(outputDirectory,report,"ocr_reviewed");
            if (!allExpected)
            {
                report["status"] = "failed_ocr_or_identity";
                throw new InvalidOperationException("Actual native OCR or review did not retain every expected name and quantity; no browser preparation was attempted.");
            }

            AssertAutomaticSpot(window, value);
            ApplyMetadata(window, value);
            var spot = Control<ComboBox>(window,"SpotBox");
            report["selectedSpot"] = Spot(spot);
            var prepare = Control<Button>(window,"PrepareButton");
            await WriteReportAsync(outputDirectory,report,"prepare_requested");
            prepare.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            // The normal async-void click handler owns validation and busy state.
            // Poll that local state, never drive native focus or bypass it.
            await Dispatcher.Yield(DispatcherPriority.Background);
            while (!prepare.IsEnabled)
            {
                cancellation.Token.ThrowIfCancellationRequested();
                CheckNeverShown(window);
                if (service.CurrentCore is not null) LiveMultiSpotChecks.CheckBackground(service);
                await Task.Delay(50, cancellation.Token);
            }
            CheckNeverShown(window);
            report["nativeStatus"] = SafeStatus(Control<TextBlock>(window,"StatusText").Text);
            report["primaryAction"] = prepare.Content?.ToString();
            if (browser.LastResponse?["ok"]?.GetValue<bool>() == true &&
                browser.LastResponse?["matched"]?.GetValue<int>() > 0 &&
                prepare.Content?.ToString() != "Review inputs")
                throw new InvalidOperationException("The successful Send did not become the Review inputs action.");
            report["reviewRowsAfter"] = ReviewRows(window);
            report["allExpectedRowsRetainedAfter"] = ExpectedRows(window, value);
            if (!value.Synthetic) report["allSixteenRetainedAfter"] = ExpectedRows(window, value);
            report["prepareCalls"] = browser.PrepareCalls;
            if (browser.LastRequest is null)
            {
                report["status"] = "blocked_before_preparation";
                throw new InvalidOperationException("The ordinary Prepare action did not produce a draft; automatic recognition or validation remains blocked.");
            }
            var draft = ReadDraft(browser.LastRequest);
            AssertDraft(value, (JsonObject)browser.LastRequest["draft"]!);
            report["sentSpot"] = new JsonObject { ["id"] = draft.SpotId, ["name"] = draft.SpotName, ["activity"] = draft.Activity };
            report["sentRows"] = JsonSerializer.SerializeToNode(draft.Items);
            report["sentMetadata"] = browser.LastRequest["draft"]?["session"]?.DeepClone();
            var response = browser.LastResponse;
            report["responseOk"] = response?["ok"]?.GetValue<bool>() == true;
            report["responseCode"] = LiveMultiSpotChecks.SafeCode(response?["code"]);
            report["matchedCount"] = response?["matched"] is JsonValue matched && matched.TryGetValue<int>(out var count) ? count : null;
            report["skipped"] = LiveMultiSpotChecks.SanitizeSkipped(response?["skipped"] as JsonArray,draft);
            report["warnings"] = new JsonArray((response?["warnings"] as JsonArray ?? []).Select(LiveMultiSpotChecks.SafeCode).Where(code => code is not null).Select(code => (JsonNode?)JsonValue.Create(code)).ToArray());
            report["notesStatus"] = LiveMultiSpotChecks.SafeCode(response?["notesStatus"]);
            await WriteReportAsync(outputDirectory,report,"preparation_completed");
            var core = service.CurrentCore ?? throw new InvalidOperationException("The production background browser has no page for independent readback.");
            await Task.Delay(500,cancellation.Token);
            var readback = await LiveMultiSpotChecks.ReadBackAsync(core,draft,cancellation.Token);
            report["readback"] = readback;
            LiveMultiSpotChecks.CheckBackground(service);
            var entered = CountEntered(readback,draft.Items);
            report["independentlyVerifiedQuantities"] = entered;
            var noteNames = (value.NotesItemNames ?? []).ToHashSet(StringComparer.Ordinal);
            var noteItems = draft.Items.Where(item => noteNames.Contains(item.Name)).ToArray();
            var expectedStructured = draft.Items.Where(item => !noteNames.Contains(item.Name)).ToArray();
            var notesProtocolMatches = NotesProtocolMatches(response, draft, noteItems);
            var notesReadback = noteItems.Length == 0 ? null : await ReadNotesBackAsync(core, draft, noteItems, cancellation.Token);
            report["notesReadback"] = notesReadback;
            report["expectedStructuredCount"] = expectedStructured.Length;
            report["expectedNotesCount"] = noteItems.Length;
            report["notesProtocolMatchesExpected"] = notesProtocolMatches;
            report["notesVerified"] = notesProtocolMatches ? JsonSerializer.SerializeToNode(noteItems) : null;
            // Omitted percentages are not target values. Observe them independently,
            // while requiring exact readback only for explicitly supplied percentages.
            var verificationDraft = draft with
            {
                Items = expectedStructured,
                AdditionalDropRate = draft.AdditionalDropRate ?? ObservedPercent(readback["dropRate"]),
                AdditionalDropAmount = draft.AdditionalDropAmount ?? ObservedPercent(readback["dropAmount"])
            };
            report["omittedPercentagesObservedNotAsserted"] = draft.AdditionalDropRate is null || draft.AdditionalDropAmount is null;
            var passed = browser.PrepareCalls == 1 && draft.Items.Count == value.Rows.Count && ExpectedRows(window, value) &&
                response?["ok"]?.GetValue<bool>() == true && report["matchedCount"]?.GetValue<int>() == expectedStructured.Length &&
                (response["warnings"] as JsonArray)?.Count is null or 0 &&
                entered == expectedStructured.Length && notesProtocolMatches &&
                (noteItems.Length == 0 || notesReadback?["expectedBlockMatched"]?.GetValue<bool>() == true) &&
                LiveMultiSpotChecks.Verify(readback,verificationDraft) && browser.OwnedActivations == 0;
            report["allLootAccountedFor"] = passed;
            report["notesExcludedFromGarmothTotals"] = noteItems.Length > 0;
            report["status"] = passed ? "passed" : entered > 0 && entered < value.Rows.Count ? "partial" : "failed";
            await WriteReportAsync(outputDirectory,report,"independent_readback_completed");
            await using var image = File.Create(Path.Combine(outputDirectory,"unsaved-form.png"));
            await core.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png,image).WaitAsync(cancellation.Token);
            await WriteReportAsync(outputDirectory,report,"capture_completed");
            if (!passed) throw new InvalidOperationException("The screenshot-to-Garmoth preparation is incomplete or failed independent verification.");
        }
        catch(Exception error) when(error is not OutOfMemoryException)
        {
            if(report["status"]?.GetValue<string>() == "pending") report["status"] = "failed";
            report["exceptionType"] = error.GetType().Name;
            report["nativeStatus"] = SafeStatus(Control<TextBlock>(window,"StatusText").Text);
            report["reviewRowsAfter"] = ReviewRows(window);
            report["allExpectedRowsRetainedAfter"] = ExpectedRows(window, value);
            if (!value.Synthetic) report["allSixteenRetainedAfter"] = ExpectedRows(window, value);
            await WriteReportAsync(outputDirectory,report,"failed");
            throw;
        }
        finally
        {
            try
            {
                try { await browser.CloseAsync(); }
                finally { window.Close(); }
            }
            finally
            {
                report["ownedBrowserClosed"] = service.CurrentWindow is null;
                report["ownedActivationEvents"] = browser.OwnedActivations;
                report["mainWindowWasNeverShown"] = !window.IsLoaded && !window.IsVisible;
                await WriteReportAsync(outputDirectory,report,"cleanup_finished");
            }
        }
    }

    private static Task WriteReportAsync(string outputDirectory, JsonObject report, string phase)
    {
        report["phase"] = phase;
        return File.WriteAllTextAsync(Path.Combine(outputDirectory,"screenshot-preparation-report.json"),report.ToJsonString(JsonOptions));
    }

    private sealed class GuardedBrowser(EmbeddedGarmothBrowser service) : IAppManagedSessionImportBrowser
    {
        private string? _guard;
        private CoreWebView2? _core;
        internal int PrepareCalls { get; private set; }
        internal JsonObject? LastRequest { get; private set; }
        internal JsonObject? LastResponse { get; private set; }
        internal int OwnedActivations { get; private set; }
        public RegistrationResult Registration => service.Registration;
        public Task OpenAsync(Window? owner = null) => throw new InvalidOperationException("Foreground browser opening is forbidden in this background test.");
        public void OpenSetup() => throw new InvalidOperationException("Browser setup is outside this test.");
        public void CopyExtensionPath() => throw new InvalidOperationException("Firefox is outside this test.");
        public async Task OpenForPreparationAsync(Window? owner = null)
        {
            var opening = service.OpenForPreparationAsync(owner);
            if (service.CurrentWindow is { } window) window.Activated += (_, _) => OwnedActivations++;
            await opening;
            if (OwnedActivations != 0) throw new InvalidOperationException("An owned browser activation was observed.");
            LiveMultiSpotChecks.CheckBackground(service);
            _core = service.CurrentCore ?? throw new InvalidOperationException("The normal background open did not initialize.");
            _guard = await _core.AddScriptToExecuteOnDocumentCreatedAsync(LiveMultiSpotChecks.SaveGuard);
            await _core.ExecuteScriptAsync(LiveMultiSpotChecks.SaveGuard);
        }
        public async Task<JsonObject> SendAsync(JsonObject request,TimeSpan timeout)
        {
            var type = request["type"]?.GetValue<string>();
            if(type is not ("status" or "prepare")) throw new InvalidOperationException("Only status and unsaved preparation are allowed.");
            if(type == "prepare")
            {
                if(_guard is null || _core is null) throw new InvalidOperationException("The normal flow did not arm the no-Save guard.");
                PrepareCalls++;
                LastRequest = (JsonObject)request.DeepClone();
                LastResponse = await service.SendAsync(request,timeout);
                if (OwnedActivations != 0) throw new InvalidOperationException("An owned browser activation was observed.");
                return LastResponse;
            }
            return await service.SendAsync(request,timeout);
        }
        public async Task CloseAsync()
        {
            try { if(_guard is not null && _core is not null) _core.RemoveScriptToExecuteOnDocumentCreated(_guard); }
            finally { _guard=null;_core=null;await service.CloseAsync(); }
        }
    }

    private static SessionDraft ReadDraft(JsonObject request)
    {
        var draft=request["draft"]!;var target=draft["target"]!;var session=draft["session"]!;
        return new(draft["draftId"]!.GetValue<string>(),DateTimeOffset.UtcNow,DateTimeOffset.UtcNow.AddMinutes(5),
            target["spotId"]!.GetValue<string>(),target["spotName"]!.GetValue<string>(),target["activity"]!.GetValue<string>(),
            session["durationSeconds"]!.GetValue<int>(),((JsonArray)session["items"]!).Select(item=>new SessionItem(
                item?["itemId"]?.GetValue<string>(),item?["subKey"]?.GetValue<int>()??0,item!["name"]!.GetValue<string>(),item["quantity"]!.GetValue<long>())).ToArray(),
            AdditionalDropRate:session["additionalDropRate"]?.GetValue<decimal>(),AdditionalDropAmount:session["additionalDropAmount"]?.GetValue<decimal>(),AgrisActive:session["agrisActive"]?.GetValue<bool>());
    }
    internal static async Task<SummaryOcrResult> ReadAndReviewAsync(MainWindow window, string imagePath, string helperPath, CancellationToken cancellation)
    {
        SummaryOcrResult? result = null;
        var reader = new IqonSummaryOcr(helperPath);
        Func<Task<SummaryOcrResult>> read = async () => result = await reader.ReadAsync(imagePath, cancellation);
        var method = typeof(MainWindow).GetMethod("ReadScreenshotAsync", BindingFlags.Instance | BindingFlags.NonPublic)
            ?? throw new MissingMethodException("The production screenshot review method changed.");
        var task = method.Invoke(window, [read]) as Task ?? throw new InvalidOperationException("Screenshot processing did not return a task.");
        await task.WaitAsync(cancellation);
        CheckNeverShown(window);
        return result ?? throw new InvalidOperationException("Actual native OCR returned no result.");
    }

    internal static bool OcrRowsMatch(SummaryOcrResult result, ScreenshotCase value) =>
        result.Rows.Count == value.Rows.Count && value.Rows.All(expected => result.Rows.Count(row =>
            Normalize(row.ItemName) == Normalize(expected.Name) && row.Count == expected.Quantity) == 1);

    internal static bool ExpectedRows(MainWindow window, ScreenshotCase value) => window.LootRows.Count == value.Rows.Count && value.Rows.All(expected=>
        window.LootRows.Count(row=>Normalize(row.Name)==Normalize(expected.Name)&&IntegerInput.TryParseGrouped(row.Quantity,out var count)&&count==expected.Quantity &&
            (expected.ItemId is null || row.ItemId == expected.ItemId))==1);

    internal static void AssertAutomaticSpot(MainWindow window, ScreenshotCase value)
    {
        var selected = Control<ComboBox>(window, "SpotBox").SelectedItem as SpotDefinition;
        if (selected?.GarmothSpotId != value.SpotId || selected?.Activity != value.Activity)
            throw new InvalidOperationException("The expected automatic destination or ambiguity was not produced; manual rescue is forbidden.");
    }

    internal static void ApplyMetadata(MainWindow window, ScreenshotCase value)
    {
        if (value.Metadata is not { } settings) return;
        Control<TextBox>(window, "DurationBox").Text = settings.Duration;
        Control<ComboBox>(window, "AgrisActiveBox").SelectedIndex = settings.Agris ? 1 : 0;
        Control<TextBox>(window, "AdditionalDropRateBox").Text = settings.Rate?.ToString(CultureInfo.InvariantCulture) ?? "";
        Control<TextBox>(window, "AdditionalDropAmountBox").Text = settings.Amount?.ToString(CultureInfo.InvariantCulture) ?? "";
    }

    internal static void AssertDraft(ScreenshotCase value, JsonObject draft)
    {
        var target = draft["target"]!;
        var session = draft["session"]!;
        var metadata = value.Metadata ?? new ScreenshotMetadata("01:00", false, null, null);
        var time = metadata.Duration.Split(':');
        var duration = int.Parse(time[0], CultureInfo.InvariantCulture) * 3600 + int.Parse(time[1], CultureInfo.InvariantCulture) * 60;
        if (target["spotId"]?.GetValue<string>() != value.SpotId || target["activity"]?.GetValue<string>() != value.Activity ||
            session["durationSeconds"]?.GetValue<int>() != duration || session["agrisActive"]?.GetValue<bool>() != metadata.Agris ||
            session["additionalDropRate"]?.GetValue<decimal>() != metadata.Rate || session["additionalDropAmount"]?.GetValue<decimal>() != metadata.Amount)
            throw new InvalidOperationException("Normal Prepare changed expected destination or screenshot-default/explicit metadata.");
        var rows = (JsonArray)session["items"]!;
        if (rows.Count != value.Rows.Count || !value.Rows.All(expected => rows.Count(row =>
            Normalize(row?["name"]?.GetValue<string>() ?? "") == Normalize(expected.Name) && row?["quantity"]?.GetValue<long>() == expected.Quantity &&
            (expected.ItemId is null || row?["itemId"]?.GetValue<string>() == expected.ItemId)) == 1))
            throw new InvalidOperationException("Normal Prepare changed expected item identity or quantity.");
    }

    private static decimal? ObservedPercent(JsonNode? value) => value is JsonValue node && node.TryGetValue<string>(out var text) &&
        decimal.TryParse(text, NumberStyles.AllowDecimalPoint | NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var number) ? number : null;

    internal static bool NotesProtocolMatches(JsonObject? response, SessionDraft draft, IReadOnlyList<SessionItem> expected)
    {
        if (response is null) return false;
        var notes = response["notesVerified"] as JsonArray ?? [];
        var skipped = response["skipped"] as JsonArray ?? [];
        if (expected.Count == 0) return notes.Count == 0 && skipped.Count == 0 && response["notesStatus"]?.GetValue<string>() == "not_needed";
        if (response["notesStatus"]?.GetValue<string>() != "verified" || notes.Count != expected.Count || skipped.Count != expected.Count) return false;
        return expected.All(item =>
        {
            var index = draft.Items.ToList().IndexOf(item);
            return notes.Count(note => Integer(note?["index"]) == index && note?["itemId"]?.GetValue<string>() == item.ItemId &&
                Integer(note?["subKey"]) == item.SubKey && note?["name"]?.GetValue<string>() == item.Name &&
                Integer(note?["quantity"]) == item.Quantity) == 1 &&
                skipped.Count(missing => Integer(missing?["index"]) == index && missing?["reason"]?.GetValue<string>() == "item_not_found") == 1;
        });
    }

    private static long? Integer(JsonNode? value) => value is JsonValue node
        ? node.TryGetValue<long>(out var wide) ? wide : node.TryGetValue<int>(out var narrow) ? narrow : null
        : null;

    private static async Task<JsonObject> ReadNotesBackAsync(CoreWebView2 core, SessionDraft draft,
        IReadOnlyList<SessionItem> expected, CancellationToken cancellation)
    {
        // Independent DOM read: no shared filler/readiness/ownership state, clicks,
        // input events or arbitrary existing user-note text are consumed/exported.
        const string start = "[BS Life: not included in Garmoth totals]";
        const string end = "[/BS Life]";
        var options = new JsonObject
        {
            ["spotId"] = draft.SpotId, ["spotName"] = draft.SpotName, ["start"] = start, ["end"] = end,
            ["block"] = start + "\n" + string.Join("\n", expected.Select(item => item.Name + " × " + item.Quantity.ToString(CultureInfo.InvariantCulture))) + "\n" + end
        };
        var script = "(()=>{const o=" + options.ToJsonString() + ";" + """
            const fail={expectedBlockMatched:false};
            const norm=s=>String(s||'').normalize('NFKC').replace(/\s+/g,' ').trim().toLowerCase();
            const u=new URL(location.href),parts=u.pathname.split('/').filter(Boolean);
            if(window.top!==window||u.origin!=='https://garmoth.com'||parts.length!==4||parts[0]!=='grind-tracker'||parts[2]!=='spot'||parts[3]!==o.spotId)return fail;
            if(![...document.querySelectorAll('h1')].some(h=>norm(h.textContent)===norm(o.spotName)))return fail;
            const tables=[...document.querySelectorAll('table')].filter(t=>/hours/i.test(t.tHead?.textContent||'')&&/mins/i.test(t.tHead?.textContent||'')&&t.tBodies.length===1&&t.tBodies[0].rows.length===1);
            if(tables.length!==1)return fail;
            let ancestor=tables[0].parentElement,panel=null;
            while(ancestor&&ancestor!==document.body){
              const saves=[...ancestor.querySelectorAll('button')].filter(b=>/^save(?: session)?$/i.test(b.textContent.trim()));
              const labels=[...ancestor.querySelectorAll('span')].filter(s=>s.textContent.trim()==='Notes'&&s.parentElement.classList.contains('cursor-pointer'));
              if(saves.length===1&&labels.length===1){panel=labels[0].parentElement.parentElement;break;}
              ancestor=ancestor.parentElement;
            }
            const fields=panel?[...panel.querySelectorAll('textarea[placeholder="Notes"]')]:[];
            if(fields.length!==1)return {...fail,notesFieldCount:fields.length};
            const text=fields[0].value,starts=text.split(o.start).length-1,ends=text.split(o.end).length-1;
            const a=text.indexOf(o.start),b=text.indexOf(o.end);
            const matches=starts===1&&ends===1&&a>=0&&b>a&&text.slice(a,b+o.end.length)===o.block;
            return {expectedBlockMatched:matches,notesFieldCount:1,startMarkers:starts,endMarkers:ends,
              verifiedBlock:matches?o.block:null,otherTextLength:matches?text.length-o.block.length:null};
            })()
            """;
        return JsonNode.Parse(await core.ExecuteScriptAsync(script).WaitAsync(cancellation)) as JsonObject
            ?? throw new InvalidOperationException("Independent Notes readback returned no object.");
    }
    private static int CountEntered(JsonObject readback,IReadOnlyList<SessionItem> items) => items.Count(item=>
    {
        var columns=(readback["columns"] as JsonArray ?? []).Where(column=>Normalize(column?["name"]?.GetValue<string>()??"")==Normalize(item.Name)).ToArray();
        return columns.Length==1&&columns[0]?["value"]?.GetValue<string>()==item.Quantity.ToString(CultureInfo.InvariantCulture);
    });
    private static JsonArray ReviewRows(MainWindow window) => new(window.LootRows.Select(row=>(JsonNode?)new JsonObject
    { ["name"]=row.Name,["quantity"]=row.Quantity,["itemId"]=row.ItemId }).ToArray());
    private static JsonObject Spot(ComboBox box) => new()
    { ["text"]=box.Text,["selectedName"]=(box.SelectedItem as SpotDefinition)?.Name,["selectedId"]=(box.SelectedItem as SpotDefinition)?.GarmothSpotId };
    internal static T Control<T>(MainWindow window,string name) where T:FrameworkElement => window.FindName(name) as T ?? throw new InvalidOperationException("The native test control changed.");
    private static void CheckNeverShown(MainWindow window)
    {
        if(window.IsVisible||window.IsActive||window.IsLoaded) throw new InvalidOperationException("The test MainWindow must remain unshown.");
    }
    private static string Normalize(string value) => SpotCatalog.Normalize(value);
    private static string SafeStatus(string value)
    {
        var clean=Regex.Replace(value,@"https?://\S+","[URL omitted]",RegexOptions.IgnoreCase);
        return clean[..Math.Min(600,clean.Length)];
    }
}
