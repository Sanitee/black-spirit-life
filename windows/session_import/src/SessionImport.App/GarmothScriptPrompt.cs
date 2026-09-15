using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;

namespace BlackSpiritLife.SessionImport.App;

// Only instantiated for an explicit site prompt in the active foreground
// browser. Site message/default/response strings are data, never markup or logs.
internal sealed class GarmothScriptPrompt : Window
{
    private readonly TextBox _response;
    internal string ResultText => _response.Text;

    internal GarmothScriptPrompt(string message, string defaultText)
    {
        Title = "Garmoth";
        Width = 440;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        SetResourceReference(StyleProperty, typeof(Window));

        var content = new StackPanel { Margin = new Thickness(20) };
        var messageText = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap };
        content.Children.Add(new ScrollViewer
        {
            Content = messageText, MaxHeight = 220,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto
        });
        _response = new TextBox { Text = defaultText, MinHeight = 36, Margin = new Thickness(0, 16, 0, 16) };
        AutomationProperties.SetName(_response, "Response");
        AutomationProperties.SetLabeledBy(_response, messageText);
        content.Children.Add(_response);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = new Button { Content = "Cancel", IsCancel = true, MinWidth = 76, Margin = new Thickness(0, 0, 8, 0) };
        var confirm = new Button { Content = "OK", IsDefault = true, MinWidth = 76 };
        confirm.SetResourceReference(StyleProperty, "PrimaryButton");
        confirm.Click += (_, _) => DialogResult = true;
        actions.Children.Add(cancel);
        actions.Children.Add(confirm);
        content.Children.Add(actions);
        Content = content;
        Loaded += (_, _) => { _response.Focus(); _response.SelectAll(); };
    }
}
