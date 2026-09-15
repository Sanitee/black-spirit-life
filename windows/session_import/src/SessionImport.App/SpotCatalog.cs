using System.Globalization;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace BlackSpiritLife.SessionImport.App;

internal sealed record SpotItemDefinition(string Id, string Name, IReadOnlyList<string> Aliases);
internal sealed record SpotSessionColumn(string Name, string? ItemId, IReadOnlyList<string> CandidateItemIds, string Role);

internal sealed record SpotDefinition(
    string Id, string Name, string Activity, string SourceKind, string SourceId,
    IReadOnlyList<string> Aliases, IReadOnlyList<string> MethodIds,
    IReadOnlyList<string> DropItemIds, IReadOnlyList<string> CommonDropItemIds,
    string? GarmothSpotId)
{
    public override string ToString() => Name;
    public IEnumerable<string> NavigationNames => new[] { Name }.Concat(Aliases);
    public string? SidebarCategory { get; init; }
    public string? SidebarGroup { get; init; }
    public IReadOnlyList<string> ArtworkUrls { get; init; } = [];
    public IReadOnlyList<string> Badges { get; init; } = [];
    public IReadOnlyList<string> LinkedSourceIds { get; init; } = [];
    public IReadOnlyList<string> SourceDropItemIds { get; init; } = [];
    public IReadOnlyList<SpotSessionColumn> SessionColumns { get; init; } = [];
    public bool HasVerifiedSessionColumns { get; init; }
    public bool ActivityNeedsReview => SidebarGroup == "WHALING";
}

/// <summary>Observed destination identities with separately verified loot and informational source links.</summary>
internal sealed partial class SpotCatalog
{
    private readonly Dictionary<string, SpotItemDefinition> _itemsById;
    private readonly Dictionary<string, List<SpotItemDefinition>> _itemsByName = new(StringComparer.Ordinal);

    private SpotCatalog(IReadOnlyList<SpotDefinition> entries, IReadOnlyList<SpotItemDefinition> items,
        int clientZones, int companionSpots, IReadOnlyList<SpotDefinition>? sourceEntries = null)
    {
        Entries = entries;
        Items = items;
        SourceEntries = sourceEntries ?? entries;
        ClientGrindingZoneCount = clientZones;
        CompanionSpotCount = companionSpots;
        _itemsById = items.ToDictionary(item => item.Id, StringComparer.Ordinal);
        foreach (var item in items)
        {
            foreach (var name in new[] { item.Name }.Concat(item.Aliases).Select(Normalize).Distinct())
            {
                if (!_itemsByName.TryGetValue(name, out var matches)) _itemsByName[name] = matches = [];
                matches.Add(item);
            }
        }
    }

    public IReadOnlyList<SpotDefinition> Entries { get; }
    public IReadOnlyList<SpotDefinition> SourceEntries { get; }
    public IReadOnlyList<SpotItemDefinition> Items { get; }
    public int ClientGrindingZoneCount { get; }
    public int CompanionSpotCount { get; }
    public bool IsCompleteGameOrGarmothCatalog => false;

    public static SpotCatalog Load(string? path = null)
    {
        path ??= Path.Combine(AppContext.BaseDirectory, "Assets", "spot_catalog.json");
        // Missing optional catalog leaves manual correction available; it never
        // restores the old one-spot guess or invents an activity.
        var source = File.Exists(path) ? Parse(File.ReadAllText(path)) : new([], [], 0, 0);
        var observedPath = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(path))!, "garmoth_spot_catalog.json");
        return File.Exists(observedPath) ? source.WithObserved(File.ReadAllText(observedPath)) : source;
    }

    internal static SpotCatalog Parse(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (root.GetProperty("schemaVersion").GetInt32() != 1)
            throw new InvalidDataException("Unsupported spot catalog.");
        var items = root.GetProperty("items").EnumerateArray().Select(item => new SpotItemDefinition(
            Required(item, "id"), Required(item, "name"), Strings(item, "aliases"))).ToArray();
        if (items.Select(item => item.Id).Distinct(StringComparer.Ordinal).Count() != items.Length ||
            items.Any(item => !IsItemId(item.Id)))
            throw new InvalidDataException("Invalid or duplicate spot item identity.");
        var itemIds = items.Select(item => item.Id).ToHashSet(StringComparer.Ordinal);
        var spots = root.GetProperty("spots").EnumerateArray().Select(spot => new SpotDefinition(
            Required(spot, "id"), Required(spot, "name"), Required(spot, "activity"),
            Required(spot, "sourceKind"), Required(spot, "sourceId"), Strings(spot, "aliases"),
            Strings(spot, "methodIds"), Strings(spot, "dropItemIds"), Strings(spot, "commonDropItemIds"),
            spot.TryGetProperty("garmothSpotId", out var key) && key.ValueKind == JsonValueKind.String ? key.GetString() : null)).ToArray();
        if (spots.Select(spot => spot.Id).Distinct(StringComparer.Ordinal).Count() != spots.Length ||
            spots.Any(spot => spot.Activity is not ("gathering" or "hunting" or "grinding") ||
                spot.DropItemIds.Any(id => !itemIds.Contains(id)) ||
                spot.CommonDropItemIds.Any(id => !spot.DropItemIds.Contains(id))))
            throw new InvalidDataException("Invalid spot identity, activity or item mapping.");
        // Client/source keys must never become site IDs. Only the separately
        // observed catalog establishes actual site destination identities.
        if (spots.Any(spot => spot.GarmothSpotId is not null))
            throw new InvalidDataException("This source catalog does not establish Garmoth spot IDs.");
        var clientCount = spots.Count(spot => spot.SourceKind == "client-zone");
        var companionCount = spots.Count(spot => spot.SourceKind == "companion-spot");
        return new(spots, items, clientCount, companionCount);
    }

    internal SpotCatalog WithObserved(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (root.GetProperty("schemaVersion").GetInt32() != 1)
            throw new InvalidDataException("Unsupported observed Garmoth catalog.");
        var items = Items.ToDictionary(item => item.Id, StringComparer.Ordinal);
        if (root.TryGetProperty("items", out var extraItems))
        {
            foreach (var value in extraItems.EnumerateArray())
            {
                var id = Required(value, "id");
                if (!IsItemId(id)) throw new InvalidDataException("Invalid observed item ID.");
                var name = Required(value, "name");
                var aliases = Strings(value, "aliases");
                if (items.TryGetValue(id, out var old))
                    items[id] = old with { Aliases = old.Aliases.Concat(new[] { name }).Concat(aliases).Where(alias => alias != old.Name).Distinct().ToArray() };
                else items[id] = new(id, name, aliases);
            }
        }
        var observed = new List<SpotDefinition>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var commonIds = SourceEntries.SelectMany(spot => spot.CommonDropItemIds).ToHashSet(StringComparer.Ordinal);
        foreach (var value in root.GetProperty("spots").EnumerateArray())
        {
            var siteId = Required(value, "siteId");
            var name = Required(value, "name");
            var category = Required(value, "sidebarCategory");
            var group = Required(value, "sidebarGroup");
            if (!IsItemId(siteId) || !seen.Add(siteId) || category is not ("lifeskill" or "grinding"))
                throw new InvalidDataException("Invalid or duplicate observed Garmoth destination.");
            var activity = category == "grinding" ? "grinding" : group is "HUNTING SPOTS" or "WHALING" ? "hunting" : "gathering";
            var artwork = Strings(value, "artworkUrls");
            if (artwork.Any(url => !Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme != "https" ||
                uri.Host != "assets.garmoth.com" || !uri.IsDefaultPort || uri.UserInfo.Length > 0 || uri.Query.Length > 0 ||
                uri.Fragment.Length > 0 || !uri.AbsolutePath.StartsWith("/img/", StringComparison.Ordinal)))
                throw new InvalidDataException("Observed artwork must be a public static asset without account data.");
            var badges = Strings(value, "badges");
            var sourceMatches = SourceEntries.Where(spot => spot.Activity == activity &&
                spot.NavigationNames.Any(alias => Normalize(alias) == Normalize(name)) &&
                badges.Contains("elvia") == spot.Name.Contains("Elvia", StringComparison.OrdinalIgnoreCase) &&
                badges.Contains("lantern") == spot.Name.Contains("Dehkia", StringComparison.OrdinalIgnoreCase)).ToArray();
            // A same-named base/Elvia variant or a method-merged source is not
            // proof of this site's loot columns. Links remain informational.
            var linked = sourceMatches.Length == 1 ? sourceMatches : [];
            var sessionIds = Strings(value, "verifiedSessionItemIds");
            var costIds = Strings(value, "costItemIds");
            var sessionColumns = new List<SpotSessionColumn>();
            var hasEvidence = value.TryGetProperty("sessionEvidence", out var evidence) && evidence.ValueKind == JsonValueKind.Object &&
                evidence.TryGetProperty("kind", out var kind) && kind.GetString() == "rendered-history-item-columns" &&
                evidence.TryGetProperty("spotId", out var proofId) && proofId.GetString() == siteId &&
                evidence.TryGetProperty("complete", out var complete) && complete.ValueKind == JsonValueKind.True &&
                evidence.TryGetProperty("capturedAt", out var captured) && DateTimeOffset.TryParse(captured.GetString(), CultureInfo.InvariantCulture, DateTimeStyles.None, out _) &&
                evidence.TryGetProperty("captureSha256", out var hash) && hash.GetString() is { } digest && digest.Length == 64 && digest.All(char.IsAsciiHexDigit);
            if (hasEvidence)
            {
                // Artwork keys are not item IDs: different items can reuse one
                // bitmap. Every mapped column needs its own observed identity.
                if (!evidence.TryGetProperty("columns", out var columns) || columns.ValueKind != JsonValueKind.Array)
                    throw new InvalidDataException("Observed drop evidence is missing named item columns.");
                var mapped = new HashSet<string>(StringComparer.Ordinal);
                foreach (var column in columns.EnumerateArray())
                {
                    var id = column.TryGetProperty("itemId", out var itemId) && itemId.ValueKind == JsonValueKind.String ? itemId.GetString() : null;
                    var nameText = Required(column, "observedName");
                    var observedName = Normalize(nameText);
                    var identityKind = Required(column, "identityKind");
                    var candidates = Strings(column, "candidateItemIds");
                    var role = Required(column, "role");
                    if (role is not ("session-item" or "cost" or "noncanonical"))
                        throw new InvalidDataException("Invalid session column role.");
                    if (id is null)
                    {
                        if (identityKind == "ambiguous-exact-client-name" && candidates.Length > 1 && candidates.All(IsItemId) && role == "session-item")
                            sessionColumns.Add(new(nameText, null, candidates, role));
                        else if (identityKind == "noncanonical-session-header" && candidates.Length == 0 && role == "noncanonical")
                            sessionColumns.Add(new(nameText, null, [], role));
                        else throw new InvalidDataException("Unresolved columns must retain their ambiguity without a canonical item ID.");
                        continue;
                    }
                    var matches = items.Values.Where(item => new[] { item.Name }.Concat(item.Aliases)
                        .Any(alias => Normalize(alias) == observedName)).Select(item => item.Id).ToArray();
                    if (!matches.Contains(id) || identityKind is not ("exact-client-name" or "explicit-public-item-id") ||
                        (identityKind == "exact-client-name" && matches.Length != 1))
                        throw new InvalidDataException("Observed loot identity is unknown or ambiguous; artwork is not item identity.");
                    mapped.Add(id);
                    if ((role == "cost") != costIds.Contains(id) || role == "noncanonical")
                        throw new InvalidDataException("Session cost classification does not match its named column.");
                    sessionColumns.Add(new(nameText, id, [id], role));
                }
                if (!mapped.SetEquals(sessionIds))
                    throw new InvalidDataException("Verified session IDs do not match the identified history columns.");
            }
            if (sessionIds.Any(id => !items.ContainsKey(id)) || costIds.Any(id => !sessionIds.Contains(id)) || (sessionIds.Length > 0 && !hasEvidence))
                throw new InvalidDataException("Observed session IDs require matching complete history-header evidence and known item identities.");
            var compatibleIds = sessionColumns.Where(column => column.Role == "session-item")
                .SelectMany(column => column.CandidateItemIds).Distinct().ToArray();
            var method = category == "grinding" ? "grinding" : Normalize(group).Replace(" spots", "").Replace(' ', '-');
            observed.Add(new("garmoth:" + method + ":" + siteId, name, activity, "garmoth-observed", siteId,
                Strings(value, "aliases"), ["garmoth:" + method], compatibleIds, compatibleIds.Where(commonIds.Contains).ToArray(), siteId)
            {
                SidebarCategory = category, SidebarGroup = group, ArtworkUrls = artwork, Badges = badges,
                LinkedSourceIds = linked.Select(spot => spot.Id).ToArray(),
                SourceDropItemIds = linked.SelectMany(spot => spot.DropItemIds).Distinct().ToArray(),
                SessionColumns = sessionColumns.ToArray(), HasVerifiedSessionColumns = hasEvidence,
            });
        }
        return new(observed.ToArray(), items.Values.ToArray(), ClientGrindingZoneCount, CompanionSpotCount, SourceEntries);
    }

    public IReadOnlyList<SpotDefinition> FindByName(string text, string? activity = null)
    {
        var name = Normalize(text);
        if (name.Length == 0) return [];
        return Entries.Where(spot => (activity is null || spot.Activity == activity) &&
            spot.NavigationNames.Any(candidate => Normalize(candidate) == name)).ToArray();
    }

    public IReadOnlyList<SpotDefinition> Search(string text, string? activity = null)
    {
        var query = Normalize(text);
        return Entries.Where(spot => (activity is null || spot.Activity == activity) &&
                (query.Length == 0 || spot.NavigationNames.Any(name => Normalize(name).Contains(query, StringComparison.Ordinal))))
            .OrderBy(spot => spot.Name, StringComparer.OrdinalIgnoreCase).ThenBy(spot => spot.Id, StringComparer.Ordinal).ToArray();
    }

    public IReadOnlyList<SpotItemDefinition> FindItems(string? name, string? itemId = null)
    {
        var normalized = Normalize(name);
        var named = _itemsByName.TryGetValue(normalized, out var matches) ? matches : [];
        if (string.IsNullOrWhiteSpace(itemId)) return named.ToArray();
        if (!_itemsById.TryGetValue(itemId, out var item)) return [];
        // A supplied ID is usable with no name, or with a matching exact source
        // name. Conflicting/fuzzy upstream guesses must not drive a spot choice.
        return normalized.Length == 0 || named.Any(candidate => candidate.Id == itemId) ? [item] : [];
    }

    public SpotItemDefinition? MatchItem(string? name, string? itemId = null)
    {
        var matches = FindItems(name, itemId);
        return matches.Count == 1 ? matches[0] : null;
    }

    public static string Normalize(string? value) => Whitespace().Replace(
        (value ?? string.Empty).Normalize(NormalizationForm.FormKC)
            .Replace('’', '\'').Replace('`', '\'').Trim(), " ").ToLowerInvariant();

    private static bool IsItemId(string id) => id.Length > 0 && id.All(char.IsAsciiDigit) &&
        long.TryParse(id, NumberStyles.None, CultureInfo.InvariantCulture, out var number) && number > 0;
    private static string Required(JsonElement element, string field)
    {
        var value = element.GetProperty(field).GetString();
        return !string.IsNullOrWhiteSpace(value) ? value : throw new InvalidDataException("Missing spot catalog field.");
    }
    private static string[] Strings(JsonElement element, string field) =>
        element.TryGetProperty(field, out var value) ? value.EnumerateArray().Select(part => part.GetString() ?? string.Empty)
            .Where(part => !string.IsNullOrWhiteSpace(part)).Distinct(StringComparer.Ordinal).ToArray() : [];
    [GeneratedRegex("\\s+")]
    private static partial Regex Whitespace();
}
