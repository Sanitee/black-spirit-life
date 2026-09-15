using System.IO;
using System.Text;
using System.Text.Json.Nodes;
using BlackSpiritLife.SessionImport.App;
using Microsoft.Web.WebView2.Core;

internal static class ConnectionStatusChecks
{
    internal static async Task RunAsync(string evidence)
    {
        var preferences = new GarmothConnectionPreferences(Path.Combine(evidence, "isolated-status-" + Guid.NewGuid().ToString("N")));
        var service = new EmbeddedGarmothBrowser(preferences);
        var closed = await service.SendAsync(StatusRequest(), TimeSpan.FromSeconds(1));
        Check(closed, connected: false, "not_open", canPrepare: false);
        Assert(closed["remembered"]?.GetValue<bool>() == false, "closed connection defaults to no remembered login");
        preferences.SetRememberConnection(true);
        var remembered = await service.SendAsync(StatusRequest(), TimeSpan.FromSeconds(1));
        Check(remembered, connected: false, "not_open", canPrepare: false);
        Assert(remembered["remembered"]?.GetValue<bool>() == true, "remembered choice is independent of readiness/authentication");
        preferences.SetRememberConnection(false);

        var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: preferences.UserDataFolder,
            options: new CoreWebView2EnvironmentOptions { ReleaseChannels = CoreWebView2ReleaseChannels.Stable });
        var window = new GarmothBrowserWindow(remembered: false);
        window.Show();
        try
        {
            await window.InitializeBrowserAsync(environment, EmbeddedGarmothBrowser.ControllerOptions(environment, remember: false));
            var core = window.Core!;
            string html = string.Empty;
            core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
            core.WebResourceRequested += (_, args) =>
            {
                // All documents/resources are in-memory fixtures, never live requests.
                args.Response = environment.CreateWebResourceResponse(new MemoryStream(Encoding.UTF8.GetBytes(html)),
                    200, "OK", "Content-Type: text/html; charset=utf-8");
            };

            async Task<JsonObject> Page(string path, string body, string origin = "https://garmoth.com")
            {
                html = "<!doctype html><html><body style='background:white;color:black;font:16px sans-serif'>" + body + "</body></html>";
                var loaded = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                void Finished(object? sender, CoreWebView2NavigationCompletedEventArgs args) => loaded.TrySetResult(args.IsSuccess);
                core.NavigationCompleted += Finished;
                try
                {
                    core.Navigate(origin + path);
                    Assert(await loaded.Task.WaitAsync(TimeSpan.FromSeconds(10)), "offline page loaded");
                    return await Evaluate(core, EmbeddedGarmothScripts.ConnectionStatus());
                }
                finally { core.NavigationCompleted -= Finished; }
            }

            var noEditor = await Page("/best-grind-spots", "<h1>Best grind spots</h1><button aria-label='Account menu'>Account</button><p>Session history</p>");
            Check(noEditor, connected: true, "browser_open", canPrepare: false);
            var refused = await Evaluate(core, EmbeddedGarmothScripts.Start("not-editor", "{}", DateTimeOffset.UtcNow.AddSeconds(5).ToUnixTimeMilliseconds()));
            Assert(refused["started"]?.GetValue<bool>() == false, "public page cannot start preparation");

            var loggedOut = await Page("/best-grind-spots", "<h1>Best grind spots</h1><button>Login</button>");
            Check(loggedOut, connected: true, "login_required", canPrepare: false);
            var hiddenLogin = await Page("/best-grind-spots", "<button style='display:none'>Login</button><p>Login is available from the account menu.</p>");
            Check(hiddenLogin, connected: true, "browser_open", canPrepare: false);
            var unrelatedDialog = await Page("/grind-tracker/status-fixture", "<h1>Grind Tracker</h1><section role='dialog' aria-label='Sign in'><h2>Sign in</h2><input value='keep'><input value='also keep'></section>");
            Check(unrelatedDialog, connected: true, "login_required", canPrepare: false);

            var disabledAdd = await Page("/grind-tracker/status-fixture", "<h1>Grind Tracker</h1><button disabled>Add session</button>");
            Check(disabledAdd, connected: true, "browser_open", canPrepare: false);
            var usableAdd = await Page("/grind-tracker/status-fixture", "<h1>Grind Tracker</h1><button onclick='window.addClicks=(window.addClicks||0)+1'>Add session</button>");
            Check(usableAdd, connected: true, "tracker_ready", canPrepare: true);
            var untouched = await Evaluate(core, "({clicks:window.addClicks||0,job:!!window.__bslSessionImportJob})");
            Assert(untouched["clicks"]?.GetValue<int>() == 0 && untouched["job"]?.GetValue<bool>() == false,
                "readiness observation never clicks Add or starts a preparation");

            var sessionEditor = await Page("/grind-tracker/status-fixture", "<h1>Grind Tracker</h1><section role='dialog' aria-label='Add session'><input value='15'><input value='1005'></section>");
            Check(sessionEditor, connected: true, "tracker_ready", canPrepare: true);
            var outsideOrigin = await Page("/oauth2/authorize", "<button>Login</button>", "https://discord.com");
            Check(outsideOrigin, connected: false, "not_open", canPrepare: false);

            var maintenance = EmbeddedGarmothBrowser.ConnectionStatusResponse(true, "maintenance", false);
            Check(maintenance, connected: true, "maintenance", canPrepare: false);
            Console.WriteLine("PASS managed connection state: 11 offline state cases; isolated test profile and intercepted page requests only");
        }
        finally { window.Close(); await service.CloseAsync(); }
    }

    private static JsonObject StatusRequest() => new() { ["type"] = "status", ["protocolVersion"] = 1 };
    private static async Task<JsonObject> Evaluate(CoreWebView2 core, string script) =>
        JsonNode.Parse(await core.ExecuteScriptAsync(script)) as JsonObject ?? throw new InvalidOperationException("Expected an object from the offline page.");
    private static void Check(JsonObject result, bool connected, string state, bool canPrepare)
    {
        Assert(result["connected"]?.GetValue<bool>() == connected, state + " connection state: " + result);
        Assert(result["state"]?.GetValue<string>() == state, state + " explicit state: " + result);
        Assert(result["canPrepare"]?.GetValue<bool>() == canPrepare, state + " prepare state: " + result);
        if (result.ContainsKey("ok")) Assert(result["ok"]?.GetValue<bool>() == canPrepare, "protocol ok stays preparation-compatible");
    }
    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
