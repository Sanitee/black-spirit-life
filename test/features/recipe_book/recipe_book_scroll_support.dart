import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ingredient cards are taller than the old title-only cards. Exercise their
/// real virtualized scroll path instead of assuming every result is mounted.
Future<void> revealBookControl(WidgetTester tester, Finder control) async {
  final scrollable = find
      .descendant(
        of: find.byKey(RecipeBookKeys.r10CardScroll),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  if (control.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      control,
      240,
      scrollable: scrollable,
      maxScrolls: 80,
    );
  }
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
}

Future<void> tapBookDetails(WidgetTester tester, String name) async {
  final control = find.byKey(RecipeBookKeys.r13Details(name));
  await revealBookControl(tester, control);
  await tester.tap(control);
}
