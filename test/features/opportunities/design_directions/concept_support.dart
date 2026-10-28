import 'package:flutter/material.dart';

/// Visual exploration only. These are not market quotes or production records.
typedef ConceptItemIcon = Widget Function(String name, double size);

class ConceptRecipe {
  const ConceptRecipe(
    this.name,
    this.scope,
    this.profit,
    this.market,
    this.cost, {
    this.demand = false,
    this.profitable = true,
  });
  final String name;
  final String scope;
  final String profit;
  final String market;
  final String cost;
  final bool demand;
  final bool profitable;
}

const conceptRecipes = [
  ConceptRecipe(
    'Beer',
    'Makes 2,5 · 1 craft',
    '161,2K',
    '−100.000',
    '1.250',
    demand: true,
  ),
  ConceptRecipe(
    'Smoked Fish Steak',
    'Makes 2,5 · 1 craft',
    '535',
    '100.000',
    '1.090',
  ),
  ConceptRecipe('Dressing', 'Makes 2,5 · 1 craft', '505', '100.000', '1.120'),
  ConceptRecipe(
    'Fruit Juice',
    'Makes 2,5 · 1 craft',
    '385',
    '100.000',
    '1.240',
  ),
  ConceptRecipe('Grain Soup', 'Makes 2,5 · 1 craft', '385', '100.000', '1.240'),
  ConceptRecipe(
    'Essence of Liquor',
    'Makes 2,5 · 1 craft',
    '−105',
    '100.000',
    '1.730',
    profitable: false,
  ),
];

TextStyle conceptType(
  double size,
  Color color, {
  FontWeight weight = FontWeight.w500,
}) => TextStyle(
  fontFamily: 'Segoe UI',
  fontSize: size,
  height: 1.2,
  color: color,
  fontWeight: weight,
  fontFeatures: const [FontFeature.tabularFigures()],
);
