using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using BlackSpiritLife.SessionImport.App;
using BlackSpiritLife.SessionImport.SummaryOcr;

internal sealed record ScreenshotRow(string Name, long Quantity, string? ItemId = null);
internal sealed record ScreenshotMetadata(string Duration, bool Agris, decimal? Rate, decimal? Amount);
internal sealed record ScreenshotCase(string Id, string? SpotId, string? Activity, IReadOnlyList<ScreenshotRow> Rows,
    ScreenshotMetadata? Metadata = null, bool Synthetic = true, IReadOnlyList<string>? NotesItemNames = null);

// Test-only input images: actual catalog names, deliberately invented counts.
// Images contain no destination name, activity, ID or metadata hint.
internal static class SyntheticScreenshotCases
{
    internal static readonly IReadOnlyList<ScreenshotCase> All =
    [
        new("loopy-defaults", "56", "gathering", [new("Loopy Tree Sap", 12345, "5018"), new("Dead Tree Essence", 76, "5019"), new("Old Tree Branch", 4321, "4613")]),
        new("elephant-defaults", "204", "hunting", [new("Rock Elephant Meat", 6789, "7962"), new("Rock Elephant Blood", 2345, "6359"), new("Rock Elephant Tusk", 17, "767256")]),
        new("orc-defaults", "17", "grinding", [new("Oily Orange Mushroom", 45678, "44482"), new("Heart of the Arid Forest", 9, "8135"), new("Shard of the Furious Night", 234, "8145")]),
        new("tungrad-defaults", "148", "grinding", [new("Tungrad Ruins Fragment", 23456, "65328"), new("Tungrad Ruins Paint", 8, "761724"), new("Embers of Resonance", 123, "65318")]),
        new("orc-explicit-metadata", "17", "grinding", [new("Oily Orange Mushroom", 34567, "44482"), new("Heart of the Arid Forest", 7, "8135"), new("Shard of the Furious Night", 156, "8145")], new("00:15", true, 100m, 50m)),
        new("common-only-ambiguous", null, null, [new("Caphras Stone", 5678, "721003")])
    ];

    internal static ScreenshotCase Get(string id) => All.SingleOrDefault(value => value.Id == id)
        ?? throw new ArgumentException("Unknown explicit screenshot case.", nameof(id));

    internal static void Generate(string outputDirectory)
    {
        FreshDirectory(outputDirectory);
        var cases = new JsonArray();
        foreach (var value in All)
        {
            var path = Path.Combine(outputDirectory, value.Id + ".png");
            Render(value, path);
            cases.Add(new JsonObject
            {
                ["caseId"] = value.Id, ["imageFile"] = Path.GetFileName(path),
                ["imageSha256"] = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))),
                ["expectedSpotId"] = value.SpotId, ["expectedActivity"] = value.Activity,
                ["expectedRows"] = JsonSerializer.SerializeToNode(value.Rows),
                ["explicitSyntheticMetadata"] = JsonSerializer.SerializeToNode(value.Metadata)
            });
        }
        File.WriteAllText(Path.Combine(outputDirectory, "synthetic-screenshot-manifest.json"), new JsonObject
        {
            ["schemaVersion"] = 1,
            ["purpose"] = "Code-native synthetic OCR input, not real sessions or natural-drop ratios. Destination/metadata are not rendered in the PNG. No browser is opened by generation.",
            ["cases"] = cases
        }.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    internal static async Task VerifyOfflineAsync(string imageDirectory, string helperPath, string outputDirectory)
    {
        FreshDirectory(outputDirectory);
        ScreenshotNotesVerifierChecks.Run((name, action) => { action(); Check(true, name); });
        var results = new JsonArray();
        using var cancellation = new CancellationTokenSource(TimeSpan.FromMinutes(3));
        foreach (var value in All)
        {
            var browser = new ManagedBrowserFixture { Ready = true };
            var window = new MainWindow(browser, monitorConnection: false,
                firefoxFactory: () => throw new InvalidOperationException("Firefox is outside the offline fixture."));
            var result = new JsonObject { ["caseId"] = value.Id, ["status"] = "pending", ["browserTransport"] = "in-memory fixture; no WebView or network" };
            results.Add(result);
            try
            {
                var imagePath = Path.Combine(imageDirectory, value.Id + ".png");
                var ocr = await LiveScreenshotPreparationChecks.ReadAndReviewAsync(window, imagePath, helperPath, cancellation.Token);
                Check(LiveScreenshotPreparationChecks.OcrRowsMatch(ocr, value), "actual native OCR names and grouped quantities: " + value.Id);
                Check(LiveScreenshotPreparationChecks.ExpectedRows(window, value), "native review retains exact names, IDs and quantities: " + value.Id);
                LiveScreenshotPreparationChecks.AssertAutomaticSpot(window, value);
                Check(true, "automatic spot or ambiguity without manual rescue: " + value.Id);
                LiveScreenshotPreparationChecks.ApplyMetadata(window, value);
                var prepare = LiveScreenshotPreparationChecks.Control<Button>(window, "PrepareButton");
                prepare.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                await Dispatcher.Yield(DispatcherPriority.Background);
                while (!prepare.IsEnabled) await Task.Delay(20, cancellation.Token);
                if (value.SpotId is null)
                    Check(browser.Requests.Count == 0 && browser.LastDraft is null,
                        "common-only ambiguity blocks the ordinary Prepare before any browser request");
                else
                {
                    Check(browser.Requests.Count(type => type == "prepare") == 1 && browser.LastDraft is not null,
                        "one ordinary Prepare emits exactly one draft: " + value.Id);
                    LiveScreenshotPreparationChecks.AssertDraft(value, browser.LastDraft!);
                    Check(true, "draft destination, quantities and default/explicit metadata: " + value.Id);
                }
                Check(!window.IsLoaded && !window.IsVisible && !window.IsActive && browser.OpenCount == 0,
                    "offline screenshot workflow never shows a native or browser window: " + value.Id);
                result["ocrRows"] = JsonSerializer.SerializeToNode(ocr.Rows);
                result["prepareCalls"] = browser.Requests.Count(type => type == "prepare");
                result["sentDraft"] = browser.LastDraft?.DeepClone();
                result["status"] = "passed";
            }
            catch (Exception error)
            {
                result["status"] = "failed"; result["exceptionType"] = error.GetType().Name;
                throw;
            }
            finally
            {
                window.Close();
                await File.WriteAllTextAsync(Path.Combine(outputDirectory, "offline-screenshot-results.json"),
                    results.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            }
        }
    }

    private static void Render(ScreenshotCase value, string path)
    {
        const int width = 1280;
        var height = 138 + value.Rows.Count * 72;
        var visual = new DrawingVisual();
        using (var drawing = visual.RenderOpen())
        {
            drawing.DrawRectangle(new SolidColorBrush(Color.FromRgb(23, 26, 31)), null, new Rect(0, 0, width, height));
            Text(drawing, "ITEM", 38, 24, 22, Colors.LightGray);
            Text(drawing, "COUNT", 1050, 24, 22, Colors.LightGray);
            for (var index = 0; index < value.Rows.Count; index++)
            {
                var y = 70 + index * 72;
                drawing.DrawLine(new Pen(new SolidColorBrush(Color.FromRgb(48, 52, 59)), 1), new Point(30, y - 10), new Point(1248, y - 10));
                Text(drawing, value.Rows[index].Name, 38, y, 32, Colors.WhiteSmoke);
                Text(drawing, value.Rows[index].Quantity.ToString("N0", CultureInfo.InvariantCulture), 1050, y, 32, Colors.WhiteSmoke);
            }
            Text(drawing, "SYNTHETIC OCR FIXTURE - NOT A REAL SESSION", 38, height - 42, 16, Colors.LightGray);
        }
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path);
        encoder.Save(stream);
    }

    private static void Text(DrawingContext drawing, string text, double x, double y, double size, Color color) =>
        drawing.DrawText(new FormattedText(text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
            new Typeface("Segoe UI"), size, new SolidColorBrush(color), 1), new Point(x, y));

    private static void FreshDirectory(string path)
    {
        if (Directory.Exists(path) && Directory.EnumerateFileSystemEntries(path).Any())
            throw new InvalidOperationException("Use a fresh evidence directory; existing evidence is preserved.");
        Directory.CreateDirectory(path);
    }
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
        Console.WriteLine("PASS " + message);
    }
}
