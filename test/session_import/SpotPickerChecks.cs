using System.Globalization;
using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using BlackSpiritLife.SessionImport;
using BlackSpiritLife.SessionImport.App;

internal static class SpotPickerChecks
{
    internal static void Run(Action<string, Action> run, string? outputDir = null)
    {
        var spots = SpotCatalog.Load().Entries;
        var converter = new SpotArtworkConverter();
        run("all observed spot artwork paths preserve full variant stems and decode", () =>
        {
            var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var variantCount = 0;
            foreach (var spot in spots)
            {
                var path = converter.Convert(spot, typeof(ImageSource), null!, CultureInfo.InvariantCulture) as string;
                Assert(path is not null && File.Exists(path), "missing artwork for " + spot.GarmothSpotId);
                var stem = Path.GetFileNameWithoutExtension(new Uri(spot.ArtworkUrls[0]).AbsolutePath);
                Assert(Path.GetFileName(path) == stem + ".png", "full artwork stem retained: " + stem);
                var bitmap = Decode(path!);
                Assert(bitmap.PixelWidth > 0 && bitmap.PixelHeight > 0, "valid decoded pixels for " + stem);
                paths.Add(path!);
                if (stem.Contains('_')) variantCount++;
            }
            Assert(spots.Count == 174 && paths.Count == 138 && variantCount > 0,
                $"complete observed scope: {spots.Count} spots, {paths.Count} distinct assets, {variantCount} variant references");
        });
        run("spot artwork converter never substitutes an identity for absent presentation data", () =>
        {
            Assert(converter.Convert(null!, typeof(ImageSource), null!, CultureInfo.InvariantCulture) is null, "null selection has no image");
            Assert(converter.Convert("Rusalka's Coral", typeof(ImageSource), null!, CultureInfo.InvariantCulture) is null,
                "typed text is not guessed artwork identity");
            Assert(converter.Convert(spots[0] with { ArtworkUrls = [] }, typeof(ImageSource), null!, CultureInfo.InvariantCulture) is null,
                "missing artwork remains absent");
            Assert(ReferenceEquals(converter.ConvertBack("image", typeof(object), null!, CultureInfo.InvariantCulture), Binding.DoNothing),
                "artwork cannot write back to the selected spot");
        });
        run("dark editable spot picker retains real text input and exact canonical selection", () =>
        {
            var window = CreateWindow();
            try
            {
                var picker = Control<ComboBox>(window, "SpotBox");
                var spot = picker.Items.Cast<SpotDefinition>().Single(item => item.GarmothSpotId == "186");
                picker.SelectedItem = spot;
                Layout(window, 904, 630);
                var editor = (TextBox)picker.Template.FindName("PART_EditableTextBox", picker);
                var artwork = (Image)picker.Template.FindName("SelectedArtwork", picker);
                Assert(picker.IsEditable && !picker.IsTextSearchEnabled && editor.Visibility == Visibility.Visible && !editor.IsReadOnly,
                    "native editable text remains available without ambiguous auto-selection");
                Assert(editor.Text == spot.Name && artwork.Source is BitmapSource,
                    $"selected spot has canonical name/artwork: expected={spot.Name}; editor={editor.Text}; text={picker.Text}; tag={picker.Tag}; source={artwork.Source?.GetType().Name ?? "null"}");
                Assert(ColorOf(picker.Background) == ColorOf((Brush)window.FindResource("SurfaceRaised")) &&
                    ColorOf(editor.Foreground) == ColorOf((Brush)window.FindResource("Text")) && ColorOf(editor.Background).A == 0,
                    "editable field uses the dark surface and readable inherited text without a white input rectangle");
                var draft = BuildDraft(window);
                Assert(draft["target"]?["spotId"]?.GetValue<string>() == "186" && draft["target"]?["activity"]?.GetValue<string>() == "gathering",
                    "selected image does not replace canonical destination/activity");
                Assert(!picker.IsDropDownOpen && !window.IsVisible && !window.IsActive, "template checks never show a native window or popup");
            }
            finally { window.Close(); }
        });
        run("typing and editing spot names uses the native editable text box and invalidates sent inputs", () =>
        {
            var window = CreateWindow();
            try
            {
                var picker = Control<ComboBox>(window, "SpotBox");
                Layout(window, 904, 630);
                var editor = (TextBox)picker.Template.FindName("PART_EditableTextBox", picker);
                editor.Text = "RUSALKA’S CORAL";
                DrainBindings();
                Assert(BuildDraft(window)["target"]?["spotId"]?.GetValue<string>() == "186", "typed canonical alias resolves to the same exact spot");
                typeof(MainWindow).GetField("_preparedDraftId", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(window, "old-draft");
                editor.Text = "unknown spot fixture";
                DrainBindings();
                Assert(typeof(MainWindow).GetField("_preparedDraftId", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(window) is null,
                    "editing actual input invalidates the prepared result");
                Assert((string)Control<Button>(window, "PrepareButton").Content == "Send to Garmoth", "edit restores Send rather than stale Review");
                var args = new object?[] { null, null };
                Assert(!(bool)typeof(MainWindow).GetMethod("TryBuildDraft", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(window, args)!,
                    "unrecognized edited text cannot silently send the old selected destination");
            }
            finally { window.Close(); }
        });
        run("native picker keeps editable keyboard roles and same-name destination identity", () =>
        {
            var window = CreateWindow();
            try
            {
                var picker = Control<ComboBox>(window, "SpotBox");
                picker.SelectedIndex = 0;
                Layout(window, 904, 630);
                var editor = (TextBox)picker.Template.FindName("PART_EditableTextBox", picker);
                Assert(picker.Focusable && (picker.IsTabStop || editor.IsTabStop) && editor.Focusable && !editor.IsReadOnly,
                    $"native editable picker retains one tab entry and focus/input roles: combo={picker.Focusable}/{picker.IsTabStop}; editor={editor.Focusable}/{editor.IsTabStop}/{editor.IsReadOnly}");
                var duplicate = picker.Items.Cast<SpotDefinition>().GroupBy(item => item.Name)
                    .First(group => group.Select(item => item.GarmothSpotId).Distinct().Count() > 1).ToArray();
                picker.SelectedItem = duplicate[1];
                DrainBindings();
                Assert(BuildDraft(window)["target"]?["spotId"]?.GetValue<string>() == duplicate[1].GarmothSpotId,
                    "explicit same-name method keeps the chosen canonical destination");
                Assert(!picker.IsDropDownOpen && !window.IsVisible && !window.IsActive,
                    "structural keyboard-role checks and selection require no OS input or foreground activation");
            }
            finally { window.Close(); }
        });
        run("Agris No and Yes fit the actual dark selection at 904 pixels", () =>
        {
            var window = CreateWindow();
            try
            {
                var agris = Control<ComboBox>(window, "AgrisActiveBox");
                foreach (var value in new[] { 0, 1 })
                {
                    agris.SelectedIndex = value;
                    Layout(window, 904, 630);
                    var selection = (ContentPresenter)agris.Template.FindName("Selection", agris);
                    var label = ((ComboBoxItem)agris.SelectedItem).Content.ToString()!;
                    var text = new FormattedText(label, CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
                        new Typeface(agris.FontFamily, agris.FontStyle, agris.FontWeight, agris.FontStretch), agris.FontSize, agris.Foreground, 1);
                    Assert(selection.ActualWidth >= text.WidthIncludingTrailingWhitespace && selection.ActualHeight >= text.Height,
                        $"{label} needs {text.WidthIncludingTrailingWhitespace:F1}x{text.Height:F1}, selection provides {selection.ActualWidth:F1}x{selection.ActualHeight:F1}");
                    Assert(!agris.IsDropDownOpen, "Agris popup stays closed");
                }
            }
            finally { window.Close(); }
        });
        run("actual spot popup child templates measure and render without creating a popup window", () =>
        {
            var window = CreateWindow();
            try
            {
                var picker = Control<ComboBox>(window, "SpotBox");
                picker.SelectedItem = picker.Items.Cast<SpotDefinition>().Single(item => item.GarmothSpotId == "186");
                var root = Layout(window, 904, 630);
                var popup = (Popup)picker.Template.FindName("PART_Popup", picker);
                var popupRoot = (FrameworkElement)popup.Child;
                popupRoot.Measure(new Size(420, 360));
                popupRoot.Arrange(new Rect(0, 0, popupRoot.DesiredSize.Width, popupRoot.DesiredSize.Height));
                popupRoot.UpdateLayout();
                DrainBindings();
                var itemsPresenter = Descendants(popupRoot).OfType<ItemsPresenter>().Single();
                Assert(KeyboardNavigation.GetDirectionalNavigation(itemsPresenter) == KeyboardNavigationMode.Contained,
                    "actual popup retains contained native directional navigation");
                var labels = Descendants(popupRoot).OfType<TextBlock>().Where(label => !string.IsNullOrWhiteSpace(label.Text)).ToArray();
                Assert(labels.Length > 0 && Descendants(popupRoot).OfType<Image>().Any(image => image.Source is BitmapSource),
                    "actual closed-popup child materializes spot labels and bundled images offscreen");
                Assert(!popup.IsOpen && !picker.IsDropDownOpen && !window.IsVisible && PresentationSource.FromVisual(popupRoot) is null,
                    "no native popup or visible window was created by template measurement");
                if (outputDir is not null)
                {
                    Directory.CreateDirectory(outputDir);
                    Render(root, window.Background, 904, 630, Path.Combine(outputDir, "spot-picker-closed-904.png"));
                    Render(popupRoot, window.Background, (int)Math.Ceiling(popupRoot.ActualWidth), (int)Math.Ceiling(popupRoot.ActualHeight),
                        Path.Combine(outputDir, "spot-picker-popup-child.png"));
                    File.WriteAllText(Path.Combine(outputDir, "scope.txt"),
                        "Actual production WPF templates rendered with RenderTargetBitmap only. Popup child measured directly while IsOpen=false; no native popup placement, OS keyboard input, focus, active foreground reveal, real website or saved profile was tested.");
                }
            }
            finally { window.Close(); }
        });
    }

    private static MainWindow CreateWindow()
    {
        var window = new MainWindow(new ManagedBrowserFixture { Ready = true }, monitorConnection: false);
        var item = ItemCatalog.Load().MatchExact("Rough Stone")!;
        window.LootRows.Add(new LootRowViewModel(item.Name, 1005, item.ItemId, item.IconPath));
        typeof(MainWindow).GetMethod("ShowReview", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(window, null);
        return window;
    }
    private static System.Text.Json.Nodes.JsonObject BuildDraft(MainWindow window)
    {
        var args = new object?[] { null, null };
        Assert((bool)typeof(MainWindow).GetMethod("TryBuildDraft", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(window, args)!,
            "draft must build: " + args[1]);
        return (System.Text.Json.Nodes.JsonObject)((SessionDraft)args[0]!).ToPrepareMessage()["draft"]!;
    }
    private static T Control<T>(MainWindow window, string name) where T : FrameworkElement => (T)window.FindName(name);
    private static Color ColorOf(Brush brush) => ((SolidColorBrush)brush).Color;
    private static BitmapFrame Decode(string path)
    {
        using var stream = File.OpenRead(path);
        return BitmapFrame.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
    }
    private static void DrainBindings() => Dispatcher.CurrentDispatcher.Invoke(() => { }, DispatcherPriority.ContextIdle);
    private static FrameworkElement Layout(MainWindow window, int width, int height)
    {
        var root = (FrameworkElement)window.Content;
        root.Measure(new Size(width, height)); root.Arrange(new Rect(0, 0, width, height)); root.UpdateLayout(); DrainBindings();
        return root;
    }
    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            yield return child;
            foreach (var nested in Descendants(child)) yield return nested;
        }
    }
    private static void Render(FrameworkElement root, Brush background, int width, int height, string path)
    {
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        var canvas = new DrawingVisual();
        using (var context = canvas.RenderOpen()) context.DrawRectangle(background, null, new Rect(0, 0, width, height));
        bitmap.Render(canvas); bitmap.Render(root);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path); encoder.Save(stream);
    }
    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
