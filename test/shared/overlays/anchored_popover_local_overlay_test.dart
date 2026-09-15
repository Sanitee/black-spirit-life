import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('popover aligns with its anchor inside an inset tab navigator', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 700);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(32, 72, 32, 24),
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: Stack(
                    children: [
                      Positioned(
                        left: 160,
                        top: 100,
                        child: AnchoredPopover(
                          overlayId: 'inset-tab',
                          preferredWidth: 180,
                          maximumHeight: 100,
                          alignEnd: false,
                          anchorBuilder: (context, toggle, open) => TextButton(
                            key: const ValueKey('inset-anchor'),
                            onPressed: toggle,
                            child: const Text('Open'),
                          ),
                          popoverBuilder: (context, close) => const SizedBox(
                            key: ValueKey('inset-content'),
                            height: 60,
                            child: Text('Item details'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final anchor = find.byKey(const ValueKey('inset-anchor'));
    await tester.tap(anchor);
    await tester.pumpAndSettle();
    final anchorRect = tester.getRect(anchor);
    final contentRect = tester.getRect(
      find.byKey(const ValueKey('inset-content')),
    );
    expect(contentRect.left, closeTo(anchorRect.left, .01));
    expect(contentRect.top, closeTo(anchorRect.bottom + 6, .01));
    expect(tester.takeException(), isNull);
  });
}
