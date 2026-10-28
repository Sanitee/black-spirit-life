import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/application_theme.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_pill.dart' as actual;
import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/resource_map_pill_current_fixture.dart' as current;
import 'fixtures/resource_map_pill_earlier_fixture.dart' as earlier;

const _diagnostic = bool.fromEnvironment(
  'BSL_DIAGNOSTIC_EARLIER_RESOURCE_PILL_PAINT',
);
const _captureKey = ValueKey('pill-diagnostic-capture');
const _pillKey = ValueKey('pill-diagnostic-surface');
const _actionKey = ValueKey('pill-diagnostic-action');
const _artworkKey = ValueKey('pill-diagnostic-artwork');
const _labelKey = ValueKey('pill-diagnostic-label');
const _currentSha =
    '8f33c4cddfb9f88247a3dabf5e38a4673af2ca7dd47dd6b268e1a75dd28b1c6f';
const _earlierSha =
    '775ce9955fbd819bed59da0b6b9ec22371deecf4d61af014189a38ad07fe1143';
late Uint8List _artwork;

enum _Implementation { actual, current, earlier }

enum _Interaction { idle, hovered, pressed, focused, disabledHover }

class _Case {
  const _Case({
    required this.name,
    required this.opacity,
    this.leadingWidth,
    this.layered = false,
    this.quiet = false,
    this.selected = false,
    this.rtl = false,
    this.interaction = _Interaction.idle,
  });

  final String name;
  final double opacity;
  final double? leadingWidth;
  final bool layered;
  final bool quiet;
  final bool selected;
  final bool rtl;
  final _Interaction interaction;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await _loadFonts();
    final bytes = await rootBundle.load(
      'packages/bdo_map_core/assets/images/menu_artwork/iron_ore.webp',
    );
    _artwork = Uint8List.fromList(Uint8List.sublistView(bytes));
  });

  test('independent frozen paint oracles match protected source hashes', () {
    for (final (name, expected) in [
      ('current', _currentSha),
      ('earlier', _earlierSha),
    ]) {
      final text = File(
        'test/features/resource_map/fixtures/'
        'resource_map_pill_${name}_fixture.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final source = text
          .split('// BEGIN FROZEN PILL SOURCE\n')
          .last
          .replaceFirst(
            "import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';",
            "import 'resource_map_chrome_theme.dart';",
          );
      expect(sha256.convert(utf8.encode(source)).toString(), expected);
      expect(
        source,
        isNot(contains('BSL_DIAGNOSTIC_EARLIER_RESOURCE_PILL_PAINT')),
      );
      expect(source, isNot(contains('earlier_resource_pill_paint.dart')));
    }
  });

  for (final (themeName, spec) in _themes) {
    // Representative combinations, not a Cartesian-product golden suite.
    for (final configuration in const [
      _Case(name: 'plain-zero', opacity: 0),
      _Case(name: 'artwork-70', opacity: .7, leadingWidth: 56),
      _Case(
        name: 'layered-quiet-full',
        opacity: 1,
        leadingWidth: 56,
        layered: true,
        quiet: true,
      ),
      _Case(
        name: 'selected-rtl-70',
        opacity: .7,
        leadingWidth: 56,
        selected: true,
        rtl: true,
      ),
    ]) {
      testWidgets('$themeName ${configuration.name} matches frozen paint', (
        tester,
      ) async {
        await _compare(
          tester,
          '$themeName-${configuration.name}',
          spec,
          configuration,
        );
      });
    }
  }

  for (final interaction in [
    _Interaction.hovered,
    _Interaction.pressed,
    _Interaction.focused,
    _Interaction.disabledHover,
  ]) {
    testWidgets('${interaction.name} feedback matches frozen paint', (
      tester,
    ) async {
      final configuration = _Case(
        name: interaction.name,
        opacity: .7,
        leadingWidth: 56,
        interaction: interaction,
      );
      await _compare(
        tester,
        'feedback-${interaction.name}',
        SakuraNightGardenSpec.theme,
        configuration,
      );
    });
  }

  testWidgets(
    'diagnostic keeps actions, child identity and direct opacity updates',
    (tester) async {
      final opacity = ValueNotifier(.7);
      final reducedMotion = ValueNotifier(false);
      final focus = FocusNode();
      var activations = 0;
      final semantics = tester.ensureSemantics();
      try {
        final child = _child(
          resourceMapChromeThemeForPlannerTheme(SakuraNightGardenSpec.theme),
          focus,
          () => activations++,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Segoe UI'),
            home: ValueListenableBuilder<bool>(
              valueListenable: reducedMotion,
              child: child,
              builder: (context, reduce, child) =>
                  ValueListenableBuilder<double>(
                    valueListenable: opacity,
                    child: child,
                    builder: (context, value, child) => MediaQuery(
                      data: MediaQueryData(disableAnimations: reduce),
                      child: ResourceMapThemeAdapter(
                        spec: SakuraNightGardenSpec.theme,
                        uiOpacity: value,
                        child: Center(
                          child: SizedBox(
                            width: 312,
                            child: actual.ResourceMapPill(
                              key: _pillKey,
                              leadingWidth: 56,
                              child: child!,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            ),
          ),
        );
        await _settleArtwork(tester);
        final bounds = tester.getRect(find.byKey(_pillKey));
        final childElement = tester.element(find.byKey(_actionKey));
        final pillState = tester.state(find.byKey(_pillKey));
        expect(_container(tester).duration, const Duration(milliseconds: 150));
        expect(find.bySemanticsLabel('Iron Ore'), findsOneWidget);
        await tester.tapAt(bounds.centerLeft + const Offset(3, 0));
        await tester.pumpAndSettle();
        expect(
          activations,
          1,
          reason: 'Paint-only edges do not intercept clicks.',
        );
        focus.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(activations, 3);
        focus.unfocus();
        await tester.pumpAndSettle();

        for (final value in [0.0, 1.0, .7]) {
          opacity.value = value;
          await tester.pump();
          expect(_container(tester).duration, Duration.zero);
          final target = _container(tester).decoration! as BoxDecoration;
          final painted = tester
              .widgetList<DecoratedBox>(
                find.descendant(
                  of: find.byKey(_pillKey),
                  matching: find.byType(DecoratedBox),
                ),
              )
              .map((widget) => widget.decoration)
              .whereType<BoxDecoration>()
              .singleWhere((decoration) => decoration.gradient != null);
          expect(
            painted,
            target,
            reason: 'Opacity must paint its new value in one frame.',
          );
          final gradient = target.gradient! as LinearGradient;
          final strength = value < .02 ? .02 : value;
          expect(gradient.colors.first.a, closeTo(.96 * strength, .000001));
          expect(gradient.colors.last.a, closeTo(.98 * strength, .000001));
          expect(tester.getRect(find.byKey(_pillKey)), bounds);
          expect(tester.element(find.byKey(_actionKey)), same(childElement));
          expect(tester.state(find.byKey(_pillKey)), same(pillState));
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.binding.hasScheduledFrame, isFalse);
        }

        reducedMotion.value = true;
        await tester.pump();
        expect(_container(tester).duration, Duration.zero);
        expect(find.byType(Opacity), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);
        final art = tester.widget<Image>(find.byKey(_artworkKey));
        expect(art.opacity, isNull);
        expect(art.color, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        focus.dispose();
        opacity.dispose();
        reducedMotion.dispose();
        semantics.dispose();
      }
    },
  );
}

List<(String, ThemeSpec)> get _themes => [
  ('sakura', SakuraNightGardenSpec.theme),
  ('ledger', IlluminatedLedgerSpec.theme),
  (
    'greenhouse',
    applicationThemeForAppearance(
      AppearanceSettings.classicDefaultsFor(CraftMode.alchemy),
    ),
  ),
];

Future<void> _compare(
  WidgetTester tester,
  String name,
  ThemeSpec spec,
  _Case configuration,
) async {
  final previousShadows = debugDisableShadows;
  debugDisableShadows = false;
  try {
    final rendered =
        <_Implementation, ({Uint8List bytes, Map<String, Rect> bounds})>{};
    for (final implementation in _Implementation.values) {
      rendered[implementation] = await _render(
        tester,
        '$name-${implementation.name}',
        implementation,
        spec,
        configuration,
      );
    }
    final expected = _diagnostic
        ? _Implementation.earlier
        : _Implementation.current;
    final opposite = _diagnostic
        ? _Implementation.current
        : _Implementation.earlier;
    final result = rendered[_Implementation.actual]!;
    final expectedPixels = _differentPixels(
      result.bytes,
      rendered[expected]!.bytes,
    );
    final oppositePixels = _differentPixels(
      result.bytes,
      rendered[opposite]!.bytes,
    );
    final report = {
      'diagnosticDefine': _diagnostic,
      'expectedOracle': expected.name,
      'currentSourceSha256': _currentSha,
      'earlierSourceSha256': _earlierSha,
      'expectedDifferentPixels': expectedPixels,
      'oppositeDifferentPixels': oppositePixels,
      'opacity': configuration.opacity,
      'leadingWidth': configuration.leadingWidth,
      'layered': configuration.layered,
      'quiet': configuration.quiet,
      'selected': configuration.selected,
      'rtl': configuration.rtl,
      'interaction': configuration.interaction.name,
      'bounds': {
        for (final entry in rendered.entries)
          entry.key.name: {
            for (final bound in entry.value.bounds.entries)
              bound.key: [
                bound.value.left,
                bound.value.top,
                bound.value.width,
                bound.value.height,
              ],
          },
      },
      'comparisonScope':
          'Pill paint only, identical current child/layout/theme data. '
          'Earlier Pill is not a rollback of the historical app or theme. '
          'Headless captures do not establish physical display behavior.',
    };
    final output = Platform.environment['RESOURCE_PILL_DIAGNOSTIC_CAPTURE_DIR'];
    if (output != null) {
      await tester.runAsync(() async {
        await Directory(output).create(recursive: true);
        await File(
          '$output/$name.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      });
    }
    expect(
      expectedPixels,
      0,
      reason: 'Actual paint must match $expected exactly.',
    );
    if (configuration.opacity >= .7) {
      expect(
        oppositePixels,
        greaterThan(0),
        reason: 'The independent oracles must discriminate the two finishes.',
      );
    }
    expect(result.bounds, rendered[_Implementation.current]!.bounds);
    expect(result.bounds, rendered[_Implementation.earlier]!.bounds);
  } finally {
    // The binding checks this global before addTearDown callbacks execute.
    debugDisableShadows = previousShadows;
  }
}

Future<({Uint8List bytes, Map<String, Rect> bounds})> _render(
  WidgetTester tester,
  String name,
  _Implementation implementation,
  ThemeSpec spec,
  _Case configuration,
) async {
  final focus = FocusNode();
  TestGesture? mouse;
  try {
    final chrome = resourceMapChromeThemeForPlannerTheme(
      spec,
    ).withUiOpacity(configuration.opacity);
    final child = _child(
      chrome,
      focus,
      configuration.interaction == _Interaction.disabledHover ? null : () {},
    );
    final pill = switch (implementation) {
      _Implementation.actual => actual.ResourceMapPill(
        key: _pillKey,
        selected: configuration.selected,
        quiet: configuration.quiet,
        leadingWidth: configuration.leadingWidth,
        child: child,
      ),
      _Implementation.current => current.ResourceMapPill(
        key: _pillKey,
        selected: configuration.selected,
        quiet: configuration.quiet,
        leadingWidth: configuration.leadingWidth,
        child: child,
      ),
      // The old paint has no artwork bay; keep precisely the same child.
      _Implementation.earlier => earlier.ResourceMapPill(
        key: _pillKey,
        selected: configuration.selected,
        quiet: configuration.quiet,
        child: child,
      ),
    };
    Widget content = SizedBox(width: 312, child: pill);
    if (configuration.layered) {
      content = ResourceMapReadingPlane(child: content);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          fontFamily: 'Segoe UI',
          platform: TargetPlatform.windows,
        ),
        home: MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: configuration.rtl
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: ResourceMapChromeTheme(
              data: chrome,
              child: Align(
                alignment: Alignment.topLeft,
                child: RepaintBoundary(
                  key: _captureKey,
                  child: SizedBox(
                    width: 360,
                    height: 118,
                    child: ColoredBox(
                      color: const Color(0xff46535a),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: content,
                        ),
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
    await _settleArtwork(tester);
    final beforeBounds = tester.getRect(find.byKey(_pillKey));
    if (configuration.interaction == _Interaction.focused) {
      focus.requestFocus();
    } else if (configuration.interaction != _Interaction.idle) {
      mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(700, 500));
      await mouse.moveTo(beforeBounds.center);
      if (configuration.interaction == _Interaction.pressed) {
        await mouse.down(beforeBounds.center);
      }
    }
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_pillKey)), beforeBounds);
    expect(_container(tester).duration, const Duration(milliseconds: 150));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(Opacity), findsNothing);
    final art = tester.widget<Image>(find.byKey(_artworkKey));
    expect(art.opacity, isNull);
    expect(art.color, isNull);
    final paint = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byKey(_pillKey),
            matching: find.byType(CustomPaint),
          ),
        )
        .singleWhere(
          (widget) =>
              widget.painter != null && widget.foregroundPainter != null,
        );
    expect(paint.painter!.hitTest(const Offset(24, 24)), isFalse);
    expect(paint.foregroundPainter!.hitTest(const Offset(2, 25)), isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    final bounds = <String, Rect>{
      'pill': tester.getRect(find.byKey(_pillKey)),
      'action': tester.getRect(find.byKey(_actionKey)),
      'artwork': tester.getRect(find.byKey(_artworkKey)),
      'label': tester.getRect(find.byKey(_labelKey)),
    };
    return (bytes: await _capture(tester, name), bounds: bounds);
  } finally {
    if (mouse != null) {
      if (configuration.interaction == _Interaction.pressed) await mouse.up();
      await mouse.removePointer();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    focus.dispose();
  }
}

Widget _child(
  ResourceMapChromeThemeData chrome,
  FocusNode focus,
  VoidCallback? onTap,
) => InkWell(
  key: _actionKey,
  focusNode: focus,
  onTap: onTap,
  splashFactory: NoSplash.splashFactory,
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  child: SizedBox(
    height: 50,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Image.memory(
            _artwork,
            key: _artworkKey,
            width: 36,
            height: 36,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Iron Ore',
              key: _labelKey,
              style: TextStyle(
                color: chrome.readingInk,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Icon(Icons.chevron_right, size: 19, color: chrome.readingInk),
        ],
      ),
    ),
  ),
);

AnimatedContainer _container(WidgetTester tester) =>
    tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(_pillKey),
        matching: find.byType(AnimatedContainer),
      ),
    );

Future<void> _settleArtwork(WidgetTester tester) async {
  await tester.runAsync(
    () => precacheImage(
      MemoryImage(_artwork),
      tester.element(find.byKey(_artworkKey)),
    ),
  );
  await tester.pumpAndSettle();
  final raw = tester.widgetList<RawImage>(find.byType(RawImage)).single;
  expect(raw.image, isNotNull);
  expect(raw.image!.width, greaterThan(0));
}

Future<Uint8List> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  expect(boundary.debugNeedsPaint, isFalse);
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final output =
          Platform.environment['RESOURCE_PILL_DIAGNOSTIC_CAPTURE_DIR'];
      if (output != null) {
        await Directory(output).create(recursive: true);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File(
          '$output/$name.png',
        ).writeAsBytes(Uint8List.sublistView(png));
      }
      return Uint8List.fromList(Uint8List.sublistView(bytes));
    } finally {
      image.dispose();
    }
  }))!;
}

int _differentPixels(Uint8List first, Uint8List second) {
  expect(first.length, second.length);
  var differences = 0;
  for (var offset = 0; offset < first.length; offset += 4) {
    if (first[offset] != second[offset] ||
        first[offset + 1] != second[offset + 1] ||
        first[offset + 2] != second[offset + 2] ||
        first[offset + 3] != second[offset + 3]) {
      differences++;
    }
  }
  return differences;
}

Future<void> _loadFonts() async {
  if (Platform.isWindows) {
    final windows = Platform.environment['WINDIR'] ?? 'C:/Windows';
    final loader = FontLoader('Segoe UI');
    for (final name in ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf']) {
      loader.addFont(
        File('$windows/Fonts/$name').readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  }
  var sdk = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${sdk.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    if (sdk.parent.path == sdk.path) {
      throw StateError('Flutter fonts not found.');
    }
    sdk = sdk.parent;
  }
  final loader = FontLoader('MaterialIcons');
  loader.addFont(
    File(
      '${sdk.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ).readAsBytes().then(ByteData.sublistView),
  );
  await loader.load();
}
