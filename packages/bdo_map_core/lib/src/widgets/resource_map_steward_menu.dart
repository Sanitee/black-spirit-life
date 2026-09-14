import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'resource_map_chrome_theme.dart';
import 'resource_map_desktop_shell.dart';
import 'resource_map_panel_metrics.dart';

/// The three human-sized sections in the Worker map menu.
enum ResourceMapWorkerMenuSection { plan, explore, manage }

/// Physical desk objects used by the Guild Steward's Desk icon family.
enum ResourceMapStewardIconKind {
  gatherMode,
  workersMode,
  search,
  plan,
  explore,
  manage,
  gatherTools,
  browse,
  needed,
  checklist,
  favorites,
  specificItems,
  bestIncome,
  findNodes,
  connections,
  invest,
  houses,
  plantsWood,
  oresMinerals,
  meat,
  bloodHides,
  mushrooms,
  coastal,
  other,
}

@immutable
class ResourceMapStewardMenuAction {
  const ResourceMapStewardMenuAction({
    required this.key,
    required this.icon,
    required this.label,
    required this.semanticHint,
    required this.onPressed,
    this.selected = false,
    this.badge,
  });

  final Key key;
  final ResourceMapStewardIconKind icon;
  final String label;
  final String semanticHint;
  final VoidCallback onPressed;
  final bool selected;
  final String? badge;
}

/// A compact, reversible Worker menu based on the approved Guild Steward's
/// Desk direction.
///
/// The closed state shows Plan, Explore and Manage. Opening one section keeps
/// that section in place, glides the others out to the left, and reveals its
/// actions in a short vertical stagger. The layout never turns into a drawer
/// or a large card over the map.
class ResourceMapStewardWorkerMenu extends StatefulWidget {
  const ResourceMapStewardWorkerMenu({
    required this.selectedSection,
    required this.onSectionChanged,
    required this.planActions,
    required this.exploreActions,
    required this.manageActions,
    this.semanticLabel = 'Worker map tools',
    this.menuContentKey = const ValueKey<String>(
      'resource-map-worker-steward-menu',
    ),
    this.controlKeyPrefix = 'resource-map-worker-menu',
    this.planLabel = 'Plan',
    this.exploreLabel = 'Explore',
    this.manageLabel = 'Manage',
    this.planIcon = ResourceMapStewardIconKind.plan,
    this.exploreIcon = ResourceMapStewardIconKind.explore,
    this.manageIcon = ResourceMapStewardIconKind.manage,
    this.visibleSections = ResourceMapWorkerMenuSection.values,
    super.key,
  });

  final ResourceMapWorkerMenuSection? selectedSection;
  final ValueChanged<ResourceMapWorkerMenuSection?> onSectionChanged;
  final List<ResourceMapStewardMenuAction> planActions;
  final List<ResourceMapStewardMenuAction> exploreActions;
  final List<ResourceMapStewardMenuAction> manageActions;
  final String semanticLabel;
  final Key menuContentKey;
  final String controlKeyPrefix;
  final String planLabel;
  final String exploreLabel;
  final String manageLabel;
  final ResourceMapStewardIconKind planIcon;
  final ResourceMapStewardIconKind exploreIcon;
  final ResourceMapStewardIconKind manageIcon;
  final List<ResourceMapWorkerMenuSection> visibleSections;

  @override
  State<ResourceMapStewardWorkerMenu> createState() =>
      _ResourceMapStewardWorkerMenuState();
}

class _ResourceMapStewardWorkerMenuState
    extends State<ResourceMapStewardWorkerMenu>
    with SingleTickerProviderStateMixin {
  static const double _rowGap = 5;
  static const double _parentWidth = 200;
  // Action names are part of the navigation, not secondary metadata. Keep
  // enough room for the longest current label at the normal text scale and
  // let larger text use the expanded layout below. These controls must never
  // communicate their meaning through an ellipsis.
  static const double _childWidth = ResourceMapPanelMetrics.menuWidth;
  static const double _childIndent = 12;

  late final AnimationController _controller;
  ResourceMapWorkerMenuSection? _displayedSection;
  int _transitionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _displayedSection = widget.selectedSection;
    _controller = AnimationController(
      vsync: this,
      duration: ResourceMapDesktopMotion.settle,
      reverseDuration: ResourceMapDesktopMotion.enter,
      value: widget.selectedSection == null ? 0 : 1,
    );
  }

  @override
  void didUpdateWidget(ResourceMapStewardWorkerMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSection == widget.selectedSection) {
      return;
    }
    _transitionGeneration += 1;
    final generation = _transitionGeneration;
    final next = widget.selectedSection;
    if (next == null) {
      _reverseAndClear(generation);
      return;
    }
    if (_displayedSection == null || _controller.value <= .001) {
      setState(() => _displayedSection = next);
      _animateForward();
      return;
    }
    _switchSection(next, generation);
  }

  Future<void> _animateForward() async {
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    await _controller.forward();
  }

  Future<void> _reverseAndClear(int generation) async {
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0;
    } else {
      await _controller.reverse();
    }
    if (!mounted || generation != _transitionGeneration) {
      return;
    }
    setState(() => _displayedSection = null);
  }

  Future<void> _switchSection(
    ResourceMapWorkerMenuSection next,
    int generation,
  ) async {
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _displayedSection = next);
      _controller.value = 1;
      return;
    }
    await _controller.reverse();
    if (!mounted || generation != _transitionGeneration) {
      return;
    }
    setState(() => _displayedSection = next);
    await _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<ResourceMapStewardMenuAction> _actionsFor(
    ResourceMapWorkerMenuSection? section,
  ) => switch (section) {
    ResourceMapWorkerMenuSection.plan => widget.planActions,
    ResourceMapWorkerMenuSection.explore => widget.exploreActions,
    ResourceMapWorkerMenuSection.manage => widget.manageActions,
    null => const <ResourceMapStewardMenuAction>[],
  };

  String _labelFor(ResourceMapWorkerMenuSection section) => switch (section) {
    ResourceMapWorkerMenuSection.plan => widget.planLabel,
    ResourceMapWorkerMenuSection.explore => widget.exploreLabel,
    ResourceMapWorkerMenuSection.manage => widget.manageLabel,
  };

  ResourceMapStewardIconKind _iconFor(ResourceMapWorkerMenuSection section) =>
      switch (section) {
        ResourceMapWorkerMenuSection.plan => widget.planIcon,
        ResourceMapWorkerMenuSection.explore => widget.exploreIcon,
        ResourceMapWorkerMenuSection.manage => widget.manageIcon,
      };

  @override
  Widget build(BuildContext context) {
    final actions = _actionsFor(_displayedSection);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    final childWidth = largeText ? 350.0 : _childWidth;
    final rowHeight = _measuredRowHeight(context, actions, childWidth);
    final visibleSectionCount = widget.visibleSections.length;
    final closedHeight =
        (rowHeight * visibleSectionCount) +
        (_rowGap * math.max(0, visibleSectionCount - 1));
    final openHeight =
        rowHeight +
        (actions.isEmpty ? 0 : _rowGap) +
        (actions.length * rowHeight) +
        (math.max(0, actions.length - 1) * _rowGap);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.semanticLabel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = Curves.easeOutCubic.transform(_controller.value);
          final height = _lerp(closedHeight, openHeight, progress);
          return SizedBox(
            key: widget.menuContentKey,
            width: _childIndent + childWidth,
            height: height,
            child: ClipRect(
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  for (final section in widget.visibleSections)
                    _buildParent(
                      context,
                      section: section,
                      progress: progress,
                      rowHeight: rowHeight,
                    ),
                  for (var index = 0; index < actions.length; index += 1)
                    _buildAction(
                      context,
                      action: actions[index],
                      index: index,
                      overallProgress: _controller.value,
                      rowHeight: rowHeight,
                      childWidth: childWidth,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  double _measuredRowHeight(
    BuildContext context,
    List<ResourceMapStewardMenuAction> actions,
    double childWidth,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    var height = math.max(
      ResourceMapPanelMetrics.rowHeight,
      scaler.scale(ResourceMapPanelMetrics.primary) * 1.2 + 12,
    );
    for (final entry in <(String, double)>[
      for (final section in widget.visibleSections)
        (_labelFor(section), _parentWidth),
      for (final action in actions) (action.label, childWidth),
    ]) {
      final painter = TextPainter(
        text: TextSpan(
          text: entry.$1,
          style: DefaultTextStyle.of(context).style.copyWith(
            fontSize: ResourceMapPanelMetrics.primary,
            height: 1.1,
            fontWeight: FontWeight.w500,
            letterSpacing: -.08,
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout(maxWidth: entry.$2 - 95);
      height = math.max(height, painter.height + 10);
      painter.dispose();
    }
    return height.ceilToDouble();
  }

  Widget _buildParent(
    BuildContext context, {
    required ResourceMapWorkerMenuSection section,
    required double progress,
    required double rowHeight,
  }) {
    final originalIndex = widget.visibleSections.indexOf(section);
    final selected = section == _displayedSection;
    final closedY = originalIndex * (rowHeight + _rowGap);
    final selectedIndex = _displayedSection == null
        ? null
        : widget.visibleSections.indexOf(_displayedSection!);
    final targetY = selected
        ? 0.0
        : selectedIndex == null
        ? closedY
        : closedY + (originalIndex < selectedIndex ? -18 : 18);
    final y = _lerp(closedY, targetY, progress);
    final hiddenProgress = selected ? 0.0 : progress;
    final x = -(_parentWidth + 16) * hiddenProgress;
    final hidden = _displayedSection != null && !selected && progress > .04;
    final externalSelected = widget.selectedSection == section;
    return Positioned(
      left: x,
      top: y,
      width: _parentWidth,
      height: rowHeight,
      child: Opacity(
        opacity: 1 - hiddenProgress,
        child: ExcludeFocus(
          excluding: hidden,
          child: ExcludeSemantics(
            excluding: hidden,
            child: IgnorePointer(
              ignoring: hidden,
              child: _StewardMenuButton(
                key: ValueKey<String>(
                  '${widget.controlKeyPrefix}-${section.name}',
                ),
                icon: _iconFor(section),
                label: _labelFor(section),
                semanticHint: externalSelected
                    ? 'Close ${_labelFor(section)} tools.'
                    : 'Show ${_labelFor(section)} tools.',
                selected: externalSelected,
                expanded: externalSelected,
                onPressed: () =>
                    widget.onSectionChanged(externalSelected ? null : section),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAction(
    BuildContext context, {
    required ResourceMapStewardMenuAction action,
    required int index,
    required double overallProgress,
    required double rowHeight,
    required double childWidth,
  }) {
    final start = .25 + (index * .1);
    final end = math.min(1.0, start + .48);
    final local = ((overallProgress - start) / (end - start)).clamp(0.0, 1.0);
    final progress = Curves.easeOutCubic.transform(local);
    final top =
        rowHeight +
        _rowGap +
        (index * (rowHeight + _rowGap)) +
        ((1 - progress) * 13);
    final closing = widget.selectedSection == null;
    return Positioned(
      left: _childIndent + ((1 - progress) * 9),
      top: top,
      width: childWidth,
      height: rowHeight,
      child: Opacity(
        opacity: progress,
        child: ExcludeFocus(
          excluding: closing || progress < .72,
          child: ExcludeSemantics(
            excluding: closing || progress < .45,
            child: IgnorePointer(
              ignoring: closing || progress < .72,
              child: _StewardMenuButton(
                key: action.key,
                icon: action.icon,
                label: action.label,
                badge: action.badge,
                semanticHint: action.semanticHint,
                selected: action.selected,
                onPressed: action.onPressed,
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _lerp(double from, double to, double t) => from + ((to - from) * t);
}

class _StewardMenuButton extends StatefulWidget {
  const _StewardMenuButton({
    required this.icon,
    required this.label,
    required this.semanticHint,
    required this.onPressed,
    this.selected = false,
    this.expanded,
    this.badge,
    super.key,
  });

  final ResourceMapStewardIconKind icon;
  final String label;
  final String semanticHint;
  final VoidCallback onPressed;
  final bool selected;
  final bool? expanded;
  final String? badge;

  @override
  State<_StewardMenuButton> createState() => _StewardMenuButtonState();
}

class _StewardMenuButtonState extends State<_StewardMenuButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final chrome = ResourceMapChromeTheme.of(context);
    final active = widget.selected || _hovered || _focused;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final clipper = _StewardButtonClipper();
    final semanticLabel = widget.badge == null
        ? '${widget.label}. ${widget.semanticHint}'
        : '${widget.label}, ${widget.badge}. ${widget.semanticHint}';
    return Semantics(
      button: true,
      selected: widget.selected,
      expanded: widget.expanded,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: AnimatedScale(
          scale: _hovered && !reduceMotion ? 1.012 : 1,
          alignment: Alignment.centerLeft,
          duration: ResourceMapDesktopMotion.duration(
            context,
            ResourceMapDesktopMotion.quick,
          ),
          curve: ResourceMapDesktopMotion.curve,
          child: PhysicalShape(
            clipper: clipper,
            clipBehavior: Clip.antiAlias,
            color: chrome.chromeRaised,
            shadowColor: Colors.black.withValues(alpha: .72),
            elevation: active ? 8 : 5,
            child: Material(
              type: MaterialType.transparency,
              child: AnimatedContainer(
                duration: ResourceMapDesktopMotion.duration(
                  context,
                  ResourceMapDesktopMotion.quick,
                ),
                curve: ResourceMapDesktopMotion.curve,
                decoration: BoxDecoration(
                  gradient: widget.selected
                      ? chrome.selectedControlGradient
                      : active
                      ? chrome.hoverControlGradient
                      : chrome.idleControlGradient,
                ),
                child: InkWell(
                  onTap: widget.onPressed,
                  onHover: (value) {
                    if (_hovered != value) {
                      setState(() => _hovered = value);
                    }
                  },
                  onFocusChange: (value) {
                    if (_focused != value) {
                      setState(() => _focused = value);
                    }
                  },
                  focusColor: chrome.accent.withValues(alpha: .13),
                  hoverColor: chrome.primary.withValues(alpha: .07),
                  highlightColor: chrome.primary.withValues(alpha: .12),
                  child: Stack(
                    children: <Widget>[
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 3,
                        child: ColoredBox(
                          color: widget.selected
                              ? chrome.accent
                              : chrome.primary.withValues(alpha: .78),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        top: 0,
                        right: 18,
                        height: 1,
                        child: ColoredBox(
                          color: chrome.trimLine.withValues(
                            alpha: active ? .82 : .42,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          12,
                          5,
                          22,
                          5,
                        ),
                        child: Row(
                          children: <Widget>[
                            ResourceMapStewardIcon(
                              kind: widget.icon,
                              size: ResourceMapPanelMetrics.navigationArtwork,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.label,
                                softWrap: true,
                                style: TextStyle(
                                  color: chrome.ink,
                                  fontSize: ResourceMapPanelMetrics.primary,
                                  height: 1.1,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -.08,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              widget.expanded == true
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.chevron_right_rounded,
                              size: 19,
                              color: active ? chrome.accent : chrome.muted,
                            ),
                          ],
                        ),
                      ),
                    ],
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

/// A compact list destination rendered in the same physical desk language as
/// the collapsing menu. It is used by deeper map pages such as Houses so the
/// experience does not fall back to generic mobile list tiles.
class ResourceMapStewardSurface extends StatelessWidget {
  const ResourceMapStewardSurface({
    required this.child,
    this.highlighted = false,
    super.key,
  });

  final Widget child;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final chrome = ResourceMapChromeTheme.of(context);
    return PhysicalShape(
      clipper: const _StewardButtonClipper(cut: 8),
      clipBehavior: Clip.antiAlias,
      color: chrome.chromeRaised,
      elevation: highlighted ? 5 : 2,
      shadowColor: Colors.black.withValues(alpha: .56),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: highlighted
              ? chrome.hoverControlGradient
              : chrome.idleControlGradient,
        ),
        child: Stack(
          children: <Widget>[
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: ColoredBox(
                color: highlighted
                    ? chrome.accent
                    : chrome.primary.withValues(alpha: .68),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class ResourceMapStewardListRow extends StatefulWidget {
  const ResourceMapStewardListRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.semanticLabel,
    required this.onPressed,
    this.badge,
    super.key,
  });

  final ResourceMapStewardIconKind icon;
  final String title;
  final String subtitle;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final String? badge;

  @override
  State<ResourceMapStewardListRow> createState() =>
      _ResourceMapStewardListRowState();
}

class _ResourceMapStewardListRowState extends State<ResourceMapStewardListRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final chrome = ResourceMapChromeTheme.of(context);
    final active = _hovered || _focused;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: widget.onPressed != null,
      label: widget.semanticLabel,
      hint: [
        widget.subtitle,
        ?widget.badge,
      ].where((value) => value.trim().isNotEmpty).join('. '),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: AnimatedScale(
            scale: active && !reduceMotion ? 1.008 : 1,
            alignment: Alignment.centerLeft,
            duration: reduceMotion
                ? Duration.zero
                : ResourceMapDesktopMotion.quick,
            curve: ResourceMapDesktopMotion.curve,
            child: PhysicalShape(
              clipper: _StewardButtonClipper(cut: 8),
              clipBehavior: Clip.antiAlias,
              color: chrome.chromeRaised,
              elevation: active ? 6 : 3,
              shadowColor: Colors.black.withValues(alpha: .62),
              child: Material(
                type: MaterialType.transparency,
                child: AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : ResourceMapDesktopMotion.quick,
                  curve: ResourceMapDesktopMotion.curve,
                  constraints: const BoxConstraints(
                    minHeight: ResourceMapPanelMetrics.rowHeight,
                  ),
                  decoration: BoxDecoration(
                    gradient: active
                        ? chrome.hoverControlGradient
                        : chrome.idleControlGradient,
                  ),
                  child: InkWell(
                    onTap: widget.onPressed,
                    onHover: (value) {
                      if (_hovered != value) {
                        setState(() => _hovered = value);
                      }
                    },
                    onFocusChange: (value) {
                      if (_focused != value) {
                        setState(() => _focused = value);
                      }
                    },
                    child: Stack(
                      children: <Widget>[
                        PositionedDirectional(
                          start: 0,
                          top: 0,
                          bottom: 0,
                          width: 3,
                          child: ColoredBox(
                            color: active
                                ? chrome.accent
                                : chrome.primary.withValues(alpha: .68),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            10,
                            6,
                            20,
                            6,
                          ),
                          child: Row(
                            children: <Widget>[
                              ResourceMapStewardIcon(
                                kind: widget.icon,
                                size: ResourceMapPanelMetrics.navigationArtwork,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  widget.title,
                                  softWrap: true,
                                  style: TextStyle(
                                    color: chrome.ink,
                                    fontSize: ResourceMapPanelMetrics.primary,
                                    height: 1.1,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: active ? chrome.accent : chrome.muted,
                              ),
                            ],
                          ),
                        ),
                      ],
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

class _StewardButtonClipper extends CustomClipper<Path> {
  const _StewardButtonClipper({this.cut = 11});

  final double cut;

  @override
  Path getClip(Size size) {
    const radius = 8.0;
    return Path()
      ..moveTo(radius, 0)
      ..lineTo(size.width - cut, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width - cut, size.height)
      ..lineTo(radius, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - radius)
      ..lineTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant _StewardButtonClipper oldClipper) =>
      oldClipper.cut != cut;
}

/// One detailed, frameless physical object from the Guild Steward's Desk set.
class ResourceMapStewardIcon extends StatelessWidget {
  const ResourceMapStewardIcon({
    required this.kind,
    this.size = ResourceMapPanelMetrics.navigationArtwork,
    super.key,
  });

  final ResourceMapStewardIconKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _ResourceMapStewardIconPainter(
          kind: kind,
          chrome: ResourceMapChromeTheme.of(context),
        ),
      ),
    );
  }
}

class _ResourceMapStewardIconPainter extends CustomPainter {
  const _ResourceMapStewardIconPainter({
    required this.kind,
    required this.chrome,
  });

  final ResourceMapStewardIconKind kind;
  final ResourceMapChromeThemeData chrome;

  Paint _fill(Color color) => Paint()
    ..style = PaintingStyle.fill
    ..color = color;

  Paint _line(Color color, [double width = 2.2]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / 64;
    canvas.save();
    canvas.translate(
      (size.width - (64 * scale)) / 2,
      (size.height - (64 * scale)) / 2,
    );
    canvas.scale(scale);
    switch (kind) {
      case ResourceMapStewardIconKind.gatherMode:
      case ResourceMapStewardIconKind.gatherTools:
        _paintGatherTools(canvas);
        break;
      case ResourceMapStewardIconKind.workersMode:
        _paintWorkers(canvas);
        break;
      case ResourceMapStewardIconKind.search:
        _paintFind(canvas);
        break;
      case ResourceMapStewardIconKind.plan:
        _paintPlan(canvas);
        break;
      case ResourceMapStewardIconKind.explore:
        _paintExplore(canvas);
        break;
      case ResourceMapStewardIconKind.manage:
        _paintManage(canvas);
        break;
      case ResourceMapStewardIconKind.browse:
        _paintBrowse(canvas);
        break;
      case ResourceMapStewardIconKind.needed:
        _paintNeeded(canvas);
        break;
      case ResourceMapStewardIconKind.checklist:
        _paintChecklist(canvas);
        break;
      case ResourceMapStewardIconKind.favorites:
        _paintFavorites(canvas);
        break;
      case ResourceMapStewardIconKind.specificItems:
        _paintSpecific(canvas);
        break;
      case ResourceMapStewardIconKind.bestIncome:
        _paintIncome(canvas);
        break;
      case ResourceMapStewardIconKind.findNodes:
        _paintFind(canvas);
        break;
      case ResourceMapStewardIconKind.connections:
        _paintConnections(canvas);
        break;
      case ResourceMapStewardIconKind.invest:
        _paintInvest(canvas);
        break;
      case ResourceMapStewardIconKind.houses:
        _paintHouses(canvas);
        break;
      case ResourceMapStewardIconKind.plantsWood:
        _paintPlantsWood(canvas);
        break;
      case ResourceMapStewardIconKind.oresMinerals:
        _paintOres(canvas);
        break;
      case ResourceMapStewardIconKind.meat:
        _paintMeat(canvas);
        break;
      case ResourceMapStewardIconKind.bloodHides:
        _paintBloodHides(canvas);
        break;
      case ResourceMapStewardIconKind.mushrooms:
        _paintMushrooms(canvas);
        break;
      case ResourceMapStewardIconKind.coastal:
        _paintCoastal(canvas);
        break;
      case ResourceMapStewardIconKind.other:
        _paintOther(canvas);
        break;
    }
    canvas.restore();
  }

  Color get _outline => chrome.chromeBase.withValues(alpha: .96);
  Color get _paper => Color.lerp(chrome.ink, const Color(0xFFEAD49B), .46)!;
  Color get _paperShade => Color.lerp(_paper, chrome.trimDeep, .28)!;
  Color get _brass => Color.lerp(chrome.accent, const Color(0xFFD3A64C), .38)!;
  Color get _brassDark => Color.lerp(_brass, chrome.chromeBase, .38)!;
  Color get _leather =>
      Color.lerp(chrome.deepAccent, const Color(0xFF753B37), .45)!;
  Color get _wood => Color.lerp(chrome.trimDeep, const Color(0xFF6A452B), .48)!;
  Color get _emerald =>
      Color.lerp(chrome.positive, const Color(0xFF2C8B72), .5)!;

  void _shadow(Canvas canvas, Path path, {double elevation = 3}) {
    canvas.drawShadow(path, const Color(0xE6000000), elevation, true);
  }

  void _paintGatherTools(Canvas c) {
    final basket = Path()
      ..moveTo(11, 29)
      ..lineTo(53, 27)
      ..lineTo(47, 53)
      ..lineTo(16, 54)
      ..close();
    _shadow(c, basket);
    c.drawPath(basket, _fill(_wood));
    c.drawPath(basket, _line(_outline, 2.7));
    for (final y in <double>[35, 42, 49]) {
      c.drawLine(Offset(15, y), Offset(49, y - 1), _line(_brassDark, 1.4));
    }
    c.drawArc(
      const Rect.fromLTWH(17, 14, 30, 27),
      math.pi,
      math.pi,
      false,
      _line(_brass, 3),
    );
    c.drawPath(
      Path()
        ..moveTo(27, 30)
        ..quadraticBezierTo(24, 18, 16, 12)
        ..quadraticBezierTo(29, 13, 32, 28),
      _line(_emerald, 3),
    );
    c.drawOval(const Rect.fromLTWH(12, 10, 12, 7), _fill(_emerald));
    c.drawOval(const Rect.fromLTWH(23, 17, 13, 7), _fill(_emerald));
    c.drawArc(
      const Rect.fromLTWH(37, 7, 18, 23),
      -.7,
      2.8,
      false,
      _line(_paper, 3.1),
    );
    c.drawLine(const Offset(47, 25), const Offset(55, 40), _line(_brass, 3));
  }

  void _paintWorkers(Canvas c) {
    _paintManage(c);
    c.drawLine(const Offset(15, 12), const Offset(28, 7), _line(_brass, 2));
    c.drawLine(const Offset(28, 7), const Offset(46, 12), _line(_brass, 2));
    for (final point in <Offset>[
      const Offset(14, 12),
      const Offset(29, 7),
      const Offset(47, 12),
    ]) {
      c.drawCircle(point, 4.5, _fill(_brass));
      c.drawCircle(point, 4.5, _line(_outline, 1.5));
    }
  }

  void _paintBrowse(Canvas c) {
    final cabinet = RRect.fromRectAndRadius(
      const Rect.fromLTWH(9, 17, 45, 39),
      const Radius.circular(3),
    );
    _shadow(c, Path()..addRRect(cabinet));
    c.drawRRect(cabinet, _fill(_wood));
    c.drawRRect(cabinet, _line(_outline, 2.8));
    for (var row = 0; row < 3; row += 1) {
      final rect = Rect.fromLTWH(14, 22.0 + (row * 10), 35, 8);
      c.drawRect(rect, _fill(row == 1 ? _paper : _paperShade));
      c.drawRect(rect, _line(_brassDark, 1.2));
      c.drawCircle(Offset(31.5, 26.0 + (row * 10)), 1.5, _fill(_brass));
    }
    final card = Path()
      ..moveTo(18, 8)
      ..lineTo(43, 10)
      ..lineTo(41, 22)
      ..lineTo(17, 20)
      ..close();
    c.drawPath(card, _fill(_paper));
    c.drawPath(card, _line(_outline, 1.8));
    c.drawLine(
      const Offset(23, 14),
      const Offset(36, 15),
      _line(_emerald, 1.8),
    );
  }

  void _paintFavorites(Canvas c) {
    final docket = Path()
      ..moveTo(17, 9)
      ..lineTo(46, 12)
      ..lineTo(43, 52)
      ..lineTo(14, 49)
      ..close();
    _shadow(c, docket);
    c.drawPath(docket, _fill(_paper));
    c.drawPath(docket, _line(_outline, 2.5));
    c.drawPath(
      Path()
        ..moveTo(24, 11)
        ..lineTo(34, 12)
        ..lineTo(33, 31)
        ..lineTo(28, 27)
        ..lineTo(23, 30)
        ..close(),
      _fill(_leather),
    );
    c.drawCircle(const Offset(42, 43), 10, _fill(_brass));
    c.drawCircle(const Offset(42, 43), 10, _line(_outline, 2.3));
    c.drawPath(
      Path()
        ..moveTo(42, 36)
        ..lineTo(44, 41)
        ..lineTo(50, 41)
        ..lineTo(45, 45)
        ..lineTo(47, 51)
        ..lineTo(42, 47)
        ..lineTo(37, 51)
        ..lineTo(39, 45)
        ..lineTo(34, 41)
        ..lineTo(40, 41)
        ..close(),
      _fill(_emerald),
    );
  }

  void _paintPlantsWood(Canvas c) {
    final log = RRect.fromRectAndRadius(
      const Rect.fromLTWH(11, 39, 39, 14),
      const Radius.circular(7),
    );
    _shadow(c, Path()..addRRect(log));
    c.drawRRect(log, _fill(_wood));
    c.drawRRect(log, _line(_outline, 2.5));
    c.drawOval(const Rect.fromLTWH(42, 39, 14, 14), _fill(_paperShade));
    c.drawOval(const Rect.fromLTWH(42, 39, 14, 14), _line(_outline, 2.1));
    c.drawArc(
      const Rect.fromLTWH(46, 43, 6, 6),
      0,
      math.pi * 1.7,
      false,
      _line(_wood, 1.4),
    );
    c.drawLine(const Offset(21, 43), const Offset(38, 15), _line(_wood, 3.5));
    for (final leaf in <Rect>[
      const Rect.fromLTWH(12, 28, 16, 9),
      const Rect.fromLTWH(29, 18, 17, 9),
      const Rect.fromLTWH(22, 9, 15, 9),
      const Rect.fromLTWH(31, 30, 16, 9),
    ]) {
      c.drawOval(leaf, _fill(_emerald));
      c.drawOval(leaf, _line(_outline, 1.3));
    }
    c.drawLine(const Offset(17, 33), const Offset(25, 31), _line(_paper, 1));
    c.drawLine(const Offset(34, 23), const Offset(41, 22), _line(_paper, 1));
  }

  void _paintOres(Canvas c) {
    final ore = Path()
      ..moveTo(9, 43)
      ..lineTo(17, 22)
      ..lineTo(31, 10)
      ..lineTo(49, 18)
      ..lineTo(56, 39)
      ..lineTo(45, 53)
      ..lineTo(22, 55)
      ..close();
    _shadow(c, ore);
    c.drawPath(ore, _fill(_paperShade));
    c.drawPath(ore, _line(_outline, 2.8));
    c.drawPath(
      Path()
        ..moveTo(17, 22)
        ..lineTo(31, 10)
        ..lineTo(34, 34)
        ..lineTo(9, 43)
        ..close(),
      _fill(_brassDark),
    );
    c.drawPath(
      Path()
        ..moveTo(31, 10)
        ..lineTo(49, 18)
        ..lineTo(34, 34)
        ..close(),
      _fill(_emerald),
    );
    c.drawPath(
      Path()
        ..moveTo(34, 34)
        ..lineTo(49, 18)
        ..lineTo(56, 39)
        ..lineTo(45, 53)
        ..close(),
      _fill(Color.lerp(_paperShade, const Color(0xFF7797A8), .55)!),
    );
    c.drawLine(
      const Offset(34, 34),
      const Offset(22, 55),
      _line(_outline, 1.4),
    );
    c.drawLine(
      const Offset(34, 34),
      const Offset(45, 53),
      _line(_outline, 1.4),
    );
    c.drawPath(ore, _line(_outline, 2.8));
  }

  void _paintMeat(Canvas c) {
    final cut = Path()
      ..moveTo(10, 34)
      ..quadraticBezierTo(15, 15, 34, 13)
      ..quadraticBezierTo(53, 12, 57, 30)
      ..quadraticBezierTo(59, 47, 40, 54)
      ..quadraticBezierTo(20, 59, 10, 44)
      ..quadraticBezierTo(7, 40, 10, 34)
      ..close();
    _shadow(c, cut);
    c.drawPath(cut, _fill(_leather));
    c.drawPath(cut, _line(_paper, 3.2));
    c.drawOval(const Rect.fromLTWH(31, 25, 15, 13), _fill(_paper));
    c.drawOval(const Rect.fromLTWH(35, 28, 8, 7), _fill(_brassDark));
    c.drawPath(
      Path()
        ..moveTo(16, 34)
        ..quadraticBezierTo(22, 21, 31, 20)
        ..quadraticBezierTo(21, 29, 19, 43),
      _line(Color.lerp(_paper, _leather, .32)!, 2.2),
    );
  }

  void _paintBloodHides(Canvas c) {
    final hide = Path()
      ..moveTo(9, 16)
      ..quadraticBezierTo(23, 11, 33, 18)
      ..lineTo(29, 49)
      ..quadraticBezierTo(17, 56, 9, 47)
      ..close();
    _shadow(c, hide);
    c.drawPath(hide, _fill(_paperShade));
    c.drawPath(hide, _line(_outline, 2.5));
    final vial = RRect.fromRectAndRadius(
      const Rect.fromLTWH(34, 18, 17, 35),
      const Radius.circular(5),
    );
    c.drawRRect(vial, _fill(chrome.chromeHighlight));
    c.drawRRect(vial, _line(_brass, 2.4));
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(37, 33, 11, 17),
        const Radius.circular(3),
      ),
      _fill(_leather),
    );
    c.drawRect(const Rect.fromLTWH(37, 11, 11, 10), _fill(_wood));
    c.drawRect(const Rect.fromLTWH(37, 11, 11, 10), _line(_outline, 1.5));
  }

  void _paintMushrooms(Canvas c) {
    final cluster = Path()..addOval(const Rect.fromLTWH(10, 42, 45, 12));
    _shadow(c, cluster);
    c.drawPath(cluster, _fill(_wood.withValues(alpha: .72)));
    for (final mushroom in <(double, double, double)>[
      (18, 29, 18),
      (35, 20, 24),
      (49, 34, 15),
    ]) {
      c.drawLine(
        Offset(mushroom.$1, mushroom.$2),
        Offset(mushroom.$1, 48),
        _line(_paper, mushroom.$3 > 20 ? 6 : 4.5),
      );
      final cap = Path()
        ..moveTo(mushroom.$1 - mushroom.$3 / 2, mushroom.$2)
        ..quadraticBezierTo(
          mushroom.$1,
          mushroom.$2 - mushroom.$3 * .76,
          mushroom.$1 + mushroom.$3 / 2,
          mushroom.$2,
        )
        ..quadraticBezierTo(
          mushroom.$1,
          mushroom.$2 + 4,
          mushroom.$1 - mushroom.$3 / 2,
          mushroom.$2,
        )
        ..close();
      c.drawPath(cap, _fill(mushroom.$1 == 35 ? _leather : _emerald));
      c.drawPath(cap, _line(_outline, 1.8));
      c.drawCircle(
        Offset(mushroom.$1 - mushroom.$3 * .13, mushroom.$2 - 4),
        1.5,
        _fill(_paper),
      );
    }
  }

  void _paintCoastal(Canvas c) {
    final body = Path()..addOval(const Rect.fromLTWH(16, 22, 33, 25));
    _shadow(c, body);
    c.drawPath(body, _fill(_leather));
    c.drawPath(body, _line(_outline, 2.5));
    for (final pair in <(Offset, Offset)>[
      (const Offset(19, 33), const Offset(7, 26)),
      (const Offset(18, 38), const Offset(6, 43)),
      (const Offset(46, 33), const Offset(57, 25)),
      (const Offset(46, 39), const Offset(58, 45)),
    ]) {
      c.drawLine(pair.$1, pair.$2, _line(_brass, 3));
    }
    c.drawPath(
      Path()
        ..moveTo(9, 26)
        ..quadraticBezierTo(3, 17, 11, 13)
        ..quadraticBezierTo(20, 17, 15, 25)
        ..close(),
      _fill(_leather),
    );
    c.drawPath(
      Path()
        ..moveTo(54, 25)
        ..quadraticBezierTo(61, 16, 54, 12)
        ..quadraticBezierTo(45, 16, 49, 25)
        ..close(),
      _fill(_leather),
    );
    c.drawCircle(const Offset(26, 27), 2.5, _fill(_paper));
    c.drawCircle(const Offset(39, 27), 2.5, _fill(_paper));
    c.drawCircle(const Offset(26, 27), 1.2, _fill(_outline));
    c.drawCircle(const Offset(39, 27), 1.2, _fill(_outline));
    c.drawArc(
      const Rect.fromLTWH(23, 30, 19, 10),
      .15,
      math.pi * .85,
      false,
      _line(_paperShade, 1.6),
    );
  }

  void _paintPlan(Canvas c) {
    final book = Path()
      ..moveTo(10, 14)
      ..lineTo(50, 12)
      ..quadraticBezierTo(55, 13, 54, 18)
      ..lineTo(51, 52)
      ..lineTo(13, 54)
      ..quadraticBezierTo(9, 52, 10, 47)
      ..close();
    _shadow(c, book);
    c.drawPath(book, _fill(_leather));
    c.drawPath(book, _line(_outline, 3));
    final page = RRect.fromRectAndRadius(
      const Rect.fromLTWH(15, 17, 31, 31),
      const Radius.circular(2),
    );
    c.drawRRect(page, _fill(_paper));
    c.drawRRect(page, _line(_brassDark, 1.8));
    c.drawLine(const Offset(23, 24), const Offset(40, 23), _line(_leather, 2));
    c.drawLine(
      const Offset(20, 31),
      const Offset(41, 30),
      _line(_brassDark, 1.8),
    );
    c.drawLine(
      const Offset(20, 37),
      const Offset(35, 36),
      _line(_brassDark, 1.8),
    );
    c.drawPath(
      Path()
        ..moveTo(19, 17)
        ..lineTo(24, 17)
        ..lineTo(23, 31)
        ..lineTo(20.5, 27)
        ..lineTo(18, 31)
        ..close(),
      _fill(_emerald),
    );
    c.drawCircle(const Offset(45, 43), 5.2, _fill(_brass));
    c.drawCircle(const Offset(45, 43), 5.2, _line(_outline, 1.8));
  }

  void _paintExplore(Canvas c) {
    final globe = Path()..addOval(const Rect.fromLTWH(13, 9, 36, 36));
    _shadow(c, globe);
    c.drawPath(globe, _fill(_emerald));
    c.drawPath(globe, _line(_brass, 3));
    c.drawOval(const Rect.fromLTWH(22, 10, 18, 34), _line(_paper, 1.6));
    c.drawArc(
      const Rect.fromLTWH(14, 20, 34, 15),
      0,
      math.pi * 2,
      false,
      _line(_paper, 1.6),
    );
    c.drawArc(
      const Rect.fromLTWH(8, 5, 47, 47),
      -.95,
      3.15,
      false,
      _line(_brass, 3),
    );
    c.drawLine(
      const Offset(32, 45),
      const Offset(32, 53),
      _line(_brassDark, 3),
    );
    c.drawPath(
      Path()
        ..moveTo(21, 56)
        ..quadraticBezierTo(32, 49, 43, 56)
        ..close(),
      _fill(_wood),
    );
    c.drawLine(const Offset(20, 56), const Offset(44, 56), _line(_outline, 3));
  }

  void _paintManage(Canvas c) {
    final book = Path()
      ..moveTo(8, 17)
      ..quadraticBezierTo(21, 12, 31, 18)
      ..quadraticBezierTo(42, 12, 56, 17)
      ..lineTo(53, 50)
      ..quadraticBezierTo(42, 46, 31, 52)
      ..quadraticBezierTo(20, 46, 11, 50)
      ..close();
    _shadow(c, book);
    c.drawPath(book, _fill(_paper));
    c.drawPath(book, _line(_outline, 2.6));
    c.drawLine(
      const Offset(31, 18),
      const Offset(31, 51),
      _line(_leather, 2.2),
    );
    for (final y in <double>[25, 32, 39]) {
      c.drawLine(Offset(15, y), Offset(27, y - 1), _line(_brassDark, 1.4));
    }
    final frame = RRect.fromRectAndRadius(
      const Rect.fromLTWH(34, 23, 17, 22),
      const Radius.circular(2),
    );
    c.drawRRect(frame, _fill(_wood));
    c.drawRRect(frame, _line(_brass, 1.8));
    for (var row = 0; row < 3; row += 1) {
      final y = 28.0 + row * 6;
      c.drawLine(Offset(37, y), Offset(48, y), _line(_paperShade, 1));
      c.drawCircle(
        Offset(row.isEven ? 41 : 45, y),
        2.1,
        _fill(row == 1 ? _emerald : _brass),
      );
    }
  }

  void _paintNeeded(Canvas c) {
    final back = RRect.fromRectAndRadius(
      const Rect.fromLTWH(16, 10, 34, 42),
      const Radius.circular(3),
    );
    _shadow(c, Path()..addRRect(back));
    c.drawRRect(back, _fill(_leather));
    final sheet = Path()
      ..moveTo(11, 15)
      ..lineTo(43, 12)
      ..lineTo(48, 47)
      ..lineTo(16, 51)
      ..close();
    c.drawPath(sheet, _fill(_paper));
    c.drawPath(sheet, _line(_outline, 2.4));
    for (var i = 0; i < 3; i += 1) {
      final y = 23.0 + i * 7;
      c.drawPath(
        Path()
          ..moveTo(18, y)
          ..lineTo(21, y + 3)
          ..lineTo(26, y - 2),
        _line(_emerald, 2.5),
      );
      c.drawLine(Offset(29, y), Offset(40, y - 1), _line(_brassDark, 1.5));
    }
    c.drawCircle(const Offset(47, 46), 8, _fill(_leather));
    c.drawCircle(const Offset(47, 46), 8, _line(_brass, 2));
    c.drawCircle(const Offset(47, 46), 3.5, _fill(_brass));
  }

  void _paintChecklist(Canvas c) {
    final board = RRect.fromRectAndRadius(
      const Rect.fromLTWH(12, 10, 39, 46),
      const Radius.circular(4),
    );
    _shadow(c, Path()..addRRect(board));
    c.drawRRect(board, _fill(_wood));
    c.drawRRect(board, _line(_outline, 2.7));
    final paper = RRect.fromRectAndRadius(
      const Rect.fromLTWH(17, 16, 29, 34),
      const Radius.circular(2),
    );
    c.drawRRect(paper, _fill(_paper));
    c.drawRRect(paper, _line(_brassDark, 1.4));
    final clip = RRect.fromRectAndRadius(
      const Rect.fromLTWH(24, 7, 15, 12),
      const Radius.circular(3),
    );
    c.drawRRect(clip, _fill(_brass));
    c.drawRRect(clip, _line(_outline, 1.8));
    for (var index = 0; index < 3; index += 1) {
      final y = 25.0 + (index * 8);
      c.drawPath(
        Path()
          ..moveTo(21, y)
          ..lineTo(24, y + 3)
          ..lineTo(29, y - 2),
        _line(_emerald, 2.5),
      );
      c.drawLine(Offset(32, y), Offset(42, y - 1), _line(_leather, 1.5));
    }
  }

  void _paintOther(Canvas c) {
    final box = Path()
      ..moveTo(8, 23)
      ..lineTo(53, 18)
      ..lineTo(57, 48)
      ..lineTo(13, 55)
      ..close();
    _shadow(c, box);
    c.drawPath(box, _fill(_wood));
    c.drawPath(box, _line(_outline, 2.8));
    c.drawLine(const Offset(11, 31), const Offset(55, 25), _line(_brass, 2));
    final label = Path()
      ..moveTo(21, 28)
      ..lineTo(43, 25)
      ..lineTo(45, 38)
      ..lineTo(23, 41)
      ..close();
    c.drawPath(label, _fill(_paper));
    c.drawPath(label, _line(_brassDark, 1.4));
    c.drawCircle(const Offset(29, 34), 3.5, _fill(_emerald));
    c.drawCircle(const Offset(38, 32), 3.5, _fill(_leather));
    c.drawPath(
      Path()
        ..moveTo(18, 19)
        ..quadraticBezierTo(23, 10, 30, 17)
        ..quadraticBezierTo(37, 8, 44, 16),
      _line(_paper, 3),
    );
  }

  void _paintSpecific(Canvas c) {
    final tray = Path()
      ..moveTo(8, 22)
      ..lineTo(46, 18)
      ..lineTo(53, 43)
      ..lineTo(14, 49)
      ..close();
    _shadow(c, tray);
    c.drawPath(tray, _fill(_wood));
    c.drawPath(tray, _line(_outline, 2.8));
    c.drawPath(
      Path()
        ..moveTo(17, 31)
        ..lineTo(26, 26)
        ..lineTo(34, 32)
        ..lineTo(29, 41)
        ..lineTo(20, 40)
        ..close(),
      _fill(_emerald),
    );
    c.drawPath(
      Path()
        ..moveTo(17, 31)
        ..lineTo(26, 26)
        ..lineTo(34, 32)
        ..lineTo(29, 41)
        ..lineTo(20, 40)
        ..close(),
      _line(_paper, 1.5),
    );
    c.drawCircle(const Offset(43, 20), 9, _fill(chrome.chromeHighlight));
    c.drawCircle(const Offset(43, 20), 9, _line(_brass, 3));
    c.drawLine(const Offset(49, 27), const Offset(57, 37), _line(_brass, 4));
    c.drawLine(
      const Offset(50, 28),
      const Offset(57, 37),
      _line(_outline, 1.4),
    );
  }

  void _paintIncome(Canvas c) {
    c.drawLine(const Offset(31, 12), const Offset(31, 49), _line(_brass, 3.4));
    c.drawLine(const Offset(15, 20), const Offset(47, 20), _line(_brass, 3.4));
    c.drawCircle(const Offset(31, 13), 4, _fill(_emerald));
    c.drawCircle(const Offset(31, 13), 4, _line(_outline, 1.5));
    c.drawLine(
      const Offset(18, 21),
      const Offset(13, 35),
      _line(_brassDark, 1.8),
    );
    c.drawLine(
      const Offset(18, 21),
      const Offset(23, 35),
      _line(_brassDark, 1.8),
    );
    c.drawLine(
      const Offset(44, 21),
      const Offset(38, 32),
      _line(_brassDark, 1.8),
    );
    c.drawLine(
      const Offset(44, 21),
      const Offset(51, 32),
      _line(_brassDark, 1.8),
    );
    c.drawArc(
      const Rect.fromLTWH(9, 31, 18, 11),
      0,
      math.pi,
      false,
      _line(_paper, 2.4),
    );
    c.drawArc(
      const Rect.fromLTWH(34, 28, 21, 12),
      0,
      math.pi,
      false,
      _line(_paper, 2.4),
    );
    c.drawPath(
      Path()
        ..moveTo(20, 52)
        ..lineTo(42, 52)
        ..lineTo(47, 57)
        ..lineTo(15, 57)
        ..close(),
      _fill(_wood),
    );
    c.drawLine(
      const Offset(14, 57),
      const Offset(48, 57),
      _line(_outline, 2.6),
    );
    for (var i = 0; i < 3; i += 1) {
      c.drawOval(
        Rect.fromLTWH(39.0 + i * 2, 36.0 - i * 4, 10, 5),
        _fill(_brass),
      );
      c.drawOval(
        Rect.fromLTWH(39.0 + i * 2, 36.0 - i * 4, 10, 5),
        _line(_outline, 1),
      );
    }
  }

  void _paintFind(Canvas c) {
    final cabinet = RRect.fromRectAndRadius(
      const Rect.fromLTWH(8, 22, 40, 30),
      const Radius.circular(3),
    );
    _shadow(c, Path()..addRRect(cabinet));
    c.drawRRect(cabinet, _fill(_wood));
    c.drawRRect(cabinet, _line(_outline, 2.8));
    c.drawRect(const Rect.fromLTWH(13, 27, 29, 10), _fill(_paperShade));
    c.drawRect(const Rect.fromLTWH(13, 27, 29, 10), _line(_brassDark, 1.4));
    c.drawCircle(const Offset(28, 32), 1.6, _fill(_brass));
    final card = Path()
      ..moveTo(17, 12)
      ..lineTo(42, 10)
      ..lineTo(44, 27)
      ..lineTo(20, 29)
      ..close();
    c.drawPath(card, _fill(_paper));
    c.drawPath(card, _line(_outline, 2));
    c.drawCircle(const Offset(48, 19), 8, _fill(chrome.chromeHighlight));
    c.drawCircle(const Offset(48, 19), 8, _line(_brass, 2.8));
    c.drawLine(const Offset(53, 25), const Offset(59, 33), _line(_brass, 3.8));
  }

  void _paintConnections(Canvas c) {
    final chain = _line(_brass, 3.2);
    c.drawLine(const Offset(18, 24), const Offset(32, 34), chain);
    c.drawLine(const Offset(32, 34), const Offset(48, 21), chain);
    c.drawLine(const Offset(32, 34), const Offset(43, 49), chain);
    for (final point in <Offset>[
      const Offset(17, 23),
      const Offset(48, 20),
      const Offset(43, 49),
    ]) {
      c.drawCircle(point, 9, _fill(_leather));
      c.drawCircle(point, 9, _line(_outline, 2.5));
      c.drawCircle(point, 6, _line(_brass, 2));
      c.drawCircle(point, 2.4, _fill(_emerald));
    }
    c.drawCircle(const Offset(32, 34), 6, _fill(_brass));
    c.drawCircle(const Offset(32, 34), 6, _line(_outline, 2));
  }

  void _paintInvest(Canvas c) {
    final contract = Path()
      ..moveTo(12, 10)
      ..lineTo(47, 13)
      ..lineTo(44, 54)
      ..lineTo(9, 50)
      ..close();
    _shadow(c, contract);
    c.drawPath(contract, _fill(_paper));
    c.drawPath(contract, _line(_outline, 2.6));
    c.drawLine(const Offset(18, 20), const Offset(39, 22), _line(_leather, 2));
    c.drawLine(
      const Offset(17, 28),
      const Offset(36, 30),
      _line(_brassDark, 1.5),
    );
    c.drawLine(
      const Offset(16, 35),
      const Offset(32, 37),
      _line(_brassDark, 1.5),
    );
    c.drawPath(
      Path()
        ..moveTo(17, 44)
        ..quadraticBezierTo(24, 38, 30, 44)
        ..quadraticBezierTo(35, 48, 40, 42),
      _line(_leather, 2.1),
    );
    c.drawCircle(const Offset(47, 45), 10, _fill(_brass));
    c.drawCircle(const Offset(47, 45), 10, _line(_outline, 2.6));
    c.drawPath(
      Path()
        ..moveTo(42, 45)
        ..lineTo(46, 49)
        ..lineTo(53, 41),
      _line(_emerald, 3.4),
    );
  }

  void _paintHouses(Canvas c) {
    final deed = RRect.fromRectAndRadius(
      const Rect.fromLTWH(10, 12, 34, 42),
      const Radius.circular(3),
    );
    _shadow(c, Path()..addRRect(deed));
    c.drawRRect(deed, _fill(_paper));
    c.drawRRect(deed, _line(_outline, 2.5));
    c.drawPath(
      Path()
        ..moveTo(16, 31)
        ..lineTo(27, 21)
        ..lineTo(39, 31)
        ..lineTo(36, 31)
        ..lineTo(36, 43)
        ..lineTo(19, 43)
        ..lineTo(19, 31)
        ..close(),
      _fill(_leather),
    );
    c.drawPath(
      Path()
        ..moveTo(16, 31)
        ..lineTo(27, 21)
        ..lineTo(39, 31),
      _line(_brass, 2.4),
    );
    c.drawCircle(const Offset(46, 24), 6.5, _fill(chrome.chromeHighlight));
    c.drawCircle(const Offset(46, 24), 6.5, _line(_brass, 3));
    c.drawLine(const Offset(50, 29), const Offset(59, 41), _line(_brass, 4));
    c.drawLine(const Offset(55, 36), const Offset(51, 40), _line(_brass, 2.5));
    c.drawLine(const Offset(58, 39), const Offset(54, 43), _line(_brass, 2.5));
  }

  @override
  bool shouldRepaint(covariant _ResourceMapStewardIconPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.chrome != chrome;
}
