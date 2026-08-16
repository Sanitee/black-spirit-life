import 'package:bdo_craft_planner_flutter/shared/overlays/draggable_overlay_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'dialog surface moves from its explicit handle, clamps, and resets by id',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var actionCount = 0;

      Widget host(String id) => MaterialApp(
        home: Scaffold(
          body: DraggableOverlaySurface(
            overlayId: id,
            child: SizedBox(
              key: const ValueKey<String>('panel'),
              width: 200,
              height: 120,
              child: ColoredBox(
                color: Colors.black,
                child: Column(
                  children: <Widget>[
                    DraggableOverlayDragRegion(
                      child: SizedBox(
                        key: const ValueKey<String>('handle'),
                        width: 200,
                        height: 40,
                        child: const Text('Move'),
                      ),
                    ),
                    TextButton(
                      key: const ValueKey<String>('action'),
                      onPressed: () => actionCount += 1,
                      child: const Text('Action'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(host('first'));
      final initial = tester.getRect(find.byKey(const ValueKey('panel')));
      expect(initial, const Rect.fromLTWH(150, 140, 200, 120));

      await tester.drag(
        find.byKey(const ValueKey('handle')),
        const Offset(24, 18),
      );
      await tester.pump();
      final moved = tester.getRect(find.byKey(const ValueKey('panel')));
      expect(moved.topLeft, initial.topLeft + const Offset(24, 18));

      await tester.tap(find.byKey(const ValueKey('action')));
      expect(actionCount, 1);

      await tester.drag(
        find.byKey(const ValueKey('handle')),
        const Offset(1000, 1000),
      );
      await tester.pump();
      final clamped = tester.getRect(find.byKey(const ValueKey('panel')));
      expect(clamped.right, lessThanOrEqualTo(484));
      expect(clamped.bottom, lessThanOrEqualTo(384));

      await tester.pumpWidget(host('second'));
      await tester.pump();
      expect(tester.getRect(find.byKey(const ValueKey('panel'))), initial);
      expect(tester.takeException(), isNull);
    },
  );
}
