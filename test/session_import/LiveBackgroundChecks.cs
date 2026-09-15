using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using BlackSpiritLife.SessionImport;
using BlackSpiritLife.SessionImport.App;
using Microsoft.Web.WebView2.Core;

// Explicit, opt-in live diagnostic of the application's OWN browser integration.
// Uses the normal remembered-connection preference, never copies/extracts login
// material, never foregrounds a window and never invokes Garmoth's final Save.
internal static class LiveBackgroundChecks
{
    internal static async Task RunAsync(string evidence, bool prepare, bool inspectForm = false)
    {
        Directory.CreateDirectory(evidence);
        var preferences = new GarmothConnectionPreferences();
        if (!preferences.RememberConnection)
            throw new InvalidOperationException("Live background check needs an already opted-in remembered app connection. No preference was changed.");
        var service = new EmbeddedGarmothBrowser(preferences);
        var decisions = new List<string>();
        service.NavigationDiagnostic = decisions.Add;
        try
        {
            await service.OpenForPreparationAsync();
            var core = service.CurrentCore ?? throw new InvalidOperationException("The app browser did not initialize.");
            var navigation = new List<string>();
            core.NavigationStarting += (_, args) => navigation.Add(new Uri(args.Uri).AbsolutePath + " cancel=" + args.Cancel);
            await CaptureAsync(core, evidence, "opened");
            await Task.Delay(2500);
            await CaptureAsync(core, evidence, "settled");
            if (prepare)
            {
                var now = DateTimeOffset.UtcNow;
                var names = new (string, long)[] {
                    ("Dim Heartvein Shard",26),("Rusalka's Coral",59),("Sharp Black Crystal Shard",8),
                    ("Black Gem Fragment",52),("Lobster",38),("Cracked Terrashard",2),
                    ("Ancient Spirit Dust",37),("Rough Stone",1005),("Fairy's Breath",162),
                    ("Caphras Stone",3),("Coral Piece",413),("Fairy Powder",132),
                    ("Fruit of Nature",4),("Blue Coral",5),("Rough Translucent Crystal",5),("Rough Blue Crystal",6)
                };
                // Values transcribed from the user-provided example. Duration is
                // an UNSAVED test value, not a claim about the real session.
                var catalog = ItemCatalog.Load();
                var items = names.Select(entry => new SessionItem(catalog.Match(entry.Item1)?.ItemId,
                    0, entry.Item1, entry.Item2)).ToArray();
                var draft = new SessionDraft("live-unsaved-" + Guid.NewGuid().ToString("N"), now,
                    now.AddMinutes(10), "", "Rusalka's Coral", "gathering", 3600, items,
                    AgrisActive: false, AdditionalDropRate: 0, AdditionalDropAmount: 0);
                var response = await service.SendAsync(draft.ToPrepareMessage(), TimeSpan.FromSeconds(45));
                await File.WriteAllTextAsync(Path.Combine(evidence, "prepare-result.json"), response.ToJsonString(new() { WriteIndented = true }));
                await CaptureAsync(core, evidence, "after-prepare");
                await Task.Delay(3500);
                await CaptureAsync(core, evidence, "after-settled");
                if (inspectForm) await InspectFormControlsAsync(core, evidence);
                await File.WriteAllTextAsync(Path.Combine(evidence, "navigation.json"), JsonSerializer.Serialize(navigation));
                await File.WriteAllTextAsync(Path.Combine(evidence, "decisions.json"), JsonSerializer.Serialize(decisions));
                if (response["ok"]?.GetValue<bool>() != true && response["message"]?.GetValue<string>()?.Contains("No matching rendered link") == true)
                {
                    response = await service.SendAsync(draft.ToPrepareMessage(), TimeSpan.FromSeconds(45));
                    await File.WriteAllTextAsync(Path.Combine(evidence, "settled-retry-result.json"), response.ToJsonString(new() { WriteIndented = true }));
                    await Task.Delay(1000);
                    await CaptureAsync(core, evidence, "settled-retry");
                }
                Console.WriteLine("Live UNSAVED preparation response: " + response.ToJsonString());
            }
            Console.WriteLine("Background evidence captured. No final Save, native input or foreground activation was requested.");
        }
        finally { await service.CloseAsync(); }
    }

    private static async Task InspectFormControlsAsync(CoreWebView2 core, string evidence)
    {
        await core.ExecuteScriptAsync("""
          window.__bslFormControlInspection = null;
          (async()=>{
            if(!/\/spot\/186\/?$/.test(location.pathname)||![...document.querySelectorAll('h1')].some(e=>e.textContent.trim()==="Rusalka's Coral"))return{blocked:true};
            const table=[...document.querySelectorAll('table')].find(t=>/hours/i.test(t.tHead?.innerText||'')&&/mins/i.test(t.tHead?.innerText||''));
            if(!table||table.tBodies.length!==1||table.tBodies[0].rows.length!==1)return{blocked:true};
            const pause=ms=>new Promise(r=>setTimeout(r,ms));
            const result={};
            const inspect=async(th,key)=>{
              if(!th)return;
              th.dispatchEvent(new MouseEvent('mouseover',{bubbles:true}));th.dispatchEvent(new MouseEvent('mouseenter',{bubbles:false}));
              await pause(450);
              result[key]=[...document.querySelectorAll('[role=tooltip],.v-popper__popper')].filter(e=>e.getClientRects().length&&getComputedStyle(e).visibility!=='hidden').map(e=>({text:e.textContent,html:e.outerHTML.slice(0,12000)}));
              th.dispatchEvent(new MouseEvent('mouseout',{bubbles:true}));th.dispatchEvent(new MouseEvent('mouseleave',{bubbles:false}));await pause(150);
            };
            await inspect([...table.tHead.rows[0].cells].find(c=>c.textContent.trim()==='Agris'),'agris');
            await inspect([...table.tHead.rows[0].cells].find(c=>c.querySelector('img')?.src.includes('000820014')),'fairy');
            const used=[...document.querySelectorAll('p')].filter(p=>p.textContent.trim()==='Used Agris');
            const agris=[...table.tHead.rows[0].cells].find(c=>c.textContent.trim()==='Agris');
            if(used.length===1&&agris){
              const row=used[0].parentElement;
              result.agrisBefore={row:row.outerHTML,header:agris.outerHTML};
              row.click();await pause(200);
              result.agrisAfter={row:row.outerHTML,header:agris.outerHTML};
              row.click();await pause(200);
            }
            let ancestor=table.parentElement;result.formAncestors=[];
            for(let n=0;ancestor&&ancestor!==document.body&&n<9;n++,ancestor=ancestor.parentElement)
              result.formAncestors.push({tag:ancestor.tagName,class:ancestor.className,prefix:ancestor.outerHTML.slice(0,2000)});
            const last=[...table.tHead.rows[0].cells].at(-1);
            if(last.tagName==='TH'&&last.classList.contains('cursor-pointer')&&!last.textContent.trim()&&!last.querySelector('img,input,button')){
              last.dispatchEvent(new MouseEvent('mouseover',{bubbles:true}));last.dispatchEvent(new MouseEvent('mouseenter',{bubbles:false}));await pause(250);
              result.addHeader=last.outerHTML;
              last.click();await pause(400);
              result.pickers=[...document.querySelectorAll('input')].filter(e=>e.getClientRects().length&&(e.type==='search'||/search/i.test(e.placeholder))).map(e=>({placeholder:e.placeholder,html:e.parentElement.parentElement.outerHTML.slice(0,85000)}));
            }
            const overlay=table.closest('div.fixed');
            const closes=overlay?[...overlay.querySelectorAll('svg[viewBox="0 0 24 24"]')].filter(s=>s.querySelector('path')?.getAttribute('d')==='M19 6.41L17.59 5L12 10.59L6.41 5L5 6.41L10.59 12L5 17.59L6.41 19L12 13.41L17.59 19L19 17.59L13.41 12z'):[];
            if(closes.length===1&&closes[0].closest('div')?.classList.contains('absolute')){
              closes[0].closest('div').click();await pause(350);
              result.toolbar=[];
              for(const button of [...document.querySelectorAll('main button')].filter(b=>!b.closest('#grind-menu')&&!b.textContent.trim()&&b.getClientRects().length).slice(0,10)){
                const key='toolbar-'+result.toolbar.length;await inspect(button,key);result.toolbar.push({key,html:button.outerHTML});
              }
            }
            return result;
          })().then(result=>window.__bslFormControlInspection=result, error=>window.__bslFormControlInspection={error:String(error)});
          """);
        string result = "null";
        for(var attempt=0;attempt<30&&result=="null";attempt++)
        {
            await Task.Delay(200);
            result = await core.ExecuteScriptAsync("window.__bslFormControlInspection");
        }
        await File.WriteAllTextAsync(Path.Combine(evidence, "form-controls.json"), result);
        await CaptureAsync(core, evidence, "form-picker");
    }

    private static async Task CaptureAsync(CoreWebView2 core, string evidence, string name)
    {
        // Only rendered navigation/form structure is collected. No page globals,
        // network payloads, storage, cookies, passwords or account profile fields.
        const string inspect = """
        (() => {
          const visible=e=>!!e.getClientRects().length && getComputedStyle(e).visibility!=='hidden';
          const attrs=e=>Object.fromEntries(['id','role','type','name','aria-label','aria-labelledby','aria-pressed','aria-checked','aria-expanded','placeholder','headers','colspan','rowspan','data-item-id','disabled','readonly'].filter(k=>e.hasAttribute(k)).map(k=>[k,e.getAttribute(k)]));
          const text=e=>(e.innerText||e.textContent||'').trim().replace(/\s+/g,' ').slice(0,180);
          const control=e=>({tag:e.tagName,...attrs(e),text: e.matches('input')?'':text(e),images:[...e.querySelectorAll('img')].map(i=>({src:i.getAttribute('src'),alt:i.alt})),rect: e.getBoundingClientRect().toJSON()});
          return {
            path:location.pathname, title:document.title,
            sidebar:document.getElementById('grind-menu')?.outerHTML?.slice(0,160000),
            sidebarContext:(()=>{let m=document.getElementById('grind-menu');return m?{ancestors:[m.parentElement,m.parentElement?.parentElement,m.parentElement?.parentElement?.parentElement].filter(Boolean).map(e=>({tag:e.tagName,id:e.id})),rect:m.querySelector('aside')?.getBoundingClientRect().toJSON()}:null})(),
            entryForm:(()=>{
              const table=[...document.querySelectorAll('table')].find(t=>/hours/i.test(t.tHead?.innerText||'') && /mins|minutes/i.test(t.tHead?.innerText||''));
              if(!table)return null;
              const ancestors=[];let current=table.parentElement;
              for(let n=0;current && current!==document.body && n<9;n++,current=current.parentElement){
                const saves=[...current.querySelectorAll('button')].filter(b=>/^save(?: session)?$/i.test(text(b)));
                ancestors.push({tag:current.tagName,...attrs(current),class:current.className,saveCount:saves.length});
                if(saves.length===1 && !current.querySelector('header,input[type=password],input[type=email]'))
                  return {ancestors,html:current.outerHTML.slice(0,240000)};
              }return{ancestors};
            })(),
            entryValues:(()=>{
              const table=[...document.querySelectorAll('table')].find(t=>/hours/i.test(t.tHead?.innerText||'') && /mins|minutes/i.test(t.tHead?.innerText||''));
              if(!table||table.tBodies[0]?.rows.length!==1)return null;
              return [...table.tHead.rows[0].cells].map((h,i)=>({label:text(h),images:[...h.querySelectorAll('img')].map(img=>img.getAttribute('src')),values:[...table.tBodies[0].rows[0].cells[i].querySelectorAll('input')].map(input=>input.value)}));
            })(),
            headings:[...document.querySelectorAll('h1,h2,h3,h4')].filter(visible).map(control),
            nav:[...document.querySelectorAll('a[href]')].filter(visible).filter(e=>{try{return new URL(e.href).pathname.startsWith('/grind-tracker')}catch{return false}}).map(e=>({...control(e),href:e.getAttribute('href'),parent:e.parentElement.tagName,parentRole:e.parentElement.getAttribute('role')})),
            actions:[...document.querySelectorAll('button,[role=button]')].filter(visible).filter(e=>!e.closest('header')).map(control),
            tables:[...document.querySelectorAll('table')].filter(visible).map(t=>({attrs:attrs(t),ancestors:[t.parentElement,t.parentElement.parentElement,t.parentElement.parentElement?.parentElement].filter(Boolean).map(e=>({tag:e.tagName,...attrs(e)})),rows:[...t.rows].map(r=>[...r.cells].map(c=>({tag:c.tagName,...attrs(c),text:text(c),images:[...c.querySelectorAll('img')].map(i=>({src:i.getAttribute('src'),alt:i.alt})),controls:[...c.querySelectorAll('input,button,[role=switch],[role=checkbox]')].map(control)})))})),
            dialogs:[...document.querySelectorAll('[role=dialog],dialog')].filter(visible).map(e=>({tag:e.tagName,...attrs(e),heading:[...e.querySelectorAll('h1,h2,h3,h4')].map(text),inputs:[...e.querySelectorAll('input:not([type=password]),select')].map(control)}))
          };
        })()
        """;
        var result = JsonNode.Parse(await core.ExecuteScriptAsync(inspect));
        await File.WriteAllTextAsync(Path.Combine(evidence, name + "-structure.json"), result?.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) ?? "null");
        await using var capture = File.Create(Path.Combine(evidence, name + ".png"));
        await core.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, capture);
    }
}
