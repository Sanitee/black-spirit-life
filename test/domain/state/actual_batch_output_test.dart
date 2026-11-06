import 'package:bdo_craft_planner_flutter/domain/state/actual_batch_output.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('blank and zero use estimate; whole/grouped amounts stay exact', () {
    for (final input in ['', ' ', '0', '000']) {
      expect(parseActualBatchOutput(input), 0);
    }
    expect(parseActualBatchOutput('2480'), 2480);
    expect(parseActualBatchOutput(' 2.480 '), 2480);
    expect(parseActualBatchOutput('999.999.999.999'), maxActualBatchOutput);
  });
  test('bad input is never silently converted into a different amount', () {
    for (final input in [
      '-1',
      '2.5',
      '2,5',
      '1e3',
      'NaN',
      'Infinity',
      '12 fish',
      '2..480',
      '1000000000000',
    ]) {
      expect(parseActualBatchOutput(input), isNull, reason: input);
    }
  });
  test(
    'strictly below 80%, not zero or exactly 80%, asks for confirmation',
    () {
      expect(actualBatchOutputNeedsConfirmation(null, 2500), isFalse);
      expect(actualBatchOutputNeedsConfirmation(0, 2500), isFalse);
      expect(actualBatchOutputNeedsConfirmation(1999, 2500), isTrue);
      expect(actualBatchOutputNeedsConfirmation(2000, 2500), isFalse);
      expect(actualBatchOutputNeedsConfirmation(3000, 2500), isFalse);
    },
  );
}
