using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using BlackSpiritLife.SessionImport.App;
using Microsoft.Web.WebView2.Core;

// Explicit opt-in live READ ONLY catalog inspection. Never calls Send/Prepare,
// clicks controls, opens Add, reads session rows, or accesses auth/storage APIs.
internal static class LiveSpotDropHarvestChecks
{
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();
    private sealed record ObservedSpot(string Url, string Id, string Name, string Category, string? Group);
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private static readonly Regex SpotPath = new(@"^/grind-tracker/[^/]+/spot/(?<id>[1-9][0-9]*)/?$", RegexOptions.CultureInvariant);

    internal static async Task RunNavigationDiagnosticAsync(string taskEvidenceRoot, string outputDirectory)
    {
        var spot = LoadObservedSpots(taskEvidenceRoot).Spots.Single(spot => spot.Id == "64");
        if (Directory.Exists(outputDirectory) && Directory.EnumerateFileSystemEntries(outputDirectory).Any())
            throw new InvalidOperationException("Use a fresh diagnostic output directory.");
        Directory.CreateDirectory(outputDirectory);
        var preferences = new GarmothConnectionPreferences();
        if (!preferences.RememberConnection) throw new InvalidOperationException("The existing remembered app connection is required; no preference was changed.");
        var foreground = GetForegroundWindow();
        var service = new EmbeddedGarmothBrowser(preferences);
        var record = BaseRecord(spot);
        var events = new JsonArray();
        record["diagnosticOnly"] = true;
        record["automaticallyVerified"] = false;
        record["navigationEvents"] = events;
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(60));
        try
        {
            await service.OpenForPreparationAsync().WaitAsync(cancellation.Token);
            CheckBackground(service, foreground, requireUnchanged: true);
            var core = service.CurrentCore!;
            ulong? targetNavigationId = null;
            var rateLimited = false;
            core.NavigationStarting += (_, args) =>
            {
                if (args.Uri == spot.Url && targetNavigationId is null) targetNavigationId = args.NavigationId;
                events.Add(new JsonObject { ["event"] = "starting", ["navigationId"] = args.NavigationId,
                    ["exactObservedDestination"] = args.Uri == spot.Url, ["cancelled"] = args.Cancel });
            };
            core.NavigationCompleted += (_, args) => events.Add(new JsonObject
            {
                ["event"] = "completed", ["navigationId"] = args.NavigationId, ["matchesTargetId"] = args.NavigationId == targetNavigationId,
                ["isSuccess"] = args.IsSuccess, ["webErrorStatus"] = args.WebErrorStatus.ToString(), ["httpStatusCode"] = args.HttpStatusCode
            });
            core.WebResourceResponseReceived += (_, args) =>
            {
                if (args.Request.Uri != spot.Url) return;
                record["mainDocumentHttpStatus"] = args.Response.StatusCode;
                if (args.Response.StatusCode == 429) { rateLimited = true; cancellation.Cancel(); }
            };
            try { await NavigateExactAsync(core, spot.Url, cancellation.Token); record["navigateGuardPassed"] = true; }
            catch (HarvestPageException error) { record["navigateGuardPassed"] = false; record["nativeFailure"] = error.Message; }
            if (!rateLimited)
            {
                await Task.Delay(3000, cancellation.Token);
                record["exactSourceAfterSettling"] = core.Source == spot.Url;
                if (core.Source == spot.Url)
                {
                    record["publicHeaderStructure"] = JsonNode.Parse(await core.ExecuteScriptAsync(InspectHeaders).WaitAsync(cancellation.Token));
                    record["publicErrorMarkers"] = JsonNode.Parse(await core.ExecuteScriptAsync("""
                        (()=>{
                          const value=(document.body?.innerText||'').toLowerCase();
                          return {notFound:/\b404\b|page (?:was |is )?not found|could(?:n't| not) find (?:this |the )?page/.test(value),
                            serverError:/\b50[0234]\b|internal server error|bad gateway|service unavailable/.test(value),
                            rateLimited:/\b429\b|too many requests|rate limit exceeded/.test(value),
                            challenge:/verify (?:that )?you are human|checking your browser|just a moment/.test(value)};
                        })()
                        """).WaitAsync(cancellation.Token));
                }
            }
            record["rateLimitDetected"] = rateLimited;
            record["externalForegroundChangeObserved"] = CheckBackground(service, foreground);
            record["noSaveOrFormMutation"] = true;
        }
        finally
        {
            await service.CloseAsync();
            record["ownBrowserClosed"] = true;
            await WriteAsync(Path.Combine(outputDirectory, "spot-64-navigation-diagnostic.json"), record);
        }
        Console.WriteLine("Spot64 diagnostic finished; native failure and public structure preserved without automatic verification or any form action.");
    }

    internal static async Task RunAsync(string taskEvidenceRoot, string outputDirectory, string? selectedSpotId = null)
    {
        var inputs = LoadObservedSpots(taskEvidenceRoot);
        if (inputs.Spots.Count != 174) throw new InvalidOperationException("Expected exactly 174 distinct observed spot destinations; review the saved sidebar inputs first.");
        var selectedIds = selectedSpotId?.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries).ToHashSet(StringComparer.Ordinal);
        var selected = selectedIds is null ? inputs.Spots : inputs.Spots.Where(spot => selectedIds.Contains(spot.Id)).ToList();
        if (selected.Count == 0 || (selectedIds is not null && selected.Count != selectedIds.Count))
            throw new InvalidOperationException("A requested spot ID was not present in the captured sidebar links.");
        outputDirectory = Path.GetFullPath(outputDirectory);
        if (Directory.Exists(outputDirectory) && Directory.EnumerateFileSystemEntries(outputDirectory).Any())
            throw new InvalidOperationException("Use a fresh output directory; prior harvest evidence must remain unchanged.");
        Directory.CreateDirectory(outputDirectory);
        await WriteAsync(Path.Combine(outputDirectory, "input-proof.json"), new JsonObject
        {
            ["observedSpots"] = inputs.Spots.Count, ["sources"] = inputs.Proof,
            ["selectedForThisRun"] = selected.Count,
            ["urlsReconstructed"] = false, ["accountIdentifiersExported"] = false
        });
        var preferences = new GarmothConnectionPreferences();
        if (!preferences.RememberConnection)
            throw new InvalidOperationException("An already opted-in remembered app connection is required. No preference was changed.");
        var foreground = GetForegroundWindow();
        var service = new EmbeddedGarmothBrowser(preferences);
        var results = new JsonArray();
        var externalForegroundChangeObserved = false;
        using var lifetime = new CancellationTokenSource(TimeSpan.FromMinutes(20));
        try
        {
            await service.OpenForPreparationAsync().WaitAsync(lifetime.Token);
            CheckBackground(service, foreground, requireUnchanged: true);
            var core = service.CurrentCore ?? throw new InvalidOperationException("The app-owned browser did not initialize.");
            core.WebResourceResponseReceived += (_, args) =>
            {
                if (args.Response.StatusCode == 429 && Uri.TryCreate(args.Request.Uri, UriKind.Absolute, out var uri) &&
                    uri.Scheme == "https" && uri.Host == "garmoth.com" && SpotPath.IsMatch(uri.AbsolutePath))
                {
                    Console.Error.WriteLine("Harvest stopped: an observed Garmoth spot request returned HTTP 429. No further requests will be retried.");
                    lifetime.Cancel();
                }
            };
            var pace = Stopwatch.StartNew();
            foreach (var spot in selected)
            {
                lifetime.Token.ThrowIfCancellationRequested();
                if (pace.ElapsedMilliseconds < 1000) await Task.Delay((int)(1000 - pace.ElapsedMilliseconds), lifetime.Token);
                externalForegroundChangeObserved |= CheckBackground(service, foreground);
                pace.Restart();
                using var pageTimeout = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
                pageTimeout.CancelAfter(TimeSpan.FromSeconds(45));
                var pageElapsed = Stopwatch.StartNew();
                JsonObject record;
                try
                {
                    await NavigateExactAsync(core, spot.Url, pageTimeout.Token);
                    var structure = await WaitForHeadersAsync(core, spot, pageTimeout.Token);
                    await ReadTooltipNamesAsync(core, spot, structure, pageTimeout.Token);
                    record = BaseRecord(spot);
                    record["status"] = "verified_header_structure";
                    record["rawImageKeys"] = structure["rawImageKeys"]!.DeepClone();
                    record["itemIdentitiesVerified"] = false;
                    record["headerImages"] = structure["headerImages"]!.DeepClone();
                    record["tooltipObservations"] = structure["tooltipObservations"]!.DeepClone();
                    record["structure"] = structure;
                    record["observedUtc"] = DateTimeOffset.UtcNow.ToString("O");
                    record["elapsedMilliseconds"] = pageElapsed.ElapsedMilliseconds;
                }
                catch (OperationCanceledException) when (!lifetime.IsCancellationRequested)
                {
                    record = BaseRecord(spot);
                    record["status"] = "unverified";
                    record["reason"] = "The exact title, stable history headers and bounded tooltip inspection did not complete within 45 seconds.";
                }
                catch (HarvestPageException error)
                {
                    record = BaseRecord(spot);
                    record["status"] = "unverified";
                    record["reason"] = error.Message; // Only fixed, sanitized messages are used below.
                }
                externalForegroundChangeObserved |= CheckBackground(service, foreground);
                results.Add(record);
                await WriteAsync(Path.Combine(outputDirectory, "spot-" + spot.Id + ".json"), record);
                await WriteReportAsync(outputDirectory, results, selected.Count, false, externalForegroundChangeObserved);
                Console.WriteLine($"Harvest {results.Count}/{selected.Count}: spot {spot.Id} {record["status"]}");
            }
            await WriteReportAsync(outputDirectory, results, selected.Count, true, externalForegroundChangeObserved);
        }
        finally
        {
            await service.CloseAsync();
            await WriteReportAsync(outputDirectory, results, selected.Count, results.Count == selected.Count, externalForegroundChangeObserved);
        }
    }

    // The URLs are resolved only from literal saved hrefs against their known
    // HTTPS origin; no account path or spot route is synthesized.
    private static (List<ObservedSpot> Spots, JsonArray Proof) LoadObservedSpots(string evidence)
    {
        var spots = new Dictionary<string, ObservedSpot>(StringComparer.Ordinal);
        var proof = new JsonArray();
        foreach (var input in new[] { ("live-second/after-settled-structure.json", "Grinding"), ("live-fourth/after-settled-structure.json", "Lifeskill") })
        {
            var path = Path.Combine(evidence, input.Item1.Replace('/', Path.DirectorySeparatorChar));
            var bytes = File.ReadAllBytes(path);
            var html = JsonNode.Parse(bytes)?["sidebar"]?.GetValue<string>() ?? throw new InvalidOperationException("Saved sidebar HTML is missing.");
            var groups = Regex.Matches(html, "<div\\b[^>]*class=\"[^\"]*uppercase[^\"]*\"[^>]*>(?<name>[^<]+)</div>", RegexOptions.CultureInvariant);
            var count = 0;
            foreach (Match anchor in Regex.Matches(html, "<a\\b[^>]*href=\"(?<href>[^\"]+)\"[^>]*>(?<body>.*?)</a>", RegexOptions.Singleline | RegexOptions.CultureInvariant))
            {
                var href = WebUtility.HtmlDecode(anchor.Groups["href"].Value);
                if (!Uri.TryCreate(new Uri("https://garmoth.com"), href, out var uri)) continue;
                var route = SpotPath.Match(uri.AbsolutePath);
                if (!route.Success) continue;
                if (uri.Scheme != "https" || uri.Host != "garmoth.com" || !uri.IsDefaultPort || uri.UserInfo.Length != 0 || uri.Query.Length != 0 || uri.Fragment.Length != 0)
                    throw new InvalidOperationException("An observed spot link has an unsupported origin or suffix.");
                var label = Regex.Match(anchor.Groups["body"].Value, "<span\\b[^>]*class=\"[^\"]*cut-text[^\"]*\"[^>]*>(?<name>.*?)</span>", RegexOptions.Singleline | RegexOptions.CultureInvariant);
                if (!label.Success) throw new InvalidOperationException("A spot link has no unambiguous captured label.");
                var name = Normalize(WebUtility.HtmlDecode(Regex.Replace(label.Groups["name"].Value, "<[^>]*>", string.Empty)));
                if (name.Length is 0 or > 180) throw new InvalidOperationException("A captured spot name is empty or oversized.");
                var group = groups.LastOrDefault(candidate => candidate.Index < anchor.Index);
                var item = new ObservedSpot(uri.AbsoluteUri, route.Groups["id"].Value, name, input.Item2,
                    group is null ? null : Normalize(WebUtility.HtmlDecode(group.Groups["name"].Value)));
                if (spots.TryGetValue(item.Url, out var duplicate) && duplicate.Name != item.Name)
                    throw new InvalidOperationException("A repeated observed URL has conflicting spot names.");
                spots.TryAdd(item.Url, item);
                count++;
            }
            proof.Add(new JsonObject { ["file"] = input.Item1, ["sha256"] = Convert.ToHexString(SHA256.HashData(bytes)), ["category"] = input.Item2, ["observedLinks"] = count });
        }
        if (spots.Values.GroupBy(spot => spot.Id).Any(group => group.Count() != 1))
            throw new InvalidOperationException("Distinct observed destinations share a spot ID; review before exporting a public catalog.");
        return (spots.Values.OrderBy(spot => int.Parse(spot.Id, CultureInfo.InvariantCulture)).ToList(), proof);
    }

    private static async Task NavigateExactAsync(CoreWebView2 core, string destination, CancellationToken cancellation)
    {
        var loaded = new TaskCompletionSource<(bool Success, CoreWebView2WebErrorStatus Error)>(TaskCreationOptions.RunContinuationsAsynchronously);
        ulong? navigationId = null;
        void Starting(object? sender, CoreWebView2NavigationStartingEventArgs args)
        {
            if (args.Uri != destination || args.Cancel || (navigationId is not null && navigationId != args.NavigationId))
            {
                args.Cancel = true;
                loaded.TrySetException(new HarvestPageException("The page redirected or navigated away from the exact observed spot URL."));
                return;
            }
            navigationId = args.NavigationId;
        }
        void Completed(object? sender, CoreWebView2NavigationCompletedEventArgs args)
        {
            if (args.NavigationId == navigationId) loaded.TrySetResult((args.IsSuccess, args.WebErrorStatus));
        }
        core.NavigationStarting += Starting;
        core.NavigationCompleted += Completed;
        try
        {
            cancellation.ThrowIfCancellationRequested();
            core.Navigate(destination);
            var result = await loaded.Task.WaitAsync(cancellation);
            if (!result.Success || core.Source != destination)
                throw new HarvestPageException("The exact observed spot page did not complete successfully. Native status: " + result.Error + "; exact source: " + (core.Source == destination) + ".");
        }
        finally { core.NavigationStarting -= Starting; core.NavigationCompleted -= Completed; }
    }

    private static async Task<JsonObject> WaitForHeadersAsync(CoreWebView2 core, ObservedSpot spot, CancellationToken cancellation)
    {
        string? previous = null;
        var stableSince = Stopwatch.StartNew();
        while (true)
        {
            cancellation.ThrowIfCancellationRequested();
            if (core.Source != spot.Url) throw new HarvestPageException("The page left the exact observed spot while reading its headers.");
            var observed = JsonNode.Parse(await core.ExecuteScriptAsync(InspectHeaders).WaitAsync(cancellation)) as JsonObject;
            if (observed?["challengeDetected"]?.GetValue<bool>() == true)
                throw new InvalidOperationException("The public page showed a rate-limit, capacity or browser-verification challenge. The harvest stopped without attempting to bypass it.");
            if (observed?["loginRequired"]?.GetValue<bool>() == true)
                throw new InvalidOperationException("The remembered connection needs sign-in; the harvest stopped without using authentication controls.");
            var title = observed?["heading"]?.GetValue<string>();
            var ready = observed?["ready"]?.GetValue<bool>() == true && Normalize(title ?? string.Empty) == spot.Name;
            var identity = ready ? observed!.ToJsonString() : null;
            if (identity is not null && identity == previous && stableSince.ElapsedMilliseconds >= 1000)
                return observed!;
            if (identity != previous) { previous = identity; stableSince.Restart(); }
            await Task.Delay(500, cancellation);
        }
    }

    private const string InspectHeaders = """
        (() => {
          const visible=e=>!!e.getClientRects().length && getComputedStyle(e).visibility!=='hidden' && getComputedStyle(e).display!=='none';
          const text=e=>(e.innerText||e.textContent||'').trim().replace(/\s+/g,' ').normalize('NFC');
          const headings=[...document.querySelectorAll('h1')].filter(visible).map(text);
          const challengeDetected=[document.title,...[...document.querySelectorAll('h1,h2,[role="alert"]')].filter(visible).map(text)]
            .some(value=>/^(?:just a moment\.{0,3}|verify (?:that )?you are human|checking your browser|too many requests|rate limit(?: exceeded)?|temporarily unavailable|at capacity)$/i.test(value.trim()));
          const loginRequired=[...document.querySelectorAll('button,a,h1,h2')].filter(visible).some(e=>/^(?:log ?in|sign ?in)(?: to garmoth| with discord)?$/i.test(text(e)));
          const tables=[...document.querySelectorAll('table')].filter(visible).filter(t=>t.tHead && [...t.tHead.querySelectorAll('th')].some(h=>/^time ago$/i.test(text(h))));
          if(headings.length!==1 || tables.length!==1) return {ready:false,heading:headings.length===1?headings[0]:null,loginRequired,challengeDetected,historyTableCount:tables.length};
          const headers=[...tables[0].tHead.querySelectorAll('th')];
          const headerImages=[];
          const otherHeaderImages=[];
          for(let index=0;index<headers.length;index++) for(const img of headers[index].querySelectorAll('img')) {
            try {
              const url=new URL(img.getAttribute('src'),location.href);
              if(url.origin!=='https://assets.garmoth.com'||url.username||url.password||url.search||url.hash) continue;
              const match=/^\/img\/new_icon\/(?:[^/]+\/)*([0-9]+)\.(?:webp|png)$/i.exec(url.pathname);
              if(match&&Number(match[1])>0) headerImages.push({column:index,artworkKey:String(Number(match[1])),url:url.href,headerMarkup:headers[index].outerHTML});
              else if(/^\/img\/other\/[0-9]+\.(?:webp|png)$/i.test(url.pathname)) otherHeaderImages.push({column:index,url:url.href,headerMarkup:headers[index].outerHTML});
            } catch(_) {}
          }
          const rawImageKeys=[...new Set(headerImages.map(image=>image.artworkKey))].sort((a,b)=>Number(a)-Number(b));
          return {ready:document.readyState==='complete'&&rawImageKeys.length>0,heading:headings[0],loginRequired,challengeDetected,historyTableCount:1,
            headerLabels:headers.map(text),headerCount:headers.length,headerImages,otherHeaderImages,rawImageKeys};
        })()
        """;

    private static async Task ReadTooltipNamesAsync(CoreWebView2 core, ObservedSpot spot, JsonObject structure, CancellationToken cancellation)
    {
        var token = Guid.NewGuid().ToString("N");
        var key = "__bslReadOnlyHeaderHarvest_" + token;
        var headers = new JsonArray();
        foreach (var group in new[] { ("headerImages", "game_artwork"), ("otherHeaderImages", "other_artwork") })
            foreach (var image in (JsonArray)structure[group.Item1]!)
            {
                var header = (JsonObject)image!.DeepClone();
                header["imageKind"] = group.Item2;
                headers.Add(header);
            }
        var options = new JsonObject
        {
            ["key"] = key, ["token"] = token, ["source"] = spot.Url, ["name"] = spot.Name,
            ["deadline"] = DateTimeOffset.UtcNow.AddSeconds(45).ToUnixTimeMilliseconds(),
            ["headers"] = headers
        };
        try
        {
            // ExecuteScriptAsync does not await a returned JavaScript Promise.
            // Start a token-bound job and poll its plain synchronous state.
            var started = JsonNode.Parse(await core.ExecuteScriptAsync(StartTooltips.Replace("__OPTIONS__", options.ToJsonString())).WaitAsync(cancellation));
            if (started?["started"]?.GetValue<bool>() != true) throw new HarvestPageException("The header tooltip inspection did not start safely.");
            while (true)
            {
                await Task.Delay(35, cancellation);
                if (core.Source != spot.Url) throw new HarvestPageException("The page changed during header tooltip inspection.");
                var poll = JsonNode.Parse(await core.ExecuteScriptAsync("(()=>{const s=window[" + JsonSerializer.Serialize(key) +
                    "];return s?{done:s.done,failed:s.failed,headers:s.done?s.headers:null}:null})()").WaitAsync(cancellation));
                if (poll is null || poll["failed"]?.GetValue<bool>() == true) throw new HarvestPageException("The header tooltip inspection stopped because its page or controls changed.");
                if (poll["done"]?.GetValue<bool>() != true) continue;
                structure["tooltipObservations"] = poll["headers"]!.DeepClone();
                structure["tooltipNamesObserved"] = ((JsonArray)structure["tooltipObservations"]!).Count(header => header?["tooltipStatus"]?.GetValue<string>() == "observed");
                return;
            }
        }
        finally
        {
            try
            {
                await core.ExecuteScriptAsync("(()=>{const k=" + JsonSerializer.Serialize(key) +
                    ";const s=window[k];if(s){s.cancelled=true;s.stop?.();delete window[k];}return true})()").WaitAsync(TimeSpan.FromSeconds(1));
            }
            catch { /* No auth or application state is touched if the document has gone. */ }
        }
    }

    private const string StartTooltips = """
        (()=>{
          const options=__OPTIONS__;
          if(window[options.key]) return {started:false};
          const text=e=>(e.innerText||e.textContent||'').trim().replace(/\s+/g,' ').normalize('NFC');
          const visible=e=>!!e.getClientRects().length && getComputedStyle(e).visibility!=='hidden' && getComputedStyle(e).display!=='none';
          const state={token:options.token,done:false,failed:false,cancelled:false,headers:[],stop:null};
          window[options.key]=state;
          const active=()=>window[options.key]===state&&!state.cancelled&&Date.now()<options.deadline&&location.href===options.source
            && [...document.querySelectorAll('h1')].filter(visible).some(h=>text(h)===options.name);
          const assertActive=()=>{if(!active()) throw new Error('inspection stopped')};
          const poppers=()=>[...document.querySelectorAll('.v-popper__popper--shown[aria-hidden="false"],[role="tooltip"]')].filter(visible);
          const name=p=>text(p.querySelector('.v-popper__inner')||p);
          const itemName=p=>{
            const inner=p.querySelector('.v-popper__inner')||p;
            const full=text(inner);
            const match=/^(.+?)\s+Average:\s+.*?\s+Total:\s+.*?\s+Price:\s+.*$/.exec(full);
            if(!match) return null; // Do not export unknown tooltip statistics.
            const value=match[1].trim();
            const exactElement=[...inner.querySelectorAll('*')].find(e=>text(e)===value);
            return {value,extraction:exactElement?'exact tooltip name element':'prefix before observed Average:/Total:/Price: fields'};
          };
          const leave=header=>{
            if(location.href!==options.source||!header.isConnected) return;
            header.dispatchEvent(new MouseEvent('mouseout',{bubbles:true,view:window}));
            header.dispatchEvent(new MouseEvent('mouseleave',{bubbles:false,view:window}));
          };
          const read=header=>new Promise(resolve=>{
            assertActive();
            const before=new Map(poppers().map(p=>[p,name(p)]));
            let observer,timer,finished=false;
            const finish=result=>{
              if(finished) return;
              finished=true;observer?.disconnect();clearTimeout(timer);state.stop=null;resolve(result);
            };
            const inspect=()=>{
              if(!active()) {finish({tooltipStatus:'cancelled'});return;}
              const described=new Set([header,...header.querySelectorAll('[aria-describedby]')]
                .flatMap(e=>(e.getAttribute('aria-describedby')||'').split(/\s+/)).filter(Boolean));
              const shown=poppers();
              const associated=shown.filter(p=>described.has(p.id));
              const fresh=shown.filter(p=>!before.has(p)||before.get(p)!==name(p));
              const candidates=associated.length?associated:fresh;
              if(candidates.length>1){finish({tooltipStatus:'ambiguous'});return;}
              if(candidates.length===1){
                const extracted=itemName(candidates[0]);
                if(extracted&&extracted.value.length>0&&extracted.value.length<=180) finish({tooltipStatus:'observed',tooltipName:extracted.value,
                  tooltipNameExtraction:extracted.extraction,tooltipAssociation:associated.length?'aria-describedby':'newly shown tooltip',
                  columnMeaning:'supported session item column; natural drop status not established',explicitCostIndicator:null,
                  canonicalIdentity:extracted.value==='Any Artifact'?'noncanonical synthetic header':'unresolved exact name'});
              }
            };
            observer=new MutationObserver(inspect);
            observer.observe(document.documentElement,{childList:true,subtree:true,attributes:true,characterData:true});
            timer=setTimeout(()=>finish({tooltipStatus:'not_observed'}),450);
            state.stop=()=>finish({tooltipStatus:'cancelled'});
            header.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,view:window}));
            assertActive();
            header.dispatchEvent(new MouseEvent('mouseenter',{bubbles:false,view:window}));
            inspect();
          });
          (async()=>{
            try{
              for(const image of options.headers){
                assertActive();
                const tables=[...document.querySelectorAll('table')].filter(visible).filter(t=>t.tHead&&[...t.tHead.querySelectorAll('th')].some(h=>/^time ago$/i.test(text(h))));
                if(tables.length!==1) throw new Error('history table changed');
                const header=[...tables[0].tHead.querySelectorAll('th')][image.column];
                if(!header||![...header.querySelectorAll('img')].some(img=>new URL(img.getAttribute('src'),location.href).href===image.url)) throw new Error('header artwork changed');
                if(options.headers.filter(h=>h.column===image.column).length!==1){state.headers.push({...image,tooltipStatus:'multiple_artworks_in_header'});continue;}
                const triggers=[...new Set([...header.querySelectorAll('img')].filter(img=>new URL(img.getAttribute('src'),location.href).href===image.url)
                  .map(img=>img.closest('.v-popper--has-tooltip')).filter(trigger=>trigger&&header.contains(trigger)))];
                if(triggers.length!==1){state.headers.push({...image,tooltipStatus:'no_unique_tooltip_trigger'});continue;}
                const trigger=triggers[0];
                try{state.headers.push({...image,tooltipTrigger:trigger.tagName+'.v-popper--has-tooltip',...await read(trigger)});}
                finally{leave(trigger);}
              }
              assertActive();state.done=true;
            }catch(_){state.failed=true;state.done=true;}
          })();
          return {started:true};
        })()
        """;

    private static JsonObject BaseRecord(ObservedSpot spot) => new()
    {
        ["spotId"] = spot.Id, ["name"] = spot.Name, ["category"] = spot.Category, ["sidebarGroup"] = spot.Group
    };
    private static async Task WriteReportAsync(string output, JsonArray results, int expected, bool enumerationFinished, bool externalForegroundChangeObserved)
    {
        var verified = results.Count(result => result?["status"]?.GetValue<string>() == "verified_header_structure");
        await WriteAsync(Path.Combine(output, "session-item-column-catalog.json"), new JsonObject
        {
            ["status"] = enumerationFinished && verified == expected ? "complete" : "partial",
            ["expected"] = expected, ["observed"] = results.Count, ["verified"] = verified,
            ["itemIdentitiesVerified"] = false,
            ["tooltipStatisticsExported"] = false,
            ["noSave"] = true, ["noFormMutation"] = true, ["noOsInputOrActivationRequested"] = true,
            ["externalForegroundChangeObserved"] = externalForegroundChangeObserved,
            ["foregroundPolicy"] = "Startup foreground unchanged; own window never foreground/active. Later foreground changes belong to external activity; this harness makes no OS input or activation calls.",
            ["source"] = "Visible named session item columns, including possible costs and synthetic headers; NOT proof of natural drops. Exact captured sidebar links and h1 labels verified. Artwork basenames are NOT item IDs. Tooltip statistics are not exported.",
            ["spots"] = results.DeepClone()
        });
    }
    private static Task WriteAsync(string path, JsonNode value) => File.WriteAllTextAsync(path, value.ToJsonString(JsonOptions), Encoding.UTF8);
    private static string Normalize(string value) => Regex.Replace(value.Normalize(NormalizationForm.FormC).Trim(), @"\s+", " ");
    private static bool CheckBackground(EmbeddedGarmothBrowser service, IntPtr foreground, bool requireUnchanged = false)
    {
        var window = service.CurrentWindow;
        var currentForeground = GetForegroundWindow();
        var ownHandle = window is null ? IntPtr.Zero : new System.Windows.Interop.WindowInteropHelper(window).Handle;
        if (window?.IsBackgroundPreparation != true || window.IsActive || window.ShowActivated || window.ShowInTaskbar ||
            currentForeground == ownHandle || (requireUnchanged && currentForeground != foreground))
            throw new InvalidOperationException("Background isolation could not be verified; harvest stopped.");
        return currentForeground != foreground;
    }
    private sealed class HarvestPageException(string message) : Exception(message);
}
