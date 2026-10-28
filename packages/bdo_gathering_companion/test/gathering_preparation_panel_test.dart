import 'dart:io';
import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/src/domain/bairog_calculator.dart';
import 'package:bdo_gathering_companion/src/domain/gathering_preparation.dart';
import 'package:bdo_gathering_companion/src/domain/matchlock_advice.dart';
import 'package:bdo_gathering_companion/src/domain/models.dart';
import 'package:bdo_gathering_companion/src/domain/pets.dart';
import 'package:bdo_gathering_companion/src/gathering_companion_home.dart';
import 'package:bdo_gathering_companion/src/services/host_services.dart';
import 'package:bdo_gathering_companion/src/services/session_store.dart';
import 'package:bdo_gathering_companion/src/ui/buff_picker.dart';
import 'package:bdo_gathering_companion/src/ui/gathering_preparation_panel.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Harness extends StatefulWidget {
  const _Harness({
    super.key,
    required this.catalog,
    required this.pets,
    this.methodId = 'butcher',
    this.statsConfirmed = true,
    this.scale = 1,
    this.captureKey,
    this.disableAnimations = false,
  });
  final Catalog catalog;
  final List<PetRecommendation> pets;
  final String methodId;
  final bool statsConfirmed;
  final double scale;
  final GlobalKey? captureKey;
  final bool disableAnimations;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _PrepareMemoryStore extends SessionStore {
  _PrepareMemoryStore() : super(directory: Directory.systemTemp);
  @override
  Future<void> save() async {}
}

class _HarnessState extends State<_Harness> {
  late GatheringPreparation profile = GatheringPreparation(
    baseSettings: const BairogCalculatorSettings(
      mastery: 1800,
      gatheringDropRatePercent: 40,
    ),
    statsConfirmed: widget.statsConfirmed,
  );
  var edits = 0;
  bool statsValid = true, statsEnabled = true;
  Object? statsContextId;
  void update(VoidCallback mutation) => setState(mutation);
  void toggle(Buff buff) => setState(() {
    final selected = Set<String>.from(profile.buffIds);
    if (!selected.remove(buff.id)) {
      selected.removeWhere(
        (id) => buff.conflictsWith(
          widget.catalog.buffs.firstWhere((entry) => entry.id == id),
        ),
      );
      selected.add(buff.id);
    }
    profile = profile.withBuffIds(selected, widget.catalog);
  });
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: widget.captureKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: companionTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(widget.scale),
          disableAnimations: widget.disableAnimations,
        ),
        child: companionBackdropBuilder(context, child),
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: GatheringPreparationPanel(
            catalog: widget.catalog,
            methodId: widget.methodId,
            spotId: null,
            selectedBuffIds: profile.buffIds,
            selectedPetIds: profile.petIds,
            pets: widget.pets,
            baseSettings: profile.baseSettings,
            effectiveSettings: profile.effectiveSettings(widget.catalog),
            statsConfirmed: profile.statsConfirmed,
            onToggleBuff: toggle,
            onTogglePet: (pet) => setState(() {
              final ids = Set<String>.from(profile.petIds);
              if (!ids.remove(pet.id)) ids.add(pet.id);
              profile = profile.withPetIds(ids);
            }),
            onPreset: (preset) => setState(
              () => profile = profile.withBuffIds(
                strings(preset['buffIds']).toSet(),
                widget.catalog,
              ),
            ),
            onClearBuffs: () => setState(
              () => profile = profile.withBuffIds({}, widget.catalog),
            ),
            onClearPets: () => setState(() => profile = profile.withPetIds({})),
            onStatsChanged: (settings, confirmed) => setState(() {
              edits++;
              profile = profile.withBaseSettings(
                settings,
                widget.catalog,
                statsConfirmed: confirmed,
              );
            }),
            onStatsValidityChanged: (valid) => statsValid = valid,
            statsEnabled: statsEnabled,
            statsContextId: statsContextId,
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  late List<PetRecommendation> pets;
  setUpAll(() async {
    catalog = await Catalog.load();
    pets = await PetCatalog.load();
    if (const bool.fromEnvironment('CAPTURE_GATHERING_PREPARATION')) {
      await _loadPreparationCaptureFonts();
    }
  });
  Future<GlobalKey<_HarnessState>> open(
    WidgetTester tester, {
    Size size = const Size(1100, 1000),
    double scale = 1,
    bool confirmed = true,
    String methodId = 'butcher',
    GlobalKey? captureKey,
    bool disableAnimations = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      _Harness(
        key: key,
        catalog: catalog,
        pets: pets,
        scale: scale,
        statsConfirmed: confirmed,
        methodId: methodId,
        captureKey: captureKey,
        disableAnimations: disableAnimations,
      ),
    );
    await tester.pumpAndSettle();
    return key;
  }

  testWidgets(
    'artifact pair references retain accepted artwork and never add stats',
    (tester) async {
      final key = await open(tester);
      final before = key.currentState!.profile.toJson();
      for (final entry in const {
        '735353': '+4% Gathering Item Drop Rate',
        '735367': '+20 Gathering Mastery',
      }.entries) {
        final chip = find.byKey(ValueKey('preparation-artifact-${entry.key}'));
        await tester.ensureVisible(chip);
        expect(
          tester
              .widget<GameIcon>(
                find.descendant(of: chip, matching: find.byType(GameIcon)),
              )
              .path,
          'assets/icons/items/${entry.key}.webp',
        );
        expect(
          find.descendant(of: chip, matching: find.byIcon(Icons.info_outline)),
          findsOneWidget,
        );
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('preparation-artifact-details-${entry.key}')),
          findsOneWidget,
        );
        expect(find.text(entry.value), findsOneWidget);
        expect(
          find.text('Choose one pair; these are alternatives.'),
          findsOneWidget,
        );
        expect(key.currentState!.profile.toJson(), before);
        await tester.tap(
          find.byKey(ValueKey('close-preparation-artifact-${entry.key}')),
        );
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Journal layout uses readable choices without nested sparse panels',
    (tester) async {
      await open(tester);
      final kit = find.byKey(const ValueKey('preparation-kit-section'));
      expect(
        find.ancestor(of: kit, matching: find.byType(GlassSurface)),
        findsNothing,
      );
      final choice = find.byKey(const ValueKey('preparation-kit-buff-791'));
      expect(tester.getSize(choice).width, lessThanOrEqualTo(360));
      expect(
        tester
            .widget<GameIcon>(
              find.descendant(of: choice, matching: find.byType(GameIcon)),
            )
            .size,
        40,
      );
      final label = tester.widget<Text>(
        find.descendant(of: choice, matching: find.text('Verdure Draught')),
      );
      expect(label.style!.fontSize, greaterThanOrEqualTo(14));
      final all = find.byKey(const ValueKey('preparation-all-buffs-toggle'));
      expect(tester.getSize(all).width, lessThanOrEqualTo(230));
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('artifact hover uses normal typography at text $scale', (
      tester,
    ) async {
      final shadows = debugDisableShadows;
      const capture = bool.fromEnvironment('CAPTURE_GATHERING_PREPARATION');
      if (capture) debugDisableShadows = false;
      try {
        final captureKey = GlobalKey();
        await open(
          tester,
          size: const Size(1200, 752),
          scale: scale,
          captureKey: captureKey,
        );
        final chip = find.byKey(const ValueKey('preparation-artifact-735353'));
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(chip));
        await tester.pump(const Duration(milliseconds: 350));
        final hover = find.byKey(
          const ValueKey('preparation-artifact-hover-735353'),
        );
        expect(hover, findsOneWidget);
        final bounds = tester.getRect(hover);
        expect(bounds.left, greaterThanOrEqualTo(12));
        expect(bounds.right, lessThanOrEqualTo(1188));
        expect(bounds.bottom, lessThanOrEqualTo(740));
        final title = tester.widget<Text>(
          find.descendant(
            of: hover,
            matching: find.text('2× Gathering Item Drop Rate'),
          ),
        );
        final effect = tester.widget<Text>(
          find.descendant(
            of: hover,
            matching: find.text('+4% Gathering Item Drop Rate'),
          ),
        );
        expect(title.style!.fontSize, 16);
        expect(effect.style!.fontSize, 14);
        for (final rich in tester.widgetList<RichText>(
          find.descendant(of: hover, matching: find.byType(RichText)),
        )) {
          final style = rich.text.style!;
          expect(style.color, isNot(const Color(0xffff0000)));
          expect(style.decorationStyle, isNot(TextDecorationStyle.double));
          expect(style.fontSize, lessThanOrEqualTo(16));
        }
        if (capture) {
          await _capturePreparation(
            tester,
            captureKey,
            'artifact-hover-text${(scale * 100).toInt()}',
          );
        }
        await mouse.removePointer();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        debugDisableShadows = shadows;
      }
    });
  }

  testWidgets(
    'Journal disclosure respects reduced motion without changing input state',
    (tester) async {
      final key = await open(tester, disableAnimations: true);
      final mastery = find.byKey(const ValueKey('inline-stats-mastery'));
      final controller = tester.widget<TextField>(mastery).controller!;
      await tester.enterText(mastery, '1801');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('preparation-library-reveal')),
        findsNothing,
      );
      final all = find.byKey(const ValueKey('preparation-all-buffs-toggle'));
      await tester.ensureVisible(all);
      await tester.tap(all);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(mastery).controller, same(controller));
      expect(controller.text, '1801');
      expect(key.currentState!.profile.baseSettings.mastery, 1801);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('artifact reference remains bounded with enlarged text', (
    tester,
  ) async {
    await open(tester, size: const Size(420, 760), scale: 2);
    final chip = find.byKey(const ValueKey('preparation-artifact-735353'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    final dialog = find.byKey(
      const ValueKey('preparation-artifact-details-735353'),
    );
    final bounds = tester.getRect(dialog);
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(420));
    expect(bounds.bottom, lessThanOrEqualTo(760));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Prepare starts with the audited small kit and updates shared totals immediately',
    (tester) async {
      final key = await open(tester);
      expect(find.byType(BuffPicker), findsNothing);
      final kitIds = strings(
        catalog.presets.firstWhere(
          (preset) => preset['id'] == 'gathering-simple',
        )['buffIds'],
      );
      expect(kitIds, ['buff-9691', 'buff-791', 'buff-721092']);
      for (final id in kitIds) {
        final buff = catalog.buffs.firstWhere((entry) => entry.id == id);
        final choice = find.byKey(ValueKey('preparation-kit-$id'));
        expect(choice, findsOneWidget);
        expect(
          find.descendant(of: choice, matching: find.text(buff.name)),
          findsOneWidget,
        );
        expect(
          tester
              .widget<GameIcon>(
                find.descendant(of: choice, matching: find.byType(GameIcon)),
              )
              .path,
          buff.icon,
        );
      }
      await tester.tap(find.byKey(const ValueKey('preparation-use-kit')));
      await tester.pumpAndSettle();
      expect(key.currentState!.profile.buffIds, kitIds.toSet());
      final effective = key.currentState!.profile.effectiveSettings(catalog);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('preparation-effective-mastery')),
            )
            .data,
        '${countText(effective.mastery)} Mastery',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('preparation-effective-drop-rate')),
            )
            .data,
        '${numberText(effective.gatheringDropRatePercent)}% Drop rate',
      );
      await tester.tap(find.byKey(const ValueKey('preparation-kit-buff-791')));
      await tester.pumpAndSettle();
      expect(key.currentState!.profile.buffIds, isNot(contains('buff-791')));
      expect(find.text('Apply setup'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Unconfirmed stats are blank and focus never accepts examples', (
    tester,
  ) async {
    final key = await open(tester, confirmed: false);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('inline-stats-mastery')))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      find.byKey(const ValueKey('preparation-effective-mastery')),
      findsNothing,
    );
    final drop = find.byKey(const ValueKey('inline-stats-drop-rate'));
    expect(tester.widget<TextField>(drop).controller!.text, isEmpty);
    expect(tester.widget<TextField>(drop).decoration!.hintText, 'Example: 40');
    await tester.tap(drop);
    await tester.pumpAndSettle();
    expect(key.currentState!.edits, 0);
    expect(key.currentState!.statsValid, isTrue);
    expect(key.currentState!.profile.statsConfirmed, isFalse);
    expect(find.text('Enter stats'), findsNothing);
  });

  testWidgets(
    'Both explicit base values save immediately and keep raw typing',
    (tester) async {
      final key = await open(tester, confirmed: false);
      final mastery = find.byKey(const ValueKey('inline-stats-mastery'));
      final drop = find.byKey(const ValueKey('inline-stats-drop-rate'));
      await tester.enterText(mastery, '1850');
      await tester.pumpAndSettle();
      expect(key.currentState!.statsValid, isFalse);
      expect(key.currentState!.edits, 0);
      await tester.enterText(drop, '040,50');
      await tester.pumpAndSettle();
      expect(key.currentState!.profile.statsConfirmed, isTrue);
      expect(key.currentState!.profile.baseSettings.mastery, 1850);
      expect(
        key.currentState!.profile.baseSettings.gatheringDropRatePercent,
        40.5,
      );
      expect(key.currentState!.statsValid, isTrue);
      expect(key.currentState!.edits, 1);
      expect(tester.widget<TextField>(drop).controller!.text, '040,50');
      await tester.enterText(mastery, '1900');
      await tester.pumpAndSettle();
      expect(key.currentState!.profile.baseSettings.mastery, 1900);
      expect(key.currentState!.edits, 2);
    },
  );

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'Effective totals pulse without touching input; reduced motion $reducedMotion',
      (tester) async {
        final key = await open(tester, disableAnimations: reducedMotion);
        final input = find.byKey(const ValueKey('inline-stats-drop-rate'));
        final controller = tester.widget<TextField>(input).controller!;
        expect(
          find.ancestor(of: input, matching: find.byType(ValueChangePulse)),
          findsNothing,
        );
        await tester.enterText(input, '47.25');
        await tester.pump();
        final output = find.byKey(
          const ValueKey('preparation-effective-drop-rate'),
        );
        final pulse = find.ancestor(
          of: output,
          matching: find.byType(ValueChangePulse),
        );
        expect(tester.widget<ValueChangePulse>(pulse).value, 47.25);
        expect(
          tester.widget<Text>(output).data,
          '${numberText(47.25)}% Drop rate',
        );
        double backgroundAlpha() =>
            (tester
                        .widget<DecoratedBox>(
                          find.descendant(
                            of: pulse,
                            matching: find.byType(DecoratedBox),
                          ),
                        )
                        .decoration
                    as BoxDecoration)
                .color!
                .a;
        expect(backgroundAlpha(), reducedMotion ? 0 : greaterThan(0));
        await tester.pump(const Duration(milliseconds: 700));
        expect(backgroundAlpha(), 0);
        expect(tester.widget<TextField>(input).controller, same(controller));
        expect(controller.text, '47.25');
        await tester.enterText(input, '-1');
        await tester.pump();
        expect(key.currentState!.statsValid, isFalse);
        await tester.tap(find.byKey(const ValueKey('inline-stats-reset')));
        await tester.pumpAndSettle();
        expect(controller.text, '47.25');
        expect(
          tester.widget<Text>(output).data,
          '${numberText(47.25)}% Drop rate',
        );
        expect(tester.widget<ValueChangePulse>(pulse).value, 47.25);
        expect(backgroundAlpha(), 0);
        expect(
          key.currentState!.profile.baseSettings.gatheringDropRatePercent,
          47.25,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Invalid raw stats survive buff rebuilds and reset safely', (
    tester,
  ) async {
    final key = await open(tester);
    final drop = find.byKey(const ValueKey('inline-stats-drop-rate'));
    final controller = tester.widget<TextField>(drop).controller!;
    for (final invalid in ['-1', '1..2', 'Infinity', '1e309', 'NaN', '']) {
      await tester.enterText(drop, invalid);
      await tester.pumpAndSettle();
      expect(controller.text, invalid);
      expect(key.currentState!.statsValid, isFalse);
      expect(key.currentState!.edits, 0);
    }
    await tester.enterText(drop, '3..7');
    controller.selection = const TextSelection.collapsed(offset: 2);
    key.currentState!.toggle(
      catalog.buffs.firstWhere((buff) => buff.id == 'buff-yawning-hedgehog'),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(drop).controller, same(controller));
    expect(controller.text, '3..7');
    expect(controller.selection.baseOffset, 2);
    expect(key.currentState!.statsValid, isFalse);
    await tester.tap(find.byKey(const ValueKey('inline-stats-reset')));
    await tester.pumpAndSettle();
    expect(controller.text, '40');
    expect(key.currentState!.statsValid, isTrue);
    expect(key.currentState!.edits, 0);
    expect(key.currentState!.profile.buffIds, {'buff-yawning-hedgehog'});
  });

  testWidgets('Advanced-only edits never confirm blank sample stats', (
    tester,
  ) async {
    final key = await open(tester, confirmed: false);
    final advanced = find.descendant(
      of: find.byKey(const ValueKey('inline-stats-advanced')),
      matching: find.byType(ListTile),
    );
    await tester.tap(advanced);
    await tester.pumpAndSettle();
    final minigame = find.byKey(const ValueKey('minigame-event'));
    await tester.ensureVisible(minigame);
    await tester.tap(minigame);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.profile.baseSettings.minigameMode,
      BairogMinigameMode.event,
    );
    expect(key.currentState!.profile.statsConfirmed, isFalse);
    expect(key.currentState!.statsValid, isTrue);
    expect(key.currentState!.edits, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('inline-stats-mastery')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets(
    'External stat changes and context reset sync without callbacks',
    (tester) async {
      final key = await open(tester);
      final mastery = find.byKey(const ValueKey('inline-stats-mastery'));
      await tester.enterText(mastery, '3001');
      await tester.pumpAndSettle();
      key.currentState!.update(() {
        key.currentState!.profile = key.currentState!.profile.withBaseSettings(
          key.currentState!.profile.baseSettings.copyWith(mastery: 1750),
          catalog,
        );
      });
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(mastery).controller!.text, '1750');
      expect(key.currentState!.statsValid, isTrue);
      expect(key.currentState!.edits, 0);
      await tester.enterText(mastery, '3001');
      await tester.pumpAndSettle();
      key.currentState!.update(
        () => key.currentState!.statsContextId = Object(),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(mastery).controller!.text, '1750');
      expect(key.currentState!.statsValid, isTrue);
      key.currentState!.update(() => key.currentState!.statsEnabled = false);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(mastery).enabled, isFalse);
    },
  );

  testWidgets(
    'Lightstone selection replaces conflicts without counting components twice',
    (tester) async {
      final key = await open(tester);
      final yawning = find.byKey(
        const ValueKey('preparation-lightstones-buff-yawning-hedgehog'),
      );
      final weasel = find.byKey(
        const ValueKey('preparation-lightstones-buff-scurrying-weasel'),
      );
      await tester.ensureVisible(yawning);
      await tester.tap(yawning);
      await tester.pumpAndSettle();
      expect(key.currentState!.profile.buffIds, {'buff-yawning-hedgehog'});
      expect(
        key.currentState!.profile.effectiveSettings(catalog).mastery,
        1825,
      );
      expect(
        key.currentState!.profile
            .effectiveSettings(catalog)
            .gatheringDropRatePercent,
        50,
      );
      await tester.ensureVisible(weasel);
      await tester.tap(weasel);
      await tester.pumpAndSettle();
      expect(key.currentState!.profile.buffIds, {'buff-scurrying-weasel'});
      expect(
        key.currentState!.profile.effectiveSettings(catalog).mastery,
        1825,
      );
      expect(
        key.currentState!.profile
            .effectiveSettings(catalog)
            .gatheringDropRatePercent,
        45,
      );
    },
  );

  testWidgets('Inline info explains base stats without another editor', (
    tester,
  ) async {
    final key = await open(tester);
    expect(
      tester.getSize(find.byKey(const ValueKey('preparation-stats'))).width,
      lessThanOrEqualTo(600),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('inline-stats-mastery'))).width,
      245,
    );
    await tester.tap(find.byKey(const ValueKey('inline-stats-info')));
    await tester.pumpAndSettle();
    final info = find.byType(AlertDialog);
    expect(info, findsOneWidget);
    expect(
      find.descendant(of: info, matching: find.byType(TextField)),
      findsNothing,
    );
    expect(
      find.text('Include your gear, artifacts and crystals.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Leave out the buffs selected in Prepare. They are added automatically.',
      ),
      findsOneWidget,
    );
    expect(key.currentState!.edits, 0);
  });

  testWidgets('Saved decimal stats retain precision through Advanced edits', (
    tester,
  ) async {
    final key = await open(tester);
    key.currentState!.update(() {
      key.currentState!.profile = key.currentState!.profile.withBaseSettings(
        key.currentState!.profile.baseSettings.copyWith(
          gatheringDropRatePercent: 47.25,
          yourEnergy: 500.125,
        ),
        catalog,
      );
    });
    await tester.pumpAndSettle();
    final drop = find.byKey(const ValueKey('inline-stats-drop-rate'));
    expect(tester.widget<TextField>(drop).controller!.text, '47.25');
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('inline-stats-advanced')),
        matching: find.byType(ListTile),
      ),
    );
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('minigame-event'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      key.currentState!.profile.baseSettings.gatheringDropRatePercent,
      47.25,
    );
    expect(key.currentState!.profile.baseSettings.yourEnergy, 500.125);
    expect(tester.widget<TextField>(drop).controller!.text, '47.25');
  });

  testWidgets('Base stats information is scrollable at420px and200percent', (
    tester,
  ) async {
    await open(tester, size: const Size(420, 760), scale: 2);
    await tester.tap(find.byKey(const ValueKey('inline-stats-info')));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(tester.widget<AlertDialog>(dialog).scrollable, isTrue);
    expect(tester.getRect(dialog).bottom, lessThanOrEqualTo(760));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Pet tier opens inline Advanced at200percent with editable energy',
    (tester) async {
      final key = await open(tester, size: const Size(420, 900), scale: 2);
      key.currentState!.update(() {
        key.currentState!.profile = key.currentState!.profile.withBaseSettings(
          key.currentState!.profile.baseSettings.copyWith(
            hedgehogTier: BairogHedgehogTier.tier4,
          ),
          catalog,
        );
      });
      await tester.pumpAndSettle();
      final tier = find.byKey(const ValueKey('preparation-pet-tier'));
      await tester.ensureVisible(tier);
      await tester.tap(tier);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('gathering-setup-dialog')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('hedgehog-4')), findsOneWidget);
      final energy = find.byKey(const ValueKey('gathering-setup-energy'));
      await tester.ensureVisible(energy);
      await tester.enterText(energy, '650');
      await tester.pumpAndSettle();
      expect(key.currentState!.profile.baseSettings.yourEnergy, 650);
      expect(
        key.currentState!.profile.baseSettings.hedgehogTier,
        BairogHedgehogTier.tier4,
      );
      final lastExpense = find.byKey(
        const ValueKey('energy-expense-info-buff-821145'),
      );
      await tester.ensureVisible(lastExpense);
      await tester.pumpAndSettle();
      expect(lastExpense.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Every Lightstone info button retains exact current component identities',
    (tester) async {
      await open(tester);
      for (final buff in catalog.buffs.where(
        (entry) => entry.category == 'lightstones',
      )) {
        final info = find.byKey(
          ValueKey('preparation-info-lightstones-${buff.id}'),
        );
        await tester.ensureVisible(info);
        await tester.pumpAndSettle();
        await tester.tap(info);
        await tester.pumpAndSettle();
        final dialog = find.byType(AlertDialog);
        expect(dialog, findsOneWidget);
        expect(
          find.descendant(of: dialog, matching: find.text('How to get')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: dialog,
            matching: find.textContaining('Equip Flora:'),
          ),
          findsNothing,
        );
        for (final component in buff.components) {
          expect(
            find.descendant(
              of: dialog,
              matching: find.byKey(ValueKey('buff-component-${component.id}')),
            ),
            findsOneWidget,
          );
        }
        if (buff.id == 'buff-hand-of-manos') {
          final icons = find
              .descendant(of: dialog, matching: find.byType(GameIcon))
              .evaluate();
          expect(
            icons.where(
              (element) =>
                  (element.widget as GameIcon).path ==
                  'assets/icons/items/764002.webp',
            ),
            hasLength(3),
          );
        }
        await tester.tap(
          find.descendant(
            of: dialog,
            matching: find.byKey(ValueKey('buff-details-close-${buff.id}')),
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Visible info pins rich hover without selecting or leaving a second popup',
    (tester) async {
      final key = await open(tester);
      final card = find.byKey(const ValueKey('preparation-kit-buff-9691'));
      final info = find.byKey(const ValueKey('preparation-info-kit-buff-9691'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(card));
      await tester.pump(const Duration(milliseconds: 350));
      final hover = find.byKey(const ValueKey('buff-hover-card-buff-9691'));
      expect(hover, findsOneWidget);
      await tester.tap(info);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(hover, findsNothing);
      expect(key.currentState!.profile.buffIds, isEmpty);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'All buffs stays accessible with events and reference-only energy information',
    (tester) async {
      final key = await open(tester);
      final toggle = find.byKey(const ValueKey('preparation-all-buffs-toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byType(BuffPicker), findsOneWidget);
      expect(find.byKey(const ValueKey('buff-row-events')), findsOneWidget);
      final potion = find.byKey(const ValueKey('buff-icon-buff-589'));
      await tester.ensureVisible(potion);
      await tester.pumpAndSettle();
      await tester.tap(potion);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(key.currentState!.profile.buffIds, isEmpty);
    },
  );

  testWidgets('All buffs reveals usable content from the bottom of Prepare', (
    tester,
  ) async {
    final captureKey = GlobalKey();
    await open(tester, size: const Size(1200, 752), captureKey: captureKey);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('preparation-all-buffs-toggle'));
    expect(toggle.hitTestable(), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    if (const bool.fromEnvironment('CAPTURE_GATHERING_PREPARATION')) {
      await _capturePreparation(
        tester,
        captureKey,
        'all-buffs-disclosure-1200',
      );
    }
    expect(
      find.byKey(const ValueKey('buff-icon-buff-9691')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('recommended items keep food and energy alternatives exclusive', (
    tester,
  ) async {
    final key = await open(tester);
    expect(find.text('Recommended Items'), findsOneWidget);
    expect(find.text('Recommended kit'), findsNothing);
    for (final heading in [
      'Food · choose one',
      'Gathering drop rate',
      'Energy recovery',
      'Energy potions',
    ]) {
      expect(find.text(heading), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('preparation-kit-section')),
        matching: find.byKey(const ValueKey('preparation-energy-section')),
      ),
      findsNothing,
    );
    expect(
      tester.widget<Text>(find.text('Energy recovery')).style!.fontSize,
      tester.widget<Text>(find.text('Recommended Items')).style!.fontSize,
    );
    Future<void> choose(String id, {String group = 'kit'}) async {
      final finder = find.byKey(ValueKey('preparation-$group-$id'));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await choose('buff-9691');
    expect(key.currentState!.profile.buffIds, {'buff-9691'});
    await choose('buff-9301');
    expect(key.currentState!.profile.buffIds, {'buff-9301'});
    expect(
      key.currentState!.profile
          .effectiveSettings(catalog)
          .gatheringDropRatePercent,
      43,
    );
    await choose('buff-9216');
    expect(key.currentState!.profile.buffIds, {'buff-9216'});
    await choose('buff-791');
    await choose('buff-1159');
    expect(key.currentState!.profile.buffIds, {'buff-9216', 'buff-1159'});
    await choose('buff-721092');
    await choose('buff-45514');
    expect(key.currentState!.profile.buffIds, {
      'buff-9216',
      'buff-1159',
      'buff-45514',
    });
    expect(
      key.currentState!.profile
          .effectiveSettings(catalog)
          .gatheringDropRatePercent,
      60,
    );
    await choose('buff-821144', group: 'energy');
    expect(
      key.currentState!.profile.baseSettings.enabledExpenseItemIds,
      contains(821144),
    );
    await choose('buff-821145', group: 'energy');
    expect(key.currentState!.profile.buffIds, contains('buff-821145'));
    expect(key.currentState!.profile.buffIds, isNot(contains('buff-821144')));
    expect(
      key.currentState!.profile.baseSettings.enabledExpenseItemIds,
      contains(821145),
    );
    expect(
      key.currentState!.profile.baseSettings.enabledExpenseItemIds,
      isNot(contains(821144)),
    );
    final before = key.currentState!.profile.toJson();
    await choose('buff-589', group: 'instant-energy');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(key.currentState!.profile.toJson(), before);
    final section = find.byKey(const ValueKey('preparation-kit-section'));
    for (final buff in catalog.buffs.where((b) => b.category == 'events')) {
      expect(
        find.descendant(of: section, matching: find.text(buff.name)),
        findsNothing,
      );
    }
    expect(tester.takeException(), isNull);
  });

  test(
    'herbal expense names match the catalog without changing expense math',
    () {
      final expected = {
        821144: ('Mystical Herbal Medicine', 1000.0),
        821145: ('Mellow Herbal Medicine', 600.0),
      };
      for (final entry in expected.entries) {
        final expense = bairogEnergyExpenses.firstWhere(
          (e) => e.bdoItemId == entry.key,
        );
        expect(expense.name, entry.value.$1);
        expect(
          expense.name,
          catalog.buffs.firstWhere((b) => b.id == 'buff-${entry.key}').name,
        );
        expect(expense.durationHours, 3);
        expect(expense.recoveryPerHour, entry.value.$2);
        expect(expense.energyBoost, 0);
      }
    },
  );

  for (final variant in [
    (width: 1200.0, scale: 1.0, reduced: false),
    (width: 900.0, scale: 2.0, reduced: false),
    (width: 1200.0, scale: 1.0, reduced: true),
    (width: 900.0, scale: 2.0, reduced: true),
  ]) {
    final label =
        '${variant.width.toInt()}-text${(variant.scale * 100).toInt()}-${variant.reduced ? 'reduced' : 'animated'}';
    testWidgets(
      'actual Prepare reveals buff content without extra scroll $label',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(variant.width, 752);
        addTearDown(tester.view.reset);
        final shadows = debugDisableShadows;
        const capture = bool.fromEnvironment('CAPTURE_GATHERING_PREPARATION');
        if (capture) debugDisableShadows = false;
        try {
          final store = _PrepareMemoryStore();
          store.preferences = {
            'methodId': 'butcher',
            'spotId': 'imp-cave-wolves',
            gatheringPreparationPreferenceKey: GatheringPreparation(
              statsConfirmed: true,
            ).toJson(),
          };
          final captureKey = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: captureKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: companionTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(variant.scale),
                    disableAnimations: variant.reduced,
                  ),
                  child: companionBackdropBuilder(context, child),
                ),
                home: GatheringHostServicesScope(
                  services: GatheringHostServices(
                    openExternal: (_) async => true,
                  ),
                  child: CompanionHome(
                    catalog: catalog,
                    store: store,
                    glassOpacityPercent: 60,
                    onGlassOpacityChanged: (_) {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('workflow-prepare')));
          await tester.pumpAndSettle();
          final selectedBefore = jsonEncode(
            store.preferences[gatheringPreparationPreferenceKey],
          );
          if (capture && !variant.reduced) {
            await tester.ensureVisible(find.text('Recommended Items'));
            await tester.pumpAndSettle();
            await _capturePreparation(
              tester,
              captureKey,
              'recommended-items-$label',
            );
            await tester.ensureVisible(find.text('Energy recovery'));
            await tester.pumpAndSettle();
            await _capturePreparation(
              tester,
              captureKey,
              'energy-recovery-$label',
            );
          }
          final scrollable = find.descendant(
            of: find.byKey(const ValueKey('preparation-scroll')),
            matching: find.byType(Scrollable),
          );
          final position = tester
              .state<ScrollableState>(scrollable.first)
              .position;
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
          final toggle = find.byKey(
            const ValueKey('preparation-all-buffs-toggle'),
          );
          expect(toggle.hitTestable(), findsOneWidget);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          final firstFood = find.byKey(const ValueKey('buff-icon-buff-9691'));
          expect(firstFood.hitTestable(), findsOneWidget);
          expect(tester.getRect(firstFood).bottom, lessThan(752));
          expect(tester.getRect(firstFood).left, greaterThanOrEqualTo(0));
          if (capture && !variant.reduced) {
            await _capturePreparation(tester, captureKey, 'all-buffs-$label');
          }
          expect(
            jsonEncode(store.preferences[gatheringPreparationPreferenceKey]),
            selectedBefore,
          );
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(find.byType(BuffPicker), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          debugDisableShadows = shadows;
        }
      },
    );
  }

  testWidgets('matchlock advice is reference-only for the shared preparation', (
    tester,
  ) async {
    final key = await open(tester, methodId: 'hunting');
    final before = key.currentState!.profile.toJson();
    final editsBefore = key.currentState!.edits;
    expect(
      find.byKey(const ValueKey('matchlock-damage-advice')),
      findsOneWidget,
    );
    for (final entry in matchlockCrystalAdvice) {
      final chip = find.byKey(ValueKey('matchlock-crystal-${entry.id}'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GameIcon>(
              find.descendant(of: chip, matching: find.byType(GameIcon)),
            )
            .path,
        entry.icon,
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.text(entry.name), findsOneWidget);
      expect(find.text(entry.benefit), findsOneWidget);
      expect(key.currentState!.profile.toJson(), before);
      expect(key.currentState!.edits, editsBefore);
      await tester.tap(
        find.byKey(ValueKey('matchlock-close-crystal-${entry.id}')),
      );
      await tester.pumpAndSettle();
    }
    final info = find.byKey(const ValueKey('matchlock-damage-info'));
    await tester.ensureVisible(info);
    await tester.pumpAndSettle();
    await tester.tap(info);
    await tester.pumpAndSettle();
    expect(find.text('Matchlock damage setup'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('matchlock-damage-source-0')).hitTestable(),
      findsNothing,
    );
    expect(key.currentState!.profile.toJson(), before);
    expect(key.currentState!.edits, editsBefore);
    await tester.tap(
      find.byKey(const ValueKey('matchlock-close-damage-details')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final method in ['butcher', 'sniper']) {
    testWidgets('$method does not show matchlock damage advice', (
      tester,
    ) async {
      await open(tester, methodId: method);
      expect(
        find.byKey(const ValueKey('matchlock-damage-advice')),
        findsNothing,
      );
      expect(find.text('Example crystals'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'matchlock source failure is visible and retry leaves setup alone',
    (tester) async {
      var opened = false;
      final calls = <MethodCall>[];
      const channel = MethodChannel('bdo_gathering/native');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return opened;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final key = await open(tester, methodId: 'hunting');
      final before = key.currentState!.profile.toJson();
      final info = find.byKey(const ValueKey('matchlock-damage-info'));
      await tester.ensureVisible(info);
      await tester.tap(info);
      await tester.pumpAndSettle();
      final sources = find.byKey(const ValueKey('matchlock-damage-sources'));
      await tester.ensureVisible(sources);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: sources, matching: find.text('Sources')),
      );
      await tester.pumpAndSettle();
      final link = find.byKey(const ValueKey('matchlock-damage-source-0'));
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pumpAndSettle();
      final message = 'Could not open ${matchlockAdviceSources.first.label}.';
      expect(find.text(message), findsOneWidget);
      expect(calls.single.method, 'openExternal');
      expect(calls.single.arguments, {'url': matchlockAdviceSources.first.url});
      expect(key.currentState!.profile.toJson(), before);
      opened = true;
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
      expect(calls, hasLength(2));
      expect(key.currentState!.profile.toJson(), before);
      expect(tester.takeException(), isNull);
    },
  );

  for (final method in ['hunting', 'sniper']) {
    testWidgets(
      '$method uses its existing audited kit instead of the Gathering preset',
      (tester) async {
        final key = await open(tester, methodId: method);
        await tester.tap(find.byKey(const ValueKey('preparation-use-kit')));
        final preset = catalog.presets.firstWhere(
          (entry) => entry['id'] == '$method-simple',
        );
        expect(
          key.currentState!.profile.buffIds,
          strings(preset['buffIds']).toSet(),
        );
      },
    );
  }

  for (final size in const [Size(1100, 1000), Size(700, 900), Size(420, 760)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Prepare is readable at $size and text $scale', (
        tester,
      ) async {
        final oldShadows = debugDisableShadows;
        const capture = bool.fromEnvironment('CAPTURE_GATHERING_PREPARATION');
        if (capture) debugDisableShadows = false;
        try {
          final captureKey = GlobalKey();
          await open(tester, size: size, scale: scale, captureKey: captureKey);
          if (capture && scale == 1) {
            await _capturePreparation(
              tester,
              captureKey,
              'prepare-${size.width.toInt()}',
            );
          }
          for (final id in ['buff-9691', 'buff-791', 'buff-721092']) {
            final card = find.byKey(ValueKey('preparation-kit-$id'));
            final rect = tester.getRect(card);
            expect(rect.left, greaterThanOrEqualTo(16));
            expect(rect.right, lessThanOrEqualTo(size.width - 16));
            expect(rect.width.isFinite, isTrue);
          }
          final toggle = find.byKey(
            const ValueKey('preparation-all-buffs-toggle'),
          );
          await tester.ensureVisible(toggle);
          await tester.pumpAndSettle();
          expect(toggle.hitTestable(), findsOneWidget);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          final picker = find.byType(BuffPicker);
          expect(picker, findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          debugDisableShadows = oldShadows;
        }
      });
    }
  }
}

Future<void> _capturePreparation(
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
      'PREPARATION_CAPTURE_DIRECTORY',
      defaultValue: 'build/guided-workflow-evidence',
    );
    final file = File('$directory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _loadPreparationCaptureFonts() async {
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
