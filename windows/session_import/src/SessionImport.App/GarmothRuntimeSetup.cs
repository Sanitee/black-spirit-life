using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Security.Principal;
using Microsoft.Web.WebView2.Core;

namespace BlackSpiritLife.SessionImport.App;

// Called only by the explicit Open Garmoth action, never application startup.
// Microsoft documents on-demand, non-elevated /silent /install deployment:
// https://learn.microsoft.com/microsoft-edge/webview2/concepts/distribution
internal static class GarmothRuntimeSetup
{
    internal const string BootstrapperUrl = "https://go.microsoft.com/fwlink/p/?LinkId=2124703";
    private const int MaximumDownloadBytes = 10 * 1024 * 1024;
    private static readonly SemaphoreSlim SetupGate = new(1, 1);
    private static readonly TimeSpan DownloadTimeout = TimeSpan.FromMinutes(2);
    private static readonly TimeSpan InstallTimeout = TimeSpan.FromMinutes(5);
    private static Task<int>? _installation;

    internal static async Task EnsureAsync(Action<string> status, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(status);
        cancellationToken.ThrowIfCancellationRequested();
        if (RuntimeAvailable()) return;
        await SetupGate.WaitAsync(cancellationToken);
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (RuntimeAvailable()) return;
            // A previous Open may have stopped waiting, but its Microsoft installer
            // still owns its files. Never start a second installer in that case.
            if (_installation is null || _installation.IsCompleted)
            {
                using var identity = WindowsIdentity.GetCurrent();
                if (new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))
                    throw new InvalidOperationException(
                        "Browser setup needs a normal Windows session. Reopen Session Import without Run as administrator and try again.");

                status("Downloading Microsoft browser support…");
                var directory = Directory.CreateTempSubdirectory("BSLife-WebView2-").FullName;
                var installerPath = Path.Combine(directory, "MicrosoftEdgeWebview2Setup.exe");
                FileStream? verifiedFile = null;
                try
                {
                    await DownloadAsync(installerPath, cancellationToken);
                    cancellationToken.ThrowIfCancellationRequested();
                    status("Verifying Microsoft browser support…");
                    // Prevent replacement or modification between verification and
                    // execution, retaining this read-only lock until setup exits.
                    verifiedFile = new FileStream(installerPath, FileMode.Open, FileAccess.Read, FileShare.Read);
                    var fileToVerify = verifiedFile;
                    await Task.Run(() => VerifyMicrosoftSignature(installerPath, fileToVerify));
                    cancellationToken.ThrowIfCancellationRequested();
                    status("Installing Microsoft browser support…");
                    cancellationToken.ThrowIfCancellationRequested();
                    var process = Process.Start(CreateInstallStartInfo(installerPath))
                        ?? throw new InvalidOperationException("Microsoft browser setup could not start. Try opening Garmoth again.");
                    _installation = FinishInstallerAsync(process, verifiedFile, installerPath, directory);
                    verifiedFile = null; // The completion task now owns the file lock and cleanup.
                }
                catch (Win32Exception error)
                {
                    throw new InvalidOperationException(
                        "Windows could not start Microsoft browser setup. Check your Windows security policy and try again.", error);
                }
                finally
                {
                    if (verifiedFile is not null)
                    {
                        verifiedFile.Dispose();
                        CleanupDownload(installerPath, directory);
                    }
                    else if (_installation is null || _installation.IsCompleted)
                    {
                        CleanupDownload(installerPath, directory);
                    }
                }
            }
            else
            {
                status("Microsoft browser setup is still finishing…");
            }

            int exitCode;
            try
            {
                // Once launched, cancellation must not terminate a shared system
                // installer. Bound our wait; keep observing/cleaning it afterward.
                exitCode = await _installation!.WaitAsync(InstallTimeout);
            }
            catch (TimeoutException error)
            {
                throw new InvalidOperationException(
                    "Microsoft browser setup is still running; it has not been stopped. Try opening Garmoth again shortly.", error);
            }
            cancellationToken.ThrowIfCancellationRequested();
            for (var attempt = 0; attempt < 10; attempt++)
            {
                if (RuntimeAvailable()) return;
                await Task.Delay(TimeSpan.FromMilliseconds(500), cancellationToken);
            }
            throw new InvalidOperationException(
                $"Microsoft browser setup finished (code {exitCode}), but the runtime is not available. Check your connection or Windows installation policy, then try again.");
        }
        catch (UnauthorizedAccessException error)
        {
            throw new InvalidOperationException(
                "Windows blocked access to browser setup's temporary files. Check your Windows security policy and try again.", error);
        }
        catch (IOException error)
        {
            throw new InvalidOperationException(
                "Browser setup could not access its temporary files. Check available disk space and try again.", error);
        }
        finally
        {
            SetupGate.Release();
        }
    }

    private static bool RuntimeAvailable()
    {
        try
        {
            var version = CoreWebView2Environment.GetAvailableBrowserVersionString(null,
                new CoreWebView2EnvironmentOptions { ReleaseChannels = CoreWebView2ReleaseChannels.Stable });
            if (IsEvergreenVersion(version)) return true;
            // A machine override may select an Edge preview channel. Installing
            // repeatedly cannot repair that configuration, so fail explicitly.
            throw new InvalidOperationException(
                "Windows has overridden the browser runtime with an unsupported version. Restore the WebView2 Evergreen setting before opening Garmoth.");
        }
        catch (WebView2RuntimeNotFoundException)
        {
            return false;
        }
        catch (Exception error) when (error is DllNotFoundException or BadImageFormatException)
        {
            throw new InvalidOperationException(
                "Session Import's browser component is missing or damaged. Reinstall the application; no browser setup was started.", error);
        }
    }

    internal static bool IsEvergreenVersion(string? version) =>
        Version.TryParse(version, out var parsed) && parsed > new Version(0, 0, 0, 0);

    internal static bool IsAllowedDownloadUri(Uri? uri) =>
        uri is { IsAbsoluteUri: true } && uri.Scheme == Uri.UriSchemeHttps && uri.IsDefaultPort &&
        string.IsNullOrEmpty(uri.UserInfo) && string.IsNullOrEmpty(uri.Fragment) &&
        (uri.AbsoluteUri == BootstrapperUrl ||
         (uri.Host == "msedge.sf.dl.delivery.mp.microsoft.com" &&
          uri.AbsolutePath.StartsWith("/filestreamingservice/files/", StringComparison.Ordinal) &&
          uri.AbsolutePath.EndsWith("/MicrosoftEdgeWebview2Setup.exe", StringComparison.Ordinal) &&
          string.IsNullOrEmpty(uri.Query)));

    internal static bool IsTrustedMicrosoftPublisher(int trustResult, string? publisher) =>
        trustResult == 0 && string.Equals(publisher, "Microsoft Corporation", StringComparison.Ordinal);

    internal static ProcessStartInfo CreateInstallStartInfo(string installerPath) => new(installerPath)
    {
        Arguments = "/silent /install",
        UseShellExecute = false,
        CreateNoWindow = true,
        WindowStyle = ProcessWindowStyle.Hidden,
        WorkingDirectory = Path.GetDirectoryName(installerPath)!,
    };

    private static async Task DownloadAsync(string path, CancellationToken cancellationToken)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(DownloadTimeout);
        using var handler = new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false };
        using var client = new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };
        var uri = new Uri(BootstrapperUrl);
        try
        {
            for (var redirect = 0; redirect <= 5; redirect++)
            {
                if (!IsAllowedDownloadUri(uri))
                    throw new InvalidOperationException("Microsoft browser setup returned an unexpected download address. Nothing was installed.");
                using var response = await client.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
                if (response.StatusCode is HttpStatusCode.MovedPermanently or HttpStatusCode.Redirect or
                    HttpStatusCode.SeeOther or HttpStatusCode.TemporaryRedirect or HttpStatusCode.PermanentRedirect)
                {
                    var location = response.Headers.Location
                        ?? throw new InvalidOperationException("Microsoft browser setup returned an incomplete download address. Try again later.");
                    uri = location.IsAbsoluteUri ? location : new Uri(uri, location);
                    continue;
                }
                response.EnsureSuccessStatusCode();
                if (response.Content.Headers.ContentLength is long size && (size <= 0 || size > MaximumDownloadBytes))
                    throw new InvalidOperationException("Microsoft browser setup returned an unexpected file size. Nothing was installed.");
                await using var source = await response.Content.ReadAsStreamAsync(deadline.Token);
                await using var destination = new FileStream(path, FileMode.CreateNew, FileAccess.Write,
                    FileShare.None, 81920, FileOptions.Asynchronous);
                var buffer = new byte[81920];
                var total = 0;
                int read;
                while ((read = await source.ReadAsync(buffer, deadline.Token)) != 0)
                {
                    total += read;
                    if (total > MaximumDownloadBytes)
                        throw new InvalidOperationException("Microsoft browser setup exceeded the download limit. Nothing was installed.");
                    await destination.WriteAsync(buffer.AsMemory(0, read), deadline.Token);
                }
                if (total == 0)
                    throw new InvalidOperationException("Microsoft browser setup downloaded an empty file. Try again later.");
                return;
            }
            throw new InvalidOperationException("Microsoft browser setup returned too many redirects. Nothing was installed.");
        }
        catch (OperationCanceledException error) when (!cancellationToken.IsCancellationRequested)
        {
            throw new InvalidOperationException("Microsoft browser setup download timed out. Check your connection and try again.", error);
        }
        catch (HttpRequestException error)
        {
            throw new InvalidOperationException("Microsoft browser setup could not be downloaded securely. Check your connection and try again.", error);
        }
        catch (IOException error)
        {
            throw new InvalidOperationException("Microsoft browser setup could not be saved. Check available disk space and try again.", error);
        }
    }

    private static async Task<int> FinishInstallerAsync(Process process, FileStream verifiedFile,
        string installerPath, string directory)
    {
        try
        {
            await process.WaitForExitAsync().ConfigureAwait(false);
            return process.ExitCode;
        }
        finally
        {
            process.Dispose();
            verifiedFile.Dispose();
            CleanupDownload(installerPath, directory);
        }
    }

    private static void CleanupDownload(string installerPath, string directory)
    {
        try
        {
            // These are only the exact file/directory created by this invocation.
            // Never recursively remove the temp root or installer-created files.
            File.Delete(installerPath);
            Directory.Delete(directory, recursive: false);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // Windows may still hold the installer image. Leaving only our unique
            // temporary directory is safer than force-deleting a running install.
        }
    }

    private static void VerifyMicrosoftSignature(string path, FileStream verifiedFile)
    {
        var action = new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");
        var file = new WinTrustFileInfo
        {
            Size = (uint)Marshal.SizeOf<WinTrustFileInfo>(),
            FilePath = Marshal.StringToCoTaskMemUni(path),
            FileHandle = verifiedFile.SafeFileHandle.DangerousGetHandle(),
        };
        var filePointer = Marshal.AllocHGlobal(Marshal.SizeOf<WinTrustFileInfo>());
        Marshal.StructureToPtr(file, filePointer, false);
        var data = new WinTrustData
        {
            Size = (uint)Marshal.SizeOf<WinTrustData>(),
            UiChoice = 2, // WTD_UI_NONE
            UnionChoice = 1, // WTD_CHOICE_FILE
            FileInfo = filePointer,
            StateAction = 1, // WTD_STATEACTION_VERIFY
            ProviderFlags = 0x80 | 0x2000 | 0x4000, // chain revocation (except root), reject MD2/MD4, downloaded-file policy
            UiContext = 1, // WTD_UICONTEXT_INSTALL
        };
        try
        {
            var result = WinVerifyTrust(new IntPtr(-1), ref action, ref data);
            // Trust must be exactly zero; positive warnings are NOT success.
            if (result != 0)
                throw new InvalidOperationException(
                    "Windows could not verify Microsoft browser setup's signature or certificate status. Nothing was installed. Check your connection and Windows security settings, then retry.");
            using var signedCertificate = X509Certificate.CreateFromSignedFile(path);
            using var certificate = new X509Certificate2(signedCertificate);
            if (!IsTrustedMicrosoftPublisher(result, certificate.GetNameInfo(X509NameType.SimpleName, false)))
                throw new InvalidOperationException("Browser setup was not signed by Microsoft Corporation. Nothing was installed.");
        }
        catch (CryptographicException error)
        {
            throw new InvalidOperationException("The Microsoft browser setup signature could not be read. Nothing was installed.", error);
        }
        finally
        {
            data.StateAction = 2; // WTD_STATEACTION_CLOSE is required even when verification fails.
            WinVerifyTrust(new IntPtr(-1), ref action, ref data);
            Marshal.FreeHGlobal(filePointer);
            Marshal.FreeCoTaskMem(file.FilePath);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WinTrustFileInfo
    {
        internal uint Size;
        internal IntPtr FilePath;
        internal IntPtr FileHandle;
        internal IntPtr KnownSubject;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WinTrustData
    {
        internal uint Size;
        internal IntPtr PolicyCallbackData;
        internal IntPtr SipClientData;
        internal uint UiChoice;
        internal uint RevocationChecks;
        internal uint UnionChoice;
        internal IntPtr FileInfo;
        internal uint StateAction;
        internal IntPtr StateData;
        internal IntPtr UrlReference;
        internal uint ProviderFlags;
        internal uint UiContext;
        internal IntPtr SignatureSettings;
    }

    [DllImport("wintrust.dll", ExactSpelling = true)]
    private static extern int WinVerifyTrust(IntPtr window, ref Guid action, ref WinTrustData data);
}
