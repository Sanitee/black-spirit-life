using System.Windows;
using System.Windows.Controls;
using BlackSpiritLife.SessionImport.App;
using Microsoft.Web.WebView2.Core;

internal static class ForegroundScriptDialogChecks
{
    internal static void Run(Action<string, Action> run)
    {
        run("site dialogs never show from an unshown inactive browser", () =>
        {
            var window = new GarmothBrowserWindow(false);
            try
            {
                foreach (var kind in Enum.GetValues<CoreWebView2ScriptDialogKind>().Append((CoreWebView2ScriptDialogKind)999))
                {
                    Assert(!window.TryShowForegroundScriptDialog(kind, "Site text", "default", out var result), "inactive dialog declined");
                    Assert(result is null && !window.IsVisible && !window.IsActive, "no result or UI activation");
                }
            }
            finally { window.Close(); }
        });
        run("site dialogs never reveal an app-owned background browser", () =>
        {
            var window = new GarmothBrowserWindow(false);
            try
            {
                window.ConfigureForBackground(null);
                Assert(!window.TryShowForegroundScriptDialog(CoreWebView2ScriptDialogKind.Prompt, "Site text", "default", out var result), "background prompt declined");
                Assert(result is null && window.IsBackgroundPreparation && !window.IsVisible && !window.ShowActivated,
                    "background placement and no activation preserved");
            }
            finally { window.Close(); }
        });
        run("closed browser cannot create a site dialog", () =>
        {
            var window = new GarmothBrowserWindow(false);
            window.Close();
            Assert(!window.TryShowForegroundScriptDialog(CoreWebView2ScriptDialogKind.Alert, "Site text", "", out var result), "closed alert declined");
            Assert(result is null && window.IsConnectionClosed, "closed state retained");
        });
        run("site prompt keeps literal message and default text with native OK and Cancel", () =>
        {
            const string message = "<Window>Literal site text & instructions</Window>";
            const string value = "<value> & 0";
            var prompt = new GarmothScriptPrompt(message, value);
            try
            {
                var content = (StackPanel)prompt.Content;
                Assert(((TextBlock)((ScrollViewer)content.Children[0]).Content).Text == message, "message is literal data");
                Assert(prompt.ResultText == value, "default text is not transformed");
                var actions = (StackPanel)content.Children[2];
                Assert(((Button)actions.Children[0]).IsCancel && ((Button)actions.Children[1]).IsDefault, "native Escape and Enter roles");
                Assert(prompt.Title == "Garmoth" && !prompt.ShowInTaskbar && !prompt.IsVisible, "owned neutral dialog stays unshown in tests");
                ((TextBox)content.Children[1]).Text = "";
                Assert(prompt.ResultText == "", "explicit empty response remains valid");
            }
            finally { prompt.Close(); }
        });
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
