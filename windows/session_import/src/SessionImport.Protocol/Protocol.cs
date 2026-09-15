using System.Buffers.Binary;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BlackSpiritLife.SessionImport;

public static class SessionImportProtocol
{
    public const int Version = 1;
    public const int MaximumMessageBytes = 64 * 1024;
    public const string PipeName = "blackspiritlife.session_import.trial.v1";
    public const string NativeHostName = "com.blackspiritlife.session_import.trial";
    public const string FirefoxExtensionId = "session-import-trial@blackspirit.life";
}

public static class FramedJson
{
    public static async Task<JsonObject?> ReadAsync(
        Stream source,
        CancellationToken cancellationToken = default)
    {
        var lengthBytes = new byte[4];
        var first = await source.ReadAsync(lengthBytes.AsMemory(0, 1), cancellationToken);
        if (first == 0) return null;
        await ReadExactlyAsync(source, lengthBytes.AsMemory(1), cancellationToken);

        var length = BinaryPrimitives.ReadUInt32LittleEndian(lengthBytes);
        if (length == 0 || length > SessionImportProtocol.MaximumMessageBytes)
        {
            throw new InvalidDataException("The browser helper message has an invalid size.");
        }

        var payload = new byte[length];
        await ReadExactlyAsync(source, payload, cancellationToken);
        try
        {
            return JsonNode.Parse(payload) as JsonObject
                ?? throw new InvalidDataException("The browser helper message must be a JSON object.");
        }
        catch (JsonException error)
        {
            throw new InvalidDataException("The browser helper sent invalid JSON.", error);
        }
    }

    public static async Task WriteAsync(
        Stream destination,
        JsonObject message,
        CancellationToken cancellationToken = default)
    {
        var payload = Encoding.UTF8.GetBytes(message.ToJsonString(
            new JsonSerializerOptions { WriteIndented = false }));
        if (payload.Length == 0 || payload.Length > SessionImportProtocol.MaximumMessageBytes)
        {
            throw new InvalidDataException("The browser helper message is too large.");
        }

        var lengthBytes = new byte[4];
        BinaryPrimitives.WriteUInt32LittleEndian(lengthBytes, (uint)payload.Length);
        await destination.WriteAsync(lengthBytes, cancellationToken);
        await destination.WriteAsync(payload, cancellationToken);
        await destination.FlushAsync(cancellationToken);
    }

    private static async Task ReadExactlyAsync(
        Stream source,
        Memory<byte> destination,
        CancellationToken cancellationToken)
    {
        var read = 0;
        while (read < destination.Length)
        {
            var count = await source.ReadAsync(destination[read..], cancellationToken);
            if (count == 0) throw new EndOfStreamException("The browser helper message ended early.");
            read += count;
        }
    }
}

public sealed record SessionItem(
    string? ItemId,
    int SubKey,
    string Name,
    long Quantity);

public sealed record SessionDraft(
    string DraftId,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset ExpiresAtUtc,
    string SpotId,
    string SpotName,
    string Activity,
    int DurationSeconds,
    IReadOnlyList<SessionItem> Items,
    long? AgrisUsed = null,
    decimal? AdditionalDropRate = null,
    decimal? AdditionalDropAmount = null,
    bool? AgrisActive = null)
{
    public JsonObject ToPrepareMessage() => new()
    {
        ["type"] = "prepare",
        ["protocolVersion"] = SessionImportProtocol.Version,
        ["draft"] = new JsonObject
        {
            ["schemaVersion"] = 1,
            ["draftId"] = DraftId,
            ["createdAtUtc"] = CreatedAtUtc.ToString("O"),
            ["expiresAtUtc"] = ExpiresAtUtc.ToString("O"),
            ["target"] = new JsonObject
            {
                ["provider"] = "garmoth",
                ["spotId"] = SpotId,
                ["spotName"] = SpotName,
                ["activity"] = Activity,
            },
            ["session"] = SessionToJson(),
            ["behavior"] = new JsonObject
            {
                ["skipUnsupported"] = true,
                ["submit"] = false,
            },
        },
    };

    private JsonObject SessionToJson()
    {
        var session = new JsonObject
        {
            ["durationSeconds"] = DurationSeconds,
            ["items"] = new JsonArray(Items.Select(item => new JsonObject
            {
                ["itemId"] = item.ItemId,
                ["subKey"] = item.SubKey,
                ["name"] = item.Name,
                ["quantity"] = item.Quantity,
            }).ToArray<JsonNode?>()),
        };
        if (AgrisUsed is long agris) session["agrisUsed"] = agris;
        if (AgrisActive is bool active) session["agrisActive"] = active;
        if (AdditionalDropRate is decimal rate) session["additionalDropRate"] = rate;
        if (AdditionalDropAmount is decimal amount) session["additionalDropAmount"] = amount;
        return session;
    }
}
