import 'package:bdo_craft_planner_flutter/domain/formatting/planner_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatQuantity', () {
    test('matches audited de-DE grouping and adaptive precision', () {
      expect(formatQuantity(1234), '1.234');
      expect(formatQuantity(1234.5), '1.234,5');
      expect(formatQuantity(1.25), '1,2');
      expect(formatQuantity(12.0004), '12');
      expect(formatQuantity(double.nan), '0');
      expect(formatQuantity(double.infinity), '0');
    });

    test('supports explicit de-DE and invariant fixtures', () {
      expect(formatQuantity(1234.5, fractionDigits: 2), '1.234,50');
      expect(
        formatQuantity(
          1234.5,
          locale: PlannerNumberLocale.invariant,
          fractionDigits: 2,
        ),
        '1,234.50',
      );
      expect(formatEditableQuantity(1234.56789), '1234.5679');
      expect(formatGroupedEditableQuantity(1000), '1.000');
      expect(formatGroupedEditableQuantity(10000), '10.000');
      expect(formatGroupedEditableQuantity(1234.56789), '1.234,5679');
      expect(formatQuantity(-.5), '-0,5');
    });
  });

  test('parser accepts invariant and de-DE editable values', () {
    expect(parsePlannerNumber('1,5'), 1.5);
    expect(parsePlannerNumber('1,234'), 1.234);
    expect(parsePlannerNumber('1.234,5'), 1234.5);
    expect(parsePlannerNumber('1,234.5'), 1234.5);
    expect(parsePlannerNumber(' 12.75 '), 12.75);
    expect(parsePlannerNumber('0.125'), .125);
    expect(parsePlannerNumber('not a number'), isNull);
    expect(parsePlannerNumber('NaN'), isNull);
  });

  test('parser round-trips de-DE grouped integers without truncation', () {
    expect(parsePlannerNumber('1.900'), 1900);
    expect(parsePlannerNumber('-1.900'), -1900);
    expect(parsePlannerNumber('1.234.567'), 1234567);
    expect(parsePlannerNumber('1,234,567'), 1234567);
    expect(parsePlannerNumber(formatQuantity(1900)), 1900);
    expect(parsePlannerNumber(formatQuantity(999999)), 999999);
  });

  group('formatSilver', () {
    test('uses de-DE grouping below one million', () {
      expect(formatSilver(999999), '999.999');
      expect(formatSilverLabel(1234), '1.234 silver');
    });

    test('uses invariant one-decimal M and B abbreviations', () {
      expect(formatSilver(1000000), '1M');
      expect(formatSilver(1200000), '1.2M');
      expect(formatSilver(1250000), '1.2M');
      expect(formatSilver(1200000000), '1.2B');
      expect(formatSilver(2.5), '2');
      expect(
        formatSilver(999999, locale: PlannerNumberLocale.invariant),
        '999,999',
      );
    });
  });

  test('date output is UTC and independent of the process locale', () {
    final value = DateTime.utc(2026, 7, 20, 12, 34, 56);
    expect(formatPlannerDateTime(value), '20.07.2026, 12:34 UTC');
    expect(
      formatPlannerDateTime(
        value,
        locale: PlannerNumberLocale.invariant,
        includeSeconds: true,
      ),
      '2026-07-20 12:34:56 UTC',
    );
    expect(formatMarketFetchedAt(0), 'Never');
    expect(
      formatMarketFetchedAt(value.millisecondsSinceEpoch),
      '20.07.2026, 12:34 UTC',
    );
  });
}
