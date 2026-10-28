import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_theme.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_market_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('quiet loading never changes the content position', (
    tester,
  ) async {
    const anchor = ValueKey('content-anchor');
    Rect? bounds;
    for (final (total, loaded, loading) in [
      (0, 0, false),
      (28, 0, true),
      (28, 21, true),
      (40, 21, true),
      (40, 40, false),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: OpportunitiesTheme(
            child: Column(
              children: [
                OpportunityMarketProgress(
                  label: 'Market details',
                  showLoading: false,
                  status: OpportunityMarketLoadStatus(
                    total: total,
                    loaded: loaded,
                    loading: loading,
                    failed: 0,
                    blocked: false,
                  ),
                ),
                const Expanded(child: SizedBox(key: anchor)),
              ],
            ),
          ),
        ),
      );
      bounds ??= tester.getRect(find.byKey(anchor));
      expect(tester.getRect(find.byKey(anchor)), bounds);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('Market details'), findsNothing);
    }
  });

  for (final loading in [false, true]) {
    testWidgets('quiet checks retain failures while loading=$loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OpportunitiesTheme(
            child: OpportunityMarketProgress(
              label: 'Market details',
              showLoading: false,
              status: OpportunityMarketLoadStatus(
                total: 28,
                loaded: 21,
                loading: loading,
                failed: 1,
                blocked: false,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Market details · 21 / 28 · 1 failed'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  }

  testWidgets('completed prices disappear while preorders remain readable', (
    tester,
  ) async {
    var clicks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: OpportunitiesTheme(
          child: Column(
            children: [
              const OpportunityMarketProgress(
                label: 'Loading prices',
                status: OpportunityMarketLoadStatus(
                  total: 1446,
                  loaded: 1446,
                  failed: 0,
                  loading: true,
                  blocked: false,
                ),
              ),
              const OpportunityMarketProgress(
                label: 'Preorders',
                status: OpportunityMarketLoadStatus(
                  total: 322,
                  loaded: 99,
                  failed: 0,
                  loading: true,
                  blocked: false,
                ),
              ),
              TextButton(
                onPressed: () => clicks++,
                child: const Text('Open loaded recipe'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.textContaining('Loading prices'), findsNothing);
    expect(find.text('Preorders · 99 / 322'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      99 / 322,
    );
    await tester.tap(find.text('Open loaded recipe'));
    expect(clicks, 1);
    expect(tester.takeException(), isNull);
  });

  for (final failed in [0, 2]) {
    testWidgets(
      'incomplete ${failed == 0 ? 'blocked' : 'failed'} checks stay visible',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: OpportunitiesTheme(
              child: OpportunityMarketProgress(
                label: 'Preorders',
                status: OpportunityMarketLoadStatus(
                  total: 322,
                  loaded: 99,
                  failed: failed,
                  loading: false,
                  blocked: failed == 0,
                ),
              ),
            ),
          ),
        );
        expect(find.textContaining('Preorders · 99 / 322'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        if (failed > 0) expect(find.textContaining('2 failed'), findsOneWidget);
      },
    );
  }

  testWidgets('unrequested work does not show an empty bar', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OpportunitiesTheme(
          child: OpportunityMarketProgress(
            label: 'Preorders',
            status: OpportunityMarketLoadStatus(
              total: 0,
              loaded: 0,
              failed: 0,
              loading: false,
              blocked: false,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('Preorders'), findsNothing);
  });
}
