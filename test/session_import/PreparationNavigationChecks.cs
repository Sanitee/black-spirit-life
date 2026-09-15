using System.IO;
using System.Reflection;
using System.Text;
using System.Text.Json.Nodes;
using BlackSpiritLife.SessionImport;
using BlackSpiritLife.SessionImport.App;
using Microsoft.Web.WebView2.Core;

internal static class PreparationNavigationChecks
{
    private const string PublicUrl = "https://garmoth.com/best-grind-spots";
    private const string SummaryUrl = "https://garmoth.com/grind-tracker/summary";
    private const string SpotUrl = "https://garmoth.com/grind-tracker/spot/coral";
    private const string OtherUrl = "https://garmoth.com/grind-tracker/spot/other";

    // These deliberately small, intercepted DOM fixtures prove the production
    // service contract, not parity with an authenticated live Garmoth account.
    internal static async Task RunAsync(string evidence)
    {
        Directory.CreateDirectory(evidence);
        await using var fixture = await Fixture.OpenAsync(evidence);
        await ColdOpenChecksAsync(fixture, evidence);

        fixture.Pages[PublicUrl] = "<h1>Best Grind Spots</h1><a href='/grind-tracker/summary'>My Grind Tracker</a>";
        fixture.Pages[SummaryUrl] = "<h1>Grind Tracker</h1><a href='/grind-tracker/spot/other'>Bloody Monastery</a><a href='/grind-tracker/spot/coral'>Rusalka's Coral</a>";
        fixture.Pages[SpotUrl] = Editor(open: false);
        await fixture.NavigateAsync(PublicUrl);
        var initialDocuments = fixture.Documents.Count;
        var status = await fixture.Service.SendAsync(StatusRequest(), TimeSpan.FromSeconds(2));
        Require(status["canPrepare"]?.GetValue<bool>() == false, "public status is not preparation-ready");
        Require(fixture.Core.Source == PublicUrl && fixture.Documents.Count == initialDocuments,
            "read-only status does not navigate or start a preparation");
        var prepared = await fixture.Service.SendAsync(Draft(metadata: true), TimeSpan.FromSeconds(8));
        Require(prepared["ok"]?.GetValue<bool>() == true, "public-to-summary-to-exact-spot prepares: " + prepared);
        var browserStatus = ((System.Windows.Controls.TextBlock)fixture.Window.FindName("StatusText")).Text;
        Require(browserStatus.Contains("prepared", StringComparison.OrdinalIgnoreCase)
            && !browserStatus.Contains("Entering", StringComparison.OrdinalIgnoreCase),
            "successful preparation replaces browser progress with its prepared status");
        Require(fixture.Documents.Skip(initialDocuments).SequenceEqual([SummaryUrl, SpotUrl]),
            "only rendered summary and exact Rusalka links were navigated");
        var values = await fixture.ValuesAsync();
        Require(values["hours"]?.GetValue<string>() == "0" && values["minutes"]?.GetValue<string>() == "15",
            "duration is filled through the production service");
        Require(values["quantity"]?.GetValue<string>() == "1005", "selected spot quantity is filled");
        Require(values["agris"]?.GetValue<string>() == "750" && values["rate"]?.GetValue<string>() == "35"
            && values["amount"]?.GetValue<string>() == "100", "explicit optional numeric metadata is filled");
        Require(values["addClicks"]?.GetValue<int>() == 1 && values["saves"]?.GetValue<int>() == 0,
            "Add is explicit and Save is never invoked");
        await using (var capture = File.Create(Path.Combine(evidence, "preparation-navigation-fixture.png")))
            await fixture.Core.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, capture);
        Pass("public page reaches the rendered exact spot and fills duration/items/optional metadata without Save");

        fixture.Pages[SpotUrl] = Editor(open: true, metadataValue: "23");
        await fixture.NavigateAsync(SpotUrl);
        initialDocuments = fixture.Documents.Count;
        prepared = await fixture.Service.SendAsync(Draft(), TimeSpan.FromSeconds(8));
        values = await fixture.ValuesAsync();
        Require(prepared["ok"]?.GetValue<bool>() == true, "already-open matching editor prepares: " + prepared);
        Require(fixture.Documents.Count == initialDocuments && values["addClicks"]?.GetValue<int>() == 0,
            "already-open form needs no navigation or Add click");
        Require(values["agris"]?.GetValue<string>() == "23" && values["rate"]?.GetValue<string>() == "23"
            && values["amount"]?.GetValue<string>() == "23", "omitted optional metadata leaves existing values alone");
        Require(values["saves"]?.GetValue<int>() == 0, "existing editor is never saved");
        Pass("already-open matching editor is filled in place and absent metadata is not invented");

        fixture.Pages[OtherUrl] = Editor(open: true, wrongSpot: true);
        await fixture.NavigateAsync(OtherUrl);
        initialDocuments = fixture.Documents.Count;
        var refused = await fixture.Service.SendAsync(Draft(metadata: true), TimeSpan.FromSeconds(3));
        values = await fixture.ValuesAsync();
        Require(refused["ok"]?.GetValue<bool>() == false, "unrelated existing editor is refused");
        Require(((System.Windows.Controls.TextBlock)fixture.Window.FindName("StatusText")).Text
            .Contains(refused["message"]!.GetValue<string>(), StringComparison.Ordinal),
            "wrong-spot failure is displayed in the browser with the response message");
        Require(fixture.Documents.Count == initialDocuments, "wrong editor is not navigated away without consent");
        RequireUntouched(values, "wrong spot");
        Pass("wrong-spot editor is not filled or submitted");

        fixture.Pages[SpotUrl] = Editor(open: false, editorDelayMs: 1400);
        await fixture.NavigateAsync(SpotUrl);
        var active = fixture.Service.SendAsync(Draft(), TimeSpan.FromSeconds(5));
        await fixture.WaitForAddAsync(active);
        await fixture.NavigateAsync(OtherUrl);
        refused = await active.WaitAsync(TimeSpan.FromSeconds(5));
        await Task.Delay(1600);
        Require(refused["ok"]?.GetValue<bool>() == false, "unexpected navigation cancels active preparation");
        RequireUntouched(await fixture.ValuesAsync(), "unexpected destination");
        Pass("unexpected navigation cancels the active service operation before destination writes");

        fixture.Pages[SpotUrl] = Editor(open: false, editorDelayMs: 1800);
        await fixture.NavigateAsync(SpotUrl);
        active = fixture.Service.SendAsync(Draft(metadata: true), TimeSpan.FromMilliseconds(600));
        await fixture.WaitForAddAsync(active);
        refused = await active.WaitAsync(TimeSpan.FromSeconds(5));
        await Task.Delay(2000);
        Require(refused["ok"]?.GetValue<bool>() == false, "held editor preparation times out");
        RequireUntouched(await fixture.ValuesAsync(), "late editor after timeout");
        prepared = await fixture.Service.SendAsync(Draft(), TimeSpan.FromSeconds(8));
        Require(prepared["ok"]?.GetValue<bool>() == true, "explicit retry after timeout can prepare: " + prepared);
        Require((await fixture.ValuesAsync())["saves"]?.GetValue<int>() == 0, "timeout/retry never saves");
        Pass("timeout blocks late writes and releases the service for a new explicit preparation");

        const string sidebarUrl = "https://garmoth.com/grind-tracker/best-grind-spots";
        const string sidebarSummaryUrl = "https://garmoth.com/grind-tracker/user/summary";
        fixture.Pages[sidebarUrl] = Sidebar(collapsed: false, selected: false);
        await fixture.NavigateAsync(sidebarUrl);
        var sidebarDraft = (JsonObject)Draft()["draft"]!;
        var discovery = JsonNode.Parse(await fixture.Core.ExecuteScriptAsync(
            EmbeddedGarmothNavigationScripts.Discover(sidebarDraft.ToJsonString()))) as JsonObject;
        Require(discovery?["state"]?.GetValue<string>() == "act" &&
            discovery["action"]?.GetValue<string>() == "select_activity" &&
            discovery["expectedUrl"]?.GetValue<string>() == sidebarSummaryUrl,
            "observed Lifeskill control identifies only its rendered parent summary link");
        await fixture.Core.ExecuteScriptAsync("document.querySelector('#categories').setAttribute('href','/grind-tracker/other/summary')");
        var rejectedAction = JsonNode.Parse(await fixture.Core.ExecuteScriptAsync(
            EmbeddedGarmothNavigationScripts.Execute(sidebarDraft.ToJsonString(), "select_activity",
                DateTimeOffset.UtcNow.AddSeconds(5).ToUnixTimeMilliseconds(), sidebarSummaryUrl))) as JsonObject;
        Require(rejectedAction?["acted"]?.GetValue<bool>() == false && fixture.Core.Source == sidebarUrl,
            "changed parent destination is rejected before clicking or navigating");

        fixture.Pages[sidebarUrl] = Sidebar(collapsed: true, selected: false);
        fixture.Pages[sidebarSummaryUrl] = Sidebar(collapsed: false, selected: true);
        fixture.Pages[SpotUrl] = Editor(open: false);
        await fixture.NavigateAsync(sidebarUrl);
        initialDocuments = fixture.Documents.Count;
        prepared = await fixture.Service.SendAsync(Draft(), TimeSpan.FromSeconds(8));
        Require(prepared["ok"]?.GetValue<bool>() == true,
            "actual-sidebar-shaped BACK/Lifeskill parent-link preparation succeeds: " + prepared);
        Require(fixture.Documents.Skip(initialDocuments).SequenceEqual([sidebarSummaryUrl, SpotUrl]),
            "scoped Lifeskill click follows only its observed summary and exact Rusalka destination");
        values = await fixture.ValuesAsync();
        Require(values["minutes"]?.GetValue<string>() == "15" && values["quantity"]?.GetValue<string>() == "1005"
            && values["saves"]?.GetValue<int>() == 0, "sidebar navigation fills the correct form without Save");
        Pass("intercepted real-sidebar structure supports BACK, Lifeskill parent navigation, exact spot and changed-href refusal");

        fixture.Pages[SpotUrl] = Editor(open: false, editorDelayMs: 1800);
        await fixture.NavigateAsync(SpotUrl);
        active = fixture.Service.SendAsync(Draft(), TimeSpan.FromSeconds(5));
        await fixture.WaitForAddAsync(active);
        await fixture.Service.CloseAsync();
        refused = await active.WaitAsync(TimeSpan.FromSeconds(5));
        Require(refused["ok"]?.GetValue<bool>() == false && fixture.Window.IsConnectionClosed,
            "closing the service cancels its active preparation and destroys the document");
        Require(ReadField(fixture.Service, "_activeOperation") is null && ReadField(fixture.Service, "_preparedDraftId") is null,
            "close leaves no active operation or prepared draft identity");
        var closedStatus = await fixture.Service.SendAsync(StatusRequest(), TimeSpan.FromSeconds(1));
        Require(closedStatus["connected"]?.GetValue<bool>() == false, "closed service does not claim readiness");
        Require(fixture.UnhandledRequests == 0, "every WebView resource request was intercepted");
        Pass("close cancels preparation and clears readiness without reopening a browser");
        Console.WriteLine("11 production-service preparation navigation checks passed. Every WebView request was intercepted; isolated test storage only. No live account, actual website form parity, or saved session is claimed.");
    }

    private static async Task ColdOpenChecksAsync(Fixture fixture, string evidence)
    {
        fixture.Pages[GarmothNavigationPolicy.TrackerUrl] = Editor(open: true);
        fixture.HoldDocument();
        var initial = fixture.OpenInitialPageAsync();
        var reopen = fixture.Service.OpenAsync();
        var prepare = fixture.Service.SendAsync(Draft(), TimeSpan.FromSeconds(8));
        await fixture.DocumentHeld.Task.WaitAsync(TimeSpan.FromSeconds(5));
        await Task.Delay(100);
        Require(!initial.IsCompleted && !reopen.IsCompleted && !prepare.IsCompleted &&
            ReadField(fixture.Service, "_activeOperation") is null,
            "cold Open and immediate Prepare wait before arming against the initial document");
        fixture.ReleaseDocument();
        await initial;
        await reopen;
        var prepared = await prepare;
        Require(prepared["ok"]?.GetValue<bool>() == true, "first cold preparation succeeds without retry: " + prepared);
        var values = await fixture.ValuesAsync();
        Require(values["quantity"]?.GetValue<string>() == "1005" && values["saves"]?.GetValue<int>() == 0,
            "cold preparation fills once without saving");
        Pass("held production initial navigation is awaited by Open and the first Prepare without a retry");

        fixture.HoldDocument();
        initial = fixture.OpenInitialPageAsync();
        prepare = fixture.Service.SendAsync(Draft(), TimeSpan.FromMilliseconds(250));
        await fixture.DocumentHeld.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var refused = await prepare.WaitAsync(TimeSpan.FromSeconds(3));
        Require(refused["ok"]?.GetValue<bool>() == false, "initial loading is inside the caller's preparation deadline");
        fixture.ReleaseDocument();
        await initial;
        await Task.Delay(200);
        RequireUntouched(await fixture.ValuesAsync(), "initial document arriving after Prepare timeout");
        prepared = await fixture.Service.SendAsync(Draft(), TimeSpan.FromSeconds(8));
        Require(prepared["ok"]?.GetValue<bool>() == true, "only an explicit retry prepares after initial-load timeout");
        Pass("initial-load timeout cannot resume a stale preparation when the page eventually arrives");

        fixture.HoldDocument();
        initial = fixture.OpenInitialPageAsync();
        prepare = fixture.Service.SendAsync(Draft(), TimeSpan.FromSeconds(8));
        await fixture.DocumentHeld.Task.WaitAsync(TimeSpan.FromSeconds(5));
        fixture.Pages[OtherUrl] = Editor(open: true, wrongSpot: true);
        await fixture.NavigateAsync(OtherUrl);
        refused = await prepare;
        Require(refused["ok"]?.GetValue<bool>() == false, "unexpected navigation while initially opening cancels preparation");
        var openingFailed = false;
        try { await initial; }
        catch (InvalidOperationException) { openingFailed = true; }
        Require(openingFailed, "aborted or replaced initial navigation fails its opening task");
        fixture.ReleaseDocument();
        RequireUntouched(await fixture.ValuesAsync(), "unexpected initial destination");
        Pass("initial navigation accepts only its own navigation identity and never fills a user-selected destination");

        var preferences = new GarmothConnectionPreferences(Path.Combine(Path.GetFullPath(evidence),
            "held-initialization-" + Guid.NewGuid().ToString("N")));
        preferences.SetRememberConnection(true);
        var environment = new TaskCompletionSource<CoreWebView2Environment>(TaskCreationOptions.RunContinuationsAsynchronously);
        var service = new EmbeddedGarmothBrowser(preferences, () => environment.Task);
        var firstOpen = service.OpenAsync();
        var existingOpen = service.OpenAsync();
        prepare = service.SendAsync(Draft(), TimeSpan.FromMilliseconds(250));
        await Task.Delay(100);
        Require(!firstOpen.IsCompleted && !existingOpen.IsCompleted && !prepare.IsCompleted &&
            ReadField(service, "_window") is GarmothBrowserWindow { Core: null },
            "reopening the existing window also waits for pending environment initialization");
        refused = await prepare.WaitAsync(TimeSpan.FromSeconds(3));
        Require(refused["ok"]?.GetValue<bool>() == false, "Prepare deadline includes environment initialization");
        await service.CloseAsync();
        await firstOpen.WaitAsync(TimeSpan.FromSeconds(3));
        try { await existingOpen; throw new InvalidOperationException("Closed initialization was accepted."); }
        catch (OperationCanceledException) { }
        environment.TrySetCanceled();
        await Task.Delay(100);
        Require(ReadField(service, "_window") is null && ReadField(service, "_activeOperation") is null,
            "close cancels held Open calls and cannot reopen a window or resume a timed-out preparation");
        Pass("existing-window Open waits for initialization; timeout and close do not reopen or prepare late");
    }

    private static JsonObject Draft(bool metadata = false)
    {
        var now = DateTimeOffset.UtcNow;
        var draft = new SessionDraft("navigation-fixture-" + Guid.NewGuid().ToString("N"), now,
            now.AddMinutes(10), "coral", "Rusalka's Coral", "gathering", 900,
            [new SessionItem("4001", 0, "Rough Stone", 1005)]).ToPrepareMessage();
        if (metadata)
        {
            var session = (JsonObject)draft["draft"]!["session"]!;
            session["agrisUsed"] = 750;
            session["additionalDropRate"] = 35;
            session["additionalDropAmount"] = 100;
        }
        return draft;
    }

    private static JsonObject StatusRequest() => new() { ["type"] = "status", ["protocolVersion"] = 1 };

    private static string Sidebar(bool collapsed, bool selected) => $$"""
        <main><div id="grind-menu"><aside>
          <button type="button" {{(collapsed ? "" : "hidden")}} onclick="this.hidden=true;document.querySelector('#categories').hidden=false">BACK</button>
          <a id="categories" href="/grind-tracker/user/summary" {{(collapsed ? "hidden" : "")}}>
            <button type="button">Grinding</button>
            <button type="button" aria-pressed="{{(selected ? "true" : "false")}}">Lifeskill</button>
            <button type="button">Scrolls</button><button type="button">Dungeon</button>
          </a>
          {{(selected ? "<section><h3>Stone Spots</h3><a href='/grind-tracker/spot/coral'>Rusalka's Coral</a></section>" : "")}}
        </aside></div><h1>Grind Tracker</h1></main>
        """;

    private static string Editor(bool open, bool wrongSpot = false, int editorDelayMs = 0, string metadataValue = "0") => $$"""
        <h1>Grind Tracker</h1><h2>{{(wrongSpot ? "Bloody Monastery" : "Rusalka's Coral")}}</h2>
        <button type="button" onclick="window.addClicks=(window.addClicks||0)+1;setTimeout(()=>document.querySelector('[role=dialog]').hidden=false,{{editorDelayMs}})">Add session</button>
        <section role="dialog" aria-label="Add session" {{(open ? "" : "hidden")}}>
          <h2>Add session</h2>
          <label>Spot<select><option value="{{(wrongSpot ? "other" : "coral")}}">{{(wrongSpot ? "Bloody Monastery" : "Rusalka's Coral")}}</option></select></label>
          <label>Hours<input id="hours" type="number" value="0"></label>
          <label>Minutes<input id="minutes" type="number" value="0"></label>
          <label>Agris used<input id="agris" type="number" value="{{metadataValue}}"></label>
          <label>Additional drop rate<input id="rate" type="number" value="{{metadataValue}}"></label>
          <label>Additional drop amount<input id="amount" type="number" value="{{metadataValue}}"></label>
          <h3>Loot</h3><div data-item-id="4001"><span>Rough Stone</span><label>Quantity<input id="quantity" type="number" value="0"></label></div>
          <button type="button" onclick="window.saves=(window.saves||0)+1">Save</button>
        </section>
        """;

    private static object? ReadField(object instance, string name) => instance.GetType()
        .GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(instance);

    private static void RequireUntouched(JsonObject values, string context)
    {
        foreach (var name in new[] { "hours", "minutes", "quantity", "agris", "rate", "amount" })
            Require(values[name]?.GetValue<string>() == "0", context + " preserves " + name + ": " + values);
        Require(values["saves"]?.GetValue<int>() == 0, context + " never saves");
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private static void Pass(string message) => Console.WriteLine("PASS " + message);

    private sealed class Fixture : IAsyncDisposable
    {
        internal readonly Dictionary<string, string> Pages = new(StringComparer.Ordinal);
        internal readonly List<string> Documents = [];
        internal EmbeddedGarmothBrowser Service { get; }
        internal GarmothBrowserWindow Window { get; }
        internal CoreWebView2 Core => Window.Core ?? throw new InvalidOperationException("Fixture browser is closed.");
        internal int UnhandledRequests { get; private set; }
        private readonly CoreWebView2Environment _environment;
        private TaskCompletionSource<bool>? _heldDocument;
        internal TaskCompletionSource<bool> DocumentHeld { get; private set; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        private Fixture(EmbeddedGarmothBrowser service, GarmothBrowserWindow window, CoreWebView2Environment environment)
        {
            Service = service;
            Window = window;
            _environment = environment;
        }

        internal static async Task<Fixture> OpenAsync(string evidence)
        {
            var preferences = new GarmothConnectionPreferences(Path.Combine(Path.GetFullPath(evidence),
                "isolated-navigation-" + Guid.NewGuid().ToString("N")));
            var profileOverride = Environment.GetEnvironmentVariable("WEBVIEW2_USER_DATA_FOLDER");
            Require(string.IsNullOrEmpty(profileOverride), "fixture refuses a process-level WebView profile override");
            var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: preferences.UserDataFolder,
                options: new CoreWebView2EnvironmentOptions { ReleaseChannels = CoreWebView2ReleaseChannels.Stable });
            Require(string.Equals(Path.GetFullPath(environment.UserDataFolder), Path.GetFullPath(preferences.UserDataFolder),
                StringComparison.OrdinalIgnoreCase), "browser uses only the isolated fixture profile");
            var service = new EmbeddedGarmothBrowser(preferences);
            var window = (GarmothBrowserWindow)typeof(EmbeddedGarmothBrowser)
                .GetMethod("CreateWindow", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(service, [null, false, false])!;
            window.Show();
            try
            {
                await window.InitializeBrowserAsync(environment, EmbeddedGarmothBrowser.ControllerOptions(environment, remember: false));
                var fixture = new Fixture(service, window, environment);
                fixture.Core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
                fixture.Core.WebResourceRequested += fixture.Intercept;
                typeof(EmbeddedGarmothBrowser).GetField("_window", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(service, window);
                typeof(EmbeddedGarmothBrowser).GetMethod("Configure", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(service, [window, true]);
                return fixture;
            }
            catch { window.Close(); await service.CloseAsync(); throw; }
        }

        private async void Intercept(object? sender, CoreWebView2WebResourceRequestedEventArgs args)
        {
            using var deferral = args.GetDeferral();
            try
            {
                var body = string.Empty;
                var status = 200;
                if (args.ResourceContext == CoreWebView2WebResourceContext.Document)
                {
                    Documents.Add(args.Request.Uri);
                    var held = _heldDocument;
                    if (held is not null)
                    {
                        _heldDocument = null;
                        DocumentHeld.TrySetResult(true);
                        await held.Task;
                    }
                    if (!Pages.TryGetValue(args.Request.Uri, out body)) { body = "<p>Unknown intercepted fixture route.</p>"; status = 404; }
                }
                // Even unknown origins/resources receive an in-memory response;
                // there is no branch that lets a request reach the network.
                var html = "<!doctype html><html><head><meta charset='utf-8'><title>Isolated navigation fixture</title></head><body style='font:16px sans-serif;background:#17251f;color:white'>" + body + "</body></html>";
                args.Response = _environment.CreateWebResourceResponse(new MemoryStream(Encoding.UTF8.GetBytes(html)),
                    status, status == 200 ? "OK" : "Not Found", "Content-Type: text/html; charset=utf-8");
            }
            catch
            {
                UnhandledRequests++;
                args.Response = _environment.CreateWebResourceResponse(new MemoryStream(), 500, "Fixture failure", "Content-Type: text/plain");
            }
        }

        private TaskCompletionSource<bool>? _releaseDocument;
        internal void HoldDocument()
        {
            DocumentHeld = new(TaskCreationOptions.RunContinuationsAsynchronously);
            _heldDocument = _releaseDocument = new(TaskCreationOptions.RunContinuationsAsynchronously);
        }
        internal void ReleaseDocument() => _releaseDocument?.TrySetResult(true);
        internal Task OpenInitialPageAsync() => (Task)typeof(EmbeddedGarmothBrowser)
            .GetMethod("OpenInitialPageAsync", BindingFlags.Instance | BindingFlags.NonPublic)!
            .Invoke(Service, [Window, CancellationToken.None])!;

        internal async Task NavigateAsync(string uri)
        {
            var loaded = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            ulong? navigationId = null;
            void Starting(object? sender, CoreWebView2NavigationStartingEventArgs args)
            {
                if (args.Uri == uri && navigationId is null) navigationId = args.NavigationId;
            }
            void Completed(object? sender, CoreWebView2NavigationCompletedEventArgs args)
            {
                if (args.NavigationId == navigationId) loaded.TrySetResult(args.IsSuccess);
            }
            var core = Core;
            core.NavigationStarting += Starting;
            core.NavigationCompleted += Completed;
            try
            {
                core.Navigate(uri);
                Require(await loaded.Task.WaitAsync(TimeSpan.FromSeconds(10)), "offline fixture navigation completed");
            }
            finally { core.NavigationStarting -= Starting; core.NavigationCompleted -= Completed; }
        }

        internal async Task<JsonObject> ValuesAsync() => JsonNode.Parse(await Core.ExecuteScriptAsync("({hours:document.querySelector('#hours')?.value,minutes:document.querySelector('#minutes')?.value,quantity:document.querySelector('#quantity')?.value,agris:document.querySelector('#agris')?.value,rate:document.querySelector('#rate')?.value,amount:document.querySelector('#amount')?.value,addClicks:window.addClicks||0,saves:window.saves||0})")) as JsonObject
            ?? throw new InvalidOperationException("Offline fixture did not return values.");

        internal async Task WaitForAddAsync(Task<JsonObject> active)
        {
            var deadline = DateTime.UtcNow.AddSeconds(3);
            while (DateTime.UtcNow < deadline)
            {
                if ((await ValuesAsync())["addClicks"]?.GetValue<int>() == 1) return;
                if (active.IsCompleted) throw new InvalidOperationException("Preparation ended before exercising the held editor: " + await active);
                await Task.Delay(20);
            }
            throw new InvalidOperationException("Add was not clicked before the fixture deadline.");
        }

        public async ValueTask DisposeAsync() => await Service.CloseAsync();
    }
}
