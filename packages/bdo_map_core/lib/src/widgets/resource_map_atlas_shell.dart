import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'resource_map_chrome_theme.dart';
import 'resource_map_panel_metrics.dart';
import 'resource_map_pill.dart';

bool _ghostLedger(BuildContext context) =>
    context.mapChrome.variant == ResourceMapChromeThemeVariant.ghostLedger;

// Contrast comes from the reading plane, not a blurred duplicate of each glyph.
const _glassTextShadows = <Shadow>[];

const _glassTextTheme = TextTheme(
  bodyLarge: TextStyle(
    fontSize: ResourceMapPanelMetrics.primary,
    shadows: _glassTextShadows,
  ),
  bodyMedium: TextStyle(
    fontSize: ResourceMapPanelMetrics.primary,
    shadows: _glassTextShadows,
  ),
  bodySmall: TextStyle(
    fontSize: ResourceMapPanelMetrics.secondary,
    shadows: _glassTextShadows,
  ),
  labelLarge: TextStyle(
    fontSize: ResourceMapPanelMetrics.primary,
    shadows: _glassTextShadows,
  ),
  labelMedium: TextStyle(
    fontSize: ResourceMapPanelMetrics.primary,
    shadows: _glassTextShadows,
  ),
  labelSmall: TextStyle(
    fontSize: ResourceMapPanelMetrics.secondary,
    shadows: _glassTextShadows,
  ),
  titleLarge: TextStyle(
    fontSize: ResourceMapPanelMetrics.heading,
    shadows: _glassTextShadows,
  ),
  titleMedium: TextStyle(
    fontSize: ResourceMapPanelMetrics.primary,
    shadows: _glassTextShadows,
  ),
  titleSmall: TextStyle(
    fontSize: ResourceMapPanelMetrics.primary,
    shadows: _glassTextShadows,
  ),
);

/// Compact, map-native desktop controls that leave the geographic canvas in
/// charge of the screen.
abstract final class ResourceMapAtlasMotion {
  static const Duration quick = Duration(milliseconds: 130);
  static const Duration enter = Duration(milliseconds: 210);
  static const Duration settle = Duration(milliseconds: 280);
  static const Curve curve = Curves.easeOutCubic;

  static Duration resolve(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

@immutable
class ResourceMapAtlasDockAction {
  const ResourceMapAtlasDockAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    this.badge,
  });

  final Key key;
  final String label;
  final Widget icon;
  final VoidCallback onPressed;
  final bool selected;
  final String? badge;
}

/// One stable search/navigation surface. Its tabs wrap at large text sizes;
/// only the task below it changes when the user chooses a different tool.
class ResourceMapAtlasNavigator extends StatelessWidget {
  const ResourceMapAtlasNavigator({
    required this.actions,
    required this.search,
    required this.width,
    super.key,
  });

  final List<ResourceMapAtlasDockAction> actions;
  final Widget search;
  final double width;

  static TextStyle _style(BuildContext context) =>
      context.mapChrome.headingStyle(
        fontSize: ResourceMapPanelMetrics.primary,
        fontWeight: FontWeight.w600,
      );

  static String _label(ResourceMapAtlasDockAction action) => action.label;

  static double _actionWidth(
    BuildContext context,
    ResourceMapAtlasDockAction action,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: _label(action), style: _style(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width.ceilToDouble() + 24;
    painter.dispose();
    return width;
  }

  static double _rowHeight(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(ResourceMapPanelMetrics.primary) *
                  1.2 +
              16)
          .clamp(44, double.infinity);

  /// Height before the search field. Shared by the host's panel positioning.
  static double headerExtent(
    BuildContext context, {
    required double width,
    required List<ResourceMapAtlasDockAction> actions,
  }) {
    var rows = 1;
    var used = 0.0;
    final available = width - 12;
    for (final action in actions) {
      final itemWidth = _actionWidth(context, action).clamp(0, available);
      if (used > 0 && used + 4 + itemWidth > available) {
        rows++;
        used = 0;
      }
      used += (used == 0 ? 0 : 4) + itemWidth;
    }
    return rows * _rowHeight(context) + (rows - 1) * 4 + 18;
  }

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return SizedBox(
      width: width,
      child: _AtlasGlass(
        radius: chrome.surfaceRadius,
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              label: 'Map tools',
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final action in actions)
                    Semantics(
                      button: true,
                      selected: action.selected,
                      label: action.label,
                      child: Material(
                        key: action.key,
                        color: Colors.transparent,
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: action.selected
                                ? chrome.selectedCompactGradient
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            border: action.selected
                                ? Border.all(
                                    color: chrome.primary.withValues(alpha: .6),
                                  )
                                : null,
                          ),
                          child: InkWell(
                            onTap: action.onPressed,
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: _actionWidth(
                                context,
                                action,
                              ).clamp(0, width - 12),
                              height: _rowHeight(context),
                              child: Center(
                                child: Text(
                                  _label(action),
                                  style: _style(context),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            search,
          ],
        ),
      ),
    );
  }
}

/// A single place for discovery, results and the current task. Navigation
/// changes the content, rather than adding another floating menu to the map.
class ResourceMapJourneySurface extends StatelessWidget {
  const ResourceMapJourneySurface({
    required this.title,
    required this.child,
    this.search,
    this.controls,
    this.onBack,
    this.onHome,
    this.onSearch,
    this.onMinimize,
    this.unframed = false,
    this.framedBody = true,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? search;
  final Widget? controls;
  final VoidCallback? onBack;
  final VoidCallback? onHome;
  final VoidCallback? onSearch;
  final VoidCallback? onMinimize;
  final bool unframed;
  final bool framedBody;

  static double headerHeight(BuildContext context) =>
      math.max(36, MediaQuery.textScalerOf(context).scale(16) * 1.2 + 8);

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    if (unframed) {
      return Column(
        key: const ValueKey('resource-map-unframed-home'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (search != null) ...[
            _AtlasGlass(
              radius: chrome.surfaceRadius,
              padding: EdgeInsets.zero,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: ResourceMapPanelMetrics.searchHeight(context),
                ),
                child: search,
              ),
            ),
            const SizedBox(height: 4),
          ],
          if (controls != null) ...[controls!, const SizedBox(height: 4)],
          Flexible(child: child),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AtlasGlass(
          radius: chrome.surfaceRadius,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: headerHeight(context)),
            child: Row(
              children: [
                if (onBack != null)
                  _AtlasCompactButton(
                    key: const ValueKey('resource-map-task-back'),
                    tooltip: 'Back',
                    onPressed: onBack!,
                    icon: Icons.arrow_back_rounded,
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: chrome.headingStyle(
                      fontSize: ResourceMapPanelMetrics.heading,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onSearch != null)
                  _AtlasCompactButton(
                    key: const ValueKey('resource-map-search-button'),
                    tooltip: 'Search the map',
                    onPressed: onSearch!,
                    icon: Icons.search_rounded,
                  ),
                if (onHome != null)
                  _AtlasCompactButton(
                    key: const ValueKey('resource-map-home-button'),
                    tooltip: 'Map home',
                    onPressed: onHome!,
                    icon: Icons.home_outlined,
                  ),
                if (onMinimize != null)
                  _AtlasCompactButton(
                    key: const ValueKey(
                      'resource-map-atlas-workspace-minimize',
                    ),
                    tooltip: 'Minimize and use the map',
                    onPressed: onMinimize!,
                    icon: Icons.remove_rounded,
                  ),
              ],
            ),
          ),
        ),
        if (search != null) ...[
          const SizedBox(height: 4),
          _AtlasGlass(
            radius: chrome.surfaceRadius,
            padding: EdgeInsets.zero,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: ResourceMapPanelMetrics.searchHeight(context),
              ),
              child: search,
            ),
          ),
        ],
        if (controls != null) ...[const SizedBox(height: 4), controls!],
        const SizedBox(height: 4),
        Flexible(
          child: !framedBody
              ? child
              : _AtlasGlass(
                  radius: chrome.surfaceRadius,
                  padding: EdgeInsets.zero,
                  child: child,
                ),
        ),
      ],
    );
  }
}

/// The same reading surface as the navigation dock, positioned from the
/// selected map location using the panel's actual laid-out size.
class ResourceMapAnchoredDetails extends StatelessWidget {
  const ResourceMapAnchoredDetails({
    required this.anchor,
    required this.width,
    required this.child,
    super.key,
  });

  final Offset anchor;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomSingleChildLayout(
    delegate: ResourceMapDetailsPlacement(anchor: anchor, width: width),
    child: KeyedSubtree(
      key: const ValueKey('resource-map-anchored-details-surface'),
      child: _AtlasGlass(
        radius: context.mapChrome.surfaceRadius,
        padding: EdgeInsets.zero,
        child: child,
      ),
    ),
  );
}

class ResourceMapDetailsPlacement extends SingleChildLayoutDelegate {
  const ResourceMapDetailsPlacement({
    required this.anchor,
    required this.width,
  });

  final Offset anchor;
  final double width;
  static const inset = 12.0;
  static const gap = 32.0;

  @override
  BoxConstraints getConstraintsForChild(
    BoxConstraints constraints,
  ) => BoxConstraints(
    minWidth: math.min(width, math.max(0, constraints.maxWidth - inset * 2)),
    maxWidth: math.min(width, math.max(0, constraints.maxWidth - inset * 2)),
    maxHeight: math.max(0, constraints.maxHeight - inset * 2),
  );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final right = anchor.dx + gap;
    final left = right + childSize.width <= size.width - inset
        ? right
        : anchor.dx - gap - childSize.width;
    return Offset(
      left.clamp(inset, math.max(inset, size.width - childSize.width - inset)),
      (anchor.dy - 36).clamp(
        inset,
        math.max(inset, size.height - childSize.height - inset),
      ),
    );
  }

  @override
  bool shouldRelayout(ResourceMapDetailsPlacement oldDelegate) =>
      anchor != oldDelegate.anchor || width != oldDelegate.width;
}

class ResourceMapAtlasDock extends StatelessWidget {
  const ResourceMapAtlasDock({
    super.key,
    required this.primaryActions,
    this.secondaryActions = const <ResourceMapAtlasDockAction>[],
    this.maximumWidth,
  });

  final List<ResourceMapAtlasDockAction> primaryActions;
  final List<ResourceMapAtlasDockAction> secondaryActions;
  final double? maximumWidth;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final ghost = _ghostLedger(context);
    final radius = BorderRadius.circular(ghost ? 0 : 5);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maximumWidth ?? MediaQuery.sizeOf(context).width - 32,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Semantics(
          container: true,
          label: 'Map tools',
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: 18 * math.min(1, chrome.materialOpacity / .6),
                sigmaY: 18 * math.min(1, chrome.materialOpacity / .6),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: chrome.taskStripGradient,
                  border: ghost
                      ? Border(
                          bottom: BorderSide(
                            color: chrome.primary.withValues(alpha: .78),
                            width: 1,
                          ),
                        )
                      : Border.all(
                          color: chrome.softOutline.withValues(alpha: .52),
                        ),
                  borderRadius: radius,
                  boxShadow: chrome.subtleSurfaceShadows,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ghost ? 4 : 3,
                    vertical: ghost ? 0 : 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final action in primaryActions)
                        _AtlasDockButton(action: action),
                      if (secondaryActions.isNotEmpty) ...<Widget>[
                        Container(
                          width: 1,
                          height: ghost ? 16 : 22,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          color: chrome.softOutline.withValues(alpha: .58),
                        ),
                        for (final action in secondaryActions)
                          _AtlasDockButton(action: action),
                      ],
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

class _AtlasDockButton extends StatefulWidget {
  const _AtlasDockButton({required this.action});

  final ResourceMapAtlasDockAction action;

  @override
  State<_AtlasDockButton> createState() => _AtlasDockButtonState();
}

class _AtlasDockButtonState extends State<_AtlasDockButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final chrome = context.mapChrome;
    final ghost = _ghostLedger(context);
    final active = action.selected || _hovered;
    final label = ghost ? action.label.toUpperCase() : action.label;
    final labelStyle = TextStyle(
      color: chrome.ink,
      fontSize: ResourceMapPanelMetrics.primary,
      fontWeight: FontWeight.w700,
      letterSpacing: ghost ? .45 : .1,
      shadows: _glassTextShadows,
    );
    final labelMeasure = TextPainter(
      text: TextSpan(
        text: label,
        style: DefaultTextStyle.of(context).style.merge(labelStyle),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final buttonWidth =
        labelMeasure.width.ceilToDouble() +
        ResourceMapPanelMetrics.artwork +
        33;
    labelMeasure.dispose();
    return Semantics(
      button: true,
      selected: action.selected,
      label: action.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Tooltip(
          message: action.label,
          child: Material(
            key: action.key,
            color: Colors.transparent,
            child: InkWell(
              onTap: action.onPressed,
              borderRadius: BorderRadius.circular(ghost ? 0 : 4),
              child: SizedBox(
                width: buttonWidth,
                height: 48,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: <Widget>[
                    AnimatedContainer(
                      duration: ResourceMapAtlasMotion.resolve(
                        context,
                        ResourceMapAtlasMotion.quick,
                      ),
                      width: buttonWidth - 4,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _hovered
                            ? chrome.primary.withValues(
                                alpha: ghost ? .055 : .1,
                              )
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(ghost ? 0 : 4),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        SizedBox.square(
                          dimension: ResourceMapPanelMetrics.artwork,
                          child: IconTheme(
                            data: IconThemeData(
                              size: ResourceMapPanelMetrics.artwork,
                              color: active ? chrome.primary : chrome.text,
                              shadows: _glassTextShadows,
                            ),
                            child: action.icon,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text(label, style: labelStyle, maxLines: 1),
                      ],
                    ),
                    AnimatedPositioned(
                      duration: ResourceMapAtlasMotion.resolve(
                        context,
                        ResourceMapAtlasMotion.quick,
                      ),
                      left: action.selected ? 11 : buttonWidth / 2,
                      right: action.selected ? 11 : buttonWidth / 2,
                      bottom: ghost ? 0 : 2,
                      height: ghost ? 1 : 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: chrome.primary,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
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

@immutable
class ResourceMapAtlasCommandAction {
  const ResourceMapAtlasCommandAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.badge,
    this.selected = false,
    this.semanticHint,
  });

  final Key key;
  final String label;
  final Widget icon;
  final VoidCallback onPressed;
  final String? badge;
  final bool selected;
  final String? semanticHint;
}

/// Separate map choices. Only each option has backing; list gaps stay clear.
class ResourceMapAtlasCommandMenu extends StatelessWidget {
  const ResourceMapAtlasCommandMenu({
    super.key,
    required this.semanticsLabel,
    required this.actions,
    this.maximumHeight = 390,
    this.setupActions = const <ResourceMapAtlasCommandAction>[],
    this.framed = true,
  });

  static const double preferredWidth = ResourceMapPanelMetrics.menuWidth;
  static const double labelFontSize = ResourceMapPanelMetrics.optionLabel;
  static const double artworkSize = ResourceMapPanelMetrics.optionArtwork;
  static const double rowHeight = ResourceMapPanelMetrics.optionHeight;

  final String semanticsLabel;
  final List<ResourceMapAtlasCommandAction> actions;
  final double maximumHeight;
  final List<ResourceMapAtlasCommandAction> setupActions;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    if (!framed) {
      return SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in actions) _AtlasCommandRow(action: action),
            for (final action in setupActions) _AtlasCommandRow(action: action),
          ],
        ),
      );
    }
    final duration = ResourceMapAtlasMotion.resolve(
      context,
      ResourceMapAtlasMotion.enter,
    );
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: .965, end: 1),
        duration: duration,
        curve: ResourceMapAtlasMotion.curve,
        builder: (context, value, child) => Opacity(
          opacity: ((value - .965) / .035).clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 90),
            child: Transform.scale(
              scale: value,
              alignment: Alignment.topLeft,
              child: child,
            ),
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maximumHeight),
          child: SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final action in actions) _AtlasCommandRow(action: action),
                if (setupActions.isNotEmpty)
                  ExpansionTile(
                    key: const ValueKey<String>('resource-map-your-setup'),
                    maintainState: true,
                    tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                    title: Text(
                      'Your setup',
                      style: context.mapChrome.headingStyle(
                        fontSize: ResourceMapPanelMetrics.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      for (final action in setupActions)
                        _AtlasCommandRow(action: action),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AtlasCommandRow extends StatefulWidget {
  const _AtlasCommandRow({required this.action});

  final ResourceMapAtlasCommandAction action;

  @override
  State<_AtlasCommandRow> createState() => _AtlasCommandRowState();
}

/// Saved is a short list beside discovery, not a full planning workspace.
class ResourceMapAtlasSavedList extends StatelessWidget {
  const ResourceMapAtlasSavedList({
    super.key,
    required this.count,
    required this.onClose,
    required this.child,
    required this.maximumHeight,
  });

  final int count;
  final VoidCallback onClose;
  final Widget child;
  final double maximumHeight;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return _AtlasGlass(
      radius: _ghostLedger(context) ? 0 : 5,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maximumHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                children: <Widget>[
                  Text(
                    'Saved',
                    style: TextStyle(
                      color: chrome.ink,
                      fontSize: ResourceMapPanelMetrics.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _AtlasCompactButton(
                    key: const ValueKey<String>('resource-map-saved-close'),
                    tooltip: 'Close saved',
                    onPressed: onClose,
                    icon: Icons.close_rounded,
                  ),
                ],
              ),
            ),
            Flexible(fit: FlexFit.loose, child: child),
          ],
        ),
      ),
    );
  }
}

class ResourceMapFavoriteButton extends StatelessWidget {
  const ResourceMapFavoriteButton({
    super.key,
    required this.name,
    required this.saved,
    required this.onPressed,
  });

  final String name;
  final bool saved;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return TextFieldTapRegion(
      child: Semantics(
        toggled: saved,
        child: IconButton(
          tooltip: saved
              ? 'Remove $name from favorites'
              : 'Add $name to favorites',
          onPressed: onPressed,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: AnimatedSwitcher(
            duration: ResourceMapAtlasMotion.resolve(
              context,
              ResourceMapAtlasMotion.quick,
            ),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              saved ? Icons.star_rounded : Icons.star_outline_rounded,
              key: ValueKey<bool>(saved),
              size: 22,
              color: saved ? chrome.accent : chrome.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _AtlasCommandRowState extends State<_AtlasCommandRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final chrome = context.mapChrome;
    final ghost = _ghostLedger(context);
    final highlighted = action.selected || _hovered;
    return Semantics(
      button: true,
      selected: action.selected,
      label: action.label,
      hint: action.semanticHint,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Padding(
          padding: const EdgeInsets.only(
            bottom: ResourceMapPanelMetrics.optionGap,
          ),
          child: ResourceMapPill(
            selected: action.selected,
            child: Material(
              key: action.key,
              color: Colors.transparent,
              child: InkWell(
                onTap: action.onPressed,
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: ResourceMapAtlasCommandMenu.rowHeight,
                  ),
                  child: Row(
                    children: <Widget>[
                      const SizedBox(width: 10),
                      SizedBox.square(
                        dimension: ResourceMapAtlasCommandMenu.artworkSize,
                        child: IconTheme(
                          data: IconThemeData(
                            size: ResourceMapAtlasCommandMenu.artworkSize,
                            color: highlighted ? chrome.primary : chrome.text,
                          ),
                          child: action.icon,
                        ),
                      ),
                      SizedBox(width: ghost ? 10 : 10),
                      Expanded(
                        child: Text(
                          action.label,
                          style: TextStyle(
                            color: chrome.ink,
                            fontSize: ResourceMapAtlasCommandMenu.labelFontSize,
                            height: 1.12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(width: ghost ? 18 : 12),
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

class ResourceMapAtlasSearch extends StatelessWidget {
  const ResourceMapAtlasSearch({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    this.scopeControl,
    required this.onChanged,
    required this.onSubmitted,
    required this.onTap,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final Widget? scopeControl;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final ghost = _ghostLedger(context);
    return Row(
      children: <Widget>[
        SizedBox(width: ghost ? 4 : 3),
        ?scopeControl,
        if (scopeControl != null)
          Container(
            width: 1,
            height: ghost ? 18 : 24,
            color: chrome.softOutline.withValues(alpha: ghost ? .4 : .68),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            key: const ValueKey<String>('resource-map-atlas-search-field'),
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.search,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            onTap: onTap,
            onTapAlwaysCalled: true,
            style: TextStyle(
              color: chrome.ink,
              fontSize: ResourceMapPanelMetrics.primary,
              height: 1.2,
              fontWeight: FontWeight.w400,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                color: chrome.text,
                fontSize: ResourceMapPanelMetrics.primary,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              filled: false,
              fillColor: Colors.transparent,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 9),
            ),
          ),
        ),
        if (controller.text.isNotEmpty)
          _AtlasCompactButton(
            tooltip: 'Clear search',
            onPressed: onClear,
            icon: Icons.close_rounded,
          ),
        const SizedBox(width: 4),
        Icon(Icons.search_rounded, size: 22, color: chrome.text),
        const SizedBox(width: 11),
      ],
    );
  }
}

/// A restrained top search instrument. Results open directly beneath the
/// field in one vertical command list, never across the width of the map.
class ResourceMapDiscoveryLens extends StatelessWidget {
  const ResourceMapDiscoveryLens({
    super.key,
    required this.search,
    required this.results,
    required this.expanded,
    required this.resultLabel,
    required this.onClose,
    this.maximumWidth = 500,
    this.expandedHeight = 470,
    this.framed = true,
  });

  final Widget search;
  final Widget results;
  final bool expanded;
  final String resultLabel;
  final VoidCallback onClose;
  final double maximumWidth;
  final double expandedHeight;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final ghost = _ghostLedger(context);
    final duration = ResourceMapAtlasMotion.resolve(
      context,
      ResourceMapAtlasMotion.settle,
    );
    final searchHeight = ResourceMapPanelMetrics.searchHeight(context);
    final searchBar = SizedBox(
      height: searchHeight,
      child: Row(
        children: <Widget>[
          Expanded(child: search),
          if (expanded) ...<Widget>[
            _AtlasCompactButton(
              tooltip: 'Close search',
              onPressed: onClose,
              icon: Icons.close_rounded,
            ),
            const SizedBox(width: 3),
          ],
        ],
      ),
    );
    final divider = Divider(
      height: 0,
      thickness: 1,
      color: chrome.softOutline.withValues(alpha: .54),
    );
    final body = Column(
      key: const ValueKey<String>('resource-map-discovery-lens-content'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        searchBar,
        if (expanded) ...<Widget>[
          divider,
          Flexible(
            fit: FlexFit.loose,
            key: const ValueKey<String>('resource-map-atlas-search-palette'),
            child: results,
          ),
        ],
      ],
    );
    final content = SizedBox(
      width: maximumWidth,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: expanded ? expandedHeight : searchHeight,
        ),
        child: !framed
            ? body
            : _AtlasGlass(
                radius: ghost ? 0 : 5,
                padding: EdgeInsets.zero,
                // Keep the field in one stable element tree while results open.
                // A tight result height used to reserve empty map space and made
                // short results look like a full drawer.
                child: body,
              ),
      ),
    );
    if (duration == Duration.zero) {
      return KeyedSubtree(
        key: const ValueKey<String>('resource-map-discovery-lens'),
        child: content,
      );
    }
    return AnimatedSize(
      key: const ValueKey<String>('resource-map-discovery-lens'),
      duration: duration,
      curve: ResourceMapAtlasMotion.curve,
      alignment: Alignment.topLeft,
      child: content,
    );
  }
}

class ResourceMapAtlasPalette extends StatelessWidget {
  const ResourceMapAtlasPalette({
    super.key,
    required this.child,
    this.width = 700,
  });

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return _AtlasGlass(
      radius: 14,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: SizedBox(width: width, child: child),
    );
  }
}

class ResourceMapAtlasWorkspace extends StatelessWidget {
  const ResourceMapAtlasWorkspace({
    super.key,
    required this.title,
    required this.child,
    this.leading,
    this.onBack,
    this.onMinimize,
    this.onClose,
    this.actions = const <Widget>[],
    this.docked = false,
    this.shrinkWrap = false,
  });

  final String title;
  final Widget child;
  final Widget? leading;
  final VoidCallback? onBack;
  final VoidCallback? onMinimize;
  final VoidCallback? onClose;
  final List<Widget> actions;
  final bool docked;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final ghost = _ghostLedger(context);
    final content = Column(
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: <Widget>[
        ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: ResourceMapPanelMetrics.rowHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: <Widget>[
                if (onBack != null)
                  _AtlasCompactButton(
                    key: const ValueKey<String>('resource-map-task-back'),
                    tooltip: 'Back',
                    onPressed: onBack!,
                    icon: Icons.arrow_back_rounded,
                  )
                else if (leading != null)
                  SizedBox(
                    width: ResourceMapPanelMetrics.artwork,
                    height: ResourceMapPanelMetrics.artwork,
                    child: Center(child: leading),
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: chrome.ink,
                      fontSize: ResourceMapPanelMetrics.primary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: ghost ? .2 : -.25,
                    ),
                  ),
                ),
                ...actions,
                if (onMinimize != null) ...<Widget>[
                  const SizedBox(width: 4),
                  _AtlasCompactButton(
                    key: const ValueKey<String>(
                      'resource-map-atlas-workspace-minimize',
                    ),
                    tooltip: 'Minimize and use the map',
                    onPressed: onMinimize!,
                    icon: Icons.remove_rounded,
                  ),
                ],
                if (onClose != null) ...<Widget>[
                  const SizedBox(width: 4),
                  _AtlasCompactButton(
                    key: const ValueKey<String>(
                      'resource-map-atlas-workspace-close',
                    ),
                    tooltip: 'Close',
                    onPressed: onClose!,
                    icon: Icons.close_rounded,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (!ghost)
          Divider(height: 1, color: chrome.softOutline.withValues(alpha: .65))
        else
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 94,
              height: 1,
              color: chrome.primary.withValues(alpha: .72),
            ),
          ),
        if (shrinkWrap) Flexible(child: child) else Expanded(child: child),
      ],
    );
    return _AtlasGlass(
      radius: chrome.surfaceRadius,
      padding: EdgeInsets.zero,
      child: SafeArea(left: false, child: content),
    );
  }
}

class ResourceMapAtlasTaskChip extends StatelessWidget {
  const ResourceMapAtlasTaskChip({
    super.key,
    required this.title,
    required this.leading,
    required this.onRestore,
    required this.onClose,
  });

  final String title;
  final Widget leading;
  final VoidCallback onRestore;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return _AtlasGlass(
      radius: chrome.surfaceRadius,
      padding: const EdgeInsets.fromLTRB(5, 4, 4, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox.square(
            dimension: ResourceMapPanelMetrics.artwork,
            child: Center(child: leading),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 230),
              child: Text(
                title,
                style: TextStyle(
                  color: chrome.ink,
                  fontSize: ResourceMapPanelMetrics.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _AtlasCompactButton(
            key: const ValueKey<String>('resource-map-atlas-task-restore'),
            tooltip: 'Resume task',
            onPressed: onRestore,
            icon: Icons.open_in_full_rounded,
          ),
          _AtlasCompactButton(
            tooltip: 'Close task',
            onPressed: onClose,
            icon: Icons.close_rounded,
          ),
        ],
      ),
    );
  }
}

class ResourceMapAtlasInspector extends StatelessWidget {
  const ResourceMapAtlasInspector({
    super.key,
    required this.child,
    required this.onBack,
    required this.onClose,
    required this.expanded,
    required this.onToggleExpanded,
    this.backLabel = 'Back',
    this.callout = false,
    this.tailOnLeft = true,
  });

  final Widget child;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final String backLabel;
  final bool callout;
  final bool tailOnLeft;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final ghost = _ghostLedger(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: callout ? 36 : 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: <Widget>[
                _AtlasCompactButton(
                  key: const ValueKey<String>('resource-map-task-back'),
                  tooltip: backLabel,
                  onPressed: onBack,
                  icon: Icons.arrow_back_rounded,
                ),
                const SizedBox(width: 5),
                const Spacer(),
                _AtlasCompactButton(
                  key: const ValueKey<String>(
                    'resource-map-desktop-details-expand',
                  ),
                  tooltip: expanded ? 'Show less' : 'Show more',
                  onPressed: onToggleExpanded,
                  icon: expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                ),
                const SizedBox(width: 2),
                _AtlasCompactButton(
                  key: const ValueKey<String>('resource-map-task-close'),
                  tooltip: 'Close details',
                  onPressed: onClose,
                  icon: Icons.close_rounded,
                ),
              ],
            ),
          ),
        ),
        if (!ghost)
          Divider(height: 1, color: chrome.softOutline.withValues(alpha: .62))
        else
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 78,
              height: 1,
              color: chrome.primary.withValues(alpha: .72),
            ),
          ),
        Flexible(fit: FlexFit.loose, child: child),
      ],
    );
    if (!callout) {
      return _AtlasGlass(
        radius: ghost ? 0 : 5,
        padding: EdgeInsets.zero,
        child: content,
      );
    }
    return Material(
      color: chrome.fillAlpha(chrome.chromeBase, .975),
      elevation: 20,
      shadowColor: const Color(0x99000000),
      shape: _AtlasCalloutBorder(
        tailOnLeft: tailOnLeft,
        side: BorderSide(color: chrome.softOutline.withValues(alpha: .9)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(
          left: tailOnLeft ? 13 : 0,
          right: tailOnLeft ? 0 : 13,
        ),
        child: content,
      ),
    );
  }
}

class _AtlasCalloutBorder extends ShapeBorder {
  const _AtlasCalloutBorder({required this.tailOnLeft, required this.side});

  final bool tailOnLeft;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.only(
    left: tailOnLeft ? side.width : 0,
    right: tailOnLeft ? 0 : side.width,
  );

  Path _path(Rect rect) {
    const tail = 13.0;
    const radius = 18.0;
    final body = tailOnLeft
        ? Rect.fromLTRB(rect.left + tail, rect.top, rect.right, rect.bottom)
        : Rect.fromLTRB(rect.left, rect.top, rect.right - tail, rect.bottom);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(body, const Radius.circular(radius)));
    final y = rect.top + 74;
    if (tailOnLeft) {
      path
        ..moveTo(body.left, y - 12)
        ..lineTo(rect.left, y)
        ..lineTo(body.left, y + 12)
        ..close();
    } else {
      path
        ..moveTo(body.right, y - 12)
        ..lineTo(rect.right, y)
        ..lineTo(body.right, y + 12)
        ..close();
    }
    return path;
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(
      _path(rect.deflate(side.width / 2)),
      side.toPaint()..style = PaintingStyle.stroke,
    );
  }

  @override
  ShapeBorder scale(double t) =>
      _AtlasCalloutBorder(tailOnLeft: tailOnLeft, side: side.scale(t));
}

class _AtlasCompactButton extends StatelessWidget {
  const _AtlasCompactButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: ResourceMapPanelMetrics.controlTarget,
            child: Icon(
              icon,
              size: ResourceMapPanelMetrics.controlGlyph,
              color: chrome.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _AtlasGlass extends StatelessWidget {
  const _AtlasGlass({
    required this.child,
    required this.radius,
    required this.padding,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final ghost = _ghostLedger(context);
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: ghost ? chrome.subtleSurfaceShadows : chrome.surfaceShadows,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 18 * math.min(1, chrome.materialOpacity / .6),
            sigmaY: 18 * math.min(1, chrome.materialOpacity / .6),
          ),
          child: Material(
            color: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: chrome.readingSurfaceGradient,
                borderRadius: borderRadius,
              ),
              child: CustomPaint(
                foregroundPainter: _MapGlassLight(
                  radius: radius,
                  light: chrome.primary,
                  opacity: chrome.materialOpacity,
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    textTheme: Theme.of(
                      context,
                    ).textTheme.merge(_glassTextTheme),
                    iconTheme: Theme.of(
                      context,
                    ).iconTheme.copyWith(shadows: _glassTextShadows),
                  ),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(shadows: _glassTextShadows),
                    child: IconTheme.merge(
                      data: const IconThemeData(shadows: _glassTextShadows),
                      child: Padding(padding: padding, child: child),
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

/// One illuminated rim with a quiet six-pixel reflection. It never paints
/// across the item artwork or text, and it introduces no animation work.
class _MapGlassLight extends CustomPainter {
  const _MapGlassLight({
    required this.radius,
    required this.light,
    this.opacity = 1,
  });
  final double radius;
  final Color light;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 16 || size.height < 16) return;
    final rect = (Offset.zero & size).deflate(.6);
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    // A dark lower edge and a second inset reflection give the pane thickness
    // without laying texture over its reading area.
    canvas.drawRRect(
      shape.deflate(1.2).shift(const Offset(0, .6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0x00FFFFFF),
            const Color(0x00000000),
            const Color(0xA0000813).withValues(alpha: .63 * opacity),
          ],
          stops: [0, .7, 1],
        ).createShader(rect),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(
              light,
              Colors.white,
              .45,
            )!.withValues(alpha: .48 * opacity),
            light.withValues(alpha: .12 * opacity),
            light.withValues(alpha: .18 * opacity),
          ],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRRect(shape),
        Path()..addRRect(shape.deflate(6)),
      ),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            light.withValues(alpha: .06 * opacity),
            light.withValues(alpha: 0),
          ],
          stops: const [0, .25],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant _MapGlassLight oldDelegate) =>
      radius != oldDelegate.radius ||
      light != oldDelegate.light ||
      opacity != oldDelegate.opacity;
}
