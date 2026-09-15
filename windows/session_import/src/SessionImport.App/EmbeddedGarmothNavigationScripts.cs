using System.Text.Json;

namespace BlackSpiritLife.SessionImport.App;

// Discovery is read-only. The native host owns deadlines and each navigation.
internal static class EmbeddedGarmothNavigationScripts
{
    public static string Execute(string draftJson, string action, long deadlineUnixMilliseconds, string? expectedUrl = null) => $$"""
        (() => {
          if (window !== window.top || location.origin !== 'https://garmoth.com' || !location.pathname.startsWith('/grind-tracker/'))
            return {acted:false,message:'Open your tracker before preparing.'};
          {{EmbeddedGarmothScripts.HelperSource}}
          const source = location.href;
          const deadline = {{deadlineUnixMilliseconds}};
          const expectedUrl = {{JsonSerializer.Serialize(expectedUrl)}};
          const assertActive = () => {
            if (window !== window.top || location.href !== source && location.href !== expectedUrl || Date.now() >= deadline)
              throw new TrackerProtocol.ProtocolError('cancelled','Tracker navigation stopped. Prepare again when the page is ready.');
          };
          try {
            return TrackerContentTest.executeNavigationStep(document, JSON.parse({{JsonSerializer.Serialize(draftJson)}}),
              {{JsonSerializer.Serialize(action)}}, {assertActive,deadline,expectedUrl});
          } catch (error) {
            return {acted:false,message:TrackerProtocol.errorResult(error).message};
          }
        })()
        """;

    public static string Discover(string draftJson) => $$"""
        (() => {
          if (window !== window.top || location.origin !== 'https://garmoth.com')
            return {state:'blocked',message:'Open Garmoth before preparing.'};
          {{EmbeddedGarmothScripts.HelperSource}}
          try {
            return TrackerContentTest.discoverPreparation(document, JSON.parse({{JsonSerializer.Serialize(draftJson)}}));
          } catch (error) {
            return {state:'blocked',message:TrackerProtocol.errorResult(error).message};
          }
        })()
        """;
}
