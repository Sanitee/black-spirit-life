import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/services/session_store.dart';
import 'package:bdo_gathering_companion/src/gathering_companion_home.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _receiptDirectory = r'C:\fixture\gathering\session-import-inbox';

const _package = 'bdo_gathering_companion';
const _minigame = 'assets/icons/sources/minigame_helper.png';
const _garmoth = 'assets/icons/sources/garmoth_icon.png';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  late Directory temporary;
  late SessionStore store;
  final captureDirectory = Platform.environment['GATHERING_ACTION_CAPTURE_DIR'];

  setUpAll(() async {
    catalog = await Catalog.load();
    temporary = await Directory.systemTemp.createTemp(
      'gathering-action-icons-',
    );
    store = SessionStore(directory: temporary);
    await store.load();
    if (Platform.isWindows) {
      final windowsRoot = Platform.environment['WINDIR'] ?? r'C:\Windows';
      final loader = FontLoader('Segoe UI');
      for (final name in ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf']) {
        loader.addFont(
          File(
            '$windowsRoot/Fonts/$name',
          ).readAsBytes().then(ByteData.sublistView),
        );
      }
      await loader.load();
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
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        File(
          '${flutterRoot.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes().then(ByteData.sublistView),
      );
      await icons.load();
    }
  });
  tearDownAll(() async => temporary.delete(recursive: true));

  test(
    'action artwork decodes and matches its recorded unchanged source',
    () async {
      final provenance =
          jsonDecode(
                await rootBundle.loadString(
                  'packages/$_package/assets/icons/sources/provenance.json',
                ),
              )
              as Map<String, dynamic>;
      for (final path in [_minigame, _garmoth]) {
        final data = await rootBundle.load('packages/$_package/$path');
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final record = provenance[path.split('/').last] as Map<String, dynamic>;
        expect(sha256.convert(bytes).toString(), record['sha256']);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(
          '${frame.image.width}x${frame.image.height}',
          record['dimensions'],
        );
        expect(frame.image.width, greaterThanOrEqualTo(22));
        expect(frame.image.height, greaterThanOrEqualTo(22));
        frame.image.dispose();
        codec.dispose();
      }
      expect(
        provenance['minigame_helper.png']['sha256'],
        '7847698bb25cf870070472333bbb1d94b10f9905e3f4e5598b14a55f0abc78a2',
      );
      final official = Uri.parse(
        provenance['garmoth_icon.png']['source'] as String,
      );
      expect(official.scheme, 'https');
      expect({'garmoth.com', 'assets.garmoth.com'}, contains(official.host));
    },
  );

  for (final variant in [
    (width: 1200.0, scale: 1.0),
    (width: 1500.0, scale: 1.0),
    (width: 1200.0, scale: 2.0),
    (width: 1500.0, scale: 2.0),
    (width: 900.0, scale: 2.0),
  ]) {
    final name =
        '${variant.width.toInt()}-text${(variant.scale * 100).toInt()}';
    testWidgets(
      'actual Gathering action artwork preserves native actions $name',
      (tester) async {
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = Size(variant.width, 752);
        addTearDown(tester.view.reset);
        final shadows = debugDisableShadows;
        if (captureDirectory != null) debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = shadows);
        const channel = MethodChannel('bdo_gathering/native');
        final calls = <MethodCall>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final capture = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: companionTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(variant.scale),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: CompanionBackdrop(
                child: CompanionHome(
                  catalog: catalog,
                  store: store,
                  glassOpacityPercent: defaultGlassOpacityPercent,
                  onGlassOpacityChanged: (_) {},
                  sessionImportReceiptDirectory: _receiptDirectory,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final action in [
          (
            key: 'open-minigame-helper',
            label: 'Minigame Helper',
            path: _minigame,
          ),
          (key: 'open-garmoth-upload', label: 'Garmoth Upload', path: _garmoth),
        ]) {
          final button = find.byKey(ValueKey(action.key));
          expect(button.hitTestable(), findsOneWidget);
          expect(
            tester.widget(button),
            variant.width >= 1400 ? isA<TextButton>() : isA<IconButton>(),
          );
          final imageFinder = find.descendant(
            of: button,
            matching: find.byType(Image),
          );
          expect(imageFinder, findsOneWidget);
          final image = tester.widget<Image>(imageFinder);
          final asset = image.image as AssetImage;
          expect(asset.assetName, action.path);
          expect(asset.package, _package);
          expect(image.fit, BoxFit.contain);
          expect(
            image.color,
            isNull,
            reason: 'Keep the supplied artwork colours.',
          );
          expect(image.excludeFromSemantics, isTrue);
          expect(tester.getSize(imageFinder), const Size(32, 32));
          final bounds = tester.getRect(button);
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(variant.width));
          expect(bounds.top, greaterThanOrEqualTo(0));
          expect(bounds.bottom, lessThanOrEqualTo(752));
          if (variant.width < 1400) {
            expect(find.byTooltip(action.label), findsOneWidget);
          } else {
            final label = find.descendant(
              of: button,
              matching: find.text(action.label),
            );
            expect(label, findsOneWidget);
            expect(
              tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
              isFalse,
            );
          }
        }
        expect(calls, isEmpty);
        expect(tester.takeException(), isNull);

        if (captureDirectory != null) {
          for (final provider
              in find
                  .byType(Image)
                  .evaluate()
                  .map((element) => (element.widget as Image).image)
                  .toSet()) {
            await tester.runAsync(
              () => precacheImage(provider, capture.currentContext!),
            );
          }
          await tester.pumpAndSettle();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(capture),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '$captureDirectory/gathering-actions-$name.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        await tester.tap(find.byKey(const ValueKey('open-minigame-helper')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('open-garmoth-upload')));
        await tester.pump();
        expect(calls.map((call) => call.method), [
          'openReferenceWindow',
          'openSessionImport',
        ]);
        expect(calls.first.arguments, {
          'glassOpacityPercent': defaultGlassOpacityPercent,
        });
        expect(calls.last.arguments, {'receiptDirectory': _receiptDirectory});
        expect(tester.takeException(), isNull);
        debugDisableShadows = shadows;
      },
    );
  }
}
