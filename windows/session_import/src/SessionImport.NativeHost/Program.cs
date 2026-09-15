using System.IO.Pipes;
using System.Text.Json.Nodes;
using System.Threading.Channels;
using BlackSpiritLife.SessionImport;

return await NativeHost.RunAsync(args);

internal static class NativeHost
{
    public static async Task<int> RunAsync(string[] args)
    {
        if (args.Contains("--self-test", StringComparer.OrdinalIgnoreCase))
        {
            return await RunSelfTestAsync();
        }

        try
        {
            await RunBrowserSessionAsync(Console.OpenStandardInput(), Console.OpenStandardOutput());
            return 0;
        }
        catch (Exception error)
        {
            await Console.Error.WriteLineAsync($"Session Import host stopped: {error.Message}");
            return 1;
        }
    }

    private static async Task RunBrowserSessionAsync(Stream browserInput, Stream browserOutput)
    {
        var activation = await FramedJson.ReadAsync(browserInput)
            ?? throw new EndOfStreamException("The browser closed before activation.");
        if (!string.Equals(activation["type"]?.GetValue<string>(), "activate", StringComparison.Ordinal) ||
            activation["protocolVersion"]?.GetValue<int>() != SessionImportProtocol.Version)
        {
            throw new InvalidDataException("The extension and native host use different protocols.");
        }

        await FramedJson.WriteAsync(browserOutput, new JsonObject
        {
            ["type"] = "activated",
            ["protocolVersion"] = SessionImportProtocol.Version,
        });

        var browserMessages = Channel.CreateBounded<JsonObject>(new BoundedChannelOptions(4)
        {
            SingleReader = true,
            SingleWriter = true,
            FullMode = BoundedChannelFullMode.Wait,
        });
        var browserReader = PumpBrowserMessagesAsync(browserInput, browserMessages.Writer);

        while (true)
        {
            await using var pipe = new NamedPipeServerStream(
                SessionImportProtocol.PipeName,
                PipeDirection.InOut,
                1,
                PipeTransmissionMode.Byte,
                PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
            using var acceptCancellation = new CancellationTokenSource();
            var accept = pipe.WaitForConnectionAsync(acceptCancellation.Token);
            var completed = await Task.WhenAny(accept, browserReader);
            if (completed == browserReader)
            {
                acceptCancellation.Cancel();
                try { await accept; } catch (OperationCanceledException) { }
                await browserReader;
                return;
            }
            await accept;

            try
            {
                using var clientReadTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                var request = await FramedJson.ReadAsync(pipe, clientReadTimeout.Token);
                if (request is null) continue;
                var type = request["type"]?.GetValue<string>();
                if (type is not ("prepare" or "review" or "status") ||
                    request["protocolVersion"]?.GetValue<int>() != SessionImportProtocol.Version)
                {
                    await TryWriteClientAsync(pipe, Error("invalid_request", "Unsupported helper request."));
                    continue;
                }

                var requestId = request["requestId"] is JsonValue requestIdValue &&
                    requestIdValue.TryGetValue<string>(out var suppliedRequestId) &&
                    !string.IsNullOrWhiteSpace(suppliedRequestId)
                        ? suppliedRequestId
                        : Guid.NewGuid().ToString("N");
                request["requestId"] = requestId;
                await FramedJson.WriteAsync(browserOutput, request);
                JsonObject response;
                try
                {
                    response = await ReadBrowserResponseAsync(
                        browserMessages.Reader,
                        requestId,
                        type == "prepare" ? TimeSpan.FromSeconds(22) : TimeSpan.FromSeconds(4));
                }
                catch (TimeoutException)
                {
                    await TryWriteClientAsync(pipe, Error("browser_timeout", "Firefox did not answer in time."));
                    continue;
                }
                catch (ChannelClosedException)
                {
                    await browserReader;
                    return;
                }

                var expectedType = type switch
                {
                    "prepare" => "prepareResult",
                    "review" => "reviewResult",
                    _ => "statusResult",
                };
                var responseType = response["type"]?.GetValue<string>();
                if (responseType != expectedType && responseType != "error")
                {
                    await TryWriteClientAsync(pipe, Error("invalid_browser_response", "Firefox returned an unexpected response."));
                    continue;
                }
                await TryWriteClientAsync(pipe, response);
            }
            catch (Exception error) when (IsClientFailure(error))
            {
                // A desktop request may time out or disconnect. Keep the browser host alive
                // so the next status/prepare request can reuse the active extension port.
            }
        }
    }

    private static async Task PumpBrowserMessagesAsync(
        Stream browserInput,
        ChannelWriter<JsonObject> destination)
    {
        try
        {
            while (true)
            {
                var message = await FramedJson.ReadAsync(browserInput);
                if (message is null) break;
                await destination.WriteAsync(message);
            }
            destination.TryComplete();
        }
        catch (Exception error)
        {
            destination.TryComplete(error);
            throw;
        }
    }

    private static async Task<JsonObject> ReadBrowserResponseAsync(
        ChannelReader<JsonObject> source,
        string requestId,
        TimeSpan timeout)
    {
        using var cancellation = new CancellationTokenSource(timeout);
        try
        {
            while (true)
            {
                var response = await source.ReadAsync(cancellation.Token);
                if (response["requestId"] is JsonValue responseId &&
                    responseId.TryGetValue<string>(out var value) &&
                    string.Equals(value, requestId, StringComparison.Ordinal))
                {
                    return response;
                }
            }
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
            throw new TimeoutException("Firefox did not answer in time.");
        }
    }

    private static async Task TryWriteClientAsync(Stream pipe, JsonObject response)
    {
        try
        {
            await FramedJson.WriteAsync(pipe, response);
        }
        catch (Exception error) when (IsClientFailure(error))
        {
            // The app may have reached its own shorter timeout; this is not a browser failure.
        }
    }

    private static bool IsClientFailure(Exception error) =>
        error is IOException or EndOfStreamException or InvalidDataException or
            InvalidOperationException or OperationCanceledException;

    private static JsonObject Error(string code, string message) => new()
    {
        ["type"] = "error",
        ["code"] = code,
        ["message"] = message,
    };

    private static async Task<int> RunSelfTestAsync()
    {
        var message = new JsonObject { ["type"] = "status", ["value"] = "ready" };
        await using var stream = new MemoryStream();
        await FramedJson.WriteAsync(stream, message);
        stream.Position = 0;
        var decoded = await FramedJson.ReadAsync(stream);
        if (decoded?["value"]?.GetValue<string>() != "ready") return 1;
        Console.WriteLine("Native host framing self-test passed.");
        return 0;
    }
}
