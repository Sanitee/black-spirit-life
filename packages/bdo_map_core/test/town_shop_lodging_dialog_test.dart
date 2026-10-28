import 'dart:async';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/town_shop_lodging_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/map_menu_capture.dart';

const _prefix = 'resource-map-town-lodging';
Finder _key(String suffix) => find.byKey(ValueKey('$_prefix-$suffix'));

void main() {
  testWidgets(
    'normal town rows have the same compact height with or without Loyalty',
    (tester) async {
      await _open(tester);
      for (final townId in ['1101', '1380', '1834', '1858', '601']) {
        expect(tester.getSize(_key('row-$townId')).height, 50);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all 28 catalog towns form one scrollable list without scrollbars',
    (tester) async {
      await _open(tester);
      expect(find.text('Extra lodging'), findsOneWidget);
      expect(find.text('Purchased slots'), findsOneWidget);
      expect(find.text('Town'), findsOneWidget);
      expect(find.text('Pearl'), findsOneWidget);
      expect(find.text('Loyalty'), findsOneWidget);
      expect(
        tester
            .widget<ListView>(_key('list'))
            .childrenDelegate
            .estimatedChildCount,
        28,
      );
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.byType(Scrollbar), findsNothing);
      expect(find.byType(RawScrollbar), findsNothing);
      expect(find.text('Altinova'), findsOneWidget);
      await tester.scrollUntilVisible(
        _key('row-1853'),
        300,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Yukjo Street').hitTestable(), findsOneWidget);
      expect(_key('loyalty-1853'), findsNothing);
      expect(_key('save').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'counts and checkbox are drafts, enforce limits, and Save returns once',
    (tester) async {
      final results = <Map<String, BdoTownWorkerCapacity>?>[];
      await _open(tester, onResult: results.add);
      final minus = _key('pearl-minus-1101');
      final plus = _key('pearl-plus-1101');
      expect(tester.widget<IconButton>(minus).onPressed, isNull);
      for (var index = 0; index < 5; index++) {
        await tester.tap(plus);
        await tester.pump();
      }
      expect(tester.widget<Text>(_key('pearl-count-1101')).data, '5');
      expect(tester.widget<IconButton>(plus).onPressed, isNull);
      await tester.tap(_key('loyalty-1101'));
      await tester.pump();
      expect(results, isEmpty);
      final save = tester.widget<FilledButton>(_key('save')).onPressed!;
      save();
      save();
      await tester.pumpAndSettle();
      expect(results, hasLength(1));
      final result = results.single!;
      expect(result.keys, ['1101']);
      expect(result['1101']!.pearlLodgingPurchasedCount, 5);
      expect(result['1101']!.loyaltyLodgingPurchasedCount, 1);
      expect(result['1101']!.otherBonusLodgingSlotCount, isNull);
      expect(result['1101']!.freeLodgingSlotCount, 7);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dismissal in ['cancel', 'close', 'escape', 'barrier']) {
    testWidgets(
      '$dismissal discards edited lodging without touching initial values',
      (tester) async {
        const original = BdoTownWorkerCapacity(
          availableWorkerCount: 3,
          freeLodgingSlotCount: 0,
          hiredWorkerCount: 3,
          bonusLodgingSlotCount: 1,
          pearlLodgingPurchasedCount: 1,
        );
        final initial = <String, BdoTownWorkerCapacity>{'1101': original};
        final results = <Map<String, BdoTownWorkerCapacity>?>[];
        await _open(tester, initial: initial, onResult: results.add);
        await tester.tap(_key('pearl-plus-1101'));
        await tester.pump();
        switch (dismissal) {
          case 'escape':
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          case 'barrier':
            await tester.tapAt(const Offset(5, 5));
          default:
            await tester.tap(_key(dismissal));
        }
        await tester.pumpAndSettle();
        expect(results, [null]);
        expect(initial.keys, ['1101']);
        expect(initial['1101'], same(original));
        expect(original.pearlLodgingPurchasedCount, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'untouched legacy unknown and out-of-range entries retain exact objects',
    (tester) async {
      const aggregate = BdoTownWorkerCapacity(
        availableWorkerCount: 7,
        freeLodgingSlotCount: 3,
        hiredWorkerCount: 7,
        bonusLodgingSlotCount: 9,
      );
      const effectiveOnly = BdoTownWorkerCapacity(
        availableWorkerCount: 4,
        freeLodgingSlotCount: 11,
      );
      const unusual = BdoTownWorkerCapacity(
        availableWorkerCount: 2,
        freeLodgingSlotCount: 20,
        hiredWorkerCount: 2,
        bonusLodgingSlotCount: 999,
        pearlLodgingPurchasedCount: 8,
        loyaltyLodgingPurchasedCount: 2,
        otherBonusLodgingSlotCount: 12,
      );
      const unknown = BdoTownWorkerCapacity(
        availableWorkerCount: 91,
        freeLodgingSlotCount: 17,
      );
      final initial = {
        '1101': aggregate,
        '1380': effectiveOnly,
        '1834': unusual,
        'future-town': unknown,
      };
      final results = <Map<String, BdoTownWorkerCapacity>?>[];
      await _open(tester, initial: initial, onResult: results.add);
      expect(_key('review-1101'), findsOneWidget);
      expect(_key('review-1380'), findsOneWidget);
      expect(_key('pearl-plus-1101'), findsNothing);
      expect(tester.widget<Text>(_key('pearl-count-1834')).data, '8');
      await tester.tap(_key('save'));
      await tester.pumpAndSettle();
      expect(results.single!.keys, initial.keys);
      for (final entry in initial.entries) {
        expect(results.single![entry.key], same(entry.value));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing one shop source preserves hired Other and nullable source fields',
    (tester) async {
      const original = BdoTownWorkerCapacity(
        availableWorkerCount: 7,
        freeLodgingSlotCount: 0,
        hiredWorkerCount: 7,
        bonusLodgingSlotCount: 4,
        pearlLodgingPurchasedCount: 1,
        otherBonusLodgingSlotCount: 3,
      );
      const yukjo = BdoTownWorkerCapacity(
        availableWorkerCount: 12,
        freeLodgingSlotCount: 0,
        hiredWorkerCount: 12,
      );
      final results = <Map<String, BdoTownWorkerCapacity>?>[];
      await _open(
        tester,
        initial: {'1101': original, '1853': yukjo},
        knownSlots: const {'1101': 4},
        onResult: results.add,
      );
      await tester.tap(_key('pearl-plus-1101'));
      await tester.pump();
      await tester.tap(_key('save'));
      await tester.pumpAndSettle();
      final changed = results.single!['1101']!;
      expect(changed.hiredWorkerCount, 7);
      expect(changed.availableWorkerCount, 7);
      expect(changed.freeLodgingSlotCount, 2);
      expect(changed.bonusLodgingSlotCount, 5);
      expect(changed.pearlLodgingPurchasedCount, 2);
      expect(changed.loyaltyLodgingPurchasedCount, isNull);
      expect(changed.otherBonusLodgingSlotCount, 3);
      expect(results.single!['1853'], same(yukjo));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editing an out-of-range Pearl value changes only that source', (
    tester,
  ) async {
    const original = BdoTownWorkerCapacity(
      availableWorkerCount: 30,
      freeLodgingSlotCount: 0,
      hiredWorkerCount: 30,
      bonusLodgingSlotCount: 14,
      pearlLodgingPurchasedCount: 8,
      loyaltyLodgingPurchasedCount: 2,
      otherBonusLodgingSlotCount: 4,
    );
    final results = <Map<String, BdoTownWorkerCapacity>?>[];
    await _open(tester, initial: {'1101': original}, onResult: results.add);
    expect(
      tester.widget<IconButton>(_key('pearl-plus-1101')).onPressed,
      isNull,
    );
    await tester.tap(_key('pearl-minus-1101'));
    await tester.pump();
    await tester.tap(_key('save'));
    await tester.pumpAndSettle();
    final changed = results.single!['1101']!;
    expect(changed.pearlLodgingPurchasedCount, 7);
    expect(changed.loyaltyLodgingPurchasedCount, 2);
    expect(changed.otherBonusLodgingSlotCount, 4);
    expect(changed.hiredWorkerCount, 30);
    expect(changed.freeLodgingSlotCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'legacy review does not guess Pearl and nested Cancel keeps the original',
    (tester) async {
      const original = BdoTownWorkerCapacity(
        availableWorkerCount: 4,
        freeLodgingSlotCount: 6,
        hiredWorkerCount: 4,
        bonusLodgingSlotCount: 9,
      );
      final results = <Map<String, BdoTownWorkerCapacity>?>[];
      await _open(tester, initial: {'1101': original}, onResult: results.add);
      await tester.tap(_key('review-1101'));
      await tester.pumpAndSettle();
      expect(find.text('Shop lodging · Altinova'), findsOneWidget);
      expect(
        find.byTooltip(
          'Enter purchased coupons, not the remaining shop allowance.\nSaving replaces the older unsplit total of 9 bonus beds.',
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('resource-map-shop-lodging-pearl-plus')),
      );
      await tester.pump();
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(_key('review-1101'), findsOneWidget);
      await tester.tap(_key('save'));
      await tester.pumpAndSettle();
      expect(results.single!['1101'], same(original));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmed legacy split and Other edit remain draft until outer Save',
    (tester) async {
      const original = BdoTownWorkerCapacity(
        availableWorkerCount: 4,
        freeLodgingSlotCount: 6,
        hiredWorkerCount: 4,
        bonusLodgingSlotCount: 9,
      );
      final results = <Map<String, BdoTownWorkerCapacity>?>[];
      await _open(tester, initial: {'1101': original}, onResult: results.add);
      await tester.tap(_key('review-1101'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('resource-map-shop-lodging-pearl-plus')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('resource-map-shop-lodging-other')),
        '8',
      );
      await tester.tap(
        find.byKey(const ValueKey('resource-map-shop-lodging-save')),
      );
      await tester.pumpAndSettle();
      expect(results, isEmpty);
      expect(_key('review-1101'), findsNothing);
      expect(tester.widget<Text>(_key('pearl-count-1101')).data, '1');
      await tester.tap(_key('save'));
      await tester.pumpAndSettle();
      final changed = results.single!['1101']!;
      expect(changed.pearlLodgingPurchasedCount, 1);
      expect(changed.otherBonusLodgingSlotCount, 8);
      expect(changed.hiredWorkerCount, 4);
      expect(changed.freeLodgingSlotCount, 6);
      expect(original.hasBonusLodgingBreakdown, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final entry in <String, BdoTownWorkerCapacity>{
    'legacy': const BdoTownWorkerCapacity(
      availableWorkerCount: 4,
      freeLodgingSlotCount: 6,
      hiredWorkerCount: 4,
      bonusLodgingSlotCount: 9,
    ),
    'split': const BdoTownWorkerCapacity(
      availableWorkerCount: 2,
      freeLodgingSlotCount: 21,
      hiredWorkerCount: 2,
      bonusLodgingSlotCount: 999,
      pearlLodgingPurchasedCount: 8,
      loyaltyLodgingPurchasedCount: 2,
      otherBonusLodgingSlotCount: 4,
    ),
  }.entries) {
    testWidgets(
      'saving an unchanged ${entry.key} review preserves the raw entry',
      (tester) async {
        final results = <Map<String, BdoTownWorkerCapacity>?>[];
        await _open(
          tester,
          initial: {'1101': entry.value},
          onResult: results.add,
        );
        await tester.tap(
          _key('${entry.key == 'legacy' ? 'review' : 'details'}-1101'),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('resource-map-shop-lodging-save')),
        );
        await tester.pumpAndSettle();
        expect(results, isEmpty);
        await tester.tap(_key('save'));
        await tester.pumpAndSettle();
        expect(results.single!['1101'], same(entry.value));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'reviewing Other does not clamp untouched out-of-range shop sources',
    (tester) async {
      const original = BdoTownWorkerCapacity(
        availableWorkerCount: 2,
        freeLodgingSlotCount: 13,
        hiredWorkerCount: 2,
        bonusLodgingSlotCount: 14,
        pearlLodgingPurchasedCount: 8,
        loyaltyLodgingPurchasedCount: 2,
        otherBonusLodgingSlotCount: 4,
      );
      final results = <Map<String, BdoTownWorkerCapacity>?>[];
      await _open(tester, initial: {'1101': original}, onResult: results.add);
      await tester.tap(_key('details-1101'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('resource-map-shop-lodging-other')),
        '5',
      );
      await tester.tap(
        find.byKey(const ValueKey('resource-map-shop-lodging-save')),
      );
      await tester.pumpAndSettle();
      await tester.tap(_key('save'));
      await tester.pumpAndSettle();
      final changed = results.single!['1101']!;
      expect(changed.pearlLodgingPurchasedCount, 8);
      expect(changed.loyaltyLodgingPurchasedCount, 2);
      expect(changed.otherBonusLodgingSlotCount, 5);
      expect(changed.hiredWorkerCount, 2);
      expect(tester.takeException(), isNull);
    },
  );

  for (final saveDraft in [false, true]) {
    testWidgets(
      'existing-worker edits share the outer ${saveDraft ? 'Save' : 'Cancel'} transaction',
      (tester) async {
        final results = <Map<String, BdoTownWorkerCapacity>?>[];
        Map<String, BdoTownWorkerCapacity>? received;
        await _open(
          tester,
          onResult: results.add,
          onWorkers: (current) async {
            received = current;
            return {
              ...current,
              '1853': const BdoTownWorkerCapacity(
                availableWorkerCount: 12,
                freeLodgingSlotCount: 0,
                hiredWorkerCount: 12,
              ),
            };
          },
        );
        await tester.tap(_key('pearl-plus-1101'));
        await tester.pump();
        await tester.tap(_key('workers'));
        await tester.pumpAndSettle();
        expect(received!['1101']!.pearlLodgingPurchasedCount, 1);
        expect(results, isEmpty);
        await tester.tap(_key(saveDraft ? 'save' : 'cancel'));
        await tester.pumpAndSettle();
        if (saveDraft) {
          expect(results.single!['1101']!.pearlLodgingPurchasedCount, 1);
          expect(results.single!['1853']!.hiredWorkerCount, 12);
        } else {
          expect(results, [null]);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'worker editor cancellation preserves draft and gates duplicate opens',
    (tester) async {
      final pending = Completer<Map<String, BdoTownWorkerCapacity>?>();
      var calls = 0;
      final results = <Map<String, BdoTownWorkerCapacity>?>[];
      await _open(
        tester,
        onResult: results.add,
        onWorkers: (current) {
          calls++;
          return pending.future;
        },
      );
      await tester.tap(_key('pearl-plus-1101'));
      await tester.pump();
      final open = tester.widget<TextButton>(_key('workers')).onPressed!;
      open();
      open();
      await tester.pump();
      expect(calls, 1);
      expect(tester.widget<FilledButton>(_key('save')).onPressed, isNull);
      pending.complete(null);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(_key('pearl-count-1101')).data, '1');
      await tester.tap(_key('save'));
      await tester.pumpAndSettle();
      expect(results.single!['1101']!.pearlLodgingPurchasedCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('header drags, while close remains a separate action', (
    tester,
  ) async {
    await _open(tester);
    final title = find.text('Extra lodging');
    final before = tester.getCenter(title);
    await tester.drag(_key('drag-handle'), const Offset(70, 32));
    await tester.pump();
    final after = tester.getCenter(title);
    expect(after.dx, greaterThan(before.dx));
    expect(after.dy, greaterThan(before.dy));
    expect(_key('close').hitTestable(), findsOneWidget);
    await tester.tap(_key('close'));
    await tester.pumpAndSettle();
    expect(_key('dialog'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final chrome in [
    ResourceMapChromeThemeData.sakuraCartographer,
    ResourceMapChromeThemeData.illuminatedAtlas,
    ResourceMapChromeThemeData.fieldAtlas,
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '${chrome.variant.name} at ${scale * 100}% stays readable opaque and bounded',
        (tester) async {
          await tester.runAsync(loadMapMenuCaptureFonts);
          await _open(
            tester,
            chrome: chrome.withUiOpacity(0),
            scale: scale,
            onWorkers: (_) async => null,
          );
          final dialog = tester.widget<AlertDialog>(_key('dialog'));
          expect(dialog.backgroundColor!.a, 1);
          expect(
            tester.widget<Text>(find.text('Altinova')).style!.color,
            chrome.ink,
          );
          final rect = tester.getRect(
            find
                .descendant(of: _key('dialog'), matching: find.byType(Material))
                .first,
          );
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(1200));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(752));
          expect(_key('save').hitTestable(), findsOneWidget);
          expect(_key('workers').hitTestable(), findsOneWidget);
          for (final townId in ['1101', '1380', '1834']) {
            expect(_key('row-$townId').hitTestable(), findsOneWidget);
          }
          await captureMapMenu(
            tester,
            boundary: find.byKey(const ValueKey('town-lodging-capture')),
            name:
                'town-lodging-${chrome.variant.name}-text${(scale * 100).round()}',
          );
          final longTownName = find.text("Nopsae's Byeot County");
          await tester.scrollUntilVisible(
            longTownName,
            230,
            scrollable: find.byType(Scrollable),
          );
          await Scrollable.ensureVisible(
            tester.element(longTownName),
            alignment: .5,
          );
          await tester.pumpAndSettle();
          expect(longTownName.hitTestable(), findsOneWidget);
          final townRect = tester.getRect(longTownName);
          final listRect = tester.getRect(_key('list'));
          expect(townRect.top, greaterThanOrEqualTo(listRect.top));
          expect(townRect.bottom, lessThanOrEqualTo(listRect.bottom));
          expect(find.byType(Scrollbar), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Future<void> _open(
  WidgetTester tester, {
  Map<String, BdoTownWorkerCapacity> initial = const {},
  Map<String, int>? knownSlots,
  ValueChanged<Map<String, BdoTownWorkerCapacity>?>? onResult,
  TownExistingWorkerEditor? onWorkers,
  ResourceMapChromeThemeData chrome =
      ResourceMapChromeThemeData.sakuraCartographer,
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 752));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: chrome.brightness,
        useMaterial3: true,
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: const Size.square(32),
            padding: const EdgeInsets.all(5),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
      builder: (context, child) => RepaintBoundary(
        key: const ValueKey('town-lodging-capture'),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: const Size(1200, 752),
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
      ),
      home: ResourceMapChromeTheme(
        data: chrome,
        child: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  final result =
                      await showDialog<Map<String, BdoTownWorkerCapacity>>(
                        context: context,
                        builder: (context) => TownShopLodgingDialog(
                          initialValues: initial,
                          knownSlotCountsByTownNodeId:
                              knownSlots ??
                              {
                                for (final town
                                    in WorkerLodgingShopCatalog.towns)
                                  town.townNodeId: 1,
                              },
                          onOpenExistingWorkers: onWorkers,
                        ),
                      );
                  onResult?.call(result);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
