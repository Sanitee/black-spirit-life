using System.IO;
using System.ComponentModel;
using System.Reflection;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using BlackSpiritLife.SessionImport.App;
using BlackSpiritLife.SessionImport.SummaryOcr;

internal static class Program
{
    private static int _passed;

    [STAThread]
    private static int Main(string[] args)
    {
        var application = new App();
        application.InitializeComponent();
        application.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(Dispatcher.CurrentDispatcher));
        try
        {
            if (args.Length == 2 && args[0] == "--session-history-receipts")
            {
                SessionHistoryReceiptChecks.Run(Run, Path.GetFullPath(args[1]));
                return 0;
            }
            if (args.Length == 1 && args[0] == "--session-history-flow")
            {
                SessionHistoryFlowChecks.Run(Run);
                return 0;
            }
            if (args.Length == 2 && args[0] == "--spot-picker")
            {
                SpotPickerChecks.Run(Run, Path.GetFullPath(args[1]));
                return 0;
            }
            if (args.Length == 2 && args[0] == "--review-reveal")
            {
                Await(ReviewRevealChecks.RunAsync(Path.GetFullPath(args[1])), 60);
                return 0;
            }
            if (args.Length == 2 && args[0] == "--generate-screenshot-cases")
            {
                SyntheticScreenshotCases.Generate(Path.GetFullPath(args[1]));
                return 0;
            }
            if (args.Length == 4 && args[0] == "--verify-screenshot-cases")
            {
                Await(SyntheticScreenshotCases.VerifyOfflineAsync(Path.GetFullPath(args[1]), Path.GetFullPath(args[2]), Path.GetFullPath(args[3])), 160);
                return 0;
            }
            if (args.Length == 5 && args[0] == "--live-screenshot-case")
            {
                Await(LiveScreenshotPreparationChecks.RunCaseAsync(args[1], Path.GetFullPath(args[2]), Path.GetFullPath(args[3]), Path.GetFullPath(args[4])), 200);
                return 0;
            }
            if (args.Length == 2 && args[0] is "--live-notes-inspect" or "--live-notes-repeat")
            {
                Await(LiveNotesChecks.InspectAsync(Path.GetFullPath(args[1]), args[0] == "--live-notes-repeat"), 240);
                return 0;
            }
            if (args.Length == 3 && args[0] == "--harvest-navigation-diagnostic")
            {
                Await(LiveSpotDropHarvestChecks.RunNavigationDiagnosticAsync(Path.GetFullPath(args[1]), Path.GetFullPath(args[2])), 75);
                return 0;
            }
            if (args.Length == 4 && args[0] == "--live-screenshot-prepare")
            {
                Await(LiveScreenshotPreparationChecks.RunAsync(Path.GetFullPath(args[1]), Path.GetFullPath(args[2]), Path.GetFullPath(args[3])), 200);
                return 0;
            }
            if (args.Length is 3 or 4 && args[0] == "--live-multispot")
            {
                Await(LiveMultiSpotChecks.RunAsync(Path.GetFullPath(args[1]), Path.GetFullPath(args[2]), args.Length == 4 ? args[3] : null), 1300);
                return 0;
            }
            if (args.Length is 3 or 4 && args[0] == "--harvest-spot-drops")
            {
                Await(LiveSpotDropHarvestChecks.RunAsync(Path.GetFullPath(args[1]), Path.GetFullPath(args[2]), args.Length == 4 ? args[3] : null), 2000);
                return 0;
            }
            if (args.Length == 2 && args[0] is "--live-background-observe" or "--live-background-prepare" or "--live-background-form-inspect")
            {
                Await(LiveBackgroundChecks.RunAsync(Path.GetFullPath(args[1]), args[0] != "--live-background-observe", args[0] == "--live-background-form-inspect"), 110);
                return 0;
            }
            if (args.Length == 2 && args[0] == "--background-preparation")
            {
                Await(BackgroundPreparationChecks.RunAsync(Path.GetFullPath(args[1])), 90);
                return 0;
            }
            SpotResolutionChecks.Run(Run);
            ForegroundScriptDialogChecks.Run(Run);
            ScreenshotNotesVerifierChecks.Run(Run);
            Run("test runner drains idle-priority cleanup without a busy loop", () =>
            {
                var completed = false;
                async Task IdleCleanup()
                {
                    await Dispatcher.Yield(DispatcherPriority.ApplicationIdle);
                    completed = true;
                }
                Await(IdleCleanup());
                Assert(completed, "idle cleanup completes within the original deadline");
            });
            Run("OCR preserves exact wider-catalog loot absent from the artwork catalog", () =>
            {
                var artwork = ItemCatalog.Load();
                var spots = SpotCatalog.Load();
                var item = spots.Items.First(item => spots.FindItems(item.Name).Count == 1 && artwork.MatchExact(item.Name) is null);
                var window = Window(new ManagedBrowserFixture());
                Func<Task<SummaryOcrResult>> read = () => Task.FromResult(new SummaryOcrResult([new(item.Name, 27)], item.Name, []));
                var task = (Task)typeof(MainWindow).GetMethod("ReadScreenshotAsync", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(window, [read])!;
                Await(task);
                Assert(window.LootRows.Single().Name == item.Name && window.LootRows.Single().ItemId == item.Id, "exact identity survives the smaller artwork catalog");
                Assert(window.LootRows.Single().Quantity == "27", "quantity retained");
            });
            Run("typed spot spelling is canonicalized after exact catalog resolution", () =>
            {
                var browser = new ManagedBrowserFixture { Ready = true };
                var window = ReviewWindow(browser);
                Control<ComboBox>(window, "SpotBox").Text = "RUSALKA’S CORAL";
                Click(window, "PrepareButton");
                Assert(browser.LastDraft?["target"]?["spotName"]?.GetValue<string>() == "Rusalka's Coral", "navigation receives the observed canonical label");
                Assert(browser.LastDraft?["target"]?["spotId"]?.GetValue<string>() == "186", "identity remains the observed spot");
            });
            Run("same-name spot methods require an explicit dropdown choice", () =>
            {
                var browser = new ManagedBrowserFixture { Ready = true };
                var window = ReviewWindow(browser);
                var picker = Control<ComboBox>(window, "SpotBox");
                var duplicate = SpotCatalog.Load().Entries.GroupBy(spot => spot.Name)
                    .First(group => group.Select(spot => spot.GarmothSpotId).Distinct().Count() > 1).ToArray();
                Assert(!picker.IsTextSearchEnabled, "native autocomplete cannot silently choose the first method");
                picker.SelectedItem = null;
                picker.Text = duplicate[0].Name;
                Click(window, "PrepareButton");
                Assert(browser.LastDraft is null && Status(window).Contains("Choose a matching spot"), "ambiguous typed name never enters a draft");
                var chosen = picker.Items.Cast<SpotDefinition>().Single(spot => spot.GarmothSpotId == duplicate[1].GarmothSpotId);
                picker.SelectedItem = chosen;
                Click(window, "PrepareButton");
                Assert(browser.LastDraft?["target"]?["spotId"]?.GetValue<string>() == chosen.GarmothSpotId,
                    "explicit method retains its exact observed destination");
            });
            Run("loot corrections invalidate automatic spots but retain manual choices", () =>
            {
                var automatic = ReviewWindow(new ManagedBrowserFixture { Ready = true });
                typeof(MainWindow).GetField("_suggestedSpotName", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(automatic, "Rusalka's Coral");
                automatic.LootRows[0].Name = "Wolf Meat";
                Assert(Control<ComboBox>(automatic, "SpotBox").Text == string.Empty, "stale auto-selection cleared");
                var manual = ReviewWindow(new ManagedBrowserFixture { Ready = true });
                manual.LootRows[0].Name = "Wolf Meat";
                Assert(Control<ComboBox>(manual, "SpotBox").Text == "Rusalka's Coral", "manual location retained for correction/review");
            });
            if (args.Length == 2 && args[0] == "--preparation-navigation")
            {
                Await(PreparationNavigationChecks.RunAsync(Path.GetFullPath(args[1])), 90);
                return 0;
            }
            if (args.Length == 2 && args[0] == "--webview")
            {
                Await(EmbeddedBrowserChecks.RunAsync(Path.GetFullPath(args[1])), 90);
                return 0;
            }
            if (args.Length == 2 && args[0] == "--connection-status")
            {
                Await(ConnectionStatusChecks.RunAsync(Path.GetFullPath(args[1])), 60);
                return 0;
            }
            if (args.Length == 2 && args[0] is "--storage-write" or "--storage-read")
            {
                Await(EmbeddedBrowserChecks.RunRestartPhaseAsync(Path.GetFullPath(args[1]), args[0] == "--storage-write"), 45);
                return 0;
            }
            if (args.Length == 2 && args[0] == "--public-smoke")
            {
                Await(EmbeddedBrowserChecks.RunPublicSmokeAsync(Path.GetFullPath(args[1])), 65);
                return 0;
            }
            Run("embedded navigation only accepts exact HTTPS destinations", () =>
            {
                Assert(GarmothNavigationPolicy.IsTrackerUrl("https://garmoth.com/grind-tracker/spot/123"), "tracker accepted");
                foreach (var url in new[] { "http://garmoth.com/grind-tracker/", "https://garmoth.com.evil.test/grind-tracker/",
                    "https://garmoth.com@evil.test/grind-tracker/", "https://garmoth.com:444/grind-tracker/", "file:///C:/index.html",
                    "https://discord.com/grind-tracker/", "https://garmoth.com/grind-tracker-other/" })
                    Assert(!GarmothNavigationPolicy.IsTrackerUrl(url), "reject " + url);
                Assert(GarmothNavigationPolicy.IsAllowedNavigation("https://discord.com/oauth2/authorize"), "normal Discord auth allowed");
                Assert(!GarmothNavigationPolicy.IsAllowedNavigation("https://discord.com.evil.test/"), "no auth lookalikes");
                Assert(!GarmothNavigationPolicy.IsAllowedNavigation("javascript:alert(1)"), "no script navigation");
            });
            Run("runtime setup accepts only official signed Microsoft downloads", () =>
            {
                Assert(GarmothRuntimeSetup.IsAllowedDownloadUri(new Uri(GarmothRuntimeSetup.BootstrapperUrl)), "official bootstrap link");
                Assert(!GarmothRuntimeSetup.IsAllowedDownloadUri(new Uri("http://go.microsoft.com/fwlink/p/?LinkId=2124703")), "HTTPS required");
                Assert(!GarmothRuntimeSetup.IsAllowedDownloadUri(new Uri("https://msedge.sf.dl.delivery.mp.microsoft.com.evil.test/filestreamingservice/files/x/MicrosoftEdgeWebview2Setup.exe")), "exact Microsoft host");
                Assert(GarmothRuntimeSetup.IsTrustedMicrosoftPublisher(0, "Microsoft Corporation"), "trusted Microsoft signature");
                Assert(!GarmothRuntimeSetup.IsTrustedMicrosoftPublisher(1, "Microsoft Corporation"), "failed trust cannot pass publisher check");
                Assert(!GarmothRuntimeSetup.IsTrustedMicrosoftPublisher(0, "Other Publisher"), "trusted non-Microsoft file refused");
                Assert(GarmothRuntimeSetup.IsEvergreenVersion("140.0.0.0"), "stable version accepted");
                Assert(!GarmothRuntimeSetup.IsEvergreenVersion("140.0.0.0 beta"), "preview override refused");
                var start = GarmothRuntimeSetup.CreateInstallStartInfo(Path.Combine(Path.GetTempPath(), "MicrosoftEdgeWebview2Setup.exe"));
                Assert(!start.UseShellExecute && start.CreateNoWindow && start.Verb != "runas", "hidden non-elevated setup");
                Assert(start.Arguments == "/silent /install", "only documented installer arguments");
            });
            Run("remembering a connection requires explicit stored opt-in", () =>
            {
                var root = Path.Combine(Path.GetTempPath(), "bsl-preference-test-" + Guid.NewGuid().ToString("N"));
                var preferences = new GarmothConnectionPreferences(root);
                Assert(!preferences.RememberConnection && !Directory.Exists(root), "private by default without profile writes");
                preferences.SetRememberConnection(true);
                Assert(new GarmothConnectionPreferences(root).RememberConnection, "explicit preference survives restart");
                preferences.SetRememberConnection(false);
                Assert(!new GarmothConnectionPreferences(root).RememberConnection, "opt-out survives restart");
                Assert(!Directory.Exists(preferences.UserDataFolder), "preference writes never create a browser profile");
                File.WriteAllText(Path.Combine(root, "connection.json"), "broken json");
                Assert(!preferences.RememberConnection, "invalid preference fails private");
                foreach (var value in new[] { "true", "null", "[]" })
                {
                    File.WriteAllText(Path.Combine(root, "connection.json"), value);
                    Assert(!preferences.RememberConnection, "non-object preference fails private");
                }
            });
            Run("BS Life artwork and window identity", () =>
            {
                var window = Window(new BrowserFixture());
                Assert(window.Title == "Session Import · Black Spirit Life", "window branding");
                Assert(window.Icon is not null, "native icon resource");
                Assert(window.Icon is BitmapSource icon && icon.PixelWidth > 0, "icon decodes");
                Assert(Control<Image>(window, "AppArtwork").Source is BitmapSource artwork && artwork.PixelWidth == 512,
                    "header uses original high-resolution artwork, not the ICO's first 16px frame");
                Assert(window.Icon is BitmapFrame frame && frame.Decoder.Frames.Count == 7, "native multi-resolution icon preserved");
                Assert(window.Foreground is SolidColorBrush text && text.Color == Color.FromRgb(240, 245, 241), "native window applies readable text colour");
                var primary = Control<Button>(window, "PrepareButton");
                Assert(primary.Foreground is SolidColorBrush ink && ink.Color == Color.FromRgb(16, 32, 22), "primary action keeps dark text on the light accent");
            });
            Run("built-in connection does not register or open Firefox on startup", () =>
            {
                var managed = new ManagedBrowserFixture();
                var firefoxCreated = 0;
                var window = new MainWindow(managed, monitorConnection: false,
                    firefoxFactory: () => { firefoxCreated++; return new BrowserFixture(); });
                Assert(firefoxCreated == 0 && managed.OpenCount == 0, "startup has no connection side effects");
                Assert(Control<TextBlock>(window, "BrowserStatusText").Text == "Garmoth login", "built-in default");
                Click(window, "FirefoxSetupButton");
                Assert(managed.OpenCount == 1 && firefoxCreated == 0, "Connect opens only the managed connection");
                Assert(!managed.Requests.Contains("prepare"), "connect never auto-imports");
            });
            Run("only the header offers login, without a duplicate connection panel", () =>
            {
                var managed = new ManagedBrowserFixture();
                var window = ReviewWindow(managed);
                Control<TextBox>(window, "DurationBox").Text = string.Empty;
                Assert((string)Control<Button>(window, "PrepareButton").Content == "Send to Garmoth", "session action stays distinct");
                Click(window, "PrepareButton");
                Assert(managed.Requests.Count == 0 && managed.OpenCount == 0, "invalid draft does not become a login action");
                Assert(Status(window).Contains("duration"), "validation remains actionable");
                Click(window, "FirefoxSetupButton");
                Assert(managed.Requests.SequenceEqual(["status"]), "only readiness checked");
                Assert(managed.OpenCount == 1, "login click opens the managed connection");
                Assert(window.FindName("ManagedHelp") is null, "redundant connection box removed");
                Assert(Control<Border>(window, "SetupPanel").Visibility == Visibility.Collapsed, "loot area remains available");
                Assert(Control<StackPanel>(window, "FirefoxHelp").Visibility == Visibility.Collapsed, "no developer setup in default flow");
                Assert(window.LootRows.Single().Quantity == "1.005", "quantity preserved");
                Assert(Control<Button>(window, "PrepareButton").IsEnabled, "no stuck progress");
            });
            Run("already-ready tracker prepares on the first explicit session click", () =>
            {
                var managed = new ManagedBrowserFixture { Ready = true };
                var window = ReviewWindow(managed);
                Click(window, "PrepareButton");
                Assert(managed.OpenCount == 0 && managed.Requests.Count(type => type == "prepare") == 1, "ready tracker prepares immediately");
                Assert((string)Control<Button>(window, "PrepareButton").Content == "Review inputs", "sent inputs become the primary review action");
                Assert(Control<Border>(window, "SetupPanel").Visibility == Visibility.Collapsed, "ready connection hides login help");
                managed.Ready = false;
                managed.State = "login_required";
                Await(InvokeTask(window, "RefreshBrowserStatusAsync"));
                Assert((string)Control<Button>(window, "PrepareButton").Content == "Review inputs", "status polling does not replace review with login or resend");
                Assert(Control<TextBlock>(window, "BrowserStatusText").Text == "Garmoth login", "explicit expired login is shown only in header");
            });
            Run("signed-in or unknown Garmoth page is not confused with login or a ready form", () =>
            {
                var managed = new ManagedBrowserFixture { State = "browser_open" };
                var window = ReviewWindow(managed);
                Await(InvokeTask(window, "RefreshBrowserStatusAsync"));
                Assert(Control<TextBlock>(window, "BrowserStatusText").Text == "Open Garmoth", "no false login on a live non-editor page");
                Click(window, "PrepareButton");
                Assert(managed.OpenCount == 1 && managed.Requests.Count(type => type == "prepare") == 1,
                    "explicit Prepare delegates guarded navigation from a signed-in non-editor page");
                Assert(Status(window).Contains("Ready in Garmoth"), "show completion only after the managed service reports entered loot");
                Assert(Control<Border>(window, "SetupPanel").Visibility == Visibility.Collapsed, "no help box covers loot");
                managed.Ready = true;
                Await(InvokeTask(window, "RefreshBrowserStatusAsync"));
                Assert(managed.Requests.Count(type => type == "prepare") == 1, "readiness change never sends another draft automatically");
                Click(window, "PrepareButton");
                Assert(managed.Requests.Count(type => type == "prepare") == 1 && managed.Requests.Count(type => type == "review") == 1,
                    "same primary button reviews without sending twice");
            });
            Run("remembered connection does not claim a new login is required", () =>
            {
                var managed = new ManagedBrowserFixture { Remembered = true };
                var window = ReviewWindow(managed);
                Await(InvokeTask(window, "RefreshBrowserStatusAsync"));
                Assert(Control<TextBlock>(window, "BrowserStatusText").Text == "Open Garmoth", "remembered connection can be reopened");
                Assert(!managed.Requests.Contains("prepare") && managed.OpenCount == 0, "monitoring has no navigation side effects");
            });
            Run("expired connection on prepare requests explicit login without taking focus", () =>
            {
                var managed = new ManagedBrowserFixture { Ready = true };
                var window = ReviewWindow(managed);
                Await(InvokeTask(window, "RefreshBrowserStatusAsync"));
                managed.Ready = false;
                managed.State = "login_required";
                Click(window, "PrepareButton");
                Assert(managed.OpenCount == 0 && !managed.Requests.Contains("prepare"), "stale readiness cannot upload or foreground a login window");
                Assert(Control<TextBlock>(window, "BrowserStatusText").Text == "Garmoth login", "expired header updated");
                Assert((string)Control<Button>(window, "PrepareButton").Content == "Send to Garmoth", "session action retained");
                Assert(Control<Button>(window, "PrepareButton").IsEnabled, "retry available");
            });
            Run("closing during a readiness check cannot prepare or reopen Garmoth", () =>
            {
                var managed = new ManagedBrowserFixture { Ready = true };
                var window = ReviewWindow(managed);
                Await(InvokeTask(window, "RefreshBrowserStatusAsync"));
                managed.PendingStatus = new TaskCompletionSource<JsonObject>();
                Click(window, "PrepareButton");
                window.Close();
                managed.PendingStatus.SetResult(BrowserFixture.ReadyStatus());
                Pump();
                Assert(!managed.Requests.Contains("prepare") && managed.OpenCount == 0, "no late browser action after closing");
            });
            Run("Firefox fallback is lazy and switching retains import data", () =>
            {
                var managed = new ManagedBrowserFixture();
                var fallback = new BrowserFixture();
                var factoryCalls = 0;
                var window = new MainWindow(managed, monitorConnection: false,
                    firefoxFactory: () => { factoryCalls++; return fallback; });
                window.LootRows.Add(Loot("Rough Stone", 1005));
                Click(window, "FirefoxSetupButton");
                Click(window, "SwitchBrowserMenuItem");
                Assert(factoryCalls == 1 && managed.CloseCount == 1, "explicit switch creates fallback and closes private browser");
                Assert(Control<TextBlock>(window, "BrowserStatusText").Text == "Connect Firefox", "fallback selected");
                Click(window, "SwitchBrowserButton");
                Assert(factoryCalls == 1 && managed.OpenCount == 1, "return does not unexpectedly open anything");
                Assert(Control<TextBlock>(window, "BrowserStatusText").Text == "Garmoth login", "built-in restored");
                Assert(window.LootRows.Single().Quantity == "1.005", "draft survived both switches");
            });
            Run("managed open failure is visible and recoverable", () =>
            {
                var managed = new ManagedBrowserFixture { SetupError = "Garmoth could not open." };
                var window = ReviewWindow(managed);
                Click(window, "FirefoxSetupButton");
                Assert(Status(window) == managed.SetupError, "actual failure shown");
                Assert(Control<Button>(window, "PrepareButton").IsEnabled, "actions restored");
                Assert(Control<Border>(window, "SetupPanel").Visibility == Visibility.Collapsed, "failure does not cover loot with duplicate setup");
                Assert(Control<MenuItem>(window, "SwitchBrowserMenuItem").IsEnabled, "optional fallback remains reachable");
                Assert(window.LootRows.Count == 1, "loot untouched");
            });
            Run("disconnected prepare opens inline help without sending a draft", () =>
            {
                var browser = new BrowserFixture { Ready = false };
                var window = ReviewWindow(browser);
                Click(window, "PrepareButton");
                Assert(browser.Requests.SequenceEqual(["status"]), "only a connection check is sent");
                Assert(Control<Border>(window, "SetupPanel").Visibility == Visibility.Visible, "setup shown inline");
                Assert(Control<Button>(window, "PrepareButton").IsEnabled, "not left busy");
                Assert(window.LootRows.Count == 1 && window.LootRows[0].Quantity == "1.005", "loot retained");
                Assert(Control<TextBox>(window, "DurationBox").Text == "00:15", "duration retained");
                Assert(Status(window).Contains("Your items stay here"), "actionable connection message");
                Assert(browser.Timeouts.Single() < TimeSpan.FromSeconds(2), "no 25-second missing-helper wait");
            });
            Run("connection ready automatically replaces setup and enables prepare", () =>
            {
                var browser = new BrowserFixture();
                var window = ReviewWindow(browser);
                Click(window, "FirefoxSetupButton");
                browser.Ready = true;
                Await(InvokeTask(window, "RefreshBrowserStatusAsync"));
                Assert(Control<Border>(window, "SetupPanel").Visibility == Visibility.Collapsed, "setup closes on detection");
                Assert(Control<TextBlock>(window, "BrowserStatusText").Text == "Firefox connected", "real connection status");
                Click(window, "PrepareButton");
                Assert(browser.Requests.Count(type => type == "prepare") == 1, "one prepare after readiness");
                Assert(browser.LastDraft?["behavior"]?["submit"]?.GetValue<bool>() == false, "never auto-submit");
                Assert(browser.LastDraft?["session"]?["items"]?[0]?["quantity"]?.GetValue<long>() == 1005, "grouped count unchanged");
                Assert((string)Control<Button>(window, "PrepareButton").Content == "Review inputs", "review is the primary action");
                Assert(window.FindName("ReviewButton") is null, "no separate text-only review action");
            });
            Run("missing packaged helper does not attempt browser communication", () =>
            {
                var browser = new BrowserFixture { Registered = false };
                var window = ReviewWindow(browser);
                Click(window, "PrepareButton");
                Assert(browser.Requests.Count == 0, "missing helper short-circuits");
                Assert(!Control<Button>(window, "SetupOpenButton").IsEnabled, "missing add-on cannot launch");
                Assert(Status(window) == browser.Registration.Message, "actual missing-helper reason shown");
            });
            Run("setup actions are explicit, recoverable and do not lose draft", () =>
            {
                var browser = new BrowserFixture();
                var window = ReviewWindow(browser);
                Click(window, "FirefoxSetupButton");
                Assert(browser.OpenCount == 0 && browser.CopyCount == 0, "no surprise browser/clipboard action");
                Click(window, "SetupOpenButton");
                Click(window, "SetupCopyButton");
                Assert(browser.OpenCount == 1 && browser.CopyCount == 1, "explicit actions wired");
                browser.SetupError = "Firefox was not found.";
                Click(window, "SetupOpenButton");
                Assert(Status(window) == "Firefox was not found.", "launch errors stay visible");
                Assert(window.LootRows.Count == 1, "failed setup preserves loot");
            });
            Run("wrong protocol or malformed status is not treated as connected", () =>
            {
                foreach (var response in new[]
                {
                    new JsonObject { ["type"] = "statusResult", ["ok"] = true, ["protocolVersion"] = 999 },
                    new JsonObject { ["type"] = "statusResult", ["ok"] = "true", ["protocolVersion"] = 1 },
                    new JsonObject { ["type"] = "prepareResult", ["ok"] = true, ["protocolVersion"] = 1 },
                })
                {
                    var browser = new BrowserFixture { StatusOverride = response };
                    var window = ReviewWindow(browser);
                    Click(window, "PrepareButton");
                    Assert(!browser.Requests.Contains("prepare"), "invalid status does not send a draft");
                    Assert(Control<TextBlock>(window, "BrowserStatusText").Text == "Connect Firefox", "not falsely green");
                    var managed = new ManagedBrowserFixture { StatusOverride = response };
                    var managedWindow = ReviewWindow(managed);
                    Await(InvokeTask(managedWindow, "RefreshBrowserStatusAsync"));
                    Assert(Control<TextBlock>(managedWindow, "BrowserStatusText").Text == "Open Garmoth",
                        "invalid response is unknown, not evidence of a missing login");
                    Assert(!managed.Requests.Contains("prepare"), "invalid managed status never sends the draft");
                }
            });
            Run("concurrent readiness checks share one request", () =>
            {
                var browser = new BrowserFixture { PendingStatus = new TaskCompletionSource<JsonObject>() };
                var window = Window(browser);
                var first = InvokeTask(window, "RefreshBrowserStatusAsync");
                var second = InvokeTask(window, "RefreshBrowserStatusAsync");
                Assert(browser.Requests.Count == 1, "only one pipe status request");
                browser.PendingStatus.SetResult(BrowserFixture.ReadyStatus());
                Await(Task.WhenAll(first, second));
                Assert(Control<TextBlock>(window, "BrowserStatusText").Text == "Firefox connected", "pending status completed");
            });
            Run("edit after prepare invalidates explicit review", () =>
            {
                var browser = new BrowserFixture { Ready = true };
                var window = ReviewWindow(browser);
                Click(window, "PrepareButton");
                window.LootRows[0].Quantity = "1.006";
                Assert((string)Control<Button>(window, "PrepareButton").Content == "Send to Garmoth", "edits require a fresh send");
            });
            Run("pending Connect cannot overwrite Prepare progress", () =>
            {
                var browser = new BrowserFixture
                {
                    PendingStatus = new TaskCompletionSource<JsonObject>(),
                    PendingPrepare = new TaskCompletionSource<JsonObject>(),
                };
                var window = ReviewWindow(browser);
                var messages = new List<string>();
                var status = Control<TextBlock>(window, "StatusText");
                DependencyPropertyDescriptor.FromProperty(TextBlock.TextProperty, typeof(TextBlock))
                    .AddValueChanged(status, (_, _) => messages.Add(status.Text));
                Click(window, "FirefoxSetupButton");
                Click(window, "PrepareButton");
                browser.PendingStatus.SetResult(BrowserFixture.ReadyStatus());
                Pump();
                Assert(Status(window) == "Sending to Garmoth…", "send owns progress while pending");
                Assert(!messages.Contains("Firefox connected. You can prepare this session in Garmoth."), "Connect cannot report idle readiness during prepare");
                Assert(!Control<Button>(window, "PrepareButton").IsEnabled, "one pending prepare");
                browser.PendingPrepare.SetResult(new JsonObject
                {
                    ["type"] = "prepareResult", ["ok"] = true,
                    ["draftId"] = browser.LastDraft!["draftId"]!.GetValue<string>(), ["matched"] = 1,
                });
                Pump();
                Assert(Control<Button>(window, "PrepareButton").IsEnabled, "completed prepare restores actions");
            });
            Run("review is explicit and carries the prepared draft identity", () =>
            {
                var browser = new BrowserFixture { Ready = true };
                var window = ReviewWindow(browser);
                Click(window, "PrepareButton");
                Assert(!browser.Requests.Contains("review"), "prepare does not focus or save Garmoth");
                Click(window, "PrepareButton");
                Assert(browser.Requests.Count(type => type == "review") == 1, "one explicit review");
                Assert(browser.LastDraft!["behavior"]!["submit"]!.GetValue<bool>() == false, "no automatic submission");
                Assert(Control<Button>(window, "PrepareButton").IsEnabled, "review restores controls");
            });
            Run("prepare failure returns to editable review", () =>
            {
                var browser = new BrowserFixture { Ready = true, PrepareError = true };
                var window = ReviewWindow(browser);
                Click(window, "PrepareButton");
                Assert(Control<Button>(window, "PrepareButton").IsEnabled, "failure clears busy state");
                Assert(Control<Grid>(window, "ReviewPanel").IsEnabled, "loot remains editable");
                Assert((string)Control<Button>(window, "PrepareButton").Content == "Send to Garmoth", "no false prepared result");
            });
            Run("active importer sends once then opens the same prepared inputs", () =>
            {
                var browser = new ManagedBrowserFixture { Ready = true };
                var window = ReviewWindow(browser, autoReviewAllowed: () => true);
                Click(window, "PrepareButton");
                Assert(browser.Requests.SequenceEqual(["status", "prepare", "review"]), "one send followed by one guarded reveal");
                Assert(browser.LastReview!["draftId"]!.GetValue<string>() == browser.LastDraft!["draftId"]!.GetValue<string>(), "same prepared draft");
                Assert(browser.LastReview["revealIfOwnerActive"]!.GetValue<bool>(), "host rechecks activity before auto reveal");
                Assert((string)Control<Button>(window, "PrepareButton").Content == "Review inputs", "primary changes rather than adding a link");
                Click(window, "PrepareButton");
                Assert(browser.Requests.Count(type => type == "prepare") == 1, "review does not resend");
                Assert(!browser.LastReview["revealIfOwnerActive"]!.GetValue<bool>(), "explicit review can open after returning from game");
            });
            Run("switching away while sending defers review without losing the result", () =>
            {
                var active = true;
                var browser = new ManagedBrowserFixture { Ready = true, PendingPrepare = new TaskCompletionSource<JsonObject>() };
                var window = ReviewWindow(browser, autoReviewAllowed: () => active);
                Click(window, "PrepareButton");
                active = false;
                browser.PendingPrepare.SetResult(new JsonObject { ["type"] = "prepareResult", ["ok"] = true,
                    ["draftId"] = browser.LastDraft!["draftId"]!.GetValue<string>(), ["matched"] = 1 });
                Pump();
                Assert(!browser.Requests.Contains("review"), "no focus stealing after switching away");
                Assert((string)Control<Button>(window, "PrepareButton").Content == "Review inputs", "ready to open on return");
                Assert(Status(window).StartsWith("Ready in Garmoth"), "result retained");
            });
            Run("late activity change deferred by browser keeps primary review available", () =>
            {
                var browser = new ManagedBrowserFixture { Ready = true, ReviewDeferred = true };
                var window = ReviewWindow(browser, autoReviewAllowed: () => true);
                Click(window, "PrepareButton");
                Assert((string)Control<Button>(window, "PrepareButton").Content == "Review inputs" && Status(window).StartsWith("Ready in Garmoth"), "deferred is not a failure or a new send");
                Assert(Control<Button>(window, "PrepareButton").IsEnabled, "button restored");
            });
            Run("auto review preserves incomplete and metadata warnings", () =>
            {
                var browser = new ManagedBrowserFixture { Ready = true, PendingPrepare = new TaskCompletionSource<JsonObject>() };
                var window = ReviewWindow(browser, autoReviewAllowed: () => true);
                window.LootRows.Add(Loot("Lobster", 38));
                Click(window, "PrepareButton");
                browser.PendingPrepare.SetResult(new JsonObject { ["type"] = "prepareResult", ["ok"] = true,
                    ["draftId"] = browser.LastDraft!["draftId"]!.GetValue<string>(), ["matched"] = 1,
                    ["warnings"] = new JsonArray("agris_toggle_not_found"),
                    ["skipped"] = new JsonArray(new JsonObject { ["index"] = 1, ["reason"] = "item_not_found" }) });
                Pump();
                Assert(browser.Requests.Count(type => type == "review") == 1, "open the partial editor for correction");
                Assert(Status(window).StartsWith("Incomplete") && Status(window).Contains("Lobster") && Status(window).Contains("Check Agris"), "opening never erases warnings");
            });
            Run("review opening failure retries review but missing form resets to send", () =>
            {
                var browser = new ManagedBrowserFixture { Ready = true, ReviewError = true };
                var window = ReviewWindow(browser, autoReviewAllowed: () => true);
                Click(window, "PrepareButton");
                Assert((string)Control<Button>(window, "PrepareButton").Content == "Review inputs", "opening failure retains prepared result");
                Assert(Status(window).Contains("Garmoth could not open") && window.LootRows.Count == 1, "recoverable failure retains loot");
                browser.PreparedFormMissing = true;
                Click(window, "PrepareButton");
                Assert((string)Control<Button>(window, "PrepareButton").Content == "Send to Garmoth", "stale editor cannot trap the user in review");
                browser.ReviewError = false;
                browser.PreparedFormMissing = false;
                Click(window, "PrepareButton");
                Assert(browser.Requests.Count(type => type == "prepare") == 2, "fresh send after stale editor");
            });
            Run("double click cannot send or open two simultaneous sessions", () =>
            {
                var browser = new ManagedBrowserFixture { Ready = true, PendingReview = new TaskCompletionSource<JsonObject>() };
                var window = ReviewWindow(browser, autoReviewAllowed: () => true);
                Click(window, "PrepareButton");
                Click(window, "PrepareButton");
                Assert(browser.Requests.Count(type => type == "prepare") == 1 && browser.Requests.Count(type => type == "review") == 1, "single action while busy");
                browser.PendingReview.SetResult(new JsonObject { ["type"] = "reviewResult", ["ok"] = true,
                    ["draftId"] = browser.LastDraft!["draftId"]!.GetValue<string>(), ["revealed"] = true });
                Pump();
                Assert(Control<Button>(window, "PrepareButton").IsEnabled, "review completes");
            });
            Run("unrelated or malformed review reply cannot discard the prepared draft", () =>
            {
                foreach (var invalid in new[] { "wrong-draft", "wrong-type", "wrong-version" })
                {
                    var browser = new ManagedBrowserFixture { Ready = true };
                    var window = ReviewWindow(browser);
                    Click(window, "PrepareButton");
                    browser.ReviewOverride = new JsonObject {
                        ["type"] = invalid == "wrong-type" ? "prepareResult" : "reviewResult",
                        ["draftId"] = invalid == "wrong-draft" ? "another-draft" : browser.LastDraft!["draftId"]!.GetValue<string>(),
                        ["protocolVersion"] = invalid == "wrong-version" ? 999 : 1,
                        ["ok"] = false, ["preparedFormMissing"] = true };
                    Click(window, "PrepareButton");
                    Assert((string)Control<Button>(window, "PrepareButton").Content == "Review inputs", "only this draft's valid reply can invalidate review: " + invalid);
                }
            });
            Run("preparation warnings name the field instead of exposing protocol codes", () =>
            {
                var browser = new BrowserFixture { Ready = true, PendingPrepare = new TaskCompletionSource<JsonObject>() };
                var window = ReviewWindow(browser);
                Click(window, "PrepareButton");
                browser.PendingPrepare.SetResult(new JsonObject
                {
                    ["type"] = "prepareResult", ["ok"] = true,
                    ["draftId"] = browser.LastDraft!["draftId"]!.GetValue<string>(), ["matched"] = 1,
                    ["warnings"] = new JsonArray("agris_toggle_not_found", "additional_drop_rate_field_not_accepted"),
                });
                Pump();
                Assert(Status(window).Contains("Check Agris in Garmoth.") && Status(window).Contains("Check additional drop rate in Garmoth."), "actionable field names");
                Assert(!Status(window).Contains("_not_"), "no internal warning codes in the UI");
                Assert(Status(window).StartsWith("Check session details") && !Status(window).Contains("Ready in Garmoth"), "unconfirmed metadata never claims fully ready");
                Assert((string)Control<Button>(window, "PrepareButton").Content == "Review inputs", "review remains available for fixing unconfirmed fields");
                Assert(window.LootRows.Single().Quantity == "1.005" && !browser.Requests.Contains("review"), "warning neither loses loot nor opens the browser");
            });
            Run("partial preparation is explicitly incomplete and retains all loot", () =>
            {
                var browser = new BrowserFixture { Ready = true, PendingPrepare = new TaskCompletionSource<JsonObject>() };
                var window = ReviewWindow(browser);
                window.LootRows.Add(Loot("Lobster", 38));
                Click(window, "PrepareButton");
                browser.PendingPrepare.SetResult(new JsonObject
                {
                    ["type"] = "prepareResult", ["ok"] = true,
                    ["draftId"] = browser.LastDraft!["draftId"]!.GetValue<string>(), ["matched"] = 1,
                    ["skipped"] = new JsonArray(new JsonObject { ["index"] = 1, ["itemId"] = "6511", ["reason"] = "item_not_found" }),
                });
                Pump();
                Assert(Status(window).StartsWith("Incomplete") && Status(window).Contains("1 not entered"), "partial is not ready or complete");
                Assert(Status(window).Contains("Lobster"), "missing entry is identifiable without a tooltip");
                Assert(!Status(window).Contains("not supported"), "a missing match is not proof the site cannot support an item");
                Assert(window.LootRows.Count == 2 && window.LootRows[1].Quantity == "38", "unmatched loot remains intact");
                Assert(!browser.Requests.Contains("review"), "partial prepare never opens or saves Garmoth automatically");
            });
            Run("verified Notes account for missing loot without inflating structured counts", () =>
            {
                var browser = new BrowserFixture { Ready = true, PendingPrepare = new TaskCompletionSource<JsonObject>() };
                var window = ReviewWindow(browser);
                window.LootRows.Add(Loot("Lobster", 38));
                Click(window, "PrepareButton");
                var note = (JsonObject)browser.LastDraft!["session"]!["items"]![1]!.DeepClone();
                note["index"] = 1;
                browser.PendingPrepare.SetResult(new JsonObject
                {
                    ["type"] = "prepareResult", ["ok"] = true,
                    ["draftId"] = browser.LastDraft!["draftId"]!.GetValue<string>(), ["matched"] = 1,
                    ["skipped"] = new JsonArray(new JsonObject { ["index"] = 1, ["reason"] = "item_not_found" }),
                    ["notesStatus"] = "verified", ["notesVerified"] = new JsonArray(note)
                });
                Pump();
                Assert(Status(window) == "Ready in Garmoth · 1 items · 1 in Notes (not included in totals)", "notes are visibly excluded, not reported as two numeric loot entries");
                Assert(window.LootRows.Count == 2 && window.LootRows[1].Quantity == "38", "notes never remove the local item");
                Assert(!browser.Requests.Contains("review"), "no implicit foreground review or save");
            });
            Run("incorrect or duplicated Notes receipts cannot conceal missing loot", () =>
            {
                var items = new JsonArray(new JsonObject { ["itemId"] = "6511", ["subKey"] = 0, ["name"] = "Lobster", ["quantity"] = 38L });
                var note = (JsonObject)items[0]!.DeepClone(); note["index"] = 0;
                var response = new JsonObject
                {
                    ["notesStatus"] = "verified", ["notesVerified"] = new JsonArray(note),
                    ["skipped"] = new JsonArray(new JsonObject { ["index"] = 0, ["reason"] = "item_not_found" })
                };
                Assert(PreparedNotes.VerifiedIndices(response, items).SetEquals([0]), "exact receipt recognized");
                foreach (var (field, value) in new (string, JsonNode?)[] { ("quantity",JsonValue.Create(39L)),("name",JsonValue.Create("Blue Coral")),("itemId",JsonValue.Create("4477")),("subKey",JsonValue.Create(1)),("index",JsonValue.Create(4)) })
                {
                    var invalid = (JsonObject)response.DeepClone(); invalid["notesVerified"]![0]![field] = value;
                    Assert(PreparedNotes.VerifiedIndices(invalid, items).Count == 0, "mismatched receipt rejected: " + field);
                }
                ((JsonArray)response["notesVerified"]!).Add(note.DeepClone());
                Assert(PreparedNotes.VerifiedIndices(response, items).Count == 0, "duplicate receipt rejected");
            });
            Run("zero entered items never shows a successful preparation", () =>
            {
                var browser = new BrowserFixture { Ready = true, PendingPrepare = new TaskCompletionSource<JsonObject>() };
                var window = ReviewWindow(browser);
                Click(window, "PrepareButton");
                browser.PendingPrepare.SetResult(new JsonObject
                {
                    ["type"] = "prepareResult", ["ok"] = true,
                    ["draftId"] = browser.LastDraft!["draftId"]!.GetValue<string>(), ["matched"] = 0,
                });
                Pump();
                Assert(Status(window).Contains("No loot was entered"), "zero-match response is not success");
                Assert((string)Control<Button>(window, "PrepareButton").Content == "Send to Garmoth", "no false review action");
                Assert(window.LootRows.Single().Quantity == "1.005", "loot is retained");
            });
            SessionTimingChecks.Run(Run, args.Length == 1 ? Path.GetFullPath(args[0]) : null);
            if (args.Length > 0)
            {
                var directory = Path.GetFullPath(args[0]);
                Directory.CreateDirectory(directory);
                var browser = new ManagedBrowserFixture();
                var window = ReviewWindow(browser);
                foreach (var (name, count) in new[]
                {
                    ("Black Gem Fragment", 52L), ("Sharp Black Crystal Shard", 8L),
                    ("Lobster", 38L), ("Fairy's Breath", 162L), ("Caphras Stone", 3L),
                    ("Coral Piece", 413L), ("Fairy Powder", 132L),
                    ("Dim Heartvein Shard", 26L), ("Rusalka's Coral", 59L),
                    ("Cracked Terrashard", 2L), ("Ancient Spirit Dust", 37L),
                    ("Fruit of Nature", 4L), ("Blue Coral", 5L),
                    ("Rough Translucent Crystal", 5L), ("Rough Blue Crystal", 6L),
                }) window.LootRows.Add(Loot(name, count));
                Click(window, "FirefoxSetupButton");
                Render(window, 904, 650, Path.Combine(directory, "session-import-connect-920.png"));
                Render(window, 1184, 820, Path.Combine(directory, "session-import-connect-1200.png"));
                browser.Ready = true;
                Await(InvokeTask(window, "RefreshBrowserStatusAsync"));
                Render(window, 904, 650, Path.Combine(directory, "session-import-connected-920.png"));
                var connection = new GarmothBrowserWindow(remembered: false);
                RenderWindow(connection, 1084, 740, Path.Combine(directory, "garmoth-connect-1100.png"));
                RenderWindow(connection, 784, 530, Path.Combine(directory, "garmoth-connect-800.png"));
            }
            Console.WriteLine($"{_passed} Session Import checks passed. No browser, profile, clipboard or registration actions were performed.");
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(error);
            return 1;
        }
    }

    private static MainWindow Window(ISessionImportBrowser browser) => new(browser, monitorConnection: false);
    private static MainWindow ReviewWindow(ISessionImportBrowser browser, Func<bool>? autoReviewAllowed = null)
    {
        var window = new MainWindow(browser, monitorConnection: false, autoReviewAllowed: autoReviewAllowed);
        window.LootRows.Add(Loot("Rough Stone", 1005));
        Control<ComboBox>(window, "SpotBox").Text = "Rusalka's Coral";
        Control<TextBox>(window, "DurationBox").Text = "00:15";
        typeof(MainWindow).GetMethod("ShowReview", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(window, null);
        return window;
    }
    private static T Control<T>(MainWindow window, string name) where T : FrameworkElement => (T)window.FindName(name);
    private static LootRowViewModel Loot(string name, long count)
    {
        var match = ItemCatalog.Load().Match(name);
        Assert(match?.IconPath is not null, "fixture uses original bundled artwork for " + name);
        return new LootRowViewModel(match!.Name, count, match.ItemId, match.IconPath);
    }
    private static string Status(MainWindow window) => Control<TextBlock>(window, "StatusText").Text;
    private static void Click(MainWindow window, string name)
    {
        var element = (UIElement)window.FindName(name);
        element.RaiseEvent(new RoutedEventArgs(element is MenuItem ? MenuItem.ClickEvent : Button.ClickEvent));
        Pump();
    }
    private static Task InvokeTask(MainWindow window, string method) =>
        (Task)typeof(MainWindow).GetMethod(method, BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(window, null)!;
    private static void Await(Task task, int seconds = 5)
    {
        if (!task.IsCompleted)
        {
            // Keep one dispatcher frame alive so ApplicationIdle continuations
            // can run too. Repeated Background-only frames starved cleanup and
            // spun a CPU core while real browser work had already finished.
            var dispatcher = Dispatcher.CurrentDispatcher;
            var frame = new DispatcherFrame();
            var timeout = new DispatcherTimer(DispatcherPriority.Send, dispatcher)
            {
                Interval = TimeSpan.FromSeconds(seconds),
            };
            EventHandler stop = (_, _) => frame.Continue = false;
            timeout.Tick += stop;
            _ = task.ContinueWith(_ =>
            {
                if (!dispatcher.HasShutdownStarted)
                    dispatcher.BeginInvoke(DispatcherPriority.Send, new Action(() => frame.Continue = false));
            }, TaskScheduler.Default);
            timeout.Start();
            try { Dispatcher.PushFrame(frame); }
            finally
            {
                timeout.Stop();
                timeout.Tick -= stop;
            }
        }
        Assert(task.IsCompleted, "asynchronous operation finished");
        task.GetAwaiter().GetResult();
    }
    private static void Pump()
    {
        var frame = new DispatcherFrame();
        Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() => frame.Continue = false));
        Dispatcher.PushFrame(frame);
    }
    private static void Render(MainWindow window, int width, int height, string path)
        => RenderWindow(window, width, height, path);
    private static void RenderWindow(Window window, int width, int height, string path)
    {
        var root = (FrameworkElement)window.Content;
        root.Measure(new Size(width, height));
        root.Arrange(new Rect(0, 0, width, height));
        root.UpdateLayout();
        Pump();
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        var canvas = new DrawingVisual();
        using (var drawing = canvas.RenderOpen())
            drawing.DrawRectangle(window.Background, null, new Rect(0, 0, width, height));
        bitmap.Render(canvas);
        bitmap.Render(root);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path);
        encoder.Save(stream);
    }
    private static void Run(string name, Action action)
    {
        action();
        _passed++;
        Console.WriteLine("PASS " + name);
    }
    private static void Assert(bool value, string message)
    {
        if (!value) throw new InvalidOperationException(message);
    }
}

internal class BrowserFixture : ISessionImportBrowser
{
    internal bool Registered = true;
    internal bool Ready;
    internal bool PrepareError;
    internal string? SetupError;
    internal JsonObject? StatusOverride;
    internal TaskCompletionSource<JsonObject>? PendingStatus;
    internal TaskCompletionSource<JsonObject>? PendingPrepare;
    internal TaskCompletionSource<JsonObject>? PendingReview;
    internal bool ReviewError;
    internal bool PreparedFormMissing;
    internal bool ReviewDeferred;
    internal readonly List<string> Requests = [];
    internal readonly List<TimeSpan> Timeouts = [];
    internal int OpenCount;
    internal int CopyCount;
    internal JsonObject? LastDraft;
    internal JsonObject? LastReview;
    internal JsonObject? ReviewOverride;
    public RegistrationResult Registration => new(Registered, "isolated-test-addon/manifest.json", "The Firefox add-on is missing from this build.");
    public Task<JsonObject> SendAsync(JsonObject request, TimeSpan timeout)
    {
        var type = request["type"]!.GetValue<string>();
        Requests.Add(type);
        Timeouts.Add(timeout);
        if (type == "status")
        {
            if (PendingStatus is not null) return PendingStatus.Task;
            if (StatusOverride is not null) return Task.FromResult(StatusOverride);
            if (this is ManagedBrowserFixture managed)
                return Task.FromResult(new JsonObject
                {
                    ["type"] = "statusResult", ["protocolVersion"] = 1, ["ok"] = Ready, ["canPrepare"] = Ready,
                    ["connected"] = Ready || managed.State != "not_open", ["state"] = Ready ? "tracker_ready" : managed.State,
                    ["remembered"] = managed.Remembered,
                });
            if (!Ready) return Task.FromException<JsonObject>(new TimeoutException("not connected"));
            return Task.FromResult(ReadyStatus());
        }
        if (type == "prepare")
        {
            LastDraft = (JsonObject)request["draft"]!;
            if (PendingPrepare is not null) return PendingPrepare.Task;
            return Task.FromResult(new JsonObject
            {
                ["type"] = "prepareResult", ["ok"] = !PrepareError,
                ["draftId"] = LastDraft["draftId"]!.GetValue<string>(),
                ["matched"] = 1, ["message"] = PrepareError ? "Garmoth did not become ready." : "ready",
            });
        }
        LastReview = (JsonObject)request.DeepClone();
        if (ReviewOverride is not null) return Task.FromResult(ReviewOverride);
        if (PendingReview is not null) return PendingReview.Task;
        return Task.FromResult(new JsonObject
        {
            ["type"] = "reviewResult", ["ok"] = !ReviewError,
            ["draftId"] = request["draftId"]!.GetValue<string>(),
            ["preparedFormMissing"] = PreparedFormMissing,
            ["revealed"] = !ReviewDeferred,
            ["message"] = PreparedFormMissing ? "The prepared form is no longer open. Send this session again." : "Garmoth could not open.",
        });
    }
    internal static JsonObject ReadyStatus() => new() { ["type"] = "statusResult", ["protocolVersion"] = 1, ["ok"] = true };
    public void OpenSetup()
    {
        OpenCount++;
        if (SetupError is not null) throw new IOException(SetupError);
    }
    public void CopyExtensionPath() => CopyCount++;
}

internal sealed class ManagedBrowserFixture : BrowserFixture, IAppManagedSessionImportBrowser
{
    internal int CloseCount;
    internal int BackgroundOpenCount;
    internal string State = "not_open";
    internal bool Remembered;
    public Task OpenForPreparationAsync(Window? owner = null)
    {
        BackgroundOpenCount++;
        OpenCount++;
        if (State == "not_open") State = "browser_open";
        return SetupError is null ? Task.CompletedTask : Task.FromException(new IOException(SetupError));
    }
    public Task OpenAsync(Window? owner = null)
    {
        OpenCount++;
        if (State == "not_open") State = "browser_open";
        return SetupError is null ? Task.CompletedTask : Task.FromException(new IOException(SetupError));
    }
    public Task CloseAsync()
    {
        CloseCount++;
        return Task.CompletedTask;
    }
}
