import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/src/domain/matchlock_advice.dart';
import 'package:bdo_gathering_companion/src/ui/matchlock_damage_advice.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureEvidence = bool.fromEnvironment('CAPTURE_MATCHLOCK_ADVICE');
const _evidenceDirectory = 'build/matchlock-advice-evidence';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.isWindows || _captureEvidence) await _loadNativeFonts();
  });

  for (final width in [480.0, 700.0, 1200.0]) {
    for (final textScale in [1.0, 2.0]) {
      final suffix = '${width.toInt()}-text${(textScale * 100).toInt()}';
      testWidgets('matchlock advice stays readable and read-only at $suffix', (
        tester,
      ) async {
        final viewport = Size(width, 900);
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = viewport;
        addTearDown(tester.view.reset);
        final previousShadows = debugDisableShadows;
        if (_captureEvidence) debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = previousShadows);
        final calls = <MethodCall>[];
        const channel = MethodChannel('bdo_gathering/native');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return true;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });
        final capture = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              // Reading cards must stay protected even at the lowest setting.
              theme: companionTheme(opacityPercent: 0),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                  disableAnimations: true,
                ),
                child: companionBackdropBuilder(context, child),
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 1040),
                      child: const MatchlockDamageAdvice(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final advice = find.byKey(const ValueKey('matchlock-damage-advice'));
        expect(advice, findsOneWidget);
        for (final entry in matchlockCrystalAdvice) {
          final chip = find.byKey(ValueKey('matchlock-crystal-${entry.id}'));
          await tester.ensureVisible(chip);
          await tester.pumpAndSettle();
          expect(chip.hitTestable(), findsOneWidget);
          final art = find.descendant(
            of: chip,
            matching: find.byType(GameIcon),
          );
          expect(tester.widget<GameIcon>(art).path, entry.icon);
          expect(tester.widget<GameIcon>(art).size, 36);
          expect(tester.getSize(chip).width, lessThan(width - 40));
        }
        expect(calls, isEmpty);
        _expectNoClippedText(tester);
        await tester.ensureVisible(advice);
        await tester.pumpAndSettle();
        if (_captureEvidence) await _capture(tester, capture, 'row-$suffix');

        final entry = matchlockCrystalAdvice.first;
        final chip = find.byKey(ValueKey('matchlock-crystal-${entry.id}'));
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(chip));
        await tester.pump(const Duration(milliseconds: 350));
        final hover = find.byKey(
          ValueKey('matchlock-crystal-hover-${entry.id}'),
        );
        expect(hover, findsOneWidget);
        _expectInViewport(tester.getRect(hover), viewport);
        expect(find.text(entry.name), findsOneWidget);
        expect(calls, isEmpty, reason: 'Hovering must not open a browser.');
        _expectNoClippedText(tester);
        if (_captureEvidence) await _capture(tester, capture, 'hover-$suffix');
        // Even when a narrow viewport places the hover over its own chip,
        // secondary-clicking that preview must pin it without disappearing.
        final pinPoint = tester.getCenter(hover);
        await mouse.moveTo(pinPoint);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(pinPoint, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        expect(hover, findsNothing);
        final crystalDialog = find.byKey(
          ValueKey('matchlock-crystal-dialog-${entry.id}'),
        );
        expect(crystalDialog, findsOneWidget);
        expect(calls, isEmpty);
        for (final note in entry.notes) {
          expect(
            find.descendant(of: crystalDialog, matching: find.text(note)),
            findsOneWidget,
          );
        }
        _expectProtected(tester, crystalDialog);
        if (_captureEvidence) {
          await _capture(tester, capture, 'crystal-$suffix');
        }
        await _expandSources(tester, 'matchlock-crystal-${entry.id}-sources');
        for (final source in entry.sources) {
          final link = find.descendant(
            of: crystalDialog,
            matching: find.text(source.label),
          );
          await tester.ensureVisible(link);
          await tester.pumpAndSettle();
          expect(link.hitTestable(), findsOneWidget);
          final count = calls.length;
          await mouse.moveTo(tester.getCenter(link));
          await tester.pump(const Duration(milliseconds: 350));
          expect(calls.length, count);
          await tester.tap(link);
          await tester.pumpAndSettle();
          expect(calls.last.method, 'openExternal');
          expect(calls.last.arguments, {'url': source.url});
        }
        final closeCrystal = find.byKey(
          ValueKey('matchlock-close-crystal-${entry.id}'),
        );
        await tester.ensureVisible(closeCrystal);
        await tester.tap(closeCrystal);
        await tester.pumpAndSettle();
        expect(crystalDialog, findsNothing);
        await mouse.moveTo(Offset.zero);
        await tester.pump(const Duration(milliseconds: 200));

        // The ordinary primary click pins the same reference without relying
        // on hover or a desktop-only secondary-click interaction.
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(crystalDialog, findsOneWidget);
        expect(hover, findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(crystalDialog, findsNothing);

        final info = find.byKey(const ValueKey('matchlock-damage-info'));
        await tester.ensureVisible(info);
        await tester.tap(info);
        await tester.pumpAndSettle();
        final guide = find.byKey(const ValueKey('matchlock-damage-dialog'));
        expect(guide, findsOneWidget);
        _expectProtected(tester, guide);
        for (final section in matchlockDamageSections) {
          expect(
            find.descendant(of: guide, matching: find.text(section.title)),
            findsOneWidget,
          );
          for (final line in section.lines) {
            expect(
              find.descendant(of: guide, matching: find.text(line)),
              findsOneWidget,
            );
          }
        }
        _expectNoClippedText(tester);
        if (_captureEvidence) await _capture(tester, capture, 'guide-$suffix');
        await _expandSources(tester, 'matchlock-damage-sources');
        for (final source in matchlockAdviceSources) {
          final link = find.descendant(
            of: guide,
            matching: find.text(source.label),
          );
          await tester.ensureVisible(link);
          await tester.pumpAndSettle();
          expect(link.hitTestable(), findsOneWidget);
          await tester.tap(link);
          await tester.pumpAndSettle();
          expect(calls.last.method, 'openExternal');
          expect(calls.last.arguments, {'url': source.url});
        }
        _expectNoClippedText(tester);
        if (_captureEvidence) {
          await _capture(tester, capture, 'guide-sources-$suffix');
        }
        final close = find.byKey(
          const ValueKey('matchlock-close-damage-details'),
        );
        await tester.ensureVisible(close);
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(guide, findsNothing);
        await mouse.moveTo(Offset.zero);
        await tester.pump(const Duration(milliseconds: 200));
        for (final crystal in matchlockCrystalAdvice) {
          final crystalChip = find.byKey(
            ValueKey('matchlock-crystal-${crystal.id}'),
          );
          await tester.ensureVisible(crystalChip);
          await tester.tap(crystalChip);
          await tester.pumpAndSettle();
          final details = find.byKey(
            ValueKey('matchlock-crystal-dialog-${crystal.id}'),
          );
          expect(details, findsOneWidget);
          for (final line in [
            crystal.name,
            crystal.benefit,
            ...crystal.notes,
          ]) {
            expect(
              find.descendant(of: details, matching: find.text(line)),
              findsOneWidget,
            );
          }
          _expectProtected(tester, details);
          _expectNoClippedText(tester);
          final close = find.byKey(
            ValueKey('matchlock-close-crystal-${crystal.id}'),
          );
          await tester.ensureVisible(close);
          await tester.tap(close);
          await tester.pumpAndSettle();
          expect(details, findsNothing);
        }
        expect(
          calls.length,
          entry.sources.length + matchlockAdviceSources.length,
        );
        expect(calls.every((call) => call.method == 'openExternal'), isTrue);
        expect(find.byType(Scrollbar), findsNothing);
        expect(find.byType(RawScrollbar), findsNothing);
        expect(tester.takeException(), isNull);
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        debugDisableShadows = previousShadows;
      });
    }
  }
}

Future<void> _expandSources(WidgetTester tester, String key) async {
  final title = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.text('Sources'),
  );
  await tester.ensureVisible(title);
  await tester.pumpAndSettle();
  await tester.tap(title);
  await tester.pumpAndSettle();
}

void _expectProtected(WidgetTester tester, Finder scope) {
  final surfaces = find.descendant(
    of: scope,
    matching: find.byType(GlassSurface),
  );
  expect(surfaces, findsWidgets);
  expect(
    tester.widgetList<GlassSurface>(surfaces).any((s) => s.reading),
    isTrue,
  );
  final text = find.descendant(of: scope, matching: find.byType(Text)).first;
  expect(tester.element(text).glass.opacityPercent, greaterThanOrEqualTo(96));
}

void _expectInViewport(Rect rect, Size viewport) {
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(viewport.width));
  expect(rect.bottom, lessThanOrEqualTo(viewport.height));
}

void _expectNoClippedText(WidgetTester tester) {
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.findRenderObject();
    if (paragraph is RenderParagraph && paragraph.hasSize) {
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: 'Advice copy must wrap, not disappear behind an ellipsis.',
      );
    }
  }
  expect(tester.takeException(), isNull);
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  for (final provider
      in find
          .byType(Image)
          .evaluate()
          .map((element) => (element.widget as Image).image)
          .toSet()) {
    await tester.runAsync(() => precacheImage(provider, key.currentContext!));
  }
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_evidenceDirectory/$name.png');
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
      throw StateError('Flutter fonts missing.');
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
  for (final font in fonts.entries) {
    final loader = FontLoader(font.key);
    for (final path in font.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
