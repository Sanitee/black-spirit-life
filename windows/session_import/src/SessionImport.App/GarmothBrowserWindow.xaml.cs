using System.Windows;
using System.Runtime.InteropServices;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace BlackSpiritLife.SessionImport.App;

public partial class GarmothBrowserWindow : Window
{
    internal WebView2? Browser { get; private set; }
    internal CoreWebView2? Core => Browser?.CoreWebView2;
    internal event Action<bool>? OpenRequested;
    internal event Action? ForgetRequested;
    internal bool IsConnectionClosed { get; private set; }
    internal bool IsBackgroundPreparation { get; private set; }
    private Window? _revealOwner;
    private bool _initializing;
    private bool _maintenance;
    private readonly bool _authentication;

    internal GarmothBrowserWindow(bool remembered, bool authentication = false, bool canForget = false, bool maintenance = false)
    {
        InitializeComponent();
        _authentication = authentication;
        RememberBox.IsChecked = remembered;
        ForgetButton.Visibility = (remembered || canForget) && !authentication ? Visibility.Visible : Visibility.Collapsed;
        if (authentication)
        {
            Title = "Sign in · Garmoth";
            ConnectionPanel.Visibility = Visibility.Collapsed;
        }
        SetMaintenance(maintenance);
        Closed += (_, _) =>
        {
            IsConnectionClosed = true;
            Browser?.Dispose();
            Browser = null;
        };
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var enabled = 1;
        var handle = new System.Windows.Interop.WindowInteropHelper(this).Handle;
        _ = DwmSetWindowAttribute(handle, 20, ref enabled, sizeof(int));
        if (IsBackgroundPreparation) SetNoActivateStyle(true);
    }

    internal void ConfigureForBackground(Window? revealOwner)
    {
        if (IsLoaded) throw new InvalidOperationException("Background placement must be configured before showing a new connection.");
        _revealOwner = revealOwner;
        IsBackgroundPreparation = true;
        ShowActivated = false;
        ShowInTaskbar = false;
        Topmost = false;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Left = -32000;
        Top = -32000;
    }

    internal bool TryShowForUserIfOwnerActive()
    {
        // Recheck the real importer at the reveal boundary, after the host's
        // asynchronous form validation. Deferral must leave placement and the
        // no-activation style untouched so gameplay cannot be interrupted.
        var owner = Owner ?? _revealOwner;
        if (!Dispatcher.CheckAccess() || IsConnectionClosed || _maintenance ||
            owner is null || !owner.IsVisible || !owner.IsActive || owner.WindowState == WindowState.Minimized)
            return false;
        ShowForUser(owner);
        return true;
    }

    internal void ShowForUser(Window? owner = null)
    {
        if (IsConnectionClosed) throw new InvalidOperationException("The Garmoth connection was closed.");
        if (IsBackgroundPreparation)
        {
            var centerOwner = owner ?? _revealOwner;
            if (centerOwner?.IsLoaded == true && centerOwner.WindowState != WindowState.Minimized)
            {
                Owner = centerOwner;
                Left = centerOwner.Left + (centerOwner.ActualWidth - Width) / 2;
                Top = centerOwner.Top + (centerOwner.ActualHeight - Height) / 2;
            }
            else
            {
                var area = SystemParameters.WorkArea;
                Left = area.Left + (area.Width - Width) / 2;
                Top = area.Top + (area.Height - Height) / 2;
            }
            IsBackgroundPreparation = false;
            _revealOwner = null;
            ShowInTaskbar = true;
            ShowActivated = true;
            SetNoActivateStyle(false);
        }
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Show();
        Activate();
    }

    private void SetNoActivateStyle(bool value)
    {
        var handle = new System.Windows.Interop.WindowInteropHelper(this).Handle;
        if (handle == IntPtr.Zero) return;
        const int extendedStyle = -20;
        const long noActivate = 0x08000000;
        var style = GetWindowLongPtr(handle, extendedStyle).ToInt64();
        SetWindowLongPtr(handle, extendedStyle, new IntPtr(value ? style | noActivate : style & ~noActivate));
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr(IntPtr handle, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern IntPtr SetWindowLongPtr(IntPtr handle, int index, IntPtr value);

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);

    internal async Task InitializeBrowserAsync(CoreWebView2Environment environment, CoreWebView2ControllerOptions options)
    {
        if (IsConnectionClosed) throw new InvalidOperationException("The Garmoth connection was closed.");
        if (_initializing || Browser is not null)
            throw new InvalidOperationException("This browser already has connection settings. Close it before changing profiles.");
        _initializing = true;
        OpenButton.IsEnabled = false;
        var browser = new WebView2();
        Browser = browser;
        BrowserHost.Children.Add(browser);
        BrowserHost.Visibility = Visibility.Visible;
        ConnectionPanel.Visibility = Visibility.Collapsed;
        try
        {
            await browser.EnsureCoreWebView2Async(environment, options);
            if (IsConnectionClosed) throw new InvalidOperationException("The Garmoth connection was closed.");
            if (browser.CoreWebView2.Profile.IsInPrivateModeEnabled != options.IsInPrivateModeEnabled ||
                browser.CoreWebView2.Profile.ProfileName != options.ProfileName)
                throw new InvalidOperationException("The browser did not use the requested private connection settings.");
            browser.CoreWebView2.SourceChanged += (_, _) => UpdateAddress();
            browser.CoreWebView2.HistoryChanged += (_, _) => UpdateAddress();
            browser.CoreWebView2.NavigationCompleted += (_, args) =>
            {
                UpdateAddress();
                if (!_maintenance)
                    SetStatus(args.IsSuccess ? string.Empty : "The page could not load. Reload or use the Firefox fallback in Session Import.");
            };
            ReloadButton.IsEnabled = !_maintenance;
        }
        catch
        {
            browser.Dispose();
            Browser = null;
            BrowserHost.Children.Clear();
            BrowserHost.Visibility = Visibility.Collapsed;
            ConnectionPanel.Visibility = _maintenance ? Visibility.Collapsed : Visibility.Visible;
            OpenButton.IsEnabled = !_maintenance;
            throw;
        }
        finally { _initializing = false; }
    }

    internal void SetStatus(string value) => StatusText.Text = value;

    internal bool TryShowForegroundScriptDialog(CoreWebView2ScriptDialogKind kind, string message,
        string defaultText, out string? resultText)
    {
        resultText = null;
        // The host also gates preparation and rechecks ownership after this
        // modal returns. Never reveal or activate a background connection here.
        if (!Dispatcher.CheckAccess() || IsConnectionClosed || IsBackgroundPreparation || _maintenance || !IsVisible || !IsActive)
            return false;
        switch (kind)
        {
            case CoreWebView2ScriptDialogKind.Alert:
                return MessageBox.Show(this, message, "Garmoth", MessageBoxButton.OK,
                    MessageBoxImage.Information, MessageBoxResult.OK) == MessageBoxResult.OK;
            case CoreWebView2ScriptDialogKind.Confirm:
            case CoreWebView2ScriptDialogKind.Beforeunload:
                return MessageBox.Show(this, message, "Garmoth", MessageBoxButton.OKCancel,
                    MessageBoxImage.Question, MessageBoxResult.Cancel) == MessageBoxResult.OK;
            case CoreWebView2ScriptDialogKind.Prompt:
                var prompt = new GarmothScriptPrompt(message, defaultText) { Owner = this, Icon = Icon };
                if (prompt.ShowDialog() != true) return false;
                resultText = prompt.ResultText;
                return true;
            default:
                return false;
        }
    }

    internal void SetRemembered(bool value) => ForgetButton.Visibility = value ? Visibility.Visible : Visibility.Collapsed;
    internal void SetMaintenance(bool value)
    {
        _maintenance = value;
        OpenButton.IsEnabled = !value && Browser is null;
        RememberBox.IsEnabled = !value;
        ForgetButton.IsEnabled = !value;
        ReloadButton.IsEnabled = !value && Core is not null;
        BackButton.IsEnabled = !value && Core?.CanGoBack == true;
        if (value) ConnectionPanel.Visibility = Visibility.Collapsed;
        else if (Browser is null && !_authentication) ConnectionPanel.Visibility = Visibility.Visible;
    }
    private void UpdateAddress()
    {
        var source = Core?.Source;
        HostText.Text = Uri.TryCreate(source, UriKind.Absolute, out var uri) ? uri.Host : "Garmoth connection";
        BackButton.IsEnabled = !_maintenance && Core?.CanGoBack == true;
    }
    private void Open_Click(object sender, RoutedEventArgs e)
    {
        if (!_maintenance && OpenButton.IsEnabled) OpenRequested?.Invoke(RememberBox.IsChecked == true);
    }
    private void Forget_Click(object sender, RoutedEventArgs e)
    {
        if (!_maintenance && ForgetButton.IsEnabled) ForgetRequested?.Invoke();
    }
    private void Back_Click(object sender, RoutedEventArgs e)
    {
        if (!_maintenance && Core?.CanGoBack == true) Core.GoBack();
    }
    private void Reload_Click(object sender, RoutedEventArgs e)
    {
        if (!_maintenance) Core?.Reload();
    }
}
