import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_book_test_support.dart';

void main() {
  setUpAll(() async {
    final fonts = '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts';
    for (final entry in {
      'Segoe UI': ['$fonts/segoeui.ttf', '$fonts/seguisb.ttf'],
      'Georgia': ['$fonts/georgia.ttf', '$fonts/georgiab.ttf'],
    }.entries) {
      if (!File(entry.value.first).existsSync()) continue;
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });

  for (final spec in [
    StandardSpec.theme,
    SakuraNightGardenSpec.theme,
    IlluminatedLedgerSpec.theme,
  ]) {
    for (final sizeScale in [
      (1100.0, 1.0),
      (1440.0, 1.25),
      (1440.0, 2.0),
      (720.0, 1.0),
    ]) {
      testWidgets(
        'search edges and copy ${spec.id} ${sizeScale.$1} ${sizeScale.$2}',
        (tester) async {
          tester.view.physicalSize = Size(sizeScale.$1, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final environment = buildRecipeBookTestEnvironment();
          final book = RecipeBookController(
            modeController: environment.application.active,
            catalogRepository: environment.catalogRepository,
            callingContext: RecipeBookCallingContext.planner,
            allowedTargets: environment.application.active.craftableNames,
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('search-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: spec.materialTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(sizeScale.$2)),
                  child: child!,
                ),
                home: ThemeSpecScope(
                  spec: spec,
                  child: Scaffold(
                    body: RecipeBookModal(
                      controller: book,
                      onClose: () {},
                      onActivated: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final search = tester.getRect(find.byKey(RecipeBookKeys.r03Search));
          final recipe = tester.getRect(
            find.byKey(RecipeBookKeys.r05RecipeNameScope),
          );
          final ingredient = tester.getRect(
            find.byKey(RecipeBookKeys.r05SearchByIngredient),
          );
          final searchHeading = tester.getRect(find.text('SEARCH RECIPES'));
          final scopeHeading = tester.getRect(find.text('SEARCH BY'));
          expect(recipe.top, closeTo(ingredient.top, .1));
          expect(recipe.bottom, closeTo(ingredient.bottom, .1));
          expect(recipe.height, closeTo(search.height, .1));
          if (recipe.left > search.right) {
            expect(search.top, closeTo(recipe.top, .1));
            expect(search.bottom, closeTo(recipe.bottom, .1));
            expect(searchHeading.top, closeTo(scopeHeading.top, .1));
            expect(recipe.left - search.right, closeTo(14, .1));
          } else {
            expect(scopeHeading.top, greaterThan(search.bottom));
            expect(recipe.left, closeTo(search.left, .1));
          }
          expect(ingredient.right, lessThanOrEqualTo(sizeScale.$1));
          final input = tester.widget<AppTextField>(
            find.byKey(RecipeBookKeys.r03Search),
          );
          expect(input.hintText, book.searchHint);
          expect(find.text('SEARCH RECIPES'), findsOneWidget);
          expect(find.text('SEARCH BY'), findsOneWidget);
          for (final label in [
            'Recipe name',
            'Ingredient',
            'SEARCH RECIPES',
            'SEARCH BY',
          ]) {
            expect(
              tester
                  .renderObject<RenderParagraph>(find.text(label))
                  .didExceedMaxLines,
              isFalse,
            );
          }
          expect(tester.takeException(), isNull);
          final root = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('search-capture')),
          );
          final bounds = searchHeading
              .expandToInclude(search)
              .expandToInclude(scopeHeading)
              .expandToInclude(ingredient)
              .inflate(8);
          await tester.runAsync(() async {
            final image = await (root.debugLayer! as OffsetLayer).toImage(bounds);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final output = File(
              'build/search-alignment-captures/${spec.id}-${sizeScale.$1.toInt()}-${(sizeScale.$2 * 100).toInt()}.png',
            );
            await output.parent.create(recursive: true);
            await output.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          await tester.tap(find.byKey(RecipeBookKeys.r05SearchByIngredient));
          await tester.pumpAndSettle();
          expect(book.searchByIngredient, isTrue);
          expect(
            tester
                .widget<AppTextField>(find.byKey(RecipeBookKeys.r03Search))
                .hintText,
            book.searchHint,
          );
          await tester.enterText(find.byKey(RecipeBookKeys.r03Search), 'Wild');
          await tester.pumpAndSettle();
          expect(book.search, 'Wild');
          await tester.tap(find.byKey(RecipeBookKeys.r03ClearSearch));
          await tester.pumpAndSettle();
          expect(book.search, isEmpty);
          await tester.tap(find.byKey(RecipeBookKeys.r05RecipeNameScope));
          await tester.pumpAndSettle();
          expect(book.searchByIngredient, isFalse);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          book.dispose();
          await environment.dispose();
        },
      );
    }
  }
}
