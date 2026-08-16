import 'package:bdo_craft_planner_flutter/domain/market/market_calculations.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy disabled flag cannot bypass Central Market tax', () {
    final tax = MarketTax(
      enabled: false,
      valuePack: true,
      merchantRing: true,
      familyFameBonus: .015,
    );
    expect(marketNetRate(tax), closeTo(.88725, 1e-12));
    expect(marketNetProceeds(125000, tax), closeTo(110906.25, 1e-6));
  });

  test('enabled tax matches the audited base and bonus formula', () {
    expect(marketNetRate(MarketTax()), closeTo(.65, 1e-12));
    expect(marketNetRate(MarketTax(valuePack: true)), closeTo(.845, 1e-12));
    expect(marketNetRate(MarketTax(merchantRing: true)), closeTo(.6825, 1e-12));
    expect(
      marketNetRate(MarketTax(familyFameBonus: .005)),
      closeTo(.65325, 1e-12),
    );
    expect(
      marketNetRate(MarketTax(familyFameBonus: .01)),
      closeTo(.6565, 1e-12),
    );
    expect(
      marketNetRate(MarketTax(familyFameBonus: .015)),
      closeTo(.65975, 1e-12),
    );
    expect(
      marketNetRate(
        MarketTax(valuePack: true, merchantRing: true, familyFameBonus: .015),
      ),
      closeTo(.88725, 1e-12),
    );
    expect(
      marketNetProceeds(1000000, MarketTax(valuePack: true)),
      closeTo(845000, 1e-6),
    );
  });

  test('non-finite gross proceeds are rejected deterministically', () {
    expect(marketNetProceeds(double.nan, MarketTax()), 0);
    expect(marketNetProceeds(double.infinity, MarketTax()), 0);
  });
}
