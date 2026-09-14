import 'dart:async';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/gather_checklist_quantity_row.dart';
import 'package:bdo_map_core/src/widgets/resource_map_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'compact quantity row records and undoes at text scale $scale',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 752));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final pending = Completer<BdoGatherChecklistReceipt>();
        final amounts = <double>[];
        var undos = 0;
        await tester.pumpWidget(
          _host(
            scale: scale,
            onRecord: (_, amount) {
              amounts.add(amount);
              return pending.future;
            },
          ),
        );
        expect(find.text('Needed'), findsOneWidget);
        expect(find.text('Owned'), findsOneWidget);
        expect(find.text('Remaining'), findsOneWidget);
        expect(find.text('13'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('gather-record-open:herb')));
        await tester.pump();
        await tester.enterText(
          find.byKey(const ValueKey('gather-record-amount:herb')),
          '4.5',
        );
        await tester.tap(find.byKey(const ValueKey('gather-record-save:herb')));
        await tester.pump();
        expect(amounts, [4.5]);
        expect(
          tester
              .widget<TextButton>(
                find.byKey(const ValueKey('gather-record-save:herb')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '4.5',
        );
        pending.complete(BdoGatherChecklistReceipt(undo: () async => undos++));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        await tester.tap(find.byKey(const ValueKey('gather-record-undo:herb')));
        await tester.pumpAndSettle();
        expect(undos, 1);
        expect(
          find.byKey(const ValueKey('gather-record-undo:herb')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('invalid input never writes; failed save preserves draft', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(
        onRecord: (_, amount) async {
          calls++;
          throw StateError('Disk unavailable');
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('gather-record-open:herb')));
    await tester.pump();
    final field = find.byKey(const ValueKey('gather-record-amount:herb'));
    for (final invalid in ['0', '-1', 'NaN', 'text']) {
      await tester.enterText(field, invalid);
      await tester.tap(find.byKey(const ValueKey('gather-record-save:herb')));
      await tester.pump();
      expect(calls, 0);
    }
    await tester.enterText(field, '7');
    await tester.tap(find.byKey(const ValueKey('gather-record-save:herb')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Disk unavailable'), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, '7');
    expect(find.byKey(const ValueKey('gather-record-undo:herb')), findsNothing);
  });

  testWidgets('unknown exact identity has no record control', (tester) async {
    await tester.pumpWidget(
      _host(
        quantity: const BdoGatherChecklistQuantity(),
        onRecord: (_, _) => throw StateError('Must not write'),
      ),
    );
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('Record gathered'), findsNothing);
  });
}

Widget _host({
  required BdoRecordGathered onRecord,
  double scale = 1,
  BdoGatherChecklistQuantity quantity = const BdoGatherChecklistQuantity(
    needed: 20,
    owned: 7,
    canRecord: true,
  ),
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: ResourceMapChromeTheme(
      data: ResourceMapChromeThemeData.glassDock,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 286,
            child: ResourceMapPill(
              child: GatherChecklistQuantityRow(
                resourceId: 'herb',
                quantity: quantity,
                onRecord: onRecord,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Sunrise Herb'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
