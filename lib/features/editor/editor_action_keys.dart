import 'package:flutter/foundation.dart';

abstract final class EditorActionKeys {
  static const Key e01 = ValueKey<String>('editor-E01-search');
  static const Key e02 = ValueKey<String>('editor-E02-select-item');
  static const Key e03 = ValueKey<String>('editor-E03-new-recipe');
  static const Key e04 = ValueKey<String>('editor-E04-name');
  static const Key e05 = ValueKey<String>('editor-E05-base-output');
  static const Key e06 = ValueKey<String>('editor-E06-market-id');
  static const Key e07 = ValueKey<String>('editor-E07-type');
  static const Key e08 = ValueKey<String>('editor-E08-category');
  static const Key e09 = ValueKey<String>('editor-E09-method');
  static const Key e10 = ValueKey<String>('editor-E10-source-fields');
  static const Key e11 = ValueKey<String>('editor-E11-choose-icon');
  static const Key e12 = ValueKey<String>('editor-E12-remove-icon');
  static const Key e13 = ValueKey<String>('editor-E13-ingredient-item');
  static const Key e14 = ValueKey<String>('editor-E14-ingredient-quantity');
  static const Key e15 = ValueKey<String>('editor-E15-add-ingredient');
  static const Key e16 = ValueKey<String>('editor-E16-remove-ingredient');
  static const Key e17 = ValueKey<String>('editor-E17-save');
  static const Key e18 = ValueKey<String>('editor-E18-delete');

  static Key item(String name) => ValueKey<String>('editor-item-$name');
  static Key type(String type) => ValueKey<String>('editor-type-$type');
  static Key ingredientItem(int index) =>
      ValueKey<String>('editor-ingredient-item-$index');
  static Key ingredientQuantity(int index) =>
      ValueKey<String>('editor-ingredient-quantity-$index');
  static Key removeIngredient(int index) =>
      ValueKey<String>('editor-remove-ingredient-$index');
}
