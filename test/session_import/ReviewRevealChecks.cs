using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;
using System.Windows;
using BlackSpiritLife.SessionImport;
using BlackSpiritLife.SessionImport.App;
using Microsoft.Web.WebView2.Core;

internal static class ReviewRevealChecks
{
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr(IntPtr handle, int index);

    // Intercepted fixture only. No explicit foreground reveal, real website,
    // remembered profile, cookies, OS input, or Save is exercised here.
    internal static async Task RunAsync(string evidence)
    {
        Directory.CreateDirectory(evidence);
        var passed = 0;
        void Check(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
            passed++;
            Console.WriteLine("PASS " + message);
        }
        Check(string.IsNullOrEmpty(Environment.GetEnvironmentVariable("WEBVIEW2_USER_DATA_FOLDER")),
            "process-level profile override cannot escape the isolated fixture");
        Check(!string.IsNullOrWhiteSpace(CoreWebView2Environment.GetAvailableBrowserVersionString()),
            "installed runtime is used without setup or download");
        var preferences = new GarmothConnectionPreferences(Path.Combine(Path.GetFullPath(evidence), "profile-" + Guid.NewGuid().ToString("N")));
        var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: preferences.UserDataFolder,
            options: new CoreWebView2EnvironmentOptions { ReleaseChannels = CoreWebView2ReleaseChannels.Stable });
        Check(string.Equals(Path.GetFullPath(environment.UserDataFolder), Path.GetFullPath(preferences.UserDataFolder),
            StringComparison.OrdinalIgnoreCase), "WebView profile stays inside test evidence");
        var service = new EmbeddedGarmothBrowser(preferences);
        var owner = new Window { ShowActivated = false, ShowInTaskbar = false };
        var window = (GarmothBrowserWindow)typeof(EmbeddedGarmothBrowser)
            .GetMethod("CreateWindow", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(service, [null, false, false])!;
        window.ConfigureForBackground(owner);
        Set(service, "_window", window);
        var activations = 0;
        window.Activated += (_, _) => activations++;
        var initialForeground = GetForegroundWindow();
        var ownedForegroundSeen = false;
        void CheckHidden(string context)
        {
            var handle = new System.Windows.Interop.WindowInteropHelper(window).Handle;
            ownedForegroundSeen |= handle != IntPtr.Zero && GetForegroundWindow() == handle;
            Check(!window.IsConnectionClosed && window.IsBackgroundPreparation && !window.IsActive &&
                !window.ShowActivated && !window.ShowInTaskbar && window.Left == -32000 && window.Top == -32000 &&
                activations == 0 && !ownedForegroundSeen &&
                (handle == IntPtr.Zero || (GetWindowLongPtr(handle, -20).ToInt64() & 0x08000000) != 0),
                context + ": hidden placement, NOACTIVATE, no taskbar and zero owned activation remain intact");
        }
        window.Show();
        var traces = new List<JsonObject>();
        var responses = new JsonArray();
        var intercepted = 0;
        service.NavigationDiagnostic = raw => traces.Add((JsonObject)JsonNode.Parse(raw)!);
        try
        {
            await window.InitializeBrowserAsync(environment, EmbeddedGarmothBrowser.ControllerOptions(environment, false));
            var core = window.Core!;
            core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
            core.WebResourceRequested += (_, args) =>
            {
                intercepted++;
                // No branch passes through to the network, including subresources.
                args.Response = environment.CreateWebResourceResponse(new MemoryStream(Encoding.UTF8.GetBytes(Form)),
                    200, "OK", "Content-Type: text/html; charset=utf-8\r\nCache-Control: no-store");
            };
            typeof(EmbeddedGarmothBrowser).GetMethod("Configure", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(service, [window, true]);
            await (Task)typeof(EmbeddedGarmothBrowser).GetMethod("OpenInitialPageAsync", BindingFlags.Instance | BindingFlags.NonPublic)!
                .Invoke(service, [window, CancellationToken.None])!;
            CheckHidden("initial background document");

            async Task<string> PrepareAsync()
            {
                var now = DateTimeOffset.UtcNow;
                var draft = new SessionDraft("review-fixture-" + Guid.NewGuid().ToString("N"), now, now.AddMinutes(5),
                    "77", "Rusalka's Coral", "gathering", 900, [new SessionItem("4001", 0, "Rough Stone", 1005)]);
                var answer = await service.SendAsync(draft.ToPrepareMessage(), TimeSpan.FromSeconds(8));
                Check(answer["ok"]?.GetValue<bool>() == true && answer["matched"]?.GetValue<int>() == 1 &&
                    (answer["warnings"] as JsonArray)?.Count == 0, "production service prepares the intercepted form without warnings: " + answer);
                return draft.DraftId;
            }
            async Task<JsonObject> ReviewAsync(string id, bool automatic = true, TimeSpan? timeout = null)
            {
                var request = new JsonObject { ["type"] = "review", ["protocolVersion"] = 1, ["draftId"] = id };
                if (automatic) request["revealIfOwnerActive"] = true;
                var answer = await service.SendAsync(request, timeout ?? TimeSpan.FromSeconds(3));
                responses.Add(answer.DeepClone());
                return answer;
            }
            var draftId = await PrepareAsync();
            var before = await core.ExecuteScriptAsync("({value:document.querySelector('#quantity').value,saves:window.saves||0})");
            // A review must neither start nor cancel a preparation helper job.
            await core.ExecuteScriptAsync("window.jobReads=0;const originalJob=window.__bslSessionImportJob;Object.defineProperty(window,'__bslSessionImportJob',{configurable:true,get(){window.jobReads++;return originalJob}})");
            traces.Clear();
            foreach (var state in new[] { WindowState.Normal, WindowState.Minimized })
            {
                owner.WindowState = state;
                var reviewed = await ReviewAsync(draftId);
                Check(reviewed["ok"]?.GetValue<bool>() == true && reviewed["revealed"]?.GetValue<bool>() == false &&
                    reviewed["preparedFormMissing"] is null, "inactive/unshown owner defers review successfully: " + state);
                Check(Get(service, "_preparedDraftId") as string == draftId, "deferred review retains the exact prepared draft");
                CheckHidden("deferred review " + state);
            }
            Check(before == await core.ExecuteScriptAsync("({value:document.querySelector('#quantity').value,saves:window.saves||0})"),
                "repeated deferred review leaves exact quantities and Save count untouched");
            Check(JsonNode.Parse(await core.ExecuteScriptAsync("window.jobReads"))!.GetValue<int>() == 0 &&
                !traces.Any(trace => trace["phase"]?.GetValue<string>()?.StartsWith("cleanup_", StringComparison.Ordinal) == true),
                "review performs no helper Start/Cancel access or prepare-only cleanup");
            await core.ExecuteScriptAsync("Object.defineProperty(window,'__bslSessionImportJob',{configurable:true,writable:true,value:null})");
            Set(window, "_revealOwner", null);
            Check(!window.TryShowForUserIfOwnerActive(), "missing owner cannot trigger an automatic reveal");
            CheckHidden("missing owner");
            Set(window, "_revealOwner", owner);

            var malformed = new JsonObject { ["type"] = "review", ["protocolVersion"] = 1, ["draftId"] = draftId, ["revealIfOwnerActive"] = "true" };
            var invalid = await service.SendAsync(malformed, TimeSpan.FromSeconds(3));
            Check(invalid["ok"]?.GetValue<bool>() == false && Get(service, "_preparedDraftId") as string == draftId,
                "malformed reveal flag is rejected without converting it to an explicit reveal or discarding the form");

            Set(service, "_opening", Task.FromException(new InvalidOperationException("Isolated transient opening failure")));
            var failed = await ReviewAsync(draftId);
            Set(service, "_opening", null);
            Check(failed["ok"]?.GetValue<bool>() == false && failed["preparedFormMissing"] is null &&
                Get(service, "_preparedDraftId") as string == draftId, "transient review opening failure preserves the prepared draft for retry");
            var held = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            Set(service, "_opening", held.Task);
            failed = await ReviewAsync(draftId, timeout: TimeSpan.FromMilliseconds(100));
            Set(service, "_opening", null);
            held.SetResult(true);
            Check(failed["ok"]?.GetValue<bool>() == false && failed["preparedFormMissing"] is null &&
                Get(service, "_preparedDraftId") as string == draftId, "review timeout preserves the prepared draft without a late reveal");
            Check((await ReviewAsync(draftId))["ok"]?.GetValue<bool>() == true, "explicit retry of deferred validation succeeds after a transient failure");
            CheckHidden("transient failure and retry");

            await core.ExecuteScriptAsync("document.querySelector('[role=dialog]').setAttribute('data-bsl-session-import-draft','different-draft')");
            failed = await ReviewAsync(draftId);
            Check(failed["ok"]?.GetValue<bool>() == false && failed["preparedFormMissing"]?.GetValue<bool>() == true &&
                Get(service, "_preparedDraftId") is null, "mismatched actual editor is flagged stale and clears prepared identity");
            draftId = await PrepareAsync();
            await core.ExecuteScriptAsync("document.querySelector('[role=dialog]').remove()");
            failed = await ReviewAsync(draftId, automatic: false);
            Check(failed["ok"]?.GetValue<bool>() == false && failed["preparedFormMissing"]?.GetValue<bool>() == true,
                "ordinary explicit Review still validates the form before any reveal; removed form is flagged stale");
            CheckHidden("stale form");
            await service.CloseAsync();
            failed = await ReviewAsync(draftId);
            Check(failed["ok"]?.GetValue<bool>() == false && failed["preparedFormMissing"]?.GetValue<bool>() == true,
                "closed browser is a missing prepared form, not a successful deferred reveal");
            Check(activations == 0 && !ownedForegroundSeen && intercepted > 0,
                "all checks used intercepted resources with zero owned activation or foreground reveal");
            await File.WriteAllTextAsync(Path.Combine(evidence, "review-reveal-report.json"), new JsonObject
            {
                ["passed"] = passed, ["responses"] = responses, ["ownedActivations"] = activations,
                ["ownedForegroundObserved"] = ownedForegroundSeen, ["externalForegroundChanged"] = initialForeground != GetForegroundWindow(),
                ["interceptedRequests"] = intercepted, ["allWebViewRequestsIntercepted"] = true,
                ["foregroundRevealExercised"] = false, ["saveInvoked"] = false,
                ["scope"] = "Offline production-service review validation and deferred reveal; explicit active-owner reveal is not exercised while the user plays."
            }.ToJsonString(new() { WriteIndented = true }));
            Console.WriteLine($"{passed} offscreen review-reveal checks passed. No real website or foreground reveal was exercised.");
        }
        finally { Set(service, "_opening", null); await service.CloseAsync(); owner.Close(); }
    }

    private static object? Get(object instance, string name) => instance.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(instance);
    private static void Set(object instance, string name, object? value) => instance.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(instance, value);
    private const string Form = """
        <!doctype html><html><body><h1>Grind Tracker</h1><section role="dialog" aria-label="Add session">
        <h2>Add session</h2><label>Spot<select><option value="77">Rusalka's Coral</option></select></label>
        <label>Hours<input type="number" value="0"></label><label>Minutes<input type="number" value="0"></label>
        <h3>Loot</h3><div data-item-id="4001"><span>Rough Stone</span><label>Quantity<input id="quantity" type="number" value="0"></label></div>
        <button onclick="window.saves=(window.saves||0)+1">Save</button></section></body></html>
        """;
}
