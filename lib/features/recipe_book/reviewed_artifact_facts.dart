// Exact PC identities and dated changes: docs/reviewed-artifact-facts.json.
// Informational only: never consume equipment or infer a loot probability.
import 'recipe_book_item_info.dart';

const reviewedBasicArtifacts = <int, String>{
  735201: "Marsh's Artifact - Melee AP",
  735202: "Marsh's Artifact - Ranged AP",
  735203: "Marsh's Artifact - Magic AP",
  735204: "Marsh's Artifact - Melee Accuracy",
  735205: "Marsh's Artifact - Ranged Accuracy",
  735206: "Marsh's Artifact - Magic Accuracy",
  735207: "Marsh's Artifact - Extra AP Against Monsters",
  735251: "Lesha's Artifact - Melee Damage Reduction",
  735252: "Lesha's Artifact - Melee Evasion",
  735253: "Lesha's Artifact - Ranged Damage Reduction",
  735254: "Lesha's Artifact - Ranged Evasion",
  735255: "Lesha's Artifact - Magic Damage Reduction",
  735256: "Lesha's Artifact - Magic Evasion",
  735257: "Lesha's Artifact - All Damage Reduction",
  735258: "Lesha's Artifact - All Evasion",
  735259: "Lesha's Artifact - Monster Damage Reduction",
  735301: "Kehelle's Artifact - Max HP",
  735302: "Kehelle's Artifact - Max Stamina",
  735303: "Kehelle's Artifact - Black Spirit's Rage Max Increase",
  735351: "Sethra's Artifact - Life EXP",
  735352: "Sethra's Artifact - Life Skill Mastery",
  735353: "Sethra's Artifact - Gathering Item Drop Rate",
  735354: "Sethra's Artifact - Processing Success Rate",
  735355: "Sethra's Artifact - Mount EXP",
  735356: "Sethra's Artifact - Gathering EXP",
  735357: "Sethra's Artifact - Fishing EXP",
  735358: "Sethra's Artifact - Hunting EXP",
  735359: "Sethra's Artifact - Cooking EXP",
  735360: "Sethra's Artifact - Alchemy EXP",
  735361: "Sethra's Artifact - Processing EXP",
  735362: "Sethra's Artifact - Training EXP",
  735363: "Sethra's Artifact - Trading EXP",
  735364: "Sethra's Artifact - Farming EXP",
  735365: "Sethra's Artifact - Sailing EXP",
  735366: "Sethra's Artifact - Barter EXP",
  735367: "Sethra's Artifact - Gathering Mastery",
  735368: "Sethra's Artifact - Fishing Mastery",
  735369: "Sethra's Artifact - Hunting Mastery",
  735370: "Sethra's Artifact - Cooking Mastery",
  735371: "Sethra's Artifact - Alchemy Mastery",
  735372: "Sethra's Artifact - Processing Mastery",
  735373: "Sethra's Artifact - Training Mastery",
  735374: "Sethra's Artifact - Sailing Mastery",
};

RecipeBookItemInfo withReviewedArtifactFacts(
  RecipeBookItemInfo info, {
  required String? itemId,
}) {
  if (info.isTemporarilyArchived) return info;
  final id = int.tryParse(itemId ?? '');
  final name = reviewedBasicArtifacts[id];
  if (name == null || info.title.trim().toLowerCase() != name.toLowerCase()) {
    return info;
  }
  final sources = {...info.acquisitionNotes};
  final notes = {...info.notes};
  // Same published Maretta loot table as Resplendent Lightstone of Flora.
  if (const {735351, 735352, 735365, 735374}.contains(id)) {
    sources.add('Sea monster · Hollow Maretta in Margoria (chance)');
  }
  if (id! < 735351) {
    sources.remove('Monster drops · Check Monster Zone Info');
    sources.remove(
      'Obtain as a monster drop; use Monster Zone Info to see the current zones.',
    );
    sources.add('Monster drops · Kratuga Ancient Ruins and other zones');
  }
  if (id == 735207 || id == 735259) {
    final quest = id == 735207 ? 'I' : 'IV';
    sources.add(
      'Black Spirit · A Gift for Leaping Forward $quest (once per family)',
    );
    notes.add('Gift quest unlocks through main-story progress.');
  }
  if (id == 735351 || id == 735352) {
    notes.add('Bonuses apply only to the Life Skill slot this is equipped in.');
  }
  return info.copyWith(
    acquisitionNotes: sources.toList(),
    notes: notes.toList(),
    uses: {
      ...info.uses,
      'Spare artifact (no Lightstones) · Dalishain → 2 Purified Lightstones',
    }.toList(),
  );
}
