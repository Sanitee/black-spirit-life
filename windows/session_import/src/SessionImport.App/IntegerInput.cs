using System.Globalization;

namespace BlackSpiritLife.SessionImport.App;

internal static class IntegerInput
{
    private static readonly char[] GroupSeparators = [',', '.', ' ', '\u00A0', '\u202F'];

    public static bool TryParseGrouped(string? text, out long value)
    {
        value = 0;
        if (string.IsNullOrWhiteSpace(text)) return false;

        var trimmed = text.Trim();
        if (trimmed.All(char.IsDigit))
            return long.TryParse(trimmed, NumberStyles.None, CultureInfo.InvariantCulture, out value);

        var groups = trimmed.Split(GroupSeparators, StringSplitOptions.None);
        if (groups.Length < 2 || groups[0].Length is < 1 or > 3) return false;
        if (groups[0].Any(character => !char.IsDigit(character))) return false;
        if (groups.Skip(1).Any(group => group.Length != 3 || group.Any(character => !char.IsDigit(character))))
            return false;

        var digits = string.Concat(groups);
        return long.TryParse(digits, NumberStyles.None, CultureInfo.InvariantCulture, out value);
    }

    public static bool IsAllowedInput(string text) =>
        text.All(character => char.IsDigit(character) || GroupSeparators.Contains(character));
}
