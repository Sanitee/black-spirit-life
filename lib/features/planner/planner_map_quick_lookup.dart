import 'package:flutter/material.dart';

import '../../shared/overlays/anchored_popover.dart';
import '../../visual/visual.dart';
import 'planner_contracts.dart';
import 'planner_keys.dart';

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
    super.key,
  });

  final String materialName;
  final String stableId;
  final PlannerExternalActions externalActions;
  final Widget child;

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
    final menuWidth = _plannerMapLookupMenuWidth(
      context: context,
      viewportSize: overlay.size,
      actionLabels: <String>[
        if (canOpenNpcVendors) 'Show NPC vendors',
        if (canOpenManual) manualActionLabel,
        if (canAddToChecklist) 'Add to checklist',
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
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: _PlannerMapLookupMenuLabel(
              icon: Icons.storefront_rounded,
              tone: AppSurfaceTone.info,
              label: 'Show NPC vendors',
              detail: npcVendorDetail,
            ),
          ),
        if (canOpenManual)
          PopupMenuItem<_PlannerMapQuickAction>(
            key: PlannerActionKeys.mapLookupAction(
              widget.stableId,
              PlannerMapLookupSource.manualGathering.name,
            ),
            value: _PlannerMapQuickAction.manualGathering,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: _PlannerMapLookupMenuLabel(
              icon: Icons.location_on_rounded,
              tone: AppSurfaceTone.warning,
              label: manualActionLabel,
              detail: manualDetail,
            ),
          ),
        if ((canOpenNpcVendors || canOpenManual) &&
            (canAddToChecklist || canAddToPlannedNetwork))
          const PopupMenuDivider(height: 8),
        if (canAddToChecklist)
          PopupMenuItem<_PlannerMapQuickAction>(
            key: PlannerActionKeys.mapLookupAction(
              widget.stableId,
              'addToGatherChecklist',
            ),
            value: _PlannerMapQuickAction.addToGatherChecklist,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: const _PlannerMapLookupMenuLabel(
              icon: Icons.checklist_rounded,
              tone: AppSurfaceTone.success,
              label: 'Add to checklist',
              detail: checklistDetail,
            ),
          ),
        if (canAddToPlannedNetwork)
          PopupMenuItem<_PlannerMapQuickAction>(
            key: PlannerActionKeys.mapLookupAction(
              widget.stableId,
              'addToPlannedNetwork',
            ),
            value: _PlannerMapQuickAction.addToPlannedNetwork,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: _PlannerMapLookupMenuLabel(
              icon: Icons.account_tree_rounded,
              tone: AppSurfaceTone.info,
              label: 'Add to planned network',
              detail: plannedNetworkDetail,
            ),
          ),
      ],
    );
    if (selected == null || !mounted) return;
    if (selected == _PlannerMapQuickAction.addToGatherChecklist) {
      widget.externalActions.addToGatherChecklist?.call(availability);
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

const _plannerMapLookupMenuHorizontalChrome = 104.0;
const _plannerMapLookupMenuViewportPadding = 8.0;

TextStyle _plannerMapLookupActionStyle(ThemeSpec spec) =>
    spec.typography.body.copyWith(fontSize: 13.5, fontWeight: FontWeight.w800);

TextStyle _plannerMapLookupDetailStyle(ThemeSpec spec) => spec.typography.meta
    .copyWith(color: spec.palette.textMuted, fontSize: 10.5);

double _plannerMapLookupMenuWidth({
  required BuildContext context,
  required Size viewportSize,
  required Iterable<String> actionLabels,
  required Iterable<String> actionDetails,
}) {
  final spec = context.visualTheme;
  final textScaler = MediaQuery.textScalerOf(context);
  final textDirection = Directionality.of(context);

  double measure(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  var widestText = 0.0;
  for (final label in actionLabels) {
    final width = measure(label, _plannerMapLookupActionStyle(spec));
    if (width > widestText) widestText = width;
  }
  for (final detail in actionDetails) {
    final width = measure(detail, _plannerMapLookupDetailStyle(spec));
    if (width > widestText) widestText = width;
  }

  final viewportLimit =
      (viewportSize.width - 2 * _plannerMapLookupMenuViewportPadding).clamp(
        0.0,
        double.infinity,
      );
  if (viewportLimit == 0) return 0;
  final minimumWidth = viewportLimit < 286.0 ? viewportLimit : 286.0;
  return (widestText + _plannerMapLookupMenuHorizontalChrome)
      .clamp(minimumWidth, viewportLimit)
      .toDouble();
}

class _PlannerMapLookupMenuLabel extends StatefulWidget {
  const _PlannerMapLookupMenuLabel({
    required this.icon,
    required this.tone,
    required this.label,
    this.detail,
  });

  final IconData icon;
  final AppSurfaceTone tone;
  final String label;
  final String? detail;

  @override
  State<_PlannerMapLookupMenuLabel> createState() =>
      _PlannerMapLookupMenuLabelState();
}

class _PlannerMapLookupMenuLabelState
    extends State<_PlannerMapLookupMenuLabel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final focused = Focus.of(context).hasFocus;
    final highlighted = _hovered || focused;
    final accent = spec.palette.forTone(widget.tone);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              accent.withAlpha(highlighted ? 48 : 22),
              accent.withAlpha(highlighted ? 14 : 0),
            ],
          ),
          borderRadius: BorderRadius.circular(spec.geometry.buttonRadius),
          border: Border.all(
            color: highlighted
                ? accent.withAlpha(168)
                : spec.palette.trim.withAlpha(76),
          ),
          boxShadow: highlighted
              ? <BoxShadow>[
                  BoxShadow(
                    color: accent.withAlpha(46),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withAlpha(highlighted ? 78 : 42),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: accent.withAlpha(highlighted ? 210 : 132),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accent.withAlpha(highlighted ? 62 : 26),
                    blurRadius: highlighted ? 10 : 6,
                  ),
                ],
              ),
              child: Icon(widget.icon, size: 23, color: accent),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(widget.label, style: _plannerMapLookupActionStyle(spec)),
                  if (widget.detail case final detail?) ...<Widget>[
                    const SizedBox(height: 1),
                    Text(detail, style: _plannerMapLookupDetailStyle(spec)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: highlighted ? accent : spec.palette.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
