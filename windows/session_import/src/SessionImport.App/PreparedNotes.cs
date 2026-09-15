using System.Text.Json.Nodes;

namespace BlackSpiritLife.SessionImport.App;

// Notes are accounted for separately from numeric loot columns. A response may
// only claim a Notes entry for the exact missing item that this draft supplied.
internal static class PreparedNotes
{
    internal static IReadOnlySet<int> VerifiedIndices(JsonObject response, JsonArray items)
    {
        var verified = new HashSet<int>();
        if (Text(response["notesStatus"]) != "verified" || response["notesVerified"] is not JsonArray entries
            || response["skipped"] is not JsonArray skipped || entries.Count > items.Count) return verified;
        foreach (var entry in entries)
        {
            if (entry is not JsonObject note || !Number(note["index"], out var rawIndex)
                || rawIndex < 0 || rawIndex >= items.Count || !verified.Add((int)rawIndex)) return new HashSet<int>();
            var item = items[(int)rawIndex];
            if (item is not JsonObject expected || Text(note["name"]) != Text(expected["name"])
                || !JsonNode.DeepEquals(note["itemId"], expected["itemId"])
                || !Number(note["subKey"], out var subKey) || !Number(expected["subKey"], out var expectedSubKey) || subKey != expectedSubKey
                || !Number(note["quantity"], out var quantity) || !Number(expected["quantity"], out var expectedQuantity)
                || quantity != expectedQuantity || quantity <= 0
                || skipped.Count(row => row is JsonObject missing && Number(missing["index"], out var index)
                    && index == rawIndex && Text(missing["reason"]) == "item_not_found") != 1)
                return new HashSet<int>();
        }
        return verified;
    }

    private static string? Text(JsonNode? node) => node is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;
    private static bool Number(JsonNode? node, out long number)
    {
        number = 0;
        if (node is not JsonValue value) return false;
        if (value.TryGetValue<long>(out number)) return true;
        if (!value.TryGetValue<int>(out var integer)) return false;
        number = integer;
        return true;
    }
}
