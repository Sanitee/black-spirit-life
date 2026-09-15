using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using BlackSpiritLife.SessionImport;
using BlackSpiritLife.SessionImport.App;
using BlackSpiritLife.SessionImport.SummaryOcr;

internal static class SessionTimingChecks
{
    internal static void Run(Action<string, Action> run, string? evidenceDirectory = null)
    {
        run("duration accepts hours and minutes without guessing or overflowing", () =>
        {
            foreach (var (text, seconds) in new[] { ("01:00", 3600), ("1:05", 3900), ("00:01", 60), ("24:00", 86400), (" 02:30 ", 9000) })
                Assert(SessionDetailsInput.TryDuration(text, out var actual) && actual == seconds, "exact duration " + text);
            foreach (var text in new[] { "", "00:00", "60", "1", "1:5", "1:60", "24:01", "25:00", "001:00", "-1:00", "1.5:00", "01:00:30", "1e2", "NaN" })
                Assert(!SessionDetailsInput.TryDuration(text, out _), "invalid duration " + text);
        });
        run("optional percentages preserve blank and zero with strict decimal limits", () =>
        {
            Assert(SessionDetailsInput.TryOptionalPercentage(null, out var absent) && absent is null, "blank absent");
            Assert(SessionDetailsInput.TryOptionalPercentage("0", out var zero) && zero == 0, "explicit zero");
            Assert(SessionDetailsInput.TryOptionalPercentage("12,75", out var comma) && comma == 12.75m, "decimal comma");
            Assert(SessionDetailsInput.TryOptionalPercentage("10000.00", out var maximum) && maximum == 10000m, "upper bound");
            foreach (var text in new[] { "-1", "10000.01", "1.005", "NaN", "Infinity", "1e2", "25%", "1,000.00" })
                Assert(!SessionDetailsInput.TryOptionalPercentage(text, out _), "invalid percentage " + text);
        });
        run("protocol distinguishes omitted Agris from explicit No and Yes and retains legacy counts", () =>
        {
            var plain = Draft().ToPrepareMessage()["draft"]!["session"]!.AsObject();
            Assert(!plain.ContainsKey("agrisActive") && !plain.ContainsKey("agrisUsed") && !plain.ContainsKey("additionalDropRate"), "old callers omit optional fields");
            var no = (Draft() with { AgrisActive = false, AdditionalDropRate = 0 }).ToPrepareMessage();
            Assert(no["draft"]!["session"]!["agrisActive"]!.GetValue<bool>() == false, "No serialized as false");
            Assert(no["draft"]!["session"]!["additionalDropRate"]!.GetValue<decimal>() == 0, "zero rate retained");
            var yes = (Draft() with { AgrisActive = true }).ToPrepareMessage()["draft"]!["session"]!;
            Assert(yes["agrisActive"]!.GetValue<bool>() && yes["agrisUsed"] is null, "Yes does not invent points");
            var legacy = (Draft() with { AgrisUsed = 123, AdditionalDropAmount = 12.5m }).ToPrepareMessage()["draft"]!["session"]!;
            Assert(legacy["agrisUsed"]!.GetValue<long>() == 123 && legacy["agrisActive"] is null, "legacy points not reinterpreted");
            Assert(legacy["additionalDropAmount"]!.GetValue<decimal>() == 12.5m, "exact decimal");
            Assert(no["draft"]!["behavior"]!["submit"]!.GetValue<bool>() == false, "never submits");
        });
        run("single header duration is editable before screenshot and defaults to one hour", () =>
        {
            var window = Window();
            try
            {
                Assert(Control<Grid>(window, "ReviewPanel").Visibility == Visibility.Collapsed, "before screenshot");
                var duration = Control<TextBox>(window, "DurationBox");
                Assert(duration.Text == "01:00" && duration.IsEnabled && !duration.IsReadOnly, "editable one-hour default");
                Assert(AutomationProperties.GetName(duration).Contains("hours and minutes"), "duration units accessible");
                AddReview(window);
                var draft = ReadDraft(window);
                Assert(draft.DurationSeconds == 3600 && draft.AgrisActive == false && draft.AgrisUsed is null, "explicit No with no points");
                Assert(draft.AdditionalDropRate is null && draft.AdditionalDropAmount is null, "no invented percentages");
            }
            finally { Close(window); }
        });
        run("duration edits define exact minutes and invalid text blocks preparation", () =>
        {
            var window = Window();
            try
            {
                AddReview(window);
                Control<TextBox>(window, "DurationBox").Text = "02:15";
                Assert(ReadDraft(window).DurationSeconds == 8100, "two hours fifteen minutes");
                Control<TextBox>(window, "DurationBox").Text = "1:60";
                Assert(!TryReadDraft(window, out _, out var error) && error.Contains("hours:minutes"), "does not repair invalid minutes");
                Control<TextBox>(window, "DurationBox").Text = "00:01";
                Assert(ReadDraft(window).DurationSeconds == 60, "minimum minute");
                Control<TextBox>(window, "DurationBox").Text = "24:00";
                Assert(ReadDraft(window).DurationSeconds == 86400, "maximum day");
            }
            finally { Close(window); }
        });
        run("new screenshot preserves explicit duration Agris and percentages", () =>
        {
            var window = Window();
            try
            {
                AddReview(window);
                Control<TextBox>(window, "DurationBox").Text = "00:45";
                Control<ComboBox>(window, "AgrisActiveBox").SelectedIndex = 1;
                Control<TextBox>(window, "AdditionalDropRateBox").Text = "12.5";
                Control<TextBox>(window, "AdditionalDropAmountBox").Text = "0";
                Invoke(window, "ResetButton_Click", null, new RoutedEventArgs());
                AddReview(window);
                var draft = ReadDraft(window);
                Assert(draft.DurationSeconds == 2700 && draft.AgrisActive == true && draft.AdditionalDropRate == 12.5m && draft.AdditionalDropAmount == 0, "explicit fields preserved");
            }
            finally { Close(window); }
        });
        run("each duration and metadata edit invalidates a prepared draft", () =>
        {
            var window = Window();
            try
            {
                AddReview(window);
                foreach (var edit in new Action[]
                {
                    () => Control<TextBox>(window, "DurationBox").Text = "01:01",
                    () => Control<ComboBox>(window, "AgrisActiveBox").SelectedIndex = 1,
                    () => Control<ComboBox>(window, "AgrisActiveBox").SelectedIndex = 0,
                    () => Control<TextBox>(window, "AdditionalDropRateBox").Text = "0",
                    () => Control<TextBox>(window, "AdditionalDropAmountBox").Text = "1.5",
                })
                {
                    Field("_preparedDraftId").SetValue(window, "prepared-fixture");
                    Control<Button>(window, "PrepareButton").Content = "Review inputs";
                    edit();
                    Assert(Field("_preparedDraftId").GetValue(window) is null && (string)Control<Button>(window, "PrepareButton").Content == "Send to Garmoth", "changed draft no longer reviewable");
                }
            }
            finally { Close(window); }
        });
        run("invalid optional values block and No never becomes a numeric Agris count", () =>
        {
            var window = Window();
            try
            {
                AddReview(window);
                Control<TextBox>(window, "AdditionalDropRateBox").Text = "-1";
                Assert(!TryReadDraft(window, out _, out var error) && error.Contains("drop rate"), "invalid rate blocks");
                Control<TextBox>(window, "AdditionalDropRateBox").Text = "0";
                Control<TextBox>(window, "AdditionalDropAmountBox").Text = "3,25";
                var draft = ReadDraft(window);
                Assert(draft.AgrisActive == false && draft.AgrisUsed is null && draft.AdditionalDropRate == 0 && draft.AdditionalDropAmount == 3.25m, "exact entered values");
                Control<TextBox>(window, "AdditionalDropRateBox").Text = "";
                Assert(ReadDraft(window).AdditionalDropRate is null, "cleared remains absent");
                Control<ComboBox>(window, "AgrisActiveBox").SelectedIndex = -1;
                Assert(!TryReadDraft(window, out _, out var agrisError) && agrisError.Contains("Agris"), "missing selection is not guessed");
            }
            finally { Close(window); }
        });
        run("busy state protects header duration and stopwatch controls no longer exist", () =>
        {
            var window = Window();
            try
            {
                Invoke(window, "SetBusy", true, null);
                Assert(!Control<TextBox>(window, "DurationBox").IsEnabled, "header duration frozen during preparation");
                Invoke(window, "SetBusy", false, null);
                Assert(Control<TextBox>(window, "DurationBox").IsEnabled, "header duration editable afterward");
                foreach (var retired in new[] { "TimerElapsedText", "TimerToggleButton", "TimerResetButton", "TimerUseButton", "DurationSecondsText", "AgrisUsedBox", "SessionDetailsExpander" })
                    Assert(window.FindName(retired) is null, "retired control absent: " + retired);
                Assert(typeof(MainWindow).GetField("_sessionTimerDisplay", BindingFlags.NonPublic | BindingFlags.Instance) is null, "no timer lifecycle remains");
            }
            finally { Close(window); }
        });
        run("all session fields and sixteen original loot rows fit the normal 920px layout", () =>
        {
            var window = Window();
            try
            {
                AddReview(window, sixteen: true);
                var content = Layout(window, 904, 650);
                var scroll = Descendants(content).OfType<ScrollViewer>().Single(view => IsAncestor(view, Control<ItemsControl>(window, "LootItems")));
                Assert(scroll.ScrollableHeight < 1, "all sixteen items fit with all fields visible");
                var fields = new[] { "SpotBox", "AgrisActiveBox", "AdditionalDropRateBox", "AdditionalDropAmountBox" };
                var boxes = fields.Select(name => Bounds(Control<FrameworkElement>(window, name), content)).ToArray();
                Assert(boxes.All(box => box.Height >= 28 && Math.Abs(box.Top - boxes[0].Top) < 2), "one readable field row");
                Assert(boxes.Zip(boxes.Skip(1), (left, right) => left.Right <= right.Left).All(value => value), "fields do not overlap");
                Assert(boxes[^1].Right <= Bounds(Control<Button>(window, "NewScreenshotButton"), content).Left, "New screenshot remains separate");
                Assert(Control<ComboBox>(window, "SpotBox").ActualWidth == 220 && Control<TextBox>(window, "AdditionalDropRateBox").ActualWidth == 80, "fields content-sized");
                var durationBounds = Bounds(Control<TextBox>(window, "DurationBox"), content);
                Assert(durationBounds.Right <= Bounds(Control<Button>(window, "FirefoxSetupButton"), content).Left, "header fields fit");
                Assert(Control<TextBlock>(window, "SpotLabel").Text == "Spot", "no suggestion prose");
                Assert(Control<TextBlock>(window, "BrowserStatusText").Text == "Garmoth connected", "truthful local fixture state");
                if (evidenceDirectory is not null)
                {
                    Directory.CreateDirectory(evidenceDirectory);
                    Render(window, 904, 650, Path.Combine(evidenceDirectory, "session-compact-16-items-920.png"));
                    Control<ComboBox>(window, "AgrisActiveBox").SelectedIndex = 1;
                    Control<TextBox>(window, "AdditionalDropRateBox").Text = "12.5";
                    Control<TextBox>(window, "AdditionalDropAmountBox").Text = "0";
                    Render(window, 904, 650, Path.Combine(evidenceDirectory, "session-compact-values-920.png"));
                    Render(window, 1184, 820, Path.Combine(evidenceDirectory, "session-compact-values-1200.png"));
                }
            }
            finally { Close(window); }
        });
        RunProvidedScreenshot(run, evidenceDirectory);
    }

    private static void RunProvidedScreenshot(Action<string, Action> run, string? evidenceDirectory = null)
    {
        var imagePath = Environment.GetEnvironmentVariable("BSL_SESSION_IMPORT_OCR_IMAGE");
        var helperPath = Environment.GetEnvironmentVariable("BSL_SESSION_IMPORT_OCR_HELPER");
        if (string.IsNullOrWhiteSpace(imagePath) && string.IsNullOrWhiteSpace(helperPath)) return;
        run("provided real OCR screenshot imports all sixteen counts into compact session fields", () =>
        {
            Assert(File.Exists(imagePath) && File.Exists(helperPath), "explicit local OCR fixture paths exist");
            var window = Window();
            try
            {
                Control<TextBox>(window, "DurationBox").Text = "01:00";
                Func<Task<SummaryOcrResult>> read = () => new IqonSummaryOcr(helperPath).ReadAsync(imagePath!);
                var task = (Task)typeof(MainWindow).GetMethod("ReadScreenshotAsync", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(window, [read])!;
                var deadline = DateTime.UtcNow.AddSeconds(30);
                while (!task.IsCompleted && DateTime.UtcNow < deadline) Pump();
                Assert(task.IsCompleted, "local OCR completed within thirty seconds");
                task.GetAwaiter().GetResult();
                var draft = ReadDraft(window);
                var expected = new Dictionary<string, long>
                {
                    ["Rough Stone"] = 1005, ["Black Gem Fragment"] = 52, ["Sharp Black Crystal Shard"] = 8,
                    ["Lobster"] = 38, ["Fairy's Breath"] = 162, ["Caphras Stone"] = 3, ["Coral Piece"] = 413,
                    ["Fairy Powder"] = 132, ["Dim Heartvein Shard"] = 26, ["Rusalka's Coral"] = 59,
                    ["Cracked Terrashard"] = 2, ["Ancient Spirit Dust"] = 37, ["Fruit of Nature"] = 4,
                    ["Blue Coral"] = 5, ["Rough Translucent Crystal"] = 5, ["Rough Blue Crystal"] = 6,
                };
                Assert(draft.Items.Count == expected.Count, "all sixteen OCR rows imported");
                foreach (var item in draft.Items)
                    Assert(expected.TryGetValue(item.Name, out var quantity) && quantity == item.Quantity, "OCR identity and quantity " + item.Name);
                Assert(draft.SpotName == "Rusalka's Coral" && Control<TextBlock>(window, "SpotLabel").Text == "Spot", "editable identified spot without repeated prose");
                Assert(draft.DurationSeconds == 3600 && draft.AgrisActive == false && draft.AgrisUsed is null, "OCR does not infer duration or Agris");
                var content = Layout(window, 904, 650);
                var scroll = Descendants(content).OfType<ScrollViewer>().Single(view => IsAncestor(view, Control<ItemsControl>(window, "LootItems")));
                Assert(scroll.ScrollableHeight < 1, "real imported rows fit normal window");
                if (evidenceDirectory is not null)
                    Render(window, 904, 650, Path.Combine(evidenceDirectory, "session-real-ocr-920.png"));
            }
            finally { Close(window); }
        });
    }

    private static MainWindow Window()
    {
        var window = new MainWindow(new ManagedBrowserFixture { Ready = true }, monitorConnection: false);
        var refresh = (Task)typeof(MainWindow).GetMethod("RefreshBrowserStatusAsync", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(window, null)!;
        Assert(refresh.IsCompleted, "local status fixture synchronous");
        refresh.GetAwaiter().GetResult();
        return window;
    }
    private static T Control<T>(MainWindow window, string name) where T : FrameworkElement => (T)window.FindName(name);
    private static void Close(MainWindow window)
    {
        window.Close();
        Pump();
    }
    private static void Pump()
    {
        var frame = new DispatcherFrame();
        Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() => frame.Continue = false));
        Dispatcher.PushFrame(frame);
    }
    private static FieldInfo Field(string name) => typeof(MainWindow).GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!;
    private static void Invoke(MainWindow window, string name, params object?[] args) =>
        typeof(MainWindow).GetMethod(name, BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(window, args);
    private static bool TryReadDraft(MainWindow window, out SessionDraft? draft, out string error)
    {
        object?[] args = [null, string.Empty];
        var valid = (bool)typeof(MainWindow).GetMethod("TryBuildDraft", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(window, args)!;
        draft = (SessionDraft?)args[0]; error = (string)args[1]!;
        return valid;
    }
    private static SessionDraft ReadDraft(MainWindow window)
    {
        Assert(TryReadDraft(window, out var draft, out var error), error);
        return draft!;
    }
    private static SessionDraft Draft() => new("fixture", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddMinutes(10),
        "", "Rusalka's Coral", "gathering", 3600, [new SessionItem("4001", 0, "Rough Stone", 1005)]);
    private static void AddReview(MainWindow window, bool sixteen = false)
    {
        var items = sixteen ? new[]
        {
            ("Rough Stone", 1005L), ("Black Gem Fragment", 52L), ("Sharp Black Crystal Shard", 8L),
            ("Lobster", 38L), ("Fairy's Breath", 162L), ("Caphras Stone", 3L),
            ("Coral Piece", 413L), ("Fairy Powder", 132L), ("Dim Heartvein Shard", 26L),
            ("Rusalka's Coral", 59L), ("Cracked Terrashard", 2L), ("Ancient Spirit Dust", 37L),
            ("Fruit of Nature", 4L), ("Blue Coral", 5L), ("Rough Translucent Crystal", 5L), ("Rough Blue Crystal", 6L),
        } : [("Rough Stone", 1005L)];
        var catalog = ItemCatalog.Load();
        window.LootRows.Clear();
        foreach (var (name, count) in items)
        {
            var item = catalog.Match(name)!;
            window.LootRows.Add(new LootRowViewModel(item.Name, count, item.ItemId, item.IconPath));
        }
        Control<ComboBox>(window, "SpotBox").Text = "Rusalka's Coral";
        Invoke(window, "ShowReview");
    }
    private static FrameworkElement Layout(MainWindow window, int width, int height)
    {
        var content = (FrameworkElement)window.Content;
        content.Measure(new Size(width, height));
        content.Arrange(new Rect(0, 0, width, height));
        content.UpdateLayout();
        return content;
    }
    private static Rect Bounds(FrameworkElement element, Visual parent) => element.TransformToAncestor(parent).TransformBounds(new Rect(element.RenderSize));
    private static bool IsAncestor(DependencyObject parent, DependencyObject child)
    {
        for (var node = child; node is not null; node = VisualTreeHelper.GetParent(node))
            if (ReferenceEquals(node, parent)) return true;
        return false;
    }
    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            yield return child;
            foreach (var descendant in Descendants(child)) yield return descendant;
        }
    }
    private static void Render(MainWindow window, int width, int height, string path)
    {
        var content = Layout(window, width, height);
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        var canvas = new DrawingVisual();
        using (var drawing = canvas.RenderOpen()) drawing.DrawRectangle(window.Background, null, new Rect(0, 0, width, height));
        bitmap.Render(canvas); bitmap.Render(content);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path); encoder.Save(stream);
    }
    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
