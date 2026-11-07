import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/features/planner/planner_shared.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget amount(TextEditingController text, {bool shared = false}) => SizedBox(
  width: 170,
  child: shared
      ? AppTextField(
          controller: text,
          semanticLabel: 'Owned amount',
          keyboardType: TextInputType.number,
          textAlign: TextAlign.right,
          prefixIcon: const Icon(Icons.inventory_2_outlined, size: 18),
        )
      : PlannerTextField(
          controller: text,
          semanticLabel: 'Amount to add',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.right,
          fontWeight: FontWeight.w700,
        ),
);

Widget host(
  Widget child, {
  ThemeSpec? theme,
  MediaQueryData? media,
  bool active = true,
}) {
  final spec = theme ?? RetainedThemeRegistry.themes.first;
  return RepaintBoundary(
    key: const ValueKey('capture'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: spec.materialTheme(),
      home: ThemeSpecScope(
        spec: spec,
        child: MediaQuery(
          data: media ?? const MediaQueryData(),
          child: TickerMode(
            enabled: active,
            child: Scaffold(
              backgroundColor: spec.palette.surface,
              body: Center(child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> capture(WidgetTester tester, String name) async {
  final root = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await (root.debugLayer! as OffsetLayer).toImage(
      Offset.zero & root.size,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/subtle-number-fade/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final fonts = '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts';
    final artifacts = File(
      Platform.resolvedExecutable,
    ).parent.parent.parent.path;
    for (final entry in {
      'Segoe UI': ['$fonts/segoeui.ttf', '$fonts/seguisb.ttf'],
      'Georgia': ['$fonts/georgia.ttf', '$fonts/georgiab.ttf'],
      'MaterialIcons': ['$artifacts/material_fonts/MaterialIcons-Regular.otf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });

  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'Only changed numbers fade with stable geometry ${spec.id} $scale',
        (tester) async {
          tester.view.physicalSize = const Size(780, 460);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final texts = List.generate(
            3,
            (_) => TextEditingController(text: '0'),
          );
          addTearDown(() {
            for (final text in texts) {
              text.dispose();
            }
          });
          var parentBuilds = 0;
          await tester.pumpWidget(
            host(
              Builder(
                builder: (_) {
                  parentBuilds++;
                  return SizedBox(
                    width: 650,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < texts.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    [
                                      'Need First amount',
                                      'Inventory amount',
                                      'Unchanged amount',
                                    ][i],
                                    style: spec.typography.body,
                                  ),
                                ),
                                const SizedBox(width: 32),
                                amount(texts[i], shared: i == 1),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              theme: spec,
              media: MediaQueryData(textScaler: TextScaler.linear(scale)),
            ),
          );
          await tester.pumpAndSettle();
          await tester.runAsync(
            () => precacheImage(
              const AssetImage(
                'assets/sakura/materials/charcoal-plum-lacquer.png',
              ),
              tester.element(find.byType(Scaffold)),
            ),
          );
          await tester.pumpAndSettle();
          final editors = find.byType(EditableText);
          final fields = find.byType(TextField);
          final rectangles = [
            for (var i = 0; i < 3; i++) tester.getRect(editors.at(i)),
          ];
          final colors = tester
              .widgetList<EditableText>(editors)
              .map((e) => e.style.color!)
              .toList();
          final borders = tester
              .widgetList<TextField>(fields)
              .map((e) => e.decoration!.enabledBorder)
              .toList();
          final cursors = tester
              .widgetList<EditableText>(editors)
              .map((e) => e.cursorColor)
              .toList();
          final builds = parentBuilds;
          void expectStableChromeAndNeighbors() {
            for (var i = 0; i < 3; i++) {
              expect(tester.getRect(editors.at(i)), rectangles[i]);
              expect(
                tester.widget<EditableText>(editors.at(i)).cursorColor,
                cursors[i],
              );
              expect(
                tester
                    .widget<TextField>(fields.at(i))
                    .decoration!
                    .enabledBorder,
                borders[i],
              );
            }
            expect(
              tester.widget<EditableText>(editors.at(2)).style.color,
              colors[2],
            );
          }

          texts[0].text = '20';
          texts[1].text = '20';
          await tester.pump();
          for (var i = 0; i < 2; i++) {
            expect(
              tester.widget<EditableText>(editors.at(i)).style.color!.a,
              closeTo(colors[i].a * .65, .001),
            );
            expect(
              tester.widget<EditableText>(editors.at(i)).controller.text,
              '20',
            );
          }
          expectStableChromeAndNeighbors();
          await capture(tester, '${spec.id}-$scale-start');
          await tester.pump(const Duration(milliseconds: 90));
          for (var i = 0; i < 2; i++) {
            expect(
              tester.widget<EditableText>(editors.at(i)).style.color!.a,
              closeTo(
                colors[i].a * (.65 + .35 * Curves.easeOut.transform(.5)),
                .001,
              ),
            );
          }
          expectStableChromeAndNeighbors();
          await capture(tester, '${spec.id}-$scale-middle');
          await tester.pump(const Duration(milliseconds: 90));
          await capture(tester, '${spec.id}-$scale-end');
          expect(
            parentBuilds,
            builds,
            reason: 'Animation stays inside each changed editor',
          );
          for (var i = 0; i < 3; i++) {
            expect(tester.getRect(editors.at(i)), rectangles[i]);
            expect(
              tester.widget<EditableText>(editors.at(i)).style.color,
              colors[i],
            );
            expect(
              tester.widget<EditableText>(editors.at(i)).cursorColor,
              cursors[i],
            );
            expect(
              tester.widget<TextField>(fields.at(i)).decoration!.enabledBorder,
              borders[i],
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  for (final shared in [false, true]) {
    testWidgets(
      'Selection and typing stay steady; latest change wins shared=$shared',
      (tester) async {
        final text = TextEditingController(text: '0');
        addTearDown(text.dispose);
        await tester.pumpWidget(host(amount(text, shared: shared)));
        await tester.pumpAndSettle();
        final base = tester
            .widget<EditableText>(find.byType(EditableText))
            .style
            .color!;
        Color color() =>
            tester.widget<EditableText>(find.byType(EditableText)).style.color!;
        text.selection = const TextSelection.collapsed(offset: 1);
        await tester.pump();
        expect(color(), base);
        text.text = '20';
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 70));
        text.text = '40';
        await tester.pump();
        expect(color().a, closeTo(base.a * .65, .001));
        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(color(), base, reason: 'Focusing cancels the fade immediately');
        await tester.enterText(find.byType(TextField), '400');
        await tester.pump();
        expect(color(), base);
        expect(text.text, '400');
        await tester.pump(const Duration(milliseconds: 300));
        expect(color(), base);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Reduced motion and inactive hosts finish without replay shared=$shared',
      (tester) async {
        final text = TextEditingController(text: '0');
        addTearDown(text.dispose);
        final field = amount(text, shared: shared);
        await tester.pumpWidget(host(field));
        await tester.pumpAndSettle();
        final base = tester
            .widget<EditableText>(find.byType(EditableText))
            .style
            .color!;
        for (final media in [
          const MediaQueryData(disableAnimations: true),
          const MediaQueryData(accessibleNavigation: true),
        ]) {
          text.text = '10';
          await tester.pump();
          await tester.pumpWidget(host(field, media: media));
          text.text = '20';
          await tester.pump();
          expect(
            tester.widget<EditableText>(find.byType(EditableText)).style.color,
            base,
          );
          await tester.pumpWidget(host(field));
          expect(
            tester.widget<EditableText>(find.byType(EditableText)).style.color,
            base,
          );
        }
        text.text = '30';
        await tester.pump();
        await tester.pumpWidget(host(field, active: false));
        text.text = '40';
        await tester.pump();
        await tester.pumpWidget(host(field));
        expect(
          tester.widget<EditableText>(find.byType(EditableText)).style.color,
          base,
        );
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Controller replacement and disposal cannot replay old changes shared=$shared',
      (tester) async {
        final first = TextEditingController(text: '0');
        final second = TextEditingController(text: '50');
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        await tester.pumpWidget(host(amount(first, shared: shared)));
        await tester.pumpAndSettle();
        final base = tester
            .widget<EditableText>(find.byType(EditableText))
            .style
            .color!;
        first.text = '20';
        await tester.pump();
        await tester.pumpWidget(host(amount(second, shared: shared)));
        expect(
          tester.widget<EditableText>(find.byType(EditableText)).style.color,
          base,
        );
        first.text = '30';
        await tester.pump();
        expect(
          tester.widget<EditableText>(find.byType(EditableText)).style.color,
          base,
        );
        second.text = '60';
        await tester.pump();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Search text does not acquire number motion', (tester) async {
    final text = TextEditingController(text: 'Aloe');
    addTearDown(text.dispose);
    await tester.pumpWidget(
      host(SizedBox(width: 240, child: AppTextField(controller: text))),
    );
    await tester.pumpAndSettle();
    final base = tester
        .widget<EditableText>(find.byType(EditableText))
        .style
        .color;
    text.text = 'Wheat';
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).style.color,
      base,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
