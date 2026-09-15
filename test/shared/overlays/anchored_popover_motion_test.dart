import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _anchor = ValueKey('motion-popover-anchor');
const _content = ValueKey('motion-popover-content');
const _entrance = ValueKey('popover-entrance:motion-test');

void main() {
  testWidgets('popover fades without shifting geometry or delaying actions', (
    tester,
  ) async {
    var count = 0;
    await tester.pumpWidget(_host(onAction: () => count++));
    await tester.tap(find.byKey(_anchor));
    await tester.pump();
    final rect = tester.getRect(find.byKey(_content));
    expect(_opacity(tester), closeTo(.84, .001));
    await tester.tap(find.text('Apply'));
    expect(count, 1);
    await tester.pump(const Duration(milliseconds: 70));
    expect(_opacity(tester), inExclusiveRange(.84, 1));
    expect(tester.getRect(find.byKey(_content)), rect);
    await tester.pump(const Duration(milliseconds: 70));
    expect(_opacity(tester), 1);
    expect(tester.getRect(find.byKey(_content)), rect);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(_content), findsNothing);
    await tester.tap(find.byKey(_anchor));
    await tester.pump();
    expect(_opacity(tester), closeTo(.84, .001));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keyboard focus works during entrance and close leaves no ghost',
    (tester) async {
      var count = 0;
      await tester.pumpWidget(_host(onAction: () => count++));
      await tester.tap(find.byKey(_anchor));
      await tester.pump();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(count, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(_content), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(count, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('reduced motion has no entrance animation and retains input', (
    tester,
  ) async {
    var count = 0;
    await tester.pumpWidget(_host(reduced: true, onAction: () => count++));
    await tester.tap(find.byKey(_anchor));
    await tester.pump();
    expect(find.byKey(_entrance), findsNothing);
    expect(find.byKey(_content), findsOneWidget);
    await tester.tap(find.text('Apply'));
    expect(count, 1);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(find.byKey(_content), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .descendant(of: find.byKey(_entrance), matching: find.byType(Opacity))
          .first,
    )
    .opacity;

Widget _host({required VoidCallback onAction, bool reduced = false}) =>
    AppOverlayCoordinatorHost(
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: AnchoredPopover(
              overlayId: 'motion-test',
              preferredWidth: 240,
              anchorBuilder: (context, toggle, showing) => TextButton(
                key: _anchor,
                onPressed: toggle,
                child: const Text('Open'),
              ),
              popoverBuilder: (context, close) => Material(
                key: _content,
                child: SizedBox(
                  height: 100,
                  child: TextButton(
                    autofocus: true,
                    onPressed: onAction,
                    child: const Text('Apply'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
