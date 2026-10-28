using System.IO;
using System.Text.Json;
using BlackSpiritLife.SessionImport;

namespace BlackSpiritLife.SessionImport.App;

internal static class GarmothNavigationPolicy
{
    public const string TrackerUrl = "https://garmoth.com/grind-tracker/";

    public static bool IsTrackerUrl(string? value) =>
        TryHttps(value, out var uri) && uri!.Host == "garmoth.com" &&
        uri.AbsolutePath.StartsWith("/grind-tracker/", StringComparison.Ordinal);

    public static bool IsAllowedNavigation(string? value)
    {
        if (!TryHttps(value, out var uri)) return false;
        return uri!.Host is "garmoth.com" or "discord.com";
    }

    private static bool TryHttps(string? value, out Uri? uri) =>
        Uri.TryCreate(value, UriKind.Absolute, out uri) &&
        uri.Scheme == Uri.UriSchemeHttps && uri.IsDefaultPort &&
        string.IsNullOrEmpty(uri.UserInfo);
}

// This file contains only our opt-in flag, never browser cookies or credentials.
internal sealed class GarmothConnectionPreferences
{
    public string RootDirectory { get; }
    public string UserDataFolder => Path.Combine(RootDirectory, "WebViewProfile");
    public bool HasProfileData => Directory.Exists(UserDataFolder);
    private string PreferencePath => Path.Combine(RootDirectory, "connection.json");

    public GarmothConnectionPreferences(string? rootDirectory = null)
    {
        RootDirectory = Path.GetFullPath(rootDirectory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Black Spirit Life", "integrations", "session-import", "garmoth-connection"));
    }

    internal static GarmothConnectionPreferences FromCommandLine(IEnumerable<string> arguments)
    {
        const string prefix = "--data-root=";
        var matches = arguments.Where(value => value.StartsWith(prefix, StringComparison.Ordinal)).ToArray();
        if (matches.Length == 0) return new GarmothConnectionPreferences();
        if (matches.Length != 1) throw new ArgumentException("Only one personal-data root may be supplied.");
        var root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(matches[0][prefix.Length..]));
        if (!Path.IsPathFullyQualified(root) || root.StartsWith(@"\\", StringComparison.Ordinal) ||
            root.Any(character => char.IsControl(character) || character == '"') ||
            !string.Equals(Path.GetFileName(root), "session-import", StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(Path.GetFileName(Path.GetDirectoryName(root)), "integrations", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("The Session Import personal-data root is invalid.");
        return new GarmothConnectionPreferences(Path.Combine(root, "garmoth-connection"));
    }

    public bool RememberConnection
    {
        get
        {
            try
            {
                if (!File.Exists(PreferencePath)) return false;
                using var json = JsonDocument.Parse(File.ReadAllText(PreferencePath));
                return json.RootElement.ValueKind == JsonValueKind.Object
                    && json.RootElement.TryGetProperty("rememberConnection", out var value)
                    && value.ValueKind == JsonValueKind.True;
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException)
            {
                return false;
            }
        }
    }

    public void SetRememberConnection(bool value)
    {
        Directory.CreateDirectory(RootDirectory);
        var temporary = Path.Combine(RootDirectory, "connection-" + Guid.NewGuid().ToString("N") + ".tmp");
        File.WriteAllText(temporary, JsonSerializer.Serialize(new { rememberConnection = value }));
        File.Move(temporary, PreferencePath, overwrite: true);
    }
}
