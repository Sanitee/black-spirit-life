import 'package:bdo_map_core/src/widgets/draggable_dialog_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('drag handle moves and clamps a modal surface to the viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: _SurfaceHarness()));

    final surface = find.byKey(const ValueKey<String>('test-surface'));
    final handle = find.byKey(const ValueKey<String>('test-drag-handle'));
    final initial = tester.getRect(surface);

    await tester.drag(handle, const Offset(120, 75));
    await tester.pump();
    final moved = tester.getRect(surface);

    expect(moved.left, closeTo(initial.left + 120, 1));
    expect(moved.top, closeTo(initial.top + 75, 1));

    await tester.drag(handle, const Offset(3000, 3000));
    await tester.pump();
    final clamped = tester.getRect(surface);
    expect(clamped.right, lessThanOrEqualTo(800));
    expect(clamped.bottom, lessThanOrEqualTo(600));
  });

  testWidgets('changing dialog identity resets the position to center', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: _SurfaceHarness()));
    final surface = find.byKey(const ValueKey<String>('test-surface'));
    final handle = find.byKey(const ValueKey<String>('test-drag-handle'));
    final initial = tester.getRect(surface);

    await tester.drag(handle, const Offset(-100, -70));
    await tester.pump();
    expect(tester.getRect(surface).topLeft, isNot(initial.topLeft));

    await tester.tap(find.byKey(const ValueKey<String>('change-identity')));
    await tester.pump();
    expect(tester.getRect(surface), initial);
  });

  testWidgets(
    'anchored flyout follows its anchor until moved then resets by identity',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(home: _PositionedSurfaceHarness()),
      );
      final surface = find.byKey(
        const ValueKey<String>('positioned-test-surface'),
      );
      final handle = find.byKey(
        const ValueKey<String>('positioned-test-handle'),
      );
      expect(tester.getTopLeft(surface), const Offset(120, 90));

      await tester.tap(
        find.byKey(const ValueKey<String>('move-anchor-without-drag')),
      );
      await tester.pump();
      expect(tester.getTopLeft(surface), const Offset(170, 120));

      await tester.drag(handle, const Offset(80, 45));
      await tester.pump();
      expect(tester.getTopLeft(surface), const Offset(250, 165));
      expect(find.text('Moved'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('move-anchor-without-drag')),
      );
      await tester.pump();
      expect(tester.getTopLeft(surface), const Offset(250, 165));

      await tester.tap(
        find.byKey(const ValueKey<String>('change-positioned-identity')),
      );
      await tester.pump();
      expect(tester.getTopLeft(surface), const Offset(220, 150));
      expect(find.text('Anchored'), findsOneWidget);
    },
  );

  testWidgets('alert-dialog controls remain interactive after title drag', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => DraggableAlertDialog(
                      identity: 'interactive-test',
                      estimatedSize: const Size(360, 250),
                      title: const Text('Movable settings'),
                      content: const TextField(
                        key: ValueKey<String>('dialog-field'),
                      ),
                      actions: <Widget>[
                        FilledButton(
                          onPressed: () {
                            saved = 'saved';
                            Navigator.of(context).pop();
                          },
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final title = find.text('Movable settings');
    final before = tester.getCenter(title);
    await tester.drag(title, const Offset(90, 45));
    await tester.pump();
    expect(tester.getCenter(title).dx, greaterThan(before.dx + 20));

    await tester.enterText(
      find.byKey(const ValueKey<String>('dialog-field')),
      'still interactive',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, 'saved');
    expect(find.text('Movable settings'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _SurfaceHarness extends StatefulWidget {
  const _SurfaceHarness();

  @override
  State<_SurfaceHarness> createState() => _SurfaceHarnessState();
}

class _SurfaceHarnessState extends State<_SurfaceHarness> {
  int _identity = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          DraggableDialogSurface(
            identity: _identity,
            estimatedSize: const Size(240, 160),
            builder: (context, alignment) => Align(
              alignment: alignment,
              child: SizedBox(
                key: const ValueKey<String>('test-surface'),
                width: 240,
                height: 160,
                child: Material(
                  child: Column(
                    children: <Widget>[
                      DraggableDialogDragHandle(
                        key: const ValueKey<String>('test-drag-handle'),
                        child: const SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: Text('Drag me'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: TextButton(
              key: const ValueKey<String>('change-identity'),
              onPressed: () => setState(() => _identity += 1),
              child: const Text('Change identity'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionedSurfaceHarness extends StatefulWidget {
  const _PositionedSurfaceHarness();

  @override
  State<_PositionedSurfaceHarness> createState() =>
      _PositionedSurfaceHarnessState();
}

class _PositionedSurfaceHarnessState extends State<_PositionedSurfaceHarness> {
  int _identity = 0;
  Offset _anchor = const Offset(120, 90);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          DraggablePositionedSurface(
            identity: _identity,
            viewportSize: const Size(800, 600),
            initialPosition: _anchor,
            estimatedSize: const Size(220, 160),
            builder: (context, position, manuallyMoved) => Positioned(
              key: const ValueKey<String>('positioned-test-surface'),
              left: position.dx,
              top: position.dy,
              width: 220,
              height: 160,
              child: Material(
                child: DraggableDialogDragHandle(
                  key: const ValueKey<String>('positioned-test-handle'),
                  child: Text(manuallyMoved ? 'Moved' : 'Anchored'),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Row(
              children: <Widget>[
                TextButton(
                  key: const ValueKey<String>('move-anchor-without-drag'),
                  onPressed: () =>
                      setState(() => _anchor += const Offset(50, 30)),
                  child: const Text('Move anchor'),
                ),
                TextButton(
                  key: const ValueKey<String>('change-positioned-identity'),
                  onPressed: () => setState(() => _identity += 1),
                  child: const Text('New identity'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
