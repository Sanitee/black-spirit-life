import 'dart:io';
import 'dart:ui' as ui;
import 'package:bdo_gathering_companion/src/domain/bairog_calculator.dart';
import 'package:bdo_gathering_companion/src/domain/models.dart';
import 'package:bdo_gathering_companion/src/ui/gathering_setup_dialog.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  setUpAll(() async {
    catalog = await Catalog.load();
    if (const bool.fromEnvironment('CAPTURE_GATHERING_SETUP')) {
      await _loadSetupCaptureFonts();
    }
  });
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1200, 800),
    double textScale = 1,
    double opacity = 60,
    GlobalKey? captureKey,
    ValueChanged<BairogCalculatorSettings>? onPreview,
    ValueChanged<BairogCalculatorSettings?>? onResult,
    BairogCalculatorSettings initial = const BairogCalculatorSettings(
      mastery: 1800,
      gatheringDropRatePercent: 40,
    ),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final theme = companionTheme(opacityPercent: opacity);
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: companionBackdropBuilder(context, child),
          ),
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  final result = await showGatheringSetupDialog(
                    context: context,
                    catalog: catalog,
                    initial: initial,
                    onPreview: onPreview,
                  );
                  onResult?.call(result);
                },
                child: const Text('Open stats'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open stats'));
    await tester.pumpAndSettle();
  }

  Future<void> advanced(WidgetTester tester) async {
    final target = find.descendant(
      of: find.byKey(const ValueKey('gathering-stats-advanced')),
      matching: find.byType(ListTile),
    );
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Your stats is compact and previews valid base inputs before saving',
    (tester) async {
      final previews = <BairogCalculatorSettings>[];
      BairogCalculatorSettings? result;
      await open(
        tester,
        onPreview: previews.add,
        onResult: (value) => result = value,
      );
      expect(find.text('Your stats'), findsOneWidget);
      expect(find.text('Base mastery'), findsOneWidget);
      expect(find.text('Base drop rate %'), findsOneWidget);
      expect(
        find.textContaining('Leave out the buffs selected in Prepare'),
        findsOneWidget,
      );
      expect(find.text('LIGHTSTONES'), findsNothing);
      expect(find.text('ARTIFACTS'), findsNothing);
      expect(find.byKey(const ValueKey('loot-option-afuaru')), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('gathering-setup-frame')))
            .height,
        lessThan(420),
      );
      await tester.enterText(
        find.byKey(const ValueKey('gathering-setup-mastery')),
        '1950',
      );
      await tester.enterText(
        find.byKey(const ValueKey('gathering-setup-gdr')),
        '47.5',
      );
      expect(previews.last.mastery, 1950);
      expect(previews.last.gatheringDropRatePercent, 47.5);
      await tester.tap(find.text('Save stats'));
      await tester.pumpAndSettle();
      expect(result?.mastery, 1950);
      expect(result?.gatheringDropRatePercent, 47.5);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Cancel returns no saved change and invalid input is not previewed',
    (tester) async {
      final previews = <BairogCalculatorSettings>[];
      var receivedResult = false;
      BairogCalculatorSettings? result;
      await open(
        tester,
        onPreview: previews.add,
        onResult: (value) {
          receivedResult = true;
          result = value;
        },
      );
      await tester.enterText(
        find.byKey(const ValueKey('gathering-setup-mastery')),
        '3001',
      );
      expect(previews.every((draft) => draft.mastery <= 3000), isTrue);
      await tester.tap(find.text('Save stats'));
      await tester.pumpAndSettle();
      expect(find.text('Mastery must be between 0 and 3,000.'), findsOneWidget);
      expect(receivedResult, isFalse);
      await tester.enterText(
        find.byKey(const ValueKey('gathering-setup-mastery')),
        '1900',
      );
      expect(previews.last.mastery, 1900);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(receivedResult, isTrue);
      expect(result, isNull);
    },
  );
  testWidgets('Stats groups share a left edge and comfortable gaps', (
    tester,
  ) async {
    await open(tester);
    final mastery = tester.getRect(
      find.byKey(const ValueKey('gathering-setup-mastery')),
    );
    final dropRate = tester.getRect(
      find.byKey(const ValueKey('gathering-setup-gdr')),
    );
    expect(dropRate.left - mastery.right, greaterThanOrEqualTo(16));
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('gathering-base-stats-note')))
          .dx,
      moreOrLessEquals(mastery.left),
    );
    final surface = tester.widget<GlassSurface>(
      find
          .descendant(
            of: find.byKey(const ValueKey('gathering-setup-dialog')),
            matching: find.byType(GlassSurface),
          )
          .first,
    );
    expect(surface.reading, isTrue);
    await advanced(tester);
    final disclosure = tester.widget<ExpansionTile>(
      find.byKey(const ValueKey('gathering-stats-advanced')),
    );
    expect(disclosure.expandedCrossAxisAlignment, CrossAxisAlignment.start);
    final energyRows = tester.widget<Wrap>(
      find.byKey(const ValueKey('gathering-setup-energy-expenses-grid')),
    );
    for (final row in energyRows.children.cast<SizedBox>()) {
      expect(row.width, lessThanOrEqualTo(540));
    }
    for (final heading in [
      'Gathering minigame',
      'LOOT OPTIONS',
      'ENERGY RECOVERY',
    ]) {
      expect(
        tester.getTopLeft(find.text(heading)).dx,
        moreOrLessEquals(mastery.left),
        reason: heading,
      );
    }
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('minigame-none'))).dy -
          tester.getBottomLeft(find.text('Gathering minigame')).dy,
      greaterThanOrEqualTo(10),
    );
    expect(tester.takeException(), isNull);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'Drop-rate help stays readable without changing stats at $scale',
      (tester) async {
        final previews = <BairogCalculatorSettings>[];
        await open(
          tester,
          size: const Size(420, 750),
          textScale: scale,
          initial: const BairogCalculatorSettings(
            gatheringDropRatePercent: 47.25,
          ),
          onPreview: previews.add,
        );
        final field = find.byKey(const ValueKey('gathering-setup-gdr'));
        final controller = tester.widget<TextField>(field).controller;
        final help = find.byKey(const ValueKey('gathering-drop-rate-help'));
        await tester.ensureVisible(help);
        await tester.pumpAndSettle();
        final hover = tester.widget<Tooltip>(
          find.byKey(const ValueKey('gathering-drop-rate-help-hover')),
        );
        expect(
          hover.message,
          contains('Additional Drop Rate (excluding Mastery)'),
        );
        await tester.tap(help);
        await tester.pumpAndSettle();
        final popup = find.byKey(
          const ValueKey('gathering-drop-rate-help-dialog'),
        );
        expect(popup, findsOneWidget);
        expect(tester.widget<AlertDialog>(popup).scrollable, isTrue);
        expect(
          find.textContaining('not “Basic Resource Drop Rate”'),
          findsOneWidget,
        );
        expect(
          find.text('52% with a selected +10% bonus: enter 42%.'),
          findsOneWidget,
        );
        expect(
          find.text('Gathering level is already reflected in Mastery.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller, same(controller));
        expect(controller!.text, '47.25');
        expect(previews, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Drop-rate hover and clicked help read clearly at25percent', (
    tester,
  ) async {
    const capture = bool.fromEnvironment('CAPTURE_GATHERING_SETUP');
    final oldShadows = debugDisableShadows;
    if (capture) debugDisableShadows = false;
    try {
      final key = GlobalKey();
      await open(
        tester,
        size: const Size(1500, 950),
        opacity: 25,
        captureKey: key,
      );
      final help = find.byKey(const ValueKey('gathering-drop-rate-help'));
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(help));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Use “Additional Drop Rate', findRichText: true),
        findsOneWidget,
      );
      if (capture) {
        await _captureSetup(tester, key, 'stats-drop-rate-hover-opacity25');
      }
      await mouse.moveTo(Offset.zero);
      await mouse.removePointer();
      await tester.pumpAndSettle();
      await tester.tap(help);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('gathering-drop-rate-help-dialog')),
        findsOneWidget,
      );
      if (capture) {
        await _captureSetup(tester, key, 'stats-drop-rate-help-opacity25');
      }
      expect(tester.takeException(), isNull);
    } finally {
      debugDisableShadows = oldShadows;
    }
  });
  testWidgets('Saved decimal stats survive a dialog Advanced-only change', (
    tester,
  ) async {
    final previews = <BairogCalculatorSettings>[];
    await open(
      tester,
      initial: const BairogCalculatorSettings(
        gatheringDropRatePercent: 47.25,
        yourEnergy: 500.125,
      ),
      onPreview: previews.add,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('gathering-setup-gdr')))
          .controller!
          .text,
      '47.25',
    );
    await advanced(tester);
    await tester.tap(find.byKey(const ValueKey('minigame-event')));
    expect(previews.last.gatheringDropRatePercent, 47.25);
    expect(previews.last.yourEnergy, 500.125);
  });
  testWidgets(
    'Advanced options retain pet tier, loot help, energy costs and rich information',
    (tester) async {
      final previews = <BairogCalculatorSettings>[];
      await open(tester, onPreview: previews.add);
      await advanced(tester);
      expect(find.text('Extra-gather pet tier'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hedgehog-4')));
      await tester.tap(find.byKey(const ValueKey('minigame-event')));
      expect(previews.last.hedgehogTier.storageValue, 4);
      expect(previews.last.minigameMode, BairogMinigameMode.event);
      const help = {
        'agris': 'Uses Agris Fever points',
        'afuaru': 'Rare goblin',
        'treasure-chests': 'deducts one Gold Key',
        'minigame-chest': 'not guaranteed',
        'fever-time': 'Automatic weekend gathering bonus',
        'evergreen-shard': 'replaced the old WON',
        'marketplace-tax': '84.5%',
      };
      for (final entry in help.entries) {
        final target = find.byKey(ValueKey('loot-option-${entry.key}'));
        expect(target, findsOneWidget);
        expect(
          tester
              .widget<Tooltip>(
                find.ancestor(of: target, matching: find.byType(Tooltip)),
              )
              .message,
          contains(entry.value),
        );
      }
      final afuaru = find.byKey(const ValueKey('loot-option-afuaru'));
      await tester.ensureVisible(afuaru);
      await tester.tap(afuaru);
      expect(previews.last.includeAfuaru, isFalse);
      final medicine = find.byKey(
        const ValueKey('energy-expense-info-buff-820150'),
      );
      await tester.ensureVisible(medicine);
      await tester.pumpAndSettle();
      await tester.tap(medicine);
      await tester.pumpAndSettle();
      expect(find.text('Simple Alchemy'), findsOneWidget);
      for (final ingredient in [
        'Energy Potion (Extra Large)',
        'Everlasting Herb',
        'Mysterious Powder',
        'Strange and Beautiful Herb',
      ]) {
        expect(
          find.byKey(ValueKey('buff-obtain-item-$ingredient')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in const [
    Size(1500, 950),
    Size(1200, 752),
    Size(700, 800),
    Size(420, 750),
  ]) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets(
        'Your stats fits $size at text $scale with advanced controls scrollable',
        (tester) async {
          final oldShadows = debugDisableShadows;
          const capture = bool.fromEnvironment('CAPTURE_GATHERING_SETUP');
          if (capture) debugDisableShadows = false;
          try {
            final key = GlobalKey();
            await open(tester, size: size, textScale: scale, captureKey: key);
            final frame = tester.getRect(
              find.byKey(const ValueKey('gathering-setup-frame')),
            );
            expect(frame.left, greaterThanOrEqualTo(16));
            expect(frame.right, lessThanOrEqualTo(size.width - 16));
            expect(frame.top, greaterThanOrEqualTo(16));
            expect(frame.bottom, lessThanOrEqualTo(size.height - 16));
            expect(frame.width, lessThanOrEqualTo(720));
            final suffix = scale == 1 ? '' : '-text200';
            if (capture) {
              await _captureSetup(
                tester,
                key,
                'stats-${size.width.toInt()}$suffix',
              );
            }
            await advanced(tester);
            if (capture) {
              await _captureSetup(
                tester,
                key,
                'stats-advanced-top-${size.width.toInt()}$suffix',
              );
            }
            final lastExpense = find.byKey(
              const ValueKey('energy-expense-info-buff-821145'),
            );
            await tester.ensureVisible(lastExpense);
            await tester.pumpAndSettle();
            expect(lastExpense.hitTestable(), findsOneWidget);
            expect(find.text('Save stats').hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (capture) {
              await _captureSetup(
                tester,
                key,
                'stats-advanced-${size.width.toInt()}$suffix',
              );
            }
          } finally {
            debugDisableShadows = oldShadows;
          }
        },
      );
    }
  }
}

Future<void> _captureSetup(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  for (final element
      in find
          .descendant(of: find.byKey(key), matching: find.byType(Image))
          .evaluate()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    const directory = String.fromEnvironment(
      'SETUP_CAPTURE_DIRECTORY',
      defaultValue: 'build/guided-workflow-evidence',
    );
    final file = File('$directory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _loadSetupCaptureFonts() async {
  final windowsRoot = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var flutterRoot = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${flutterRoot.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    final parent = flutterRoot.parent;
    if (parent.path == flutterRoot.path) {
      throw StateError('Flutter fonts not found.');
    }
    flutterRoot = parent;
  }
  final files = <String, List<String>>{
    'Segoe UI': [
      for (final name in ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf'])
        '$windowsRoot/Fonts/$name',
    ],
    'MaterialIcons': [
      '${flutterRoot.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
    'Roboto': [
      for (final name in ['roboto-regular.ttf', 'roboto-bold.ttf'])
        '${flutterRoot.path}/bin/cache/artifacts/material_fonts/$name',
    ],
  };
  for (final entry in files.entries) {
    final loader = FontLoader(entry.key);
    for (final file in entry.value) {
      loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
