import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'coordinator keeps one edge-safe nonmodal popover and Escape dismisses top',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(320, 240);
      addTearDown(tester.view.reset);
      var outsideActivations = 0;

      await tester.pumpWidget(
        AppOverlayCoordinatorHost(
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                children: <Widget>[
                  Positioned(
                    left: 2,
                    top: 2,
                    child: _TestPopover(
                      id: 'first',
                      anchorKey: const ValueKey<String>('first-anchor'),
                      contentKey: const ValueKey<String>('first-content'),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: _TestPopover(
                      id: 'second',
                      anchorKey: const ValueKey<String>('second-anchor'),
                      contentKey: const ValueKey<String>('second-content'),
                    ),
                  ),
                  Positioned(
                    left: 2,
                    bottom: 2,
                    child: SizedBox(
                      width: 120,
                      child: TextButton(
                        key: const ValueKey<String>('outside-action'),
                        onPressed: () => outsideActivations += 1,
                        child: const Text('Outside action'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('first-anchor')));
      await tester.pump();
      final first = find.byKey(const ValueKey<String>('first-content'));
      expect(first, findsOneWidget);
      _expectSafe(tester.getRect(first));

      await tester.tap(find.byKey(const ValueKey<String>('second-anchor')));
      await tester.pump();
      expect(first, findsNothing);
      final second = find.byKey(const ValueKey<String>('second-content'));
      expect(second, findsOneWidget);
      _expectSafe(tester.getRect(second));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(second, findsNothing);

      await tester.tap(find.byKey(const ValueKey<String>('first-anchor')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('outside-action')));
      await tester.pump();
      expect(outsideActivations, 1);
      expect(first, findsNothing);

      await tester.tap(find.byKey(const ValueKey<String>('first-anchor')));
      await tester.pump();
      expect(first, findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'beside annotation ignores Escape and consumes its outside-dismiss click',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(500, 300);
      addTearDown(tester.view.reset);
      var outsideActivations = 0;

      await tester.pumpWidget(
        AppOverlayCoordinatorHost(
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                children: <Widget>[
                  Positioned(
                    right: 12,
                    top: 110,
                    child: _TestPopover(
                      id: 'annotation',
                      anchorKey: const ValueKey<String>('annotation-anchor'),
                      contentKey: const ValueKey<String>('annotation-content'),
                      placement: AnchoredPopoverPlacement.beside,
                      dismissOnEscape: false,
                      consumeOutsideTap: true,
                    ),
                  ),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: TextButton(
                      key: const ValueKey<String>('covered-action'),
                      onPressed: () => outsideActivations += 1,
                      child: const Text('Covered action'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final anchor = find.byKey(const ValueKey<String>('annotation-anchor'));
      await tester.tap(anchor);
      await tester.pump();
      final content = find.byKey(const ValueKey<String>('annotation-content'));
      expect(content, findsOneWidget);
      final anchorRect = tester.getRect(anchor);
      final contentRect = tester.getRect(content);
      expect(
        anchorRect.center.dx - contentRect.right,
        6,
        reason: 'anchor=$anchorRect content=$contentRect',
      );
      expect(
        contentRect.center.dy,
        anchorRect.center.dy,
        reason:
            'anchor=$anchorRect content=$contentRect '
            'region=${tester.getRect(find.byKey(const ValueKey<String>('popover-region:annotation')))}',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(content, findsOneWidget);

      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey<String>('covered-action'))),
      );
      await tester.pump();
      expect(content, findsNothing);
      expect(outsideActivations, 0);

      await tester.tap(anchor);
      await tester.pump();
      await tester.tap(
        find.descendant(of: content, matching: find.text('Close')),
      );
      await tester.pump();
      expect(content, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'beside popover can use the safe viewport height for scrollable content',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(420, 240);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        AppOverlayCoordinatorHost(
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.centerLeft,
                child: AnchoredPopover(
                  overlayId: 'tall-beside',
                  preferredWidth: 190,
                  maximumHeight: 500,
                  placement: AnchoredPopoverPlacement.beside,
                  anchorBuilder: (context, toggle, isShowing) => TextButton(
                    key: const ValueKey<String>('tall-anchor'),
                    onPressed: toggle,
                    child: const Text('Open'),
                  ),
                  popoverBuilder: (context, close) => SingleChildScrollView(
                    key: const ValueKey<String>('tall-scroll'),
                    child: const SizedBox(
                      height: 560,
                      child: ColoredBox(color: Colors.black),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('tall-anchor')));
      await tester.pump();
      final popover = find.byKey(const ValueKey<String>('popover:tall-beside'));
      expect(popover, findsOneWidget);
      final rect = tester.getRect(popover);
      expect(rect.top, 12);
      expect(rect.bottom, 228);

      final scrollable = find.descendant(
        of: find.byKey(const ValueKey<String>('tall-scroll')),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      expect(
        tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
        greaterThan(0),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opt-in drag region moves and clamps without stealing body gestures',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(520, 360);
      addTearDown(tester.view.reset);
      var actionCount = 0;

      await tester.pumpWidget(
        AppOverlayCoordinatorHost(
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                children: <Widget>[
                  Positioned(
                    left: 160,
                    top: 30,
                    child: _DraggableTestPopover(
                      id: 'draggable',
                      onAction: () => actionCount += 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('draggable-anchor')));
      await tester.pump();
      final popover = find.byKey(const ValueKey<String>('popover:draggable'));
      final handle = find.byKey(const ValueKey<String>('draggable-handle'));
      final body = find.byKey(const ValueKey<String>('draggable-scroll'));
      expect(popover, findsOneWidget);
      expect(handle, findsOneWidget);

      final moveRegion = tester.widget<MouseRegion>(
        find.descendant(of: handle, matching: find.byType(MouseRegion)),
      );
      expect(moveRegion.cursor, SystemMouseCursors.move);

      final initialRect = tester.getRect(popover);
      await tester.drag(handle, const Offset(60, 36));
      await tester.pump();
      final movedRect = tester.getRect(popover);
      expect(movedRect.left, closeTo(initialRect.left + 60, 0.01));
      expect(movedRect.top, closeTo(initialRect.top + 36, 0.01));

      await tester.tap(find.byKey(const ValueKey<String>('draggable-action')));
      await tester.pump();
      expect(actionCount, 1);
      expect(tester.getRect(popover), movedRect);

      final scrollable = find.descendant(
        of: body,
        matching: find.byType(Scrollable),
      );
      final scrollState = tester.state<ScrollableState>(scrollable);
      expect(scrollState.position.pixels, 0);
      await tester.drag(body, const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(scrollState.position.pixels, greaterThan(0));
      expect(tester.getRect(popover), movedRect);

      await tester.drag(handle, const Offset(1000, 1000));
      await tester.pump();
      final bottomRight = tester.getRect(popover);
      expect(bottomRight.right, lessThanOrEqualTo(508));
      expect(bottomRight.bottom, lessThanOrEqualTo(348));

      await tester.drag(handle, const Offset(-1000, -1000));
      await tester.pump();
      final topLeft = tester.getRect(popover);
      expect(topLeft.left, greaterThanOrEqualTo(12));
      expect(topLeft.top, greaterThanOrEqualTo(12));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manual position resets on reopen and overlay ID change', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(520, 360);
    addTearDown(tester.view.reset);
    var overlayId = 'drag-reset-one';
    late StateSetter rebuild;

    await tester.pumpWidget(
      AppOverlayCoordinatorHost(
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return Stack(
                  children: <Widget>[
                    Positioned(
                      left: 160,
                      top: 30,
                      child: _DraggableTestPopover(
                        id: overlayId,
                        onAction: () {},
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    final anchor = find.byKey(const ValueKey<String>('draggable-anchor'));
    final handle = find.byKey(const ValueKey<String>('draggable-handle'));
    await tester.tap(anchor);
    await tester.pump();
    var popover = find.byKey(const ValueKey<String>('popover:drag-reset-one'));
    final anchoredRect = tester.getRect(popover);

    await tester.drag(handle, const Offset(70, 40));
    await tester.pump();
    expect(tester.getRect(popover), isNot(anchoredRect));

    rebuild(() => overlayId = 'drag-reset-two');
    await tester.pump();
    popover = find.byKey(const ValueKey<String>('popover:drag-reset-two'));
    expect(tester.getRect(popover), anchoredRect);

    await tester.drag(handle, const Offset(70, 40));
    await tester.pump();
    expect(tester.getRect(popover), isNot(anchoredRect));
    await tester.tap(find.byKey(const ValueKey<String>('draggable-close')));
    await tester.pump();
    expect(popover, findsNothing);

    await tester.tap(anchor);
    await tester.pump();
    popover = find.byKey(const ValueKey<String>('popover:drag-reset-two'));
    expect(tester.getRect(popover), anchoredRect);
    expect(tester.takeException(), isNull);
  });
}

class _DraggableTestPopover extends StatelessWidget {
  const _DraggableTestPopover({required this.id, required this.onAction});

  final String id;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => AnchoredPopover(
    overlayId: id,
    preferredWidth: 220,
    maximumHeight: 190,
    alignEnd: false,
    anchorBuilder: (context, toggle, isShowing) => SizedBox(
      width: 100,
      height: 40,
      child: TextButton(
        key: const ValueKey<String>('draggable-anchor'),
        onPressed: toggle,
        child: Text(isShowing ? 'Open' : 'Closed'),
      ),
    ),
    popoverBuilder: (context, close) => SizedBox(
      height: 190,
      child: ColoredBox(
        color: Colors.black,
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 42,
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: AnchoredPopoverDragRegion(
                      key: ValueKey<String>('draggable-handle'),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Move this panel'),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('draggable-close'),
                    onPressed: close,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey<String>('draggable-scroll'),
                child: Column(
                  children: <Widget>[
                    TextButton(
                      key: const ValueKey<String>('draggable-action'),
                      onPressed: onAction,
                      child: const Text('Action'),
                    ),
                    const SizedBox(height: 300),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TestPopover extends StatelessWidget {
  const _TestPopover({
    required this.id,
    required this.anchorKey,
    required this.contentKey,
    this.placement = AnchoredPopoverPlacement.vertical,
    this.dismissOnEscape = true,
    this.consumeOutsideTap = false,
  });

  final String id;
  final Key anchorKey;
  final Key contentKey;
  final AnchoredPopoverPlacement placement;
  final bool dismissOnEscape;
  final bool consumeOutsideTap;

  @override
  Widget build(BuildContext context) => AnchoredPopover(
    overlayId: id,
    preferredWidth: 180,
    maximumHeight: 100,
    placement: placement,
    dismissOnEscape: dismissOnEscape,
    consumeOutsideTap: consumeOutsideTap,
    anchorBuilder: (context, toggle, isShowing) => SizedBox(
      width: 140,
      height: 56,
      child: TextButton(
        key: anchorKey,
        onPressed: toggle,
        child: Text('$id ${isShowing ? 'open' : 'closed'}'),
      ),
    ),
    popoverBuilder: (context, close) => SizedBox(
      key: contentKey,
      height: 100,
      child: ColoredBox(
        color: Colors.black,
        child: Align(
          alignment: Alignment.bottomRight,
          child: TextButton(onPressed: close, child: const Text('Close')),
        ),
      ),
    ),
  );
}

void _expectSafe(Rect rect) {
  expect(rect.left, greaterThanOrEqualTo(12));
  expect(rect.top, greaterThanOrEqualTo(12));
  expect(rect.right, lessThanOrEqualTo(308));
  expect(rect.bottom, lessThanOrEqualTo(228));
}
