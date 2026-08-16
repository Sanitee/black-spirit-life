import '../state/planner_state.dart';

/// Returns the share of a Central Market sale received after configured tax.
double marketNetRate(MarketTax tax) {
  // The Central Market deduction always applies. The legacy `enabled` field
  // remains readable for old save files, but can no longer create an
  // impossible tax-free profit estimate.
  return .65 *
      (1 +
          (tax.valuePack ? .3 : 0) +
          tax.familyFameBonus +
          (tax.merchantRing ? .05 : 0));
}

/// Applies [marketNetRate] to a gross sale value.
double marketNetProceeds(double gross, MarketTax tax) {
  if (!gross.isFinite) return 0;
  return gross * marketNetRate(tax);
}
