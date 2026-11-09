import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder substituteChooser() => find.byWidgetPredicate(
  (w) => w is RecipeIngredientTable && w.onChoose != null,
);

Future<void> openSubstitutes(
  WidgetTester tester,
  String parent,
  String ingredient,
) async {
  final button = find
      .byKey(ValueKey('recipe-substitutes:$parent:$ingredient'))
      .first;
  expect(button, findsOneWidget);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(substituteChooser(), findsOneWidget);
}

Future<void> chooseSubstitute(
  WidgetTester tester,
  String parent,
  String name,
) async {
  final row = find.byKey(ValueKey('recipe-choose:$parent:$name'));
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
  expect(substituteChooser(), findsNothing);
}

Finder substituteBadge(String name) => find.descendant(
  of: substituteChooser(),
  matching: find.byKey(ValueKey('reference-source:$name')),
);

Finder substituteLabel(String name) => find.descendant(
  of: substituteChooser(),
  matching: find.byWidgetPredicate(
    (w) =>
        w is Text &&
        (w.textSpan?.toPlainText().toLowerCase().startsWith(
              '${name.toLowerCase()}  ×',
            ) ??
            false),
  ),
);
