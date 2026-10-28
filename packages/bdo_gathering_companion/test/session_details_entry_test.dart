import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/src/domain/bairog_calculator.dart';
import 'package:bdo_gathering_companion/src/domain/gathering_preparation.dart';
import 'package:bdo_gathering_companion/src/domain/models.dart';
import 'package:bdo_gathering_companion/src/gathering_companion_home.dart';
import 'package:bdo_gathering_companion/src/services/host_services.dart';
import 'package:bdo_gathering_companion/src/services/session_store.dart';
import 'package:bdo_gathering_companion/src/ui/field_desk_materials.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_gathering_companion/src/ui/visual_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureKey = ValueKey('session-details-capture');
const _lightPalette = CompanionVisualPalette(
  brightness: Brightness.light,
  canvas: Color(0xFFECE1C4),
  canvasDeep: Color(0xFFD7C9A8),
  surface: Color(0xFFF1E8D3),
  raised: Color(0xFFFFF8E8),
  inset: Color(0xFFE2D3B1),
  ink: Color(0xFF262C32),
  muted: Color(0xFF645C50),
  accent: Color(0xFF264D62),
  accentBright: Color(0xFF3C6A80),
  gold: Color(0xFF87601F),
  edge: Color(0xFF92784D),
  rim: Color(0xFFFFFDF5),
  positive: Color(0xFF315E42),
  warning: Color(0xFF87601F),
  danger: Color(0xFF933A36),
);

class _MemoryStore extends SessionStore {
  _MemoryStore() : super(directory: Directory.systemTemp);

  int saveCalls = 0;
  Completer<void>? pendingSave;

  @override
  Future<void> save() async {
    saveCalls++;
    if (pendingSave case final pending?) await pending.future;
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));
Finder get _edit => _key('session-edit-details');
Finder get _dialog => _key('session-details-dialog');
Finder get _duration => _key('session-details-duration');
Finder get _notes => _key('session-details-notes');
Finder get _date => _key('session-details-date');
Finder get _done => _key('session-details-done');

Future<void> _loadFonts() async {
  if (!Platform.isWindows) return;
  final windows = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var flutter = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${flutter.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    final parent = flutter.parent;
    if (parent.path == flutter.path) throw StateError('Flutter fonts missing.');
    flutter = parent;
  }
  for (final entry in <String, List<String>>{
    'Segoe UI': [
      '$windows/Fonts/segoeui.ttf',
      '$windows/Fonts/seguisb.ttf',
      '$windows/Fonts/segoeuib.ttf',
    ],
    'Georgia': ['$windows/Fonts/georgia.ttf', '$windows/Fonts/georgiab.ttf'],
    'Roboto': [
      '${flutter.path}/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
    ],
    'MaterialIcons': [
      '${flutter.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}

Future<_MemoryStore> _mount(
  WidgetTester tester,
  Catalog catalog, {
  double scale = 1,
  Size viewport = const Size(1200, 752),
  CompanionVisualPalette palette = CompanionVisualPalette.fieldDesk,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
  addTearDown(tester.view.reset);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
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
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: companionTheme(opacityPercent: 60, visualPalette: palette),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: companionBackdropBuilder(context, child),
        ),
        home: GatheringHostServicesScope(
          services: GatheringHostServices(openExternal: (_) async => false),
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
  await tester.tap(_key('workflow-gather'));
  await tester.pumpAndSettle();
  expect(_key('session-workspace'), findsOneWidget);
  await tester.ensureVisible(_key('session-duration-header'));
  await tester.pumpAndSettle();
  return store;
}

Future<void> _openDetails(WidgetTester tester) async {
  await tester.ensureVisible(_edit);
  await tester.tap(_edit);
  await tester.pumpAndSettle();
  expect(_dialog, findsOneWidget);
}

Future<void> _finishDetails(WidgetTester tester) async {
  await tester.tap(_done);
  await tester.pumpAndSettle();
  expect(_dialog, findsNothing);
}

Future<DateTime> _pickFirstOfMonth(WidgetTester tester) async {
  final current = DateTime.now();
  await tester.tap(_date);
  await tester.pumpAndSettle();
  final calendar = find.byType(CalendarDatePicker);
  expect(calendar, findsOneWidget);
  await tester.tap(find.descendant(of: calendar, matching: find.text('1')));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  final expected = DateTime(current.year, current.month, 1);
  expect(
    find.descendant(
      of: _date,
      matching: find.text(
        '01.${current.month.toString().padLeft(2, '0')}.${current.year}',
      ),
    ),
    findsOneWidget,
  );
  return expected;
}

Future<void> _enterLoot(WidgetTester tester) async {
  final quantity = find
      .byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('loot-total-'),
      )
      .first;
  await tester.ensureVisible(quantity);
  await tester.enterText(quantity, '1200');
  await tester.pumpAndSettle();
  await tester.ensureVisible(_key('session-save-actions'));
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final root = Platform.environment['SESSION_DETAILS_CAPTURE_DIR'];
  if (root == null || root.isEmpty) return;
  for (final element in find.byType(Image).evaluate()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    await Directory(root).create(recursive: true);
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File('$root/session-details-$name.png').writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  setUpAll(() async {
    catalog = await Catalog.load();
    await _loadFonts();
  });

  testWidgets(
    'Edit details opens the existing draft editor, not Save actions',
    (tester) async {
      final store = await _mount(tester, catalog);
      expect(find.text('Edit details'), findsOneWidget);
      expect(find.text('Details'), findsNothing);
      expect(
        find.descendant(of: _key('session-save-actions'), matching: _edit),
        findsNothing,
      );
      expect(find.text('Save session'), findsOneWidget);
      expect(find.byTooltip('New session'), findsOneWidget);
      await _openDetails(tester);
      expect(tester.widget<TextField>(_duration).enabled, isTrue);
      await tester.enterText(_duration, '45');
      await tester.enterText(_notes, 'Northern route');
      final date = await _pickFirstOfMonth(tester);
      await _finishDetails(tester);
      expect(find.text('45:00'), findsOneWidget);
      expect(
        tester.widget<Text>(_key('session-summary-notes')).data,
        'Northern route',
      );
      expect(
        tester.widget<Text>(_key('session-summary-date')).data,
        '01.${date.month.toString().padLeft(2, '0')}.${date.year}',
      );
      expect(store.saveCalls, 0);
      expect(store.sessions, isEmpty);

      await tester.tap(find.byTooltip('New session'));
      await tester.pumpAndSettle();
      expect(find.text('Start a new session?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await _openDetails(tester);
      expect(tester.widget<TextField>(_duration).controller!.text, '45');
      expect(
        tester.widget<TextField>(_notes).controller!.text,
        'Northern route',
      );
      await _finishDetails(tester);
      await _enterLoot(tester);
      await tester.tap(find.text('Save session'));
      await tester.pumpAndSettle();
      expect(store.sessions, hasLength(1));
      final saved = store.sessions.single;
      expect(saved.durationSeconds, 2700);
      expect(saved.notes, 'Northern route');
      expect(saved.createdAt.year, date.year);
      expect(saved.createdAt.month, date.month);
      expect(saved.createdAt.day, date.day);
      expect(saved.totalItems, 1200);
      expect(store.saveCalls, 1);
      expect(_key('gathering-history'), findsOneWidget);
      await tester.tap(find.text('New session'));
      await tester.pumpAndSettle();
      await _openDetails(tester);
      expect(tester.widget<TextField>(_duration).controller!.text, '30');
      expect(tester.widget<TextField>(_notes).controller!.text, isEmpty);
      expect(store.sessions.single, same(saved));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'running timer keeps date and notes editable but locks duration',
    (tester) async {
      final store = await _mount(tester, catalog);
      await tester.tap(_key('session-timer-action'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byTooltip('Pause timer'), findsOneWidget);
      expect(tester.widget<TextButton>(_edit).onPressed, isNotNull);
      await _openDetails(tester);
      expect(tester.widget<TextField>(_duration).enabled, isFalse);
      expect(tester.widget<TextField>(_notes).enabled, isNot(false));
      final durationController = tester
          .widget<TextField>(_duration)
          .controller!;
      final originalDuration = durationController.text;
      await tester.enterText(_notes, 'A note while gathering');
      await _pickFirstOfMonth(tester);
      expect(durationController.text, originalDuration);
      await _finishDetails(tester);
      expect(find.byTooltip('Pause timer'), findsOneWidget);
      expect(find.text('Pause gathering?'), findsNothing);
      expect(tester.widget<OutlinedButton>(_key('time-30')).onPressed, isNull);
      await _openDetails(tester);
      expect(
        tester.widget<TextField>(_notes).controller!.text,
        'A note while gathering',
      );
      expect(tester.widget<TextField>(_duration).enabled, isFalse);
      await _finishDetails(tester);
      await tester.tap(_key('session-timer-action'));
      await tester.pumpAndSettle();
      await _openDetails(tester);
      expect(tester.widget<TextField>(_duration).enabled, isTrue);
      expect(store.sessions, isEmpty);
      expect(store.saveCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('custom location and all original tool choices remain editable', (
    tester,
  ) async {
    await _mount(tester, catalog);
    await _openDetails(tester);
    await tester.tap(_key('session-details-custom-location'));
    await tester.pumpAndSettle();
    for (final method in catalog.methods) {
      expect(_key('method-${method.id}'), findsOneWidget);
    }
    await tester.ensureVisible(_key('method-hoe'));
    await tester.tap(_key('method-hoe'));
    final location = _key('session-details-location-name');
    await tester.ensureVisible(location);
    await tester.enterText(location, 'My herb route');
    await tester.ensureVisible(_notes);
    await tester.enterText(_notes, 'Keep the tool and location');
    await _finishDetails(tester);
    await _openDetails(tester);
    expect(
      tester
          .widget<CheckboxListTile>(_key('session-details-custom-location'))
          .value,
      isTrue,
    );
    expect(
      tester.widget<TextField>(location).controller!.text,
      'My herb route',
    );
    final selectedTool = find
        .ancestor(of: _key('method-hoe'), matching: find.byType(GlassControl))
        .first;
    expect(tester.widget<GlassControl>(selectedTool).selected, isTrue);
    expect(
      tester.widget<TextField>(_notes).controller!.text,
      'Keep the tool and location',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('relocated Edit details preserves the existing saving guard', (
    tester,
  ) async {
    final store = await _mount(tester, catalog);
    await _enterLoot(tester);
    store.pendingSave = Completer<void>();
    await tester.tap(find.text('Save session'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    expect(tester.widget<TextButton>(_edit).onPressed, isNull);
    final newSession = find.descendant(
      of: _key('session-save-actions'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(newSession).onPressed, isNull);
    store.pendingSave!.complete();
    await tester.pumpAndSettle();
    expect(store.sessions, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline session groups values and keeps timer beside presets', (
    tester,
  ) async {
    final store = await _mount(tester, catalog);
    final panel = _key('session-inline-panel');
    final heading = _key('session-inline-heading');
    final body = _key('session-inline-body');
    final actions = _key('session-inline-actions');
    for (final region in [heading, body, actions]) {
      expect(find.descendant(of: panel, matching: region), findsOneWidget);
    }
    expect(
      tester.getRect(heading).bottom,
      closeTo(tester.getRect(body).top, .01),
    );
    expect(
      tester.getRect(body).bottom,
      closeTo(tester.getRect(actions).top, .01),
    );
    expect(
      find.descendant(of: actions, matching: find.text('Save session')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: actions, matching: find.byTooltip('New session')),
      findsOneWidget,
    );
    expect(find.text('Start timer'), findsOneWidget);
    expect(find.text('30:00'), findsOneWidget);
    expect(_key('session-summary-notes'), findsNothing);
    expect(find.text('None'), findsNothing);
    final thirty = tester.getRect(_key('time-30'));
    final sixty = tester.getRect(_key('time-60'));
    final timer = tester.getRect(_key('session-timer-action'));
    expect(thirty.center.dy, closeTo(sixty.center.dy, .01));
    expect(sixty.center.dy, closeTo(timer.center.dy, .01));
    expect(timer.left, greaterThan(sixty.right));
    await tester.tap(_key('time-60'));
    await tester.pumpAndSettle();
    expect(find.text('1:00:00'), findsOneWidget);
    await tester.tap(_key('session-timer-action'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pause timer'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(_key('time-60')).onPressed, isNull);
    expect(store.saveCalls, 0);
    expect(store.sessions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inline save stays reachable and validates loot in a narrow view',
    (tester) async {
      final store = await _mount(
        tester,
        catalog,
        scale: 1.5,
        viewport: const Size(520, 752),
      );
      final quantity = find
          .byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'loot-total-',
                ),
          )
          .last;
      final save = find.ancestor(
        of: find.text('Save session'),
        matching: find.byType(FilledButton),
      );
      await tester.ensureVisible(quantity);
      await tester.enterText(quantity, 'not a number');
      await tester.pumpAndSettle();
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(store.sessions, isEmpty);
      await tester.ensureVisible(quantity);
      await tester.enterText(quantity, '23');
      await tester.pumpAndSettle();
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(store.sessions, hasLength(1));
      expect(store.sessions.single.totalItems, 23);
      expect(store.sessions.single.durationSeconds, 1800);
      expect(tester.takeException(), isNull);
    },
  );

  for (final palette in {
    'dark': CompanionVisualPalette.fieldDesk,
    'light': _lightPalette,
  }.entries) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '${palette.key} duration header stays compact at ${scale * 100}%',
        (tester) async {
          await _mount(tester, catalog, scale: scale, palette: palette.value);
          final header = _key('session-duration-header');
          await tester.ensureVisible(header);
          await tester.pumpAndSettle();
          final headerRect = tester.getRect(header);
          final title = find.descendant(
            of: header,
            matching: find.text('Duration'),
          );
          final titleRect = tester.getRect(title);
          final editRect = tester.getRect(_edit);
          final viewport =
              Offset.zero &
              (tester.view.physicalSize / tester.view.devicePixelRatio);
          final panel = find
              .ancestor(of: header, matching: find.byType(FieldDeskPanel))
              .first;
          expect(tester.getSize(panel).width, closeTo(340, .01));
          expect(editRect.left, greaterThanOrEqualTo(headerRect.left));
          expect(editRect.right, lessThanOrEqualTo(headerRect.right + .01));
          expect(titleRect.top, greaterThanOrEqualTo(viewport.top));
          expect(titleRect.bottom, lessThanOrEqualTo(viewport.bottom));
          expect(titleRect.left, greaterThanOrEqualTo(viewport.left));
          expect(titleRect.right, lessThanOrEqualTo(viewport.right));
          expect(title.hitTestable(), findsOneWidget);
          expect(_edit.hitTestable(), findsOneWidget);
          final editFont = tester
              .widget<TextButton>(_edit)
              .style!
              .textStyle!
              .resolve({})!
              .fontFamily;
          expect(
            editFont,
            Theme.of(tester.element(_edit)).textTheme.labelLarge!.fontFamily,
          );
          if (editRect.top < titleRect.bottom) {
            expect(editRect.left, greaterThan(titleRect.right));
            expect(editRect.center.dy, closeTo(titleRect.center.dy, .01));
          } else {
            expect(editRect.top, greaterThanOrEqualTo(titleRect.bottom));
          }
          final suffix = '${palette.key}-text${(scale * 100).round()}';
          tester
              .widget<SingleChildScrollView>(_key('session-scroll'))
              .controller!
              .jumpTo(0);
          await tester.pumpAndSettle();
          await _capture(tester, 'entry-$suffix');
          await _openDetails(tester);
          expect(_date.hitTestable(), findsOneWidget);
          expect(tester.widget<TextField>(_duration).enabled, isTrue);
          await tester.ensureVisible(_notes);
          await tester.pumpAndSettle();
          expect(_notes.hitTestable(), findsOneWidget);
          expect(_done.hitTestable(), findsOneWidget);
          await _capture(tester, 'editor-$suffix');
          await _finishDetails(tester);
          expect(_edit.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
