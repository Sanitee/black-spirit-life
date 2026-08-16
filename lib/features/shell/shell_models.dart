import 'package:flutter/widgets.dart';

import '../../app_identity.dart';
import '../../domain/models/craft_mode.dart';

/// Main workspace destinations exposed by the persistent navigation rail.
enum ShellDestination {
  planner(label: 'Planner', semanticLabel: 'Open Planner', actionId: 'S07'),
  bonusRecipes(
    label: 'Bonus Recipes',
    semanticLabel: 'Open Bonus Recipes',
    actionId: 'S08',
  ),
  inventory(
    label: 'Inventory',
    semanticLabel: 'Open Inventory',
    actionId: 'S09',
  ),
  recipeEditor(
    label: 'Recipe Editor',
    semanticLabel: 'Open Recipe Editor',
    actionId: 'S10',
  ),
  appearance(
    label: 'Appearance',
    semanticLabel: 'Open Appearance',
    actionId: 'S11',
  ),
  data(
    label: 'Craft Profile',
    semanticLabel: 'Open Craft Profile',
    actionId: 'S12',
  ),
  about(
    label: 'About',
    semanticLabel: 'Open About Black Spirit Life',
    actionId: 'S16',
  );

  const ShellDestination({
    required this.label,
    required this.semanticLabel,
    required this.actionId,
  });

  final String label;
  final String semanticLabel;
  final String actionId;

  bool get isAdvanced =>
      this == ShellDestination.inventory ||
      this == ShellDestination.recipeEditor;

  bool isAvailableFor(CraftMode mode) =>
      this != ShellDestination.bonusRecipes || mode != CraftMode.processing;

  bool get isTemporarilyHidden =>
      this == ShellDestination.about && !AppIdentity.showAboutDestination;

  bool isVisibleFor(CraftMode mode, {required bool showAdvanced}) =>
      !isTemporarilyHidden &&
      isAvailableFor(mode) &&
      (showAdvanced || !isAdvanced);

  Key get actionKey => ValueKey<String>(actionId);
}

/// Content-only transitions available from Appearance settings.
enum ShellContentTransition {
  off('Off'),
  fade('Fade'),
  slide('Slide'),
  lift('Lift');

  const ShellContentTransition(this.label);

  final String label;
}

/// User-selectable pacing for content-only workspace transitions.
enum ShellContentTransitionSpeed {
  slow('Slow', Duration(milliseconds: 450)),
  normal('Normal', Duration(milliseconds: 300)),
  fast('Fast', Duration(milliseconds: 180));

  const ShellContentTransitionSpeed(this.label, this.duration);

  final String label;
  final Duration duration;
}

/// Stable action and region identities used by tests and integrations.
abstract final class ShellActionKeys {
  static const Key modeSelector = ValueKey<String>('S13');
  static const Key animatedTransition = ValueKey<String>('S14');
  static const Key immediateTransition = ValueKey<String>('S15');

  static Key mode(CraftMode mode) => ValueKey<String>('S13:${mode.key}');
}

/// Stable element identities for the long-lived workspace regions.
abstract final class WorkspaceShellKeys {
  static const Key root = ValueKey<String>('workspace-shell');
  static const Key sidebar = ValueKey<String>('workspace-shell-sidebar');
  static const Key sidebarMaterial = ValueKey<String>(
    'workspace-shell-sidebar-material',
  );
  static const Key ledgerMarginaliaHost = ValueKey<String>(
    'workspace-shell-ledger-marginalia-host',
  );
  static const Key sakuraBotanicalHost = ValueKey<String>(
    'workspace-shell-sakura-botanical-host',
  );
  static const Key navigation = ValueKey<String>('workspace-shell-navigation');
  static const Key contentHost = ValueKey<String>(
    'workspace-shell-content-host',
  );
  static const Key compactLayout = ValueKey<String>(
    'workspace-shell-layout-compact',
  );
  static const Key referenceLayout = ValueKey<String>(
    'workspace-shell-layout-reference',
  );
}
