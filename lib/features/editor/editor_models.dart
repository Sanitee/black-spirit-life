import '../../domain/state/planner_state.dart';

final class EditorIngredientDraft {
  EditorIngredientDraft({
    required this.name,
    required this.quantityText,
    required this.options,
    required this.substituteGroup,
    required this.substituteRatios,
    required this.extensions,
  });

  factory EditorIngredientDraft.fromState(IngredientState source) =>
      EditorIngredientDraft(
        name: source.name,
        quantityText: formatEditorNumber(source.quantity),
        options: List<String>.of(source.options),
        substituteGroup: source.substituteGroup,
        substituteRatios: Map<String, double>.of(source.substituteRatios),
        extensions: Map<String, Object?>.of(source.extensions),
      );

  factory EditorIngredientDraft.empty() => EditorIngredientDraft(
    name: '',
    quantityText: '1',
    options: const <String>[],
    substituteGroup: null,
    substituteRatios: const <String, double>{},
    extensions: const <String, Object?>{},
  );

  String name;
  String quantityText;
  final List<String> options;
  final String? substituteGroup;
  final Map<String, double> substituteRatios;
  final Map<String, Object?> extensions;

  IngredientState toState({
    required String canonicalName,
    required double quantity,
  }) => IngredientState(
    name: canonicalName,
    quantity: quantity,
    options: options,
    substituteGroup: substituteGroup,
    substituteRatios: substituteRatios,
    extensions: extensions,
  );
}

final class RecipeEditorDraft {
  RecipeEditorDraft({
    required this.originalName,
    required this.isNew,
    required this.name,
    required this.baseOutputText,
    required this.marketId,
    required this.type,
    required this.category,
    required this.categoryIsCustom,
    required this.customCategory,
    required this.method,
    required this.methodIsCustom,
    required this.customMethod,
    required this.vendor,
    required this.npcPriceText,
    required this.location,
    required this.sourceNote,
    required this.searchKeywords,
    required this.ingredients,
    required this.sourceRecipe,
    required this.sourceMetadata,
    required this.originalIcon,
    required this.icon,
  });

  final String? originalName;
  final bool isNew;
  String name;
  String baseOutputText;
  String marketId;
  String type;
  String category;
  bool categoryIsCustom;
  String customCategory;
  String method;
  bool methodIsCustom;
  String customMethod;
  String vendor;
  String npcPriceText;
  String location;
  String sourceNote;
  String searchKeywords;
  final List<EditorIngredientDraft> ingredients;
  final RecipeState sourceRecipe;
  final IngredientMetadata sourceMetadata;
  final CustomIconReference? originalIcon;
  CustomIconReference? icon;
  bool dirty = false;
  bool iconChanged = false;

  String get effectiveCategory => categoryIsCustom ? customCategory : category;
  String get effectiveMethod => methodIsCustom ? customMethod : method;
}

double? parseEditorNumber(String text) {
  final normalized = text.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  final value = double.tryParse(normalized);
  return value != null && value.isFinite ? value : null;
}

String formatEditorNumber(double value) {
  if (!value.isFinite) return '0';
  if ((value - value.roundToDouble()).abs() < .0000001) {
    return value.round().toString();
  }
  return value
      .toStringAsFixed(6)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String normalizeEditorCategory(String value) => value
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .join(' ');

String? trimmedOrNull(String value) {
  final result = value.trim();
  return result.isEmpty ? null : result;
}
