import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/domain/bairog_calculator.dart';
import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/domain/gathering_crystals.dart';
import 'package:bdo_gathering_companion/src/ui/gathering_crystal_recommendation.dart';
import 'package:bdo_gathering_companion/src/ui/gathering_preparation_panel.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureEvidence = bool.fromEnvironment('CAPTURE_GATHERING_CRYSTAL');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  setUpAll(() async {
    catalog = await Catalog.load();
    if (_captureEvidence) await _loadCaptureFonts();
  });

  test(
    'reviewed recommendation uses the full regular-slot cap and exact icon',
    () async {
      const crystal = gatheringCrystalRecommendation;
      expect(crystal.itemId, 15288);
      expect(crystal.maxCount, 12 + 2 + 2);
      expect(crystal.masteryEach, 15);
      expect(crystal.lifeExpPercentEach, 7);
      expect(crystal.slotNotes.first, contains('unlocked regular slots'));
      expect(
        crystal.slotNotes.join('\n'),
        contains('Garmoth-reformed awakening'),
      );
      expect(crystal.slotNotes.join('\n'), contains('LoML Kkebiwater'));
      expect(crystal.budgetNote, contains('instead'));
      expect(crystal.budgetNote, contains('Vital Crystal'));
      expect(crystal.calculatorNote, startsWith('Reference only.'));
      final data = await rootBundle.load(
        'packages/bdo_gathering_companion/${crystal.icon}',
      );
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final provenance =
          jsonDecode(
                await rootBundle.loadString(
                  'packages/bdo_gathering_companion/assets/icons/items/gathering-crystal-provenance.json',
                ),
              )
              as Map<String, dynamic>;
      expect(bytes.length, provenance['byteLength']);
      expect(sha256.convert(bytes).toString(), provenance['sha256']);
    },
  );

  testWidgets('compact icon reveals rich hover and the same pinned facts', (
    tester,
  ) async {
    final capture = GlobalKey();
    final rowCapture = GlobalKey();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 660);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: companionTheme(),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: rowCapture,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: GatheringCrystalRecommendation(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final chip = find.byKey(const ValueKey('gathering-crystal-recommendation'));
    // Icon, count and the discoverable info affordance remain content-sized.
    expect(tester.getSize(chip).width, lessThanOrEqualTo(140));
    expect(tester.getSize(chip).height, 44);
    expect(find.text('×16'), findsOneWidget);
    expect(find.text(gatheringCrystalRecommendation.name), findsNothing);
    if (_captureEvidence) {
      await _capture(tester, rowCapture, 'gathering-crystal-compact-row');
    }
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(chip));
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.byKey(const ValueKey('gathering-crystal-hover-card')),
      findsOneWidget,
    );
    for (final line in [
      gatheringCrystalRecommendation.name,
      'Life Skill Mastery +15',
      'Life EXP +7%',
      ...gatheringCrystalRecommendation.slotNotes,
      gatheringCrystalRecommendation.budgetNote,
      gatheringCrystalRecommendation.calculatorNote,
    ]) {
      expect(find.text(line), findsOneWidget);
    }
    final hoverRect = tester.getRect(
      find.byKey(const ValueKey('gathering-crystal-hover-card')),
    );
    expect(hoverRect.contains(tester.getCenter(chip)), isTrue);
    await tester.tapAt(tester.getCenter(chip), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('gathering-crystal-hover-card')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('gathering-crystal-pinned-card')),
      findsOneWidget,
    );
    expect(find.text('Life Skill Mastery +15'), findsOneWidget);
    expect(
      find.text(gatheringCrystalRecommendation.budgetNote),
      findsOneWidget,
    );
    if (_captureEvidence) {
      await _capture(tester, capture, 'gathering-crystal-pinned-details');
    }
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(const ValueKey('gathering-crystal-pinned-card')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('close-gathering-crystal-details')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('gathering-crystal-pinned-card')),
      findsNothing,
    );
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary click replaces an existing hover with one pinned card', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(),
        home: const Scaffold(
          body: Center(child: GatheringCrystalRecommendation()),
        ),
      ),
    );
    final chip = find.byKey(const ValueKey('gathering-crystal-recommendation'));
    final hover = find.byKey(const ValueKey('gathering-crystal-hover-card'));
    final pinned = find.byKey(const ValueKey('gathering-crystal-pinned-card'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(chip));
    await tester.pump(const Duration(milliseconds: 350));
    expect(hover, findsOneWidget);
    expect(tester.getRect(hover).contains(tester.getCenter(chip)), isFalse);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(hover, findsNothing);
    expect(pinned, findsOneWidget);
    expect(find.text(gatheringCrystalRecommendation.name), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(hover, findsNothing);
    expect(pinned, findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.tap(
      find.byKey(const ValueKey('close-gathering-crystal-details')),
    );
    await tester.pumpAndSettle();
    expect(pinned, findsNothing);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('rich details fit a small viewport with 200% text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 480);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: Center(child: GatheringCrystalRecommendation()),
        ),
      ),
    );
    final chip = find.byKey(const ValueKey('gathering-crystal-recommendation'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(chip));
    await tester.pump(const Duration(milliseconds: 350));
    final hover = find.byKey(const ValueKey('gathering-crystal-hover-card'));
    expect(hover, findsOneWidget);
    expect(tester.getRect(hover).left, greaterThanOrEqualTo(12));
    expect(tester.getRect(hover).right, lessThanOrEqualTo(308));
    expect(tester.getRect(hover).bottom, lessThanOrEqualTo(468));
    expect(tester.takeException(), isNull);
    // The hover overlaps its chip in this viewport; right-clicking the card
    // must still promote the same details to a pinned surface.
    expect(tester.getRect(hover).contains(tester.getCenter(chip)), isTrue);
    await tester.tapAt(tester.getCenter(chip), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final pinned = find.byKey(const ValueKey('gathering-crystal-pinned-card'));
    final scroll = find.descendant(
      of: pinned,
      matching: find.byType(SingleChildScrollView),
    );
    expect(tester.getRect(scroll).left, greaterThanOrEqualTo(16));
    expect(tester.getRect(scroll).right, lessThanOrEqualTo(304));
    expect(tester.getRect(scroll).top, greaterThanOrEqualTo(16));
    expect(tester.getRect(scroll).bottom, lessThanOrEqualTo(464));
    await tester.ensureVisible(
      find.text(gatheringCrystalRecommendation.calculatorNote),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(gatheringCrystalRecommendation.calculatorNote).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  });

  for (final width in [900.0, 1500.0]) {
    testWidgets(
      'Prepare keeps crystal reference below Lightstones without changing setup at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 940);
        addTearDown(tester.view.reset);
        const initial = BairogCalculatorSettings(
          mastery: 1735,
          gatheringDropRatePercent: 47,
        );
        var profileChanges = 0;
        const selectedBuffs = {'buff-yawning-hedgehog'};
        const selectedPets = <String>{};
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: GatheringPreparationPanel(
                    catalog: catalog,
                    methodId: 'butcher',
                    spotId: null,
                    selectedBuffIds: selectedBuffs,
                    selectedPetIds: selectedPets,
                    pets: const [],
                    baseSettings: initial,
                    effectiveSettings: initial,
                    statsConfirmed: true,
                    onToggleBuff: (_) => profileChanges++,
                    onTogglePet: (_) => profileChanges++,
                    onPreset: (_) => profileChanges++,
                    onClearBuffs: () => profileChanges++,
                    onClearPets: () => profileChanges++,
                    onStatsChanged: (_, _) => profileChanges++,
                    onStatsValidityChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final row = find.byType(GatheringCrystalRecommendation);
        final lightstones = find.byKey(
          const ValueKey('preparation-lightstones'),
        );
        final allBuffs = find.byKey(
          const ValueKey('preparation-all-buffs-toggle'),
        );
        expect(
          tester.getTopLeft(row).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(lightstones).dy),
        );
        expect(
          tester.getBottomLeft(row).dy,
          lessThan(tester.getTopLeft(allBuffs).dy),
        );
        await tester.ensureVisible(allBuffs);
        await tester.tap(allBuffs);
        await tester.pumpAndSettle();
        final energy = find.byKey(const ValueKey('buff-row-energy'));
        expect(energy, findsOneWidget);
        expect(
          tester.getBottomLeft(row).dy,
          lessThan(tester.getTopLeft(energy).dy),
        );
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('gathering-crystal-recommendation')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('gathering-crystal-pinned-card')),
          findsOneWidget,
        );
        expect(find.text(gatheringCrystalRecommendation.name), findsOneWidget);
        expect(profileChanges, 0);
        await tester.tap(
          find.byKey(const ValueKey('close-gathering-crystal-details')),
        );
        await tester.pumpAndSettle();
        final panel = tester.widget<GatheringPreparationPanel>(
          find.byType(GatheringPreparationPanel),
        );
        expect(panel.baseSettings.toJson(), initial.toJson());
        expect(panel.effectiveSettings.toJson(), initial.toJson());
        expect(panel.selectedBuffIds, selectedBuffs);
        expect(panel.selectedPetIds, selectedPets);
        expect(profileChanges, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
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
    final file = File('build/crystal-reference-evidence/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _loadCaptureFonts() async {
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
  final fontFiles = <String, List<String>>{
    'Segoe UI': [
      for (final name in ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf'])
        '$windowsRoot/Fonts/$name',
    ],
    'MaterialIcons': [
      '${flutterRoot.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
  };
  for (final entry in fontFiles.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
