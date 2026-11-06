/// Matches the twelve-digit whole-quantity range used by inventory inputs.
const maxActualBatchOutput = 999999999999;

/// Blank/zero opt out. Invalid edits stay invalid; never strip a minus sign,
/// decimal, unit suffix or extra pasted text into a different valid quantity.
int? parseActualBatchOutput(String text) {
  final value = text.trim();
  if (value.isEmpty) return 0;
  if (!RegExp(r'^\d+$').hasMatch(value) &&
      !RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(value)) {
    return null;
  }
  final amount = int.tryParse(value.replaceAll('.', ''));
  return amount != null && amount <= maxActualBatchOutput ? amount : null;
}

bool actualBatchOutputNeedsConfirmation(int? actual, double expected) =>
    actual != null && actual > 0 && actual < expected * .8;
