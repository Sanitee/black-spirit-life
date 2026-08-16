import 'package:flutter/material.dart';

import 'resource_map_chrome_theme.dart';

/// Shared Emberglass Cartographer colors for every app-owned map surface.
///
/// The palette deliberately separates the raised reading surfaces from the
/// map canvas without using bright paper panels. Consumers should use the
/// semantic role instead of deriving lighter or darker variants locally.
abstract final class ResourceMapAtlasColors {
  static const canvas = Color(0xFF100E12);
  static const paper = Color(0xFF171419);
  static const paperRaised = Color(0xFF211B22);
  static const ink = Color(0xFFF5EDDF);
  static const text = Color(0xFFD8C9BE);
  static const muted = Color(0xFFA18F86);
  static const warmOutline = Color(0x667A625B);
  static const softOutline = Color(0x995A4548);
  static const divider = softOutline;
  static const primary = Color(0xFFEAA083);
  static const tealDeep = Color(0xFF44252F);
  static const onPrimary = canvas;
  static const accent = Color(0xFFE6C174);
  static const positive = Color(0xFF7BD0A3);
  static const warning = Color(0xFFE7A764);
  static const error = Color(0xFFF07D84);

  // Emberglass Cartographer chrome. These roles sit alongside the stable atlas
  // colors above so existing map content keeps its established semantics while
  // app-owned controls read as one purpose-built instrument panel.
  static const graphite = Color(0xFF110F13);
  static const graphiteRaised = Color(0xFF211B20);
  static const graphiteHighlight = Color(0xFF33262D);
  static const brassDeep = Color(0xFF765746);
  static const brassLine = Color(0xFFC99969);
  static const brassWash = Color(0x28E6C174);
}

/// Shared timings for finite, interaction-owned map chrome motion.
///
/// These transitions never drive the basemap or schedule repeating frames.
/// Every caller resolves its duration through [duration] so the operating
/// system's reduced-motion preference is honored consistently.
abstract final class ResourceMapDesktopMotion {
  static const quick = Duration(milliseconds: 140);
  static const enter = Duration(milliseconds: 180);
  static const settle = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;

  static Duration duration(BuildContext context, Duration preferred) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : preferred;
}

/// A one-shot fade and short translation used when a compact control island
/// enters the tree. It does not affect layout or pointer hit testing.
class _ResourceMapDesktopEnterTransition extends StatelessWidget {
  const _ResourceMapDesktopEnterTransition({
    required this.child,
    this.beginOffset = const Offset(0, 4),
  });

  final Widget child;
  final Offset beginOffset;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: ResourceMapDesktopMotion.duration(
        context,
        ResourceMapDesktopMotion.enter,
      ),
      curve: ResourceMapDesktopMotion.curve,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: .82 + (.18 * value),
        child: Transform.translate(
          offset: Offset(
            beginOffset.dx * (1 - value),
            beginOffset.dy * (1 - value),
          ),
          transformHitTests: false,
          child: child,
        ),
      ),
    );
  }
}

/// The compact command islands used over the desktop map.
///
/// Search and each mode are separate content-backed surfaces. There is no
/// enclosing slab, so the map remains visible in the space between controls.
class ResourceMapDesktopCommandBar extends StatelessWidget {
  const ResourceMapDesktopCommandBar({
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onSearchTapped,
    required this.onClearSearch,
    required this.onGatherPressed,
    required this.onWorkersPressed,
    required this.gatherSelected,
    required this.workersSelected,
    super.key,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onSearchTapped;
  final VoidCallback onClearSearch;
  final VoidCallback onGatherPressed;
  final VoidCallback onWorkersPressed;
  final bool gatherSelected;
  final bool workersSelected;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final scaledLabel = MediaQuery.textScalerOf(context).scale(12.5);
    return Semantics(
      container: true,
      label: 'Resource map tools',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactModes = constraints.maxWidth < 600 || scaledLabel > 17.5;
          return SizedBox(
            key: const ValueKey<String>('resource-map-command-dock'),
            height: 50,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _MapSearchControl(
                    controller: searchController,
                    focusNode: searchFocusNode,
                    onChanged: onSearchChanged,
                    onSubmitted: onSearchSubmitted,
                    onTap: onSearchTapped,
                    onClear: onClearSearch,
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  key: const ValueKey<String>(
                    'resource-map-command-action-rail',
                  ),
                  color: Colors.transparent,
                  elevation: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _MapModeControl(
                        key: const ValueKey<String>(
                          'resource-map-command-gather',
                        ),
                        icon: Icons.location_on_outlined,
                        label: 'Gather',
                        selected: gatherSelected,
                        onPressed: onGatherPressed,
                        reduceMotion: reduceMotion,
                        showLabel: !compactModes,
                        labeledMinWidth: 112,
                      ),
                      const SizedBox(width: 6),
                      _MapModeControl(
                        key: const ValueKey<String>(
                          'resource-map-command-workers',
                        ),
                        icon: Icons.account_tree_outlined,
                        label: 'Workers',
                        selected: workersSelected,
                        onPressed: onWorkersPressed,
                        reduceMotion: reduceMotion,
                        showLabel: !compactModes,
                        labeledMinWidth: 112,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One task exposed by [ResourceMapDesktopModeActionStrip].
class ResourceMapDesktopModeAction {
  const ResourceMapDesktopModeAction({
    required this.icon,
    required this.label,
    this.onPressed,
    this.badge,
    this.selected = false,
    this.controlKey,
  });

  /// The icon can be an app-owned image or a Flutter [Icon].
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final String? badge;
  final bool selected;
  final Key? controlKey;
}

/// A borderless row of map tasks placed directly below the command dock.
///
/// Only the individual actions draw compact instrument-key surfaces; the strip
/// itself has no card, border, shadow, or background. When labels need more
/// room, compact edge controls make the horizontal overflow discoverable and
/// reachable without adding permanent panel chrome.
class ResourceMapDesktopModeActionStrip extends StatefulWidget {
  const ResourceMapDesktopModeActionStrip({
    required this.actions,
    this.controller,
    this.padding = EdgeInsets.zero,
    this.spacing = 8,
    this.semanticLabel = 'Resource map tasks',
    super.key,
  }) : assert(spacing >= 0);

  final List<ResourceMapDesktopModeAction> actions;
  final ScrollController? controller;
  final EdgeInsetsGeometry padding;
  final double spacing;
  final String semanticLabel;

  @override
  State<ResourceMapDesktopModeActionStrip> createState() =>
      _ResourceMapDesktopModeActionStripState();
}

class _ResourceMapDesktopModeActionStripState
    extends State<ResourceMapDesktopModeActionStrip> {
  late final ScrollController _fallbackController;
  bool _canScrollBack = false;
  bool _canScrollForward = false;
  bool _metricsUpdateScheduled = false;

  ScrollController get _effectiveController =>
      widget.controller ?? _fallbackController;

  @override
  void initState() {
    super.initState();
    _fallbackController = ScrollController();
    _effectiveController.addListener(_handleScroll);
    _scheduleMetricsUpdate();
  }

  @override
  void didUpdateWidget(ResourceMapDesktopModeActionStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _fallbackController).removeListener(
        _handleScroll,
      );
      _effectiveController.addListener(_handleScroll);
    }
    _scheduleMetricsUpdate();
  }

  @override
  void dispose() {
    _effectiveController.removeListener(_handleScroll);
    _fallbackController.dispose();
    super.dispose();
  }

  void _handleScroll() => _updateScrollAvailability();

  void _scheduleMetricsUpdate() {
    if (_metricsUpdateScheduled) {
      return;
    }
    _metricsUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _metricsUpdateScheduled = false;
      if (mounted) {
        _updateScrollAvailability();
      }
    });
  }

  void _updateScrollAvailability() {
    final controller = _effectiveController;
    var canScrollBack = false;
    var canScrollForward = false;
    if (controller.hasClients) {
      final position = controller.position;
      if (position.hasContentDimensions) {
        const edgeTolerance = 0.5;
        canScrollBack =
            position.pixels > position.minScrollExtent + edgeTolerance;
        canScrollForward =
            position.pixels < position.maxScrollExtent - edgeTolerance;
      }
    }
    if (canScrollBack == _canScrollBack &&
        canScrollForward == _canScrollForward) {
      return;
    }
    setState(() {
      _canScrollBack = canScrollBack;
      _canScrollForward = canScrollForward;
    });
  }

  Future<void> _scrollByViewport({required bool forward}) async {
    final controller = _effectiveController;
    if (!controller.hasClients) {
      return;
    }
    final position = controller.position;
    final distance = (position.viewportDimension * .72).clamp(144.0, 260.0);
    final target = (position.pixels + (forward ? distance : -distance))
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.jumpTo(target);
      return;
    }
    await controller.animateTo(
      target,
      duration: ResourceMapDesktopMotion.enter,
      curve: ResourceMapDesktopMotion.curve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _scheduleMetricsUpdate();
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.semanticLabel,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _scheduleMetricsUpdate();
          return false;
        },
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            SingleChildScrollView(
              key: const ValueKey<String>('resource-map-mode-action-strip'),
              controller: _effectiveController,
              scrollDirection: Axis.horizontal,
              padding: widget.padding,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (
                    var index = 0;
                    index < widget.actions.length;
                    index++
                  ) ...<Widget>[
                    if (index > 0) SizedBox(width: widget.spacing),
                    _ResourceMapDesktopModeActionButton(
                      action: widget.actions[index],
                      reduceMotion: reduceMotion,
                    ),
                  ],
                ],
              ),
            ),
            if (_canScrollBack)
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                child: _ResourceMapModeStripEdge(
                  key: const ValueKey<String>(
                    'resource-map-mode-actions-scroll-left',
                  ),
                  forward: false,
                  onPressed: () => _scrollByViewport(forward: false),
                ),
              ),
            if (_canScrollForward)
              PositionedDirectional(
                end: 0,
                top: 0,
                bottom: 0,
                child: _ResourceMapModeStripEdge(
                  key: const ValueKey<String>(
                    'resource-map-mode-actions-scroll-right',
                  ),
                  forward: true,
                  onPressed: () => _scrollByViewport(forward: true),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResourceMapModeStripEdge extends StatelessWidget {
  const _ResourceMapModeStripEdge({
    required this.forward,
    required this.onPressed,
    super.key,
  });

  final bool forward;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final chrome = ResourceMapChromeTheme.of(context);
    final textDirection = Directionality.of(context);
    final pointsRight = forward == (textDirection == TextDirection.ltr);
    final label = forward ? 'Show more map tasks' : 'Show previous map tasks';
    return SizedBox(
      width: 52,
      child: Stack(
        alignment: forward
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: forward
                        ? AlignmentDirectional.centerStart
                        : AlignmentDirectional.centerEnd,
                    end: forward
                        ? AlignmentDirectional.centerEnd
                        : AlignmentDirectional.centerStart,
                    colors: <Color>[
                      Colors.transparent,
                      chrome.modeStripFadeColor,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Tooltip(
            message: label,
            child: Semantics(
              button: true,
              label: label,
              child: SizedBox.square(
                dimension: 34,
                child: Material(
                  color: chrome.chromeRaised,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(chrome.toolRadius),
                    side: BorderSide(color: chrome.trimDeep),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onPressed,
                    hoverColor: chrome.accent.withValues(alpha: .10),
                    focusColor: chrome.accent.withValues(alpha: .14),
                    child: Icon(
                      pointsRight
                          ? Icons.chevron_right_rounded
                          : Icons.chevron_left_rounded,
                      size: 21,
                      color: chrome.accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResourceMapDesktopModeActionButton extends StatefulWidget {
  const _ResourceMapDesktopModeActionButton({
    required this.action,
    required this.reduceMotion,
  });

  final ResourceMapDesktopModeAction action;
  final bool reduceMotion;

  @override
  State<_ResourceMapDesktopModeActionButton> createState() =>
      _ResourceMapDesktopModeActionButtonState();
}

class _ResourceMapDesktopModeActionButtonState
    extends State<_ResourceMapDesktopModeActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final chrome = ResourceMapChromeTheme.of(context);
    final action = widget.action;
    final enabled = action.onPressed != null;
    final hovered = enabled && _hovered;
    final foreground = !enabled
        ? chrome.muted.withValues(alpha: .46)
        : action.selected
        ? chrome.ink
        : chrome.text;
    final iconColor = !enabled
        ? chrome.muted.withValues(alpha: .46)
        : action.selected
        ? chrome.accent
        : chrome.text;
    final badgeColor = !enabled
        ? chrome.muted.withValues(alpha: .46)
        : chrome.accent;
    return _ResourceMapDesktopEnterTransition(
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: action.selected,
        label: action.label,
        value: action.badge,
        child: ConstrainedBox(
          key: action.controlKey,
          constraints: const BoxConstraints(minHeight: 44),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: action.onPressed,
              onHover: (value) {
                if (_hovered != value) {
                  setState(() => _hovered = value);
                }
              },
              canRequestFocus: enabled,
              borderRadius: BorderRadius.circular(chrome.controlRadius),
              hoverColor: chrome.primary.withValues(alpha: .08),
              focusColor: chrome.primary.withValues(alpha: .15),
              highlightColor: chrome.primary.withValues(alpha: .18),
              child: AnimatedContainer(
                duration: widget.reduceMotion
                    ? Duration.zero
                    : ResourceMapDesktopMotion.quick,
                curve: ResourceMapDesktopMotion.curve,
                constraints: const BoxConstraints(minHeight: 40),
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  gradient: action.selected
                      ? chrome.selectedControlGradient
                      : hovered
                      ? chrome.hoverControlGradient
                      : chrome.idleCompactGradient,
                  borderRadius: BorderRadius.circular(chrome.controlRadius),
                  border: Border.all(
                    color: action.selected
                        ? chrome.primary
                        : hovered
                        ? chrome.primary.withValues(alpha: .72)
                        : chrome.warmOutline,
                  ),
                  boxShadow: action.selected
                      ? <BoxShadow>[
                          BoxShadow(
                            color: chrome.primary.withValues(alpha: .22),
                            blurRadius: 14,
                            offset: Offset(0, 3),
                          ),
                        ]
                      : hovered
                      ? <BoxShadow>[
                          BoxShadow(
                            color: chrome.primary.withValues(alpha: .18),
                            blurRadius: 13,
                            offset: Offset(0, 4),
                          ),
                        ]
                      : const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x4D000000),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ExcludeSemantics(
                      child: IconTheme(
                        data: IconThemeData(color: iconColor, size: 19),
                        child: action.icon,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      action.label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 12.5,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (action.badge case final badge?) ...<Widget>[
                      const SizedBox(width: 9),
                      Text(
                        badge,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 11.5,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
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
}

/// A finite-height, task-only workbench that sits along the bottom of the map.
///
/// Its header and panes are independent content-backed islands. The map remains
/// visible between them instead of disappearing behind one large tray. At
/// normal desktop widths its optional context, working content, and route
/// summary are arranged as three readable panes. Constrained widths and large
/// text switch to one vertically scrollable flow.
///
/// Slot children should provide semantic content rather than another outer
/// card. Each pane already scrolls without drawing scrollbar chrome.
class ResourceMapDesktopWorkbench extends StatelessWidget {
  const ResourceMapDesktopWorkbench({
    required this.body,
    this.header,
    this.leading,
    this.summary,
    this.visible = true,
    this.height = 280,
    this.leadingWidth = 286,
    this.summaryWidth = 252,
    this.wideBreakpoint = 920,
    this.bodyScrolls = true,
    this.animationDuration = ResourceMapDesktopMotion.settle,
    this.animationCurve = ResourceMapDesktopMotion.curve,
    this.hiddenOffset = const Offset(0, 1.08),
    this.onAnimationEnd,
    this.semanticLabel = 'Worker network workbench',
    super.key,
  }) : assert(height > 0),
       assert(leadingWidth > 0),
       assert(summaryWidth > 0),
       assert(wideBreakpoint > 0);

  /// Primary work area, such as material targets or route changes.
  final Widget body;

  /// Optional title/actions shown once above every workbench pane.
  final Widget? header;

  /// Optional contextual pane, such as the selected production node.
  final Widget? leading;

  /// Optional compact result pane, such as CP and worker totals.
  final Widget? summary;

  /// Whether the workbench is open over the map.
  ///
  /// A closed workbench remains mounted so task state and scroll positions are
  /// retained while it slides below the map. It cannot receive pointer or
  /// keyboard input and is removed from the semantics tree immediately.
  final bool visible;

  /// Preferred tray height. It contracts when its parent has less room.
  final double height;

  final double leadingWidth;
  final double summaryWidth;
  final double wideBreakpoint;

  /// Whether the workbench supplies scrolling for [body].
  ///
  /// Set this to false when [body] already owns a bounded scrolling tree,
  /// such as a Column containing an Expanded ListView. With no leading or
  /// summary pane, that body receives the tray's finite constraints directly
  /// in both the desktop-column and compact stacked arrangements.
  final bool bodyScrolls;

  /// Duration used for both the bottom slide and the quiet opacity change.
  ///
  /// This is automatically replaced by [Duration.zero] when the platform asks
  /// for reduced motion through [MediaQueryData.disableAnimations].
  final Duration animationDuration;

  final Curve animationCurve;

  /// Fractional translation applied while closed.
  ///
  /// The default places the complete workbench just below its open position.
  /// This keeps presentation independent of the workbench's configured height.
  final Offset hiddenOffset;

  /// Called after the implicit visibility transition completes.
  final VoidCallback? onAnimationEnd;

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scaledBody = MediaQuery.textScalerOf(context).scale(13);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final effectiveDuration = reduceMotion ? Duration.zero : animationDuration;
    final workbench = Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight =
              constraints.hasBoundedHeight && constraints.maxHeight < height
              ? constraints.maxHeight
              : height;
          final stacked =
              constraints.maxWidth < wideBreakpoint || scaledBody > 18;
          return SizedBox(
            key: const ValueKey<String>('resource-map-network-workbench'),
            height: availableHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (header case final value?) ...<Widget>[
                  ResourceMapSurfaceIsland(
                    key: const ValueKey<String>(
                      'resource-map-network-workbench-header',
                    ),
                    radius: 14,
                    padding: const EdgeInsets.fromLTRB(15, 9, 15, 9),
                    child: value,
                  ),
                  const SizedBox(height: 8),
                ],
                Expanded(
                  child: stacked
                      ? _ResourceMapWorkbenchStack(
                          leading: leading,
                          body: body,
                          summary: summary,
                          bodyScrolls: bodyScrolls,
                        )
                      : _ResourceMapWorkbenchColumns(
                          leading: leading,
                          body: body,
                          summary: summary,
                          leadingWidth: leadingWidth,
                          summaryWidth: summaryWidth,
                          bodyScrolls: bodyScrolls,
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
    return ExcludeFocus(
      key: const ValueKey<String>('resource-map-workbench-focus-guard'),
      excluding: !visible,
      child: ExcludeSemantics(
        key: const ValueKey<String>('resource-map-workbench-semantics-guard'),
        excluding: !visible,
        child: IgnorePointer(
          key: const ValueKey<String>('resource-map-workbench-pointer-guard'),
          ignoring: !visible,
          child: AnimatedSlide(
            key: const ValueKey<String>('resource-map-workbench-slide'),
            offset: visible ? Offset.zero : hiddenOffset,
            duration: effectiveDuration,
            curve: animationCurve,
            child: AnimatedOpacity(
              key: const ValueKey<String>('resource-map-workbench-fade'),
              opacity: visible ? 1 : 0,
              duration: effectiveDuration,
              curve: animationCurve,
              onEnd: onAnimationEnd,
              child: workbench,
            ),
          ),
        ),
      ),
    );
  }
}

/// One action exposed by [ResourceMapDesktopToolRail].
class ResourceMapDesktopToolRailAction {
  const ResourceMapDesktopToolRailAction({
    required this.icon,
    required this.label,
    this.onPressed,
    this.selected = false,
    this.controlKey,
  });

  /// The icon may be an app-owned image as well as a Flutter [Icon].
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  final Key? controlKey;
}

/// A slim, scrollable task rail for map-level tools.
///
/// Every action keeps a 44 px desktop hit target. The rail draws no scrollbar
/// chrome and collapses safely when its parent gives it finite height.
class ResourceMapDesktopToolRail extends StatelessWidget {
  const ResourceMapDesktopToolRail({
    required this.actions,
    this.semanticLabel = 'Map task shortcuts',
    super.key,
  });

  final List<ResourceMapDesktopToolRailAction> actions;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: DecoratedBox(
        key: const ValueKey<String>('resource-map-side-tool-rail'),
        decoration: const BoxDecoration(color: Colors.transparent),
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: 52,
            child: SingleChildScrollView(
              key: const ValueKey<String>('resource-map-side-tool-rail-scroll'),
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (
                    var index = 0;
                    index < actions.length;
                    index++
                  ) ...<Widget>[
                    if (index > 0) const SizedBox(height: 4),
                    _ResourceMapDesktopToolRailButton(
                      action: actions[index],
                      reduceMotion: reduceMotion,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResourceMapWorkbenchColumns extends StatelessWidget {
  const _ResourceMapWorkbenchColumns({
    required this.leading,
    required this.body,
    required this.summary,
    required this.leadingWidth,
    required this.summaryWidth,
    required this.bodyScrolls,
  });

  final Widget? leading;
  final Widget body;
  final Widget? summary;
  final double leadingWidth;
  final double summaryWidth;
  final bool bodyScrolls;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (leading case final value?) ...<Widget>[
          SizedBox(
            width: leadingWidth,
            child: ResourceMapSurfaceIsland(
              child: _ResourceMapWorkbenchPane(
                key: const ValueKey<String>(
                  'resource-map-network-workbench-leading',
                ),
                scrollKey: const ValueKey<String>(
                  'resource-map-network-workbench-leading-scroll',
                ),
                child: value,
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: ResourceMapSurfaceIsland(
            child: bodyScrolls
                ? _ResourceMapWorkbenchPane(
                    key: const ValueKey<String>(
                      'resource-map-network-workbench-body',
                    ),
                    scrollKey: const ValueKey<String>(
                      'resource-map-network-workbench-scroll',
                    ),
                    child: body,
                  )
                : KeyedSubtree(
                    key: const ValueKey<String>(
                      'resource-map-network-workbench-body',
                    ),
                    child: body,
                  ),
          ),
        ),
        if (summary case final value?) ...<Widget>[
          const SizedBox(width: 10),
          SizedBox(
            width: summaryWidth,
            child: ResourceMapSurfaceIsland(
              child: _ResourceMapWorkbenchPane(
                key: const ValueKey<String>(
                  'resource-map-network-workbench-summary',
                ),
                scrollKey: const ValueKey<String>(
                  'resource-map-network-workbench-summary-scroll',
                ),
                child: value,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ResourceMapWorkbenchStack extends StatelessWidget {
  const _ResourceMapWorkbenchStack({
    required this.leading,
    required this.body,
    required this.summary,
    required this.bodyScrolls,
  });

  final Widget? leading;
  final Widget body;
  final Widget? summary;
  final bool bodyScrolls;

  @override
  Widget build(BuildContext context) {
    if (!bodyScrolls && leading == null && summary == null) {
      return ResourceMapSurfaceIsland(
        child: KeyedSubtree(
          key: const ValueKey<String>('resource-map-network-workbench-body'),
          child: body,
        ),
      );
    }
    return SingleChildScrollView(
      key: const ValueKey<String>('resource-map-network-workbench-scroll'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (leading case final value?) ...<Widget>[
            ResourceMapSurfaceIsland(
              child: KeyedSubtree(
                key: const ValueKey<String>(
                  'resource-map-network-workbench-leading',
                ),
                child: value,
              ),
            ),
            const SizedBox(height: 8),
          ],
          ResourceMapSurfaceIsland(
            child: KeyedSubtree(
              key: const ValueKey<String>(
                'resource-map-network-workbench-body',
              ),
              child: body,
            ),
          ),
          if (summary case final value?) ...<Widget>[
            const SizedBox(height: 8),
            ResourceMapSurfaceIsland(
              child: KeyedSubtree(
                key: const ValueKey<String>(
                  'resource-map-network-workbench-summary',
                ),
                child: value,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResourceMapWorkbenchPane extends StatelessWidget {
  const _ResourceMapWorkbenchPane({
    required this.scrollKey,
    required this.child,
    super.key,
  });

  final Key scrollKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(key: scrollKey, child: child);
  }
}

/// A small smoky-glass surface sized by its own content.
///
/// The barely-visible contour grain keeps large work areas from looking like
/// flat color swatches while remaining deterministic for golden tests.
class ResourceMapSurfaceIsland extends StatelessWidget {
  const ResourceMapSurfaceIsland({
    required this.child,
    this.padding = const EdgeInsets.all(13),
    this.radius,
    this.subtle = false,
    this.reading = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Overrides the selected chrome theme's surface radius.
  final double? radius;
  final bool subtle;

  /// Uses the theme's selective high-contrast reading material.
  ///
  /// In Illuminated Atlas this is warm vellum with dark ink. Ordinary command
  /// and work surfaces remain navy leather.
  final bool reading;

  @override
  Widget build(BuildContext context) {
    final chrome = ResourceMapChromeTheme.of(context);
    final borderRadius = BorderRadius.circular(radius ?? chrome.surfaceRadius);
    final gradient = reading
        ? chrome.readingSurfaceGradient
        : subtle
        ? chrome.subtleSurfaceGradient
        : chrome.surfaceGradient;
    final outline = reading ? chrome.readingOutline : chrome.warmOutline;
    final foreground = reading ? chrome.readingInk : chrome.ink;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: borderRadius,
        border: Border.all(color: outline),
        boxShadow: subtle ? chrome.subtleSurfaceShadows : chrome.surfaceShadows,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ResourceMapContourGrainPainter(
                    contourColor: chrome.contourColor,
                    fleckColor: chrome.fleckColor,
                  ),
                ),
              ),
            ),
            Padding(
              padding: padding,
              child: reading
                  ? DefaultTextStyle.merge(
                      style: TextStyle(color: foreground),
                      child: IconTheme.merge(
                        data: IconThemeData(color: foreground),
                        child: child,
                      ),
                    )
                  : child,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourceMapContourGrainPainter extends CustomPainter {
  const _ResourceMapContourGrainPainter({
    required this.contourColor,
    required this.fleckColor,
  });

  final Color contourColor;
  final Color fleckColor;

  @override
  void paint(Canvas canvas, Size size) {
    final contourPaint = Paint()
      ..color = contourColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = .65;
    for (var y = 7.0; y < size.height + 10; y += 17) {
      final path = Path()
        ..moveTo(-12, y)
        ..cubicTo(
          size.width * .24,
          y - 4,
          size.width * .38,
          y + 5,
          size.width * .58,
          y + 1,
        )
        ..cubicTo(
          size.width * .74,
          y - 3,
          size.width * .88,
          y + 4,
          size.width + 12,
          y,
        );
      canvas.drawPath(path, contourPaint);
    }

    final fleckPaint = Paint()..color = fleckColor;
    for (var x = 11.0; x < size.width; x += 37) {
      final y = 9.0 + ((x ~/ 37) % 4) * 19.0;
      if (y < size.height) {
        canvas.drawCircle(Offset(x, y), .65, fleckPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_ResourceMapContourGrainPainter oldDelegate) =>
      contourColor != oldDelegate.contourColor ||
      fleckColor != oldDelegate.fleckColor;
}

class _ResourceMapDesktopToolRailButton extends StatelessWidget {
  const _ResourceMapDesktopToolRailButton({
    required this.action,
    required this.reduceMotion,
  });

  final ResourceMapDesktopToolRailAction action;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final chrome = ResourceMapChromeTheme.of(context);
    final enabled = action.onPressed != null;
    final foreground = !enabled
        ? chrome.muted.withValues(alpha: .46)
        : action.selected
        ? chrome.accent
        : chrome.text;
    return _ResourceMapDesktopEnterTransition(
      beginOffset: const Offset(-3, 0),
      child: Tooltip(
        message: action.label,
        child: Semantics(
          button: true,
          enabled: enabled,
          selected: action.selected,
          label: action.label,
          child: SizedBox(
            key: action.controlKey,
            width: 44,
            height: 44,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: action.onPressed,
                canRequestFocus: enabled,
                borderRadius: BorderRadius.circular(chrome.toolRadius),
                hoverColor: chrome.primary.withValues(alpha: .10),
                focusColor: chrome.primary.withValues(alpha: .15),
                highlightColor: chrome.primary.withValues(alpha: .18),
                child: AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : ResourceMapDesktopMotion.quick,
                  curve: ResourceMapDesktopMotion.curve,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: chrome.chromeRaised,
                    gradient: action.selected
                        ? chrome.selectedCompactGradient
                        : chrome.idleCompactGradient,
                    borderRadius: BorderRadius.circular(chrome.toolRadius),
                    border: Border.all(
                      color: action.selected
                          ? chrome.trimLine
                          : chrome.softOutline,
                    ),
                    boxShadow: action.selected
                        ? <BoxShadow>[
                            BoxShadow(
                              color: chrome.primary.withValues(alpha: .22),
                              blurRadius: 13,
                              offset: Offset(0, 3),
                            ),
                          ]
                        : const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x52000000),
                              blurRadius: 11,
                              offset: Offset(0, 4),
                            ),
                          ],
                  ),
                  child: ExcludeSemantics(
                    child: IconTheme(
                      data: IconThemeData(color: foreground, size: 20),
                      child: action.icon,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ResourceMapDesktopTaskStrip extends StatelessWidget {
  const ResourceMapDesktopTaskStrip({
    required this.leadingIcon,
    required this.title,
    required this.actions,
    this.onBack,
    this.onClose,
    super.key,
  });

  final IconData leadingIcon;
  final String title;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final chrome = ResourceMapChromeTheme.of(context);
    return IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: chrome.ink,
          hoverColor: chrome.accent.withValues(alpha: .08),
          highlightColor: chrome.accent.withValues(alpha: .14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(chrome.compactRadius - 4),
          ),
        ),
      ),
      child: ConstrainedBox(
        key: const ValueKey<String>('resource-map-desktop-task-strip'),
        constraints: const BoxConstraints(minHeight: 48),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: chrome.taskStripGradient,
            borderRadius: BorderRadius.circular(chrome.controlRadius),
            border: Border.all(color: chrome.warmOutline),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x4D000000),
                blurRadius: 13,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: <Widget>[
                if (onBack != null)
                  _MapIconControl(
                    key: const ValueKey<String>('resource-map-task-back'),
                    tooltip: 'Back',
                    semanticLabel: 'Back',
                    icon: Icons.arrow_back_rounded,
                    onPressed: onBack!,
                    compact: true,
                  )
                else
                  Container(
                    width: 34,
                    height: 34,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: chrome.trimWash,
                      borderRadius: BorderRadius.circular(chrome.inlineRadius),
                      border: Border.all(color: chrome.trimDeep),
                    ),
                    child: Icon(leadingIcon, size: 18, color: chrome.accent),
                  ),
                const SizedBox(width: 5),
                Expanded(child: Text(title, style: chrome.headingStyle())),
                ...actions,
                if (onClose != null) ...<Widget>[
                  const SizedBox(width: 4),
                  _MapIconControl(
                    key: const ValueKey<String>('resource-map-task-close'),
                    tooltip: 'Close',
                    semanticLabel: 'Close map task',
                    icon: Icons.close_rounded,
                    onPressed: onClose!,
                    compact: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A feathered left-edge reading rail for contextual map content.
///
/// This is deliberately not a card or an opaque sidebar. A paint-only gradient
/// suppresses busy map labels, symbols, and route lines beneath readable
/// content, then fades through the reserved right gutter back into the map.
class ResourceMapDesktopEdgeSurface extends StatelessWidget {
  const ResourceMapDesktopEdgeSurface({
    required this.child,
    this.contentWidth = 318,
    super.key,
  });

  final Widget child;
  final double contentWidth;

  @override
  Widget build(BuildContext context) {
    final chrome = ResourceMapChromeTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: chrome.edgeFadeGradient),
      child: Padding(
        key: const ValueKey<String>('resource-map-desktop-edge-surface'),
        padding: const EdgeInsets.only(left: 14, right: 46),
        child: SizedBox(
          width: contentWidth,
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              shadows: <Shadow>[
                Shadow(
                  color: Color(0xF2000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class ResourceMapInlineAction extends StatelessWidget {
  const ResourceMapInlineAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.badge,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final chrome = ResourceMapChromeTheme.of(context);
    final foreground = selected ? chrome.ink : chrome.text;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(chrome.inlineRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          hoverColor: selected
              ? Colors.white.withValues(alpha: .08)
              : chrome.accent.withValues(alpha: .08),
          child: AnimatedContainer(
            duration: ResourceMapDesktopMotion.duration(
              context,
              ResourceMapDesktopMotion.quick,
            ),
            curve: ResourceMapDesktopMotion.curve,
            decoration: BoxDecoration(
              gradient: selected
                  ? chrome.selectedInlineGradient
                  : chrome.idleInlineGradient,
              borderRadius: BorderRadius.circular(chrome.inlineRadius),
              border: Border.all(
                color: selected ? chrome.primary : chrome.warmOutline,
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x3D000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final labelText = Text(
                    label,
                    maxLines: constraints.hasBoundedWidth ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12.5,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                  return Row(
                    mainAxisSize: constraints.hasBoundedWidth
                        ? MainAxisSize.max
                        : MainAxisSize.min,
                    children: <Widget>[
                      Icon(icon, size: 17, color: foreground),
                      const SizedBox(width: 8),
                      if (constraints.hasBoundedWidth)
                        Expanded(child: labelText)
                      else
                        labelText,
                      if (badge case final value?) ...<Widget>[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? Colors.white.withValues(alpha: .16)
                                : chrome.paper,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            value,
                            style: TextStyle(
                              color: selected ? chrome.accent : chrome.muted,
                              fontSize: 10.5,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapSearchControl extends StatelessWidget {
  const _MapSearchControl({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onTap,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final chrome = ResourceMapChromeTheme.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final queryActive = value.text.trim().isNotEmpty;
        return AnimatedBuilder(
          animation: focusNode,
          builder: (context, child) {
            final focused = focusNode.hasFocus;
            return AnimatedContainer(
              key: const ValueKey<String>('resource-map-search-card'),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : ResourceMapDesktopMotion.quick,
              curve: ResourceMapDesktopMotion.curve,
              decoration: BoxDecoration(
                gradient: focused
                    ? chrome.focusedSearchGradient
                    : chrome.idleSearchGradient,
                borderRadius: BorderRadius.circular(chrome.commandRadius),
                border: Border.all(
                  color: focused ? chrome.primary : chrome.warmOutline,
                  width: focused ? 1.25 : 1,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: focused
                        ? chrome.primary.withValues(alpha: .24)
                        : const Color(0x52000000),
                    blurRadius: focused ? 16 : 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                onTap: onTap,
                onSubmitted: onSubmitted,
                textInputAction: TextInputAction.search,
                style: TextStyle(
                  color: chrome.ink,
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Find an item, source, node or town',
                  hintStyle: TextStyle(
                    color: chrome.muted,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: focused ? chrome.primary : chrome.accent,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 42,
                    maxWidth: 42,
                  ),
                  suffixIcon: queryActive
                      ? IconButton(
                          tooltip: 'Clear search',
                          onPressed: onClear,
                          visualDensity: VisualDensity.compact,
                          color: chrome.muted,
                          icon: const Icon(Icons.close_rounded, size: 18),
                        )
                      : Tooltip(
                          message: 'Focus search (Ctrl+F)',
                          child: Padding(
                            padding: EdgeInsetsDirectional.only(end: 14),
                            child: Center(
                              widthFactor: 1,
                              child: DecoratedBox(
                                key: ValueKey<String>(
                                  'resource-map-search-shortcut-keycap',
                                ),
                                decoration: BoxDecoration(
                                  color: chrome.chromeRaised,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(chrome.keycapRadius),
                                  ),
                                  border: Border.fromBorderSide(
                                    BorderSide(color: chrome.softOutline),
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    'CTRL F',
                                    style: TextStyle(
                                      color: chrome.muted,
                                      fontSize: 10,
                                      height: 1,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .35,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                  suffixIconConstraints: BoxConstraints(
                    minWidth: queryActive ? 42 : 64,
                  ),
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13.5),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MapModeControl extends StatelessWidget {
  const _MapModeControl({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    required this.reduceMotion,
    required this.showLabel,
    required this.labeledMinWidth,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final bool reduceMotion;
  final bool showLabel;
  final double labeledMinWidth;

  @override
  Widget build(BuildContext context) {
    final chrome = ResourceMapChromeTheme.of(context);
    final foreground = selected ? chrome.accent : chrome.text;
    final control = Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(chrome.commandRadius - 3),
          hoverColor: chrome.accent.withValues(alpha: .08),
          focusColor: chrome.accent.withValues(alpha: .12),
          highlightColor: chrome.accent.withValues(alpha: .15),
          child: AnimatedContainer(
            width: showLabel ? null : 46,
            height: 50,
            constraints: showLabel
                ? BoxConstraints(minWidth: labeledMinWidth)
                : null,
            padding: EdgeInsets.symmetric(horizontal: showLabel ? 11 : 10),
            alignment: Alignment.center,
            duration: reduceMotion
                ? Duration.zero
                : ResourceMapDesktopMotion.quick,
            curve: ResourceMapDesktopMotion.curve,
            decoration: BoxDecoration(
              gradient: selected
                  ? chrome.selectedModeGradient
                  : chrome.idleControlGradient,
              borderRadius: BorderRadius.circular(chrome.commandRadius),
              border: Border.all(
                color: selected ? chrome.primary : chrome.warmOutline,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: selected
                      ? chrome.primary.withValues(alpha: .24)
                      : const Color(0x52000000),
                  blurRadius: selected ? 15 : 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 17, color: foreground),
                if (showLabel) ...<Widget>[
                  const SizedBox(width: 7),
                  Text(
                    label,
                    softWrap: false,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12.5,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (showLabel) {
      return control;
    }
    return Tooltip(message: label, child: control);
  }
}

class _MapIconControl extends StatelessWidget {
  const _MapIconControl({
    required this.tooltip,
    required this.semanticLabel,
    required this.icon,
    required this.onPressed,
    this.compact = false,
    super.key,
  });

  final String tooltip;
  final String semanticLabel;
  final IconData icon;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final chrome = ResourceMapChromeTheme.of(context);
    final height = compact ? 38.0 : 46.0;
    final width = compact ? 38.0 : 46.0;
    final foreground = chrome.ink;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(chrome.compactRadius),
            hoverColor: chrome.primary.withValues(alpha: .10),
            focusColor: chrome.primary.withValues(alpha: .14),
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : ResourceMapDesktopMotion.quick,
              curve: ResourceMapDesktopMotion.curve,
              width: width,
              height: height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: chrome.chromeRaised,
                gradient: chrome.idleControlGradient,
                borderRadius: BorderRadius.circular(chrome.compactRadius),
                border: Border.all(
                  color: compact ? chrome.softOutline : chrome.warmOutline,
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, size: compact ? 18 : 19, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
