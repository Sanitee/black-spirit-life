using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using BlackSpiritLife.SessionImport.SummaryOcr;
using Microsoft.Win32;

namespace BlackSpiritLife.SessionImport.App;

public partial class MainWindow : Window
{
    private readonly IqonSummaryOcr _summaryOcr = new();
    private readonly ItemCatalog _catalog = ItemCatalog.Load();
    private readonly SpotCatalog _spots = SpotCatalog.Load();
    private RegistrationResult _registration;
    private ISessionImportBrowser _browser;
    private readonly IAppManagedSessionImportBrowser? _managedBrowser;
    private readonly Func<ISessionImportBrowser> _firefoxFactory;
    private ISessionImportBrowser? _firefoxBrowser;
    private readonly DispatcherTimer _browserMonitor = new() { Interval = TimeSpan.FromSeconds(2) };
    private readonly HashSet<LootRowViewModel> _observedLootRows = [];
    private string? _preparedDraftId;
    private string? _preparedSummary;
    private bool _preparedNeedsReview;
    private readonly Func<bool> _autoReviewAllowed;
    private readonly ISessionHistoryReceiptWriter? _historyWriter;
    private readonly Dictionary<string, SessionHistoryReceipt> _pendingHistoryReceipts = [];
    private string _importId = Guid.NewGuid().ToString("N");
    private DateTimeOffset _importedAtUtc = DateTimeOffset.UtcNow;
    private int _importRevision;
    private string? _suggestedSpotName;
    private Task<bool>? _browserStatusTask;
    private bool _browserReady;
    private string _browserState = "not_open";
    private bool _showingConnectionGuidance;
    private bool _busy;
    private bool _closed;
    private bool _closing;
    private bool UsesManagedBrowser => _browser is IAppManagedSessionImportBrowser;
    private string BrowserName => UsesManagedBrowser ? "Garmoth" : "Firefox";

    public ObservableCollection<LootRowViewModel> LootRows { get; } = [];

    public MainWindow() : this(new EmbeddedGarmothBrowser(
            GarmothConnectionPreferences.FromCommandLine(Environment.GetCommandLineArgs().Skip(1))),
        historyWriter: SessionHistoryReceiptWriter.FromCommandLine(Environment.GetCommandLineArgs().Skip(1))) { }

    internal MainWindow(ISessionImportBrowser browser, bool monitorConnection = true,
        Func<ISessionImportBrowser>? firefoxFactory = null, Func<bool>? autoReviewAllowed = null,
        ISessionHistoryReceiptWriter? historyWriter = null)
    {
        _browser = browser;
        _managedBrowser = browser as IAppManagedSessionImportBrowser;
        _firefoxFactory = firefoxFactory ?? (() => new FirefoxBrowser());
        _autoReviewAllowed = autoReviewAllowed ?? (() => IsVisible && IsActive && WindowState != WindowState.Minimized);
        _historyWriter = historyWriter;
        _registration = browser.Registration;
        InitializeComponent();
        InitializeSessionDetails();
        DataContext = this;
        SpotBox.ItemsSource = _spots.Search(string.Empty);
        SpotBox.SelectedIndex = -1;
        SpotBox.Text = string.Empty;
        LootRows.CollectionChanged += LootRows_CollectionChanged;
        DurationBox.TextChanged += DraftInputChanged;
        SpotBox.AddHandler(System.Windows.Controls.TextBox.TextChangedEvent,
            new System.Windows.Controls.TextChangedEventHandler(DraftInputChanged));
        StatusText.Text = _registration.Registered
            ? "Screenshots are read locally and not saved."
            : _registration.Message;
        SetupOpenButton.IsEnabled = _registration.Registered;
        SetupCopyButton.IsEnabled = _registration.Registered;
        UpdateConnectionHelp();
        ApplyBrowserStatus(false);
        Closing += async (_, e) =>
        {
            if (_closed || _managedBrowser is null) return;
            e.Cancel = true;
            if (_closing) return;
            _closing = true;
            _browserMonitor.Stop();
            SetBusy(true, "Closing Garmoth…");
            try { await _managedBrowser.CloseAsync(); }
            catch (Exception failure)
            {
                _closing = false;
                SetBusy(false);
                SetStatus(failure.Message, error: true);
                return;
            }
            _closed = true;
            // CloseAsync may complete synchronously; let this Closing event exit
            // before asking WPF to close the window for the second time.
            _ = Dispatcher.BeginInvoke(new Action(Close));
        };
        if (!monitorConnection) return;
        Loaded += async (_, _) =>
        {
            EnableDarkTitleBar();
            await RefreshBrowserStatusAsync();
            if (!_closed) _browserMonitor.Start();
        };
        _browserMonitor.Tick += async (_, _) =>
        {
            if (!_busy && !_closed && (IsActive || SetupPanel.Visibility == Visibility.Visible))
                await RefreshBrowserStatusAsync();
        };
        Activated += async (_, _) =>
        {
            if (!_busy && !_closed) await RefreshBrowserStatusAsync();
        };
        Closed += (_, _) =>
        {
            _closed = true;
            _browserMonitor.Stop();
        };
    }

    private async void PasteButton_Click(object sender, RoutedEventArgs e)
    {
        if (!Clipboard.ContainsImage())
        {
            SetStatus("Copy an IQON summary screenshot first.", error: true);
            return;
        }

        var bitmap = Clipboard.GetImage();
        if (bitmap is null)
        {
            SetStatus("The clipboard image could not be read.", error: true);
            return;
        }

        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        await using var memory = new MemoryStream();
        encoder.Save(memory);
        memory.Position = 0;
        await ReadScreenshotAsync(() => _summaryOcr.ReadAsync(memory));
    }

    private async void OpenButton_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "Open session screenshot",
            Filter = "Screenshots|*.png;*.jpg;*.jpeg;*.bmp|All files|*.*",
            CheckFileExists = true,
        };
        if (dialog.ShowDialog(this) == true)
            await ReadScreenshotAsync(() => _summaryOcr.ReadAsync(dialog.FileName));
    }

    private async Task ReadScreenshotAsync(Func<Task<SummaryOcrResult>> read)
    {
        SetBusy(true, "Reading screenshot…");
        try
        {
            var result = await read();
            LootRows.Clear();
            foreach (var row in result.Rows)
            {
                // The wider spot catalog can identify loot absent from the
                // original artwork catalog. Never fuzzy-rename an exact item.
                var sourceItem = _spots.MatchItem(row.ItemName);
                var match = sourceItem is null
                    ? _catalog.Match(row.ItemName)
                    : _catalog.MatchExact(sourceItem.Name);
                LootRows.Add(new LootRowViewModel(
                    sourceItem?.Name ?? match?.Name ?? row.ItemName,
                    row.Count,
                    sourceItem?.Id ?? match?.ItemId,
                    match?.IconPath));
            }
            if (LootRows.Count == 0)
            {
                SetStatus("No item and count rows were found.", error: true);
                return;
            }
            var resolution = ApplySafeSpotSuggestion(result.Rows.Select(row => new SpotLootItem(row.ItemName, Quantity: row.Count)));
            ShowReview();
            SetStatus(resolution.NeedsChoice
                ? $"{LootRows.Count} items found. Choose the matching spot."
                : resolution.IsHeuristicSuggestion
                    ? $"{LootRows.Count} items found. Check the suggested spot before preparing."
                : $"{LootRows.Count} items found. Check them before sending.");
        }
        catch (Exception error)
        {
            SetStatus(error.Message, error: true);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void ShowReview()
    {
        _importId = Guid.NewGuid().ToString("N");
        _importedAtUtc = DateTimeOffset.UtcNow;
        _importRevision = 0;
        EmptyPanel.Visibility = Visibility.Collapsed;
        ReviewPanel.Visibility = Visibility.Visible;
        PrepareButton.Visibility = Visibility.Visible;
        AddItemButton.Visibility = Visibility.Visible;
        ResetPreparedAction();
    }

    private SpotResolution ApplySafeSpotSuggestion(IEnumerable<SpotLootItem> items)
    {
        // Resolve raw OCR names, not a fuzzy-corrected item identity. Related
        // locations stay available; common drops cannot prove a single spot.
        var resolution = new SpotResolver(_spots).Resolve(items);
        var ranked = resolution.Candidates.Select(candidate => candidate.Spot).ToArray();
        SpotBox.ItemsSource = ranked.Concat(_spots.Search(string.Empty))
            .DistinctBy(spot => spot.Id).ToArray();
        SpotBox.SelectedItem = resolution.Suggested;
        SpotBox.Text = resolution.Suggested?.Name ?? string.Empty;
        _suggestedSpotName = resolution.Suggested?.Name;
        SpotLabel.Text = "Spot";
        return resolution;
    }

    private void ResetButton_Click(object sender, RoutedEventArgs e)
    {
        LootRows.Clear();
        EmptyPanel.Visibility = Visibility.Visible;
        ReviewPanel.Visibility = Visibility.Collapsed;
        PrepareButton.Visibility = Visibility.Collapsed;
        AddItemButton.Visibility = Visibility.Collapsed;
        ResetPreparedAction();
        _suggestedSpotName = null;
        SpotBox.SelectedIndex = -1;
        SpotBox.Text = string.Empty;
        SpotLabel.Text = "Spot";
        SetStatus("Screenshots are read locally and not saved.");
    }

    private void AddItemButton_Click(object sender, RoutedEventArgs e) =>
        LootRows.Add(new LootRowViewModel("Item name", 0));

    private void RemoveLootButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: LootRowViewModel row }) LootRows.Remove(row);
    }

    private void LootRows_CollectionChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        foreach (var row in _observedLootRows.Where(row => !LootRows.Contains(row)).ToArray())
        {
            row.PropertyChanged -= LootRow_PropertyChanged;
            _observedLootRows.Remove(row);
        }
        foreach (var row in LootRows.Where(row => _observedLootRows.Add(row)))
        {
            row.PropertyChanged += LootRow_PropertyChanged;
        }
        InvalidatePreparedDraft();
        InvalidateAutomaticSpot();
    }

    private void LootRow_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        InvalidatePreparedDraft();
        if (e.PropertyName == nameof(LootRowViewModel.Name)) InvalidateAutomaticSpot();
    }

    private void InvalidateAutomaticSpot()
    {
        // Corrected identities can invalidate the loot-based suggestion. An
        // explicitly chosen spot remains the user's choice; never replace it.
        if (_suggestedSpotName is null) return;
        _suggestedSpotName = null;
        SpotBox.SelectedIndex = -1;
        SpotBox.Text = string.Empty;
        if (!_busy) SetStatus("Loot changed · choose the matching spot.");
    }

    private void DraftInputChanged(object sender, System.Windows.Controls.TextChangedEventArgs e)
    {
        if (_suggestedSpotName is not null &&
            !string.Equals(SpotBox.Text.Trim(), _suggestedSpotName, StringComparison.OrdinalIgnoreCase))
        {
            _suggestedSpotName = null;
            SpotLabel.Text = "Spot";
        }
        InvalidatePreparedDraft();
    }

    private void InvalidatePreparedDraft()
    {
        if (_preparedDraftId is null) return;
        ResetPreparedAction();
        SetStatus("Changed · send again to update the Garmoth inputs.");
    }

    private void ResetPreparedAction()
    {
        _preparedDraftId = null;
        _preparedSummary = null;
        _preparedNeedsReview = false;
        UpdateSessionAction();
    }

    private void UpdateSessionAction() =>
        PrepareButton.Content = _preparedDraftId is null ? "Send to Garmoth" : "Review inputs";

    private async void PrepareButton_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        if (_preparedDraftId is not null)
        {
            SetBusy(true);
            try { await ReviewPreparedInputsAsync(); }
            finally { SetBusy(false); }
            return;
        }
        if (!TryBuildDraft(out var draft, out var error))
        {
            SetStatus(error, error: true);
            return;
        }
        ResetPreparedAction();
        SetBusy(true, $"Checking {BrowserName}…");
        try
        {
            var ready = await RefreshBrowserStatusAsync();
            if (_closed || _closing) return;
            if (!ready && UsesManagedBrowser && _browserState == "login_required")
            {
                SetStatus("Use Garmoth login at the top right, then send again. Your items stay here.", error: true);
                return;
            }
            if (!ready && !UsesManagedBrowser)
            {
                ShowConnectionSetup();
                SetStatus(_registration.Registered
                    ? $"Connect {BrowserName} before preparing this session. Your items stay here."
                    : _registration.Message, error: true);
                return;
            }
            SetStatus("Sending to Garmoth…");
            if (!ready && _browser is IAppManagedSessionImportBrowser managed)
                await managed.OpenForPreparationAsync(this);
            if (_closed || _closing) return;
            var response = await _browser.SendAsync(draft!.ToPrepareMessage(), TimeSpan.FromSeconds(45));
            if (_closed || _closing) return;
            if (!IsSuccessfulDraftResponse(response, "prepareResult", draft.DraftId, out var responseError))
                throw new InvalidOperationException(responseError);
            var matched = response["matched"]?.GetValue<int>() ?? 0;
            if (matched < 1) throw new InvalidOperationException("No loot was entered in Garmoth. Your items stay here.");
            _preparedDraftId = draft.DraftId;
            var skipped = response["skipped"] is JsonArray skippedRows ? skippedRows.Count : 0;
            var noted = PreparedNotes.VerifiedIndices(response, (JsonArray)draft.ToPrepareMessage()["draft"]!["session"]!["items"]!);
            var notEntered = skipped - noted.Count;
            var warnings = (response["warnings"] as JsonArray)?.Select(value => value?.GetValue<string>())
                .Where(value => !string.IsNullOrWhiteSpace(value)).Select(PreparationWarning).Distinct().ToArray();
            var needsReview = warnings?.Length > 0;
            SetStatus(notEntered == 0
                ? needsReview ? $"Check session details · {matched} items entered" : $"Ready in Garmoth · {matched} items"
                : $"Incomplete · {matched} entered · {notEntered} not entered in Garmoth", error: notEntered > 0 || needsReview);
            if (noted.Count > 0)
                SetStatus(StatusText.Text + $" · {noted.Count} in Notes (not included in totals)", error: notEntered > 0 || needsReview);
            if (response["skipped"] is JsonArray missingRows && notEntered > 0)
            {
                var missingNames = missingRows.Select(row => row?["index"] is JsonValue indexValue && indexValue.TryGetValue<int>(out var index)
                        && index >= 0 && index < draft.Items.Count && !noted.Contains(index) ? draft.Items[index].Name : null)
                    .Where(name => name is not null).Distinct().ToArray();
                if (missingNames.Length > 0)
                    SetStatus(StatusText.Text + ": " + string.Join(", ", missingNames.Take(3))
                        + (missingNames.Length > 3 ? $" (+{missingNames.Length - 3} more)" : string.Empty), error: true);
            }
            if (needsReview) SetStatus(StatusText.Text + " · " + string.Join(" · ", warnings!), error: true);
            _preparedSummary = StatusText.Text;
            _preparedNeedsReview = notEntered > 0 || needsReview;
            UpdateSessionAction();
            if (_historyWriter is not null)
            {
                var selectedSpot = _spots.Entries.SingleOrDefault(spot => spot.GarmothSpotId == draft.SpotId);
                _pendingHistoryReceipts[_importId] = new SessionHistoryReceipt(_importId, ++_importRevision, _importedAtUtc, draft,
                    selectedSpot?.MethodIds ?? [], selectedSpot?.LinkedSourceIds ?? [], matched, noted.Count, skipped);
                await QueueLocalSessionAsync();
            }
            // Finish in the background if the user has returned to their game.
            // The managed browser rechecks the owner immediately before revealing.
            if (UsesManagedBrowser && _autoReviewAllowed())
                await ReviewPreparedInputsAsync(automatic: true);
        }
        catch (Exception failure)
        {
            SetStatus(failure.Message, error: true);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private bool TryBuildDraft(out SessionDraft? draft, out string error)
    {
        draft = null;
        error = string.Empty;
        if (!TryGetSessionDetails(out var details, out error)) return false;

        var spotName = SpotBox.Text.Trim();
        var selected = SpotBox.SelectedItem as SpotDefinition;
        if (selected is null || !selected.NavigationNames.Any(name => SpotCatalog.Normalize(name) == SpotCatalog.Normalize(spotName)))
        {
            var exactSpots = _spots.FindByName(spotName);
            selected = exactSpots.Count == 1 ? exactSpots[0] : null;
        }
        if (string.IsNullOrWhiteSpace(spotName))
        {
            error = "Choose or type the Garmoth spot.";
            return false;
        }
        if (selected is null)
        {
            error = "Choose a matching spot from the list so its activity is known.";
            return false;
        }

        var items = new List<SessionItem>();
        foreach (var row in LootRows)
        {
            if (!IntegerInput.TryParseGrouped(row.Quantity, out var quantity) || quantity < 1)
            {
                error = $"Check the amount for {row.Name}.";
                return false;
            }
            var match = _catalog.MatchExact(row.Name);
            var sourceItem = _spots.MatchItem(row.Name);
            row.ItemId = match?.ItemId ?? sourceItem?.Id;
            row.IconPath = match?.IconPath;
            items.Add(new SessionItem(match?.ItemId ?? sourceItem?.Id, 0, match?.Name ?? sourceItem?.Name ?? row.Name.Trim(), quantity));
        }
        if (items.Count == 0)
        {
            error = "Add at least one item.";
            return false;
        }

        var now = DateTimeOffset.UtcNow;
        draft = new SessionDraft(
            Guid.NewGuid().ToString("N"),
            now,
            now.AddMinutes(10),
            selected.GarmothSpotId ?? string.Empty,
            selected.Name,
            selected.Activity,
            details!.DurationSeconds,
            items,
            AgrisActive: details.AgrisActive,
            AdditionalDropRate: details.AdditionalDropRate,
            AdditionalDropAmount: details.AdditionalDropAmount);
        return true;
    }

    private static string PreparationWarning(string? warning) => warning switch
    {
        "agris_toggle_not_found" or "agris_toggle_not_accepted" or "agris_field_not_found" or "agris_field_not_accepted"
            => "Check Agris in Garmoth.",
        "additional_drop_rate_field_not_found" or "additional_drop_rate_field_not_accepted"
            => "Check additional drop rate in Garmoth.",
        "additional_drop_amount_field_not_found" or "additional_drop_amount_field_not_accepted"
            => "Check additional drop amount in Garmoth.",
        "mastery_field_not_found" => "Check mastery in Garmoth.",
        "energy_field_not_found" => "Check energy in Garmoth.",
        "duration_rounded_to_minutes" => "Garmoth uses whole minutes; check the duration.",
        "unsupported_notes_not_found" or "unsupported_notes_not_accepted" => "Missing items could not be added to Notes.",
        "unsupported_notes_conflict" => "Notes were edited; check the missing items in Garmoth.",
        "unsupported_notes_too_long" => "Missing items exceed Garmoth's Notes limit.",
        "item_values_not_accepted" => "Some loot amounts changed in Garmoth; check those items.",
        _ => "Check the session details in Garmoth.",
    };

    private async Task ReviewPreparedInputsAsync(bool automatic = false)
    {
        var draftId = _preparedDraftId;
        if (draftId is null || _closed || _closing) return;
        if (!automatic) await QueueLocalSessionAsync();
        if (_closed || _closing) return;
        SetStatus("Opening Garmoth…");
        try
        {
            var response = await _browser.SendAsync(new JsonObject
            {
                ["type"] = "review",
                ["protocolVersion"] = SessionImportProtocol.Version,
                ["draftId"] = draftId,
                ["revealIfOwnerActive"] = automatic,
            }, TimeSpan.FromSeconds(5));
            if (_closed || _closing) return;
            if (!IsSuccessfulDraftResponse(response, "reviewResult", draftId, out var responseError))
            {
                if (IsMatchingDraftResponse(response, "reviewResult", draftId) &&
                    response["preparedFormMissing"] is JsonValue missing && missing.TryGetValue<bool>(out var isMissing) && isMissing)
                    ResetPreparedAction();
                throw new InvalidOperationException(responseError);
            }
            // Opening the form must not erase missing-loot or metadata warnings.
            ShowPreparedSummary();
        }
        catch (Exception error)
        {
            var detail = _preparedSummary is null ? string.Empty : _preparedSummary + " · ";
            SetStatus(detail + error.Message, error: true);
        }
    }

    private async Task QueueLocalSessionAsync()
    {
        if (_pendingHistoryReceipts.Count == 0 || _historyWriter is null) return;
        try
        {
            foreach (var receipt in _pendingHistoryReceipts.Values.ToArray())
            {
                await _historyWriter.WriteAsync(receipt);
                _pendingHistoryReceipts.Remove(receipt.ImportId);
            }
        }
        catch
        {
            // Retain the exact receipt for Review to retry. Garmoth preparation
            // remains usable; a local disk problem must not cause a second send.
        }
        ShowPreparedSummary();
    }

    private void ShowPreparedSummary() => SetStatus(
        (_preparedSummary ?? "Review the inputs in Garmoth before saving.") +
        (_pendingHistoryReceipts.Count == 0 ? string.Empty : " · Local history could not be updated. Review inputs retries."),
        error: _preparedNeedsReview || _pendingHistoryReceipts.Count > 0);

    private async void FirefoxSetupButton_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        if (UsesManagedBrowser)
        {
            await OpenManagedBrowserAsync();
            return;
        }
        var ready = await RefreshBrowserStatusAsync();
        if (_busy || _closed) return;
        if (ready)
        {
            SetStatus("Firefox connected. You can prepare this session in Garmoth.");
            return;
        }
        ShowConnectionSetup();
    }

    private void ShowConnectionSetup()
    {
        UpdateConnectionHelp();
        // The built-in browser owns sign-in. Do not consume the loot area with
        // a second connection panel or turn the session action into a login.
        SetupPanel.Visibility = UsesManagedBrowser ? Visibility.Collapsed : Visibility.Visible;
        SetupStatusText.Text = _registration.Registered
            ? string.Empty
            : _registration.Message;
    }

    private void UpdateConnectionHelp()
    {
        FirefoxHelp.Visibility = UsesManagedBrowser ? Visibility.Collapsed : Visibility.Visible;
        SwitchBrowserButton.Visibility = _managedBrowser is null ? Visibility.Collapsed : Visibility.Visible;
        SwitchBrowserButton.Content = UsesManagedBrowser ? "Use Firefox instead" : "Use built-in connection";
        SwitchBrowserMenuItem.Visibility = SwitchBrowserButton.Visibility;
        SwitchBrowserMenuItem.Header = SwitchBrowserButton.Content;
        SetupOpenButton.IsEnabled = _registration.Registered;
        SetupCopyButton.IsEnabled = _registration.Registered;
    }

    private async Task OpenManagedBrowserAsync()
    {
        if (_browser is not IAppManagedSessionImportBrowser managed) return;
        SetBusy(true, "Opening Garmoth…");
        try
        {
            await managed.OpenAsync(this);
            if (_closed) return;
            var ready = await RefreshBrowserStatusAsync();
            if (_closed || _closing) return;
            SetStatus(ready
                ? "Garmoth is ready. You can prepare your session."
                : _browserState switch
                {
                    "login_required" => "Sign in inside the Garmoth window. Your items stay here.",
                    "not_open" => "Open Garmoth using the top-right button. Your items stay here.",
                    "loading" => "Garmoth is loading. Your items stay here.",
                    "maintenance" => "Garmoth is clearing its saved connection. Your items stay here.",
                    _ => "Open your spot in Garmoth's tracker, then prepare this session. Your items stay here.",
                });
            _showingConnectionGuidance = !ready;
        }
        catch (Exception failure)
        {
            ShowConnectionSetup();
            SetStatus(failure.Message, error: true);
        }
        finally { SetBusy(false); }
    }

    private async void SwitchBrowserButton_Click(object sender, RoutedEventArgs e)
    {
        if (_busy || _managedBrowser is null) return;
        SetBusy(true);
        try
        {
            // Finish any old status request before changing providers.
            if (_browserStatusTask is not null) await _browserStatusTask;
            if (_closed || _closing) return;
            if (UsesManagedBrowser)
            {
                await _managedBrowser.CloseAsync();
                if (_closed || _closing) return;
                _browser = _firefoxBrowser ??= _firefoxFactory();
            }
            else _browser = _managedBrowser;
            _registration = _browser.Registration;
            InvalidatePreparedDraft();
            ApplyBrowserStatus(false);
            ShowConnectionSetup();
            SetStatus($"Using {BrowserName}. Your items stay here.");
        }
        catch (Exception failure) { SetStatus(failure.Message, error: true); }
        finally { SetBusy(false); }
    }

    private void SetupCloseButton_Click(object sender, RoutedEventArgs e) =>
        SetupPanel.Visibility = Visibility.Collapsed;

    private void SetupOpenButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            _browser.OpenSetup();
            SetupStatusText.Text = "Add-on path copied. Firefox setup is open.";
        }
        catch (Exception error)
        {
            SetupStatusText.Text = error.Message;
            SetStatus(error.Message, error: true);
        }
    }

    private void SetupCopyButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            _browser.CopyExtensionPath();
            SetupStatusText.Text = "Add-on path copied.";
        }
        catch (Exception error)
        {
            SetupStatusText.Text = error.Message;
            SetStatus(error.Message, error: true);
        }
    }

    private async Task<bool> RefreshBrowserStatusAsync()
    {
        if (_browserStatusTask is not null) return await _browserStatusTask;
        var pending = CheckBrowserStatusAsync();
        _browserStatusTask = pending;
        try { return await pending; }
        finally { _browserStatusTask = null; }
    }

    private async Task<bool> CheckBrowserStatusAsync()
    {
        var ready = false;
        var state = UsesManagedBrowser ? "unknown" : "not_open";
        var connected = false;
        var remembered = false;
        try
        {
            if (!_registration.Registered) return ApplyBrowserStatus(false);
            var response = await _browser.SendAsync(new JsonObject
            {
                ["type"] = "status",
                ["protocolVersion"] = SessionImportProtocol.Version,
            }, TimeSpan.FromMilliseconds(1200));
            if (response["type"]?.GetValue<string>() == "statusResult" &&
                response["protocolVersion"]?.GetValue<int>() == SessionImportProtocol.Version)
            {
                ready = response["ok"]?.GetValue<bool>() == true;
                if (UsesManagedBrowser)
                {
                    connected = response["connected"]?.GetValue<bool>() == true;
                    state = response["state"]?.GetValue<string>() ?? (ready ? "tracker_ready" : connected ? "browser_open" : "not_open");
                    remembered = response["remembered"]?.GetValue<bool>() == true;
                }
            }
        }
        catch
        {
            // A timeout is not proof that an existing login expired.
            state = UsesManagedBrowser ? "unknown" : "not_open";
            ready = false;
        }
        return ApplyBrowserStatus(ready, state, remembered);
    }

    private bool ApplyBrowserStatus(bool ready, string state = "not_open", bool remembered = false)
    {
        if (_closed) return false;
        var justConnected = ready && !_browserReady;
        _browserReady = ready;
        _browserState = state;
        BrowserStatusText.Text = ready ? $"{BrowserName} connected"
            : !UsesManagedBrowser ? "Connect Firefox"
            : state == "loading" ? "Opening Garmoth…"
            : state == "login_required" || (state == "not_open" && !remembered) ? "Garmoth login"
            : "Open Garmoth";
        UpdateSessionAction();
        BrowserStatusDot.Fill = new System.Windows.Media.SolidColorBrush(
            ready ? System.Windows.Media.Color.FromRgb(169, 215, 136) : System.Windows.Media.Color.FromRgb(115, 128, 121));
        if (ready && SetupPanel.Visibility == Visibility.Visible)
        {
            SetupPanel.Visibility = Visibility.Collapsed;
            if (justConnected && !_busy) SetStatus($"{BrowserName} connected. Your session is ready to send.");
        }
        else if (justConnected && !_busy && _showingConnectionGuidance)
            SetStatus("Garmoth is ready. You can send your session.");
        return ready;
    }

    private void SetBusy(bool busy, string? message = null)
    {
        _busy = busy;
        PrepareButton.IsEnabled = !busy;
        FirefoxSetupButton.IsEnabled = !busy;
        AddItemButton.IsEnabled = !busy;
        EmptyPanel.IsEnabled = !busy;
        ReviewPanel.IsEnabled = !busy;
        SetupPanel.IsEnabled = !busy;
        SwitchBrowserMenuItem.IsEnabled = !busy;
        UpdateSessionDetailsControls();
        if (message is not null) SetStatus(message);
    }

    private void SetStatus(string value, bool error = false)
    {
        _showingConnectionGuidance = false;
        StatusText.Text = value;
        StatusText.Foreground = new System.Windows.Media.SolidColorBrush(error
            ? System.Windows.Media.Color.FromRgb(236, 139, 139)
            : System.Windows.Media.Color.FromRgb(167, 184, 176));
    }

    private void NumberOnly_PreviewTextInput(object sender, TextCompositionEventArgs e) =>
        e.Handled = !IntegerInput.IsAllowedInput(e.Text);

    private static bool IsMatchingDraftResponse(JsonObject response, string expectedType, string expectedDraftId) =>
        response["type"] is JsonValue type && type.TryGetValue<string>(out var typeText) && typeText == expectedType &&
        response["draftId"] is JsonValue draft && draft.TryGetValue<string>(out var draftText) && draftText == expectedDraftId &&
        (response["protocolVersion"] is null || response["protocolVersion"] is JsonValue version &&
            version.TryGetValue<int>(out var versionNumber) && versionNumber == SessionImportProtocol.Version);

    private static bool IsSuccessfulDraftResponse(
        JsonObject response,
        string expectedType,
        string expectedDraftId,
        out string error)
    {
        var type = response["type"] is JsonValue typeValue && typeValue.TryGetValue<string>(out var typeText)
            ? typeText
            : string.Empty;
        var ok = response["ok"] is JsonValue okValue
            && okValue.TryGetValue<bool>(out var okValueText)
            && okValueText;
        var draftId = response["draftId"] is JsonValue draftValue && draftValue.TryGetValue<string>(out var draftText)
            ? draftText
            : string.Empty;

        if (IsMatchingDraftResponse(response, expectedType, expectedDraftId) && ok)
        {
            error = string.Empty;
            return true;
        }

        var message = response["message"] is JsonValue messageValue && messageValue.TryGetValue<string>(out var messageText)
            ? messageText.Trim()
            : string.Empty;
        error = !string.IsNullOrWhiteSpace(message)
            ? message
            : type != expectedType
                ? "The browser returned an unexpected response."
                : !ok
                    ? "The browser could not complete the request."
                    : "The browser replied for a different session. Try again.";
        return false;
    }

    private void EnableDarkTitleBar()
    {
        var enabled = 1;
        var handle = new System.Windows.Interop.WindowInteropHelper(this).Handle;
        _ = DwmSetWindowAttribute(handle, 20, ref enabled, sizeof(int));
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);
}
