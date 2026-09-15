using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace BlackSpiritLife.SessionImport.SummaryOcr;

/// <summary>
/// WPF-friendly client for the small native Windows OCR helper.
/// The stream overload keeps pasted screenshots in memory.
/// </summary>
public sealed class IqonSummaryOcr : ISummaryOcrReader
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly string _helperPath;

    public IqonSummaryOcr(string? helperPath = null)
    {
        _helperPath = Path.GetFullPath(
            helperPath ?? Path.Combine(AppContext.BaseDirectory, "SummaryOcrNative.exe"));
    }

    public async Task<SummaryOcrResult> ReadAsync(
        string imagePath,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(imagePath);
        var fullPath = Path.GetFullPath(imagePath);
        if (!File.Exists(fullPath))
        {
            throw new FileNotFoundException("The summary screenshot was not found.", fullPath);
        }

        return await RunHelperAsync([fullPath], standardInput: null, cancellationToken);
    }

    public async Task<SummaryOcrResult> ReadAsync(
        Stream imageStream,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(imageStream);
        if (!imageStream.CanRead)
        {
            throw new ArgumentException("The image stream must be readable.", nameof(imageStream));
        }

        using var memory = new MemoryStream();
        await imageStream.CopyToAsync(memory, cancellationToken);
        var encoded = Convert.ToBase64String(memory.GetBuffer(), 0, checked((int)memory.Length));
        return await RunHelperAsync(["--stdin-base64"], encoded, cancellationToken);
    }

    private async Task<SummaryOcrResult> RunHelperAsync(
        IReadOnlyList<string> arguments,
        string? standardInput,
        CancellationToken cancellationToken)
    {
        if (!File.Exists(_helperPath))
        {
            throw new FileNotFoundException(
                "The native summary OCR helper was not found. Build native/build.ps1 and package SummaryOcrNative.exe beside the app.",
                _helperPath);
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = _helperPath,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = standardInput is not null,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("The native summary OCR helper could not be started.");
        var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);

        if (standardInput is not null)
        {
            await process.StandardInput.WriteAsync(standardInput.AsMemory(), cancellationToken);
            process.StandardInput.Close();
        }

        try
        {
            await process.WaitForExitAsync(cancellationToken);
        }
        catch (OperationCanceledException)
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
            throw;
        }

        var output = await outputTask;
        var error = await errorTask;
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(
                string.IsNullOrWhiteSpace(error)
                    ? $"Summary OCR failed with exit code {process.ExitCode}."
                    : error.Trim());
        }

        return JsonSerializer.Deserialize<SummaryOcrResult>(output, JsonOptions)
            ?? throw new InvalidOperationException("Summary OCR returned no result.");
    }
}
