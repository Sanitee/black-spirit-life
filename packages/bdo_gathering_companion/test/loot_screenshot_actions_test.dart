import 'dart:async';

import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/ui/loot_panel.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('bdo_gathering/native');
const _pasteKey = ValueKey('paste-screenshot');
const _openKey = ValueKey('open-screenshot');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final catalog = Catalog(
    methods: [],
    spots: [],
    buffs: [],
    items: [],
    categories: [],
    stats: [],
    presets: [],
    stackingNotes: [],
    reviewedAt: '',
  );

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  Future<void> mount(
    WidgetTester tester, {
    Map<String, LootEntry>? entries,
    VoidCallback? onChanged,
    ValueChanged<bool>? onValidityChanged,
    double width = 700,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: LootPanel(
                key: const ValueKey('loot-panel'),
                catalog: catalog,
                entries: entries ?? {},
                onChanged: onChanged ?? () {},
                onValidityChanged: onValidityChanged,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final width in [320.0, 420.0, 700.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('screenshot actions fit at $width px and ${scale}x text', (
        tester,
      ) async {
        await mount(tester, width: width, textScale: scale);
        expect(find.text('Paste screenshot'), findsOneWidget);
        expect(find.text('Open screenshot'), findsOneWidget);
        expect(find.byIcon(Icons.content_paste), findsOneWidget);
        expect(find.byIcon(Icons.image_outlined), findsOneWidget);
        final panel = tester.getRect(find.byKey(const ValueKey('loot-panel')));
        for (final key in [_pasteKey, _openKey]) {
          final rect = tester.getRect(find.byKey(key));
          expect(rect.left, greaterThanOrEqualTo(panel.left));
          expect(rect.right, lessThanOrEqualTo(panel.right + .01));
          expect(rect.width, lessThanOrEqualTo(width - 32));
        }
        for (final label in ['Paste screenshot', 'Open screenshot']) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(label),
          );
          expect(paragraph.didExceedMaxLines, isFalse);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'Open uses the native picker and cancellation leaves loot alone',
    (tester) async {
      final pending = Completer<String?>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call.method);
        expect(call.method, 'pickImage');
        return pending.future;
      });
      final entry = LootEntry(id: 'meat', name: 'Meat')
        ..setStart(100)
        ..setSnapshot(400)
        ..recordMaidDeposit(200);
      final entries = {'meat': entry};
      final original = entry.toJson();
      var changes = 0;
      final validity = <bool>[];
      await mount(
        tester,
        entries: entries,
        onChanged: () => changes++,
        onValidityChanged: validity.add,
      );
      await tester.tap(find.byKey(_openKey));
      await tester.pump();
      expect(calls, ['pickImage']);
      expect(
        tester.widget<TextButton>(find.byKey(_pasteKey)).onPressed,
        isNull,
      );
      expect(tester.widget<TextButton>(find.byKey(_openKey)).onPressed, isNull);
      expect(validity.last, isFalse);
      expect(entry.toJson(), original);
      expect(changes, 0);

      pending.complete(null);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextButton>(find.byKey(_pasteKey)).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<TextButton>(find.byKey(_openKey)).onPressed,
        isNotNull,
      );
      expect(validity.last, isTrue);
      expect(entries.keys, ['meat']);
      expect(entry.toJson(), original);
      expect(changes, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Paste uses the native clipboard and reports an empty clipboard', (
    tester,
  ) async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      expect(call.method, 'readClipboardImage');
      return null;
    });
    final entries = <String, LootEntry>{};
    var changes = 0;
    await mount(tester, entries: entries, onChanged: () => changes++);
    await tester.tap(find.byKey(_pasteKey));
    await tester.pumpAndSettle();
    expect(calls, ['readClipboardImage']);
    expect(
      find.text(
        'No image on the clipboard. Copy a screenshot first, or choose an image file.',
      ),
      findsOneWidget,
    );
    expect(entries, isEmpty);
    expect(changes, 0);
    expect(
      tester.widget<TextButton>(find.byKey(_pasteKey)).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<TextButton>(find.byKey(_openKey)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'local reader rejection recovers and allows the next image action',
    (tester) async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call.method);
        return call.method == 'readClipboardImage'
            ? Uint8List.fromList([0, 1, 2])
            : null;
      });
      final entries = <String, LootEntry>{};
      var changes = 0;
      await mount(tester, entries: entries, onChanged: () => changes++);
      await tester.tap(find.byKey(_pasteKey));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose a PNG, JPEG, or BMP screenshot.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextButton>(find.byKey(_openKey)).onPressed,
        isNotNull,
      );
      expect(entries, isEmpty);
      expect(changes, 0);

      await tester.tap(find.byKey(_openKey));
      await tester.pumpAndSettle();
      expect(calls, ['readClipboardImage', 'pickImage']);
      expect(find.text('Choose a PNG, JPEG, or BMP screenshot.'), findsNothing);
      expect(find.text('Paste screenshot'), findsOneWidget);
      expect(entries, isEmpty);
      expect(changes, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
