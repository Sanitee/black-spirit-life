using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Win32;
using BlackSpiritLife.SessionImport;

namespace BlackSpiritLife.SessionImport.App;

internal static class BrowserBridge
{
    public static async Task<JsonObject> SendAsync(JsonObject request, TimeSpan timeout)
    {
        using var cancellation = new CancellationTokenSource(timeout);
        await using var pipe = new NamedPipeClientStream(
            ".",
            SessionImportProtocol.PipeName,
            PipeDirection.InOut,
            PipeOptions.Asynchronous);
        try
        {
            await pipe.ConnectAsync(cancellation.Token);
            await FramedJson.WriteAsync(pipe, request, cancellation.Token);
            return await FramedJson.ReadAsync(pipe, cancellation.Token)
                ?? throw new IOException("The Firefox helper disconnected.");
        }
        catch (OperationCanceledException)
        {
            throw new TimeoutException("Firefox did not respond. Check its connection, then try again.");
        }
    }
}

internal interface ISessionImportBrowser
{
    RegistrationResult Registration { get; }
    Task<JsonObject> SendAsync(JsonObject request, TimeSpan timeout);
    void OpenSetup();
    void CopyExtensionPath();
}

internal interface IAppManagedSessionImportBrowser : ISessionImportBrowser
{
    Task OpenAsync(System.Windows.Window? owner = null);
    Task OpenForPreparationAsync(System.Windows.Window? owner = null);
    Task CloseAsync();
}

internal sealed class FirefoxBrowser : ISessionImportBrowser
{
    public RegistrationResult Registration { get; } = FirefoxRegistration.Ensure();

    public Task<JsonObject> SendAsync(JsonObject request, TimeSpan timeout) =>
        BrowserBridge.SendAsync(request, timeout);

    public void OpenSetup() => FirefoxRegistration.OpenSetup(Registration.ExtensionManifest);

    public void CopyExtensionPath() => FirefoxRegistration.CopyExtensionPath(Registration.ExtensionManifest);
}

internal static class FirefoxRegistration
{
    private const string RegistryPath = @"Software\Mozilla\NativeMessagingHosts\com.blackspiritlife.session_import.trial";

    public static RegistrationResult Ensure()
    {
        var host = Path.Combine(AppContext.BaseDirectory, "browser_helper", "BlackSpiritSessionImportHost.exe");
        var extension = Path.Combine(AppContext.BaseDirectory, "browser_extension", "tracker_helper", "manifest.json");
        if (!File.Exists(host)) return new(false, extension, "The native browser helper is missing from this build.");
        if (!File.Exists(extension)) return new(false, extension, "The Firefox add-on is missing from this build.");

        try
        {
            RegisterHost(host);
            return new(true, extension, "Firefox bridge registered.");
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            return new(false, extension, "The Firefox bridge could not be registered. Check access to the app's local files and try again.");
        }
    }

    private static void RegisterHost(string host)
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            SessionImportProtocol.LocalDataDirectoryName,
            "Session Import",
            "browser_helper");
        Directory.CreateDirectory(directory);
        var manifest = Path.Combine(directory, $"{SessionImportProtocol.NativeHostName}.json");
        var payload = new JsonObject
        {
            ["name"] = SessionImportProtocol.NativeHostName,
            ["description"] = "Black Spirit Life Session Import bridge",
            ["path"] = host,
            ["type"] = "stdio",
            ["allowed_extensions"] = new JsonArray(SessionImportProtocol.FirefoxExtensionId),
        };
        File.WriteAllText(manifest, payload.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        using var key = Registry.CurrentUser.CreateSubKey(RegistryPath, writable: true);
        if (key is null) throw new IOException("The Firefox native host registration could not be opened.");
        key.SetValue(string.Empty, manifest, RegistryValueKind.String);
    }

    public static void OpenSetup(string extensionManifest)
    {
        var firefox = FindFirefox() ?? throw new FileNotFoundException(
            "Firefox was not found. Install Firefox, then reopen Session Import.");
        CopyExtensionPath(extensionManifest);
        var start = new ProcessStartInfo(firefox) { UseShellExecute = true };
        start.ArgumentList.Add("-new-tab");
        start.ArgumentList.Add("about:debugging#/runtime/this-firefox");
        Process.Start(start);
    }

    public static void CopyExtensionPath(string extensionManifest)
    {
        if (!File.Exists(extensionManifest))
            throw new FileNotFoundException("The Firefox add-on is missing from this build.");
        System.Windows.Clipboard.SetText(extensionManifest);
    }

    private static string? FindFirefox()
    {
        foreach (var hive in new[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine })
        {
            foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
            {
                try
                {
                    using var root = RegistryKey.OpenBaseKey(hive, view);
                    using var key = root.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe");
                    var registered = (key?.GetValue(string.Empty) as string)?.Trim().Trim('"');
                    if (!string.IsNullOrWhiteSpace(registered) && File.Exists(registered)) return registered;
                }
                catch (Exception error) when (error is UnauthorizedAccessException or System.Security.SecurityException)
                {
                    // Standard install locations remain available without registry access.
                }
            }
        }

        foreach (var folder in new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        })
        {
            var candidate = Path.Combine(folder, "Mozilla Firefox", "firefox.exe");
            if (File.Exists(candidate)) return candidate;
        }
        return null;
    }
}

internal sealed record RegistrationResult(bool Registered, string ExtensionManifest, string Message);
