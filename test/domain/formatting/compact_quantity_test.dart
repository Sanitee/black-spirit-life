import 'package:bdo_craft_planner_flutter/domain/formatting/compact_quantity.dart';
import 'package:bdo_craft_planner_flutter/domain/formatting/compact_silver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compact quantity shares the existing k/m/b/t rounding and carry', () {
    for (final (value, label) in <(num, String)>[
      (1100000, '1,1m'),
      (1500000, '1,5m'),
      (10800, '10,8k'),
      (1100000000, '1,1b'),
      (1100000000000, '1,1t'),
      (1000, '1k'),
      (999949, '999,9k'),
      (999950, '1m'),
      (999999999, '1b'),
      (-10800, '-10,8k'),
    ]) {
      expect(formatCompactQuantity(value), label);
      expect(formatCompactQuantity(value), formatCompactSilver(value));
    }
  });
  test(
    'small quantities retain existing precision and unknown stays unknown',
    () {
      for (final (value, label) in <(num, String)>[
        (0, '0'),
        (1, '1'),
        (62, '62'),
        (155, '155'),
        (999, '999'),
        (0.2, '0,2'),
        (1.5, '1,5'),
        (-0.2, '-0,2'),
      ]) {
        expect(formatCompactQuantity(value), label);
      }
      expect(formatCompactQuantity(double.nan), '—');
      expect(formatCompactQuantity(double.infinity), '—');
    },
  );
}
