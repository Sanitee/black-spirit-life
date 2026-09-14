import 'package:bdo_craft_planner_flutter/data/opportunities/market_eligibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the 298 audited client identities retain their separate classification',
    () {
      expect(reviewedNonMarketableOpportunityIds, hasLength(298));
      for (final id in ['9001', '9002', '9005', '9059', '16080', '8901']) {
        expect(isOpportunityMarketRequestEligible(id), isFalse, reason: id);
      }
      // Actual market alternatives must survive, even for purchasable inputs.
      for (final id in ['7702', '9064', '50006', '5205', '5960']) {
        expect(isOpportunityMarketRequestEligible(id), isTrue, reason: id);
      }
      expect(isOpportunityMarketRequestEligible('999999999'), isTrue);
    },
  );

  test('a failed request alone never excludes marketable IDs', () {
    for (final id in [
      '1189',
      '4203',
      '4703',
      '54018',
      '778',
      '7904',
      '8523',
      '9069',
      '9269',
      '9276',
    ]) {
      expect(isOpportunityMarketRequestEligible(id), isTrue, reason: id);
    }
  });

  test(
    'the exact eight user-archived IDs are excluded without false client flags',
    () {
      for (final id in [
        '15202',
        '15208',
        '15209',
        '15210',
        '15215',
        '6007',
        '6011',
        '6211',
      ]) {
        expect(reviewedNonMarketableOpportunityIds, isNot(contains(id)));
        expect(isOpportunityMarketRequestEligible(id), isFalse, reason: id);
        expect(isOpportunityMarketRequestEligible(' 00$id '), isFalse);
      }
    },
  );
}
