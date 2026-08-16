import 'package:flutter/material.dart';

import 'draggable_dialog_surface.dart';
import 'resource_map_chrome_theme.dart';

const Color _nodePanelSurface = Color(0xFA171419);
const Color _nodePanelSurfaceRaised = Color(0xFA2A2229);
const Color _nodePanelInset = Color(0xF0100D11);
const Color _nodePanelOutline = Color(0xFF765C61);
const Color _nodePanelDivider = Color(0xCC594349);
const double _nodePanelRadius = 14;

@immutable
class _NodePanelPalette {
  const _NodePanelPalette({
    required this.surface,
    required this.inset,
    required this.outline,
    required this.divider,
    required this.shadowColor,
    required this.gradient,
    required this.radius,
  });

  factory _NodePanelPalette.from(ResourceMapChromeThemeData chrome) {
    if (chrome.variant == ResourceMapChromeThemeVariant.sakuraCartographer) {
      return const _NodePanelPalette(
        surface: _nodePanelSurface,
        inset: _nodePanelInset,
        outline: _nodePanelOutline,
        divider: _nodePanelDivider,
        shadowColor: Color(0x8F000000),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[_nodePanelSurfaceRaised, _nodePanelSurface],
        ),
        radius: _nodePanelRadius,
      );
    }
    return _NodePanelPalette(
      surface: chrome.chromeBase.withValues(alpha: .98),
      inset: chrome.canvas.withValues(alpha: .94),
      outline: chrome.warmOutline,
      divider: chrome.divider,
      shadowColor: chrome.idleShadow.color,
      gradient: chrome.surfaceGradient,
      radius: chrome.surfaceRadius,
    );
  }

  final Color surface;
  final Color inset;
  final Color outline;
  final Color divider;
  final Color shadowColor;
  final Gradient gradient;
  final double radius;
}

/// Controls where the small map-anchor pointer is drawn.
enum ResourceMapNodeQuickPanelTailAlignment {
  none,
  start,
  center,
  end,
  leftCenter,
  rightCenter,
}

/// One item produced by a worker node.
///
/// [icon] may be an item image, an in-game-inspired vector icon, or any other
/// compact widget. A neutral resource icon is used when it is omitted.
class ResourceMapNodeOutput {
  const ResourceMapNodeOutput({
    required this.name,
    this.id,
    this.icon,
    this.onPressed,
  });

  final String? id;
  final String name;
  final Widget? icon;
  final VoidCallback? onPressed;
}

/// One directly reachable node shown inside the selected node flyout.
class ResourceMapNodeLink {
  const ResourceMapNodeLink({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onPressed,
  });

  final String id;
  final String title;
  final String subtitle;
  final Widget icon;
  final VoidCallback onPressed;
}

/// Optional, compact unlock guidance shown inside a node summary.
class ResourceMapNodeUnlockNotice {
  const ResourceMapNodeUnlockNotice({
    required this.managerName,
    required this.instructions,
    this.managerMarkerVisible = false,
    this.onToggleManagerMarker,
  }) : assert(
         !managerMarkerVisible || onToggleManagerMarker != null,
         'A visible manager marker must be dismissible.',
       );

  final String managerName;
  final String instructions;
  final bool managerMarkerVisible;

  /// Toggles an exact, already verified manager location on the map.
  ///
  /// Leave this null when the manager identity is known but their current
  /// game-world coordinates have not been verified.
  final VoidCallback? onToggleManagerMarker;
}

/// Optional actions for a city or town selected directly on the map.
class ResourceMapTownQuickActions {
  const ResourceMapTownQuickActions({
    this.onOpenRoyalWorkshops,
    this.onOpenWorkersAndStorage,
    this.onOpenHouses,
  }) : assert(
         onOpenRoyalWorkshops != null ||
             onOpenWorkersAndStorage != null ||
             onOpenHouses != null,
         'At least one town action is required.',
       );

  final VoidCallback? onOpenRoyalWorkshops;
  final VoidCallback? onOpenWorkersAndStorage;
  final VoidCallback? onOpenHouses;
}

/// A compact, map-anchored summary shown after selecting a node.
///
/// The panel deliberately keeps the map visible and presents only the actions
/// that are useful at the selected node. It does not move or control the map
/// camera; the parent owns selection and positioning.
class ResourceMapNodeQuickPanel extends StatelessWidget {
  const ResourceMapNodeQuickPanel({
    required this.nodeName,
    required this.nodeType,
    required this.contributionPoints,
    required this.outputs,
    required this.invested,
    required this.onToggleInvested,
    required this.onClose,
    this.onBack,
    this.backLabel,
    this.region,
    this.workTime,
    this.workloadLabel,
    this.workerSiteCount,
    this.availableWorkerNodes = const <ResourceMapNodeLink>[],
    this.connectedFrom,
    this.workerPathVisible = false,
    this.onToggleWorkerPath,
    this.provenance,
    this.onPreviewRoute,
    this.onAddCompleteRoute,
    this.completeRouteContributionPoints,
    this.unlockNotice,
    this.townActions,
    this.tailAlignment = ResourceMapNodeQuickPanelTailAlignment.center,
    this.sideTailOffset,
    super.key,
  }) : assert(contributionPoints >= 0),
       assert(workerSiteCount == null || workerSiteCount >= 0),
       assert(sideTailOffset == null || sideTailOffset >= 0);

  final String nodeName;
  final String nodeType;
  final int contributionPoints;
  final String? region;
  final Duration? workTime;
  final String? workloadLabel;
  final int? workerSiteCount;
  final List<ResourceMapNodeOutput> outputs;
  final List<ResourceMapNodeLink> availableWorkerNodes;
  final ResourceMapNodeLink? connectedFrom;
  final bool workerPathVisible;
  final VoidCallback? onToggleWorkerPath;
  final String? provenance;
  final bool invested;
  final VoidCallback onToggleInvested;
  final VoidCallback? onPreviewRoute;
  final VoidCallback? onAddCompleteRoute;
  final int? completeRouteContributionPoints;
  final ResourceMapNodeUnlockNotice? unlockNotice;
  final ResourceMapTownQuickActions? townActions;
  final VoidCallback? onBack;
  final String? backLabel;
  final VoidCallback onClose;
  final ResourceMapNodeQuickPanelTailAlignment tailAlignment;

  /// Vertical center of a left/right pointer inside the panel.
  ///
  /// The parent supplies this when the panel was clamped against a viewport
  /// edge, keeping the pointer aligned with the selected map marker.
  final double? sideTailOffset;

  static const double maxWidth = 356;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final panel = _NodePanelPalette.from(chrome);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: '$nodeName, $nodeType',
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Material(
              key: const ValueKey<String>('resource-map-node-quick-panel'),
              color: Colors.transparent,
              elevation: 12,
              shadowColor: panel.shadowColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(panel.radius),
                side: BorderSide(color: panel.outline),
              ),
              clipBehavior: Clip.antiAlias,
              child: DecoratedBox(
                key: const ValueKey<String>(
                  'resource-map-node-quick-panel-accent',
                ),
                decoration: BoxDecoration(gradient: panel.gradient),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(
                        height: 2,
                        child: ColoredBox(color: chrome.accent),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _NodeHeader(
                              nodeName: nodeName,
                              nodeType: nodeType,
                              region: region,
                              invested: invested,
                              onBack: onBack,
                              backLabel: backLabel,
                              onClose: onClose,
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: <Widget>[
                                _NodeFact(
                                  icon: Icons.stars_rounded,
                                  label: '$contributionPoints CP',
                                ),
                                if (workTime != null)
                                  _NodeFact(
                                    icon: Icons.schedule_rounded,
                                    label: _formatDuration(workTime!),
                                  ),
                                if (workloadLabel case final workload?
                                    when workload.trim().isNotEmpty)
                                  _NodeFact(
                                    icon: Icons.schedule_rounded,
                                    label: workload.trim(),
                                  ),
                                if (workerSiteCount case final count?
                                    when count > 0)
                                  _NodeFact(
                                    icon:
                                        Icons.precision_manufacturing_outlined,
                                    label:
                                        '$count worker ${count == 1 ? 'site' : 'sites'}',
                                  ),
                              ],
                            ),
                            if (townActions case final actions?) ...<Widget>[
                              const SizedBox(height: 8),
                              if (actions.onOpenRoyalWorkshops != null)
                                _NodeActionRow(
                                  key: const ValueKey<String>(
                                    'resource-map-town-open-royal-workshops',
                                  ),
                                  icon: Icons.auto_awesome_mosaic_outlined,
                                  label: 'Open Royal Workshops',
                                  semanticLabel:
                                      'Open Royal Workshops in $nodeName',
                                  onPressed: actions.onOpenRoyalWorkshops!,
                                ),
                              if (actions.onOpenWorkersAndStorage != null)
                                _NodeActionRow(
                                  key: const ValueKey<String>(
                                    'resource-map-town-open-workers-storage',
                                  ),
                                  icon: Icons.groups_2_outlined,
                                  label: 'Yukjo workers & storage',
                                  semanticLabel:
                                      'Open Yukjo workers and storage in '
                                      '$nodeName',
                                  onPressed: actions.onOpenWorkersAndStorage!,
                                ),
                              if (actions.onOpenHouses != null)
                                _NodeActionRow(
                                  key: const ValueKey<String>(
                                    'resource-map-town-open-houses',
                                  ),
                                  icon: Icons.holiday_village_outlined,
                                  label: 'Houses',
                                  semanticLabel: 'Open houses in $nodeName',
                                  onPressed: actions.onOpenHouses!,
                                ),
                            ],
                            if (outputs.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 8),
                              const _NodeSectionHeading(label: 'Produces'),
                              const SizedBox(height: 5),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: panel.inset,
                                  border: Border(
                                    top: BorderSide(color: panel.divider),
                                    bottom: BorderSide(color: panel.divider),
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    for (
                                      var index = 0;
                                      index < outputs.length;
                                      index += 1
                                    )
                                      _NodeOutputRow(
                                        output: outputs[index],
                                        showDivider: index < outputs.length - 1,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                            if (availableWorkerNodes.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 12),
                              _NodeSectionHeading(
                                label: 'Available worker nodes',
                                count: availableWorkerNodes.length,
                              ),
                              const SizedBox(height: 4),
                              for (final workerNode in availableWorkerNodes)
                                _NodeLinkRow(
                                  key: ValueKey<String>(
                                    'resource-map-node-worker-site-'
                                    '${workerNode.id}',
                                  ),
                                  link: workerNode,
                                ),
                            ],
                            if (connectedFrom case final parent?) ...<Widget>[
                              const SizedBox(height: 10),
                              if (onToggleWorkerPath != null)
                                _NodeActionRow(
                                  key: const ValueKey<String>(
                                    'resource-map-worker-path-toggle',
                                  ),
                                  icon: workerPathVisible
                                      ? Icons.visibility_off_outlined
                                      : Icons.polyline_outlined,
                                  label: workerPathVisible
                                      ? 'Hide worker path'
                                      : 'Show worker path',
                                  semanticLabel: workerPathVisible
                                      ? 'Hide worker path from $nodeName'
                                      : 'Show worker path from $nodeName',
                                  onPressed: onToggleWorkerPath!,
                                ),
                              const _NodeSectionHeading(
                                label: 'Connected from',
                              ),
                              const SizedBox(height: 4),
                              _NodeLinkRow(
                                key: ValueKey<String>(
                                  'resource-map-node-connected-from-'
                                  '${parent.id}',
                                ),
                                link: parent,
                              ),
                            ],
                            if (unlockNotice case final notice?) ...<Widget>[
                              const SizedBox(height: 10),
                              _NodeUnlockNotice(notice: notice),
                            ],
                            if (provenance case final source?
                                when source.trim().isNotEmpty) ...<Widget>[
                              const SizedBox(height: 10),
                              _NodeProvenance(text: source.trim()),
                            ],
                            const SizedBox(height: 14),
                            if (onAddCompleteRoute != null)
                              Semantics(
                                button: true,
                                label: 'Add complete route to $nodeName',
                                child: ExcludeSemantics(
                                  child: FilledButton.icon(
                                    key: const ValueKey<String>(
                                      'resource-map-node-add-route',
                                    ),
                                    onPressed: onAddCompleteRoute,
                                    icon: const Icon(
                                      Icons.route_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      completeRouteContributionPoints == null
                                          ? 'Add complete route'
                                          : 'Add complete route  +'
                                                '$completeRouteContributionPoints CP',
                                    ),
                                    style: _primaryActionStyle(
                                      chrome,
                                      chrome.accent,
                                    ),
                                  ),
                                ),
                              )
                            else
                              Semantics(
                                button: true,
                                label: invested
                                    ? 'Remove $nodeName from my setup'
                                    : 'Mark $nodeName as already invested',
                                child: ExcludeSemantics(
                                  child: FilledButton.icon(
                                    key: const ValueKey<String>(
                                      'resource-map-node-toggle-invested',
                                    ),
                                    onPressed: onToggleInvested,
                                    icon: Icon(
                                      invested
                                          ? Icons.bookmark_remove_rounded
                                          : Icons.bookmark_add_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      invested
                                          ? 'Remove from my setup'
                                          : 'Mark as invested',
                                    ),
                                    style: _primaryActionStyle(
                                      chrome,
                                      invested
                                          ? chrome.positive
                                          : chrome.accent,
                                    ),
                                  ),
                                ),
                              ),
                            if (onPreviewRoute != null ||
                                onAddCompleteRoute != null) ...<Widget>[
                              const SizedBox(height: 6),
                              if (onPreviewRoute != null)
                                _NodeActionRow(
                                  key: const ValueKey<String>(
                                    'resource-map-node-preview-route',
                                  ),
                                  icon: Icons.route_outlined,
                                  label: 'Preview complete route',
                                  semanticLabel:
                                      'Preview complete route to $nodeName',
                                  onPressed: onPreviewRoute!,
                                ),
                              if (onAddCompleteRoute != null)
                                _NodeActionRow(
                                  key: const ValueKey<String>(
                                    'resource-map-node-toggle-invested',
                                  ),
                                  icon: invested
                                      ? Icons.bookmark_remove_outlined
                                      : Icons.bookmark_add_outlined,
                                  label: invested
                                      ? 'Remove from my setup'
                                      : 'Mark as already invested',
                                  semanticLabel: invested
                                      ? 'Remove $nodeName from my setup'
                                      : 'Mark $nodeName as already invested',
                                  onPressed: onToggleInvested,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _tail(panel),
          ],
        ),
      ),
    );
  }

  ButtonStyle _primaryActionStyle(
    ResourceMapChromeThemeData chrome,
    Color backgroundColor,
  ) {
    return FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      foregroundColor: chrome.onPrimary,
      backgroundColor: backgroundColor,
      disabledForegroundColor: chrome.muted,
      disabledBackgroundColor: chrome.paper,
      overlayColor: Colors.white.withValues(alpha: .09),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(chrome.inlineRadius),
      ),
      elevation: 0,
      textStyle: const TextStyle(
        fontSize: 13,
        height: 1.15,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _tail(_NodePanelPalette panel) {
    final tail = CustomPaint(
      key: const ValueKey<String>('resource-map-node-quick-panel-tail'),
      size: const Size(20, 10),
      painter: _NodeQuickPanelTailPainter(
        surface: panel.surface,
        outline: panel.outline,
      ),
    );
    return switch (tailAlignment) {
      ResourceMapNodeQuickPanelTailAlignment.none => const SizedBox.shrink(),
      ResourceMapNodeQuickPanelTailAlignment.start => Positioned(
        left: 28,
        bottom: -8,
        child: tail,
      ),
      ResourceMapNodeQuickPanelTailAlignment.center => Positioned(
        left: 0,
        right: 0,
        bottom: -8,
        child: Center(child: tail),
      ),
      ResourceMapNodeQuickPanelTailAlignment.end => Positioned(
        right: 28,
        bottom: -8,
        child: tail,
      ),
      ResourceMapNodeQuickPanelTailAlignment.leftCenter =>
        sideTailOffset == null
            ? Positioned(
                left: -8,
                top: 0,
                bottom: 0,
                child: Center(child: RotatedBox(quarterTurns: 1, child: tail)),
              )
            : Positioned(
                left: -8,
                top: sideTailOffset! - 10,
                child: RotatedBox(quarterTurns: 1, child: tail),
              ),
      ResourceMapNodeQuickPanelTailAlignment.rightCenter =>
        sideTailOffset == null
            ? Positioned(
                right: -8,
                top: 0,
                bottom: 0,
                child: Center(child: RotatedBox(quarterTurns: 3, child: tail)),
              )
            : Positioned(
                right: -8,
                top: sideTailOffset! - 10,
                child: RotatedBox(quarterTurns: 3, child: tail),
              ),
    };
  }

  static String _formatDuration(Duration duration) {
    final totalMinutes = duration.inMinutes;
    if (totalMinutes < 1) {
      return '< 1 min';
    }
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes.remainder(60);
    if (hours == 0) {
      return '$minutes min';
    }
    if (minutes == 0) {
      return '${hours}h';
    }
    return '${hours}h ${minutes}m';
  }
}

class _NodeHeader extends StatelessWidget {
  const _NodeHeader({
    required this.nodeName,
    required this.nodeType,
    required this.region,
    required this.invested,
    required this.onBack,
    required this.backLabel,
    required this.onClose,
  });

  final String nodeName;
  final String nodeType;
  final String? region;
  final bool invested;
  final VoidCallback? onBack;
  final String? backLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final trimmedRegion = region?.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (onBack != null) ...<Widget>[
          Semantics(
            button: true,
            label: backLabel == null
                ? 'Back to previous map selection'
                : 'Back to $backLabel',
            child: ExcludeSemantics(
              child: IconButton(
                key: const ValueKey<String>('resource-map-node-quick-back'),
                onPressed: onBack,
                tooltip: backLabel == null ? 'Back' : 'Back to $backLabel',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 38,
                ),
                color: chrome.primary,
                iconSize: 19,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: DraggableDialogDragHandle(
            key: const ValueKey<String>('resource-map-node-quick-drag-handle'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  nodeName,
                  style: TextStyle(
                    color: chrome.ink,
                    fontFamily: chrome.headingFontFamily,
                    fontSize: 17,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.05,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  trimmedRegion == null || trimmedRegion.isEmpty
                      ? nodeType
                      : '$nodeType · $trimmedRegion',
                  style: TextStyle(
                    color: chrome.muted,
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (invested) ...<Widget>[
                  const SizedBox(height: 7),
                  Semantics(
                    label: 'Node is currently invested',
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: chrome.positive,
                              shape: BoxShape.circle,
                            ),
                            child: SizedBox.square(dimension: 7),
                          ),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Invested',
                              style: TextStyle(
                                color: chrome.positive,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        Semantics(
          button: true,
          label: 'Close node summary',
          child: ExcludeSemantics(
            child: IconButton(
              key: const ValueKey<String>('resource-map-node-panel-close'),
              onPressed: onClose,
              tooltip: 'Close',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 38, height: 38),
              color: chrome.ink,
              iconSize: 19,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ),
      ],
    );
  }
}

class _NodeFact extends StatelessWidget {
  const _NodeFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final panel = _NodePanelPalette.from(chrome);
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: panel.inset,
            borderRadius: BorderRadius.circular(5),
            border: Border(left: BorderSide(color: chrome.brassLine, width: 2)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 15, color: chrome.accent),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: chrome.text,
                    fontSize: 12.5,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NodeSectionHeading extends StatelessWidget {
  const _NodeSectionHeading({required this.label, this.count});

  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return Text(
      (count == null ? label : '$label · $count').toUpperCase(),
      style: TextStyle(
        color: chrome.muted,
        fontSize: 10.5,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: .8,
      ),
    );
  }
}

class _NodeOutputRow extends StatelessWidget {
  const _NodeOutputRow({required this.output, required this.showDivider});

  final ResourceMapNodeOutput output;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final panel = _NodePanelPalette.from(chrome);
    final content = Container(
      constraints: const BoxConstraints(minHeight: 35),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: panel.divider))
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox.square(
            key: ValueKey<String>(
              'resource-map-node-output-artwork-${output.id ?? output.name}',
            ),
            dimension: 28,
            child: Center(
              child:
                  output.icon ??
                  Icon(
                    Icons.image_not_supported_outlined,
                    key: ValueKey<String>(
                      'resource-map-node-output-missing-artwork',
                    ),
                    size: 17,
                    color: chrome.muted,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              output.name,
              style: TextStyle(
                color: chrome.text,
                fontSize: 13,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (output.onPressed != null)
            Icon(Icons.chevron_right_rounded, size: 18, color: chrome.primary),
        ],
      ),
    );
    return Semantics(
      key: ValueKey<String>(
        'resource-map-node-output-${output.id ?? output.name}',
      ),
      button: output.onPressed != null,
      label: 'Produces ${output.name}',
      child: ExcludeSemantics(
        child: output.onPressed == null
            ? content
            : Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: output.onPressed,
                  hoverColor: chrome.primary.withValues(alpha: .08),
                  highlightColor: chrome.primary.withValues(alpha: .13),
                  child: content,
                ),
              ),
      ),
    );
  }
}

class _NodeLinkRow extends StatelessWidget {
  const _NodeLinkRow({required this.link, super.key});

  final ResourceMapNodeLink link;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return Semantics(
      button: true,
      label: '${link.title}. ${link.subtitle}',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: link.onPressed,
            hoverColor: chrome.primary.withValues(alpha: .08),
            highlightColor: chrome.primary.withValues(alpha: .13),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox.square(
                    dimension: 25,
                    child: Center(child: link.icon),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          link.title,
                          style: TextStyle(
                            color: chrome.ink,
                            fontFamily: chrome.headingFontFamily,
                            fontSize: 12.5,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (link.subtitle.trim().isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            link.subtitle,
                            style: TextStyle(
                              color: chrome.muted,
                              fontSize: 11.25,
                              height: 1.3,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: chrome.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NodeProvenance extends StatelessWidget {
  const _NodeProvenance({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.folder_open_outlined,
            size: 15,
            color: chrome.muted,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: chrome.muted,
              fontSize: 10.75,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _NodeActionRow extends StatelessWidget {
  const _NodeActionRow({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            hoverColor: chrome.primary.withValues(alpha: .08),
            highlightColor: chrome.primary.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Row(
                children: <Widget>[
                  Icon(icon, size: 18, color: chrome.primary),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: chrome.text,
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: chrome.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NodeUnlockNotice extends StatelessWidget {
  const _NodeUnlockNotice({required this.notice});

  final ResourceMapNodeUnlockNotice notice;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final markerAction = notice.onToggleManagerMarker;
    return Semantics(
      container: true,
      label: 'Excavation unlock help. ${notice.instructions}',
      child: DecoratedBox(
        key: const ValueKey<String>('resource-map-node-unlock-notice'),
        decoration: BoxDecoration(
          color: chrome.warning.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(chrome.inlineRadius),
          border: Border.all(color: chrome.warning.withValues(alpha: .34)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.lock_open_rounded,
                  size: 18,
                  color: chrome.warning,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'EXCAVATION ACCESS',
                      style: TextStyle(
                        color: chrome.warning,
                        fontFamily: chrome.headingFontFamily,
                        fontSize: 10.5,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .65,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notice.instructions,
                      style: TextStyle(
                        color: chrome.text,
                        fontSize: 12.25,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (markerAction != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const ValueKey<String>(
                            'resource-map-node-toggle-manager-marker',
                          ),
                          onPressed: markerAction,
                          icon: Icon(
                            notice.managerMarkerVisible
                                ? Icons.location_off_outlined
                                : Icons.add_location_alt_outlined,
                            size: 17,
                          ),
                          label: Text(
                            notice.managerMarkerVisible
                                ? 'Hide ${notice.managerName}'
                                : 'Mark ${notice.managerName} on map',
                            style: const TextStyle(
                              decoration: TextDecoration.underline,
                              decorationThickness: 1.25,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: chrome.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 7,
                            ),
                            minimumSize: const Size(0, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            alignment: Alignment.centerLeft,
                            textStyle: const TextStyle(
                              fontSize: 12.5,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small map dot used to identify an exact manager location.
///
/// Positioning is owned by the map surface. This widget never changes the
/// camera and intentionally stays compact so it does not obscure nearby nodes.
class ResourceMapManagerMarker extends StatelessWidget {
  const ResourceMapManagerMarker({
    required this.managerName,
    this.contextLabel = 'manager location',
    super.key,
  });

  final String managerName;
  final String contextLabel;

  static const double size = 30;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return Semantics(
      key: const ValueKey<String>('resource-map-manager-marker'),
      label: '$managerName, $contextLabel',
      child: Tooltip(
        message: '$managerName · $contextLabel',
        child: RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: chrome.canvas.withValues(alpha: .9),
              shape: BoxShape.circle,
              border: Border.all(color: chrome.warning, width: 2),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 7,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: SizedBox.square(
              dimension: size,
              child: Icon(
                Icons.person_pin_circle_rounded,
                size: 20,
                color: chrome.warning,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NodeQuickPanelTailPainter extends CustomPainter {
  const _NodeQuickPanelTailPainter({
    required this.surface,
    required this.outline,
  });

  final Color surface;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = surface
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_NodeQuickPanelTailPainter oldDelegate) =>
      surface != oldDelegate.surface || outline != oldDelegate.outline;
}
