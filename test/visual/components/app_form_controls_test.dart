import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_ornament_painters.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final spec in RetainedThemeRegistry.themes) {
    testWidgets(
      '${spec.displayName} form controls are app-owned and operable',
      (tester) async {
        var toggled = false;
        var selected = true;
        var sliderValue = .5;
        var selectValue = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: spec.materialTheme(),
            home: ThemeSpecScope(
              spec: spec,
              child: StandardVisualScope(
                settings: const StandardVisualSettings(accentHue: 158),
                child: Material(
                  child: StatefulBuilder(
                    builder: (context, setState) => Column(
                      children: <Widget>[
                        const AppTextField(
                          semanticLabel: 'Amount',
                          hintText: '100',
                        ),
                        AppToggle(
                          value: toggled,
                          label: 'Use inventory',
                          onChanged: (value) => setState(() => toggled = value),
                        ),
                        AppChoiceChip(
                          label: 'High',
                          selected: selected,
                          onSelected: (value) =>
                              setState(() => selected = value),
                        ),
                        AppSlider(
                          value: sliderValue,
                          min: 0,
                          max: 1,
                          divisions: 10,
                          label: '${(sliderValue * 100).round()}%',
                          semanticLabel: 'Intensity',
                          onChanged: (value) =>
                              setState(() => sliderValue = value),
                        ),
                        SizedBox(
                          width: 180,
                          child: AppSelect<int>(
                            value: selectValue,
                            items: const [1, 2],
                            labelFor: (value) => '$value',
                            semanticLabel: 'Density',
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => selectValue = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Use inventory'));
        await tester.pump();
        expect(toggled, isTrue);
        expect(find.bySemanticsLabel('Amount'), findsOneWidget);
        expect(find.bySemanticsLabel('Intensity'), findsOneWidget);

        expect(find.byType(ChoiceChip), findsNothing);
        expect(find.byType(Slider), findsNothing);
        expect(find.byType(DropdownButton<int>), findsNothing);
        expect(find.byKey(AppChoiceChip.materialKey), findsOneWidget);
        expect(find.byKey(AppSlider.paintKey), findsOneWidget);
        expect(find.byKey(AppSelect.anchorMaterialKey), findsOneWidget);
        if (spec.isIlluminatedLedger) {
          expect(
            find.descendant(
              of: find.byType(AppChoiceChip),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is CustomPaint &&
                    widget.foregroundPainter is LedgerButtonToolingPainter,
              ),
            ),
            findsNothing,
          );
        }

        await tester.tap(find.text('High'));
        await tester.pump();
        expect(selected, isFalse);

        final sliderRect = tester.getRect(find.byType(AppSlider));
        await tester.tapAt(
          Offset(sliderRect.left + sliderRect.width * .8, sliderRect.center.dy),
        );
        await tester.pump();
        expect(sliderValue, closeTo(.8, .001));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(sliderValue, closeTo(.9, .001));

        await tester.tap(find.byKey(AppSelect.anchorMaterialKey));
        await tester.pumpAndSettle();
        expect(find.byType(MenuItemButton), findsNWidgets(2));
        await tester.tap(find.text('2').last);
        await tester.pumpAndSettle();
        expect(selectValue, 2);
        expect(find.bySemanticsLabel('Density'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'select keeps the complete selected label in its closed control',
    (tester) async {
      const fullLabel = 'Cheetah Dragon Blood';
      await tester.pumpWidget(
        _standardControlHost(
          child: SizedBox(
            width: 260,
            height: 38,
            child: AppSelect<String>(
              value: fullLabel,
              items: const <String>[
                'Wolf Blood',
                'Flamingo Blood',
                'Rhino Blood',
                fullLabel,
              ],
              labelFor: _stringLabel,
              semanticLabel: 'Blood substitute',
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final anchor = find.byKey(AppSelect.anchorMaterialKey);
      final selectedLabel = find.descendant(
        of: anchor,
        matching: find.text(fullLabel),
      );
      expect(selectedLabel, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(selectedLabel).didExceedMaxLines,
        isFalse,
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Blood substitute')).value,
        fullLabel,
      );

      await tester.tap(anchor);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MenuItemButton, fullLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('select menu grows past a compact anchor for complete labels', (
    tester,
  ) async {
    const longLabel = 'Processing - Simple Alchemy';
    await tester.pumpWidget(
      _standardControlHost(
        child: SizedBox(
          width: 190,
          height: 38,
          child: AppSelect<String>(
            value: longLabel,
            items: const <String>['Processing - Grinding', longLabel],
            labelFor: _stringLabel,
            semanticLabel: 'Inventory category',
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final closedLabel = find.descendant(
      of: find.byKey(AppSelect.anchorMaterialKey),
      matching: find.text(longLabel),
    );
    expect(
      tester.renderObject<RenderParagraph>(closedLabel).didExceedMaxLines,
      isFalse,
    );
    await tester.tap(find.byKey(AppSelect.anchorMaterialKey));
    await tester.pumpAndSettle();
    final option = find.widgetWithText(MenuItemButton, longLabel);
    expect(option, findsOneWidget);
    expect(tester.getSize(option).width, greaterThan(190));
    final label = find.descendant(of: option, matching: find.text(longLabel));
    expect(
      tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
      isFalse,
    );
    final rect = tester.getRect(option);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(tester.view.physicalSize.width));
    expect(tester.takeException(), isNull);
  });

  testWidgets('select trigger grows to the longest option when space permits', (
    tester,
  ) async {
    const longLabel = 'Cheetah Dragon Blood from the hunting region';
    await tester.pumpWidget(
      _standardControlHost(
        child: AppSelect<String>(
          value: longLabel,
          items: const <String>['Wolf Blood', longLabel],
          labelFor: _stringLabel,
          semanticLabel: 'Naturally sized blood substitute',
          onChanged: (_) {},
        ),
      ),
    );

    final anchor = find.byKey(AppSelect.anchorMaterialKey);
    expect(tester.getSize(anchor).width, greaterThan(260));
    final selectedLabel = find.descendant(
      of: anchor,
      matching: find.text(longLabel),
    );
    expect(
      tester.renderObject<RenderParagraph>(selectedLabel).didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('searchable select menu grows to show complete matching labels', (
    tester,
  ) async {
    const longLabel = "Resplendent Dim Tree Spirit's Armor Reform Stone V";
    final query = TextEditingController(text: longLabel);
    addTearDown(query.dispose);
    await tester.pumpWidget(
      _standardControlHost(
        child: SizedBox(
          width: 190,
          height: 38,
          child: AppSearchSelect<String>(
            controller: query,
            value: longLabel,
            items: const <String>['Wolf Blood', longLabel],
            labelFor: _stringLabel,
            semanticLabel: 'Long material search',
            onSelected: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Long material search'));
    await tester.pumpAndSettle();
    final option = find.widgetWithText(MenuItemButton, longLabel);
    expect(option, findsOneWidget);
    expect(tester.getSize(option).width, greaterThan(190));
    final label = find.descendant(of: option, matching: find.text(longLabel));
    expect(
      tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
      isFalse,
    );
    final rect = tester.getRect(option);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(tester.view.physicalSize.width));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tab enters selects and arrow keys change their value', (
    tester,
  ) async {
    final firstFocus = FocusNode();
    final selectFocus = FocusNode();
    final lastFocus = FocusNode();
    final firstText = TextEditingController(text: 'First');
    final lastText = TextEditingController(text: 'Last');
    addTearDown(() {
      firstFocus.dispose();
      selectFocus.dispose();
      lastFocus.dispose();
      firstText.dispose();
      lastText.dispose();
    });
    var selected = 1;

    await tester.pumpWidget(
      _standardControlHost(
        child: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 220,
                child: AppTextField(
                  controller: firstText,
                  focusNode: firstFocus,
                  semanticLabel: 'First field',
                ),
              ),
              SizedBox(
                width: 180,
                height: 38,
                child: AppSelect<int>(
                  value: selected,
                  items: const <int>[1, 2, 3],
                  labelFor: _numberLabel,
                  onChanged: (value) {
                    if (value != null) setState(() => selected = value);
                  },
                  semanticLabel: 'Keyboard select',
                  focusNode: selectFocus,
                ),
              ),
              SizedBox(
                width: 220,
                child: AppTextField(
                  controller: lastText,
                  focusNode: lastFocus,
                  semanticLabel: 'Last field',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    firstFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(selectFocus.hasFocus, isTrue);

    final selectRect = tester.getRect(find.byKey(AppSelect.anchorMaterialKey));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(selected, 2);
    expect(selectFocus.hasFocus, isTrue);
    expect(tester.getRect(find.byKey(AppSelect.anchorMaterialKey)), selectRect);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(selected, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(selected, 3);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNWidgets(3));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(selected, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(lastFocus.hasFocus, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    expect(selectFocus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('searchable select supports arrows, Enter, Escape, and Tab', (
    tester,
  ) async {
    final query = TextEditingController(text: 'Alpha');
    final searchFocus = FocusNode();
    final nextFocus = FocusNode();
    final nextText = TextEditingController(text: 'Next');
    addTearDown(() {
      query.dispose();
      searchFocus.dispose();
      nextFocus.dispose();
      nextText.dispose();
    });
    var selected = 'Alpha';

    await tester.pumpWidget(
      _standardControlHost(
        child: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 220,
                child: AppSearchSelect<String>(
                  controller: query,
                  focusNode: searchFocus,
                  value: selected,
                  items: const <String>['Alpha', 'Birch', 'Cedar'],
                  labelFor: _stringLabel,
                  onSelected: (value) => setState(() => selected = value),
                  semanticLabel: 'Searchable keyboard select',
                ),
              ),
              SizedBox(
                width: 220,
                child: AppTextField(
                  controller: nextText,
                  focusNode: nextFocus,
                  semanticLabel: 'Field after searchable select',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    searchFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNWidgets(3));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'Birch');
    expect(query.text, 'Birch');
    expect(query.selection.baseOffset, 0);
    expect(searchFocus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(nextFocus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'searchable select keeps a chosen long value readable in its closed field',
    (tester) async {
      const longLabel = 'Cheetah Dragon Blood Preparation Material Selection';
      final query = TextEditingController(text: 'Wolf Blood');
      final focus = FocusNode();
      addTearDown(query.dispose);
      addTearDown(focus.dispose);
      var selected = 'Wolf Blood';
      await tester.pumpWidget(
        _standardControlHost(
          child: StatefulBuilder(
            builder: (context, setState) => AppSearchSelect<String>(
              controller: query,
              focusNode: focus,
              value: selected,
              items: const <String>['Wolf Blood', longLabel],
              labelFor: _stringLabel,
              semanticLabel: 'Long selected material',
              onSelected: (value) => setState(() => selected = value),
            ),
          ),
        ),
      );

      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(selected, longLabel);
      expect(query.text, longLabel);
      expect(query.selection.baseOffset, 0);
      expect(
        tester.getSize(find.byType(AppSearchSelect<String>)).width,
        greaterThan(300),
      );
      final editable = tester.allRenderObjects
          .whereType<RenderEditable>()
          .single;
      expect(editable.offset.pixels, 0);
      expect(editable.text?.style?.fontSize, isNot(lessThan(12)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disabled app-owned controls expose no activation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: StandardSpec.theme.materialTheme(),
        home: ThemeSpecScope(
          spec: StandardSpec.theme,
          child: const Material(
            child: Column(
              children: <Widget>[
                AppChoiceChip(
                  label: 'Disabled choice',
                  selected: false,
                  onSelected: null,
                ),
                AppSlider(
                  value: .4,
                  min: 0,
                  max: 1,
                  semanticLabel: 'Disabled slider',
                  onChanged: null,
                ),
                SizedBox(
                  width: 180,
                  child: AppSelect<int>(
                    value: 1,
                    items: <int>[1, 2],
                    labelFor: _numberLabel,
                    semanticLabel: 'Disabled select',
                    onChanged: null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(AppSelect.anchorMaterialKey));
    await tester.pump();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Disabled slider')),
      matchesSemantics(
        label: 'Disabled slider',
        value: '0.40',
        hasEnabledState: true,
        isEnabled: false,
        isFocusable: true,
        isSlider: true,
      ),
    );
  });

  testWidgets('Standard subdued field matches the source-note material', (
    tester,
  ) async {
    final text = TextEditingController(text: 'Centered text');
    addTearDown(text.dispose);

    await tester.pumpWidget(
      _standardControlHost(
        child: SizedBox(
          key: const ValueKey<String>('centered-standard-field'),
          width: 260,
          height: 30,
          child: AppTextField(
            controller: text,
            semanticLabel: 'Centered standard field',
            emphasis: AppTextFieldEmphasis.subdued,
            textStyle: StandardSpec.typography.body.copyWith(
              fontSize: 12,
              height: 1.1,
            ),
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.textAlignVertical, TextAlignVertical.center);
    expect(
      field.decoration!.contentPadding,
      const EdgeInsets.symmetric(horizontal: 9),
    );
    final border = field.decoration!.enabledBorder! as OutlineInputBorder;
    expect(border.borderSide.color, const Color(0x395C8B76));
    final material = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('centered-standard-field')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = material.decoration as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    final expected = StandardSpec.glassGradient(topAlpha: 34, bottomAlpha: 12);
    expect(gradient.colors, expected.colors);
    expect(gradient.stops, expected.stops);
    expect(decoration.boxShadow, isNull);
    final fieldRect = tester.getRect(
      find.byKey(const ValueKey<String>('centered-standard-field')),
    );
    expect(
      (_caretCenterY(tester) - fieldRect.center.dy).abs(),
      lessThanOrEqualTo(1.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Ledger single-line field and select text stay vertically centered',
    (tester) async {
      final text = TextEditingController(text: 'Centered text');
      addTearDown(text.dispose);

      for (final scale in <double>[1, 2]) {
        final selectHeight = scale == 1 ? 38.0 : 44.0;
        await tester.pumpWidget(
          _ledgerControlHost(
            textScale: scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  key: const ValueKey<String>('centered-ledger-field'),
                  width: 260,
                  child: AppTextField(
                    controller: text,
                    semanticLabel: 'Centered ledger field',
                    prefixIcon: const Icon(Icons.search, size: 16),
                    suffixIcon: const Icon(Icons.close, size: 16),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 260,
                  height: selectHeight,
                  child: AppSelect<String>(
                    value: 'Centered selection',
                    items: const <String>['Centered selection', 'Other'],
                    labelFor: _stringLabel,
                    semanticLabel: 'Centered ledger select',
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
        );

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.textAlignVertical, TextAlignVertical.center);
        expect(
          field.decoration!.contentPadding,
          const EdgeInsets.symmetric(horizontal: 12),
        );
        final fieldRect = tester.getRect(
          find.byKey(const ValueKey<String>('centered-ledger-field')),
        );
        final caretCenter = _caretCenterY(tester);
        final editableCenter = _editableCenterY(tester);
        expect(
          (caretCenter - fieldRect.center.dy).abs(),
          lessThanOrEqualTo(1.5),
          reason:
              'text caret center at ${scale}x text scale: '
              '$caretCenter versus ${fieldRect.center.dy}; '
              'editable center $editableCenter',
        );

        final anchorRect = tester.getRect(
          find.byKey(AppSelect.anchorMaterialKey),
        );
        final selectedRect = tester.getRect(find.text('Centered selection'));
        expect(
          (selectedRect.center.dy - anchorRect.center.dy).abs(),
          lessThanOrEqualTo(1.5),
          reason: 'select label center at ${scale}x text scale',
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('Standard selection marker follows the live accent', (
    tester,
  ) async {
    const settings = StandardVisualSettings(accentHue: 286, neon: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: StandardSpec.theme.materialTheme(),
        home: ThemeSpecScope(
          spec: StandardSpec.theme,
          child: StandardVisualScope(
            settings: settings,
            child: const Material(
              child: Center(
                child: SizedBox.square(
                  dimension: 17,
                  child: AppSelectionMarker(selected: true),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final material = find.descendant(
      of: find.byKey(AppSelectionMarker.materialKey),
      matching: find.byType(DecoratedBox),
    );
    final decoration =
        tester.widget<DecoratedBox>(material).decoration as BoxDecoration;
    expect(
      decoration.gradient,
      StandardSpec.accentGlass(
        settings.accentHue,
        topAlpha: 255,
        bottomAlpha: 228,
        neon: settings.neon,
      ),
    );
    expect(
      decoration.border!.top.color,
      StandardSpec.accentBrush(
        settings.accentHue,
        alpha: .9,
        neon: settings.neon,
      ),
    );
    final glyph = tester.widget<AppVectorGlyph>(
      find.descendant(
        of: find.byKey(AppSelectionMarker.materialKey),
        matching: find.byType(AppVectorGlyph),
      ),
    );
    expect(glyph.color, const Color(0xFF03120E));
  });
}

String _numberLabel(int value) => '$value';
String _stringLabel(String value) => value;

Widget _ledgerControlHost({required double textScale, required Widget child}) =>
    MaterialApp(
      theme: IlluminatedLedgerSpec.theme.materialTheme(),
      builder: (context, appChild) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: appChild!,
      ),
      home: ThemeSpecScope(
        spec: IlluminatedLedgerSpec.theme,
        child: StandardVisualScope(
          settings: const StandardVisualSettings(accentHue: 158),
          child: Material(child: Center(child: child)),
        ),
      ),
    );

Widget _standardControlHost({required Widget child}) => MaterialApp(
  theme: StandardSpec.theme.materialTheme(),
  home: ThemeSpecScope(
    spec: StandardSpec.theme,
    child: StandardVisualScope(
      settings: const StandardVisualSettings(accentHue: 158),
      child: Material(child: Center(child: child)),
    ),
  ),
);

double _caretCenterY(WidgetTester tester) {
  final editable = tester.allRenderObjects.whereType<RenderEditable>().single;
  final caret = editable.getLocalRectForCaret(const TextPosition(offset: 1));
  return editable.localToGlobal(caret.center).dy;
}

double _editableCenterY(WidgetTester tester) {
  final editable = tester.allRenderObjects.whereType<RenderEditable>().single;
  return editable.localToGlobal(Offset(0, editable.size.height / 2)).dy;
}
