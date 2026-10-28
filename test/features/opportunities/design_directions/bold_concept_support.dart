import 'concept_support.dart';

/// Deliberately fixed visual examples. Never loaded by the application.
const boldConceptRecipes = <ConceptRecipe>[
  ConceptRecipe(
    'Corruption Draught',
    '100× recipe',
    '119,1M',
    '4.160',
    '363,5M',
  ),
  ConceptRecipe(
    'Perfume of Deep Sea',
    '',
    '18,4M',
    '−12.400',
    '31,6M',
    demand: true,
  ),
  ConceptRecipe('Perfume of Verdure', '', '8,3M', '6.420', '24,7M'),
  ConceptRecipe('Frenzy Draught', '', '6,2M', '820', '14,8M'),
  ConceptRecipe("Giant's Draught", '', '4,8M', '−6.240', '12,2M', demand: true),
  ConceptRecipe(
    "Griffon's Elixir",
    '',
    '−125K',
    '9.350',
    '825K',
    profitable: false,
  ),
];
