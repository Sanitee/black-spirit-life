import 'dart:io';

import 'package:bdo_craft_planner_flutter/visual/components/app_tooltip.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(
  theme: StandardSpec.theme.materialTheme(),
  home: ThemeSpecScope(
    spec: StandardSpec.theme,
    child: Scaffold(body: Center(child: child)),
  ),
);

Future<void> hover(WidgetTester tester, Finder target) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(seconds: 2));
  addTearDown(mouse.removePointer);
}

void main() {
  for (final message in <String>[
    'Test update available · 2.5 MB patch',
    'Plan ingredients around your character weight',
    'Needed for 1 craft',
    'Total needed for this craft step',
    'Other ingredients can be used.',
    'Cheetah Dragon Blood',
    'Flamingo Blood',
  ]) {
    testWidgets('$message stays semantic, without a hover popup', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          AppTooltip(
            message: message,
            child: const SizedBox(
              key: ValueKey('target'),
              width: 100,
              height: 50,
              child: ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byType(AppTooltip)).getSemanticsData().tooltip,
        message,
      );
      await hover(tester, find.byKey(const ValueKey('target')));
      expect(find.text(message), findsNothing);
      expect(
        tester
            .state<TooltipState>(find.byType(AppTooltip))
            .ensureTooltipVisible(),
        isFalse,
      );
      await tester.longPress(find.byKey(const ValueKey('target')));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(message), findsNothing);
      semantics.dispose();
    });
  }

  testWidgets('semantic exclusion is preserved', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        const AppTooltip(
          message: 'Decorative',
          excludeFromSemantics: true,
          child: Text('Visible'),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.text('Visible')).getSemanticsData().tooltip,
      isEmpty,
    );
    semantics.dispose();
  });

  testWidgets('icon buttons keep accessibility and mouse/keyboard actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var clicks = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      host(
        QuietIconButton(
          tooltip: 'Recalculate',
          icon: const Icon(Icons.calculate),
          focusNode: focus,
          onPressed: () => clicks++,
        ),
      ),
    );
    expect(
      tester
          .getSemantics(find.byType(QuietIconButton))
          .getSemanticsData()
          .tooltip,
      'Recalculate',
    );
    await hover(tester, find.byType(QuietIconButton));
    expect(find.text('Recalculate'), findsNothing);
    await tester.tap(find.byType(QuietIconButton));
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(clicks, 2);
    semantics.dispose();
  });

  testWidgets(
    'shared themed buttons suppress captions without changing bounds',
    (tester) async {
      var clicks = 0;
      await tester.pumpWidget(
        host(
          AppButton.icon(
            icon: const Icon(Icons.calculate),
            semanticLabel: 'Recalculate',
            tooltip: 'Recalculate',
            onPressed: () => clicks++,
          ),
        ),
      );
      final before = tester.getRect(find.byType(AppButton));
      await hover(tester, find.byType(AppButton));
      expect(find.text('Recalculate'), findsNothing);
      expect(tester.getRect(find.byType(AppButton)), before);
      await tester.tap(find.byType(AppButton));
      expect(clicks, 1);
    },
  );

  testWidgets('explicitly approved garden hint still opens', (tester) async {
    await tester.pumpWidget(
      host(
        QuietIconButton(
          tooltip: 'Plant in garden',
          approvedHover: true,
          icon: const Icon(Icons.grass),
          onPressed: () {},
        ),
      ),
    );
    await hover(tester, find.byType(QuietIconButton));
    expect(find.text('Plant in garden'), findsOneWidget);
  });

  for (final entry in <(String, Widget Function(VoidCallback))>[
    (
      'Map zoom',
      (onPressed) => MapQuietIconButton(
        tooltip: 'Map zoom',
        onPressed: onPressed,
        icon: const Icon(Icons.zoom_in),
      ),
    ),
    (
      'Gathering close',
      (onPressed) => GatheringQuietIconButton(
        tooltip: 'Gathering close',
        onPressed: onPressed,
        icon: const Icon(Icons.close),
      ),
    ),
  ]) {
    testWidgets('${entry.$1} stays semantic without package hover text', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var clicks = 0;
      await tester.pumpWidget(host(entry.$2(() => clicks++)));
      final target = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == entry.$1,
      );
      expect(tester.getSemantics(target).getSemanticsData().tooltip, entry.$1);
      await hover(tester, target);
      expect(find.text(entry.$1), findsNothing);
      await tester.tap(target);
      expect(clicks, 1);
      semantics.dispose();
    });
  }

  for (final entry in <(String, Widget)>[
    (
      'Map action',
      const MapQuietTooltip(message: 'Map action', child: Text('Map')),
    ),
    (
      'Gathering action',
      const GatheringQuietTooltip(
        message: 'Gathering action',
        child: Text('Gathering'),
      ),
    ),
  ]) {
    testWidgets('${entry.$1} wrapper keeps semantics without a popup', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(entry.$2));
      final target = find.text(
        entry.$1.startsWith('Map') ? 'Map' : 'Gathering',
      );
      expect(tester.getSemantics(target).getSemanticsData().tooltip, entry.$1);
      await hover(tester, target);
      expect(find.text(entry.$1), findsNothing);
      semantics.dispose();
    });
  }

  testWidgets('approved rich artwork preview obeys pinned-preview visibility', (
    tester,
  ) async {
    Widget reference(bool visible) => host(
      TooltipVisibility(
        visible: visible,
        child: const AppTooltip(
          approvedHover: true,
          richMessage: WidgetSpan(child: Text('Item reference')),
          child: Icon(Icons.inventory),
        ),
      ),
    );
    await tester.pumpWidget(reference(true));
    await hover(tester, find.byIcon(Icons.inventory));
    expect(find.text('Item reference'), findsOneWidget);
    Tooltip.dismissAllToolTips();
    await tester.pumpAndSettle();
    await tester.pumpWidget(reference(false));
    final state = tester.state<TooltipState>(find.byType(AppTooltip));
    expect(state.ensureTooltipVisible(), isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Item reference'), findsNothing);
  });

  test('native app hover hints must be an explicit opt-in', () {
    final bare = RegExp(r'\b(?:Tooltip|IconButton)\(');
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') ||
          file.path.endsWith('app_tooltip.dart')) {
        continue;
      }
      expect(
        bare.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: file.path,
      );
    }
  });

  test('map and Gathering icon buttons use quiet accessibility wrappers', () {
    final bare = RegExp(r'\bIconButton\((?!:)');
    for (final root in <String>[
      'packages/bdo_map_core/lib',
      'packages/bdo_gathering_companion/lib',
    ]) {
      for (final file in Directory(
        root,
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart') ||
            file.path.endsWith('resource_map_chrome_theme.dart') ||
            file.path.endsWith(r'ui\theme.dart') ||
            file.path.endsWith('ui/theme.dart')) {
          continue;
        }
        expect(
          bare.hasMatch(file.readAsStringSync()),
          isFalse,
          reason: file.path,
        );
      }
    }
  });

  test('Fish ordinary action labels do not use browser title popups', () {
    final index = File(
      'packages/bdo_fishing_core/assets/fish_companion/static/index.html',
    ).readAsStringSync();
    final script = File(
      'packages/bdo_fishing_core/assets/fish_companion/static/app.js',
    ).readAsStringSync();
    for (final marker in <String>[
      'data-page="map" title=',
      'data-page="capture" title=',
      'data-page="journal" title=',
      'data-page="stats" title=',
      'class="journal-sale-button" title=',
      'class="journal-edit-button" title=',
      'class="journal-map-button" title=',
      'class="delete-session" title=',
      'settlementToggle.title',
      'regionToggle.title',
    ]) {
      expect('$index\n$script', isNot(contains(marker)), reason: marker);
    }
  });
}
