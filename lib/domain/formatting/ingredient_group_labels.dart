import '../models/catalog_models.dart';

/// Display labels only. Never use these as saved substitute keys or identities.
String ingredientGroupLabel(Ingredient ingredient) {
  final group = ingredient.substituteGroup?.trim() ?? '';
  final folded = group.toLowerCase();
  final id = RegExp(r'^bdo group\s+(\d+)$').firstMatch(folded)?.group(1);
  if (id != null) return _bdoLabels[id] ?? 'Ingredient';
  if (folded == 'fruit group 6007') return 'Fruit';
  if (folded == 'sunrise herb group 3001') return 'Sunrise Herb';
  // Imported processing/recipe slot keys are not category names. Avoid
  // presenting an invented family for unrelated materials in these slots.
  if (group.contains(':') || RegExp(r'\bgroup\s+\d{3,}\b').hasMatch(folded)) {
    return 'Ingredient';
  }
  return group.isEmpty ? ingredient.name : group;
}

// Names describe the bundled option families, not a new substitution model.
const _bdoLabels = <String, String>{
  '1': 'Grain',
  '2': 'Dough',
  '3': 'Fruit',
  '4': 'Red meat',
  '5': 'Flour',
  '6': 'Dried fish',
  '9': 'Flowers',
  '10': 'Dried seafood',
  '11': 'Reptile meat',
  '13': 'Vegetables',
  '15': 'Blood Group 4',
  '16': 'Blood Group 1',
  '17': 'Blood Group 2',
  '18': 'Blood Group 3',
  '50': 'Pepper',
  '51': 'Hot Pepper',
  '52': 'Garlic',
  '53': 'Onion',
  '54': 'Fortune Mushroom',
  '55': 'Delotia',
  '56': 'Fog Mushroom',
  '57': 'Amanita Mushroom',
  '61': 'Dwarf Mushroom',
  '67': 'Arrow Mushroom',
  '68': 'Cloud Mushroom',
  '69': 'Dry Mane Grass',
  '70': 'Fire Flake Flower',
  '71': 'Flowers',
  '72': 'Citron',
  '73': 'Dictyophora',
  '76': 'Mesima',
  '77': 'Chanterelle',
  '78': 'Red-spotted Amanita',
  '79': 'Radish',
  '90': 'Shellfish',
  '6600': 'Water source',
  '8201170': 'Rice',
  '82011700': 'Rice',
  '8201200': 'Napa Cabbage',
  '8201230': 'Radish',
};
