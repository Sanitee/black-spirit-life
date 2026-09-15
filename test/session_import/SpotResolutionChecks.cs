using System.Text.Json;
using BlackSpiritLife.SessionImport.App;

internal static class SpotResolutionChecks
{
    internal static void Run(Action<string, Action> run)
    {
        run("spot catalog covers every supplied source record without claiming all Garmoth spots", () =>
        {
            var catalog = SpotCatalog.Load();
            Check(catalog.Entries.Count == 174 && catalog.SourceEntries.Count == 149 && catalog.ClientGrindingZoneCount == 112 && catalog.CompanionSpotCount == 37, "observed and source record counts");
            Check(catalog.Items.Count >= 718 && !catalog.IsCompleteGameOrGarmothCatalog, "item coverage and explicit limit");
            Check(catalog.Entries.Count(spot => spot.Activity == "grinding") == 100 &&
                catalog.Entries.Count(spot => spot.Activity == "gathering") == 48 &&
                catalog.Entries.Count(spot => spot.Activity == "hunting") == 26, "observed categories retain navigation activity");
            Check(catalog.SourceEntries.Count(spot => spot.MethodIds.Contains("sniper")) == 2, "source sniper methods retained separately");
            Check(catalog.SourceEntries.Count(spot => spot.DropItemIds.Count == 0) == 3, "unmapped source zones retained informationally");
            Check(catalog.Entries.Count(spot => spot.ActivityNeedsReview) == 5, "WHALING ambiguity remains explicit");
        });
        run("spot aliases use exact normalized source names and preserve collisions", () =>
        {
            var catalog = SourceCatalog();
            var coral = catalog.FindByName("  RUSALKA’S   CORAL  ");
            Check(coral.Count == 1 && coral[0].Id == "companion:stillcoral-rusalka-mining", "source alias normalization");
            Check(catalog.FindByName("Rusalka coral").Count == 0, "no invented spelling alias");
            Check(catalog.FindByName("Wild herbs").Count == 3, "three real herb locations remain ambiguous");
            Check(catalog.FindByName("Ｗｉｌｄ herbs").Count == 3, "NFKC normalization");
        });
        run("spot search and exact choices retain grinding gathering and hunting activities", () =>
        {
            var catalog = SpotCatalog.Load();
            Check(catalog.FindByName("Orc Camp", "grinding").Single().Activity == "grinding" &&
                catalog.FindByName("Orc Camp").Count == 2, "same name has separate gathering and grinding identities");
            Check(catalog.FindByName("Coral Stoneback Crab").Single().Activity == "hunting", "actual hunting label");
            Check(catalog.FindByName("Rusalka's Coral", "hunting").Count == 0, "activity is not inferred from same-name loot");
            Check(catalog.Search("coral").Count >= 2 && catalog.Search("coral", "grinding").All(spot => spot.Activity == "grinding"), "search activity restriction");
            Check(catalog.FindByName("Made-up zone").Count == 0, "unknown free text has no default activity");
        });
        run("source keys never become Garmoth IDs or routes", () =>
        {
            var catalog = SpotCatalog.Load();
            Check(catalog.SourceEntries.All(spot => spot.GarmothSpotId is null && !spot.Id.StartsWith("http")), "source IDs never become site identities");
            Check(catalog.Entries.All(spot => spot.GarmothSpotId is not null && spot.Id.StartsWith("garmoth:") && !spot.Id.Contains("http")), "observed numeric IDs only");
            Check(catalog.Entries.Select(spot => spot.GarmothSpotId).Distinct().Count() == 174, "featured duplicates deduplicated");
            Check(catalog.Search("").Count == 174, "all actual supplied names selectable despite unchecked drops");
        });
        run("all catalog item names and source aliases resolve without fuzzy matching", () =>
        {
            var catalog = SpotCatalog.Load();
            foreach (var item in catalog.Items)
                foreach (var name in new[] { item.Name }.Concat(item.Aliases))
                    Check(catalog.FindItems(name).Any(match => match.Id == item.Id), "exact item identity " + item.Id);
            Check(catalog.MatchItem("Rough Ston") is null, "OCR near-match is not decisive evidence");
            Check(catalog.MatchItem("Rough Stone", "821255") is null, "conflicting supplied ID is not trusted");
            Check(catalog.MatchItem("", "4006")?.Name == "Rough Stone", "explicit known item ID accepted without a conflicting name");
        });
        run("unique informative loot suggests its source and quantities never weight the choice", () =>
        {
            var resolver = new SpotResolver(Fixture());
            var result = resolver.Resolve([new("Unique A", Quantity: 1), new("Common", Quantity: 999999)]);
            Check(result.Suggested?.GarmothSpotId == "1", "unique verified positive evidence");
            var duplicate = resolver.Resolve([new("Unique A", Quantity: 2), new("Unique A", Quantity: 900), new("Common")]);
            Check(duplicate.Suggested?.GarmothSpotId == "1" && duplicate.Candidates[0].EvidenceItemIds.Count == 1, "same item counted once");
            Check(resolver.Resolve([new("Unique A", Quantity: 0), new("Unique B", Quantity: -1)]).Candidates.Count == 0, "nonpositive counts are not loot evidence");
        });
        run("common-only loot never auto-selects a spot", () =>
        {
            var result = new SpotResolver(Fixture()).Resolve([new("Common")]);
            Check(result.Candidates.Count == 2 && result.Suggested is null && result.NeedsChoice, "common overlap retained");
            var real = new SpotResolver(SpotCatalog.Load()).Resolve([new("Caphras Stone")]);
            Check(real.Suggested is null && real.Candidates.Count > 2, "real cross-activity common drop");
        });
        run("overlapping informative loot and mixed sessions remain unresolved", () =>
        {
            var resolver = new SpotResolver(Fixture());
            var overlap = resolver.Resolve([new("Shared")]);
            Check(overlap.Candidates.Count == 2 && overlap.Suggested is null, "same drop multiple sources");
            var mixed = resolver.Resolve([new("Unique A"), new("Unique B")]);
            Check(mixed.Candidates.Count == 2 && mixed.Suggested is null, "conflicting positive source evidence");
        });
        run("unknown and ambiguous identities block suggestions while known unsupported extras stay explicit", () =>
        {
            var resolver = new SpotResolver(Fixture());
            var unknown = resolver.Resolve([new("Unique A"), new("Unrecognized")]);
            Check(unknown.Suggested is null && unknown.UnknownItemNames.SequenceEqual(["Unrecognized"]), "unknown preserved");
            var unmapped = resolver.Resolve([new("Unique A"), new("Known without source")]);
            Check(unmapped.Suggested?.GarmothSpotId == "1" && unmapped.UnmappedItemNames.SequenceEqual(["Known without source"]) &&
                unmapped.UnsupportedItemNames.SequenceEqual(["Known without source"]) && unmapped.IsHeuristicSuggestion,
                "one known unsupported extra remains an explicit editable recommendation, not an exact location");
            var ambiguous = resolver.Resolve([new("Unique A"), new("Collision")]);
            Check(ambiguous.Suggested is null && ambiguous.AmbiguousItemNames.SequenceEqual(["Collision"]), "item alias tie has no first winner");
            foreach (var veto in new[] { "Unrecognized", "Collision" })
                Check(resolver.Resolve([new("Unique A"), new("Known without source"), new(veto)]).Suggested is null,
                    "unsupported-extra recommendation does not bypass unknown or ambiguous identity veto");
        });
        run("Rusalka coral alone has mining and hunting candidates", () =>
        {
            var result = new SpotResolver(SourceCatalog()).Resolve([new("Rusalka's Coral")]);
            Check(result.Candidates.Any(candidate => candidate.Spot.Id == "companion:stillcoral-rusalka-mining") &&
                result.Candidates.Any(candidate => candidate.Spot.Id == "companion:edania-coral-crab-hunting"), "both recorded acquisition methods");
            Check(result.Suggested is null, "no hardcoded mining choice");
        });
        run("sixteen-row Rusalka screenshot stays a candidate suggestion not an exhaustive location claim", () =>
        {
            string[] names = ["Rough Stone", "Black Gem Fragment", "Sharp Black Crystal Shard", "Lobster", "Fairy's Breath",
                "Caphras Stone", "Coral Piece", "Fairy Powder", "Dim Heartvein Shard", "Rusalka's Coral", "Cracked Terrashard",
                "Ancient Spirit Dust", "Fruit of Nature", "Blue Coral", "Rough Translucent Crystal", "Rough Blue Crystal"];
            var result = new SpotResolver(SourceCatalog()).Resolve(names.Select(name => new SpotLootItem(name)));
            Check(result.UnknownItemNames.Count == 0 && result.AmbiguousItemNames.Count == 0, "all sixteen item identities supported");
            Check(result.Candidates.Any(candidate => candidate.Spot.Id == "companion:stillcoral-rusalka-mining"), "mining remains a candidate");
            Check(result.UnmappedItemNames.Contains("Lobster") && result.UnmappedItemNames.Contains("Blue Coral") && result.Suggested is null,
                "incomplete source tables do not become false certainty");
        });
        run("client zone distinctive drops remain informational without actual site history proof", () =>
        {
            var catalog = SourceCatalog();
            var occurrences = catalog.Entries.SelectMany(spot => spot.DropItemIds.Select(id => (id, spot))).GroupBy(entry => entry.id)
                .Where(group => group.Count() == 1 && group.Single().spot.Activity == "grinding").ToArray();
            Check(occurrences.Length > 0, "real distinctive zone items exist");
            foreach (var occurrence in occurrences.Take(12))
            {
                var spot = occurrence.Single().spot;
                var result = new SpotResolver(catalog).Resolve([new("", occurrence.Key)]);
                Check(result.Suggested is null && result.Candidates.Any(candidate => candidate.Spot.Id == spot.Id && candidate.IsTentative), "tentative distinctive client loot " + occurrence.Key);
            }
        });
        run("malformed catalog IDs activities and invented site keys fail validation", () =>
        {
            var data = FixtureJson();
            Throws(() => SpotCatalog.Parse(data.Replace("\"activity\":\"grinding\"", "\"activity\":\"fishing\"")));
            Throws(() => SpotCatalog.Parse(data.Replace("\"garmothSpotId\":null", "\"garmothSpotId\":\"3\"")));
            Throws(() => SpotCatalog.Parse(data.Replace("\"dropItemIds\":[\"1\",\"3\",\"4\"]", "\"dropItemIds\":[\"999\"]")));
        });
        run("actual same-name spots preserve method ambiguity instead of first-match selection", () =>
        {
            var catalog = SpotCatalog.Load();
            var kaia = catalog.FindByName("North Kaia Mountain Top");
            Check(kaia.Count == 2 && kaia.Select(spot => spot.GarmothSpotId).ToHashSet().SetEquals(["51", "62"]), "timber and sap IDs retained");
            Check(kaia.Select(spot => spot.MethodIds.Single()).Distinct().Count() == 2, "per-method namespaces");
            Check(catalog.FindByName("Stonetail Horse Ranch Bisons").Count == 2, "meat and blood destinations not merged");
        });
        run("observed artwork is never the source of session item identity", () =>
        {
            var catalog = SpotCatalog.Load();
            Check(catalog.Entries.All(spot => spot.SessionColumns.All(column => column.Role is "session-item" or "cost" or "noncanonical")), "session roles are explicit");
            var coral = catalog.FindByName("Rusalka's Coral").Single();
            Check(coral.GarmothSpotId == "186" && coral.SourceDropItemIds.Count > 0 && coral.ArtworkUrls.Count > 0, "separate observed destination and informational source link");
            var result = new SpotResolver(catalog).Resolve([new("Rusalka's Coral")]);
            Check(result.Suggested is null && result.Candidates.Any(candidate => candidate.Spot == coral), "coral alone remains ambiguous even after harvest");
        });
        run("partial history coverage cannot manufacture a unique match", () =>
        {
            var catalog = SpotCatalog.Parse(FixtureJson()).WithObserved(ObservedJson(verifySecond: false).Replace("\"sidebarCategory\":\"lifeskill\"", "\"sidebarCategory\":\"grinding\""));
            var result = new SpotResolver(catalog).Resolve([new("Unique A")]);
            Check(result.Candidates.Count == 1 && result.Suggested is null, "unchecked competitor remains possible");
            Check(catalog.Search("").Count == 2, "unchecked destination still selectable");
        });
        run("named history columns reject artwork IDs, wrong item names and mismatched evidence", () =>
        {
            var source = SpotCatalog.Parse(FixtureJson());
            var json = ObservedJson();
            Throws(() => source.WithObserved(json.Replace("\"identityKind\":\"exact-client-name\"", "\"identityKind\":\"artwork-basename\"")));
            Throws(() => source.WithObserved(json.Replace("\"observedName\":\"Unique A\"", "\"observedName\":\"Unique B\"")));
            Throws(() => source.WithObserved(json.Replace("\"spotId\":\"1\"", "\"spotId\":\"9\"")));
            Throws(() => source.WithObserved(json.Replace("\"complete\":true", "\"complete\":false")));
            Throws(() => source.WithObserved(json.Replace("\"observedName\":\"Unique A\"", "\"observedName\":\"Collision\"")));
        });
        run("observed artwork accepts only public static assets without account content", () =>
        {
            var source = SpotCatalog.Parse(FixtureJson());
            foreach (var url in new[] { "https://garmoth.com/grind-tracker/private/spot/1", "https://assets.garmoth.com/img/1.webp?account=private", "https://elsewhere.test/img/1.webp" })
                Throws(() => source.WithObserved(ObservedJson().Replace("https://assets.garmoth.com/img/1.webp", url)));
        });
        run("Fairy's Breath and Dormant Fairy's Breath stay distinct despite reused artwork", () =>
        {
            var json = JsonSerializer.Serialize(new
            {
                schemaVersion = 1,
                items = new[] { new { id = "820014", name = "Dormant Fairy's Breath", aliases = Array.Empty<string>() } },
                spots = new[] {
                    ObservedSpot("1", "Fixture gathering", "lifeskill", "STONE SPOTS", ["821371"], ["Fairy's Breath"], true),
                    ObservedSpot("2", "Fixture hunting", "lifeskill", "HUNTING SPOTS", ["820014"], ["Dormant Fairy's Breath"], true) },
            });
            var catalog = SourceCatalog().WithObserved(json);
            Check(catalog.Entries.SelectMany(spot => spot.ArtworkUrls).Distinct().Count() == 1, "fixture deliberately shares artwork");
            var result = new SpotResolver(catalog).Resolve([new("Fairy's Breath")]);
            Check(result.Candidates.Count == 1 && result.Candidates[0].MatchedItemIds.SequenceEqual(["821371"]) &&
                result.Candidates[0].Spot.GarmothSpotId == "1", "actual name identity wins over shared image");
            var wrongIdentity = System.Text.Json.Nodes.JsonNode.Parse(json)!;
            wrongIdentity["spots"]![1]!["sessionEvidence"]!["columns"]![0]!["observedName"] = "Fairy's Breath";
            Throws(() => SourceCatalog().WithObserved(wrongIdentity.ToJsonString()));
        });
        run("an unrelated unchecked activity does not block a completely observed category", () =>
        {
            var catalog = SpotCatalog.Parse(FixtureJson()).WithObserved(ObservedJson(verifySecond: false));
            Check(new SpotResolver(catalog).Resolve([new("Unique A")]).Suggested?.GarmothSpotId == "1", "complete grinding category independent of unchecked Lifeskill");
        });
        run("explicit session costs cannot supply unique location evidence", () =>
        {
            var node = System.Text.Json.Nodes.JsonNode.Parse(ObservedJson())!;
            node["spots"]![0]!["costItemIds"] = new System.Text.Json.Nodes.JsonArray("1");
            node["spots"]![0]!["sessionEvidence"]!["columns"]![0]!["role"] = "cost";
            var result = new SpotResolver(SpotCatalog.Parse(FixtureJson()).WithObserved(node.ToJsonString())).Resolve([new("Unique A")]);
            Check(result.Suggested is null && result.Candidates.Count == 0, "expense excluded from positive loot evidence");
        });
        run("duplicate client identities retain exact session-name compatibility without choosing an ID", () =>
        {
            var node = System.Text.Json.Nodes.JsonNode.Parse(ObservedJson())!;
            node["spots"]![0]!["verifiedSessionItemIds"] = new System.Text.Json.Nodes.JsonArray("3", "4");
            var column = node["spots"]![0]!["sessionEvidence"]!["columns"]![0]!;
            column["itemId"] = null;
            column["identityKind"] = "ambiguous-exact-client-name";
            column["candidateItemIds"] = new System.Text.Json.Nodes.JsonArray("1", "999");
            var catalog = SpotCatalog.Parse(FixtureJson()).WithObserved(node.ToJsonString());
            var result = new SpotResolver(catalog).Resolve([new("Unique A")]);
            Check(result.Suggested?.GarmothSpotId == "1" && catalog.Entries[0].SessionColumns[0].ItemId is null &&
                catalog.Entries[0].SessionColumns[0].CandidateItemIds.Count == 2, "same exact label can identify location without fabricated canonical ID");
        });
        run("complete observed Lifeskill tables identify the sixteen-row mining example and retain three unsupported extras", () =>
        {
            string[] names = ["Rough Stone", "Black Gem Fragment", "Sharp Black Crystal Shard", "Lobster", "Fairy's Breath",
                "Caphras Stone", "Coral Piece", "Fairy Powder", "Dim Heartvein Shard", "Rusalka's Coral", "Cracked Terrashard",
                "Ancient Spirit Dust", "Fruit of Nature", "Blue Coral", "Rough Translucent Crystal", "Rough Blue Crystal"];
            var catalog = SpotCatalog.Load();
            var result = new SpotResolver(catalog).Resolve(names.Select(name => new SpotLootItem(name)));
            Check(catalog.Entries.Where(spot => spot.SidebarCategory == "lifeskill").All(spot => spot.HasVerifiedSessionColumns), "all relevant named tables must be observed before an automatic suggestion");
            Check(result.Suggested?.GarmothSpotId == "186", "full positive combination, not coral alone: " +
                string.Join("; ", result.Candidates.Take(4).Select(candidate => candidate.Spot.Name + " " + string.Join(",", candidate.EvidenceItemIds))));
            Check(result.UnsupportedItemNames.ToHashSet().SetEquals(["Lobster", "Blue Coral", "Cracked Terrashard"]), "unsupported extras are explicit and not removed");
            Check(result.UnknownItemNames.Count == 0 && result.AmbiguousItemNames.Count == 0, "known canonical OCR identities remain usable");
            Check(result.IsHeuristicSuggestion && result.Candidates[0].EvidenceItemIds.Count == 5 &&
                result.Candidates[1].EvidenceItemIds.Count == 3 &&
                result.Candidates.SelectMany(candidate => candidate.EvidenceItemIds).Distinct().Count() == 6, "honest dominant suggestion: five of six informative IDs, lead two");
            Check(result.UnmappedItemNames.SequenceEqual(["Blue Coral"]), "one known-unmapped informative identity stays explicit, within the five-match guard");
        });
        run("dominant suggestion meets inclusive three-ID two-lead and seventy-five-percent boundaries", () =>
        {
            var catalog = CombinationFixture(["1", "2", "3"], ["4"]);
            var result = new SpotResolver(catalog).Resolve([new("Material 1"), new("Material 2"), new("Material 3"), new("Material 4")]);
            Check(result.Suggested?.GarmothSpotId == "1" && result.IsHeuristicSuggestion, "3 vs 1, lead2, exactly75 percent");
            Check(result.UnsupportedItemNames.SequenceEqual(["Material 4"]), "stray supported-elsewhere item remains explicit");
            var unknown = new SpotResolver(catalog).Resolve([new("Material 1"), new("Material 2"), new("Material 3"), new("Material 4"), new("Unknown")]);
            Check(unknown.Suggested is null && !unknown.IsHeuristicSuggestion, "unknown identity vetoes heuristic too");
        });
        run("heuristic rejects weak leads coverage below threshold ties and strong mixed combinations", () =>
        {
            foreach (var (a, b) in new (string[], string[])[] {
                (["1", "2"], ["3"]), (["1", "2", "3"], ["4", "5"]),
                (["1", "2", "3", "4"], ["5", "6"]), (["1", "2", "3"], ["4", "5", "6"]),
                (["1"], ["2"]) })
            {
                var catalog = CombinationFixture(a, b);
                var result = new SpotResolver(catalog).Resolve(a.Concat(b).Select(id => new SpotLootItem("Material " + id)));
                Check(result.Suggested is null && !result.IsHeuristicSuggestion, "no weak or mixed automatic selection");
            }
        });
        run("five matching IDs over overlapping three plus one extra is a marked suggestion", () =>
        {
            var catalog = CombinationFixture(["1", "2", "3", "4", "5"], ["1", "2", "3"], ["6"]);
            var result = new SpotResolver(catalog).Resolve(Enumerable.Range(1, 6).Select(id => new SpotLootItem("Material " + id)));
            Check(result.Suggested?.GarmothSpotId == "1" && result.IsHeuristicSuggestion, "5 of6 distinct, runnerup3");
            var exact = new SpotResolver(catalog).Resolve(Enumerable.Range(1, 5).Select(id => new SpotLootItem("Material " + id)));
            Check(exact.Suggested?.GarmothSpotId == "1" && !exact.IsHeuristicSuggestion, "existing exact intersection remains first");
        });
        run("one distinctive anchor permits one known-unmapped extra but not two", () =>
        {
            var resolver = new SpotResolver(CombinationFixtureWithUnmapped(["3", "4"], ["1"], ["2"]));
            var one = resolver.Resolve([new("Material 1"), new("Material 3"), new("Material 3", Quantity: 999)]);
            Check(one.Suggested?.GarmothSpotId == "1" && one.IsHeuristicSuggestion &&
                one.UnsupportedItemNames.SequenceEqual(["Material 3"]), "one distinct extra, not rows or quantity, marks a recommendation");
            var two = resolver.Resolve([new("Material 1"), new("Material 3"), new("Material 4")]);
            Check(two.Suggested is null && !two.IsHeuristicSuggestion && two.NeedsChoice &&
                two.UnmappedItemNames.Count == 2 && two.Candidates[0].EvidenceItemIds.Count == 1,
                "two unsupported informative identities outweigh one anchor; candidate remains selectable");
        });
        run("unmapped-identity guard applies to dominant combinations as well as exact intersections", () =>
        {
            var resolver = new SpotResolver(CombinationFixtureWithUnmapped(["5", "6", "7", "8"], ["1", "2", "3"], ["4"]));
            var three = resolver.Resolve(Enumerable.Range(1, 7).Select(id => new SpotLootItem("Material " + id)));
            Check(three.Suggested?.GarmothSpotId == "1" && three.IsHeuristicSuggestion && three.UnmappedItemNames.Count == 3,
                "three matches, lead two, 3/4 mapped-positive coverage and three unmapped identities are an editable recommendation");
            var four = resolver.Resolve(Enumerable.Range(1, 8).Select(id => new SpotLootItem("Material " + id)));
            Check(four.Suggested is null && !four.IsHeuristicSuggestion && four.UnmappedItemNames.Count == 4,
                "dominant branch cannot bypass four unsupported identities outweighing three matches");
        });
        // Synthetic combinations of genuinely observed session columns. These
        // test catalog compatibility, not naturally occurring loot or live Add forms.
        foreach (var (siteId, activity, names) in new (string, string, string[])[] {
            ("56", "gathering", ["Loopy Tree Sap", "Dead Tree Essence", "Old Tree Branch"]),
            ("204", "hunting", ["Rock Elephant Meat", "Rock Elephant Blood", "Rock Elephant Tusk"]),
            ("17", "grinding", ["Oily Orange Mushroom", "Heart of the Arid Forest", "Shard of the Furious Night"]) })
            run("observed " + activity + " column combination recommends its separate site identity", () =>
            {
                var catalog = SpotCatalog.Load();
                var expected = catalog.Entries.Single(spot => spot.GarmothSpotId == siteId);
                Check(expected.HasVerifiedSessionColumns && names.All(name => expected.SessionColumns.Any(column =>
                    column.Role == "session-item" && column.Name == name)), "each fixture label is a verified column of the intended site");
                var result = new SpotResolver(catalog).Resolve(names.Select(name => new SpotLootItem(name)));
                Check(result.Suggested?.GarmothSpotId == siteId && result.Suggested.Activity == activity &&
                    !result.IsHeuristicSuggestion && result.UnsupportedItemNames.Count == 0,
                    "unambiguous complete observed-column intersection; not a source ID or cross-activity first match");
            });
        run("observed lion columns do not pick the first of several compatible hunting spots", () =>
        {
            var result = new SpotResolver(SpotCatalog.Load()).Resolve([new("Lion Meat"), new("Lion Hide"), new("Lion Blood")]);
            Check(result.Suggested is null && result.NeedsChoice && result.Candidates.Where(candidate => candidate.EvidenceItemIds.Count == 3)
                .Select(candidate => candidate.Spot.GarmothSpotId).ToHashSet().SetEquals(["76", "98", "99"]),
                "Narcion, Giant Lions and Shadow Lion retain genuine observed-column ambiguity");
        });
        run("observed same-name timber and sap destinations retain method-specific candidates", () =>
        {
            var resolver = new SpotResolver(SpotCatalog.Load());
            foreach (var (names, expected, other) in new (string[], string, string)[] {
                (["Cedar Timber", "Pine Timber", "Fir Timber"], "51", "62"),
                (["Cedar Sap", "Pine Sap", "Fir Sap"], "62", "51") })
            {
                var result = resolver.Resolve(names.Select(name => new SpotLootItem(name)));
                Check(result.Suggested is null && result.Candidates.Any(candidate => candidate.Spot.GarmothSpotId == expected && candidate.EvidenceItemIds.Count == 3) &&
                    result.Candidates.All(candidate => candidate.Spot.GarmothSpotId != other),
                    "actual method determines compatible candidate; same-name location is never merged or selected ahead of ties");
            }
        });
    }

    private static SpotCatalog CombinationFixture(params string[][] sets) => CombinationFixtureWithUnmapped([], sets);
    private static SpotCatalog CombinationFixtureWithUnmapped(string[] unmapped, params string[][] sets)
    {
        var items = sets.SelectMany(ids => ids).Concat(unmapped).Distinct().Select(id => new SpotItemDefinition(id, "Material " + id, [])).ToArray();
        var source = JsonSerializer.Serialize(new { schemaVersion = 1, items, spots = Array.Empty<SpotDefinition>() },
            new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
        var observed = JsonSerializer.Serialize(new { schemaVersion = 1,
            spots = sets.Select((ids, index) => ObservedSpot((index + 1).ToString(), "Fixture " + index, "grinding", "TEST", ids, ids.Select(id => "Material " + id).ToArray(), true)).ToArray() });
        return SpotCatalog.Parse(source).WithObserved(observed);
    }
    private static SpotCatalog SourceCatalog() => SpotCatalog.Parse(System.IO.File.ReadAllText(System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "spot_catalog.json")));
    private static SpotCatalog Fixture() => SpotCatalog.Parse(FixtureJson()).WithObserved(ObservedJson());
    private static string ObservedJson(bool verifySecond = true) => JsonSerializer.Serialize(new
    {
        schemaVersion = 1,
        spots = new[] { ObservedSpot("1", "Place A", "grinding", "TEST", ["1", "3", "4"], ["Unique A", "Common", "Shared"], true),
            ObservedSpot("2", "Place B", "lifeskill", "HUNTING SPOTS", ["2", "3", "4"], ["Unique B", "Common", "Shared"], verifySecond) },
    });
    private static object ObservedSpot(string id, string name, string category, string group, string[] drops, string[] names, bool verified) => new
    {
        siteId = id, name, sidebarCategory = category, sidebarGroup = group,
        artworkUrls = new[] { "https://assets.garmoth.com/img/1.webp" },
        verifiedSessionItemIds = verified ? drops : [],
        costItemIds = Array.Empty<string>(),
        sessionEvidence = verified ? new
        {
            kind = "rendered-history-item-columns", spotId = id, complete = true,
            capturedAt = "2026-09-14T12:00:00Z", captureSha256 = new string('A', 64),
            columns = drops.Select((itemId, index) => new { itemId, observedName = names[index], identityKind = "exact-client-name", role = "session-item" }).ToArray(),
        } : null,
    };
    private static string FixtureJson() => JsonSerializer.Serialize(new
    {
        schemaVersion = 1,
        items = new[]
        {
            new SpotItemDefinition("1", "Unique A", ["Collision"]), new SpotItemDefinition("2", "Unique B", ["Collision"]),
            new SpotItemDefinition("3", "Common", []), new SpotItemDefinition("4", "Shared", []),
            new SpotItemDefinition("5", "Known without source", []),
        },
        spots = new[]
        {
            new SpotDefinition("a", "Place A", "grinding", "test", "1", [], [], ["1","3","4"], ["3"], null),
            new SpotDefinition("b", "Place B", "hunting", "test", "2", [], [], ["2","3","4"], ["3"], null),
        },
    }, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException("Spot resolver: " + message);
    }
    private static void Throws(Action action)
    {
        try { action(); }
        catch (System.IO.InvalidDataException) { return; }
        throw new InvalidOperationException("Malformed spot catalog was accepted.");
    }
}
