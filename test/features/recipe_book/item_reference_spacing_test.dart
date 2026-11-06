import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_controller.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info_view.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_book_test_support.dart';

void main() {
  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      for (final host in ['pinned', 'hover', 'passive', 'inline']) {
        for (final market in [false, true]) {
          testWidgets('shared spacing ${spec.id} $scale $host market=$market', (
            tester,
          ) async {
            final env = buildRecipeBookTestEnvironment();
            final book = RecipeBookController(
              modeController: env.application.active,
              catalogRepository: env.catalogRepository,
              callingContext: RecipeBookCallingContext.planner,
              allowedTargets: env.application.active.craftableNames,
            );
            final info = RecipeBookItemInfo(
              title: 'Sunrise Herb',
              kind: 'Material',
              summary: 'Short description.',
              effects: ['Recorded effect.'],
              acquisitionNotes: [
                market ? 'Central Market' : 'Gather wild herbs.',
              ],
              notes: ['Recorded note.'],
            );
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(900, 1000);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);
            try {
              await tester.pumpWidget(
                MaterialApp(
                  theme: spec.materialTheme(),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: ThemeSpecScope(
                    spec: spec,
                    child: Scaffold(
                      body: Center(
                        child: SizedBox(
                          width: 480,
                          child: host == 'inline'
                              ? ItemReferenceSections(
                                  controller: book,
                                  mode: CraftMode.alchemy,
                                  name: info.title,
                                  info: info,
                                  spec: spec,
                                )
                              : ItemReferenceCard(
                                  controller: book,
                                  mode: CraftMode.alchemy,
                                  name: info.title,
                                  info: info,
                                  spec: spec,
                                  maxWidth: 480,
                                  interactive: host != 'passive',
                                  onClose: host == 'pinned' ? () {} : null,
                                  icon: const SizedBox.square(dimension: 44),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final summary = tester.getRect(find.text('Short description.'));
              final effectHeading = tester.getRect(find.text('Effects'));
              expect(
                effectHeading.top - summary.bottom,
                closeTo(host == 'inline' ? 20 * scale.clamp(1, 1.5) : 24, .1),
              );
              // Both plain and market-backed source sections must receive the
              // same spacing; stock freshness/eligibility must not move headings.
              final effect = tester.getRect(find.text('Recorded effect.'));
              final sourceHeading = tester.getRect(find.text('How to Obtain'));
              final expectedGap = host == 'inline'
                  ? 20 * scale.clamp(1, 1.5) + 4
                  : 36;
              expect(
                sourceHeading.top - effect.bottom,
                closeTo(expectedGap, .1),
              );
              expect(find.text('Recorded note.'), findsOneWidget);
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox());
              book.dispose();
              await env.dispose();
            }
          });
        }
      }
    }
  }
}
