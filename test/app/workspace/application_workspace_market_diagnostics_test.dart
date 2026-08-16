import 'package:bdo_craft_planner_flutter/app/market/market_refresh_coordinator.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'duplicate request metadata stays out of Need First row diagnostics',
    () {
      final diagnostics = mapPlannerMarketRowDiagnostics(
        const <MarketRefreshDiagnostic>[
          MarketRefreshDiagnostic(
            code: MarketRefreshDiagnosticCode.duplicateMaterialName,
            materialName: 'Acacia Sap',
            message:
                'Acacia Sap was requested more than once and was deduplicated.',
          ),
          MarketRefreshDiagnostic(
            code: MarketRefreshDiagnosticCode.rowFailure,
            materialName: 'Acacia Sap',
            message: 'The market request failed temporarily.',
          ),
          MarketRefreshDiagnostic(
            code: MarketRefreshDiagnosticCode.marketUnlisted,
            materialName: "Sea Monster's Ooze",
            message: "Can't be registered on the Central Market.",
          ),
        ],
      );

      expect(
        diagnostics.values
            .expand((entries) => entries)
            .map((entry) => entry.message),
        isNot(contains(contains('requested more than once'))),
      );
      expect(diagnostics['acacia sap'], hasLength(1));
      expect(
        diagnostics['acacia sap']!.single.severity,
        PlannerMarketDiagnosticSeverity.error,
      );
      expect(
        diagnostics["sea monster's ooze"]!.single.isMarketUnlisted,
        isTrue,
      );
    },
  );
}
