namespace BlackSpiritLife.SessionImport.App;

internal sealed record SpotLootItem(string Name, string? ItemId = null, long Quantity = 1);
internal sealed record SpotCandidate(SpotDefinition Spot, IReadOnlyList<string> MatchedItemIds,
    IReadOnlyList<string> EvidenceItemIds, IReadOnlyList<string> MatchedItemNames)
{
    public bool IsTentative => !Spot.HasVerifiedSessionColumns;
}
internal sealed record SpotResolution(IReadOnlyList<SpotCandidate> Candidates, SpotDefinition? Suggested,
    IReadOnlyList<string> UnknownItemNames, IReadOnlyList<string> AmbiguousItemNames,
    IReadOnlyList<string> UnmappedItemNames)
{
    public bool NeedsChoice => Candidates.Count > 0 && Suggested is null;
    public IReadOnlyList<string> UnsupportedItemNames { get; init; } = [];
    public bool IsHeuristicSuggestion { get; init; }
}

/// <summary>Positive-evidence candidates; no assumed absent drops or quantity ratios.</summary>
internal sealed class SpotResolver(SpotCatalog catalog)
{
    public SpotResolution Resolve(IEnumerable<SpotLootItem> loot)
    {
        var items = new Dictionary<string, SpotItemDefinition>(StringComparer.Ordinal);
        var unknown = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var ambiguous = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var row in loot)
        {
            if (row.Quantity <= 0) continue;
            var matches = catalog.FindItems(row.Name, row.ItemId);
            if (matches.Count == 1) items[matches[0].Id] = matches[0];
            else if (matches.Count > 1) ambiguous.Add(row.Name);
            else unknown.Add(row.Name);
        }
        var common = catalog.Entries.Concat(catalog.SourceEntries).SelectMany(spot => spot.CommonDropItemIds).ToHashSet(StringComparer.Ordinal);
        common.UnionWith(catalog.Entries.SelectMany(spot => spot.SessionColumns.Where(column => column.Role == "cost")
            .SelectMany(column => column.CandidateItemIds)));
        var candidates = catalog.Entries.Select(spot =>
        {
            var knownDrops = spot.DropItemIds.Concat(spot.HasVerifiedSessionColumns ? [] : spot.SourceDropItemIds);
            var matched = items.Values.Where(item => knownDrops.Contains(item.Id) ||
                spot.SessionColumns.Any(column => column.Role == "session-item" &&
                    new[] { item.Name }.Concat(item.Aliases).Any(name => SpotCatalog.Normalize(name) == SpotCatalog.Normalize(column.Name))))
                .Select(item => item.Id).Distinct(StringComparer.Ordinal).ToArray();
            var evidence = matched.Where(id => !common.Contains(id)).ToArray();
            return new SpotCandidate(spot, matched, evidence, matched.Select(id => items[id].Name).ToArray());
        }).Where(candidate => candidate.MatchedItemIds.Count > 0)
            .OrderByDescending(candidate => candidate.EvidenceItemIds.Count)
            .ThenByDescending(candidate => candidate.MatchedItemIds.Count)
            .ThenBy(candidate => candidate.Spot.Name, StringComparer.OrdinalIgnoreCase)
            .ThenBy(candidate => candidate.Spot.Id, StringComparer.Ordinal).ToArray();

        // All informative positive evidence must agree. Known extra items that
        // occur in no supported session table are reported, not silently lost.
        // Unknown names, common-only loot and mixed evidence remain unresolved.
        var evidenceIds = candidates.SelectMany(candidate => candidate.EvidenceItemIds).ToHashSet(StringComparer.Ordinal);
        var mappedIds = candidates.SelectMany(candidate => candidate.MatchedItemIds).ToHashSet(StringComparer.Ordinal);
        var informativeUnmappedCount = items.Keys.Count(id => !mappedIds.Contains(id) && !common.Contains(id));
        var unmapped = items.Values.Where(item => !mappedIds.Contains(item.Id)).Select(item => item.Name)
            .Order(StringComparer.OrdinalIgnoreCase).ToArray();
        var complete = candidates.Where(candidate => evidenceIds.Count > 0 &&
            evidenceIds.IsSubsetOf(candidate.EvidenceItemIds)).ToArray();
        // Unchecked site records may share any of these drops. Never call a
        // partial harvest unique merely because competing tables are missing.
        var exact = complete.Length == 1 ? complete[0].Spot : null;
        var top = candidates.FirstOrDefault();
        var runnerUpCount = candidates.Skip(1).FirstOrDefault()?.EvidenceItemIds.Count ?? 0;
        // This is an editable recommendation, not a claim that session columns
        // exhaust the game's drops. A strong combination may coexist with a
        // small number of unsupported extras; weak/tied/mixed evidence cannot.
        var dominant = top is not null && top.EvidenceItemIds.Count >= 3 &&
            top.EvidenceItemIds.Count - runnerUpCount >= 2 &&
            top.EvidenceItemIds.Count * 4 >= evidenceIds.Count * 3 ? top.Spot : null;
        var unique = exact ?? dominant;
        var allRelevantTablesKnown = unique is not null && unique.HasVerifiedSessionColumns &&
            catalog.Entries.Where(spot => (spot.SidebarCategory ?? spot.Activity) == (unique.SidebarCategory ?? unique.Activity))
                .All(spot => spot.HasVerifiedSessionColumns);
        var uniqueEvidenceCount = unique is null ? 0 : candidates.First(candidate => candidate.Spot == unique).EvidenceItemIds.Count;
        // Unmapped identities do not contradict observed positive evidence, but
        // a weak anchor must not outweigh numerous unsupported identities. This
        // guard applies to both exact intersections and dominant combinations.
        var suggested = allRelevantTablesKnown && unknown.Count == 0 && ambiguous.Count == 0 &&
            informativeUnmappedCount <= uniqueEvidenceCount ? unique : null;
        var unsupported = suggested is null ? [] : items.Values.Where(item =>
            !suggested.SessionColumns.Any(column => column.CandidateItemIds.Contains(item.Id) ||
                new[] { item.Name }.Concat(item.Aliases).Any(name => SpotCatalog.Normalize(name) == SpotCatalog.Normalize(column.Name))))
            .Select(item => item.Name).Order(StringComparer.OrdinalIgnoreCase).ToArray();
        return new(candidates, suggested, unknown.Order(StringComparer.OrdinalIgnoreCase).ToArray(),
            ambiguous.Order(StringComparer.OrdinalIgnoreCase).ToArray(), unmapped)
        {
            UnsupportedItemNames = unsupported,
            IsHeuristicSuggestion = suggested is not null && (exact is null || informativeUnmappedCount > 0),
        };
    }
}
