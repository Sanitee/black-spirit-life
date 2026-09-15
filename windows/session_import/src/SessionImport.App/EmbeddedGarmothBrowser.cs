using System.Text;
using System.Text.Json.Nodes;
using System.IO;
using System.Windows;
using Microsoft.Web.WebView2.Core;

namespace BlackSpiritLife.SessionImport.App;

internal sealed class EmbeddedGarmothBrowser : IAppManagedSessionImportBrowser
{
    private readonly GarmothConnectionPreferences _preferences;
    private readonly Func<Task<CoreWebView2Environment>>? _environmentFactory;
    private readonly HashSet<GarmothBrowserWindow> _children = [];
    private readonly SemaphoreSlim _operation = new(1, 1);
    private GarmothBrowserWindow? _window;
    private CoreWebView2Environment? _environment;
    private CancellationTokenSource _lifetime = new();
    private CancellationTokenSource? _activeOperation;
    private CancellationTokenSource? _pendingPreparation;
    private Task? _opening;
    private Task? _initialNavigation;
    private Task? _forgetting;
    private CancellationTokenSource? _forgetCancellation;
    private bool _rememberedSession;
    private string? _preparedDraftId;
    private string? _expectedNavigation;
    private ulong? _expectedNavigationId;
    private string? _lastActionExpectedNavigation;
    private long? _activeTraceStarted;
    private ulong? _documentNavigationId;
    private bool _documentLoading;
    private int _lifecycle;
    private GarmothBrowserWindow? _backgroundOperationWindow;
    private bool _backgroundLoginRequired;
    private bool _dialogReviewRequired;
    private const string BackgroundLoginMessage = "Sign in using Open Garmoth, then prepare again. Your items stay in Session Import.";
    private const string DialogReviewMessage = "Garmoth requested a dialog. Open Garmoth to review, then prepare again.";
    internal GarmothBrowserWindow? CurrentWindow => _window;
    internal CoreWebView2? CurrentCore => _window?.Core;
    internal Action<string>? NavigationDiagnostic { get; set; }

    public RegistrationResult Registration { get; } = new(true, string.Empty, "Garmoth connection available.");
    internal EmbeddedGarmothBrowser(GarmothConnectionPreferences? preferences = null,
        Func<Task<CoreWebView2Environment>>? environmentFactory = null)
    {
        _preferences = preferences ?? new GarmothConnectionPreferences();
        _environmentFactory = environmentFactory;
    }

    public async Task OpenAsync(Window? owner = null)
    {
        if (_forgetting is not null)
            throw new InvalidOperationException("The Garmoth connection is being forgotten. Wait for it to finish or close the connection.");
        if (_window is { IsConnectionClosed: false } existing)
        {
            _backgroundOperationWindow = null;
            _backgroundLoginRequired = false;
            _dialogReviewRequired = false;
            existing.ShowForUser(owner);
            var opening = _opening ?? _initialNavigation;
            if (opening is not null) await opening.WaitAsync(_lifetime.Token);
            if (!ReferenceEquals(_window, existing) || existing.IsConnectionClosed)
                throw new OperationCanceledException("The Garmoth connection was closed.");
            return;
        }
        if (_opening is not null)
        {
            var lifecycle = _lifecycle;
            try { await _opening; }
            catch { /* A cancelled/failed previous window must finish before its replacement. */ }
            if (_lifecycle != lifecycle || _window is not null) return;
        }
        _lifetime.Dispose();
        _lifetime = new CancellationTokenSource();
        var remembered = _preferences.RememberConnection;
        var window = CreateWindow(owner, remembered);
        _window = window;
        window.Show();
        if (remembered) await OpenPageAsync(window, remember: true);
    }

    public async Task OpenForPreparationAsync(Window? owner = null)
    {
        if (_forgetting is not null)
            throw new InvalidOperationException("The Garmoth connection is being forgotten. Wait for it to finish.");
        var window = _window;
        if (window?.IsConnectionClosed != false)
        {
            if (_opening is not null)
            {
                var lifecycle = _lifecycle;
                try { await _opening; }
                catch { /* Complete the previous lifecycle before considering a replacement. */ }
                if (_lifecycle != lifecycle)
                    throw new OperationCanceledException("The Garmoth connection was closed.");
                window = _window;
            }
            if (window?.IsConnectionClosed != false)
            {
                _lifetime.Dispose();
                _lifetime = new CancellationTokenSource();
                window = CreateWindow(null, _preferences.RememberConnection);
                window.ConfigureForBackground(owner);
                _window = window;
                window.Show(); // Offscreen, no taskbar entry and native NOACTIVATE.
            }
        }
        _backgroundOperationWindow = window;
        var opening = _opening ?? _initialNavigation;
        if (opening is not null) await opening.WaitAsync(_lifetime.Token);
        else if (window.Core is null) await InitializeSharedPageAsync(window, _preferences.RememberConnection);
        _lifetime.Token.ThrowIfCancellationRequested();
        if (!ReferenceEquals(_window, window) || window.IsConnectionClosed || window.Core is null)
            throw new InvalidOperationException("The Garmoth connection closed. Prepare again when it is available.");
        if (_backgroundLoginRequired) throw new InvalidOperationException(BackgroundLoginMessage);
        if (_dialogReviewRequired) throw new InvalidOperationException(DialogReviewMessage);
    }

    private GarmothBrowserWindow CreateWindow(Window? owner, bool remembered, bool maintenance = false)
    {
        var window = new GarmothBrowserWindow(remembered, canForget: _preferences.HasProfileData, maintenance: maintenance);
        if (owner?.IsLoaded == true) window.Owner = owner;
        window.OpenRequested += async remember => await OpenPageAsync(window, remember);
        window.ForgetRequested += async () =>
        {
            try { await ForgetAsync(); }
            catch (OperationCanceledException) { }
            catch (Exception error)
            {
                var current = _window ?? window;
                current.SetRemembered(true);
                current.SetStatus("The connection could not be forgotten: " + error.Message);
            }
        };
        window.Closed += (_, _) =>
        {
            if (!ReferenceEquals(_window, window)) return;
            _lifecycle++;
            _activeOperation?.Cancel();
            if (maintenance) _forgetCancellation?.Cancel();
            _lifetime.Cancel();
            CloseChildren();
            _preparedDraftId = null;
            _expectedNavigation = null;
            _expectedNavigationId = null;
            _documentNavigationId = null;
            _documentLoading = false;
            _window = null;
            _environment = null;
            _backgroundOperationWindow = null;
            _backgroundLoginRequired = false;
            _dialogReviewRequired = false;
        };
        return window;
    }

    private async Task OpenPageAsync(GarmothBrowserWindow window, bool remember)
    {
        if (_forgetting is not null) return;
        try { await InitializeSharedPageAsync(window, remember); }
        catch (OperationCanceledException) { }
        catch (Exception error)
        {
            if (!window.IsConnectionClosed) window.SetStatus(error.Message + " You can use the Firefox fallback in Session Import.");
        }
    }

    private async Task InitializeSharedPageAsync(GarmothBrowserWindow window, bool remember)
    {
        var task = _opening ?? InitializePageAsync(window, remember);
        _opening = task;
        try { await task; }
        finally { if (ReferenceEquals(_opening, task)) _opening = null; }
    }

    private async Task InitializePageAsync(GarmothBrowserWindow window, bool remember)
    {
        using var initialization = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
        initialization.CancelAfter(TimeSpan.FromSeconds(45));
        var cancellation = initialization.Token;
        window.SetStatus("Opening Garmoth…");
        await GarmothRuntimeSetup.EnsureAsync(window.SetStatus, cancellation);
        cancellation.ThrowIfCancellationRequested();
        var environment = await CreateEnvironmentAsync(cancellation);
        cancellation.ThrowIfCancellationRequested();
        _environment = environment;
        _rememberedSession = remember;
        await window.InitializeBrowserAsync(environment, ControllerOptions(environment, remember)).WaitAsync(cancellation);
        cancellation.ThrowIfCancellationRequested();
        Configure(window, main: true);
        // Persist only an explicit choice, after the runtime/profile is available.
        if (_preferences.RememberConnection != remember) _preferences.SetRememberConnection(remember);
        window.SetRemembered(_preferences.HasProfileData);
        await OpenInitialPageAsync(window, cancellation);
    }

    private async Task OpenInitialPageAsync(GarmothBrowserWindow window, CancellationToken cancellation)
    {
        var pending = NavigateInitialPageAsync(window, cancellation);
        _initialNavigation = pending;
        try { await pending; }
        finally { if (ReferenceEquals(_initialNavigation, pending)) _initialNavigation = null; }
    }

    private async Task NavigateInitialPageAsync(GarmothBrowserWindow window, CancellationToken cancellation)
    {
        using var opening = CancellationTokenSource.CreateLinkedTokenSource(cancellation, _lifetime.Token);
        opening.CancelAfter(TimeSpan.FromSeconds(45));
        var core = window.Core!;
        var loaded = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        ulong? navigationId = null;
        void Starting(object? sender, CoreWebView2NavigationStartingEventArgs args)
        {
            if (navigationId is null && args.Uri == GarmothNavigationPolicy.TrackerUrl && !args.Cancel)
                navigationId = args.NavigationId;
            else if (navigationId != args.NavigationId || args.Cancel ||
                !GarmothNavigationPolicy.IsAllowedNavigation(args.Uri))
                loaded.TrySetException(new InvalidOperationException("Garmoth navigated away while opening. Prepare this session again."));
        }
        void Completed(object? sender, CoreWebView2NavigationCompletedEventArgs args)
        {
            if (args.NavigationId == navigationId) loaded.TrySetResult(args.IsSuccess);
        }
        core.NavigationStarting += Starting;
        core.NavigationCompleted += Completed;
        // Navigate returns before its first event. Keep this wait visible to
        // Open/Prepare from that instant; preparation must not arm against blank.
        _documentLoading = true;
        try
        {
            opening.Token.ThrowIfCancellationRequested();
            core.Navigate(GarmothNavigationPolicy.TrackerUrl);
            if (!await loaded.Task.WaitAsync(opening.Token))
                throw new InvalidOperationException("Garmoth could not load. Reload the page, then prepare again.");
            opening.Token.ThrowIfCancellationRequested();
            if (!ReferenceEquals(_window, window) || window.IsConnectionClosed || !IsGarmothPage(core.Source))
                throw new InvalidOperationException("Finish opening Garmoth, then prepare again. Your items stay here.");
        }
        finally
        {
            core.NavigationStarting -= Starting;
            core.NavigationCompleted -= Completed;
            if (ReferenceEquals(_window, window) && _documentNavigationId == navigationId) _documentLoading = false;
        }
    }

    internal static CoreWebView2ControllerOptions ControllerOptions(CoreWebView2Environment environment, bool remember)
    {
        var options = environment.CreateCoreWebView2ControllerOptions();
        options.ProfileName = "Garmoth";
        options.IsInPrivateModeEnabled = !remember;
        return options;
    }

    private async Task<CoreWebView2Environment> CreateEnvironmentAsync(CancellationToken cancellation)
    {
        var overriddenFolder = Environment.GetEnvironmentVariable("WEBVIEW2_USER_DATA_FOLDER");
        if (!string.IsNullOrEmpty(overriddenFolder) && !SamePath(overriddenFolder, _preferences.UserDataFolder))
            throw new InvalidOperationException("A system WebView profile override prevents an isolated Garmoth connection.");
        var pending = _environmentFactory?.Invoke() ?? CoreWebView2Environment.CreateAsync(
            userDataFolder: _preferences.UserDataFolder,
            options: new CoreWebView2EnvironmentOptions { ReleaseChannels = CoreWebView2ReleaseChannels.Stable });
        var environment = await pending.WaitAsync(cancellation);
        cancellation.ThrowIfCancellationRequested();
        if (!SamePath(environment.UserDataFolder, _preferences.UserDataFolder))
            throw new InvalidOperationException("The browser did not use Session Import's isolated profile.");
        return environment;
    }

    private static bool SamePath(string first, string second) => string.Equals(
        Path.TrimEndingDirectorySeparator(Path.GetFullPath(first)),
        Path.TrimEndingDirectorySeparator(Path.GetFullPath(second)), StringComparison.OrdinalIgnoreCase);

    private void Configure(GarmothBrowserWindow window, bool main)
    {
        var core = window.Core!;
        core.Settings.AreDevToolsEnabled = false;
        core.Settings.AreHostObjectsAllowed = false;
        core.Settings.IsWebMessageEnabled = false;
        core.Settings.IsStatusBarEnabled = false;
        core.Settings.AreDefaultContextMenusEnabled = false;
        core.Settings.AreBrowserAcceleratorKeysEnabled = false;
        // This is a document-load-time setting; configure it before initial Navigate.
        core.Settings.AreDefaultScriptDialogsEnabled = false;
        core.ScriptDialogOpening += (_, args) =>
        {
            if (MayShowForegroundScriptDialog(window))
            {
                var accepted = window.TryShowForegroundScriptDialog(args.Kind, args.Message, args.DefaultText, out var resultText);
                // A modal pumps messages. Recheck preparation/lifecycle before consent.
                if (accepted && MayShowForegroundScriptDialog(window))
                {
                    if (args.Kind == CoreWebView2ScriptDialogKind.Prompt) args.ResultText = resultText ?? string.Empty;
                    args.Accept();
                }
                return;
            }
            // No Accept, deferral, native dialog, or exported site message.
            _dialogReviewRequired = true;
            _preparedDraftId = null;
            if (!window.IsConnectionClosed) window.SetStatus(DialogReviewMessage);
            CancelActivePreparation("script_dialog_blocked");
            _pendingPreparation?.Cancel();
        };
        core.Profile.IsPasswordAutosaveEnabled = false;
        core.Profile.IsGeneralAutofillEnabled = false;
        core.PermissionRequested += (_, args) =>
        {
            args.State = CoreWebView2PermissionState.Deny;
            args.SavesInProfile = false;
        };
        core.DownloadStarting += (_, args) => { args.Cancel = true; args.Handled = true; };
        core.LaunchingExternalUriScheme += (_, args) => args.Cancel = true;
        core.ServerCertificateErrorDetected += (_, args) => args.Action = CoreWebView2ServerCertificateErrorAction.Cancel;
        core.BasicAuthenticationRequested += (_, args) => args.Cancel = true;
        core.NavigationStarting += (_, args) =>
        {
            if (!GarmothNavigationPolicy.IsAllowedNavigation(args.Uri))
            {
                args.Cancel = true;
                window.SetStatus("That destination is not allowed here. Use the Firefox fallback if sign-in needs another provider.");
            }
            if (main && ReferenceEquals(_window, window))
            {
                _preparedDraftId = null;
                if (args.Cancel)
                {
                    CancelActivePreparation("blocked_navigation_start");
                    return;
                }
                _documentNavigationId = args.NavigationId;
                _documentLoading = true;
                if (_activeOperation is not null)
                {
                    if (IsExpectedNavigation(args.Uri, args.NavigationId))
                        _expectedNavigationId = args.NavigationId;
                    else
                        CancelActivePreparation("unexpected_navigation_start", new JsonObject
                        {
                            ["expectedNavigationArmed"] = _expectedNavigation is not null,
                            ["matchesLastActionDestination"] = args.Uri == _lastActionExpectedNavigation
                        });
                }
            }
        };
        core.NavigationCompleted += (_, args) =>
        {
            if (main && ReferenceEquals(_window, window) && _documentNavigationId == args.NavigationId)
                _documentLoading = false;
        };
        core.SourceChanged += (_, args) =>
        {
            if (!main || !ReferenceEquals(_window, window)) return;
            _preparedDraftId = null;
            if (_activeOperation is not null &&
                (_expectedNavigation is null || !string.Equals(core.Source, _expectedNavigation, StringComparison.Ordinal)))
                CancelActivePreparation("unexpected_source_change", new JsonObject
                {
                    ["expectedNavigationArmed"] = _expectedNavigation is not null,
                    ["matchesLastActionDestination"] = core.Source == _lastActionExpectedNavigation,
                    ["isNewDocument"] = args.IsNewDocument
                });
        };
        core.NewWindowRequested += async (_, args) => await OpenAuthenticationWindowAsync(window, args);
        core.WindowCloseRequested += (_, _) => window.Close();
        core.ProcessFailed += (_, _) =>
        {
            if (main && ReferenceEquals(_window, window))
            {
                CancelActivePreparation("browser_process_failed");
                _preparedDraftId = null;
                _documentLoading = false;
            }
            window.SetStatus("The browser stopped. Close this connection and open Garmoth again.");
        };
    }

    private async Task OpenAuthenticationWindowAsync(GarmothBrowserWindow opener, CoreWebView2NewWindowRequestedEventArgs args)
    {
        args.Handled = true;
        if (IsAuthenticationPopupSuppressed(opener.IsBackgroundPreparation,
            ReferenceEquals(_backgroundOperationWindow, opener), _activeOperation is not null,
            _pendingPreparation is not null, opener.IsActive))
        {
            _backgroundLoginRequired = true;
            opener.SetStatus(BackgroundLoginMessage);
            _pendingPreparation?.Cancel();
            _activeOperation?.Cancel();
            return;
        }
        if (_environment is null || _lifetime.IsCancellationRequested ||
            !GarmothNavigationPolicy.IsAllowedNavigation(args.Uri))
        {
            opener.SetStatus("This sign-in destination is not supported here. Use the Firefox fallback.");
            return;
        }
        using var deferral = args.GetDeferral();
        GarmothBrowserWindow? child = null;
        try
        {
            var environment = _environment;
            var cancellation = _lifetime.Token;
            child = new GarmothBrowserWindow(_rememberedSession, authentication: true) { Owner = opener };
            _children.Add(child);
            child.Closed += (_, _) => _children.Remove(child);
            child.Show();
            await child.InitializeBrowserAsync(environment, ControllerOptions(environment, _rememberedSession));
            cancellation.ThrowIfCancellationRequested();
            Configure(child, main: false);
            // An unnavigated WebView with the same environment/profile preserves OAuth's opener.
            args.NewWindow = child.Core;
        }
        catch (Exception error)
        {
            if (child?.IsConnectionClosed == false) child.Close();
            if (!opener.IsConnectionClosed) opener.SetStatus("Sign-in could not open: " + error.Message);
        }
    }

    internal static bool IsAuthenticationPopupSuppressed(bool backgroundMode, bool backgroundOperation,
        bool activePreparation, bool pendingPreparation, bool openerActive) =>
        backgroundMode || backgroundOperation || activePreparation || pendingPreparation || !openerActive;

    private bool MayShowForegroundScriptDialog(GarmothBrowserWindow window) =>
        (ReferenceEquals(_window, window) || _children.Contains(window)) && !window.IsConnectionClosed && window.IsVisible && window.IsActive &&
        !window.IsBackgroundPreparation && !ReferenceEquals(_backgroundOperationWindow, window) &&
        _activeOperation is null && _pendingPreparation is null && _forgetting is null;

    public async Task<JsonObject> SendAsync(JsonObject request, TimeSpan timeout)
    {
        var type = request["type"]?.GetValue<string>();
        var draftId = type == "prepare" ? request["draft"]?["draftId"]?.GetValue<string>()
            : request["draftId"]?.GetValue<string>();
        if (request["protocolVersion"]?.GetValue<int>() != SessionImportProtocol.Version ||
            Encoding.UTF8.GetByteCount(request.ToJsonString()) > 64 * 1024)
            return Failure(type, draftId, "Unsupported or oversized connection request.");
        if (timeout <= TimeSpan.Zero || timeout.TotalMilliseconds > int.MaxValue)
            return Failure(type, draftId, "The connection timeout is invalid.");
        if (_forgetting is not null)
            return type == "status"
                ? WithRememberedPreference(ConnectionStatusResponse(_window?.Core is not null, "maintenance", false))
                : Failure(type, draftId, "The Garmoth connection is being forgotten.");
        if (type == "status") return WithRememberedPreference(await ReadStatusAsync(timeout));
        if (type is not ("prepare" or "review")) return Failure(type, draftId, "Unsupported connection request.");
        var revealIfOwnerActive = false;
        if (type == "review" && request.ContainsKey("revealIfOwnerActive") &&
            (request["revealIfOwnerActive"] is not JsonValue revealValue || !revealValue.TryGetValue(out revealIfOwnerActive)))
            return Failure(type, draftId, "The review request is invalid.");
        if (!await _operation.WaitAsync(0)) return Failure(type, draftId, "Another preparation is still running.");
        var window = _window;
        var boundedTimeout = timeout > TimeSpan.FromSeconds(45) ? TimeSpan.FromSeconds(45) : timeout;
        var deadline = DateTimeOffset.UtcNow.Add(boundedTimeout).ToUnixTimeMilliseconds();
        var traceStarted = Environment.TickCount64;
        using var cancellation = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
        cancellation.CancelAfter(boundedTimeout);
        _pendingPreparation = cancellation;
        var token = Guid.NewGuid().ToString("N");
        JsonObject Stopped(string message)
        {
            if (_backgroundLoginRequired) message = BackgroundLoginMessage;
            else if (_dialogReviewRequired) message = DialogReviewMessage;
            if (ReferenceEquals(_window, window) && window?.IsConnectionClosed == false) window.SetStatus(message);
            var response = Failure(type, draftId, message);
            if (_backgroundLoginRequired) response["code"] = "login_required";
            else if (_dialogReviewRequired) response["code"] = "script_dialog_review_required";
            return response;
        }
        JsonObject PreparedFormMissing()
        {
            _preparedDraftId = null;
            var response = Stopped("The prepared form is no longer open. Send this session again.");
            response["preparedFormMissing"] = true;
            return response;
        }
        try
        {
            TracePreparation("prepare_start", traceStarted);
            if (type == "review" && (string.IsNullOrEmpty(draftId) || draftId != _preparedDraftId))
                return PreparedFormMissing();
            var opening = _opening ?? _initialNavigation;
            if (opening is not null) await opening.WaitAsync(cancellation.Token);
            cancellation.Token.ThrowIfCancellationRequested();
            if (!ReferenceEquals(_window, window))
                return type == "review" ? PreparedFormMissing() : Stopped("The Garmoth connection changed. Prepare this session again.");
            if (_backgroundLoginRequired) return Stopped(BackgroundLoginMessage);
            if (_dialogReviewRequired) return Stopped(DialogReviewMessage);
            _activeOperation = cancellation;
            _activeTraceStarted = traceStarted;
            if (window?.Core is null || window.IsConnectionClosed)
                return type == "review" ? PreparedFormMissing() : Stopped("Open Garmoth and sign in first. Your items stay in Session Import.");
            if (type == "review")
            {
                if (string.IsNullOrEmpty(draftId) || draftId != _preparedDraftId)
                    return PreparedFormMissing();
                var status = await ExecuteAsync(window, EmbeddedGarmothScripts.Status(), cancellation.Token);
                if (status is null)
                    return Stopped("The prepared form could not be checked. Try Review again.");
                if (draftId != _preparedDraftId || status["draftId"]?.GetValue<string>() != draftId)
                    return PreparedFormMissing();
                var revealed = !revealIfOwnerActive;
                if (revealIfOwnerActive) revealed = window.TryShowForUserIfOwnerActive();
                else window.ShowForUser();
                if (revealed)
                {
                    _backgroundOperationWindow = null;
                    _backgroundLoginRequired = false;
                }
                var reviewed = Success(type, draftId);
                reviewed["revealed"] = revealed;
                return reviewed;
            }
            _preparedDraftId = null;
            if (request["draft"] is not JsonObject draft)
                return Stopped("The session draft is missing.");
            await FindPreparationPageAsync(window, draft, deadline, traceStarted, cancellation.Token);
            TracePreparation("helper_start", traceStarted);
            var start = await ExecuteAsync(window, EmbeddedGarmothScripts.Start(token, draft.ToJsonString(), deadline), cancellation.Token);
            TracePreparation("helper_started", traceStarted);
            if (start?["started"]?.GetValue<bool>() != true)
                return Stopped("Garmoth's Add session form is not ready. Your items stay in Session Import.");
            while (true)
            {
                await Task.Delay(75, cancellation.Token);
                var result = await ExecuteAsync(window, EmbeddedGarmothScripts.Poll(token), cancellation.Token);
                if (result?["lost"]?.GetValue<bool>() == true)
                    return Stopped("Garmoth navigated away. Prepare this session again.");
                if (result?["done"]?.GetValue<bool>() != true) continue;
                TracePreparation("helper_done", traceStarted);
                if (result["result"] is not JsonObject answer || answer["ok"]?.GetValue<bool>() != true)
                    return Stopped(result["result"]?["message"]?.GetValue<string>() ?? "Garmoth could not prepare the draft.");
                if (answer["draftId"]?.GetValue<string>() != draftId)
                    return Stopped("The prepared form did not match this session.");
                cancellation.Token.ThrowIfCancellationRequested();
                _preparedDraftId = draftId;
                var response = Success(type, draftId);
                response["matched"] = (answer["matched"] as JsonArray)?.Count ?? 0;
                response["skipped"] = answer["skipped"]?.DeepClone() ?? new JsonArray();
                response["warnings"] = answer["warnings"]?.DeepClone() ?? new JsonArray();
                response["notesVerified"] = answer["notesVerified"]?.DeepClone() ?? new JsonArray();
                response["notesStatus"] = answer["notesStatus"]?.DeepClone() ?? JsonValue.Create("not_needed");
                var skippedCount = (response["skipped"] as JsonArray)?.Count ?? 0;
                var notedCount = PreparedNotes.VerifiedIndices(response, draft["session"]?["items"] as JsonArray ?? []).Count;
                var notEntered = skippedCount - notedCount;
                var notesSummary = notedCount > 0 ? $" {notedCount} items in Notes, not included in Garmoth totals." : string.Empty;
                window.SetStatus((notEntered > 0
                    ? $"Incomplete · {response["matched"]!.GetValue<int>()} entered · {notEntered} not entered. Review the items in Garmoth before saving."
                    : "Session prepared. Review the values in Garmoth before saving.") + notesSummary +
                    ((response["warnings"] as JsonArray)?.Count > 0 ? " Some fields need checking." : string.Empty));
                return response;
            }
        }
        catch (OperationCanceledException)
        {
            TracePreparation("prepare_cancelled", traceStarted);
            if (type == "prepare") _preparedDraftId = null;
            return Stopped("Preparation stopped or timed out. Review your items and try again.");
        }
        catch (Exception error)
        {
            TracePreparation("prepare_failed", traceStarted);
            if (type == "prepare") _preparedDraftId = null;
            return Stopped(error.Message);
        }
        finally
        {
            // The helper also checks its own absolute deadline before every DOM mutation.
            if (type == "prepare" && ReferenceEquals(_activeOperation, cancellation) && window?.Core is not null && GarmothNavigationPolicy.IsTrackerUrl(window.Core.Source))
            {
                TracePreparation("cleanup_start", traceStarted);
                try
                {
                    await window.Core.ExecuteScriptAsync(EmbeddedGarmothScripts.Cancel(token)).WaitAsync(TimeSpan.FromMilliseconds(500));
                    TracePreparation("cleanup_complete", traceStarted);
                }
                catch
                {
                    TracePreparation("cleanup_close", traceStarted);
                    // Do not leave a timed-out script running in a reusable browser window.
                    // Its own deadline guard prevents writes while teardown destroys the document.
                    if (!window.IsConnectionClosed) window.Close();
                }
            }
            _activeOperation = null;
            _activeTraceStarted = null;
            _lastActionExpectedNavigation = null;
            _pendingPreparation = null;
            if (window?.IsBackgroundPreparation == false && ReferenceEquals(_backgroundOperationWindow, window))
                _backgroundOperationWindow = null;
            _expectedNavigation = null;
            _expectedNavigationId = null;
            _operation.Release();
        }
    }

    private bool IsExpectedNavigation(string destination, ulong navigationId) =>
        _expectedNavigation is not null && IsPreparationDestination(destination) &&
        string.Equals(destination, _expectedNavigation, StringComparison.Ordinal) &&
        (_expectedNavigationId is null || _expectedNavigationId == navigationId);

    private static bool IsPreparationDestination(string destination) =>
        GarmothNavigationPolicy.IsTrackerUrl(destination) &&
        !new Uri(destination).AbsolutePath.Split('/').Any(part => part is "null" or "undefined");

    private void CancelActivePreparation(string code, JsonObject? detail = null)
    {
        if (_activeOperation is null) return;
        detail ??= [];
        detail["code"] = code;
        if (_activeTraceStarted is { } started) TracePreparation("cancellation_requested", started, detail);
        _activeOperation.Cancel();
    }

    private void TracePreparation(string phase, long started, JsonObject? detail = null)
    {
        if (NavigationDiagnostic is null) return;
        // Opt-in diagnostics contain no route/account identifiers. Observer
        // failures must not affect the production operation or its deadline.
        var trace = new JsonObject { ["phase"] = phase, ["elapsedMs"] = Environment.TickCount64 - started };
        foreach (var key in new[] { "state", "action", "code", "message", "scriptElapsedMs", "visibilityState",
            "expectedNavigationArmed", "matchingNavigation", "nativeSuccess", "matchesLastActionDestination", "isNewDocument",
            "documentReadyState", "bodyTextLength", "bodyElementCount", "mainCount", "grindMenuCount", "headingCount", "visibleHeadingCount", "visibleControlCount",
            "httpStatusCode", "webErrorStatus", "attempt" })
            if (detail?[key] is { } value) trace[key] = value.DeepClone();
        try { NavigationDiagnostic.Invoke(trace.ToJsonString()); }
        catch { /* Test-only observers cannot change preparation behavior. */ }
    }

    private string TimedNavigationScript(string script) => NavigationDiagnostic is null ? script : $$"""
        (() => {
          const started = performance.now();
          const result = {{script}};
          const scriptElapsedMs = Math.round(performance.now() - started);
          const structure = result?.code === 'no_matching_link' ? {{PageStructureDiagnostic}} : null;
          return {...result, ...structure, scriptElapsedMs, visibilityState: document.visibilityState};
        })()
        """;

    // Test-observer-only scalar diagnostics. No document text, URLs, forms,
    // account globals, storage or network data are exported or modified.
    internal const string PageStructureDiagnostic = """
        (() => {
          if(window!==top||location.origin!=='https://garmoth.com')return null;
          const visible=e=>{const s=getComputedStyle(e);return e.getClientRects().length>0&&s.display!=='none'&&s.visibility!=='hidden'&&s.opacity!=='0'};
          const all=s=>[...document.querySelectorAll(s)];
          const bounded=n=>Math.min(n,1000000);
          const headings=all('h1,h2,h3,h4,h5,h6,[role=heading]');
          return {documentReadyState:document.readyState,visibilityState:document.visibilityState,
            bodyTextLength:bounded((document.body?.innerText||'').trim().length),
            bodyElementCount:bounded(document.body?.querySelectorAll('*').length||0),
            mainCount:all('main').length,grindMenuCount:all('#grind-menu').length,
            headingCount:headings.length,visibleHeadingCount:headings.filter(visible).length,
            visibleControlCount:all('button,a[href],input,select,textarea,[role=button]').filter(visible).length};
        })()
        """;

    private async Task FindPreparationPageAsync(GarmothBrowserWindow window, JsonObject draft, long deadline, long traceStarted,
        CancellationToken cancellation)
    {
        var visited = new HashSet<string>(StringComparer.Ordinal);
        var actions = new HashSet<string>(StringComparer.Ordinal);
        var missingLinkSince = new Dictionary<(ulong? NavigationId, string Source), long>();
        var draftJson = draft.ToJsonString();
        var loadingReported = false;
        while (true)
        {
            cancellation.ThrowIfCancellationRequested();
            if (!ReferenceEquals(_window, window) || window.Core is null || window.IsConnectionClosed)
                throw new InvalidOperationException("The Garmoth window closed. Your items stay in Session Import.");
            if (_documentLoading)
            {
                if (!loadingReported) TracePreparation("document_wait_start", traceStarted);
                loadingReported = true;
                window.SetStatus("Loading Garmoth…");
                await Task.Delay(100, cancellation);
                continue;
            }
            if (loadingReported) TracePreparation("document_wait_complete", traceStarted);
            loadingReported = false;
            var core = window.Core;
            var source = core.Source;
            if (!IsGarmothPage(source))
                throw new InvalidOperationException("Finish signing in to Garmoth, then prepare again. Your items stay here.");
            TracePreparation("discover_start", traceStarted);
            var json = await core.ExecuteScriptAsync(TimedNavigationScript(EmbeddedGarmothNavigationScripts.Discover(draftJson))).WaitAsync(cancellation);
            cancellation.ThrowIfCancellationRequested();
            if (!ReferenceEquals(_window, window) || window.Core is null || core.Source != source)
                throw new InvalidOperationException("Garmoth navigated away. Prepare this session again.");
            var step = JsonNode.Parse(json) as JsonObject;
            TracePreparation("discover_complete", traceStarted, step);
            switch (step?["state"]?.GetValue<string>())
            {
                case "ready":
                    if (!IsPreparationDestination(source))
                        throw new InvalidOperationException("Open your Garmoth tracker before preparing.");
                    window.SetStatus("Entering your session for review…");
                    return;
                case "loading":
                    window.SetStatus(step["message"]?.GetValue<string>() ?? "Waiting for Garmoth's session controls…");
                    await Task.Delay(150, cancellation);
                    continue;
                case "login_required":
                    if (window.IsBackgroundPreparation || ReferenceEquals(_backgroundOperationWindow, window))
                    {
                        _backgroundLoginRequired = true;
                        throw new InvalidOperationException(BackgroundLoginMessage);
                    }
                    throw new InvalidOperationException(step["message"]?.GetValue<string>() ?? "Sign in to Garmoth first.");
                case "blocked" when step["code"]?.GetValue<string>() == "no_matching_link":
                    // Native document completion can precede the tracker sidebar's
                    // client-side hydration. Retry only this specific absence, once
                    // per document, within the unchanged operation deadline.
                    var document = (_documentNavigationId, source);
                    if (!missingLinkSince.TryGetValue(document, out var since))
                        missingLinkSince[document] = since = Environment.TickCount64;
                    if (Environment.TickCount64 - since < 4000)
                    {
                        window.SetStatus("Waiting for Garmoth's tracker menu…");
                        await Task.Delay(150, cancellation);
                        continue;
                    }
                    throw new InvalidOperationException(step["message"]?.GetValue<string>() ??
                        "The matching tracker link did not appear. Open the exact spot in Garmoth, then prepare again.");
                case "navigate":
                    var destination = step["url"]?.GetValue<string>();
                    if (destination is null || !IsPreparationDestination(destination) || destination == source ||
                        !visited.Add(destination) || visited.Count > 4)
                        throw new InvalidOperationException("The exact spot could not be opened safely. Open it in Garmoth, then prepare again.");
                    window.SetStatus(step["message"]?.GetValue<string>() ?? "Opening your Garmoth spot…");
                    await NavigateForPreparationAsync(window, destination, draft["target"]?["spotId"]?.GetValue<string>(), traceStarted, cancellation);
                    continue;
                case "act":
                    var action = step["action"]?.GetValue<string>();
                    if (action is not ("expand_tracker" or "select_activity" or "expand_spot_group") || !IsPreparationDestination(source) ||
                        !actions.Add(source + "\n" + action) || actions.Count > 4)
                        throw new InvalidOperationException("Garmoth's tracker menu could not be opened safely. Open the matching spot, then prepare again.");
                    var expectedUrl = step["expectedUrl"]?.GetValue<string>();
                    if ((action == "expand_spot_group" && expectedUrl is not null) ||
                        (expectedUrl is not null && !IsPreparationDestination(expectedUrl)))
                        throw new InvalidOperationException("The tracker menu points to an unsupported destination.");
                    window.SetStatus(step["message"]?.GetValue<string>() ?? "Opening Garmoth's tracker menu…");
                    await ExecuteNavigationActionAsync(window, draftJson, action, expectedUrl, deadline, traceStarted, cancellation);
                    continue;
                default:
                    throw new InvalidOperationException(step?["message"]?.GetValue<string>() ??
                        "The session controls could not be found on this Garmoth page. Your items stay here.");
            }
        }
    }

    private async Task ExecuteNavigationActionAsync(GarmothBrowserWindow window, string draftJson, string action,
        string? expectedUrl, long deadline, long traceStarted, CancellationToken cancellation)
    {
        var core = window.Core!;
        var source = core.Source;
        var loaded = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        void Completed(object? sender, CoreWebView2NavigationCompletedEventArgs args)
        {
            TracePreparation("action_native_completed", traceStarted, new JsonObject
            {
                ["action"] = action, ["matchingNavigation"] = _expectedNavigationId == args.NavigationId,
                ["nativeSuccess"] = args.IsSuccess, ["httpStatusCode"] = args.HttpStatusCode,
                ["webErrorStatus"] = args.WebErrorStatus.ToString()
            });
            if (_expectedNavigationId == args.NavigationId) loaded.TrySetResult(args.IsSuccess);
        }
        void SourceChanged(object? sender, CoreWebView2SourceChangedEventArgs args)
        {
            // Vue may commit its validated parent link with pushState after the
            // click has returned, without NavigationStarting/Completed. A new
            // document must still reach its matching native completion instead.
            if (!args.IsNewDocument && expectedUrl is not null && core.Source == expectedUrl)
            {
                TracePreparation("action_spa_destination", traceStarted, new JsonObject
                {
                    ["action"] = action, ["isNewDocument"] = false, ["matchesLastActionDestination"] = true
                });
                loaded.TrySetResult(true);
            }
        }
        // A scoped menu button can be nested in a rendered summary link. Permit
        // only that independently revalidated URL, never arbitrary act navigation.
        _expectedNavigation = expectedUrl;
        if (expectedUrl is not null) _lastActionExpectedNavigation = expectedUrl;
        _expectedNavigationId = null;
        core.NavigationCompleted += Completed;
        core.SourceChanged += SourceChanged;
        try
        {
            cancellation.ThrowIfCancellationRequested();
            string? json = null;
            try
            {
                TracePreparation("action_script_start", traceStarted, new JsonObject { ["action"] = action, ["expectedNavigationArmed"] = expectedUrl is not null });
                json = await core.ExecuteScriptAsync(TimedNavigationScript(EmbeddedGarmothNavigationScripts.Execute(draftJson, action, deadline, expectedUrl)))
                    .WaitAsync(cancellation);
            }
            catch (System.Runtime.InteropServices.COMException) when (_expectedNavigationId is not null &&
                ReferenceEquals(_window, window) && !cancellation.IsCancellationRequested)
            {
                // The verified link replaced its own script document. Await its
                // matching native completion instead of requiring an old reply.
            }
            cancellation.ThrowIfCancellationRequested();
            var result = json is null ? null : JsonNode.Parse(json) as JsonObject;
            TracePreparation("action_script_complete", traceStarted, result);
            if (result is not null && result["acted"]?.GetValue<bool>() != true)
                throw new InvalidOperationException(result["message"]?.GetValue<string>() ?? "The tracker menu changed. Prepare this session again.");
            await Task.Delay(150, cancellation);
            TracePreparation("action_settled", traceStarted, new JsonObject { ["action"] = action, ["expectedNavigationArmed"] = _expectedNavigationId is not null });
            // Do not retire permission for a different, explicitly observed URL
            // after an arbitrary150ms. Await its exact SPA/native commit inside
            // the original operation deadline before discovering another action.
            var destinationPending = expectedUrl is not null && expectedUrl != source;
            if ((destinationPending || _expectedNavigationId is not null) && !await loaded.Task.WaitAsync(cancellation))
                throw new InvalidOperationException("Garmoth could not load the tracker menu destination.");
            cancellation.ThrowIfCancellationRequested();
            if (!ReferenceEquals(_window, window) || window.Core is null ||
                (core.Source != source && (expectedUrl is null || core.Source != expectedUrl)))
                throw new InvalidOperationException("Garmoth navigated away. Prepare this session again.");
            // A completed document navigation may discard the script's return
            // value. Without that specific navigation, a missing result fails.
            if (result is null && _expectedNavigationId is null)
                throw new InvalidOperationException("The tracker menu could not be checked. Prepare this session again.");
            TracePreparation("action_complete", traceStarted, new JsonObject { ["action"] = action });
        }
        finally
        {
            core.NavigationCompleted -= Completed;
            core.SourceChanged -= SourceChanged;
            _expectedNavigation = null;
            _expectedNavigationId = null;
        }
    }

    private sealed record NavigationOutcome(bool Success, int HttpStatus, CoreWebView2WebErrorStatus Error);

    internal static bool IsTransientSpotResponse(int status, CoreWebView2WebErrorStatus error) =>
        status is 500 or 502 or 503 or 504 && error is CoreWebView2WebErrorStatus.Unknown
            or CoreWebView2WebErrorStatus.ErrorHttpInvalidServerResponse or CoreWebView2WebErrorStatus.UnexpectedError;

    private static bool IsExactNumericSpotDestination(string destination, string? requestedSpotId)
    {
        var uri = new Uri(destination);
        var parts = uri.AbsolutePath.Trim('/').Split('/');
        return requestedSpotId is { Length: > 0 } && requestedSpotId.All(char.IsAsciiDigit) && requestedSpotId[0] != '0'
            && parts.Length == 4 && parts[0] == "grind-tracker" && parts[2] == "spot" && parts[3] == requestedSpotId
            && uri.Query.Length == 0 && uri.Fragment.Length == 0 && IsPreparationDestination(destination);
    }

    private const string RetryBarrierObservation = """
        (() => {
          if(window!==top||location.origin!=='https://garmoth.com')return {blocked:true};
          const visible=e=>{const s=getComputedStyle(e);return e.getClientRects().length>0&&s.display!=='none'&&s.visibility!=='hidden'};
          const text=e=>(e.innerText||e.textContent||'').trim().replace(/\s+/g,' ');
          const headings=[...document.querySelectorAll('h1,h2,[role=heading]')].filter(visible).map(text).join(' ');
          const login=[...document.querySelectorAll('button,a,[role=button],input[type=password],input[type=email]')].filter(visible)
            .some(e=>e.matches('input[type=password],input[type=email]')||/^(?:log\s?in|sign\s?in)(?: to garmoth| with discord)?$/i.test(text(e)));
          const challenge=/verify (?:that )?you are human|captcha|checking your browser|just a moment|attention required|access denied|security check|unusual traffic/i;
          return {blocked:login||challenge.test(document.title+' '+headings)||!!document.querySelector('iframe[src*="captcha"],iframe[src*="challenges.cloudflare.com"]')};
        })()
        """;

    private async Task NavigateForPreparationAsync(GarmothBrowserWindow window, string destination, string? requestedSpotId,
        long traceStarted, CancellationToken cancellation)
    {
        var core = window.Core!;
        TaskCompletionSource<NavigationOutcome>? loaded = null;
        var attempt = 0;
        void Completed(object? sender, CoreWebView2NavigationCompletedEventArgs args)
        {
            TracePreparation("destination_native_completed", traceStarted, new JsonObject
            {
                ["matchingNavigation"] = _expectedNavigationId == args.NavigationId, ["nativeSuccess"] = args.IsSuccess,
                ["httpStatusCode"] = args.HttpStatusCode, ["webErrorStatus"] = args.WebErrorStatus.ToString(), ["attempt"] = attempt + 1
            });
            if (_expectedNavigationId == args.NavigationId) loaded?.TrySetResult(new(args.IsSuccess, args.HttpStatusCode, args.WebErrorStatus));
        }
        _expectedNavigation = destination;
        _expectedNavigationId = null;
        core.NavigationCompleted += Completed;
        try
        {
            for (attempt = 0; attempt < 2; attempt++)
            {
                cancellation.ThrowIfCancellationRequested();
                if (!ReferenceEquals(_window, window) || window.IsConnectionClosed || window.Core != core)
                    throw new OperationCanceledException("The Garmoth connection changed.");
                loaded = new(TaskCreationOptions.RunContinuationsAsynchronously);
                _expectedNavigationId = null;
                TracePreparation("destination_navigate", traceStarted, new JsonObject { ["attempt"] = attempt + 1 });
                core.Navigate(destination); // Native Navigate is a GET to this exact observed URL.
                var outcome = await loaded.Task.WaitAsync(cancellation);
                cancellation.ThrowIfCancellationRequested();
                if (!ReferenceEquals(_window, window) || window.Core != core || window.IsConnectionClosed || core.Source != destination)
                    throw new InvalidOperationException("Garmoth opened a different page. Prepare this session again.");
                if (outcome.Success && outcome.HttpStatus < 400)
                {
                    TracePreparation("destination_complete", traceStarted);
                    return;
                }
                var failure = outcome.HttpStatus > 0
                    ? $"Garmoth could not load that spot (HTTP {outcome.HttpStatus}). Your items stay here."
                    : $"Garmoth could not load that spot ({outcome.Error}). Your items stay here.";
                if (attempt != 0 || !IsExactNumericSpotDestination(destination, requestedSpotId) ||
                    !IsTransientSpotResponse(outcome.HttpStatus, outcome.Error))
                    throw new InvalidOperationException(failure);
                var barrier = JsonNode.Parse(await core.ExecuteScriptAsync(RetryBarrierObservation).WaitAsync(cancellation));
                cancellation.ThrowIfCancellationRequested();
                if (barrier?["blocked"]?.GetValue<bool>() != false || core.Source != destination || !ReferenceEquals(_window, window))
                    throw new InvalidOperationException(failure + " Review the page before trying again.");
                TracePreparation("destination_retry_wait", traceStarted, new JsonObject
                {
                    ["httpStatusCode"] = outcome.HttpStatus, ["webErrorStatus"] = outcome.Error.ToString(), ["attempt"] = 1
                });
                window.SetStatus("Garmoth returned a temporary server error. Retrying this spot once…");
                await Task.Delay(500, cancellation);
                cancellation.ThrowIfCancellationRequested();
                if (core.Source != destination || !ReferenceEquals(_window, window) || window.IsConnectionClosed)
                    throw new OperationCanceledException("The Garmoth connection changed before its retry.");
            }
        }
        finally
        {
            core.NavigationCompleted -= Completed;
            _expectedNavigation = null;
            _expectedNavigationId = null;
        }
    }

    private async Task<JsonObject> ReadStatusAsync(TimeSpan timeout)
    {
        var window = _window;
        try
        {
            if (_forgetting is not null)
                return ConnectionStatusResponse(window?.Core is not null, "maintenance", false);
            if (_backgroundLoginRequired)
                return ConnectionStatusResponse(window?.Core is not null, "login_required", false, BackgroundLoginMessage);
            if (_dialogReviewRequired)
                return ConnectionStatusResponse(window?.Core is not null, "browser_open", false, DialogReviewMessage);
            if (window?.Core is null)
                return ConnectionStatusResponse(false, _opening is null ? "not_open" : "loading", false);
            if (_activeOperation is not null)
                return ConnectionStatusResponse(true, "browser_open", false, "A session operation is already running.");
            var core = window.Core;
            var source = core.Source;
            if (!IsGarmothPage(source))
                return ConnectionStatusResponse(true, "browser_open", false);
            using var cancellation = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
            cancellation.CancelAfter(timeout);
            // Unlike the draft helper, this origin-scoped script only observes
            // visible page controls and is safe on public/non-editor pages.
            var json = await core.ExecuteScriptAsync(EmbeddedGarmothScripts.ConnectionStatus()).WaitAsync(cancellation.Token);
            cancellation.Token.ThrowIfCancellationRequested();
            if (!ReferenceEquals(_window, window) || window.Core is null)
                return ConnectionStatusResponse(false, "not_open", false);
            if (window.Core.Source != source)
                return ConnectionStatusResponse(true, "loading", false);
            var result = JsonNode.Parse(json) as JsonObject;
            var canPrepare = result?["canPrepare"]?.GetValue<bool>() == true && GarmothNavigationPolicy.IsTrackerUrl(source);
            var state = result?["state"]?.GetValue<string>();
            return ConnectionStatusResponse(true, canPrepare ? "tracker_ready"
                : state is "login_required" or "loading" ? state : "browser_open", canPrepare);
        }
        catch
        {
            var connected = ReferenceEquals(_window, window) && window?.Core is not null;
            return ConnectionStatusResponse(connected, connected ? "browser_open" : "not_open", false,
                connected ? "The page could not be checked. Open Garmoth to review it." : null);
        }
    }

    private static bool IsGarmothPage(string? source) =>
        Uri.TryCreate(source, UriKind.Absolute, out var uri) && uri.Scheme == Uri.UriSchemeHttps &&
        uri.IsDefaultPort && uri.Host == "garmoth.com" && string.IsNullOrEmpty(uri.UserInfo);

    internal static JsonObject ConnectionStatusResponse(bool connected, string state, bool canPrepare, string? message = null)
    {
        var response = Success("status", null);
        response["connected"] = connected;
        response["state"] = state;
        response["canPrepare"] = canPrepare;
        response["ok"] = canPrepare;
        response["message"] = message ?? state switch
        {
            "not_open" => "Open Garmoth to connect.",
            "loading" => "Garmoth is loading.",
            "login_required" => "Sign in to Garmoth, then open your session tracker.",
            "tracker_ready" => "Garmoth is ready to prepare your session.",
            "maintenance" => "The Garmoth connection is being forgotten.",
            _ => "Garmoth is open. Open your session tracker and Add session form to prepare.",
        };
        return response;
    }

    private JsonObject WithRememberedPreference(JsonObject response)
    {
        response["remembered"] = _preferences.RememberConnection;
        return response;
    }

    private static async Task<JsonObject?> ExecuteAsync(GarmothBrowserWindow window, string script, CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        if (window.Core is null || !GarmothNavigationPolicy.IsTrackerUrl(window.Core.Source))
            throw new InvalidOperationException("Garmoth navigated away from the Grind Tracker.");
        var json = await window.Core.ExecuteScriptAsync(script).WaitAsync(cancellation);
        cancellation.ThrowIfCancellationRequested();
        return JsonNode.Parse(json) as JsonObject;
    }

    public Task ForgetAsync()
    {
        if (_forgetting is not null) return _forgetting;
        var completion = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var cancellation = new CancellationTokenSource();
        _forgetCancellation = cancellation;
        _forgetting = completion.Task;
        _ = CompleteForgetAsync(completion, cancellation);
        return completion.Task;
    }

    private async Task CompleteForgetAsync(TaskCompletionSource<bool> completion, CancellationTokenSource cancellation)
    {
        try
        {
            await ForgetCoreAsync(cancellation.Token);
            completion.TrySetResult(true);
        }
        catch (OperationCanceledException) { completion.TrySetCanceled(cancellation.Token); }
        catch (Exception error) { completion.TrySetException(error); }
        finally
        {
            _forgetting = null;
            _forgetCancellation = null;
            cancellation.Dispose();
        }
    }

    private async Task ForgetCoreAsync(CancellationToken cancellation)
    {
        _preferences.SetRememberConnection(false);
        _pendingPreparation?.Cancel();
        _activeOperation?.Cancel();
        await _operation.WaitAsync(cancellation);
        GarmothBrowserWindow? maintenanceWindow = null;
        var owner = _window?.Owner;
        try
        {
            cancellation.ThrowIfCancellationRequested();
            CloseWindows();
            _lifetime.Dispose();
            _lifetime = new CancellationTokenSource();
            var window = CreateWindow(owner, remembered: false, maintenance: true);
            maintenanceWindow = window;
            _window = window;
            window.SetStatus("Forgetting this device's Garmoth connection…");
            window.Show();
            var environment = await CreateEnvironmentAsync(cancellation);
            cancellation.ThrowIfCancellationRequested();
            _environment = environment;
            // Clear the persistent profile, even when the last session used InPrivate.
            await window.InitializeBrowserAsync(environment, ControllerOptions(environment, remember: true)).WaitAsync(cancellation);
            cancellation.ThrowIfCancellationRequested();
            Configure(window, main: true);
            await window.Core!.Profile.ClearBrowsingDataAsync(CoreWebView2BrowsingDataKinds.AllProfile).WaitAsync(cancellation);
            cancellation.ThrowIfCancellationRequested();
            CloseWindows();
            ShowPrivateIntro(owner, "Connection forgotten on this device.");
        }
        catch
        {
            if (ReferenceEquals(_window, maintenanceWindow))
            {
                CloseWindows();
                if (!cancellation.IsCancellationRequested)
                    ShowPrivateIntro(owner, "The connection could not be forgotten. Try Forget connection again.");
            }
            cancellation.ThrowIfCancellationRequested();
            throw;
        }
        finally { _operation.Release(); }
    }

    private void ShowPrivateIntro(Window? owner, string status)
    {
        _lifetime.Dispose();
        _lifetime = new CancellationTokenSource();
        var intro = CreateWindow(owner, remembered: false);
        _window = intro;
        intro.SetStatus(status);
        intro.Show();
    }

    public Task CloseAsync()
    {
        _forgetCancellation?.Cancel();
        CloseWindows();
        return Task.CompletedTask;
    }

    private void CloseWindows()
    {
        _lifecycle++;
        _activeOperation?.Cancel();
        _lifetime.Cancel();
        CloseChildren();
        var window = _window;
        _window = null;
        if (window?.IsConnectionClosed == false) window.Close();
        _environment = null;
        _preparedDraftId = null;
        _expectedNavigation = null;
        _expectedNavigationId = null;
        _documentNavigationId = null;
        _documentLoading = false;
        _backgroundOperationWindow = null;
        _backgroundLoginRequired = false;
        _dialogReviewRequired = false;
    }

    private void CloseChildren()
    {
        foreach (var child in _children.ToArray())
            if (!child.IsConnectionClosed) child.Close();
        _children.Clear();
    }

    public void OpenSetup() => _ = OpenAsync(Application.Current?.MainWindow);
    public void CopyExtensionPath() => throw new NotSupportedException("The embedded connection does not need an add-on.");

    private static JsonObject Success(string? type, string? draftId) => new()
    {
        ["type"] = type == "prepare" ? "prepareResult" : type == "review" ? "reviewResult" : "statusResult",
        ["protocolVersion"] = SessionImportProtocol.Version,
        ["ok"] = true, ["draftId"] = draftId, ["matched"] = 0, ["skipped"] = new JsonArray(),
    };
    private static JsonObject Failure(string? type, string? draftId, string message)
    {
        var result = Success(type, draftId);
        result["ok"] = false;
        result["message"] = message;
        return result;
    }
}
