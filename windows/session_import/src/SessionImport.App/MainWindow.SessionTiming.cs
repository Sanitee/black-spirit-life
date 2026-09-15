namespace BlackSpiritLife.SessionImport.App;

public partial class MainWindow
{
    private void InitializeSessionDetails()
    {
        AgrisActiveBox.SelectionChanged += (_, _) => InvalidatePreparedDraft();
        AdditionalDropRateBox.TextChanged += (_, _) => InvalidatePreparedDraft();
        AdditionalDropAmountBox.TextChanged += (_, _) => InvalidatePreparedDraft();
        UpdateSessionDetailsControls();
    }

    private void UpdateSessionDetailsControls()
    {
        // Duration is outside ReviewPanel and must share its busy-state guard.
        DurationBox.IsEnabled = !_busy && !_closed && !_closing;
    }

    private bool TryGetSessionDetails(out SessionDetailsValues? values, out string error)
    {
        values = null;
        error = string.Empty;
        if (!SessionDetailsInput.TryDuration(DurationBox.Text, out var seconds))
        {
            error = "Enter a duration from 00:01 to 24:00 (hours:minutes).";
            return false;
        }
        if (AgrisActiveBox.SelectedIndex is not (0 or 1))
        {
            error = "Choose Yes or No for Agris.";
            return false;
        }
        if (!SessionDetailsInput.TryOptionalPercentage(AdditionalDropRateBox.Text, out var rate))
        {
            error = "Additional drop rate must be 0–10,000% with up to two decimal places, or blank.";
            return false;
        }
        if (!SessionDetailsInput.TryOptionalPercentage(AdditionalDropAmountBox.Text, out var amount))
        {
            error = "Additional drop amount must be 0–10,000% with up to two decimal places, or blank.";
            return false;
        }
        values = new SessionDetailsValues(seconds, AgrisActiveBox.SelectedIndex == 1, rate, amount);
        return true;
    }
}
