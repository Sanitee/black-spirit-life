import 'package:bdo_map_core/src/widgets/network_cp_breakdown.dart';
import 'package:bdo_map_core/src/widgets/network_cp_review.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/map_menu_capture.dart';

void main() => networkCpReviewTests();

void networkCpReviewTests({
  Map<String, ({ResourceMapChromeThemeData chrome, ThemeData theme})>
      appearanceThemes =
      const {},
  bool onlyAppearance = false,
}) {
  const costs = NetworkCpBreakdown(
    limit: 400,
    keptNodes: 120,
    newNodes: 40,
    lodgingHouses: 15,
    royalWorkshops: 5,
  );

  Future<void> open(
    WidgetTester tester, {
    required TextEditingController controller,
    NetworkCpBreakdown? breakdown = costs,
    double width = 400,
    double textScale = 1,
    double opacity = .7,
    ResourceMapChromeThemeData? chrome,
    ThemeData? materialTheme,
    VoidCallback? onCommit,
    VoidCallback? onSave,
  }) async {
    await tester.binding.setSurfaceSize(const Size(680, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final material = chrome ?? ResourceMapChromeThemeData.sakuraCartographer;
    await tester.pumpWidget(
      MaterialApp(
        theme:
            materialTheme ??
            ThemeData(fontFamily: 'Segoe UI', brightness: material.brightness),
        home: Scaffold(
          backgroundColor: material.canvas,
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Center(
              child: ResourceMapChromeTheme(
                data: material.withUiOpacity(opacity),
                child: RepaintBoundary(
                  key: const ValueKey('network-review-capture'),
                  child: ResourceMapReadingPlane(
                    child: SizedBox(
                      width: width,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          NetworkCpReview(
                            budgetController: controller,
                            onCommitBudget: onCommit ?? () {},
                            breakdown: breakdown,
                          ),
                          const SizedBox(height: 8),
                          NetworkReviewActionShelf(
                            child: FilledButton.icon(
                              onPressed: onSave,
                              icon: const Icon(Icons.bookmark_added_outlined),
                              label: const Text('Save as current'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  if (!onlyAppearance) {
    testWidgets(
      'inline summary uses the complete breakdown and compact controls',
      (tester) async {
        final controller = TextEditingController(text: '400');
        addTearDown(controller.dispose);
        await open(tester, controller: controller);
        expect(find.text('Network cost'), findsOneWidget);
        expect(find.text('180 CP'), findsOneWidget);
        expect(find.text('220 CP'), findsOneWidget);
        expect(find.text('Network CP limit'), findsOneWidget);
        final label = tester.getRect(find.text('Network CP limit'));
        final field = tester.getRect(find.byType(TextField));
        expect(label.center.dy, closeTo(field.center.dy, .1));
        expect(field.left, greaterThan(label.right));
        expect(field.width, lessThan(120));
        final shelf = tester.getRect(find.byType(NetworkReviewActionShelf));
        final save = tester.getRect(find.byType(FilledButton));
        expect(save.right, closeTo(shelf.right - 10, .1));
        expect(save.width, lessThan(shelf.width - 40));
        expect(tester.takeException(), isNull);
      },
    );

    for (final width in [284.0, 300.0]) {
      testWidgets('normal review keeps CP controls inline at $width width', (
        tester,
      ) async {
        final controller = TextEditingController(text: '400');
        addTearDown(controller.dispose);
        await open(tester, controller: controller, width: width);
        final panel = tester.getRect(find.byType(NetworkCpReview));
        final label = tester.getRect(find.text('Network CP limit'));
        final field = tester.getRect(find.byType(TextField));
        final apply = tester.getRect(find.byType(TextButton));
        expect(label.center.dy, closeTo(field.center.dy, .1));
        expect(apply.center.dy, closeTo(field.center.dy, .1));
        expect(field.width, 76);
        expect(field.left, greaterThan(label.right));
        expect(apply.left, greaterThan(field.right));
        expect(label.left, greaterThanOrEqualTo(panel.left));
        expect(apply.right, lessThanOrEqualTo(panel.right - 12));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('CP apply and keyboard submit do not save the network', (
      tester,
    ) async {
      final controller = TextEditingController(text: '400');
      addTearDown(controller.dispose);
      final commits = <String>[];
      var saved = 0;
      await open(
        tester,
        controller: controller,
        onCommit: () => commits.add(controller.text),
        onSave: () => saved++,
      );
      await tester.enterText(find.byType(TextField), '450');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(commits, contains('450'));
      expect(saved, 0);
      commits.clear();
      await tester.enterText(find.byType(TextField), '475');
      await tester.tap(find.text('Update'));
      await tester.pump();
      expect(commits, contains('475'));
      expect(saved, 0);
      await tester.tap(find.text('Save as current'));
      expect(saved, 1);
    });

    testWidgets('no plan keeps CP input but never presents a fabricated cost', (
      tester,
    ) async {
      final controller = TextEditingController(text: '20');
      addTearDown(controller.dispose);
      await open(tester, controller: controller, breakdown: null);
      expect(find.text('— CP'), findsOneWidget);
      expect(find.byType(NetworkCpBreakdown), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });

    testWidgets('over-budget balance is not hidden by the new cost header', (
      tester,
    ) async {
      final controller = TextEditingController(text: '10');
      addTearDown(controller.dispose);
      await open(
        tester,
        controller: controller,
        breakdown: const NetworkCpBreakdown(
          limit: 10,
          keptNodes: 0,
          newNodes: 12,
        ),
      );
      expect(find.text('12 CP'), findsOneWidget);
      expect(find.text('-2 CP'), findsOneWidget);
      expect(find.text('Kept nodes'), findsNothing);
      expect(find.text('Royal Workshops'), findsNothing);
    });

    testWidgets('review materials follow opacity without fading the text', (
      tester,
    ) async {
      final controller = TextEditingController(text: '400');
      addTearDown(controller.dispose);
      // The package fallback has no inputInset, so controlInset resolves to the
      // deliberately opaque basemap canvas. The action shelf must still fade.
      const material = ResourceMapChromeThemeData.sakuraCartographer;
      expect(material.inputInset, isNull);
      for (final opacity in [0.0, .7, 1.0]) {
        await open(tester, controller: controller, opacity: opacity);
        // The saved slider now maps to the approved satin-material density;
        // the review still applies its existing nested-plane factor exactly.
        final density = opacity <= .02
            ? .02
            : .02 + .98 * (1 - ((1 - opacity) / .98) * ((1 - opacity) / .98));
        final expected = density * .48;
        BoxDecoration decoration(String key) =>
            tester.widget<DecoratedBox>(find.byKey(ValueKey(key))).decoration
                as BoxDecoration;
        expect(
          decoration('resource-map-review-cost-body').color!.a,
          closeTo(expected, .001),
        );
        expect(
          decoration('resource-map-review-action-fill').color!.a,
          closeTo(expected, .001),
        );
        final gradient = decoration(
          'resource-map-review-cost-header',
        ).gradient!;
        for (final color in gradient.colors) {
          expect(color.a, lessThanOrEqualTo(expected + .001));
        }
        expect(
          tester.widget<Text>(find.text('Network cost')).style!.color,
          material.ink,
        );
        expect(find.byType(BackdropFilter), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });
  }

  final themes = appearanceThemes.isEmpty
      ? {
          'sakura': (
            chrome: ResourceMapChromeThemeData.sakuraCartographer,
            theme: ThemeData(
              fontFamily: 'Segoe UI',
              brightness: Brightness.dark,
            ),
          ),
          'ledger': (
            chrome: ResourceMapChromeThemeData.illuminatedAtlas,
            theme: ThemeData(
              fontFamily: 'Segoe UI',
              brightness: Brightness.light,
            ),
          ),
        }
      : appearanceThemes;
  for (final scale in [1.0, 2.0]) {
    for (final appearance in themes.entries) {
      testWidgets('inline review ${appearance.key} fits at ${scale}x', (
        tester,
      ) async {
        final controller = TextEditingController(text: '400');
        addTearDown(controller.dispose);
        await tester.runAsync(loadMapMenuCaptureFonts);
        await open(
          tester,
          controller: controller,
          width: scale == 1 ? 400 : 320,
          textScale: scale,
          chrome: appearance.value.chrome,
          materialTheme: appearance.value.theme,
          onSave: () {},
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(Scrollbar), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);
        await captureMapMenu(
          tester,
          boundary: find.byKey(const ValueKey('network-review-capture')),
          name:
              'inline-network-review-${appearance.key}-text${(scale * 100).round()}',
        );
        await open(
          tester,
          controller: controller,
          width: scale == 1 ? 400 : 320,
          textScale: scale,
          chrome: appearance.value.chrome,
          materialTheme: appearance.value.theme,
          opacity: 0,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller,
          same(controller),
        );
        expect(controller.text, '400');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
