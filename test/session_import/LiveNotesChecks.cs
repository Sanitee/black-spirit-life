using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using BlackSpiritLife.SessionImport;
using BlackSpiritLife.SessionImport.App;
using Microsoft.Web.WebView2.Core;

// Explicit, unsaved inspection of the real Notes control in the app-owned
// background connection. No browser profile copying, native input, or Save.
internal static class LiveNotesChecks
{
    internal static async Task InspectAsync(string evidence, bool exercise = false)
    {
        if (Directory.Exists(evidence) && Directory.EnumerateFileSystemEntries(evidence).Any())
            throw new InvalidOperationException("Use a fresh evidence directory.");
        Directory.CreateDirectory(evidence);
        var preferences = new GarmothConnectionPreferences();
        if (!preferences.RememberConnection) throw new InvalidOperationException("An existing opted-in app connection is required.");
        var service = new EmbeddedGarmothBrowser(preferences);
        var report = new JsonObject { ["unsavedSyntheticSession"] = true };
        var activated = 0;
        try
        {
            var opening = service.OpenForPreparationAsync();
            if (service.CurrentWindow is { } window) window.Activated += (_, _) => activated++;
            await opening;
            LiveMultiSpotChecks.CheckBackground(service);
            var core = service.CurrentCore ?? throw new InvalidOperationException("Background browser unavailable.");
            await core.AddScriptToExecuteOnDocumentCreatedAsync(LiveMultiSpotChecks.SaveGuard);
            await core.ExecuteScriptAsync(LiveMultiSpotChecks.SaveGuard);
            var now = DateTimeOffset.UtcNow;
            var catalog = SpotCatalog.Load();
            var names = new (string Name, long Quantity)[] {
                ("Rusalka's Coral",59), ("Rough Stone",1005), ("Lobster",38),
                ("Cracked Terrashard",2), ("Blue Coral",5)
            };
            var items = names.Select(item => new SessionItem(catalog.MatchItem(item.Name)?.Id, 0, item.Name, item.Quantity)).ToArray();
            var draft = new SessionDraft("unsaved-notes-inspection-" + Guid.NewGuid().ToString("N"),now,now.AddMinutes(5),
                "186","Rusalka's Coral","gathering",3600,items,AgrisActive:false);
            report["response"] = await service.SendAsync(draft.ToPrepareMessage(),TimeSpan.FromSeconds(45));
            LiveMultiSpotChecks.CheckBackground(service);
            report["before"] = JsonNode.Parse(await core.ExecuteScriptAsync(InspectPanel));
            if (report["before"]?["headerCount"]?.GetValue<int>() != 1)
                throw new InvalidOperationException("Unique Notes header not found in the verified Add session form.");
            await core.ExecuteScriptAsync(FindPanel + "const p=find();if(p&&!p.querySelector('textarea,input,[contenteditable=true]'))p.firstElementChild.click();return !!p;})()");
            await Task.Delay(350);
            report["expanded"] = JsonNode.Parse(await core.ExecuteScriptAsync(InspectPanel));
            report["saveGuard"] = JsonNode.Parse(await core.ExecuteScriptAsync("window.__bslMultiSpotNoSave"));
            LiveMultiSpotChecks.CheckBackground(service);
            await using var image = File.Create(Path.Combine(evidence,"notes-expanded.png"));
            await core.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png,image);
            if (exercise)
            {
                const string start = "[BS Life: not included in Garmoth totals]\n";
                const string end = "\n[/BS Life]\n";
                const string prefix = "My synthetic test note — keep this.\n\n";
                const string suffix = "\nKeep this final line too.\n";
                var originalBlock = start + "Lobster × 38\nCracked Terrashard × 2\nBlue Coral × 5" + end;
                var initial = await ReadNotesAsync(core);
                if (initial != originalBlock) throw new InvalidOperationException("Initial Notes do not exactly match the expected app block; no existing text was changed.");
                report["initialNotesExactlyVerified"] = true;
                await SetNotesAsync(core, prefix + initial + suffix);
                // Normal read-only status reinjects the helper; ownership must
                // survive it, not merely repeated calls into one JS closure.
                await service.SendAsync(new JsonObject { ["type"]="status", ["protocolVersion"]=1 },TimeSpan.FromSeconds(10));
                var revised = draft with { DraftId="unsaved-notes-repeat-" + Guid.NewGuid().ToString("N"),
                    Items=draft.Items.Select(item=>item.Name=="Lobster" ? item with { Quantity=39 } : item).ToArray() };
                var repeated = await service.SendAsync(revised.ToPrepareMessage(),TimeSpan.FromSeconds(45));
                var afterRepeat = await ReadNotesAsync(core);
                var expectedRepeat = prefix + start + "Lobster × 39\nCracked Terrashard × 2\nBlue Coral × 5" + end + suffix;
                report["repeatedResponse"] = repeated;
                report["repeatedNotesExactlyVerified"] = afterRepeat == expectedRepeat;
                if (repeated["ok"]?.GetValue<bool>() != true || afterRepeat != expectedRepeat
                    || PreparedNotes.VerifiedIndices(repeated,(JsonArray)revised.ToPrepareMessage()["draft"]!["session"]!["items"]!).Count != 3)
                    throw new InvalidOperationException("Reprepare did not preserve user text and replace exactly one app block.");
                LiveMultiSpotChecks.CheckBackground(service);
                var supportedOnly = revised with { DraftId="unsaved-notes-clear-" + Guid.NewGuid().ToString("N"), Items=revised.Items.Take(2).ToArray() };
                var cleared = await service.SendAsync(supportedOnly.ToPrepareMessage(),TimeSpan.FromSeconds(45));
                var afterClear = await ReadNotesAsync(core);
                report["clearResponse"] = cleared;
                report["userNotesPreservedAfterAppBlockRemoval"] = afterClear == prefix + suffix;
                if (cleared["ok"]?.GetValue<bool>() != true || afterClear != prefix + suffix)
                    throw new InvalidOperationException("Removing unsupported loot did not remove only the app-owned Notes block.");
                report["finalReadback"] = await LiveMultiSpotChecks.ReadBackAsync(core,supportedOnly,CancellationToken.None);
                report["saveGuard"] = JsonNode.Parse(await core.ExecuteScriptAsync("window.__bslMultiSpotNoSave"));
                if (report["saveGuard"]?["saveAttempts"]?.GetValue<int>() != 0 || report["saveGuard"]?["submitAttempts"]?.GetValue<int>() != 0 || activated != 0)
                    throw new InvalidOperationException("Background no-Save invariants failed.");
                LiveMultiSpotChecks.CheckBackground(service);
                report["status"] = "passed";
            }
        }
        finally
        {
            report["ownedActivationEvents"] = activated;
            await service.CloseAsync();
            report["ownedBrowserClosed"] = service.CurrentWindow is null;
            await File.WriteAllTextAsync(Path.Combine(evidence,"notes-inspection.json"),report.ToJsonString(new JsonSerializerOptions { WriteIndented=true }));
        }
    }

    private static async Task<string?> ReadNotesAsync(CoreWebView2 core) =>
        JsonNode.Parse(await core.ExecuteScriptAsync(FindPanel + "const p=find();const fields=p?[...p.querySelectorAll('textarea[placeholder=Notes]')]:[];return fields.length===1?fields[0].value:null;})()"))?.GetValue<string>();

    private static async Task SetNotesAsync(CoreWebView2 core, string text)
    {
        var result = JsonNode.Parse(await core.ExecuteScriptAsync(FindPanel + "const p=find();const fields=p?[...p.querySelectorAll('textarea[placeholder=Notes]')]:[];if(fields.length!==1)return false;const e=fields[0];Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,'value').set.call(e," + JsonSerializer.Serialize(text) + ");e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));return true;})()"));
        if (result?.GetValue<bool>() != true) throw new InvalidOperationException("Unique rendered Notes field unavailable.");
        await Task.Delay(100);
        if (await ReadNotesAsync(core) != text) throw new InvalidOperationException("Synthetic user note was not accepted.");
    }

    internal const string FindPanel = """
        (()=>{
          const find=()=>{
            if(!/\/spot\/186\/?$/.test(location.pathname)||![...document.querySelectorAll('h1')].some(e=>e.textContent.trim()==="Rusalka's Coral"))return null;
            const tables=[...document.querySelectorAll('table')].filter(t=>/hours/i.test(t.tHead?.textContent||'')&&/mins/i.test(t.tHead?.textContent||'')&&t.tBodies.length===1&&t.tBodies[0].rows.length===1);
            if(tables.length!==1)return null;
            let root=tables[0].parentElement;
            while(root&&root!==document.body){
              const saves=[...root.querySelectorAll('button')].filter(b=>/^save(?: session)?$/i.test(b.textContent.trim()));
              const labels=[...root.querySelectorAll('span')].filter(s=>s.textContent.trim()==='Notes'&&s.parentElement.classList.contains('cursor-pointer'));
              if(saves.length===1&&labels.length===1)return labels[0].parentElement.parentElement;
              root=root.parentElement;
            }return null;
          };
        """;
    internal const string InspectPanel = FindPanel + """
          const p=find();return{headerCount:p?1:0,panelHtml:p?.outerHTML,
            fields:p?[...p.querySelectorAll('textarea,input,[contenteditable=true]')].map(e=>({tag:e.tagName,type:e.type,placeholder:e.getAttribute('placeholder'),maxLength:e.maxLength,valueLength:(e.value||e.textContent||'').length})):[]};})()
        """;
}
