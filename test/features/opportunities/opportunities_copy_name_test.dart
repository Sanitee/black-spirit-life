import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_item_actions.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'name hover has no highlight or tooltip; keyboard focus remains',
    (tester) async {
      const captureKey = ValueKey('copy-name-capture');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(hoverColor: Colors.red, focusColor: Colors.green),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: captureKey,
                child: const Material(
                  color: Color(0xff13283b),
                  child: SizedBox(
                    width: 360,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: OpportunityCopyName(
                        name: 'Sugar',
                        style: TextStyle(color: Colors.white, fontSize: 17),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(captureKey),
      );
      Future<List<int>> pixels() async => (await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return data!.buffer.asUint8List().toList();
        } finally {
          image.dispose();
        }
      }))!;

      final idle = await pixels();
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Sugar')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(await pixels(), orderedEquals(idle));
      expect(find.byType(Tooltip), findsNothing);
      expect(find.text('Copy name'), findsNothing);

      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(Focus.of(tester.element(find.text('Sugar'))).hasFocus, isTrue);
      expect(await pixels(), isNot(orderedEquals(idle)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('copy name consumes only the text, body still opens recipe', (
    tester,
  ) async {
    final copied = <String>[];
    var opened = 0;
    await tester.pumpWidget(
      OpportunityItemActionsScope(
        externalActions: PlannerExternalActions(
          openRecipeBook: (_) {},
          copyName: (name) async => copied.add(name),
          checkPrices: (_) async =>
              throw StateError('No price requests in a copy test'),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: InkWell(
                  onTap: () => opened++,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OpportunityCopyName(
                        name: 'Mineral Water',
                        displayLabel: '20× Mineral Water',
                      ),
                      SizedBox(height: 16),
                      Text('Cost 600'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final title = find.byKey(
      const ValueKey('opportunity-copy-name:Mineral Water'),
    );
    expect(tester.getSize(title).width, lessThan(300));
    await tester.tapAt(tester.getTopRight(title) + const Offset(-4, 6));
    await tester.pump();
    expect(copied, ['Mineral Water']);
    expect(opened, 0);
    await tester.tapAt(tester.getTopRight(title) + const Offset(30, 6));
    await tester.pump();
    expect(copied, ['Mineral Water']);
    expect(opened, 1);
    Focus.of(tester.element(find.text('20× Mineral Water'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(copied, ['Mineral Water', 'Mineral Water']);
    expect(opened, 1);
    await tester.tap(find.text('Cost 600'));
    expect(opened, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy name works without a recipe and uses exact native text', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OpportunityCopyName(
            name: "Fairy's Breath",
            displayLabel: "50× Fairy's Breath",
          ),
        ),
      ),
    );
    await tester.tap(find.text("50× Fairy's Breath"));
    await tester.pump();
    expect(copied, "Fairy's Breath");
    expect(find.text("Copied Fairy's Breath"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clipboard failure is visible and does not open a recipe', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          throw PlatformException(code: 'clipboard_busy');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: OpportunityCopyName(name: 'Salt')),
      ),
    );
    await tester.tap(find.text('Salt'));
    await tester.pump();
    expect(find.text('Could not copy the name. Try again.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
