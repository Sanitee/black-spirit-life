import 'package:flutter/material.dart';

import '../../shared/overlays/anchored_popover.dart';
import '../../visual/visual.dart';
import 'planner_contracts.dart';
import 'planner_keys.dart';
import 'planner_map_menu_presentation.dart';

enum _PlannerMapQuickAction {
  npcVendors,
  manualGathering,
  addToGatherChecklist,
  addToPlannedNetwork,
}

/// Adds the planner's source-aware map menu to any material surface.
///
/// The availability resolver decides which actions are useful for the exact
/// selected material. This keeps Recipe Book ingredient rows and planner rows
/// on the same map-navigation, checklist, and worker-network pipeline.
class PlannerMapQuickLookupRegion extends StatefulWidget {
  const PlannerMapQuickLookupRegion({
    required this.materialName,
    required this.stableId,
    required this.externalActions,
    required this.child,
    this.resolveGatherDemand,
    super.key,
  });

  final String materialName;
  final String stableId;
  final PlannerExternalActions externalActions;
  final Widget child;
  final PlannerGatherDemand? Function()? resolveGatherDemand;

  @override
  State<PlannerMapQuickLookupRegion> createState() =>
      _PlannerMapQuickLookupRegionState();
}

class _PlannerMapQuickLookupRegionState
    extends State<PlannerMapQuickLookupRegion> {
  @override
  Widget build(BuildContext context) {
    final actions = widget.externalActions;
    if (actions.resolveMapLookup == null ||
        (actions.openMapLookup == null &&
            actions.addToGatherChecklist == null &&
            actions.addToPlannedNetwork == null)) {
      return widget.child;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.contextMenu,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (details) {
          _showMenu(globalPosition: details.globalPosition);
        },
        onLongPressStart: (details) {
          _showMenu(globalPosition: details.globalPosition);
        },
        child: widget.child,
      ),
    );
  }

  Future<void> _showMenu({required Offset globalPosition}) async {
    final resolver = widget.externalActions.resolveMapLookup;
    final opener = widget.externalActions.openMapLookup;
    if (resolver == null) return;

    final availability = await resolver(widget.materialName);
    if (!mounted || !availability.hasAnySource) return;
    final canOpenNpcVendors = availability.hasNpcVendors && opener != null;
    final canOpenManual = availability.hasManualGathering && opener != null;
    final canAddToChecklist =
        (availability.hasManualGathering || availability.hasWorkerNodes) &&
        widget.externalActions.addToGatherChecklist != null;
    final canAddToPlannedNetwork =
        availability.hasWorkerNodes &&
        widget.externalActions.addToPlannedNetwork != null;
    if (!canOpenNpcVendors &&
        !canOpenManual &&
        !canAddToChecklist &&
        !canAddToPlannedNetwork) {
      return;
    }

    final npcVendorDetail =
        '${availability.npcVendorCount} mapped vendor '
        '${availability.npcVendorCount == 1 ? 'location' : 'locations'}';
    final manualDetail = availability.manualLocationCount > 0
        ? '${availability.manualLocationCount} mapped '
              '${availability.manualLocationCount == 1 ? 'location' : 'locations'}'
        : 'Open this material on the map';
    final manualActionLabel = availability.manualLocationCount > 0
        ? 'Show gathering locations'
        : 'Show source on map';
    const checklistDetail = 'Keep it in your map checklist';
    final plannedNetworkDetail = availability.workerNodeCount > 0
        ? '${availability.workerNodeCount} worker '
              '${availability.workerNodeCount == 1 ? 'node' : 'nodes'} available'
        : 'Worker nodes available';

    AppOverlayCoordinatorScope.maybeOf(context)?.dismissTop();
    final overlay = Navigator.of(
      context,
      rootNavigator: true,
    ).overlay?.context.findRenderObject();
    if (overlay is! RenderBox || !overlay.hasSize) return;
    final spec = context.visualTheme;
    final menuWidth = plannerMapLookupMenuWidth(
      context: context,
      viewportSize: overlay.size,
      actionLabels: <String>[
        if (canOpenNpcVendors) 'Show NPC vendors',
        if (canOpenManual) manualActionLabel,
        if (canAddToChecklist) 'Add to to-do list',
        if (canAddToPlannedNetwork) 'Add to planned network',
      ],
      actionDetails: <String>[
        if (canOpenNpcVendors) npcVendorDetail,
        if (canOpenManual) manualDetail,
        if (canAddToChecklist) checklistDetail,
        if (canAddToPlannedNetwork) plannedNetworkDetail,
      ],
    );
    final selected = await showMenu<_PlannerMapQuickAction>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      color: spec.palette.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 18,
      constraints: BoxConstraints.tightFor(width: menuWidth),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(spec.geometry.cardRadius),
        side: BorderSide(color: spec.palette.trim.withAlpha(132)),
      ),
      items: <PopupMenuEntry<_PlannerMapQuickAction>>[
        if (canOpenNpcVendors)
          PopupMenuItem<_PlannerMapQuickAction>(
            key: PlannerActionKeys.mapLookupAction(
              widget.stableId,
              PlannerMapLookupSource.npcVendors.name,
            ),
            value: _PlannerMapQuickAction.npcVendors,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: PlannerMapMenuLabel(
              emblem: PlannerMapEmblem.npc,
              label: 'Show NPC vendors',
              detail: npcVendorDetail,
            ),
          ),
        if (canOpenNpcVendors && canOpenManual)
          const PopupMenuDivider(height: 1),
        if (canOpenManual)
          PopupMenuItem<_PlannerMapQuickAction>(
            key: PlannerActionKeys.mapLookupAction(
              widget.stableId,
              PlannerMapLookupSource.manualGathering.name,
            ),
            value: _PlannerMapQuickAction.manualGathering,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: PlannerMapMenuLabel(
              emblem: PlannerMapEmblem.gathering,
              label: manualActionLabel,
              detail: manualDetail,
            ),
          ),
        if ((canOpenNpcVendors || canOpenManual) &&
            (canAddToChecklist || canAddToPlannedNetwork))
          const PopupMenuDivider(height: 1),
        if (canAddToChecklist)
          PopupMenuItem<_PlannerMapQuickAction>(
            key: PlannerActionKeys.mapLookupAction(
              widget.stableId,
              'addToGatherChecklist',
            ),
            value: _PlannerMapQuickAction.addToGatherChecklist,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: const PlannerMapMenuLabel(
              emblem: PlannerMapEmblem.checklist,
              label: 'Add to to-do list',
              detail: checklistDetail,
            ),
          ),
        if (canAddToChecklist && canAddToPlannedNetwork)
          const PopupMenuDivider(height: 1),
        if (canAddToPlannedNetwork)
          PopupMenuItem<_PlannerMapQuickAction>(
            key: PlannerActionKeys.mapLookupAction(
              widget.stableId,
              'addToPlannedNetwork',
            ),
            value: _PlannerMapQuickAction.addToPlannedNetwork,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: PlannerMapMenuLabel(
              emblem: PlannerMapEmblem.network,
              label: 'Add to planned network',
              detail: plannedNetworkDetail,
            ),
          ),
      ],
    );
    if (selected == null || !mounted) return;
    if (selected == _PlannerMapQuickAction.addToGatherChecklist) {
      widget.externalActions.addToGatherChecklist?.call(
        PlannerGatherChecklistRequest(
          availability: availability,
          demand: widget.resolveGatherDemand?.call(),
        ),
      );
      return;
    }
    if (selected == _PlannerMapQuickAction.addToPlannedNetwork) {
      widget.externalActions.addToPlannedNetwork?.call(availability);
      return;
    }
    final source = selected == _PlannerMapQuickAction.npcVendors
        ? PlannerMapLookupSource.npcVendors
        : PlannerMapLookupSource.manualGathering;
    opener?.call(
      PlannerMapLookupRequest(
        materialName: availability.materialName,
        resourceId: availability.resourceIdFor(source),
        source: source,
      ),
    );
  }
}
