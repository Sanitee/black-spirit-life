import 'package:flutter/widgets.dart';

import '../../domain/models/craft_mode.dart';
import '../../domain/state/planner_state.dart';

/// Long-lived, document-independent Inventory state. A shell can retain one
/// instance across navigation so each mode restores its search, category,
/// tools, selection, undo offer, and scroll offset without polluting saved
/// planner data.
final class InventorySessionController {
  InventorySessionController();

  final Map<CraftMode, InventoryModeSession> _modes =
      <CraftMode, InventoryModeSession>{};
  bool _disposed = false;

  InventoryModeSession forMode(CraftMode mode) {
    assert(!_disposed, 'InventorySessionController has been disposed.');
    return _modes.putIfAbsent(mode, InventoryModeSession.new);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final mode in _modes.values) {
      mode.dispose();
    }
    _modes.clear();
  }
}

final class InventoryModeSession {
  InventoryModeSession();

  String search = '';
  String selectedCategory = '';
  String selectedSmartGroup = 'All materials';
  InventoryDisplayFilter displayFilter = InventoryDisplayFilter.materials;
  String? selectedItem;
  String groupItemQuery = '';
  String? groupItemSelection;
  bool groupToolsOpen = false;
  InventoryUndoSnapshot? undo;
  final ScrollController itemScrollController = ScrollController();
  final ScrollController categoryScrollController = ScrollController();

  void dispose() {
    itemScrollController.dispose();
    categoryScrollController.dispose();
  }
}

enum InventoryDisplayFilter {
  materials('Materials'),
  owned('Owned'),
  currentPlan('Current plan'),
  all('All items');

  const InventoryDisplayFilter(this.label);

  final String label;
}

final class InventoryUndoSnapshot {
  const InventoryUndoSnapshot({
    required this.operation,
    required this.message,
    required this.before,
    required this.after,
    required this.selectedCategory,
  });

  final String operation;
  final String message;
  final ModeState before;
  final ModeState after;
  final String selectedCategory;
}
