import 'package:flutter/foundation.dart';

import '../../domain/models/craft_mode.dart';
import '../../domain/state/planner_state.dart';

final class RecipeEditorFreshDraftRequest {
  const RecipeEditorFreshDraftRequest({
    required this.mode,
    this.initialCategory = '',
  });

  final CraftMode mode;
  final String initialCategory;
}

final class EditorUndoSnapshot {
  const EditorUndoSnapshot({
    required this.operation,
    required this.message,
    required this.before,
    required this.selectedName,
    required this.icon,
  });

  final String operation;
  final String message;
  final PlannerState before;
  final String selectedName;
  final CustomIconReference? icon;
}

final class RecipeEditorModeSession {
  String search = '';
  String? selectedName;
  EditorUndoSnapshot? undo;
}

/// Host-owned session state keeps search, selection, and fresh-draft routing
/// stable while the shell changes modes or rebuilds. Inventory can call
/// [openFreshDraft] with its mode/category payload before navigating here.
final class RecipeEditorSessionController extends ChangeNotifier {
  final Map<CraftMode, RecipeEditorModeSession> _modes =
      <CraftMode, RecipeEditorModeSession>{
        for (final mode in CraftMode.values) mode: RecipeEditorModeSession(),
      };
  final Map<CraftMode, RecipeEditorFreshDraftRequest> _pending =
      <CraftMode, RecipeEditorFreshDraftRequest>{};

  RecipeEditorModeSession forMode(CraftMode mode) => _modes[mode]!;

  void openFreshDraft({required CraftMode mode, String initialCategory = ''}) {
    _pending[mode] = RecipeEditorFreshDraftRequest(
      mode: mode,
      initialCategory: initialCategory,
    );
    notifyListeners();
  }

  RecipeEditorFreshDraftRequest? takeFreshDraft(CraftMode mode) =>
      _pending.remove(mode);
}
