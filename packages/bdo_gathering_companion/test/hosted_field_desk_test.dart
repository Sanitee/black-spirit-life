import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/src/domain/bairog_benchmarks.dart';
import 'package:bdo_gathering_companion/src/domain/bairog_calculator.dart';
import 'package:bdo_gathering_companion/src/domain/gathering_preparation.dart';
import 'package:bdo_gathering_companion/src/domain/models.dart';
import 'package:bdo_gathering_companion/src/domain/pets.dart';
import 'package:bdo_gathering_companion/src/gathering_companion_home.dart';
import 'package:bdo_gathering_companion/src/services/host_services.dart';
import 'package:bdo_gathering_companion/src/services/session_store.dart';
import 'package:bdo_gathering_companion/src/ui/field_guide.dart';
import 'package:bdo_gathering_companion/src/ui/gathering_preparation_panel.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_gathering_companion/src/ui/visual_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore extends SessionStore {
  _MemoryStore() : super(directory: Directory.systemTemp);
  int writes = 0;
  @override
  Future<void> save() async {
    writes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  final nativeCalls = <MethodCall>[];
  const channel = MethodChannel('bdo_gathering/native');
  setUpAll(() async {
    catalog = await Catalog.load();
    if (Platform.isWindows) {
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
      for (final entry in {
        'Segoe UI': [
          for (final name in ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf'])
            '$windowsRoot/Fonts/$name',
        ],
        'Georgia': [
          for (final name in ['georgia.ttf', 'georgiab.ttf'])
            '$windowsRoot/Fonts/$name',
        ],
        'Roboto': [
          for (final name in ['roboto-regular.ttf', 'roboto-bold.ttf'])
            '${flutterRoot.path}/bin/cache/artifacts/material_fonts/$name',
        ],
        'MaterialIcons': [
          '${flutterRoot.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
        ],
      }.entries) {
        final loader = FontLoader(entry.key);
        for (final file in entry.value) {
          loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
        }
        await loader.load();
      }
    }
  });
  setUp(() {
    nativeCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call);
          return true;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  _MemoryStore store({bool confirmed = true}) => _MemoryStore()
    ..preferences = {
      'methodId': 'butcher',
      'spotId': 'imp-cave-wolves',
      'unrelated-sentinel': 'preserved',
      gatheringPreparationPreferenceKey: GatheringPreparation(
        baseSettings: const BairogCalculatorSettings(
          mastery: 1800,
          gatheringDropRatePercent: 30,
          enabledExpenseItemIds: {},
        ),
        statsConfirmed: confirmed,
      ).toJson(),
    };

  Future<void> pump(
    WidgetTester tester,
    _MemoryStore memory, {
    Size size = const Size(1500, 950),
    double scale = 1,
    int opacity = 60,
    bool hosted = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    final theme = companionTheme(
      opacityPercent: opacity,
      visualPalette: hosted
          ? CompanionVisualPalette.decode(
                  const String.fromEnvironment('GATHERING_VISUAL_PALETTE'),
                ) ??
                CompanionVisualPalette.fieldDesk
          : null,
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        // ChipTheme's direct label styles do not inherit ThemeData.fontFamily
        // in widget tests, whose platform fallback is Ahem rather than Segoe.
        theme: theme.copyWith(
          chipTheme: theme.chipTheme.copyWith(
            labelStyle: theme.chipTheme.labelStyle?.copyWith(
              fontFamily: 'Segoe UI',
            ),
            secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(
              fontFamily: 'Segoe UI',
            ),
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(scale),
          ),
          child: RepaintBoundary(
            key: const ValueKey('field-desk-capture'),
            child: companionBackdropBuilder(context, child),
          ),
        ),
        home: GatheringHostServicesScope(
          services: GatheringHostServices(openExternal: (_) async => true),
          child: CompanionHome(
            catalog: catalog,
            store: memory,
            glassOpacityPercent: opacity,
            onGlassOpacityChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final folder = Platform.environment['CODEX_GATHERING_CAPTURE_DIR'];
    if (folder == null) return;
    // Frame settling alone does not wait for asynchronous asset decoding.
    // Resolve the actual visible providers outside the fake test clock before
    // taking the first screenshot, not only after the popup has been opened.
    final artwork = find
        .byType(Image)
        .evaluate()
        .where(
          (element) => switch ((element.widget as Image).image) {
            AssetImage() || ResizeImage() => true,
            _ => false,
          },
        )
        .toList();
    await tester.runAsync(() async {
      await Future.wait([
        for (final element in artwork)
          precacheImage((element.widget as Image).image, element),
      ]);
    });
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('field-desk-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(folder).create(recursive: true);
        await File(
          '$folder/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  testWidgets(
    'hosted field desk keeps map and records; links are explicit external actions',
    (tester) async {
      addTearDown(tester.view.reset);
      final memory = store();
      final spot = catalog.spots.firstWhere(
        (spot) => spot.id == 'imp-cave-wolves',
      );
      memory.sessions.add(
        GatheringSession(
          id: 'saved-fixture',
          createdAt: DateTime.utc(2026),
          methodId: 'butcher',
          methodLabel: 'Butchering',
          methodIcon: catalog.methods
              .firstWhere((method) => method.id == 'butcher')
              .icon,
          spotId: spot.id,
          spotName: spot.name,
          durationSeconds: 1800,
          mastery: 1800,
          loot: const [],
          buffs: const [],
          buffTotals: const {},
          catalogDate: catalog.reviewedAt,
        ),
      );
      final savedRecords = jsonEncode(
        memory.sessions.map((row) => row.toJson()).toList(),
      );
      await pump(tester, memory);
      expect(
        find.byKey(const ValueKey('gathering-field-rail')),
        findsOneWidget,
      );
      for (final key in [
        'workflow-spots',
        'workflow-prepare',
        'workflow-gather',
        'workflow-history',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing);
      }
      expect(find.text('Before buffs'), findsOneWidget);
      expect(find.text('1,800'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
      expect(find.byType(GatheringPreparationPanel), findsNothing);
      expect(memory.writes, 0);
      final mapState = tester.state(find.byType(FieldGuide));
      await tester.enterText(find.byKey(const ValueKey('spot-search')), 'Wolf');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('spot-card-imp-cave-wolves')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spot-detail-imp-cave-wolves')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('use-spot')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('gathering-buffs-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('close-gathering-buffs')));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(FieldGuide)), same(mapState));
      expect(
        find.byKey(const ValueKey('spot-detail-imp-cave-wolves')),
        findsOneWidget,
      );
      for (final key in ['open-bairog-source', 'open-garmoth-app']) {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
      }
      expect(
        nativeCalls
            .where((call) => call.method == 'openExternal')
            .map((call) => call.arguments['url']),
        [
          'https://bdoworkshop.com/gathering-calculator',
          'https://garmoth.com/app',
        ],
      );
      expect(
        jsonEncode(memory.sessions.map((row) => row.toJson()).toList()),
        savedRecords,
      );
      expect(memory.preferences['unrelated-sentinel'], 'preserved');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'buff popup uses real kits, preserves selections and enforces existing conflicts',
    (tester) async {
      addTearDown(tester.view.reset);
      final memory = store();
      await pump(tester, memory);
      await tester.tap(find.byKey(const ValueKey('open-gathering-buffs')));
      await tester.pumpAndSettle();
      expect(find.text('Life EXP +20%'), findsOneWidget);
      expect(find.text('Gathering speed +3 levels'), findsOneWidget);
      expect(find.text('Life skill mastery +25'), findsOneWidget);
      expect(find.text('Gathering item drop rate +10%'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('preparation-use-kit')));
      await tester.pumpAndSettle();
      GatheringPreparation current() => GatheringPreparation.fromPreferences(
        memory.preferences,
        catalog: catalog,
      );
      final gatheringKit = strings(
        catalog.presets.firstWhere(
          (p) => p['id'] == 'gathering-simple',
        )['buffIds'],
      );
      expect(current().buffIds, containsAll(gatheringKit));
      expect(
        find.byKey(const ValueKey('recommendations-effective-stats')),
        findsOneWidget,
      );
      final beforeSwitch = current().buffIds;
      await tester.tap(find.byKey(const ValueKey('buff-method-sniper')));
      await tester.pumpAndSettle();
      expect(
        current().buffIds,
        beforeSwitch,
        reason: 'Browsing a method never clears applied choices.',
      );
      await tester.tap(find.byKey(const ValueKey('preparation-use-kit')));
      await tester.pumpAndSettle();
      final sniperKit = strings(
        catalog.presets.firstWhere(
          (p) => p['id'] == 'sniper-simple',
        )['buffIds'],
      );
      expect(current().buffIds, containsAll(sniperKit));
      expect(current().buffIds, isNot(contains('buff-9691')));
      expect(current().buffIds, isNot(contains('buff-791')));
      expect(current().baseSettings.mastery, 1800);
      await tester.tap(find.byKey(const ValueKey('buff-method-hunting')));
      await tester.pumpAndSettle();
      expect(find.text('Elixir of Strong Shock'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'hosted pet selection survives method browsing and a fresh home reload',
    (tester) async {
      addTearDown(tester.view.reset);
      final pets = (await tester.runAsync(PetCatalog.load))!;
      final hedgehog = pets.firstWhere((pet) => pet.id == 'hedgehog');
      final legacySpot = catalog.spots.firstWhere(
        (spot) =>
            spot.methodIds.contains('hunting') &&
            !hedgehog.appliesTo(methodId: 'hunting', spotId: spot.id),
      );
      final memory = store();
      memory.preferences = {
        ...memory.preferences,
        'methodId': 'hunting',
        'spotId': legacySpot.id,
      };
      memory.sessions.add(
        GatheringSession(
          id: 'retained-hunting-record',
          createdAt: DateTime.utc(2026),
          methodId: 'hunting',
          methodLabel: 'Matchlock hunting',
          methodIcon: catalog.methods
              .firstWhere((method) => method.id == 'hunting')
              .icon,
          spotId: legacySpot.id,
          spotName: legacySpot.name,
          durationSeconds: 1800,
          mastery: 1500,
          loot: const [],
          buffs: const [],
          buffTotals: const {},
          catalogDate: catalog.reviewedAt,
        ),
      );
      final records = jsonEncode(
        memory.sessions.map((record) => record.toJson()).toList(),
      );
      GatheringPreparation current() => GatheringPreparation.fromPreferences(
        memory.preferences,
        catalog: catalog,
      );
      await pump(tester, memory);
      await tester.tap(find.byKey(const ValueKey('open-gathering-buffs')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('buff-method-hunting')),
            )
            .selected,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('buff-method-butcher')));
      await tester.pumpAndSettle();
      final gear = find.byKey(const ValueKey('recommendations-gear'));
      await tester.ensureVisible(gear);
      await tester.tap(gear);
      await tester.pumpAndSettle();
      final pet = find.byKey(const ValueKey('pet-icon-hedgehog'));
      await tester.ensureVisible(pet);
      await tester.tap(pet);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'T3'));
      await tester.pumpAndSettle();
      expect(current().petIds, contains('hedgehog'));
      expect(current().baseSettings.hedgehogTier, BairogHedgehogTier.tier3);
      expect(memory.preferences['methodId'], 'butcher');
      expect(memory.preferences['spotId'], '');

      await tester.tap(find.byKey(const ValueKey('buff-method-hunting')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pet-icon-hedgehog')), findsNothing);
      expect(
        find.byKey(const ValueKey('recommendations-effective-stats')),
        findsNothing,
      );
      // Hunting has source reference/session data, not a gathering projection
      // that could accidentally apply the retained extra-gather pet tier.
      expect(
        bairogBenchmarkSet.routes.where(
          (route) => route.methodId == 'hunting' || route.methodId == 'sniper',
        ),
        isEmpty,
      );
      final selectKit = find.byKey(const ValueKey('preparation-use-kit'));
      await tester.ensureVisible(selectKit);
      await tester.tap(selectKit);
      await tester.pumpAndSettle();
      expect(memory.preferences['methodId'], 'hunting');
      expect(current().petIds, contains('hedgehog'));
      final savedPreparation = jsonEncode(current().toJson());
      final writes = memory.writes;
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(tester, memory);
      expect(
        memory.writes,
        writes,
        reason: 'Browsing is not session recording.',
      );
      expect(jsonEncode(current().toJson()), savedPreparation);
      expect(current().baseSettings.hedgehogTier, BairogHedgehogTier.tier3);
      expect(current().baseSettings.mastery, 1800);
      expect(memory.preferences['unrelated-sentinel'], 'preserved');
      expect(
        jsonEncode(memory.sessions.map((record) => record.toJson()).toList()),
        records,
      );
      await tester.tap(find.byKey(const ValueKey('open-gathering-buffs')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('buff-method-hunting')),
            )
            .selected,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('buff-method-butcher')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(gear);
      await tester.tap(gear);
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(pet).properties.selected, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'rail stats editor previews, cancels and saves without changing selected buffs',
    (tester) async {
      addTearDown(tester.view.reset);
      final memory = store();
      await pump(tester, memory);
      final before = jsonEncode(memory.preferences);
      final mapState = tester.state(find.byType(FieldGuide));
      await tester.tap(find.byKey(const ValueKey('open-gathering-setup')));
      await tester.pumpAndSettle();
      expect(find.textContaining('selected in Buffs'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('gathering-setup-mastery')),
        '2000',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(jsonEncode(memory.preferences), before);
      expect(find.text('1,800'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('open-gathering-setup')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('gathering-setup-mastery')),
        '2000',
      );
      await tester.tap(find.byKey(const ValueKey('apply-gathering-setup')));
      await tester.pumpAndSettle();
      final saved = GatheringPreparation.fromPreferences(
        memory.preferences,
        catalog: catalog,
      );
      expect(saved.baseSettings.mastery, 2000);
      expect(saved.baseSettings.gatheringDropRatePercent, 30);
      expect(saved.buffIds, isEmpty);
      expect(find.text('2,000'), findsOneWidget);
      expect(tester.state(find.byType(FieldGuide)), same(mapState));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'unconfirmed stats stay blank and standalone keeps its workflow',
    (tester) async {
      addTearDown(tester.view.reset);
      final memory = store(confirmed: false);
      await pump(tester, memory);
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('1,800'), findsNothing);
      expect(memory.writes, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(tester, memory, hosted: false);
      for (final key in [
        'workflow-spots',
        'workflow-prepare',
        'workflow-gather',
        'workflow-history',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('open-gathering-buffs')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final fixture in [
    (width: 1500.0, height: 950.0, scale: 1.0),
    (width: 1200.0, height: 752.0, scale: 1.0),
    (width: 1000.0, height: 950.0, scale: 1.5),
  ]) {
    testWidgets(
      'real field desk and popup render at ${fixture.width}, scale ${fixture.scale}',
      (tester) async {
        addTearDown(tester.view.reset);
        final oldShadows = debugDisableShadows;
        try {
          debugDisableShadows = false;
          await pump(
            tester,
            store(),
            size: Size(fixture.width, fixture.height),
            scale: fixture.scale,
            opacity: const int.fromEnvironment(
              'GATHERING_CAPTURE_OPACITY',
              defaultValue: 60,
            ),
          );
          await capture(
            tester,
            'gathering-field-desk-${fixture.width.toInt()}-${fixture.scale}',
          );
          final mapState = tester.state(find.byType(FieldGuide));
          await tester.tap(find.byKey(const ValueKey('open-gathering-buffs')));
          await tester.pumpAndSettle();
          await capture(
            tester,
            'gathering-buffs-${fixture.width.toInt()}-${fixture.scale}',
          );
          final popup = tester.getRect(
            find.byKey(const ValueKey('gathering-buffs-dialog')),
          );
          expect(popup.left, greaterThanOrEqualTo(0));
          expect(popup.bottom, lessThanOrEqualTo(fixture.height));
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey('close-gathering-buffs')));
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(FieldGuide)), same(mapState));
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          debugDisableShadows = oldShadows;
        }
      },
    );
  }
}
