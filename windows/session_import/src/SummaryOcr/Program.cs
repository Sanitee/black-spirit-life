using System.Text.Json;
using BlackSpiritLife.SessionImport.SummaryOcr;

if (args.Length == 0 || args[0] is "-h" or "--help")
{
    Console.WriteLine("Usage: SummaryOcr <image-path>|--stdin-base64 [--json] [--raw]");
    return args.Length == 0 ? 2 : 0;
}

try
{
    var reader = new IqonSummaryOcr();
    SummaryOcrResult result;
    if (args[0].Equals("--stdin-base64", StringComparison.OrdinalIgnoreCase))
    {
        var bytes = Convert.FromBase64String(await Console.In.ReadToEndAsync());
        using var stream = new MemoryStream(bytes, writable: false);
        result = await reader.ReadAsync(stream);
    }
    else
    {
        result = await reader.ReadAsync(args[0]);
    }
    if (args.Contains("--json", StringComparer.OrdinalIgnoreCase))
    {
        Console.WriteLine(JsonSerializer.Serialize(result, new JsonSerializerOptions
        {
            WriteIndented = true
        }));
    }
    else
    {
        foreach (var row in result.Rows)
        {
            Console.WriteLine($"{row.ItemName}\t{row.Count}");
        }

        foreach (var warning in result.Warnings)
        {
            Console.Error.WriteLine($"Warning: {warning}");
        }

        if (args.Contains("--raw", StringComparer.OrdinalIgnoreCase))
        {
            Console.Error.WriteLine("--- OCR text ---");
            Console.Error.WriteLine(result.RawText);
        }
    }

    return result.Rows.Count == 0 ? 1 : 0;
}
catch (Exception exception)
{
    Console.Error.WriteLine(exception.Message);
    return 1;
}
