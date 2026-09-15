using System.IO;
using System.Reflection;
using System.Text.Json;

namespace BlackSpiritLife.SessionImport.App;

internal static class EmbeddedGarmothScripts
{
    private static readonly Lazy<string> Helpers = new(() =>
        Read("BlackSpiritLife.SessionImport.App.Garmoth.protocol.js") + "\n" +
        Read("BlackSpiritLife.SessionImport.App.Garmoth.content.js"));
    internal static string HelperSource => Helpers.Value;
    private const string RouteGuard = "window === window.top && location.origin === 'https://garmoth.com' && location.pathname.startsWith('/grind-tracker/')";
    private const string OriginGuard = "window === window.top && location.origin === 'https://garmoth.com'";
    private const string Readiness = """
        const editor = TrackerContentTest.findSessionEditor(document);
        const sessionEditor = !!editor;
        const opener = TrackerContentTest.findEditor(document) ? null : TrackerContentTest.findOpenEditorButton(document);
        let actionableOpener = false;
        if (opener && !opener.disabled && opener.getAttribute('aria-disabled') !== 'true') {
          const bounds = opener.getBoundingClientRect();
          const hit = document.elementFromPoint(bounds.left + bounds.width / 2, bounds.top + bounds.height / 2);
          actionableOpener = !!hit && (hit === opener || opener.contains(hit));
        }
        const ready = document.readyState !== 'loading' && (sessionEditor || actionableOpener);
        """;

    private static string Read(string name)
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name)
            ?? throw new InvalidOperationException("The Garmoth draft helper is missing from this build.");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    private static string PageStatus => $$"""
          if (document.readyState === 'loading')
            return {connected:true,state:'loading',canPrepare:false,ready:false,draftId:null};
          let canPrepare = false;
          let draftId = null;
          if ({{RouteGuard}}) {
            {{Helpers.Value}}
            {{Readiness}}
            canPrepare = ready;
            draftId = sessionEditor ? editor.getAttribute('data-bsl-session-import-draft') : null;
          }
          const normalized = value => String(value || '').normalize('NFKC').replace(/\s+/g,' ').trim().toLowerCase();
          const loginLabel = /^(?:log\s?in|sign\s?in)(?: to garmoth| with discord)?$/;
          const visible = element => {
            if (!(element instanceof Element) || element.hidden || element.getAttribute('aria-hidden') === 'true') return false;
            const style = getComputedStyle(element);
            if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
            const bounds = element.getBoundingClientRect();
            if (bounds.width <= 0 || bounds.height <= 0) return false;
            const hit = document.elementFromPoint(bounds.left + bounds.width / 2, bounds.top + bounds.height / 2);
            return !!hit && (hit === element || element.contains(hit));
          };
          const loginRequired = Array.from(document.querySelectorAll('button,a,[role="button"],[role="dialog"] h1,[role="dialog"] h2,[role="dialog"] [role="heading"]'))
            .some(element => visible(element) && [element.getAttribute('aria-label'),element.getAttribute('title'),element.textContent]
              .some(label => loginLabel.test(normalized(label))));
          return {connected:true,state:canPrepare ? 'tracker_ready' : loginRequired ? 'login_required' : 'browser_open',
            canPrepare,ready:canPrepare,draftId};
        """;

    // Connection observation reads only visible controls on Garmoth itself. It
    // does not inspect account globals, storage, credentials or OAuth pages.
    public static string ConnectionStatus() => $$"""
        (() => {
          if (!({{OriginGuard}})) return {connected:false,state:'not_open',canPrepare:false,ready:false,draftId:null};
          {{PageStatus}}
        })()
        """;

    public static string Status() => $$"""
        (() => {
          if (!({{RouteGuard}})) return {ready:false};
          {{PageStatus}}
        })()
        """;

    public static string Start(string token, string draftJson, long deadlineUnixMilliseconds) => $$"""
        (() => {
          if (!({{RouteGuard}})) return {started:false};
          {{Helpers.Value}}
          {{Readiness}}
          if (!ready) return {started:false};
          const token = {{JsonSerializer.Serialize(token)}};
          const job = {token, cancelled:false, done:false, result:null};
          window.__bslSessionImportJob = job;
          const assertActive = () => {
            if (window.__bslSessionImportJob !== job || job.cancelled ||
                Date.now() >= {{deadlineUnixMilliseconds}} || !({{RouteGuard}})) {
              throw new TrackerProtocol.ProtocolError('cancelled', 'Preparation stopped. Review your items and try again.');
            }
            const currentEditor = TrackerContentTest.findEditor(document);
            if (currentEditor && !TrackerContentTest.isSessionEditor(currentEditor)) {
              throw new TrackerProtocol.ProtocolError('session_not_ready', 'Open Garmoth\'s Add session form before preparing.');
            }
          };
          const draft = JSON.parse({{JsonSerializer.Serialize(draftJson)}});
          TrackerContentTest.prepareDraftIn(document, draft, {assertActive})
            .then(result => {assertActive(); job.result = result; job.done = true;})
            .catch(error => {job.result = TrackerProtocol.errorResult(error); job.done = true;});
          return {started:true};
        })()
        """;

    public static string Poll(string token) => $$"""
        (() => {
          if (!({{RouteGuard}})) return {lost:true};
          const job = window.__bslSessionImportJob;
          if (!job || job.token !== {{JsonSerializer.Serialize(token)}}) return {lost:true};
          return {done:job.done, result:job.done ? job.result : null};
        })()
        """;

    public static string Cancel(string token) => $$"""
        (() => {
          if (!({{RouteGuard}})) return;
          const job = window.__bslSessionImportJob;
          if (job && job.token === {{JsonSerializer.Serialize(token)}}) job.cancelled = true;
        })()
        """;
}
