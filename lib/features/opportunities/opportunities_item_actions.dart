import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/craft_mode.dart';
import '../../shared/overlays/anchored_popover.dart';
import '../../visual/visual.dart';
import '../planner/planner_contracts.dart';
import '../recipe_book/recipe_book_item_info.dart';
import '../recipe_book/recipe_book_item_info_view.dart';
import 'opportunities_controller.dart';

/// InheritedTheme keeps the shell's map actions available inside showDialog.
class OpportunityItemActionsScope extends InheritedTheme {
  const OpportunityItemActionsScope({
    required this.externalActions,
    required super.child,
    super.key,
  });

  final PlannerExternalActions externalActions;

  static PlannerExternalActions? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<OpportunityItemActionsScope>()
      ?.externalActions;

  @override
  bool updateShouldNotify(OpportunityItemActionsScope oldWidget) =>
      externalActions != oldWidget.externalActions;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      OpportunityItemActionsScope(
        externalActions: externalActions,
        child: child,
      );
}

enum _ItemAction {
  info,
  recipe,
  planner,
  npc,
  gathering,
  workers,
  checklist,
  network,
  copy,
}

/// The name copies independently of any recipe action on its surrounding card.
class OpportunityCopyName extends StatelessWidget {
  const OpportunityCopyName({
    required this.name,
    this.displayLabel,
    this.style,
    super.key,
  });

  final String name;
  final String? displayLabel;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Copy $name',
    child: Align(
      alignment: Alignment.centerLeft,
      heightFactor: 1,
      widthFactor: 1,
      child: InkWell(
        key: ValueKey('opportunity-copy-name:$name'),
        borderRadius: BorderRadius.circular(4),
        hoverColor: Colors.transparent,
        onTap: () => _copyOpportunityName(context, name),
        child: Text(displayLabel ?? name, style: style),
      ),
    ),
  );
}

Future<void> _copyOpportunityName(BuildContext context, String name) async {
  final actions = OpportunityItemActionsScope.maybeOf(context);
  if (actions != null) {
    await actions.copyName(name);
    return;
  }
  try {
    await Clipboard.setData(ClipboardData(text: name));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('Copied $name'),
        duration: const Duration(milliseconds: 1350),
      ),
    );
  } on Object {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Could not copy the name. Try again.')),
    );
  }
}

/// Secondary actions do not replace the item's existing primary click.
class OpportunityItemRegion extends StatefulWidget {
  const OpportunityItemRegion({
    required this.controller,
    required this.name,
    required this.stableId,
    required this.child,
    this.onViewRecipe,
    this.beforeNavigate,
    this.plannerMode,
    this.plannerVariantId,
    this.resolvePlannerTarget,
    this.resolveGatherDemand,
    this.childHandlesFocus = false,
    super.key,
  });

  final OpportunitiesController controller;
  final String name;
  final String stableId;
  final Widget child;
  final VoidCallback? onViewRecipe;
  final CraftMode? plannerMode;
  final String? plannerVariantId;
  final PlannerTargetRequest? Function()? resolvePlannerTarget;
  final PlannerGatherDemand? Function()? resolveGatherDemand;

  /// Optional host hook; retained Opportunities routes are not dismissed.
  final VoidCallback? beforeNavigate;

  /// Keeps an already-focusable primary action as the only Tab stop.
  /// Item-menu shortcuts still work while a descendant has focus.
  final bool childHandlesFocus;

  @override
  State<OpportunityItemRegion> createState() => _OpportunityItemRegionState();
}

class _OpportunityItemRegionState extends State<OpportunityItemRegion> {
  final _focus = FocusNode();
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _focus.skipTraversal = widget.childHandlesFocus;
  }

  @override
  void didUpdateWidget(OpportunityItemRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _focus.skipTraversal = widget.childHandlesFocus;
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    focusNode: _focus,
    includeFocusSemantics: !widget.childHandlesFocus,
    mouseCursor: SystemMouseCursors.contextMenu,
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.contextMenu): _OpenItemMenuIntent(),
      SingleActivator(LogicalKeyboardKey.f10, shift: true):
          _OpenItemMenuIntent(),
    },
    actions: {
      _OpenItemMenuIntent: CallbackAction<_OpenItemMenuIntent>(
        onInvoke: (_) {
          final box = context.findRenderObject();
          if (box is RenderBox && box.hasSize) {
            unawaited(
              _showMenu(box.localToGlobal(box.size.center(Offset.zero))),
            );
          }
          return null;
        },
      ),
    },
    child: GestureDetector(
      key: ValueKey('opportunity-item:${widget.stableId}'),
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) {
        if (!widget.childHandlesFocus) _focus.requestFocus();
        unawaited(_showMenu(details.globalPosition));
      },
      onLongPressStart: (details) {
        if (!widget.childHandlesFocus) _focus.requestFocus();
        unawaited(_showMenu(details.globalPosition));
      },
      child: widget.child,
    ),
  );

  Future<void> _showMenu(Offset position) async {
    if (_opening) return;
    _opening = true;
    final actions = OpportunityItemActionsScope.maybeOf(context);
    final navigator = Navigator.of(context);
    try {
      PlannerMapLookupAvailability? availability;
      try {
        availability = await actions?.resolveMapLookup?.call(widget.name);
      } on Object {
        // Source lookup failure must not hide item information or its recipe.
      }
      if (!mounted) return;
      final plannerTarget = widget.resolvePlannerTarget != null
          ? widget.resolvePlannerTarget!()
          : widget.controller.plannerTargetFor(
              widget.name,
              mode: widget.plannerMode,
              variantId: widget.plannerVariantId,
            );
      final spec = context.visualTheme;
      final overlay = navigator.overlay?.context.findRenderObject();
      if (overlay is! RenderBox || !overlay.hasSize) return;
      final localPosition = overlay.globalToLocal(position);
      final canNavigate = actions?.openMapLookup != null;
      final manualName = availability?.manualMaterialName?.trim();
      final manualLabel = manualName?.isNotEmpty == true
          ? 'Show $manualName'
          : 'Show gathering locations';
      AppOverlayCoordinatorScope.maybeOf(context)?.dismissTop();
      final selected = await showMenu<_ItemAction>(
        context: context,
        useRootNavigator: false,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(localPosition.dx, localPosition.dy, 0, 0),
          Offset.zero & overlay.size,
        ),
        color: spec.palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 18,
        constraints: BoxConstraints(
          minWidth: math.min(240, overlay.size.width - 16),
          maxWidth: math.min(360, overlay.size.width - 16),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(spec.geometry.cardRadius),
          side: BorderSide(color: spec.palette.trim),
        ),
        items: [
          _entry(_ItemAction.info, 'Item info', Icons.info_outline),
          if (widget.onViewRecipe != null)
            _entry(_ItemAction.recipe, 'View recipe', Icons.menu_book_outlined),
          if (plannerTarget != null && actions?.openPlannerTarget != null)
            _entry(
              _ItemAction.planner,
              'Set planner target',
              Icons.playlist_add_check,
            ),
          if (canNavigate && availability?.hasNpcVendors == true)
            _entry(
              _ItemAction.npc,
              'Show NPC vendors',
              Icons.storefront_outlined,
            ),
          if (canNavigate && availability?.hasManualGathering == true)
            _entry(
              _ItemAction.gathering,
              manualLabel,
              Icons.location_on_outlined,
            ),
          if (canNavigate && availability?.hasWorkerNodes == true)
            _entry(
              _ItemAction.workers,
              'Show worker nodes',
              Icons.account_tree_outlined,
            ),
          if (actions?.addToGatherChecklist != null &&
              (availability?.hasManualGathering == true ||
                  availability?.hasWorkerNodes == true) &&
              (availability?.manualResourceId != null ||
                  availability?.workerResourceId != null))
            _entry(_ItemAction.checklist, 'Add to to-do list', Icons.checklist),
          if (actions?.addToPlannedNetwork != null &&
              availability?.hasWorkerNodes == true &&
              availability?.workerResourceId != null)
            _entry(
              _ItemAction.network,
              'Add to planned network',
              Icons.add_location_alt_outlined,
            ),
          const PopupMenuDivider(height: 8),
          _entry(_ItemAction.copy, 'Copy name', Icons.copy_outlined),
        ],
      );
      if (selected == null || !mounted) return;
      switch (selected) {
        case _ItemAction.info:
          await _showItemInfo(context, widget.controller, widget.name);
        case _ItemAction.recipe:
          widget.onViewRecipe?.call();
        case _ItemAction.planner:
          if (plannerTarget == null || actions?.openPlannerTarget == null) {
            return;
          }
          widget.beforeNavigate?.call();
          actions!.openPlannerTarget!(plannerTarget);
        case _ItemAction.checklist:
          if (availability != null) {
            actions?.addToGatherChecklist?.call(
              PlannerGatherChecklistRequest(
                availability: availability,
                demand: widget.resolveGatherDemand?.call(),
              ),
            );
          }
        case _ItemAction.network:
          if (availability != null) {
            actions?.addToPlannedNetwork?.call(availability);
          }
        case _ItemAction.copy:
          await _copyOpportunityName(context, widget.name);
        case _ItemAction.npc:
        case _ItemAction.gathering:
        case _ItemAction.workers:
          if (availability == null || actions?.openMapLookup == null) return;
          final source = switch (selected) {
            _ItemAction.npc => PlannerMapLookupSource.npcVendors,
            _ItemAction.gathering => PlannerMapLookupSource.manualGathering,
            _ => PlannerMapLookupSource.workerNodes,
          };
          final request = PlannerMapLookupRequest(
            materialName:
                source == PlannerMapLookupSource.manualGathering &&
                    manualName?.isNotEmpty == true
                ? manualName!
                : availability.materialName,
            source: source,
            resourceId: availability.resourceIdFor(source),
          );
          widget.beforeNavigate?.call();
          actions!.openMapLookup!(request);
      }
    } finally {
      _opening = false;
    }
  }

  PopupMenuEntry<_ItemAction> _entry(
    _ItemAction action,
    String label,
    IconData icon,
  ) => PopupMenuItem(
    key: ValueKey('opportunity-item-action:${widget.stableId}:${action.name}'),
    value: action,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19),
        const SizedBox(width: 10),
        Flexible(child: Text(label)),
      ],
    ),
  );
}

class _OpenItemMenuIntent extends Intent {
  const _OpenItemMenuIntent();
}

Future<void> _showItemInfo(
  BuildContext context,
  OpportunitiesController controller,
  String name,
) async {
  final book = controller.itemInfoController;
  final mode = controller.modeController.mode;
  final info =
      book.itemInfoFor(name, mode: mode) ??
      RecipeBookItemInfo(title: name, kind: 'Item', summary: '');
  await showDialog<void>(
    context: context,
    useRootNavigator: false,
    barrierColor: Colors.black.withAlpha(200),
    builder: (context) => Dialog(
      key: ValueKey('opportunity-item-info:$name'),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ItemReferenceCard(
        controller: book,
        mode: mode,
        name: name,
        info: info,
        maxWidth: itemReferenceCardWidth(context),
        spec: context.visualTheme,
        onClose: () => Navigator.pop(context),
        onCopyItemName: (name) => _copyOpportunityName(context, name),
      ),
    ),
  );
}
