import 'package:flutter/material.dart';

import 'resource_map_chrome_theme.dart';
import 'resource_map_field_desk.dart';
import 'resource_map_menu_artwork.dart';
import 'resource_map_panel_metrics.dart';
import 'resource_map_pill.dart';

/// Task-first map navigation. The host owns search, backing and scrolling.
class ResourceMapDiscoveryHome extends StatefulWidget {
  const ResourceMapDiscoveryHome({
    super.key,
    required this.onFindMaterial,
    required this.onWorkerIncome,
    required this.onSaved,
    required this.onTodoList,
    required this.onPlanMaterials,
    required this.onBrowseWorkerNodes,
    required this.onSetup,
    this.onHouses,
    this.onPlannerNeeds,
    this.selectedAction,
    this.planArtwork,
  });

  final VoidCallback onFindMaterial;
  final VoidCallback onWorkerIncome;
  final VoidCallback onSaved;
  final VoidCallback onTodoList;
  final VoidCallback onPlanMaterials;
  final VoidCallback onBrowseWorkerNodes;
  final VoidCallback onSetup;
  final VoidCallback? onHouses;
  final VoidCallback? onPlannerNeeds;
  final String? selectedAction;
  final Widget? planArtwork;

  @override
  State<ResourceMapDiscoveryHome> createState() =>
      _ResourceMapDiscoveryHomeState();
}

class _ResourceMapDiscoveryHomeState extends State<ResourceMapDiscoveryHome> {
  bool _moreToolsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    const duration = Duration(milliseconds: 180);
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DiscoveryAction(
                key: const ValueKey('resource-map-home-find-material'),
                artwork: ResourceMapMenuArtworkKind.materials,
                title: 'Materials',
                selected: widget.selectedAction == 'find-material',
                compact: true,
                onPressed: widget.onFindMaterial,
              ),
              const SizedBox(height: 7),
              _DiscoveryAction(
                key: const ValueKey('resource-map-home-worker-income'),
                artwork: ResourceMapMenuArtworkKind.income,
                title: widget.planArtwork == null ? 'Workers' : 'Plan',
                customArtwork: widget.planArtwork,
                selected: widget.selectedAction == 'worker-income',
                compact: true,
                onPressed: widget.onWorkerIncome,
              ),
              if (widget.onHouses case final onHouses?) ...[
                const SizedBox(height: 7),
                _DiscoveryAction(
                  key: const ValueKey('resource-map-home-houses'),
                  artwork: ResourceMapMenuArtworkKind.houses,
                  title: 'Houses',
                  selected: widget.selectedAction == 'houses',
                  compact: true,
                  onPressed: onHouses,
                ),
              ],
              Divider(
                key: const ValueKey('resource-map-personal-shortcuts-divider'),
                height: 7,
                thickness: .5,
                indent: 10,
                endIndent: 10,
                color: chrome.readingOutline.withValues(
                  alpha: .34 * chrome.materialOpacity,
                ),
              ),
              _DiscoveryAction(
                key: const ValueKey('resource-map-home-saved'),
                artwork: ResourceMapMenuArtworkKind.saved,
                title: 'Saved',
                selected: widget.selectedAction == 'saved',
                compact: true,
                secondary: true,
                onPressed: widget.onSaved,
              ),
              const SizedBox(height: 7),
              _DiscoveryAction(
                key: const ValueKey('resource-map-home-checklist'),
                artwork: ResourceMapMenuArtworkKind.checklist,
                title: 'To-do list',
                selected: widget.selectedAction == 'checklist',
                compact: true,
                secondary: true,
                onPressed: widget.onTodoList,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              expanded: _moreToolsExpanded,
              child: TextButton.icon(
                key: const ValueKey('resource-map-home-more-tools'),
                onPressed: () =>
                    setState(() => _moreToolsExpanded = !_moreToolsExpanded),
                style: TextButton.styleFrom(
                  foregroundColor: chrome.muted,
                  backgroundColor: chrome.chromeBase,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(chrome.controlRadius),
                    side: BorderSide(color: chrome.softOutline),
                  ),
                  minimumSize: const Size(
                    0,
                    ResourceMapPanelMetrics.controlTarget,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: chrome.headingStyle(
                    fontSize: ResourceMapPanelMetrics.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                icon: reducedMotion
                    ? Icon(
                        _moreToolsExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 22,
                      )
                    : AnimatedRotation(
                        turns: _moreToolsExpanded ? 0.5 : 0,
                        duration: duration,
                        child: const Icon(Icons.expand_more, size: 22),
                      ),
                label: const Text('More tools'),
              ),
            ),
          ),
          if (reducedMotion)
            _buildMoreTools()
          else
            AnimatedSize(
              duration: duration,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topLeft,
              child: _buildMoreTools(),
            ),
        ],
      ),
    );
  }

  Widget _buildMoreTools() => _moreToolsExpanded
      ? Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onPlannerNeeds case final onPlannerNeeds?)
              _DiscoveryAction(
                key: const ValueKey('resource-map-home-plan-needs'),
                artwork: ResourceMapMenuArtworkKind.plan,
                title: 'Needed for your plan',
                onPressed: onPlannerNeeds,
              ),
            _DiscoveryAction(
              key: const ValueKey('resource-map-home-plan-materials'),
              artwork: ResourceMapMenuArtworkKind.plan,
              title: 'Plan materials',
              onPressed: widget.onPlanMaterials,
            ),
            _DiscoveryAction(
              key: const ValueKey('resource-map-home-browse-nodes'),
              artwork: ResourceMapMenuArtworkKind.findNodes,
              title: 'Browse worker nodes',
              onPressed: widget.onBrowseWorkerNodes,
            ),
            _DiscoveryAction(
              key: const ValueKey('resource-map-home-setup'),
              artwork: ResourceMapMenuArtworkKind.connections,
              title: 'Your setup',
              onPressed: widget.onSetup,
            ),
          ],
        )
      : const SizedBox.shrink();
}

class _DiscoveryAction extends StatelessWidget {
  const _DiscoveryAction({
    super.key,
    required this.artwork,
    required this.title,
    required this.onPressed,
    this.compact = false,
    this.selected = false,
    this.secondary = false,
    this.customArtwork,
  });

  final ResourceMapMenuArtworkKind artwork;
  final String title;
  final VoidCallback onPressed;
  final bool compact;
  final bool selected;
  final bool secondary;
  final Widget? customArtwork;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      bottom: compact ? 0 : ResourceMapPanelMetrics.optionGap,
    ),
    child: ResourceMapPill(
      selected: selected,
      quiet: secondary,
      leadingWidth: compact ? 52 : 48,
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: ResourceMapPanelMetrics.optionHeight,
            ),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                compact ? 10 : 6,
                7,
                8,
                7,
              ),
              child: Row(
                children: [
                  ResourceMapArtworkMount(
                    size: compact ? 30 : ResourceMapPanelMetrics.optionArtwork,
                    child:
                        customArtwork ??
                        ResourceMapMenuArtwork(
                          kind: artwork,
                          size: compact
                              ? 30
                              : ResourceMapPanelMetrics.optionArtwork,
                        ),
                  ),
                  SizedBox(width: compact ? 20 : 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: context.mapChrome.ink,
                        fontSize: ResourceMapPanelMetrics.optionLabel,
                        fontWeight: secondary
                            ? FontWeight.w600
                            : FontWeight.w700,
                        height: 1.12,
                      ),
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: context.mapChrome.muted,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
