using System.Text.Json.Nodes;
using BlackSpiritLife.SessionImport;

// Negative checks for the independent test oracle, not production Notes logic.
internal static class ScreenshotNotesVerifierChecks
{
    internal static void Run(Action<string, Action> run)
    {
        var now = DateTimeOffset.UtcNow;
        var draft = new SessionDraft("notes-oracle-fixture", now, now.AddMinutes(5), "186", "Rusalka's Coral", "gathering", 3600,
            [new("4001", 0, "Rough Stone", 1005), new("6511", 0, "Lobster", 38)], AgrisActive: false);
        var expected = new[] { draft.Items[1] };
        JsonObject Valid() => new()
        {
            ["notesStatus"] = "verified",
            ["notesVerified"] = new JsonArray(new JsonObject { ["index"] = 1, ["itemId"] = "6511", ["subKey"] = 0, ["name"] = "Lobster", ["quantity"] = 38L }),
            ["skipped"] = new JsonArray(new JsonObject { ["index"] = 1, ["itemId"] = "6511", ["subKey"] = 0, ["reason"] = "item_not_found" })
        };
        run("screenshot Notes oracle accepts only exact expected missing-item identity and quantity", () =>
            Require(LiveScreenshotPreparationChecks.NotesProtocolMatches(Valid(), draft, expected)));
        run("screenshot Notes oracle rejects changed quantity", () =>
        {
            var response = Valid(); response["notesVerified"]![0]!["quantity"] = 39;
            Require(!LiveScreenshotPreparationChecks.NotesProtocolMatches(response, draft, expected));
        });
        run("screenshot Notes oracle rejects remapped identity or row index", () =>
        {
            var response = Valid(); response["notesVerified"]![0]!["index"] = 0;
            Require(!LiveScreenshotPreparationChecks.NotesProtocolMatches(response, draft, expected));
            response = Valid(); response["notesVerified"]![0]!["itemId"] = "4001";
            Require(!LiveScreenshotPreparationChecks.NotesProtocolMatches(response, draft, expected));
        });
        run("screenshot Notes oracle never counts a rejected numeric write as unsupported loot", () =>
        {
            var response = Valid(); response["skipped"]![0]!["reason"] = "value_not_accepted";
            Require(!LiveScreenshotPreparationChecks.NotesProtocolMatches(response, draft, expected));
        });
        run("screenshot Notes oracle requires no extra missing rows or Notes in all-structured cases", () =>
        {
            Require(!LiveScreenshotPreparationChecks.NotesProtocolMatches(Valid(), draft, []));
            Require(LiveScreenshotPreparationChecks.NotesProtocolMatches(new JsonObject
                { ["notesStatus"] = "not_needed", ["notesVerified"] = new JsonArray(), ["skipped"] = new JsonArray() }, draft, []));
        });
    }

    private static void Require(bool condition)
    {
        if (!condition) throw new InvalidOperationException("Independent screenshot Notes oracle did not reject an inconsistent response.");
    }
}
