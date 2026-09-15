import 'dart:convert';
import 'dart:io';

import 'package:bdo_gathering_companion/src/domain/models.dart';
import 'package:bdo_gathering_companion/src/feature.dart';
import 'package:bdo_gathering_companion/src/gathering_companion_home.dart';
import 'package:bdo_gathering_companion/src/services/session_store.dart';
import 'package:bdo_gathering_companion/src/services/shared_market_loader.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('bdo_gathering/native');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'actual feature receives native prepared history without resetting its active draft and replays safely after restart',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 940);
      addTearDown(tester.view.reset);
      final temporary = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('bsl-session-feature-'),
      ))!;
      final directory = Directory('${temporary.path}/gathering');
      final cache = Directory('${temporary.path}/isolated-video-cache');
      final previousIO = IOOverrides.current;
      // Feature startup cleans its own old video cache. Route that precise
      // optional housekeeping path to our temp fixture too, not live AppData.
      IOOverrides.global = _IsolatedVideoCache(cache.path);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        IOOverrides.global = previousIO;
        await tester.runAsync(() => temporary.delete(recursive: true));
      });

      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        if (call.method != 'openSessionImport') {
          fail('Unexpected native action: ${call.method}');
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

      final catalog = (await tester.runAsync(Catalog.load))!;
      final method = catalog.methods.first;
      final spot = catalog.spots.firstWhere(
        (candidate) => candidate.methodIds.contains(method.id),
      );
      await tester.runAsync(() async {
        await directory.create(recursive: true);
        await File('${directory.path}/sessions.json').writeAsString(
          jsonEncode({
            'schemaVersion': 1,
            'sessions': <Object?>[],
            'preferences': {'methodId': method.id, 'spotId': spot.id},
          }),
        );
      });
      final bytes = await _fixtureBytes(tester);
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final metadata = SessionImportMetadata.fromJson(json);
      expect(metadata.spotId, '17');
      expect(metadata.activity, 'grinding');
      expect(metadata.items.map((item) => item.itemId), [
        '44482',
        '8135',
        '8145',
      ]);
      expect(metadata.items.map((item) => item.quantity), [45678, 9, 234]);

      Future<void> mount() async {
        await tester.pumpWidget(
          GatheringCompanionFeature(
            dataDirectory: directory,
            sharedMarketLoader: _noNetworkMarket,
          ),
        );
        await _until(
          tester,
          () => find.byType(CompanionHome).evaluate().isNotEmpty,
        );
      }

      await mount();
      final homeState = tester.state(find.byType(CompanionHome));
      final home = tester.widget<CompanionHome>(find.byType(CompanionHome));
      final expectedInbox =
          '${directory.absolute.path}${Platform.pathSeparator}session-import-inbox';
      expect(home.sessionImportReceiptDirectory, expectedInbox);
      expect(home.store.directory.absolute.path, directory.absolute.path);
      await tester.tap(find.byKey(const ValueKey('open-garmoth-upload')));
      await tester.pump();
      expect(calls, hasLength(1));
      expect(calls.single.method, 'openSessionImport');
      expect(calls.single.arguments, {'receiptDirectory': expectedInbox});

      await tester.tap(find.byKey(const ValueKey('workflow-gather')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('time-60')));
      await tester.pump();
      await tester.ensureVisible(find.text('Details'));
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      final noteField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Notes',
      );
      await tester.enterText(noteField, 'Keep my separate unfinished draft');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final name =
          '${metadata.importId.replaceAll('-', '')}-${metadata.revision.toString().padLeft(10, '0')}.json';
      final inboxFile = File('$expectedInbox${Platform.pathSeparator}$name');
      Future<void> enqueue() async {
        await tester.runAsync(() async {
          await inboxFile.parent.create(recursive: true);
          await inboxFile.writeAsBytes(bytes, flush: true);
        });
      }

      await enqueue();
      // Drive the real feature-owned inbox's two-second lifecycle poll.
      await tester.pump(const Duration(seconds: 2));
      await _until(tester, () => home.store.sessions.length == 1);
      expect(tester.state(find.byType(CompanionHome)), same(homeState));
      expect(
        tester.widget<CompanionHome>(find.byType(CompanionHome)).store,
        same(home.store),
      );
      expect(find.byKey(const ValueKey('session-workspace')), findsOneWidget);
      final timeChoice = tester.widget<GlassControl>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('time-60')),
              matching: find.byType(GlassControl),
            )
            .first,
      );
      expect(timeChoice.selected, isTrue);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(noteField).controller!.text,
        'Keep my separate unfinished draft',
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final imported = home.store.sessions.single;
      expect(imported.id, metadata.sessionId);
      expect(imported.methodId, 'grinding');
      expect(imported.methodLabel, 'Grinding');
      expect(imported.methodIcon, isEmpty);
      expect(imported.loot.map((item) => item.id), ['44482', '8135', '8145']);
      expect(imported.loot.map((item) => item.total), [45678, 9, 234]);
      expect(imported.durationSeconds, 3600);
      expect(imported.sessionImport!.agrisActive, isFalse);
      expect(imported.sessionImport!.additionalDropRate, 0);
      expect(imported.sessionImport!.additionalDropAmount, isNull);
      await _until(tester, () => !inboxFile.existsSync());
      final persisted = SessionStore(directory: directory);
      await tester.runAsync(persisted.load);
      expect(persisted.sessions.single.toJson(), imported.toJson());

      await tester.tap(find.byKey(const ValueKey('workflow-history')));
      await tester.pumpAndSettle();
      final history = find.byKey(ValueKey('history-session-${imported.id}'));
      expect(history, findsOneWidget);
      expect(
        find.descendant(of: history, matching: find.text('Grinding')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ValueKey('history-target-${imported.id}')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Loot'), findsOneWidget);
      expect(find.text('Gathered items'), findsNothing);
      for (final item in metadata.items) {
        expect(find.text(item.name), findsOneWidget);
      }
      expect(find.text('Edit session'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      final edit = find.byKey(ValueKey('edit-session-${imported.id}'));
      if (edit.evaluate().isNotEmpty) {
        await tester.tap(edit);
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Update this session in Session Import, then send it again.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('gathering-history')), findsOneWidget);
        expect(find.text('Save changes'), findsNothing);
      }
      expect(calls, hasLength(1), reason: 'history never launches a browser');
      expect(tester.takeException(), isNull);

      // A duplicate receipt left by failed acknowledgement is harmless after
      // disposing and recreating the real feature/store/inbox lifecycle.
      await tester.pumpWidget(const SizedBox.shrink());
      await enqueue();
      await mount();
      final restarted = tester.widget<CompanionHome>(
        find.byType(CompanionHome),
      );
      await _until(tester, () => !inboxFile.existsSync());
      expect(restarted.store.sessions, hasLength(1));
      expect(restarted.store.sessions.single.toJson(), imported.toJson());
      expect(calls, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) return;
  }
  fail(
    'The real feature/inbox lifecycle did not settle within the bounded test.',
  );
}

Future<GatheringMarketLoadResult> _noNetworkMarket(
  Map<String, String> itemsById, {
  required bool includePreorders,
  required bool forceRefresh,
  required void Function(GatheringMarketReceipt receipt) onItem,
  Future<void>? cancelled,
}) async => const GatheringMarketLoadResult();

final class _IsolatedVideoCache extends IOOverrides {
  _IsolatedVideoCache(this.cachePath);
  final String cachePath;

  @override
  Directory createDirectory(String path) {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null &&
        path.toLowerCase() ==
            '$local${Platform.pathSeparator}BDO Gathering Companion${Platform.pathSeparator}video-webview'
                .toLowerCase()) {
      return super.createDirectory(cachePath);
    }
    return super.createDirectory(path);
  }
}

Future<List<int>> _fixtureBytes(WidgetTester tester) async {
  final nativePath = Platform.environment['BSL_SESSION_IMPORT_RECEIPT'];
  if (nativePath != null && nativePath.isNotEmpty) {
    final bytes = await tester.runAsync(() => File(nativePath).readAsBytes());
    expect(bytes, isNotNull);
    return bytes!;
  }
  // Deterministic in-repository coverage when the external native-writer
  // artifact is absent. Final cross-language runs explicitly supply that file.
  return utf8.encode(
    jsonEncode({
      'schemaVersion': 1,
      'provider': 'garmoth',
      'status': 'prepared',
      'importId': '749a2f13-0ee9-4a35-8aaa-b9313624357f',
      'revision': 1,
      'importedAtUtc': '2026-09-14T14:00:00.0000000Z',
      'target': {
        'spotId': '17',
        'spotName': 'Orc Camp',
        'activity': 'grinding',
        'methodIds': <String>[],
        'linkedSourceIds': <String>[],
      },
      'session': {
        'durationSeconds': 3600,
        'agrisActive': false,
        'additionalDropRate': 0,
        'items': [
          {
            'itemId': '44482',
            'subKey': 0,
            'name': 'Oily Orange Mushroom',
            'quantity': 45678,
          },
          {
            'itemId': '8135',
            'subKey': 0,
            'name': 'Heart of the Arid Forest',
            'quantity': 9,
          },
          {
            'itemId': '8145',
            'subKey': 0,
            'name': 'Shard of the Furious Night',
            'quantity': 234,
          },
        ],
      },
      'preparation': {
        'matchedCount': 3,
        'notesCount': 0,
        'skippedCount': 0,
        'submitted': false,
      },
    }),
  );
}
