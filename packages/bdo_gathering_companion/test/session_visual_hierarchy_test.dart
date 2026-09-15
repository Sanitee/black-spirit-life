import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/domain/bairog_calculator.dart';
import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/services/session_store.dart';
import 'package:bdo_gathering_companion/src/domain/gathering_preparation.dart';
import 'package:bdo_gathering_companion/src/gathering_companion_home.dart';
import 'package:bdo_gathering_companion/src/services/host_services.dart';
import 'package:bdo_gathering_companion/src/ui/buff_picker.dart';
import 'package:bdo_gathering_companion/src/ui/loot_panel.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureSession = bool.fromEnvironment('CAPTURE_GATHERING_SESSION');
const _captureDirectory = String.fromEnvironment(
  'SESSION_CAPTURE_DIRECTORY',
  defaultValue: 'build/gathering-clarity-evidence',
);
const _methodIds = [
  'butcher',
  'tanning',
  'fluid',
  'hoe',
  'lumbering',
  'mining',
  'hunting',
  'sniper',
];

class _MemorySessionStore extends SessionStore {
  _MemorySessionStore(Directory directory) : super(directory: directory);

  int saveCalls = 0;

  @override
  Future<void> save() async => saveCalls++;
}

// Capture-only access to the actual map-tile origin. Normal tests retain the
// Flutter HTTP mock; no marketplace, account, or unrelated network is enabled.
class _TileReadOverrides extends HttpOverrides {
  final clients = <_TileReadClient>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = _TileReadClient(super.createHttpClient(context));
    clients.add(client);
    return client;
  }

  void close() {
    for (final client in clients) {
      client.close(force: true);
    }
  }
}

class _TileReadClient implements HttpClient {
  _TileReadClient(this.inner);
  final HttpClient inner;
  int pendingRequests = 0;
  bool closed = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (url.scheme != 'https' ||
        url.host != 'shrddr.github.io' ||
        !url.path.startsWith('/maptiles/') ||
        !url.path.endsWith('.webp')) {
      throw StateError('Session captures may only read the real map tiles.');
    }
    pendingRequests++;
    var completed = false;
    void complete() {
      if (!completed) {
        completed = true;
        pendingRequests--;
      }
    }

    try {
      return _TileReadRequest(await inner.getUrl(url), complete);
    } catch (_) {
      complete();
      rethrow;
    }
  }

  @override
  Duration? get connectionTimeout => inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;
  @override
  void close({bool force = false}) {
    closed = true;
    inner.close(force: force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unsupported capture HTTP operation: ${invocation.memberName}',
  );
}

class _TileReadRequest implements HttpClientRequest {
  _TileReadRequest(this.inner, this.complete);
  final HttpClientRequest inner;
  final VoidCallback complete;

  @override
  Future<HttpClientResponse> close() async {
    try {
      return _TileReadResponse(await inner.close(), complete);
    } catch (_) {
      complete();
      rethrow;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unsupported capture request operation: ${invocation.memberName}',
  );
}

class _TileReadResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _TileReadResponse(this.inner, this.complete);
  final HttpClientResponse inner;
  final VoidCallback complete;

  @override
  int get statusCode => inner.statusCode;

  Stream<List<int>> get _body async* {
    try {
      yield* inner;
    } finally {
      complete();
    }
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unsupported capture response operation: ${invocation.memberName}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  late Directory temporaryRoot;
  final artwork = <String, ui.Image>{};

  setUpAll(() async {
    catalog = await Catalog.load();
    temporaryRoot = await Directory.systemTemp.createTemp(
      'bdo-session-visual-',
    );
    for (final method in catalog.methods) {
      final data = await rootBundle.load(
        'packages/bdo_gathering_companion/${method.icon}',
      );
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      try {
        artwork[method.id] = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    }
    if (_captureSession || Platform.isWindows) await _loadNativeFonts();
  });

  tearDownAll(() async {
    for (final image in artwork.values) {
      image.dispose();
    }
    if (temporaryRoot.parent.absolute.path !=
            Directory.systemTemp.absolute.path ||
        !temporaryRoot.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('bdo-session-visual-')) {
      throw StateError('Refusing to remove an unexpected test directory.');
    }
    await temporaryRoot.delete(recursive: true);
  });

  final savedPreparation = GatheringPreparation(
    baseSettings: const BairogCalculatorSettings(
      mastery: 1735,
      gatheringDropRatePercent: 47.25,
      enabledExpenseItemIds: {},
    ),
    buffIds: {'buff-yawning-hedgehog'},
    statsConfirmed: true,
  );

  _MemorySessionStore newStore({
    bool chosenSpot = true,
    bool confirmedStats = false,
    String methodId = 'butcher',
  }) {
    final store = _MemorySessionStore(temporaryRoot);
    final spot = catalog.spots.firstWhere(
      (spot) => spot.methodIds.contains(methodId) && spot.mapped,
    );
    store.preferences = {
      'methodId': methodId,
      if (chosenSpot) 'spotId': spot.id,
      if (confirmedStats)
        gatheringPreparationPreferenceKey: savedPreparation.toJson(),
    };
    return store;
  }

  Widget session(
    GlobalKey capture, {
    double opacity = 60,
    double textScale = 1,
    bool chosenSpot = true,
    bool confirmedStats = false,
    String methodId = 'butcher',
  }) => RepaintBoundary(
    key: capture,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: companionTheme(opacityPercent: opacity),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: companionBackdropBuilder(context, child),
      ),
      home: GatheringHostServicesScope(
        services: GatheringHostServices(openExternal: (_) async => true),
        child: CompanionHome(
          catalog: catalog,
          store: newStore(
            chosenSpot: chosenSpot,
            confirmedStats: confirmedStats,
            methodId: methodId,
          ),
          glassOpacityPercent: opacity.toInt(),
          onGlassOpacityChanged: (_) {},
        ),
      ),
    ),
  );

  test('every original method asset decodes, including both rifles', () async {
    expect(
      catalog.methods.map((method) => method.id),
      orderedEquals(_methodIds),
    );
    for (final method in catalog.methods) {
      final image = artwork[method.id]!;
      expect(image.width, greaterThan(0), reason: method.label);
      expect(image.height, greaterThan(0), reason: method.label);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var visiblePixels = 0;
      for (var index = 3; index < bytes.lengthInBytes; index += 4) {
        if (bytes.getUint8(index) > 32) visiblePixels++;
      }
      expect(
        visiblePixels,
        greaterThan(30),
        reason: '${method.label} must not be empty artwork.',
      );
    }
    expect(
      catalog.methods.firstWhere((method) => method.id == 'hunting').icon,
      'assets/icons/tools/hunting_matchlock.webp',
    );
    expect(
      catalog.methods.firstWhere((method) => method.id == 'sniper').icon,
      'assets/icons/tools/sniper_rifle.webp',
    );
  });

  testWidgets('hunting damage advice is readable inside real Prepare', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    final capture = GlobalKey();
    final oldShadows = debugDisableShadows;
    final oldHttp = HttpOverrides.current;
    final tileHttp = _captureSession ? _TileReadOverrides() : null;
    if (_captureSession) debugDisableShadows = false;
    if (tileHttp != null) HttpOverrides.global = tileHttp;
    try {
      await tester.pumpWidget(
        session(capture, methodId: 'hunting', confirmedStats: true),
      );
      if (_captureSession) await _settleRealTiles(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workflow-prepare')));
      if (_captureSession) await _settleRealTiles(tester);
      await tester.pumpAndSettle();
      final store =
          tester.widget<CompanionHome>(find.byType(CompanionHome)).store
              as _MemorySessionStore;
      final before = jsonEncode(store.preferences);
      final saveCalls = store.saveCalls;
      final advice = find.byKey(const ValueKey('matchlock-damage-advice'));
      expect(advice, findsOneWidget);
      expect(find.byKey(const ValueKey('start-gathering')), findsOneWidget);
      if (_captureSession) {
        await _capture(tester, capture, 'matchlock-prepare-1200');
      }
      await tester.ensureVisible(advice);
      await tester.pumpAndSettle();
      if (_captureSession) {
        await _capture(tester, capture, 'matchlock-prepare-kit-1200');
      }
      final info = find.byKey(const ValueKey('matchlock-damage-info'));
      await tester.ensureVisible(info);
      await tester.tap(info);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('matchlock-damage-dialog')),
        findsOneWidget,
      );
      if (_captureSession) {
        await _capture(tester, capture, 'matchlock-prepare-guide-1200');
      }
      await tester.tap(
        find.byKey(const ValueKey('matchlock-close-damage-details')),
      );
      await tester.pumpAndSettle();
      expect(jsonEncode(store.preferences), before);
      expect(store.saveCalls, saveCalls);
      expect(find.byTooltip('Pause timer'), findsNothing);
      expect(find.byKey(const ValueKey('start-gathering')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      debugDisableShadows = oldShadows;
      tileHttp?.close();
      if (tileHttp != null) HttpOverrides.global = oldHttp;
    }
  });

  testWidgets(
    'all eight methods retain full names, original artwork and selection in Spots',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1563, 950);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(session(GlobalKey()));
      await tester.pumpAndSettle();
      final trigger = find.byKey(const ValueKey('spot-method-filter'));
      expect(trigger, findsOneWidget);
      for (final method in catalog.methods) {
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        final menuItem = find.ancestor(
          of: find.text(method.label),
          matching: find.byType(MenuItemButton),
        );
        expect(menuItem, findsOneWidget, reason: method.label);
        await tester.ensureVisible(menuItem);
        await tester.pumpAndSettle();
        expect(menuItem.hitTestable(), findsOneWidget, reason: method.label);
        final label = find.descendant(
          of: menuItem,
          matching: find.text(method.label),
        );
        expect(
          tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
          isFalse,
          reason: '${method.label} stays readable in the tool chooser.',
        );
        final icon = find.descendant(
          of: menuItem,
          matching: find.byType(GameIcon),
        );
        expect(tester.widget<GameIcon>(icon).path, method.icon);
        expect(tester.getSize(icon).shortestSide, greaterThanOrEqualTo(30));
        for (final opacity
            in find
                .ancestor(of: icon, matching: find.byType(Opacity))
                .evaluate()) {
          expect((opacity.widget as Opacity).opacity, 1);
        }
        await tester.tap(menuItem);
        await tester.pumpAndSettle();
        final semantics = find.ancestor(
          of: trigger,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == method.label,
          ),
        );
        expect(semantics, findsOneWidget);
        expect(tester.widget<Semantics>(semantics).properties.button, isTrue);
        final selectedIcon = find.descendant(
          of: trigger,
          matching: find.byType(GameIcon),
        );
        expect(tester.widget<GameIcon>(selectedIcon).path, method.icon);
        expect(
          find.byKey(ValueKey('method-${method.id}')),
          findsNothing,
          reason: 'The old eight-tool board must not return to the workflow.',
        );
        expect(tester.takeException(), isNull, reason: method.label);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  final scenarios = [
    for (final size in const [Size(1563, 950), Size(1000, 800), Size(700, 900)])
      for (final textScale in [1.0, 2.0])
        (
          size: size,
          textScale: textScale,
          opacity: 60.0,
          chosenSpot: true,
          confirmedStats: false,
        ),
    (
      size: const Size(1563, 950),
      textScale: 1.0,
      opacity: 100.0,
      chosenSpot: true,
      confirmedStats: false,
    ),
    (
      size: const Size(1563, 950),
      textScale: 1.0,
      opacity: 100.0,
      chosenSpot: false,
      confirmedStats: false,
    ),
    for (final saved in const [
      (size: Size(1563, 950), textScale: 1.0),
      (size: Size(700, 900), textScale: 1.0),
      (size: Size(700, 900), textScale: 2.0),
    ])
      (
        size: saved.size,
        textScale: saved.textScale,
        opacity: 60.0,
        chosenSpot: true,
        confirmedStats: true,
      ),
  ];
  for (final scenario in scenarios) {
    final suffix =
        '${scenario.size.width.toInt()}x${scenario.size.height.toInt()}'
        '-opacity${scenario.opacity.toInt()}-text${(scenario.textScale * 100).toInt()}'
        '${scenario.chosenSpot ? '' : '-no-spot'}'
        '${scenario.confirmedStats ? '-saved-stats' : ''}';
    testWidgets('guided-$suffix keeps each stage focused and reachable', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.size;
      addTearDown(tester.view.reset);
      final capture = GlobalKey();
      final oldShadows = debugDisableShadows;
      if (_captureSession) debugDisableShadows = false;
      final oldHttp = HttpOverrides.current;
      final tileHttp = _captureSession ? _TileReadOverrides() : null;
      if (tileHttp != null) HttpOverrides.global = tileHttp;
      try {
        await tester.pumpWidget(
          session(
            capture,
            opacity: scenario.opacity,
            textScale: scenario.textScale,
            chosenSpot: scenario.chosenSpot,
            confirmedStats: scenario.confirmedStats,
          ),
        );
        if (_captureSession) await _settleRealTiles(tester);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('workflow-tabs')), findsOneWidget);
        expect(find.byKey(const ValueKey('workflow-rail')), findsNothing);
        final sessions = find.byKey(const ValueKey('workflow-history'));
        expect(
          find.descendant(of: sessions, matching: find.text('Sessions')),
          findsOneWidget,
        );
        expect(find.text('History'), findsNothing);
        if (scenario.size.width >= 1100 * scenario.textScale) {
          final first = tester.getRect(
            find.byKey(const ValueKey('workflow-spots')),
          );
          var previous = first;
          for (final key in [
            'workflow-prepare',
            'workflow-gather',
            'workflow-history',
          ]) {
            final next = tester.getRect(find.byKey(ValueKey(key)));
            expect(next.top, moreOrLessEquals(first.top, epsilon: 1));
            expect(next.left, greaterThanOrEqualTo(previous.right));
            previous = next;
          }
        }
        final opacityControls = find.byWidgetPredicate(
          (widget) =>
              widget.key == const ValueKey('open-glass-opacity') ||
              widget.key == const ValueKey('glass-opacity-slider'),
        );
        expect(opacityControls, findsOneWidget);
        expect(
          find.byKey(
            ValueKey(scenario.size.width < 900 ? 'spot-strip' : 'spot-list'),
          ),
          findsOneWidget,
        );
        expect(find.byType(LootPanel), findsNothing);
        expect(find.byType(BuffPicker), findsNothing);
        expect(find.byKey(const ValueKey('paste-screenshot')), findsNothing);
        for (final key in [
          'workflow-spots',
          'workflow-prepare',
          'workflow-gather',
          'workflow-history',
        ]) {
          final step = find.byKey(ValueKey(key));
          expect(step, findsOneWidget);
          _expectViewportRect(tester.getRect(step), scenario.size);
        }
        for (final method in catalog.methods) {
          expect(find.byKey(ValueKey('method-${method.id}')), findsNothing);
        }
        if (_captureSession) await _capture(tester, capture, 'spots-$suffix');
        expect(tester.takeException(), isNull);

        if (!scenario.chosenSpot) {
          for (final key in ['workflow-prepare', 'workflow-gather']) {
            final button = tester.widget<ButtonStyleButton>(
              find.byKey(ValueKey(key)),
            );
            expect(button.onPressed, isNull);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          return;
        }

        await tester.tap(find.byKey(const ValueKey('workflow-prepare')));
        await tester.pumpAndSettle();
        if (_captureSession) await _settleRealTiles(tester);
        final preparation = find.byKey(
          const ValueKey('gathering-preparation-panel'),
        );
        expect(preparation, findsOneWidget);
        expect(opacityControls, findsNothing);
        expect(tester.element(preparation).glass.opacityPercent, 90);
        _expectFiniteRect(tester.getRect(preparation));
        final prepRect = tester.getRect(preparation);
        expect(prepRect.left, greaterThanOrEqualTo(0));
        expect(prepRect.right, lessThanOrEqualTo(scenario.size.width));
        expect(find.byKey(const ValueKey('preparation-stats')), findsOneWidget);
        for (final entry in {
          'inline-stats-mastery': '1735',
          'inline-stats-drop-rate': '47.25',
        }.entries) {
          final field = find.byKey(ValueKey(entry.key));
          final input = tester.widget<TextField>(field);
          expect(
            input.controller!.text,
            scenario.confirmedStats ? entry.value : '',
          );
          if (!scenario.confirmedStats) {
            expect(input.decoration!.hintText, startsWith('Example: '));
          }
          final bounds = tester.getRect(field);
          _expectFiniteRect(bounds);
          expect(bounds.left, greaterThanOrEqualTo(prepRect.left));
          expect(bounds.right, lessThanOrEqualTo(prepRect.right));
          for (final label
              in find
                  .descendant(of: field, matching: find.byType(Text))
                  .evaluate()) {
            final paragraph = label.findRenderObject();
            if (paragraph is RenderParagraph) {
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason: '${entry.key} keeps its complete label visible.',
              );
            }
          }
        }
        expect(
          find.byKey(const ValueKey('inline-stats-advanced')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('minigame-normal')), findsNothing);
        expect(
          find.byKey(const ValueKey('gathering-setup-dialog')),
          findsNothing,
        );
        if (scenario.confirmedStats) {
          final effective = savedPreparation.effectiveSettings(catalog);
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
        } else {
          expect(
            find.byKey(const ValueKey('preparation-effective-mastery')),
            findsNothing,
          );
        }
        expect(find.byType(LootPanel), findsNothing);
        expect(find.byKey(const ValueKey('paste-screenshot')), findsNothing);
        expect(find.text('Save session'), findsNothing);
        expect(find.byKey(const ValueKey('start-gathering')), findsOneWidget);
        expect(find.byKey(const ValueKey('record-results')), findsOneWidget);
        if (_captureSession) await _capture(tester, capture, 'prepare-$suffix');

        final extraDesktopEvidence =
            _captureSession &&
            scenario.size == const Size(1563, 950) &&
            scenario.textScale == 1 &&
            scenario.opacity == 60 &&
            scenario.confirmedStats;
        if (extraDesktopEvidence) {
          final advanced = find.byKey(const ValueKey('inline-stats-advanced'));
          await tester.ensureVisible(advanced);
          await tester.tap(advanced);
          await tester.pumpAndSettle();
          await _capture(tester, capture, 'prepare-advanced-$suffix');
          await tester.tap(advanced);
          await tester.pumpAndSettle();
        }

        // The compact recommendations do not remove the complete buff catalog.
        final allBuffs = find.byKey(
          const ValueKey('preparation-all-buffs-toggle'),
        );
        await tester.ensureVisible(allBuffs);
        if (extraDesktopEvidence) {
          await _capture(tester, capture, 'prepare-kit-$suffix');
        }
        await tester.tap(allBuffs);
        await tester.pumpAndSettle();
        expect(find.byType(BuffPicker), findsOneWidget);
        final finalRow = find.byKey(const ValueKey('buff-row-energy'));
        await tester.ensureVisible(finalRow);
        await tester.pumpAndSettle();
        expect(finalRow.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(allBuffs);
        await tester.tap(allBuffs);
        await tester.pumpAndSettle();

        final record = find.byKey(const ValueKey('record-results'));
        await tester.ensureVisible(record);
        await tester.tap(record);
        await tester.pumpAndSettle();
        if (_captureSession) await _settleRealTiles(tester);
        final frame = tester.getRect(
          find.byKey(const ValueKey('session-workspace')),
        );
        expect(opacityControls, findsNothing);
        expect(
          tester
              .element(find.byKey(const ValueKey('session-workspace')))
              .glass
              .opacityPercent,
          90,
        );
        _expectViewportRect(frame, scenario.size);
        expect(frame.width, lessThanOrEqualTo(1440));
        expect(find.byType(LootPanel), findsOneWidget);
        expect(find.byType(BuffPicker), findsNothing);
        expect(
          find.byKey(const ValueKey('gathering-preparation-panel')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('paste-screenshot')), findsOneWidget);
        expect(find.byTooltip('Pause timer'), findsNothing);
        final sessionScroll = find.byKey(const ValueKey('session-scroll'));
        expect(
          tester
              .widget<SingleChildScrollView>(sessionScroll)
              .controller!
              .hasClients,
          isTrue,
        );
        expect(find.byType(Scrollbar), findsNothing);
        if (_captureSession) await _capture(tester, capture, 'gather-$suffix');
        if (extraDesktopEvidence) {
          await tester.tap(find.byTooltip('Start timer'));
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byTooltip('Pause timer'), findsOneWidget);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1100)),
          );
          await tester.pump(const Duration(milliseconds: 1100));
          await _capture(tester, capture, 'gather-running-$suffix');
          await tester.tap(find.byTooltip('Pause timer'));
          await tester.pumpAndSettle();
        }
        final sharpName = find.text('Sharp Black Crystal Shard');
        expect(sharpName, findsOneWidget);
        await tester.ensureVisible(sharpName);
        await tester.pumpAndSettle();
        expect(
          tester.renderObject<RenderParagraph>(sharpName).didExceedMaxLines,
          isFalse,
          reason: 'Main loot names remain readable when text is enlarged.',
        );
        await tester.ensureVisible(find.text('Save session'));
        await tester.pumpAndSettle();
        expect(find.text('Save session').hitTestable(), findsOneWidget);
        if (extraDesktopEvidence) {
          // An isolated, in-memory session fixture exercises real History UI.
          // No existing user sessions or disk-backed profile are read/written.
          final duration = find.byKey(const ValueKey('time-30'));
          await tester.ensureVisible(duration);
          await tester.tap(duration);
          await tester.pumpAndSettle();
          final quantity = find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'loot-total-',
                ),
          );
          await tester.ensureVisible(quantity.first);
          await tester.enterText(quantity.first, '1200');
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Save session'));
          await tester.tap(find.text('Save session'));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('history-filters')), findsOneWidget);
          expect(opacityControls, findsNothing);
          await _capture(tester, capture, 'sessions-$suffix');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        debugDisableShadows = oldShadows;
        if (tileHttp != null) {
          tileHttp.close();
          HttpOverrides.global = oldHttp;
        }
      }
    });
  }
}

void _expectFiniteRect(Rect rect) {
  expect(
    [
      rect.left,
      rect.top,
      rect.right,
      rect.bottom,
    ].every((value) => value.isFinite),
    isTrue,
  );
  expect(rect.width, greaterThan(0));
  expect(rect.height, greaterThan(0));
}

void _expectViewportRect(Rect rect, Size viewport) {
  _expectFiniteRect(rect);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(viewport.width));
  expect(rect.bottom, lessThanOrEqualTo(viewport.height));
}

Future<void> _settleRealTiles(WidgetTester tester) async {
  var previousCount = 0;
  var stable = 0;
  for (var attempt = 0; attempt < 240; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    final images = find
        .byType(Image)
        .evaluate()
        .where((element) => (element.widget as Image).image is MemoryImage)
        .length;
    final override = HttpOverrides.current;
    final pending = override is _TileReadOverrides
        ? override.clients
              .where((client) => !client.closed)
              .fold(0, (sum, client) => sum + client.pendingRequests)
        : 0;
    stable = images > 0 && images == previousCount && pending == 0
        ? stable + 1
        : 0;
    previousCount = images;
    if (attempt >= 10 && stable >= 5) return;
  }
  throw StateError(
    'Real map tiles did not settle; refusing an empty-map user preview.',
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final providers = find
      .descendant(of: find.byKey(key), matching: find.byType(Image))
      .evaluate()
      .map((element) => (element.widget as Image).image)
      .toSet();
  for (final provider in providers) {
    await tester.runAsync(() => precacheImage(provider, key.currentContext!));
  }
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_captureDirectory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _loadNativeFonts() async {
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
  final fonts = <String, List<String>>{
    'Segoe UI': [
      for (final name in ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf'])
        '$windowsRoot/Fonts/$name',
    ],
    'Roboto': [
      for (final name in ['roboto-regular.ttf', 'roboto-bold.ttf'])
        '${flutterRoot.path}/bin/cache/artifacts/material_fonts/$name',
    ],
    'MaterialIcons': [
      '${flutterRoot.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
