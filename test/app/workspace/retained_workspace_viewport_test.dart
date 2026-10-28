import 'package:bdo_craft_planner_flutter/app/workspace/retained_workspace_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hidden viewport ignores resize but catches up before reveal', (
    tester,
  ) async {
    final key = GlobalKey<_ProbeState>();
    final probe = _Probe(key: key);
    var hidden = false;
    var viewport = const Size(1200, 752);
    var scale = 1.0;
    Future<void> pump() => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(
            size: viewport,
            textScaler: TextScaler.linear(scale),
          ),
          child: Center(
            child: SizedBox.fromSize(
              size: viewport,
              child: RetainedWorkspaceViewport(offstage: hidden, child: probe),
            ),
          ),
        ),
      ),
    );
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump();
    final retained = key.currentState!;
    retained.counter = 7;
    hidden = true;
    await pump();
    final builds = retained.builds;
    final layouts = retained.layouts;
    for (var i = 0; i < 12; i++) {
      viewport = Size(1250 + i * 10, 780 + i * 5);
      await pump();
    }
    scale = 1.5;
    await pump();
    expect(retained.builds, builds);
    expect(retained.layouts, layouts);
    expect(retained.mediaSize, const Size(1200, 752));
    expect(retained.layoutSize, const Size(1200, 752));
    expect(find.byType(_Probe), findsNothing);
    expect(find.byType(_Probe, skipOffstage: false), findsOneWidget);
    hidden = false;
    await pump();
    expect(key.currentState, same(retained));
    expect(retained.counter, 7);
    expect(retained.mediaSize, viewport);
    expect(retained.layoutSize, viewport);
    expect(retained.scale, 1.5);
    expect(retained.layouts, layouts + 1);
    expect(find.byType(_Probe), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initially hidden child prewarms and accepts data updates', (
    tester,
  ) async {
    final key = GlobalKey<_ProbeState>();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.shrink(),
      ),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RetainedWorkspaceViewport(
          offstage: true,
          child: _Probe(key: key),
        ),
      ),
    );
    final state = key.currentState!;
    expect(state.layouts, 1);
    state.updateCounter();
    await tester.pump();
    expect(state.counter, 1);
    expect(state.builds, 2);
    expect(tester.takeException(), isNull);
  });
}

class _Probe extends StatefulWidget {
  const _Probe({super.key});
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int builds = 0;
  int layouts = 0;
  int counter = 0;
  Size? mediaSize;
  Size? layoutSize;
  double? scale;

  void updateCounter() => setState(() => counter++);

  @override
  Widget build(BuildContext context) {
    builds++;
    mediaSize = MediaQuery.maybeSizeOf(context);
    scale = MediaQuery.maybeTextScalerOf(context)?.scale(1);
    return LayoutBuilder(
      builder: (_, constraints) {
        layouts++;
        layoutSize = constraints.biggest;
        return Text('$counter');
      },
    );
  }
}
