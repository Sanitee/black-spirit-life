import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/src/domain/bairog_calculator.dart';
import 'package:bdo_gathering_companion/src/domain/gathering_preparation.dart';
import 'package:bdo_gathering_companion/src/domain/models.dart';
import 'package:bdo_gathering_companion/src/gathering_companion_home.dart';
import 'package:bdo_gathering_companion/src/services/host_services.dart';
import 'package:bdo_gathering_companion/src/services/session_store.dart';
import 'package:bdo_gathering_companion/src/ui/expedition_chrome.dart';
import 'package:bdo_gathering_companion/src/ui/field_desk_materials.dart';
import 'package:bdo_gathering_companion/src/ui/field_guide.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_gathering_companion/src/ui/visual_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore extends SessionStore {
  _MemoryStore() : super(directory: Directory.systemTemp);
  @override
  Future<void> save() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  setUpAll(() async {
    catalog = await Catalog.load();
    if (Platform.isWindows) {
      final root = Platform.environment['WINDIR'] ?? r'C:\Windows';
      var flutterRoot = File(Platform.resolvedExecutable).parent;
      while (!Directory(
        '${flutterRoot.path}/bin/cache/artifacts/material_fonts',
      ).existsSync()) {
        final parent = flutterRoot.parent;
        if (parent.path == flutterRoot.path) {
          throw StateError('Flutter font path missing');
        }
        flutterRoot = parent;
      }
      final iconFont = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '${flutterRoot.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        );
      await iconFont.load();
      for (final entry in {
        'Segoe UI': ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf'],
        'Georgia': ['georgia.ttf', 'georgiab.ttf'],
      }.entries) {
        final loader = FontLoader(entry.key);
        for (final name in entry.value) {
          loader.addFont(
            File('$root/Fonts/$name').readAsBytes().then(ByteData.sublistView),
          );
        }
        await loader.load();
      }
    }
  });

  testWidgets('hosted spot cards preserve geometry and scroll-bounded shadows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 950);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(visualPalette: CompanionVisualPalette.fieldDesk),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Material(
          type: MaterialType.transparency,
          child: FieldGuide(catalog: catalog, onUse: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('spot-list'));
    final clip = tester.widget<ClipRect>(
      find.byKey(const ValueKey('spot-list-shadow-viewport')),
    );
    expect(tester.widget<ListView>(list).clipBehavior, Clip.none);
    final listSize = tester.getSize(list);
    expect(
      clip.clipper!.getClip(listSize),
      Rect.fromLTRB(-8, 0, listSize.width + 8, listSize.height),
      reason:
          'Only shadow gutters expand; scrolled cards stay vertically clipped.',
    );
    final cards = find.descendant(
      of: list,
      matching: find.byType(GlassControl),
    );
    final card = cards.first;
    expect(tester.getSize(card), const Size(312, 60));
    expect(tester.widget<GlassControl>(card).leadingWidth, 68);
    expect(tester.widget<GlassControl>(card).copperInlay, isTrue);
    expect(tester.widget<GlassControl>(card).radius, 8);
    final icon = find
        .descendant(of: card, matching: find.byType(GameIcon))
        .first;
    expect(tester.getSize(icon), const Size(44, 44));
    expect(tester.getRect(icon).left - tester.getRect(card).left, 12);
    expect(tester.getRect(icon).top - tester.getRect(card).top, 8);
    expect(tester.widget<GameIcon>(icon).recessed, isTrue);
    expect(
      find.ancestor(of: card, matching: find.byType(ClipRRect)),
      findsNothing,
      reason: 'A rounded parent must not clip the external contact shadow.',
    );
    expect(
      tester
          .widget<Material>(
            find.descendant(of: card, matching: find.byType(Material)).first,
          )
          .clipBehavior,
      Clip.antiAlias,
      reason: 'Artwork, content and ink still clip to the card face.',
    );
    final state = tester.state(find.byType(FieldGuide));
    await tester.drag(list, const Offset(0, -190));
    await tester.pumpAndSettle();
    expect(tester.widget<ListView>(list).controller!.offset, greaterThan(0));
    expect(tester.state(find.byType(FieldGuide)), same(state));
    await tester.enterText(find.byKey(const ValueKey('spot-search')), 'Wolf');
    await tester.pumpAndSettle();
    final wolf = find.byKey(const ValueKey('spot-card-imp-cave-wolves'));
    await tester.tap(wolf);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('spot-detail-imp-cave-wolves')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('compact raised cards retain readable enlarged type and opacity', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(860, 950);
    addTearDown(tester.view.reset);
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      for (final percent in [0, 60, 100]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(
              opacityPercent: percent,
              visualPalette: CompanionVisualPalette.fieldDesk,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(1.5),
              ),
              child: RepaintBoundary(
                key: const ValueKey('codex-gathering-capture'),
                child: child!,
              ),
            ),
            home: Material(
              type: MaterialType.transparency,
              child: FieldGuide(catalog: catalog, onUse: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final strip = find.byKey(const ValueKey('spot-strip'));
        final list = tester.widget<ListView>(strip);
        expect(list.clipBehavior, Clip.hardEdge);
        expect(list.padding, const EdgeInsets.fromLTRB(16, 0, 16, 8));
        final card = find
            .descendant(of: strip, matching: find.byType(GlassControl))
            .first;
        expect(tester.getSize(card).width, 828);
        expect(tester.getSize(card).height, greaterThanOrEqualTo(60));
        expect(tester.widget<GlassControl>(card).leadingWidth, 68);
        expect(tester.widget<GlassControl>(card).copperInlay, isTrue);
        expect(tester.widget<GlassControl>(card).radius, 8);
        final icon = find
            .descendant(of: card, matching: find.byType(GameIcon))
            .first;
        expect(tester.getSize(icon), const Size(44, 44));
        final artwork = tester.widget<Image>(
          find.descendant(of: icon, matching: find.byType(Image)).first,
        );
        expect(artwork.opacity, isNull);
        expect(artwork.color, isNull);
        expect(
          find.descendant(of: card, matching: find.byType(Opacity)),
          findsNothing,
          reason: 'Surface opacity must not fade text or bundled artwork.',
        );
        final colors = tester.element(card).gatheringColors;
        expect(colors.ink.a, 1);
        expect(colors.muted.a, 1);
        expect(
          tester.element(card).glass.effectStrength,
          closeTo(percent == 0 ? .02 / .76 : (percent / 76).clamp(0, 1), 1e-12),
        );
        expect(
          find.ancestor(of: card, matching: find.byType(ClipRRect)),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          'gathering-raised-compact-150text-${percent}opacity',
        );
        list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final lastCard = find
            .descendant(of: strip, matching: find.byType(GlassControl))
            .last;
        expect(
          tester.getRect(lastCard).bottom,
          lessThanOrEqualTo(tester.getRect(strip).bottom),
          reason:
              'The final card and its padding stay inside the scroll viewport.',
        );
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          'gathering-raised-compact-150text-${percent}opacity-scrolled',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    } finally {
      debugDisableShadows = oldShadows;
    }
  });

  testWidgets(
    'Codex field desk keeps compact vertical rail and retained stages',
    (tester) async {
      final oldShadows = debugDisableShadows;
      try {
        if (Platform.environment['CODEX_GATHERING_CAPTURE_DIR'] != null) {
          debugDisableShadows = false;
        }
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1500, 950);
        addTearDown(tester.view.reset);
        final store = _MemoryStore()
          ..preferences = {
            'methodId': 'butcher',
            'spotId': 'imp-cave-wolves',
            gatheringPreparationPreferenceKey: GatheringPreparation(
              baseSettings: const BairogCalculatorSettings(
                mastery: 1800,
                gatheringDropRatePercent: 30,
                enabledExpenseItemIds: {},
              ),
              statsConfirmed: true,
            ).toJson(),
          };
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(
              opacityPercent: const int.fromEnvironment(
                'GATHERING_CAPTURE_OPACITY',
                defaultValue: 60,
              ),
              visualPalette: CompanionVisualPalette.decode(
                const String.fromEnvironment('GATHERING_VISUAL_PALETTE'),
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: RepaintBoundary(
                key: const ValueKey('codex-gathering-capture'),
                child: companionBackdropBuilder(context, child),
              ),
            ),
            home: GatheringHostServicesScope(
              services: GatheringHostServices(openExternal: (_) async => true),
              child: CompanionHome(
                catalog: catalog,
                store: store,
                glassOpacityPercent: const int.fromEnvironment(
                  'GATHERING_CAPTURE_OPACITY',
                  defaultValue: 60,
                ),
                onGlassOpacityChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final rail = find.byKey(const ValueKey('gathering-field-rail'));
        expect(rail, findsOneWidget);
        expect(find.byKey(const ValueKey('workflow-tabs')), findsNothing);
        expect(tester.getSize(rail).width, 160);
        expect(tester.getSize(rail).height, lessThan(540));
        final railGlass = tester.element(rail).glass;
        if (railGlass.visualPalette != null) {
          final decoration =
              tester.widget<Container>(rail).decoration! as BoxDecoration;
          expect(decoration.gradient, railGlass.headerGradient);
          expect(
            (decoration.gradient! as LinearGradient).colors.first.a,
            railGlass.surfaceOpacity,
            reason: 'Hosted rail material must not be attenuated cubically.',
          );
        }
        expect(
          find.ancestor(
            of: find.byType(IndexedStack).first,
            matching: find.byType(GatheringStageReveal),
          ),
          findsNothing,
          reason:
              'Stage motion must not composite or translate the retained map.',
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('gathering-workspace-heading')),
            matching: find.byType(GatheringStageReveal),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: rail,
            matching: find.byKey(const ValueKey('open-minigame-helper')),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .getRect(
                find.byKey(const ValueKey('gathering-retained-workspace')),
              )
              .left,
          160,
        );
        // Saved location can open its detail. Return to the retained finder.
        final change = find.byKey(const ValueKey('guide-change-spot'));
        if (change.evaluate().isNotEmpty) {
          await tester.tap(change);
          await tester.pumpAndSettle();
        }
        await _capture(tester, 'gathering-finder-1500');
        expect(
          tester
              .getSize(find.byKey(const ValueKey('spot-journal-surface')))
              .width,
          336,
        );
        await tester.enterText(
          find.byKey(const ValueKey('spot-search')),
          'Wolf',
        );
        await tester.pumpAndSettle();
        final state = tester.state(find.byType(FieldGuide));
        for (final width in [1099.0, 1100.0, 1200.0, 1000.0, 1500.0]) {
          tester.view.physicalSize = Size(width, 950);
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(FieldGuide)), same(state));
          expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('spot-search')))
                .controller!
                .text,
            'Wolf',
          );
          expect(tester.takeException(), isNull);
          expect(rail, width >= 1100 ? findsOneWidget : findsNothing);
          await _capture(tester, 'gathering-finder-${width.round()}-filtered');
        }
        for (final height in [539.0, 540.0, 950.0]) {
          tester.view.physicalSize = Size(1500, height);
          await tester.pumpAndSettle();
          expect(rail, height >= 540 ? findsOneWidget : findsNothing);
          expect(tester.state(find.byType(FieldGuide)), same(state));
          expect(tester.takeException(), isNull);
        }
        for (final entry in {
          'workflow-prepare': 'gathering-preparation',
          'workflow-gather': 'gathering-record',
          'workflow-history': 'gathering-journal',
        }.entries) {
          await tester.tap(find.byKey(ValueKey(entry.key)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await _capture(tester, entry.value);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDisableShadows = oldShadows;
      }
    },
  );

  testWidgets('populated field desk retains real session and ranked screens', (
    tester,
  ) async {
    final oldShadows = debugDisableShadows;
    try {
      if (Platform.environment['CODEX_GATHERING_CAPTURE_DIR'] != null) {
        debugDisableShadows = false;
      }
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 950);
      addTearDown(tester.view.reset);
      final spot = catalog.spots.firstWhere((s) => s.id == 'imp-cave-wolves');
      final method = catalog.methods.firstWhere((m) => m.id == 'butcher');
      final loot = catalog.lootForSpot(spot, method.id).take(4).toList();
      final session = GatheringSession(
        id: 'field-desk-capture-session',
        createdAt: DateTime.utc(2026, 10, 18, 12),
        methodId: method.id,
        methodLabel: method.label,
        methodIcon: method.icon,
        spotId: spot.id,
        spotName: spot.name,
        durationSeconds: 3600,
        mastery: 1800,
        loot: [
          for (var i = 0; i < loot.length; i++)
            LootEntry(
              id: loot[i].id,
              name: loot[i].name,
              icon: loot[i].icon,
              overrideTotal: [12480, 1380, 42, 187][i],
            ),
        ],
        buffs: const [],
        buffTotals: const {},
        catalogDate: 'synthetic visual fixture; bundled catalog',
      );
      final store = _MemoryStore()
        ..sessions.add(session)
        ..preferences = {
          'methodId': method.id,
          'spotId': spot.id,
          gatheringPreparationPreferenceKey: GatheringPreparation(
            baseSettings: const BairogCalculatorSettings(
              mastery: 1800,
              gatheringDropRatePercent: 30,
              enabledExpenseItemIds: {},
            ),
            statsConfirmed: true,
          ).toJson(),
        };
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(
            opacityPercent: 100,
            visualPalette: CompanionVisualPalette.decode(
              const String.fromEnvironment('GATHERING_VISUAL_PALETTE'),
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: RepaintBoundary(
              key: const ValueKey('codex-gathering-capture'),
              child: companionBackdropBuilder(context, child),
            ),
          ),
          home: GatheringHostServicesScope(
            services: GatheringHostServices(openExternal: (_) async => true),
            child: CompanionHome(
              catalog: catalog,
              store: store,
              glassOpacityPercent: 100,
              onGlassOpacityChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final homeState = tester.state(find.byType(CompanionHome));
      await tester.tap(find.byKey(const ValueKey('workflow-history')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('history-session-${session.id}')),
        findsOneWidget,
      );
      Finder journalPanel() => find.descendant(
        of: find.byKey(ValueKey('history-session-${session.id}')),
        matching: find.byType(FieldDeskPanel),
      );
      expect(
        tester.widget<FieldDeskPanel>(journalPanel()).leadingHeight,
        isNull,
      );
      await _capture(tester, 'gathering-journal-populated-1500');
      tester.view.physicalSize = const Size(900, 950);
      await tester.pumpAndSettle();
      expect(tester.widget<FieldDeskPanel>(journalPanel()).leadingHeight, 72);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'gathering-journal-populated-900');
      tester.view.physicalSize = const Size(1500, 950);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('edit-session-${session.id}')));
      await tester.pumpAndSettle();
      final amount = find.byKey(ValueKey('loot-total-${loot.first.id}'));
      expect(
        tester.widget<TextField>(amount).controller!.text.replaceAll(',', ''),
        '12480',
      );
      final amountController = tester.widget<TextField>(amount).controller;
      final firstRow = find.byKey(ValueKey('loot-row-${loot.first.id}'));
      final firstArt = find.descendant(
        of: firstRow,
        matching: find.byType(GameIcon),
      );
      expect(tester.getRect(firstArt).left - tester.getRect(firstRow).left, 2);
      expect(tester.getSize(firstArt), const Size(40, 40));
      await _capture(tester, 'gathering-record-populated-1500');
      tester.view.physicalSize = const Size(1200, 752);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(amount).controller,
        same(amountController),
      );
      expect(tester.takeException(), isNull);
      await _capture(tester, 'gathering-record-populated-1200');
      tester.view.physicalSize = const Size(1500, 950);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workflow-spots')));
      await tester.pumpAndSettle();
      final change = find.byKey(const ValueKey('guide-change-spot'));
      if (change.evaluate().isNotEmpty) {
        await tester.tap(change);
        await tester.pumpAndSettle();
      }
      await _capture(tester, 'gathering-finder-100opacity-1500');
      await tester.tap(
        find.byKey(const ValueKey('spot-filter-compact-control')),
      );
      await tester.pumpAndSettle();
      final sharp = find.byKey(const ValueKey('spot-ranking-sharp'));
      await tester.ensureVisible(sharp);
      await tester.tap(sharp);
      await tester.pumpAndSettle();
      await _capture(tester, 'gathering-finder-ranked-1500');
      final browse = find.byKey(const ValueKey('spot-ranking-browse'));
      await tester.ensureVisible(browse);
      await tester.tap(browse);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('spot-search')), 'Wolf');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('spot-card-${spot.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('spot-detail-${spot.id}')), findsOneWidget);
      await _capture(tester, 'gathering-selected-detail-1500');
      expect(tester.state(find.byType(CompanionHome)), same(homeState));
      expect(store.sessions.single, same(session));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDisableShadows = oldShadows;
    }
  });
}

Future<void> _capture(WidgetTester tester, String name) async {
  final target = Platform.environment['CODEX_GATHERING_CAPTURE_DIR'];
  if (target == null) return;
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('codex-gathering-capture')),
  );
  await tester.runAsync(() async {
    await Directory(target).create(recursive: true);
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File('$target/$name.png').writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    image.dispose();
  });
}
