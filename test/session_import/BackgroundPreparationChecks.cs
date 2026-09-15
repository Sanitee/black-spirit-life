using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;
using BlackSpiritLife.SessionImport;
using BlackSpiritLife.SessionImport.App;
using Microsoft.Web.WebView2.Core;

internal static class BackgroundPreparationChecks
{
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr(IntPtr handle, int index);

    internal static async Task RunAsync(string evidence)
    {
        Directory.CreateDirectory(evidence);
        CheckBackgroundDiagnostics();
        Check(string.IsNullOrEmpty(Environment.GetEnvironmentVariable("WEBVIEW2_USER_DATA_FOLDER")),
            "no process profile override can escape isolated fixture storage");
        // Runtime absence must not turn an offline regression into setup/download.
        Check(!string.IsNullOrWhiteSpace(CoreWebView2Environment.GetAvailableBrowserVersionString()), "installed WebView runtime is available");
        var foreground = GetForegroundWindow();
        var coldPreferences = new GarmothConnectionPreferences(Path.Combine(evidence, "held-" + Guid.NewGuid().ToString("N")));
        coldPreferences.SetRememberConnection(true);
        var preferencePath = Path.Combine(coldPreferences.RootDirectory, "connection.json");
        var preferenceBytes = File.ReadAllBytes(preferencePath);
        var preferenceTime = File.GetLastWriteTimeUtc(preferencePath);
        var held = new TaskCompletionSource<CoreWebView2Environment>(TaskCreationOptions.RunContinuationsAsynchronously);
        var environmentCalls = 0;
        var cold = new EmbeddedGarmothBrowser(coldPreferences, () => { environmentCalls++; return held.Task; });
        try
        {
            var first = cold.OpenForPreparationAsync();
            var window = cold.CurrentWindow!;
            CheckBackground(window, foreground);
            var second = cold.OpenForPreparationAsync();
            await Task.Delay(100);
            Check(!first.IsCompleted && !second.IsCompleted && environmentCalls == 1 && ReferenceEquals(window, cold.CurrentWindow),
                "cold and concurrent background opens await one initialization without replacement");
            Check(File.ReadAllBytes(preferencePath).SequenceEqual(preferenceBytes) && File.GetLastWriteTimeUtc(preferencePath) == preferenceTime,
                "restoring remembered choice does not rewrite unchanged preferences");
            await cold.CloseAsync();
            foreach (var open in new[] { first, second })
            {
                var cancelled = false;
                try { await open.WaitAsync(TimeSpan.FromSeconds(3)); }
                catch (OperationCanceledException) { cancelled = true; }
                Check(cancelled, "closing a pending background open cancels it");
            }
            held.TrySetCanceled();
            Check(cold.CurrentWindow is null && GetForegroundWindow() == foreground, "cold close cannot foreground or reopen a window");
            var closed = LiveMultiSpotChecks.CaptureBackground(cold, window);
            Check(LiveMultiSpotChecks.BackgroundFailure(closed) == "background_connection_closed" &&
                closed["ownedHwndIsForeground"]?.GetValue<bool>() == false && closed["isActive"]?.GetValue<bool>() == false,
                "a real closed offscreen connection fails lifecycle diagnostics without alleging activation");
        }
        finally { held.TrySetCanceled(); await cold.CloseAsync(); }

        var preferences = new GarmothConnectionPreferences(Path.Combine(evidence, "offline-" + Guid.NewGuid().ToString("N")));
        var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: preferences.UserDataFolder,
            options: new CoreWebView2EnvironmentOptions { ReleaseChannels = CoreWebView2ReleaseChannels.Stable });
        var service = new EmbeddedGarmothBrowser(preferences);
        var current = (GarmothBrowserWindow)typeof(EmbeddedGarmothBrowser)
            .GetMethod("CreateWindow", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(service, [null, false, false])!;
        current.ConfigureForBackground(null);
        SetField(service, "_window", current);
        current.Show();
        var release = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var requested = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        Func<string, (string Body, int Status)>? fixtureResponse = null;
        try
        {
            await current.InitializeBrowserAsync(environment, EmbeddedGarmothBrowser.ControllerOptions(environment, false));
            var core = current.Core!;
            core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
            core.WebResourceRequested += async (_, args) =>
            {
                using var deferral = args.GetDeferral();
                if (args.ResourceContext == CoreWebView2WebResourceContext.Document)
                {
                    requested.TrySetResult(true);
                    await release.Task;
                }
                // Every request, including unexpected destinations, stays offline.
                var reply = fixtureResponse?.Invoke(args.Request.Uri) ?? (Form, 200);
                args.Response = environment.CreateWebResourceResponse(new MemoryStream(Encoding.UTF8.GetBytes(reply.Item1)),
                    reply.Item2, reply.Item2 == 200 ? "OK" : "Fixture error", "Content-Type: text/html; charset=utf-8\r\nCache-Control: no-store");
            };
            typeof(EmbeddedGarmothBrowser).GetMethod("Configure", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(service, [current, true]);
            var initial = (Task)typeof(EmbeddedGarmothBrowser).GetMethod("OpenInitialPageAsync", BindingFlags.Instance | BindingFlags.NonPublic)!
                .Invoke(service, [current, CancellationToken.None])!;
            var opening = service.OpenForPreparationAsync();
            await requested.Task.WaitAsync(TimeSpan.FromSeconds(5));
            Check(!opening.IsCompleted, "background open does not return before its held initial document loads");
            CheckBackground(current, foreground);
            release.TrySetResult(true);
            await initial;
            await opening;
            await service.OpenForPreparationAsync();
            Check(ReferenceEquals(current, service.CurrentWindow) && ReferenceEquals(core, service.CurrentCore),
                "ready connection is reused without a second window or initialization");
            CheckBackground(current, foreground);
            await WriteSchedulingProbeAsync(core, evidence);
            var loadedStructure = JsonNode.Parse(await core.ExecuteScriptAsync(EmbeddedGarmothBrowser.PageStructureDiagnostic));
            Check(loadedStructure?["documentReadyState"]?.GetValue<string>() == "complete" &&
                loadedStructure["visibleHeadingCount"]?.GetValue<int>() > 0 && loadedStructure["bodyTextLength"]?.GetValue<int>() > 0,
                "read-only scalar diagnostics distinguish the loaded fixture structure without exporting its text");
            await core.ExecuteScriptAsync("document.body.innerHTML=''");
            var blankStructure = JsonNode.Parse(await core.ExecuteScriptAsync(EmbeddedGarmothBrowser.PageStructureDiagnostic));
            Check(blankStructure?["documentReadyState"]?.GetValue<string>() == "complete" &&
                blankStructure["visibleHeadingCount"]?.GetValue<int>() == 0 && blankStructure["visibleControlCount"]?.GetValue<int>() == 0 &&
                blankStructure["bodyTextLength"]?.GetValue<int>() == 0,
                "an empty complete document is recorded separately from a loaded tracker by diagnostics only");
            await File.WriteAllTextAsync(Path.Combine(evidence, "offline-page-structure.json"),
                new JsonObject { ["loaded"] = loadedStructure, ["blank"] = blankStructure }.ToJsonString(new() { WriteIndented = true }));
            await core.ExecuteScriptAsync("document.body.innerHTML=" + System.Text.Json.JsonSerializer.Serialize(Form));
            var phases = new List<JsonObject>();
            service.NavigationDiagnostic = raw => phases.Add((JsonObject)JsonNode.Parse(raw)!);
            var now = DateTimeOffset.UtcNow;
            var draft = new SessionDraft("background-fixture", now, now.AddMinutes(5), "77", "Rusalka's Coral", "gathering", 900,
                [new SessionItem("4001", 0, "Rough Stone", 1005)]);
            var result = await service.SendAsync(draft.ToPrepareMessage(), TimeSpan.FromSeconds(8));
            Check(result["ok"]?.GetValue<bool>() == true, "production preparation succeeds in the offscreen WebView: " + result);
            Check(phases.Any(phase => phase["phase"]?.GetValue<string>() == "discover_start") &&
                phases.Any(phase => phase["phase"]?.GetValue<string>() == "discover_complete" &&
                    phase["scriptElapsedMs"]?.GetValue<long>() >= 0 && phase["visibilityState"] is not null) &&
                phases.Any(phase => phase["phase"]?.GetValue<string>() == "cleanup_complete") &&
                phases.Select(phase => phase["elapsedMs"]!.GetValue<long>()).SequenceEqual(
                    phases.Select(phase => phase["elapsedMs"]!.GetValue<long>()).Order()),
                "opt-in phase timings are monotonic and include script runtime, visibility and cleanup without changing success");
            await File.WriteAllTextAsync(Path.Combine(evidence, "offline-preparation-phase-timings.json"),
                new JsonArray(phases.Select(phase => (JsonNode)phase.DeepClone()).ToArray()).ToJsonString(new() { WriteIndented = true }));
            service.NavigationDiagnostic = null;
            var values = JsonNode.Parse(await core.ExecuteScriptAsync("({quantity:document.querySelector('#quantity').value,saves:window.saves||0})"))!;
            Check(values["quantity"]?.GetValue<string>() == "1005" && values["saves"]?.GetValue<int>() == 0,
                "background preparation fills exact quantity without Save");
            CheckBackground(current, foreground);

            await DelayedSpaActionChecksAsync(service, core, draft, evidence);
            await TransientSpotNavigationChecksAsync(service, core, draft, evidence, response => fixtureResponse = response);

            var partialDraft = new SessionDraft("background-partial-fixture", now, now.AddMinutes(5), "77", "Rusalka's Coral", "gathering", 900,
                [new SessionItem("4001", 0, "Rough Stone", 1005), new SessionItem("4203", 0, "Platinum Ore", 7)]);
            var partial = await service.SendAsync(partialDraft.ToPrepareMessage(), TimeSpan.FromSeconds(8));
            var statusText = ((System.Windows.Controls.TextBlock)current.FindName("StatusText")).Text;
            Check(partial["ok"]?.GetValue<bool>() == true && (partial["skipped"] as JsonArray)?.Count == 1 &&
                statusText.Contains("Incomplete") && statusText.Contains("1 entered") && statusText.Contains("1 not entered") &&
                !statusText.Contains("Session prepared"), "partial field entry reports exact incomplete counts without claiming the whole session was prepared");

            await core.ExecuteScriptAsync("document.body.innerHTML='<h1>Grind Tracker</h1><main></main>'");
            var missing = JsonNode.Parse(await core.ExecuteScriptAsync(EmbeddedGarmothNavigationScripts.Discover(
                draft.ToPrepareMessage()["draft"]!.ToJsonString())))!;
            Check(missing["code"]?.GetValue<string>() == "no_matching_link", "unhydrated fixture reaches the real missing-link discovery code");
            var hydration = service.SendAsync(draft.ToPrepareMessage(), TimeSpan.FromSeconds(7));
            await Task.Delay(600);
            Check(!hydration.IsCompleted, "missing-link discovery waits for client-rendered controls instead of failing immediately");
            await core.ExecuteScriptAsync("document.body.innerHTML=" + System.Text.Json.JsonSerializer.Serialize(Form));
            Check((await hydration)["ok"]?.GetValue<bool>() == true, "real production discovery resumes when the session controls hydrate");

            await core.ExecuteScriptAsync("document.body.innerHTML='<h1>Grind Tracker</h1><main></main>'");
            var elapsed = System.Diagnostics.Stopwatch.StartNew();
            var absent = await service.SendAsync(draft.ToPrepareMessage(), TimeSpan.FromSeconds(7));
            Check(absent["ok"]?.GetValue<bool>() == false && elapsed.ElapsedMilliseconds >= 3900 && elapsed.ElapsedMilliseconds < 6500 &&
                absent["message"]!.GetValue<string>().Contains("No matching rendered link"),
                "persistently absent link stops after the bounded four-second document settling window");

            elapsed.Restart();
            var timedOut = await service.SendAsync(draft.ToPrepareMessage(), TimeSpan.FromMilliseconds(300));
            Check(timedOut["ok"]?.GetValue<bool>() == false && elapsed.ElapsedMilliseconds < 2500,
                "a shorter caller deadline still cancels the missing-link settling wait");
            await core.ExecuteScriptAsync("document.body.innerHTML=" + System.Text.Json.JsonSerializer.Serialize(Form));
            await Task.Delay(450);
            Check(JsonNode.Parse(await core.ExecuteScriptAsync("document.querySelector('#quantity').value"))!.GetValue<string>() == "0",
                "timed-out settling cannot fill controls which appear later");

            await core.ExecuteScriptAsync("document.body.innerHTML=" + System.Text.Json.JsonSerializer.Serialize(
                Form.Replace("value=\"77\">Rusalka's Coral", "value=\"88\">Another Spot")));
            elapsed.Restart();
            var wrongEditor = await service.SendAsync(draft.ToPrepareMessage(), TimeSpan.FromSeconds(7));
            Check(wrongEditor["ok"]?.GetValue<bool>() == false && elapsed.ElapsedMilliseconds < 2000 &&
                wrongEditor["message"]!.GetValue<string>().Contains("Review or close the current form"),
                "an explicit wrong editor still fails immediately without the missing-link wait");
            CheckBackground(current, foreground);
            await ScriptDialogSuppressionChecksAsync(service, current, draft, evidence, foreground);
            await core.ExecuteScriptAsync("window.open('https://discord.com/oauth2/authorize','background_auth_fixture')");
            await Task.Delay(150);
            var status = await service.SendAsync(new JsonObject { ["type"] = "status", ["protocolVersion"] = 1 }, TimeSpan.FromSeconds(2));
            Check(status["state"]?.GetValue<string>() == "login_required" && status["message"]!.GetValue<string>().Contains("Open Garmoth"),
                "background authentication popup is suppressed with actionable login-required status");
            Check(((ICollection<GarmothBrowserWindow>)ReadField(service, "_children")!).Count == 0,
                "background authentication creates no popup window");
            await ReusedWindowAuthenticationChecksAsync(service, current, foreground);
            CheckBackground(current, foreground);
        }
        finally { release.TrySetResult(true); await service.CloseAsync(); }
        Check(GetForegroundWindow() == foreground, "background test cleanup preserves the foreground window");
        Console.WriteLine("Background preparation checks passed using only offscreen nonactivating windows, intercepted requests and isolated fixture storage. Explicit visible Open/Review are not invoked while the user is playing.");
    }

    private const string Form = """
        <!doctype html><html><body><h1>Grind Tracker</h1><section role="dialog" aria-label="Add session">
        <h2>Add session</h2><label>Spot<select><option value="77">Rusalka's Coral</option></select></label>
        <label>Hours<input type="number" value="0"></label><label>Minutes<input type="number" value="0"></label>
        <h3>Loot</h3><div data-item-id="4001"><span>Rough Stone</span><label>Quantity<input id="quantity" type="number" value="0"></label></div>
        <button onclick="window.saves=(window.saves||0)+1">Save</button></section></body></html>
        """;

    private static async Task WriteSchedulingProbeAsync(CoreWebView2 core, string evidence)
    {
        const string key = "__bslOfflineSchedulingProbe";
        var elapsed = System.Diagnostics.Stopwatch.StartNew();
        await core.ExecuteScriptAsync("""
            (() => {
              const s={visibilityState:document.visibilityState,started:performance.now(),timer0:null,timer100:null,animationFrame:null};
              window.__bslOfflineSchedulingProbe=s;
              const save=k=>{if(window.__bslOfflineSchedulingProbe===s)s[k]=Math.round(performance.now()-s.started)};
              setTimeout(()=>save('timer0'),0);setTimeout(()=>save('timer100'),100);requestAnimationFrame(()=>save('animationFrame'));
              return true;
            })()
            """);
        JsonObject? observation = null;
        try
        {
            do
            {
                await Task.Delay(50);
                observation = JsonNode.Parse(await core.ExecuteScriptAsync("window." + key)) as JsonObject;
                if (observation?["timer0"] is not null && observation["timer100"] is not null && observation["animationFrame"] is not null) break;
            } while (elapsed.ElapsedMilliseconds < 2500);
            observation ??= [];
            observation.Remove("started");
            observation["hostElapsedMs"] = elapsed.ElapsedMilliseconds;
            observation["boundedObservationMs"] = 2500;
            observation["interceptedOfflineFixture"] = true;
            observation["regularScriptPollingMayInfluenceScheduling"] = true;
            observation["browserSettingsChanged"] = false;
            await File.WriteAllTextAsync(Path.Combine(evidence, "offline-background-scheduling-probe.json"), observation.ToJsonString(new() { WriteIndented = true }));
        }
        finally { await core.ExecuteScriptAsync("delete window." + key); }
    }

    private static async Task DelayedSpaActionChecksAsync(EmbeddedGarmothBrowser service, CoreWebView2 core,
        SessionDraft draft, string evidence)
    {
        const string summary = "https://garmoth.com/grind-tracker/offline/summary";
        var initialSource = core.Source;
        foreach (var wrongDestination in new[] { false, true })
        {
            // These are independent operations. Do not inherit the prior
            // draft/document's deliberately retained category-selection state.
            var scenarioDraft = draft with { DraftId = "spa-fixture-" + Guid.NewGuid().ToString("N") };
            var target = wrongDestination ? "https://garmoth.com/grind-tracker/unexpected/summary" : summary;
            var click = "event.preventDefault();this.setAttribute('aria-selected','true');setTimeout(()=>{history.pushState({},'',"
                + System.Text.Json.JsonSerializer.Serialize(target) + ");document.body.innerHTML="
                + System.Text.Json.JsonSerializer.Serialize(Form) + ";},600)";
            var html = "<h1>Grind Tracker</h1><main><div id='grind-menu'><aside style='width:320px'><a href='" + summary + "'>"
                + "<button type='button'>Grinding</button><button type='button' onclick=\"" + System.Net.WebUtility.HtmlEncode(click)
                + "\">Lifeskill</button><button type='button'>Scrolls</button><button type='button'>Dungeon</button></a>"
                + "</aside></div><div class='skeleton'>Loading tracker</div></main>";
            await core.ExecuteScriptAsync("history.replaceState({},''," + System.Text.Json.JsonSerializer.Serialize(initialSource)
                + ");document.body.innerHTML=" + System.Text.Json.JsonSerializer.Serialize(html));
            var phases = new JsonArray();
            service.NavigationDiagnostic = raw => phases.Add(JsonNode.Parse(raw));
            try
            {
                var result = await service.SendAsync(scenarioDraft.ToPrepareMessage(), TimeSpan.FromSeconds(5));
                var values = JsonNode.Parse(await core.ExecuteScriptAsync("({quantity:document.querySelector('#quantity')?.value,saves:window.saves||0})"));
                var record = new JsonObject
                {
                    ["wrongDestination"] = wrongDestination, ["delayMs"] = 600,
                    ["response"] = result.DeepClone(), ["values"] = values, ["phases"] = phases
                };
                await File.WriteAllTextAsync(Path.Combine(evidence, wrongDestination ? "unexpected-spa-action.json" : "delayed-expected-spa-action.json"),
                    record.ToJsonString(new() { WriteIndented = true }));
                if (wrongDestination)
                    Check(result["ok"]?.GetValue<bool>() == false && values?["quantity"]?.GetValue<string>() == "0" &&
                        values["saves"]?.GetValue<int>() == 0 && phases.Any(phase => phase?["code"]?.GetValue<string>() == "unexpected_source_change"),
                        "a delayed SPA route different from the exact observed Summary still cancels with no field writes or Save");
                else
                    Check(result["ok"]?.GetValue<bool>() == true && values?["quantity"]?.GetValue<string>() == "1005" &&
                        values["saves"]?.GetValue<int>() == 0 && !phases.Any(phase => phase?["phase"]?.GetValue<string>() == "cancellation_requested"),
                        "the exact observed Summary transition delayed beyond150ms is awaited before preparation without cancellation");
            }
            finally { service.NavigationDiagnostic = null; }
        }
        await core.ExecuteScriptAsync("history.replaceState({},''," + System.Text.Json.JsonSerializer.Serialize(initialSource)
            + ");document.body.innerHTML=" + System.Text.Json.JsonSerializer.Serialize(Form));
    }

    private static async Task TransientSpotNavigationChecksAsync(EmbeddedGarmothBrowser service, CoreWebView2 core,
        SessionDraft draft, string evidence, Action<Func<string, (string Body, int Status)>?> setResponse)
    {
        const string destination = "https://garmoth.com/grind-tracker/offline/spot/77";
        var initialSource = core.Source;
        foreach (var status in new[] { 500, 502, 503, 504 })
            Check(EmbeddedGarmothBrowser.IsTransientSpotResponse(status, CoreWebView2WebErrorStatus.Unknown), "confirmed transient HTTP" + status + " can qualify for one exact-spot retry");
        foreach (var status in new[] { 0, 200, 401, 403, 404, 429 })
            Check(!EmbeddedGarmothBrowser.IsTransientSpotResponse(status, CoreWebView2WebErrorStatus.Unknown), "HTTP" + status + " never qualifies for transient server retry");
        foreach (var error in new[] { CoreWebView2WebErrorStatus.OperationCanceled, CoreWebView2WebErrorStatus.ConnectionAborted,
            CoreWebView2WebErrorStatus.CertificateExpired, CoreWebView2WebErrorStatus.CertificateIsInvalid,
            CoreWebView2WebErrorStatus.ValidAuthenticationCredentialsRequired, CoreWebView2WebErrorStatus.ValidProxyAuthenticationRequired })
            Check(!EmbeddedGarmothBrowser.IsTransientSpotResponse(500, error), error + " remains nonretryable even alongside a5xx status");
        try
        {
            foreach (var scenario in new[] { "recover", "permanent", "escape", "unauthorized", "forbidden", "not_found", "rate_limit", "challenge" })
            {
                var requests = 0;
                var status = scenario switch { "unauthorized" => 401, "forbidden" => 403, "not_found" => 404, "rate_limit" => 429, "challenge" => 503, _ => 500 };
                setResponse(uri =>
                {
                    if (uri != destination) return ("<h1>Offline fixture</h1>", 200);
                    requests++;
                    return scenario == "recover" && requests == 2 ? (Form, 200)
                        : (scenario == "challenge" ? "<h1>Verify you are human</h1>" : "<h1>" + status + "</h1><p>Fixture server error</p>", status);
                });
                var seed = "<h1>Grind Tracker</h1><main><a href='" + destination + "'>Rusalka's Coral</a></main>";
                await core.ExecuteScriptAsync("history.replaceState({},''," + System.Text.Json.JsonSerializer.Serialize(initialSource)
                    + ");document.body.innerHTML=" + System.Text.Json.JsonSerializer.Serialize(seed));
                var retryObserved = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                var phases = new JsonArray();
                service.NavigationDiagnostic = raw =>
                {
                    var phase = JsonNode.Parse(raw)!;
                    phases.Add(phase);
                    if (phase["phase"]?.GetValue<string>() == "destination_retry_wait") retryObserved.TrySetResult(true);
                };
                var active = service.SendAsync((draft with { DraftId = "http-fixture-" + Guid.NewGuid().ToString("N") }).ToPrepareMessage(), TimeSpan.FromSeconds(6));
                if (scenario == "escape")
                {
                    await retryObserved.Task.WaitAsync(TimeSpan.FromSeconds(3));
                    await core.ExecuteScriptAsync("history.pushState({},'', '/grind-tracker/unexpected/summary')");
                }
                var result = await active;
                var values = JsonNode.Parse(await core.ExecuteScriptAsync("({quantity:document.querySelector('#quantity')?.value||null,written:document.querySelectorAll('[data-bsl-session-import-written]').length,saves:window.saves||0})"));
                await File.WriteAllTextAsync(Path.Combine(evidence, "http-retry-" + scenario + ".json"), new JsonObject
                {
                    ["scenario"] = scenario, ["requests"] = requests, ["response"] = result.DeepClone(), ["values"] = values, ["phases"] = phases
                }.ToJsonString(new() { WriteIndented = true }));
                if (scenario == "recover")
                    Check(requests == 2 && result["ok"]?.GetValue<bool>() == true && values?["quantity"]?.GetValue<string>() == "1005" && values["saves"]?.GetValue<int>() == 0,
                        "one confirmed500 then200 retries the identical observed spot and prepares without Save");
                else
                    Check(requests == (scenario == "permanent" ? 2 : 1) && result["ok"]?.GetValue<bool>() == false &&
                        values?["written"]?.GetValue<int>() == 0 && values["saves"]?.GetValue<int>() == 0,
                        "retry control " + scenario + " stops at its exact request bound without field writes or Save");
            }
        }
        finally
        {
            service.NavigationDiagnostic = null;
            setResponse(null);
            await core.ExecuteScriptAsync("history.replaceState({},''," + System.Text.Json.JsonSerializer.Serialize(initialSource)
                + ");document.body.innerHTML=" + System.Text.Json.JsonSerializer.Serialize(Form));
        }
    }

    private static async Task ReusedWindowAuthenticationChecksAsync(EmbeddedGarmothBrowser service,
        GarmothBrowserWindow window, IntPtr foreground)
    {
        Check(!EmbeddedGarmothBrowser.IsAuthenticationPopupSuppressed(false, false, false, false, true),
            "only an active explicit nonpreparing opener remains eligible for authentication");
        foreach (var flags in new[]
        {
            (true, false, false, false, true), (false, true, false, false, true),
            (false, false, true, false, true), (false, false, false, true, true),
            (false, false, false, false, false)
        })
            Check(EmbeddedGarmothBrowser.IsAuthenticationPopupSuppressed(flags.Item1, flags.Item2,
                flags.Item3, flags.Item4, flags.Item5),
                "each background, active/pending preparation or inactive-opener guard independently suppresses authentication");

        // Represent an already-open explicit window without displaying/activating it:
        // change only the mode flag, retaining the native offscreen NOACTIVATE styles.
        var mode = typeof(GarmothBrowserWindow).GetProperty("IsBackgroundPreparation", BindingFlags.Instance | BindingFlags.NonPublic)!;
        var priorBackgroundOperation = ReadField(service, "_backgroundOperationWindow");
        mode.SetValue(window, false);
        SetField(service, "_backgroundOperationWindow", null!);
        try
        {
            foreach (var phase in new[] { "active", "pending", "inactive" })
            {
                using var cancellation = new CancellationTokenSource();
                SetField(service, "_activeOperation", phase == "active" ? cancellation : null!);
                SetField(service, "_pendingPreparation", phase == "pending" ? cancellation : null!);
                SetField(service, "_backgroundLoginRequired", false);
                await window.Core!.ExecuteScriptAsync("window.open('https://discord.com/oauth2/authorize','reused_" + phase + "')");
                await Task.Delay(100);
                Check((bool)ReadField(service, "_backgroundLoginRequired")! &&
                    ((ICollection<GarmothBrowserWindow>)ReadField(service, "_children")!).Count == 0,
                    "reused nonbackground window suppresses authentication during " + phase + " state");
                if (phase != "inactive") Check(cancellation.IsCancellationRequested,
                    "suppressed authentication cancels " + phase + " preparation");
            }
            Check(!window.IsActive && GetForegroundWindow() == foreground,
                "reused-window authentication checks never activate an owned window");
        }
        finally
        {
            SetField(service, "_activeOperation", null!);
            SetField(service, "_pendingPreparation", null!);
            SetField(service, "_backgroundOperationWindow", priorBackgroundOperation!);
            mode.SetValue(window, true);
        }
    }

    private static async Task ScriptDialogSuppressionChecksAsync(EmbeddedGarmothBrowser service, GarmothBrowserWindow window,
        SessionDraft draft, string evidence, IntPtr foreground)
    {
        var core = window.Core!;
        Check(!core.Settings.AreDefaultScriptDialogsEnabled, "native script dialogs are disabled before document preparation");
        var kinds = new List<string>();
        var beforeUnload = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        void Observed(object? sender, CoreWebView2ScriptDialogOpeningEventArgs args)
        {
            kinds.Add(args.Kind.ToString());
            if (args.Kind == CoreWebView2ScriptDialogKind.Beforeunload) beforeUnload.TrySetResult(true);
            // Observer never Accepts, defers or displays the site's text.
        }
        core.ScriptDialogOpening += Observed;
        var activations = 0;
        void Activated(object? sender, EventArgs args) => activations++;
        window.Activated += Activated;
        try
        {
            await core.ExecuteScriptAsync("document.body.innerHTML='<h1>Grind Tracker</h1><main></main>'");
            var active = service.SendAsync((draft with { DraftId = "dialog-fixture-" + Guid.NewGuid().ToString("N") }).ToPrepareMessage(), TimeSpan.FromSeconds(3));
            await Task.Delay(150);
            Check(!active.IsCompleted, "the alert fixture interrupts a real pending preparation rather than an idle fake");
            await core.ExecuteScriptAsync("alert('Offline fixture alert')").WaitAsync(TimeSpan.FromSeconds(3));
            var stopped = await active;
            Check(stopped["ok"]?.GetValue<bool>() == false && stopped["code"]?.GetValue<string>() == "script_dialog_review_required" &&
                stopped["message"]!.GetValue<string>().Contains("Open Garmoth to review"),
                "background alert is suppressed and preparation stops with an actionable review requirement");
            var answers = JsonNode.Parse(await core.ExecuteScriptAsync("({confirmed:confirm('Offline fixture confirm'),prompted:prompt('Offline fixture prompt','fixture default')})").WaitAsync(TimeSpan.FromSeconds(3)));
            Check(answers?["confirmed"]?.GetValue<bool>() == false && answers["prompted"] is null,
                "suppressed confirm returns false and prompt returns null without implicit consent");
            var status = await service.SendAsync(new JsonObject { ["type"] = "status", ["protocolVersion"] = 1 }, TimeSpan.FromSeconds(2));
            Check(status["canPrepare"]?.GetValue<bool>() == false && status["message"]!.GetValue<string>().Contains("requested a dialog"),
                "read-only status does not claim readiness after a suppressed script dialog");

            // A beforeunload dialog requires sticky activation. This flag is set
            // inside an intercepted offline page via the host test API, never by
            // OS input or activation of any native window or real website.
            await core.CallDevToolsProtocolMethodAsync("Runtime.evaluate", new JsonObject
            {
                ["expression"] = "window.onbeforeunload=()=> 'Offline beforeunload'; navigator.userActivation.hasBeenActive",
                ["userGesture"] = true, ["returnByValue"] = true
            }.ToJsonString());
            var source = core.Source;
            core.Navigate("https://garmoth.com/grind-tracker/offline/spot/88");
            await beforeUnload.Task.WaitAsync(TimeSpan.FromSeconds(3));
            await Task.Delay(150);
            Check(core.Source == source, "declined background beforeunload prevents navigation instead of implicitly accepting departure");
            await core.ExecuteScriptAsync("window.onbeforeunload=null");
            Check(kinds.SequenceEqual(new[] { "Alert", "Confirm", "Prompt", "Beforeunload" }),
                "all four native script-dialog types reach the explicit suppression handler");
            Check(activations == 0 && !window.IsActive && GetForegroundWindow() == foreground,
                "script dialog suppression creates no owned activation or foreground change");
            await File.WriteAllTextAsync(Path.Combine(evidence, "offline-script-dialog-suppression.json"), new JsonObject
            {
                ["dialogKinds"] = new JsonArray(kinds.Select(kind => (JsonNode?)JsonValue.Create(kind)).ToArray()),
                ["response"] = stopped.DeepClone(), ["answers"] = answers,
                ["ownedActivations"] = activations, ["foregroundUnchanged"] = GetForegroundWindow() == foreground,
                ["foregroundDialogPathInvoked"] = false, ["allRequestsIntercepted"] = true
            }.ToJsonString(new() { WriteIndented = true }));
        }
        finally
        {
            core.ScriptDialogOpening -= Observed;
            window.Activated -= Activated;
            await core.ExecuteScriptAsync("window.onbeforeunload=null");
        }
    }

    private static void CheckBackgroundDiagnostics()
    {
        var safe = new JsonObject
        {
            ["currentWindowPresent"] = true, ["currentWindowClosed"] = false,
            ["sameObservedWindow"] = true, ["observedWindowClosed"] = false,
            ["backgroundMode"] = true, ["isActive"] = false,
            ["showActivated"] = false, ["showInTaskbar"] = false,
            ["ownedHwndIsForeground"] = false, ["ownedActivatedEvents"] = 0
        };
        Check(LiveMultiSpotChecks.BackgroundFailure(safe) is null, "safe background snapshot passes unchanged isolation requirements");
        foreach (var key in new[] { "currentWindowClosed", "observedWindowClosed" })
        {
            var state = (JsonObject)safe.DeepClone();
            state[key] = true;
            Check(LiveMultiSpotChecks.BackgroundFailure(state) == "background_connection_closed", key + " is a lifecycle failure, not an activation claim");
        }
        var missing = (JsonObject)safe.DeepClone();
        missing["currentWindowPresent"] = false;
        Check(LiveMultiSpotChecks.BackgroundFailure(missing) == "background_connection_closed", "missing CurrentWindow still fails the case without alleging foreground theft");
        foreach (var key in new[] { "isActive", "ownedHwndIsForeground", "ownedActivatedEvents" })
        {
            var state = (JsonObject)missing.DeepClone();
            state[key] = key == "ownedActivatedEvents" ? JsonValue.Create(1) : JsonValue.Create(true);
            Check(LiveMultiSpotChecks.BackgroundFailure(state) == "background_activation_detected", key + " remains a hard stop even if the window subsequently closes");
        }
        foreach (var key in new[] { "backgroundMode", "showActivated", "showInTaskbar", "sameObservedWindow" })
        {
            var state = (JsonObject)safe.DeepClone();
            state[key] = key is "showActivated" or "showInTaskbar";
            Check(LiveMultiSpotChecks.BackgroundFailure(state) == (key == "sameObservedWindow"
                ? "background_connection_replaced" : "background_configuration_violation"), key + " retains its strict nonactivation guard");
        }
    }

    private static void CheckBackground(GarmothBrowserWindow window, IntPtr foreground)
    {
        Check(window.IsBackgroundPreparation && !window.ShowActivated && !window.ShowInTaskbar &&
            window.Left == -32000 && window.Top == -32000 && window.Width == 1100 && window.Height == 780,
            "background window retains normal viewport offscreen with no taskbar/activation request");
        var handle = new System.Windows.Interop.WindowInteropHelper(window).Handle;
        Check((GetWindowLongPtr(handle, -20).ToInt64() & 0x08000000) != 0 && !window.IsActive && GetForegroundWindow() == foreground,
            "native NOACTIVATE and unchanged foreground protect the user's active application");
    }
    private static object? ReadField(object instance, string name) => instance.GetType()
        .GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(instance);
    private static void SetField(object instance, string name, object value) => instance.GetType()
        .GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(instance, value);
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
        Console.WriteLine("PASS " + message);
    }
}
