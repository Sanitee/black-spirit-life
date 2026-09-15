using System.Text.Json;
using System.Text.RegularExpressions;
using System.IO;

namespace BlackSpiritLife.SessionImport.App;

internal sealed partial class ItemCatalog
{
    private readonly IReadOnlyList<CatalogItem> _items;

    private ItemCatalog(IReadOnlyList<CatalogItem> items) => _items = items;

    public static ItemCatalog Load()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Assets", "loot_catalog.json");
        if (!File.Exists(path)) return new ItemCatalog([]);
        using var document = JsonDocument.Parse(File.ReadAllBytes(path));
        var rows = new List<CatalogItem>();
        foreach (var item in document.RootElement.GetProperty("items").EnumerateArray())
        {
            if (!item.TryGetProperty("id", out var id) || !item.TryGetProperty("name", out var name)) continue;
            rows.Add(new CatalogItem(id.GetInt64().ToString(), name.GetString() ?? string.Empty));
        }
        return new ItemCatalog(rows);
    }

    public CatalogMatch? Match(string sourceName)
    {
        var normalized = Normalize(sourceName);
        var exact = MatchExact(sourceName);
        if (exact is not null) return exact;

        CatalogItem? best = null;
        var bestDistance = int.MaxValue;
        var tied = false;
        foreach (var item in _items)
        {
            var candidate = Normalize(item.Name);
            if (Math.Abs(candidate.Length - normalized.Length) > 3) continue;
            var distance = Distance(normalized, candidate);
            if (distance < bestDistance)
            {
                bestDistance = distance;
                best = item;
                tied = false;
            }
            else if (distance == bestDistance) tied = true;
        }
        var allowed = normalized.Length >= 18 ? 3 : normalized.Length >= 10 ? 2 : 1;
        return !tied && best is not null && bestDistance <= allowed ? ToMatch(best) : null;
    }

    public CatalogMatch? MatchExact(string sourceName)
    {
        var normalized = Normalize(sourceName);
        var matches = _items.Where(item => Normalize(item.Name) == normalized).ToArray();
        return matches.Length == 1 ? ToMatch(matches[0]) : null;
    }

    private static CatalogMatch ToMatch(CatalogItem item)
    {
        var icon = Path.Combine(AppContext.BaseDirectory, "Assets", "icons", $"{item.Id}.png");
        return new CatalogMatch(item.Id, item.Name, File.Exists(icon) ? icon : null);
    }

    private static string Normalize(string value) => NonAlphaNumericRegex()
        .Replace(value.ToLowerInvariant().Replace('’', '\''), string.Empty);

    private static int Distance(string left, string right)
    {
        var previous = Enumerable.Range(0, right.Length + 1).ToArray();
        for (var i = 1; i <= left.Length; i++)
        {
            var current = new int[right.Length + 1];
            current[0] = i;
            for (var j = 1; j <= right.Length; j++)
            {
                current[j] = Math.Min(
                    Math.Min(current[j - 1] + 1, previous[j] + 1),
                    previous[j - 1] + (left[i - 1] == right[j - 1] ? 0 : 1));
            }
            previous = current;
        }
        return previous[^1];
    }

    [GeneratedRegex("[^a-z0-9]+")]
    private static partial Regex NonAlphaNumericRegex();

    private sealed record CatalogItem(string Id, string Name);
}

internal sealed record CatalogMatch(string ItemId, string Name, string? IconPath);
