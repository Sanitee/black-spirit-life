using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Windows.Interop;
using BlackSpiritLife.SessionImport;
using BlackSpiritLife.SessionImport.App;
using Microsoft.Web.WebView2.Core;

// Explicit opt-in LIVE UNSAVED integration checks. Never invoked by normal tests.
// Inputs are previously reviewed session-item columns, not asserted natural drops
// or artwork-to-item-ID guesses. This runner must be approved before execution.
internal static class LiveMultiSpotChecks
{
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private sealed record Case(SpotDefinition Spot, SessionItem[] Items);

    internal static async Task RunAsync(string harvestEvidenceDirectory, string outputDirectory, string? spotIds = null)
    {
        var source = Path.Combine(Path.GetFullPath(harvestEvidenceDirectory), "session-item-column-catalog.json");
        var bytes = File.ReadAllBytes(source);
        var input = JsonNode.Parse(bytes) as JsonObject ?? throw new InvalidDataException("Missing session-item-column harvest object.");
        var available = ReadCases(input);
        var cases = SelectCases(available, spotIds);
        outputDirectory = Path.GetFullPath(outputDirectory);
        if (Directory.Exists(outputDirectory) && Directory.EnumerateFileSystemEntries(outputDirectory).Any())
            throw new InvalidOperationException("Use a fresh output directory; previous evidence must not be overwritten.");
        Directory.CreateDirectory(outputDirectory);
        var results = new JsonArray();
        var report = new JsonObject
        {
            ["inputFile"] = Path.GetFileName(source), ["inputSha256"] = Convert.ToHexString(SHA256.HashData(bytes)),
            ["availableVerifiedCases"] = available.Count, ["selectedCases"] = cases.Count,
            ["syntheticUnsavedValues"] = true, ["durationSeconds"] = 900,
            ["requestedSave"] = false, ["accountIdentifiersExported"] = false,
            ["noOsInputOrActivationRequested"] = true, ["results"] = results,
            ["coverage"] = new JsonObject
            {
                ["activities"] = new JsonArray(cases.Select(value => value.Spot.Activity).Distinct().Select(value => (JsonNode?)JsonValue.Create(value)).ToArray()),
                ["sameNameDifferentIds"] = cases.GroupBy(value => Normalize(value.Spot.Name)).Any(group => group.Select(value => value.Spot.GarmothSpotId).Distinct().Count() > 1),
                ["all174SpotsTested"] = false
            }
        };
        await WriteAsync(Path.Combine(outputDirectory, "multispot-report.json"), report);
        // The only connection read is the application's explicit remembered-login
        // preference. Do not copy profiles or inspect cookies/authentication state.
        var preferences = new GarmothConnectionPreferences();
        if (!preferences.RememberConnection)
            throw new InvalidOperationException("An already opted-in remembered app connection is required; no preference was changed.");
        using var lifetime = new CancellationTokenSource(TimeSpan.FromMinutes(20));
        for (var index = 0; index < cases.Count; index++)
        {
            lifetime.Token.ThrowIfCancellationRequested();
            var value = cases[index];
            // Deliberately varied, explicit test metadata; not a real session.
            var agris = cases.Count == 1 || index % 2 == 1;
            var rate = index % 3 == 0 ? 0m : 25m;
            var amount = index % 3 == 1 ? 100m : 0m;
            var folder = Path.Combine(outputDirectory, "spot-" + value.Spot.GarmothSpotId);
            Directory.CreateDirectory(folder);
            var now = DateTimeOffset.UtcNow;
            var draft = new SessionDraft("unsaved-multispot-" + Guid.NewGuid().ToString("N"), now, now.AddMinutes(5),
                value.Spot.GarmothSpotId!, value.Spot.Name, value.Spot.Activity, 900, value.Items,
                AdditionalDropRate: rate, AdditionalDropAmount: amount, AgrisActive: agris);
            var result = new JsonObject
            {
                ["spotId"] = value.Spot.GarmothSpotId, ["name"] = value.Spot.Name,
                ["activity"] = value.Spot.Activity, ["sidebarGroup"] = value.Spot.SidebarGroup,
                ["agrisActive"] = agris, ["additionalDropRate"] = rate, ["additionalDropAmount"] = amount,
                ["items"] = JsonSerializer.SerializeToNode(value.Items), ["status"] = "pending"
            };
            results.Add(result);
            var service = new EmbeddedGarmothBrowser(preferences);
            var navigationSteps = new JsonArray();
            result["navigationSteps"] = navigationSteps;
            service.NavigationDiagnostic = raw =>
            {
                if (navigationSteps.Count < 220 && SanitizeNavigationStep(raw) is { } step) navigationSteps.Add(step);
            };
            string? saveGuardId = null;
            CoreWebView2? core = null;
            BackgroundProbe? background = null;
            var backgroundGuardFailed = false;
            try
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
                timeout.CancelAfter(TimeSpan.FromSeconds(110));
                var startupForeground = GetForegroundWindow();
                var opening = service.OpenForPreparationAsync();
                // Subscribe before awaiting initialization. The synchronous Show
                // has already occurred with native NOACTIVATE; that initial gap
                // is covered by the opening foreground comparison, not this event.
                background = new BackgroundProbe(service, result);
                await opening.WaitAsync(timeout.Token);
                result["startupForegroundUnchanged"] = GetForegroundWindow() == startupForeground;
                background.Check("after_open");
                core = service.CurrentCore ?? throw new InvalidOperationException("The app-owned background browser did not initialize.");
                // Fresh service/window starts at the production tracker entry. Do
                // not pre-navigate to the spot or inject an editor in this test.
                saveGuardId = await core.AddScriptToExecuteOnDocumentCreatedAsync(SaveGuard).WaitAsync(timeout.Token);
                await core.ExecuteScriptAsync(SaveGuard).WaitAsync(timeout.Token);
                background.Check("before_send");
                var prepareElapsed = System.Diagnostics.Stopwatch.StartNew();
                var response = await service.SendAsync(draft.ToPrepareMessage(), TimeSpan.FromSeconds(45)).WaitAsync(timeout.Token);
                // Preserve only protocol facts, never a URL/account-bearing error.
                result["responseOk"] = response["ok"]?.GetValue<bool>() == true;
                result["matchedCount"] = response["matched"] is JsonValue matched && matched.TryGetValue<int>(out var count) ? count : (response["matched"] as JsonArray)?.Count;
                result["skippedCount"] = (response["skipped"] as JsonArray)?.Count;
                result["responseCode"] = SafeCode(response["code"]);
                result["responseMessage"] = SafeMessage(response["message"]);
                result["warnings"] = new JsonArray((response["warnings"] as JsonArray ?? []).Select(SafeCode).Where(code => code is not null).Select(code => (JsonNode?)JsonValue.Create(code)).ToArray());
                result["skipped"] = SanitizeSkipped(response["skipped"] as JsonArray, draft);
                // Record the returned protocol facts before checking whether
                // bounded cancellation cleanup closed the owned connection.
                background.Check("after_send");
                await Task.Delay(500, timeout.Token);
                var readback = await ReadBackAsync(core, draft, timeout.Token);
                result["readback"] = readback;
                background.Check("after_readback");
                result["status"] = Verify(readback, draft) && result["responseOk"]!.GetValue<bool>() ? "passed" : "failed";
                await using var image = File.Create(Path.Combine(folder, "unsaved-form.png"));
                await core.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, image).WaitAsync(timeout.Token);
                await WriteAsync(Path.Combine(folder, "result.json"), result);
                if (cases.Count == 1 && result["responseOk"]?.GetValue<bool>() == false &&
                    navigationSteps.OfType<JsonObject>().LastOrDefault(step => step["phase"]?.GetValue<string>() == "discover_complete")?["code"]?.GetValue<string>() == "no_matching_link")
                {
                    // Observe this same failed page once more; do not restart a
                    // preparation, navigate, open Add or change any form field.
                    var late = new JsonObject { ["readOnlyAfterFailedPreparation"] = true, ["retriedPrepare"] = false };
                    late["immediate"] = JsonNode.Parse(await core.ExecuteScriptAsync(EmbeddedGarmothBrowser.PageStructureDiagnostic).WaitAsync(timeout.Token));
                    late["immediateElapsedMs"] = prepareElapsed.ElapsedMilliseconds;
                    await Task.Delay(TimeSpan.FromMilliseconds(Math.Max(0, 10000 - prepareElapsed.ElapsedMilliseconds)), timeout.Token);
                    background.Check("after_failed_page_wait");
                    late["afterWait"] = JsonNode.Parse(await core.ExecuteScriptAsync(EmbeddedGarmothBrowser.PageStructureDiagnostic).WaitAsync(timeout.Token));
                    late["afterWaitElapsedMs"] = prepareElapsed.ElapsedMilliseconds;
                    result["failedPageObservation"] = late;
                    await using var lateImage = File.Create(Path.Combine(folder, "failed-page-after-10s.png"));
                    await core.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, lateImage).WaitAsync(timeout.Token);
                    await WriteAsync(Path.Combine(folder, "failed-page-observation.json"), late);
                    await WriteAsync(Path.Combine(folder, "result.json"), result);
                }
            }
            catch (Exception error) when (error is not OutOfMemoryException)
            {
                result["status"] = "failed";
                // Exception messages can include an opaque account URL. Keep only
                // a fixed classification in the exported diagnostic.
                result["failure"] = error is BackgroundGuardException guard ? guard.Code :
                    error is OperationCanceledException ? "bounded_check_cancelled" : "background_or_readback_check_failed";
                result["exceptionType"] = error.GetType().Name;
                backgroundGuardFailed = error is BackgroundGuardException;
                background?.Record("exception");
                await WriteAsync(Path.Combine(folder, "result.json"), result);
            }
            finally
            {
                try
                {
                    if (core is not null && saveGuardId is not null && service.CurrentCore == core)
                        core.RemoveScriptToExecuteOnDocumentCreated(saveGuardId);
                }
                finally
                {
                    await service.CloseAsync();
                    background?.Record("after_owned_cleanup");
                    background?.Dispose();
                }
                report["passed"] = results.Count(entry => entry?["status"]?.GetValue<string>() == "passed");
                report["failed"] = results.Count(entry => entry?["status"]?.GetValue<string>() == "failed");
                await WriteAsync(Path.Combine(outputDirectory, "multispot-report.json"), report);
            }
            Console.WriteLine($"Live UNSAVED check {index + 1}/{cases.Count}: spot {value.Spot.GarmothSpotId} {result["status"]}");
            if (backgroundGuardFailed)
                throw new InvalidOperationException("The owned connection failed a background lifecycle or isolation check; no further cases were started.");
        }
        if (results.Any(result => result?["status"]?.GetValue<string>() != "passed"))
            throw new InvalidOperationException("One or more live unsaved checks failed; inspect the sanitized readbacks.");
    }

    private static List<Case> ReadCases(JsonObject input)
    {
        var spotCatalog = SpotCatalog.Load();
        var observed = spotCatalog.Entries;
        if (observed.Count != 174) throw new InvalidDataException("Expected the reviewed 174-destination catalog.");
        var catalog = ItemCatalog.Load();
        var result = new List<Case>();
        foreach (var record in (input["spots"] as JsonArray ?? throw new InvalidDataException("Harvest spots are missing.")))
        {
            if (record?["status"]?.GetValue<string>() != "verified_header_structure") continue;
            var id = record["spotId"]?.GetValue<string>();
            var matches = observed.Where(spot => spot.GarmothSpotId == id && Normalize(spot.Name) == Normalize(record["name"]?.GetValue<string>() ?? "")).ToArray();
            if (matches.Length != 1 || matches[0].ActivityNeedsReview) continue;
            var items = new List<SessionItem>();
            var headers = record["tooltipObservations"] as JsonArray;
            if (headers is null) continue;
            foreach (var header in headers)
            {
                if (header?["tooltipStatus"]?.GetValue<string>() != "observed") continue;
                var text = header["tooltipName"]?.GetValue<string>() ?? "";
                // Current session-column evidence stores tooltip names only.
                // Older snapshots included this observed labelled suffix; strip
                // it before requiring a unique exact catalog identity.
                var suffix = Regex.Match(text, @"^(?<name>.+?)\s+Average:\s*.+?\s+Total:\s*.+?\s+Price:\s*.+$", RegexOptions.CultureInvariant);
                var name = suffix.Success ? suffix.Groups["name"].Value : text;
                var sourceItem = spotCatalog.MatchItem(name);
                var artworkItem = sourceItem is null ? catalog.MatchExact(name) : null;
                var itemId = sourceItem?.Id ?? artworkItem?.ItemId;
                // MatchItem includes only explicit exact source aliases. Neither
                // path guesses identity from art or applies fuzzy OCR matching.
                if (itemId is null) continue;
                if (items.Any(old => old.ItemId == itemId)) continue;
                items.Add(new SessionItem(itemId, 0, name.Trim(), items.Count + 1));
                if (items.Count == 3) break;
            }
            if (items.Count == 3) result.Add(new(matches[0], items.ToArray()));
        }
        if (result.GroupBy(value => value.Spot.GarmothSpotId).Any(group => group.Count() > 1))
            throw new InvalidDataException("Duplicate harvested spot records require review.");
        return result;
    }

    private static List<Case> SelectCases(List<Case> available, string? spotIds)
    {
        if (!string.IsNullOrWhiteSpace(spotIds))
        {
            var selected = new List<Case>();
            foreach (var id in spotIds.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries).Distinct())
            {
                if (!Regex.IsMatch(id, @"^[1-9][0-9]*$")) throw new InvalidDataException("Spot IDs must be positive decimal IDs from the harvest.");
                selected.Add(available.SingleOrDefault(value => value.Spot.GarmothSpotId == id)
                    ?? throw new InvalidDataException("A requested spot lacks three uniquely identified session-item columns."));
            }
            if (selected.Count is 0 or > 20) throw new InvalidDataException("Choose between one and twenty reviewed spot IDs.");
            return selected;
        }
        var defaults = new List<Case>();
        foreach (var activity in new[] { "gathering", "hunting", "grinding" })
        {
            var item = available.FirstOrDefault(value => value.Spot.Activity == activity);
            if (item is not null) defaults.Add(item);
        }
        var pair = available.GroupBy(value => Normalize(value.Spot.Name)).FirstOrDefault(group => group.Count() > 1);
        if (pair is not null) defaults.AddRange(pair.Take(2));
        if (defaults.Count == 0) throw new InvalidDataException("No harvested spot has three uniquely known session-item columns.");
        return defaults.DistinctBy(value => value.Spot.GarmothSpotId).ToList();
    }

    internal static bool Verify(JsonObject readback, SessionDraft draft)
    {
        if (readback["done"]?.GetValue<bool>() != true || readback["failed"]?.GetValue<bool>() == true ||
            readback["spotId"]?.GetValue<string>() != draft.SpotId || Normalize(readback["heading"]?.GetValue<string>() ?? "") != Normalize(draft.SpotName) ||
            readback["saveAttempts"]?.GetValue<int>() != 0 || readback["submitAttempts"]?.GetValue<int>() != 0 ||
            draft.DurationSeconds % 60 != 0 ||
            readback["hours"]?.GetValue<string>() != (draft.DurationSeconds / 3600).ToString(CultureInfo.InvariantCulture) ||
            readback["minutes"]?.GetValue<string>() != (draft.DurationSeconds % 3600 / 60).ToString(CultureInfo.InvariantCulture) ||
            readback["agrisActive"]?.GetValue<bool>() != draft.AgrisActive ||
            !NumberEquals(readback["dropRate"], draft.AdditionalDropRate) || !NumberEquals(readback["dropAmount"], draft.AdditionalDropAmount)) return false;
        var columns = readback["columns"] as JsonArray;
        return columns is not null && draft.Items.All(item =>
        {
            var matched = columns.Where(column => Normalize(column?["name"]?.GetValue<string>() ?? "") == Normalize(item.Name)).ToArray();
            return matched.Length == 1 && matched[0]?["value"]?.GetValue<string>() == item.Quantity.ToString(CultureInfo.InvariantCulture);
        });
    }

    private static bool NumberEquals(JsonNode? value, decimal? expected) => value is JsonValue node &&
        node.TryGetValue<string>(out var text) && decimal.TryParse(text, NumberStyles.AllowDecimalPoint | NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var number) && number == expected;

    internal static string? SafeCode(JsonNode? value) => value is JsonValue node && node.TryGetValue<string>(out var text) &&
        Regex.IsMatch(text, @"^[a-z][a-z0-9_]{0,80}$", RegexOptions.CultureInvariant) ? text : null;

    internal static JsonArray SanitizeSkipped(JsonArray? skipped, SessionDraft draft)
    {
        var result = new JsonArray();
        foreach (var entry in skipped ?? [])
        {
            var id = entry?["itemId"] is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;
            var item = entry?["index"] is JsonValue indexValue && indexValue.TryGetValue<int>(out var index)
                && index >= 0 && index < draft.Items.Count ? draft.Items[index] : null;
            if (item?.ItemId != id) continue;
            if (item is null) continue;
            result.Add(new JsonObject { ["itemId"] = id, ["name"] = item.Name, ["reason"] = SafeCode(entry?["reason"]) });
        }
        return result;
    }

    private static string? SafeMessage(JsonNode? value)
    {
        if (value is not JsonValue node || !node.TryGetValue<string>(out var text)) return null;
        text = Regex.Replace(text, @"https?://\S+|/grind-tracker/\S+", "[URL omitted]", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        text = Regex.Replace(text, @"\s+", " ").Trim();
        return text[..Math.Min(text.Length, 500)];
    }

    private static JsonObject? SanitizeNavigationStep(string raw)
    {
        // The production diagnostic prefix contains the current path. Drop it
        // entirely, and whitelist only non-routing fields from the JSON step.
        var start = raw.IndexOf('{');
        if (start < 0) return null;
        try
        {
            if (JsonNode.Parse(raw[start..]) is not JsonObject step) return null;
            return new JsonObject
            {
                ["state"] = SafeCode(step["state"]), ["action"] = SafeCode(step["action"]),
                ["code"] = SafeCode(step["code"]), ["message"] = SafeMessage(step["message"]),
                ["phase"] = SafeCode(step["phase"]), ["visibilityState"] = SafeCode(step["visibilityState"]),
                ["elapsedMs"] = SafeElapsed(step["elapsedMs"]), ["scriptElapsedMs"] = SafeElapsed(step["scriptElapsedMs"]),
                ["expectedNavigationArmed"] = SafeBoolean(step["expectedNavigationArmed"]),
                ["matchingNavigation"] = SafeBoolean(step["matchingNavigation"]), ["nativeSuccess"] = SafeBoolean(step["nativeSuccess"]),
                ["matchesLastActionDestination"] = SafeBoolean(step["matchesLastActionDestination"]), ["isNewDocument"] = SafeBoolean(step["isNewDocument"]),
                ["documentReadyState"] = SafeCode(step["documentReadyState"]),
                ["bodyTextLength"] = SafeCount(step["bodyTextLength"]), ["bodyElementCount"] = SafeCount(step["bodyElementCount"]),
                ["mainCount"] = SafeCount(step["mainCount"]), ["grindMenuCount"] = SafeCount(step["grindMenuCount"]),
                ["headingCount"] = SafeCount(step["headingCount"]), ["visibleHeadingCount"] = SafeCount(step["visibleHeadingCount"]),
                ["visibleControlCount"] = SafeCount(step["visibleControlCount"]), ["httpStatusCode"] = SafeCount(step["httpStatusCode"]),
                ["webErrorStatus"] = step["webErrorStatus"] is JsonValue error && error.TryGetValue<string>(out var errorName)
                    && Regex.IsMatch(errorName, "^[A-Za-z][A-Za-z0-9]{0,64}$", RegexOptions.CultureInvariant) ? errorName : null,
                ["attempt"] = SafeCount(step["attempt"])
            };
        }
        catch (JsonException) { return null; }
    }

    private static long? SafeElapsed(JsonNode? value) => value is JsonValue node && node.TryGetValue<long>(out var elapsed)
        && elapsed is >= 0 and <= 120000 ? elapsed : null;
    private static bool? SafeBoolean(JsonNode? value) => value is JsonValue node && node.TryGetValue<bool>(out var flag) ? flag : null;
    private static int? SafeCount(JsonNode? value) => value is JsonValue node && node.TryGetValue<int>(out var count)
        && count is >= 0 and <= 1000000 ? count : null;

    internal static async Task<JsonObject> ReadBackAsync(CoreWebView2 core, SessionDraft draft, CancellationToken cancellation)
    {
        var key = "__bslIndependentReadback_" + Guid.NewGuid().ToString("N");
        var options = new JsonObject
        {
            ["key"] = key, ["spotId"] = draft.SpotId, ["name"] = draft.SpotName,
            ["deadline"] = DateTimeOffset.UtcNow.AddSeconds(40).ToUnixTimeMilliseconds()
        };
        try
        {
            var started = JsonNode.Parse(await core.ExecuteScriptAsync(StartReadBack.Replace("__OPTIONS__", options.ToJsonString())).WaitAsync(cancellation));
            if (started?["started"]?.GetValue<bool>() != true) return new JsonObject { ["done"] = true, ["failed"] = true, ["reason"] = "entry_form_not_identified" };
            while (true)
            {
                await Task.Delay(50, cancellation);
                var readback = JsonNode.Parse(await core.ExecuteScriptAsync("(()=>{const s=window[" + JsonSerializer.Serialize(key) + "];return s?.done?s:{done:false}})()").WaitAsync(cancellation)) as JsonObject;
                if (readback?["done"]?.GetValue<bool>() == true) return readback;
                if (DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() >= options["deadline"]!.GetValue<long>()) throw new TimeoutException();
            }
        }
        finally
        {
            try { await core.ExecuteScriptAsync("(()=>{const k=" + JsonSerializer.Serialize(key) + ";if(window[k])window[k].cancelled=true;return true})()").WaitAsync(TimeSpan.FromSeconds(1)); }
            catch { /* The owned window is closed next; no late field writes exist. */ }
        }
    }

    // Test-only guard installed before production Send. It observes/prevents any
    // final Save action; no production helper or account APIs are exposed here.
    internal const string SaveGuard = """
        (()=>{
          if(window!==top||location.origin!=='https://garmoth.com')return false;
          if(window.__bslMultiSpotNoSave)return true;
          const state={saveAttempts:0,submitAttempts:0};window.__bslMultiSpotNoSave=state;
          window.addEventListener('click',e=>{
            const button=e.target?.closest?.('button,[role=button],input[type=submit]');
            const name=(button?.innerText||button?.textContent||button?.value||'').trim().replace(/\s+/g,' ');
            if(button&&/^save(?: session)?$/i.test(name)){state.saveAttempts++;e.preventDefault();e.stopImmediatePropagation();}
          },true);
          window.addEventListener('submit',e=>{state.submitAttempts++;e.preventDefault();e.stopImmediatePropagation();},true);
          return true;
        })()
        """;

    // Independent DOM assertions: never calls production matching/readback
    // functions, never reads history rows, and never mutates inputs or clicks.
    private const string StartReadBack = """
        (()=>{
          const o=__OPTIONS__;
          const norm=v=>String(v||'').normalize('NFC').replace(/’/g,"'").trim().replace(/\s+/g,' ').toLowerCase();
          const text=e=>(e?.innerText||e?.textContent||'').trim().replace(/\s+/g,' ');
          const visible=e=>!!e?.getClientRects().length&&getComputedStyle(e).visibility!=='hidden'&&getComputedStyle(e).display!=='none';
          const source=location.href;
          const route=()=>{const m=/^\/grind-tracker\/(?!null\/|undefined\/)[^/]+\/spot\/([1-9][0-9]*)\/?$/.exec(location.pathname);return m?.[1]||null;};
          const headings=()=>[...document.querySelectorAll('h1')].filter(visible);
          if(window!==top||location.origin!=='https://garmoth.com'||route()!==o.spotId||headings().length!==1||norm(text(headings()[0]))!==norm(o.name))return {started:false};
          const tables=[...document.querySelectorAll('table')].filter(visible).filter(t=>t.tHead&&[...t.tHead.querySelectorAll('th')].some(h=>/^hours$/i.test(text(h)))&&[...t.tHead.querySelectorAll('th')].some(h=>/^(?:mins|minutes)$/i.test(text(h))));
          if(tables.length!==1||tables[0].tBodies.length!==1||tables[0].tBodies[0].rows.length!==1||!window.__bslMultiSpotNoSave)return {started:false};
          const table=tables[0],row=table.tBodies[0].rows[0];
          // The captured form has one header row and unspanned body cells. Fail
          // rather than assume indices if another site layout changes that.
          if(table.tHead.rows.length!==1||[...table.rows].some(r=>[...r.cells].some(c=>c.colSpan!==1||c.rowSpan!==1)))return {started:false};
          const headers=[...table.tHead.rows[0].cells];
          if(headers.length!==row.cells.length)return {started:false};
          let editor=table.parentElement;
          for(let depth=0;editor&&editor!==document.body&&depth<6;depth++,editor=editor.parentElement){if([...editor.querySelectorAll('button')].filter(b=>/^save(?: session)?$/i.test(text(b))).length===1)break;}
          if(!editor||editor===document.body)return {started:false};
          const state={done:false,failed:false,cancelled:false,columns:[],spotId:route(),heading:text(headings()[0])};window[o.key]=state;
          const active=()=>window[o.key]===state&&!state.cancelled&&Date.now()<o.deadline&&location.href===source&&table.isConnected&&route()===o.spotId&&norm(text(headings()[0]))===norm(o.name);
          const assert=()=>{if(!active())throw new Error('readback stopped');};
          const pause=ms=>new Promise(r=>setTimeout(r,ms));
          const poppers=()=>[...document.querySelectorAll('.v-popper__popper--shown[aria-hidden="false"],[role=tooltip]')].filter(visible);
          const tooltipText=p=>text(p.querySelector('.v-popper__inner')||p);
          const valueAt=index=>{const fields=[...row.cells[index].querySelectorAll('input')];return fields.length===1?fields[0].value:null;};
          const field=name=>{const indices=headers.map((h,i)=>norm(text(h))===name?i:-1).filter(i=>i>=0);return indices.length===1?valueAt(indices[0]):null;};
          const percent=label=>{const labels=[...editor.querySelectorAll('p')].filter(p=>norm(text(p))===label);if(labels.length!==1)return null;const fields=[...labels[0].parentElement.querySelectorAll('input')];return fields.length===1?fields[0].value:null;};
          (async()=>{
            try{
              for(let i=0;i<headers.length;i++){
                assert();const header=headers[i];
                if(header.querySelectorAll('img').length!==1)continue;
                const image=header.querySelector('img');
                const trigger=image.closest('.v-popper--has-tooltip');
                if(!trigger||!header.contains(trigger))continue;
                const before=new Map(poppers().map(p=>[p,tooltipText(p)]));
                trigger.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,view:window}));assert();
                trigger.dispatchEvent(new MouseEvent('mouseenter',{bubbles:false,view:window}));
                try{
                  await pause(450);assert();
                  const ids=new Set([trigger,...trigger.querySelectorAll('[aria-describedby]')].flatMap(e=>(e.getAttribute('aria-describedby')||'').split(/\s+/)).filter(Boolean));
                  const shown=poppers(),associated=shown.filter(p=>ids.has(p.id));
                  const candidates=associated.length?associated:shown.filter(p=>!before.has(p)||before.get(p)!==tooltipText(p));
                  if(candidates.length===1)state.columns.push({column:i,name:tooltipText(candidates[0]),value:valueAt(i)});
                }finally{
                  if(active()){trigger.dispatchEvent(new MouseEvent('mouseout',{bubbles:true,view:window}));assert();trigger.dispatchEvent(new MouseEvent('mouseleave',{bubbles:false,view:window}));await pause(35);}
                }
              }
              assert();
              state.hours=field('hours');state.minutes=field('mins')??field('minutes');
              state.dropRate=percent('additional drop rate');state.dropAmount=percent('additional drop amount');
              const agris=headers.filter(h=>norm(text(h))==='agris');
              state.agrisHeaderHtml=agris.length===1?agris[0].outerHTML.slice(0,6000):null;
              const agrisInputs=agris.length===1?[...row.cells[headers.indexOf(agris[0])].querySelectorAll('input')]:[];
              state.agrisInputHtml=agrisInputs.length===1?agrisInputs[0].outerHTML.slice(0,6000):null;
              const svg=agris.length===1&&agris[0].querySelectorAll('svg').length===1?agris[0].querySelector('svg'):null;
              const path=svg?.querySelectorAll('path').length===1?svg.querySelector('path').getAttribute('d'):null;
              const cross='M342.6 150.6c12.5-12.5 12.5-32.8 0-45.3s-32.8-12.5-45.3 0L192 210.7L86.6 105.4c-12.5-12.5-32.8-12.5-45.3 0s-12.5 32.8 0 45.3L146.7 256L41.4 361.4c-12.5 12.5-12.5 32.8 0 45.3s32.8 12.5 45.3 0L192 301.3l105.4 105.3c12.5 12.5 32.8 12.5 45.3 0s12.5-32.8 0-45.3L237.3 256z';
              const check='M438.6 105.4c12.5 12.5 12.5 32.8 0 45.3l-256 256c-12.5 12.5-32.8 12.5-45.3 0l-128-128c-12.5-12.5-12.5-32.8 0-45.3s32.8-12.5 45.3 0L160 338.7l233.4-233.3c12.5-12.5 32.8-12.5 45.3 0z';
              state.agrisActive=svg?.getAttribute('viewBox')==='0 0 384 512'&&path===cross?false:svg?.getAttribute('viewBox')==='0 0 448 512'&&path===check?true:null;
              state.saveAttempts=window.__bslMultiSpotNoSave?.saveAttempts;state.submitAttempts=window.__bslMultiSpotNoSave?.submitAttempts;
              state.done=true;
            }catch(_){state.failed=true;state.done=true;}
          })();return {started:true};
        })()
        """;

    internal static void CheckBackground(EmbeddedGarmothBrowser service)
    {
        var failure = BackgroundFailure(CaptureBackground(service));
        if (failure is not null) throw new BackgroundGuardException(failure);
    }

    internal static JsonObject CaptureBackground(EmbeddedGarmothBrowser service,
        GarmothBrowserWindow? observedWindow = null, int activatedEvents = 0)
    {
        var current = service.CurrentWindow;
        var observed = observedWindow ?? current;
        var handle = observed is null ? IntPtr.Zero : new WindowInteropHelper(observed).Handle;
        return new JsonObject
        {
            ["currentWindowPresent"] = current is not null,
            ["currentWindowClosed"] = current?.IsConnectionClosed,
            ["currentCorePresent"] = service.CurrentCore is not null,
            ["sameObservedWindow"] = observed is not null && ReferenceEquals(current, observed),
            ["observedWindowClosed"] = observed?.IsConnectionClosed,
            ["backgroundMode"] = current?.IsBackgroundPreparation,
            ["isActive"] = observed?.IsActive,
            ["showActivated"] = observed?.ShowActivated,
            ["showInTaskbar"] = observed?.ShowInTaskbar,
            ["ownedHwndIsForeground"] = handle != IntPtr.Zero && handle == GetForegroundWindow(),
            ["ownedActivatedEvents"] = activatedEvents
        };
    }

    // Every old stop condition is retained. Missing/closed connections are a
    // failed case, not evidence of foreground theft; actual activation wins if
    // both are observed. No external window title, HWND or account URL is saved.
    internal static string? BackgroundFailure(JsonObject state)
    {
        bool IsTrue(string key) => state[key]?.GetValue<bool>() == true;
        if (IsTrue("isActive") || IsTrue("ownedHwndIsForeground") ||
            state["ownedActivatedEvents"]?.GetValue<int>() > 0)
            return "background_activation_detected";
        if (!IsTrue("currentWindowPresent") || IsTrue("currentWindowClosed") || IsTrue("observedWindowClosed"))
            return "background_connection_closed";
        if (!IsTrue("sameObservedWindow")) return "background_connection_replaced";
        if (!IsTrue("backgroundMode") || IsTrue("showActivated") || IsTrue("showInTaskbar"))
            return "background_configuration_violation";
        return null;
    }

    private sealed class BackgroundProbe : IDisposable
    {
        private readonly EmbeddedGarmothBrowser _service;
        private readonly GarmothBrowserWindow? _window;
        private readonly JsonArray _checkpoints = [];
        private int _activatedEvents;

        internal BackgroundProbe(EmbeddedGarmothBrowser service, JsonObject result)
        {
            _service = service;
            _window = service.CurrentWindow;
            result["backgroundCheckpoints"] = _checkpoints;
            result["activationObservationStartsAfterSynchronousShow"] = true;
            if (_window is not null) _window.Activated += OnActivated;
            Record("initialization_started");
        }

        private void OnActivated(object? sender, EventArgs args)
        {
            _activatedEvents++;
            Record("owned_window_activated");
        }

        internal JsonObject Record(string stage)
        {
            var state = CaptureBackground(_service, _window, _activatedEvents);
            state["stage"] = stage;
            state["failureCode"] = BackgroundFailure(state);
            _checkpoints.Add(state);
            return state;
        }

        internal void Check(string stage)
        {
            var failure = BackgroundFailure(Record(stage));
            if (failure is not null) throw new BackgroundGuardException(failure);
        }

        public void Dispose() { if (_window is not null) _window.Activated -= OnActivated; }
    }

    private sealed class BackgroundGuardException(string code) : InvalidOperationException(code)
    {
        internal string Code { get; } = code;
    }
    private static string Normalize(string value) => Regex.Replace(value.Normalize(NormalizationForm.FormC).Replace('’', '\'').Trim(), @"\s+", " ").ToLowerInvariant();
    private static Task WriteAsync(string path, JsonNode value) => File.WriteAllTextAsync(path, value.ToJsonString(JsonOptions), Encoding.UTF8);
}
