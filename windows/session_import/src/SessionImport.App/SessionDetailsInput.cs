using System.Globalization;
using System.Text.RegularExpressions;

namespace BlackSpiritLife.SessionImport.App;

internal sealed record SessionDetailsValues(int DurationSeconds, bool AgrisActive,
    decimal? AdditionalDropRate, decimal? AdditionalDropAmount);

internal static class SessionDetailsInput
{
    internal const decimal MaximumPercentage = 10_000m;

    internal static bool TryDuration(string? text, out int seconds)
    {
        seconds = 0;
        var match = Regex.Match(text?.Trim() ?? string.Empty, @"\A([0-9]{1,2}):([0-9]{2})\z", RegexOptions.CultureInvariant);
        if (!match.Success) return false;
        var hours = int.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture);
        var minutes = int.Parse(match.Groups[2].Value, CultureInfo.InvariantCulture);
        if (minutes > 59 || hours > 24 || hours == 24 && minutes != 0) return false;
        seconds = (hours * 60 + minutes) * 60;
        return seconds > 0;
    }

    internal static bool TryOptionalPercentage(string? text, out decimal? value)
    {
        value = null;
        if (string.IsNullOrWhiteSpace(text)) return true;
        var trimmed = text.Trim();
        // A decimal point or comma is accepted, but not grouping or repairs.
        if (!Regex.IsMatch(trimmed, @"\A[0-9]+(?:[.,][0-9]{1,2})?\z", RegexOptions.CultureInvariant) ||
            !decimal.TryParse(trimmed.Replace(',', '.'), NumberStyles.AllowDecimalPoint,
                CultureInfo.InvariantCulture, out var parsed) || parsed > MaximumPercentage)
            return false;
        value = parsed;
        return true;
    }
}
