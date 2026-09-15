import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/ui/buff_picker.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;

  setUpAll(() async => catalog = await Catalog.load());

  Future<void> showPicker(
    WidgetTester tester, {
    Set<String> selected = const {},
    ValueChanged<Buff>? onToggle,
  }) async {
    tester.view.physicalSize = const Size(1100, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 900,
              child: BuffPicker(
                catalog: catalog,
                activity: 'gathering',
                selected: selected,
                onToggle: onToggle ?? (_) {},
                onPreset: (_) {},
                onClear: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Energy category ships every catalog tile', (tester) async {
    await showPicker(tester);
    expect(find.byKey(const ValueKey('buff-row-energy')), findsOneWidget);
    final energy = catalog.buffs.where((buff) => buff.category == 'energy');
    expect(energy.length, 18);
    for (final buff in energy) {
      expect(
        find.byKey(ValueKey('buff-icon-${buff.id}')).hitTestable(),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('right-click pins current Lightstone details', (tester) async {
    await showPicker(tester);
    final icon = find.byKey(const ValueKey('buff-icon-buff-yawning-hedgehog'));
    await tester.tap(
      icon,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    final pinned = find.byKey(
      const ValueKey('buff-pinned-card-buff-yawning-hedgehog'),
    );
    expect(pinned, findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(pinned, findsOneWidget);
    expect(
      find.descendant(of: pinned, matching: find.text('Lightstones')),
      findsOneWidget,
    );
    for (final id in ['764011', '764003', '764001', '766101']) {
      expect(
        find.descendant(
          of: pinned,
          matching: find.byKey(ValueKey('buff-component-$id')),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: pinned,
        matching: find.text('Lightstone of Flora: Plains'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: pinned,
        matching: find.text('Lightstone of Flora: Wildlife'),
      ),
      findsOneWidget,
    );
    for (final bonus in const [
      'Gathering Item Drop Rate +10%',
      'Gathering EXP +10%',
      'Gathering Mastery +20',
      'Gathering Speed +1.',
    ]) {
      expect(
        find.descendant(of: pinned, matching: find.text(bonus)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: pinned, matching: find.text('Energy Recovery +1')),
      findsNothing,
    );
    expect(
      find.descendant(of: pinned, matching: find.text('How to get')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: pinned,
        matching: find.textContaining('Equip Flora:'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary click still toggles a selectable buff', (tester) async {
    final calls = <String>[];
    await showPicker(tester, onToggle: (buff) => calls.add(buff.id));
    const id = 'buff-791';
    await tester.tap(find.byKey(const ValueKey('buff-icon-$id')));
    await tester.pump();

    expect(calls, [id]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('buff-pinned-card-$id')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('past event items stay in one collapsed optional section', (
    tester,
  ) async {
    await showPicker(tester);
    final events = catalog.buffs.where((buff) => buff.category == 'events');
    expect(events.length, 17);
    expect(find.byKey(const ValueKey('buff-row-events')), findsOneWidget);
    expect(find.text('Event items you may own'), findsNothing);
    for (final buff in events) {
      expect(find.byKey(ValueKey('buff-icon-${buff.id}')), findsNothing);
    }
    await tester.tap(find.byKey(const ValueKey('buff-row-events')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('event-items-section')), findsOneWidget);
    expect(find.text('Event items you may own'), findsOneWidget);
    for (final buff in events) {
      expect(
        find.byKey(ValueKey('buff-icon-${buff.id}')).hitTestable(),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('instant event Energy items open details without toggling', (
    tester,
  ) async {
    final calls = <String>[];
    await showPicker(tester, onToggle: (buff) => calls.add(buff.id));
    await tester.tap(find.byKey(const ValueKey('buff-row-events')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('buff-icon-buff-752459')).hitTestable(),
    );
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('[Event] Energy Gourd Bottle'), findsOneWidget);
    expect(find.text('+100 Energy instantly'), findsOneWidget);
    expect(find.text('10 min cooldown'), findsOneWidget);
    expect(find.text('How to get'), findsOneWidget);
    expect(find.text('Event reward.'), findsOneWidget);
    expect(find.textContaining('Get:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Energy hover uses formatted effect and acquisition sections', (
    tester,
  ) async {
    await showPicker(tester);
    final buff = catalog.buffs.singleWhere((entry) => entry.id == 'buff-589');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(ValueKey('buff-icon-${buff.id}'))),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));
    final hover = find.byKey(ValueKey('buff-hover-card-${buff.id}'));
    expect(hover, findsOneWidget);
    expect(
      find.descendant(of: hover, matching: find.text('Effects')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: hover, matching: find.text('+50 Energy instantly')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: hover, matching: find.text('10 min cooldown')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: hover, matching: find.text('How to get')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: hover, matching: find.text(buff.obtainSummary)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hover,
        matching: find.textContaining('Right-click for details'),
      ),
      findsNothing,
    );
    expect(find.textContaining('Get:'), findsNothing);
    await mouse.moveTo(tester.getCenter(hover));
    await tester.pump(const Duration(milliseconds: 200));
    expect(hover, findsOneWidget);
    await mouse.removePointer();
    await tester.pump(const Duration(milliseconds: 200));
    expect(hover, findsNothing);
  });

  testWidgets('Energy reference is non-toggleable and opens details', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final buff = catalog.buffs.singleWhere((entry) => entry.id == 'buff-589');
    final calls = <String>[];
    await showPicker(
      tester,
      selected: {buff.id},
      onToggle: (value) => calls.add(value.id),
    );
    final icon = find.byKey(ValueKey('buff-icon-${buff.id}'));
    expect(tester.getSemantics(icon).flagsCollection.isSelected, Tristate.none);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Effects'), findsOneWidget);
    expect(find.text('+50 Energy instantly'), findsOneWidget);
    expect(find.text('10 min cooldown'), findsOneWidget);
    expect(find.text(buff.effectSummary), findsNothing);
    expect(find.text('How to get'), findsOneWidget);
    expect(find.text(buff.obtainSummary), findsOneWidget);
    expect(find.textContaining('Get:'), findsNothing);
    semantics.dispose();
  });
}
