using System.IO;
using System.Text;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using BlackSpiritLife.SessionImport.App;
using Microsoft.Web.WebView2.Core;

internal static class EmbeddedBrowserChecks
{
    // No live website or account is used: every browser request is answered here.
    private const string Fixture = """
        <!doctype html><html><head><title>Offline session fixture</title></head>
        <body style="background:#121e1b;color:white;font:16px sans-serif">
        <h1>Grind Tracker</h1><section role="dialog" aria-label="Add session">
        <label>Spot<select><option value="coral">Rusalka's Coral</option></select></label>
        <label>Hours<input type="number" value="0"></label>
        <label>Minutes<input type="number" value="0"></label>
        <div data-item-id="4001"><span>Rough Stone</span><label>Quantity<input type="number" value="0"></label></div>
        <button type="button" onclick="window.submissions=(window.submissions||0)+1">Save</button>
        </section></body></html>
        """;

    internal static async Task RunAsync(string evidence)
    {
        Directory.CreateDirectory(evidence);
        var profile = Path.Combine(evidence, "isolated-webview-profile");
        var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: profile,
            options: new CoreWebView2EnvironmentOptions { ReleaseChannels = CoreWebView2ReleaseChannels.Stable });
        var persistent = await OpenFixture(environment, remember: true);
        try
        {
            var status = await Evaluate(persistent, EmbeddedGarmothScripts.Status());
            Check(status?["ready"]?.GetValue<bool>() == true, "real WebView recognizes the offline tracker form");
            var now = DateTimeOffset.UtcNow;
            var draft = new BlackSpiritLife.SessionImport.SessionDraft(
                "offline-embedded-check", now, now.AddMinutes(10), "coral", "Rusalka's Coral", "gathering", 900,
                [new BlackSpiritLife.SessionImport.SessionItem("4001", 0, "Rough Stone", 1005)]);
            var draftJson = draft.ToPrepareMessage()["draft"]!.ToJsonString();
            await persistent.Core!.ExecuteScriptAsync("document.querySelector('[role=dialog]').setAttribute('aria-label','Sign in');document.querySelector('[role=dialog]').appendChild(Object.assign(document.createElement('p'),{textContent:'Sign in to add a session'}))");
            var loginStatus = await Evaluate(persistent, EmbeddedGarmothScripts.Status());
            Check(loginStatus?["ready"]?.GetValue<bool>() == false, "unrelated sign-in dialog is not a session editor");
            var loginStart = await Evaluate(persistent, EmbeddedGarmothScripts.Start("login-dialog-job", draftJson, now.AddSeconds(5).ToUnixTimeMilliseconds()));
            Check(loginStart?["started"]?.GetValue<bool>() == false, "preparation never starts in a sign-in dialog");
            var untouched = await Evaluate(persistent, "({untouched:Array.from(document.querySelectorAll('input')).every(input=>input.value==='0'),saved:window.submissions||0})");
            Check(untouched?["untouched"]?.GetValue<bool>() == true && untouched?["saved"]?.GetValue<int>() == 0, "sign-in dialog inputs remain untouched");
            await persistent.Core.ExecuteScriptAsync("document.querySelector('[role=dialog]').setAttribute('aria-label','Add session')");
            var start = await Evaluate(persistent, EmbeddedGarmothScripts.Start("fixture-job", draftJson, now.AddSeconds(5).ToUnixTimeMilliseconds()));
            Check(start?["started"]?.GetValue<bool>() == true, "real embedded resource starts preparation");
            JsonObject? poll = null;
            for (var i = 0; i < 40; i++)
            {
                await Task.Delay(50);
                poll = await Evaluate(persistent, EmbeddedGarmothScripts.Poll("fixture-job"));
                if (poll?["done"]?.GetValue<bool>() == true) break;
            }
            Check(poll?["result"]?["ok"]?.GetValue<bool>() == true, "prepared draft passes real DOM readback: " + poll);
            Check((poll?["result"]?["matched"] as JsonArray)?.Count == 1, "one real matched item");
            var readback = await Evaluate(persistent, "({quantity:document.querySelector('[data-item-id] input').value,minutes:document.querySelectorAll('input')[1].value,saved:window.submissions||0})");
            Check(readback?["quantity"]?.GetValue<string>() == "1005", "grouped quantity preserved exactly");
            Check(readback?["minutes"]?.GetValue<string>() == "15", "duration preserved");
            Check(readback?["saved"]?.GetValue<int>() == 0, "no Save clicked");
            await Evaluate(persistent, EmbeddedGarmothScripts.Start("expired-job", draftJson, now.AddMinutes(-1).ToUnixTimeMilliseconds()));
            await Task.Delay(50);
            var expired = await Evaluate(persistent, EmbeddedGarmothScripts.Poll("expired-job"));
            Check(expired?["result"]?["ok"]?.GetValue<bool>() == false, "expired preparation refused");
            await persistent.Core!.ExecuteScriptAsync("document.cookie='bsl_fixture_remember=yes;max-age=3600;path=/;secure';localStorage.setItem('bsl_fixture','remembered')");
            await using var capture = File.Create(Path.Combine(evidence, "embedded-offline-prepared.png"));
            await persistent.Core.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, capture);
        }
        finally { persistent.Close(); }

        var reopened = await OpenFixture(environment, remember: true);
        try
        {
            var stored = await Evaluate(reopened, "({cookie:document.cookie,storage:localStorage.getItem('bsl_fixture')})");
            Check(stored?["cookie"]?.GetValue<string>().Contains("bsl_fixture_remember=yes") == true, "remembered session survives closing/reopening browser");
            Check(stored?["storage"]?.GetValue<string>() == "remembered", "remembered site storage retained");
            var privateWindow = await OpenFixture(environment, remember: false);
            try
            {
                var isolated = await Evaluate(privateWindow, "({cookie:document.cookie,storage:localStorage.getItem('bsl_fixture')})");
                Check(!isolated!["cookie"]!.GetValue<string>().Contains("bsl_fixture_remember"), "private mode never reuses remembered cookies");
                Check(isolated["storage"] is null, "private mode never reuses remembered storage");
                await privateWindow.Core!.ExecuteScriptAsync("document.cookie='bsl_fixture_private=yes;max-age=3600;path=/;secure';localStorage.setItem('bsl_private','private')");
            }
            finally { privateWindow.Close(); }
            await Task.Delay(250);
            var nextPrivate = await OpenFixture(environment, remember: false);
            try
            {
                var cleared = await Evaluate(nextPrivate, "({cookie:document.cookie,storage:localStorage.getItem('bsl_private')})");
                Check(!cleared!["cookie"]!.GetValue<string>().Contains("bsl_fixture_private"), "private sign-in discarded on connection close");
                Check(cleared["storage"] is null, "private storage discarded on close");
            }
            finally { nextPrivate.Close(); }
            await reopened.Core!.Profile.ClearBrowsingDataAsync(CoreWebView2BrowsingDataKinds.AllProfile);
            var forgotten = await Evaluate(reopened, "({cookie:document.cookie,storage:localStorage.getItem('bsl_fixture')})");
            Check(!forgotten!["cookie"]!.GetValue<string>().Contains("bsl_fixture_remember"), "Forget clears remembered cookies");
            Check(forgotten["storage"] is null, "Forget clears remembered site storage");
        }
        finally { reopened.Close(); }
        await CheckForgetRaceAsync(Path.Combine(evidence, "forget-race"));
        Console.WriteLine("Embedded WebView integration checks passed using only intercepted offline fixtures.");
    }

    private static async Task CheckForgetRaceAsync(string evidence)
    {
        var preferences = new GarmothConnectionPreferences(evidence);
        var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: preferences.UserDataFolder,
            options: new CoreWebView2EnvironmentOptions { ReleaseChannels = CoreWebView2ReleaseChannels.Stable });
        var seeded = await OpenFixture(environment, remember: true);
        try
        {
            await seeded.Core!.ExecuteScriptAsync("document.cookie='bsl_forget_fixture=yes;max-age=3600;path=/;secure';localStorage.setItem('bsl_forget','retained')");
            var refused = false;
            try { await seeded.InitializeBrowserAsync(environment, EmbeddedGarmothBrowser.ControllerOptions(environment, remember: false)); }
            catch (InvalidOperationException) { refused = true; }
            Check(refused, "a persistent controller cannot be reused as private");
            Check(!seeded.Core!.Profile.IsInPrivateModeEnabled, "mismatched reinitialization cannot change profile identity");
        }
        finally { seeded.Close(); }
        preferences.SetRememberConnection(true);
        var heldEnvironment = new TaskCompletionSource<CoreWebView2Environment>();
        var environmentCalls = 0;
        var service = new EmbeddedGarmothBrowser(preferences, () => { environmentCalls++; return heldEnvironment.Task; });
        try
        {
            var forgetting = service.ForgetAsync();
            await Task.Delay(50);
            var maintenance = Application.Current.Windows.OfType<GarmothBrowserWindow>().Single();
            Check(!((Button)maintenance.FindName("OpenButton")).IsEnabled, "Open is disabled while Forget initialization is held");
            Check(!((CheckBox)maintenance.FindName("RememberBox")).IsEnabled, "remember choice is disabled during Forget");
            ((CheckBox)maintenance.FindName("RememberBox")).IsChecked = true;
            ((Button)maintenance.FindName("OpenButton")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            var openRefused = false;
            try { await service.OpenAsync(); }
            catch (InvalidOperationException) { openRefused = true; }
            Check(openRefused, "service refuses connection opening during maintenance");
            var secondForget = service.ForgetAsync();
            var status = await service.SendAsync(new JsonObject { ["type"] = "status", ["protocolVersion"] = 1 }, TimeSpan.FromSeconds(1));
            Check(status["ok"]?.GetValue<bool>() == false, "maintenance never claims a ready connection");
            Check(environmentCalls == 1 && !preferences.RememberConnection, "repeated Open/Forget cannot race the maintenance controller or opt in");
            heldEnvironment.SetResult(environment);
            await Task.WhenAll(forgetting, secondForget).WaitAsync(TimeSpan.FromSeconds(20));
            var intro = Application.Current.Windows.OfType<GarmothBrowserWindow>().Single();
            Check(intro.Core is null && ((CheckBox)intro.FindName("RememberBox")).IsChecked == false,
                "successful Forget returns to an unchecked private introduction");
            Check(((Button)intro.FindName("OpenButton")).IsEnabled, "connection remains usable after Forget");
        }
        finally { await service.CloseAsync(); }
        var verification = await OpenFixture(environment, remember: true);
        try
        {
            var state = await Evaluate(verification, "({cookie:document.cookie,storage:localStorage.getItem('bsl_forget')})");
            Check(!state!["cookie"]!.GetValue<string>().Contains("bsl_forget_fixture") && state["storage"] is null,
                "raced Forget still clears the actual persistent Garmoth profile");
        }
        finally { verification.Close(); }

        var closingEnvironment = new TaskCompletionSource<CoreWebView2Environment>();
        var closingService = new EmbeddedGarmothBrowser(preferences, () => closingEnvironment.Task);
        var closingForget = closingService.ForgetAsync();
        await Task.Delay(50);
        await closingService.CloseAsync();
        closingEnvironment.SetResult(environment);
        try { await closingForget.WaitAsync(TimeSpan.FromSeconds(20)); }
        catch (OperationCanceledException) { }
        Check(!Application.Current.Windows.OfType<GarmothBrowserWindow>().Any(), "closing held maintenance cannot reopen a late connection window");
        await closingService.CloseAsync();
    }

    internal static async Task RunRestartPhaseAsync(string evidence, bool write)
    {
        var environment = await CoreWebView2Environment.CreateAsync(
            userDataFolder: Path.Combine(evidence, "restart-only-profile"),
            options: new CoreWebView2EnvironmentOptions { ReleaseChannels = CoreWebView2ReleaseChannels.Stable });
        var exited = new TaskCompletionSource();
        environment.BrowserProcessExited += (_, _) => exited.TrySetResult();
        var window = await OpenFixture(environment, remember: true);
        try
        {
            if (write)
            {
                await window.Core!.ExecuteScriptAsync("document.cookie='bsl_restart_fixture=yes;max-age=3600;path=/;secure';localStorage.setItem('bsl_restart','retained')");
                Console.WriteLine("PASS test-only persistent state written before process shutdown");
            }
            else
            {
                var restored = await Evaluate(window, "({cookie:document.cookie,storage:localStorage.getItem('bsl_restart')})");
                Check(restored!["cookie"]!.GetValue<string>().Contains("bsl_restart_fixture=yes"), "remembered cookie survives actual process restart");
                Check(restored["storage"]?.GetValue<string>() == "retained", "remembered storage survives actual process restart");
                await window.Core!.Profile.ClearBrowsingDataAsync(CoreWebView2BrowsingDataKinds.AllProfile);
            }
        }
        finally { window.Close(); }
        await exited.Task.WaitAsync(TimeSpan.FromSeconds(15));
        Console.WriteLine("PASS browser process exited cleanly");
    }

    internal static async Task RunPublicSmokeAsync(string evidence)
    {
        Directory.CreateDirectory(evidence);
        var service = new EmbeddedGarmothBrowser(new GarmothConnectionPreferences(Path.Combine(evidence, "anonymous-only")));
        try
        {
            await service.OpenAsync();
            var window = Application.Current.Windows.OfType<GarmothBrowserWindow>().Single();
            ((Button)window.FindName("OpenButton")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            for (var i = 0; i < 160; i++)
            {
                await Task.Delay(250);
                if (window.Core is not null && GarmothNavigationPolicy.IsAllowedNavigation(window.Core.Source))
                {
                    var ready = await window.Core.ExecuteScriptAsync("document.readyState");
                    if (ready == "\"complete\"") break;
                }
            }
            Check(window.Core is not null && GarmothNavigationPolicy.IsAllowedNavigation(window.Core.Source), "public Garmoth navigation opened through production connection");
            await Task.Delay(1500);
            await using (var capture = File.Create(Path.Combine(evidence, "garmoth-public-page.png")))
                await window.Core!.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, capture);
            var status = await service.SendAsync(new JsonObject { ["type"] = "status", ["protocolVersion"] = 1 }, TimeSpan.FromSeconds(3));
            Console.WriteLine("Anonymous connection ready: " + status["ok"]);
            // This profile is newly created for this check; never inspect user browser data.
            var publicContent = await window.Core!.ExecuteScriptAsync("JSON.stringify({host:location.host,path:location.pathname,title:document.title,text:document.body.innerText.slice(0,12000)})");
            await File.WriteAllTextAsync(Path.Combine(evidence, "public-page-state.json"), publicContent);
            Check(window.Core.Profile.IsInPrivateModeEnabled, "public smoke uses private mode");
            Console.WriteLine("Public page captured; no login or session submission attempted.");
        }
        finally { await service.CloseAsync(); }
    }

    private static async Task<GarmothBrowserWindow> OpenFixture(CoreWebView2Environment environment, bool remember)
    {
        var window = new GarmothBrowserWindow(remember) { Title = "BS Life · Offline browser verification" };
        window.Show();
        try
        {
            await window.InitializeBrowserAsync(environment, EmbeddedGarmothBrowser.ControllerOptions(environment, remember));
            var core = window.Core!;
            core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
            core.WebResourceRequested += (_, args) =>
                args.Response = environment.CreateWebResourceResponse(new MemoryStream(Encoding.UTF8.GetBytes(Fixture)),
                    200, "OK", "Content-Type: text/html; charset=utf-8\r\nCache-Control: no-store");
            var loaded = new TaskCompletionSource<bool>();
            core.NavigationCompleted += (_, args) => loaded.TrySetResult(args.IsSuccess);
            core.Navigate("https://garmoth.com/grind-tracker/offline-fixture");
            Check(await loaded.Task.WaitAsync(TimeSpan.FromSeconds(20)), "offline fixture loads");
            return window;
        }
        catch { window.Close(); throw; }
    }

    private static async Task<JsonObject?> Evaluate(GarmothBrowserWindow window, string script) =>
        JsonNode.Parse(await window.Core!.ExecuteScriptAsync(script).WaitAsync(TimeSpan.FromSeconds(5))) as JsonObject;

    private static void Check(bool value, string message)
    {
        if (!value) throw new InvalidOperationException(message);
        Console.WriteLine("PASS " + message);
    }
}
