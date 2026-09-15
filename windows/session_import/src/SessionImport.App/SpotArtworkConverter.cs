using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Data;

namespace BlackSpiritLife.SessionImport.App;

/// <summary>Presentation only: the observed sidebar artwork never establishes loot identity.</summary>
public sealed class SpotArtworkConverter : IValueConverter
{
    public object? Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not SpotDefinition spot || spot.ArtworkUrls.Count == 0) return null;
        var source = new Uri(spot.ArtworkUrls[0]);
        var file = Path.GetFileNameWithoutExtension(source.AbsolutePath) + ".png";
        var path = Path.Combine(AppContext.BaseDirectory, "Assets", "spot_icons", file);
        return File.Exists(path) ? path : null;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => Binding.DoNothing;
}

public sealed class SpotCategoryConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not SpotDefinition spot) return string.Empty;
        // The site's compact region labels are abbreviated. Activity is clearer
        // here; lifeskill groups distinguish same-name gathering methods.
        if (spot.Activity == "grinding") return "Grinding";
        return CultureInfo.InvariantCulture.TextInfo.ToTitleCase(
            (spot.SidebarGroup ?? spot.Activity).ToLowerInvariant());
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => Binding.DoNothing;
}
