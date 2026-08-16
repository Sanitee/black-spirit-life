import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../app_identity.dart';
import '../../visual/foundations/theme_spec.dart';
import '../../visual/sakura_night_garden/sakura_botanical_assets.dart';
import '../../visual/sakura_night_garden/sakura_material_painters.dart';
import '../../visual/sakura_night_garden/sakura_spec.dart';
import '../../visual/standard/standard_spec.dart';
import 'window_host_service.dart';

@immutable
class AppTitleTab {
  const AppTitleTab({
    required this.tabKey,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.icon,
    this.artworkAssetPath,
  }) : assert(
         (icon == null) != (artworkAssetPath == null),
         'Provide exactly one tab icon or artwork asset.',
       );

  final Key tabKey;
  final IconData? icon;
  final String? artworkAssetPath;
  final String label;
  final bool selected;
  final VoidCallback onPressed;
}

/// Browser-style application destinations hosted in the app-owned title bar.
///
/// The active destination expands to its icon and name while inactive
/// destinations collapse to full-size icon controls. If the title bar becomes
/// too narrow, every destination uses its icon. Tooltips, semantics, and hit
/// targets always retain the complete destination name.
class AppTitleTabStrip extends StatelessWidget {
  const AppTitleTabStrip({required this.tabs, super.key});

  final List<AppTitleTab> tabs;

  static const Key semanticsKey = ValueKey<String>(
    'app-title-tab-strip-semantics',
  );
  static Key surfaceKey(String label) =>
      ValueKey<String>('app-title-tab-surface-$label');
  static Key artworkKey(String label) =>
      ValueKey<String>('app-title-tab-artwork-$label');
  static const double artworkSize = 34;

  @override
  Widget build(BuildContext context) {
    final spec = ThemeSpecScope.maybeOf(context) ?? StandardSpec.theme;
    final textScaler = MediaQuery.textScalerOf(context);
    final labelStyle = _tabLabelStyle(spec, selected: true);
    final animationDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : spec.motion.interactionDuration;
    const compactWidth = 52.0;
    const tabGap = 4.0;
    final expandedWidths = <double>[
      for (final tab in tabs)
        _expandedWidth(
          tab.label,
          labelStyle,
          textScaler,
          Directionality.of(context),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final gaps = tabs.length <= 1 ? 0.0 : (tabs.length - 1) * tabGap;
        final activeOnlyWidth =
            List<double>.generate(
              tabs.length,
              (index) =>
                  tabs[index].selected ? expandedWidths[index] : compactWidth,
            ).fold<double>(0, (total, width) => total + width) +
            gaps;
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : activeOnlyWidth;
        final presentation = availableWidth >= activeOnlyWidth
            ? _TitleTabPresentation.activeLabel
            : _TitleTabPresentation.iconsOnly;
        final intendedWidth = presentation == _TitleTabPresentation.activeLabel
            ? activeOnlyWidth
            : tabs.length * compactWidth + gaps;
        final stripWidth = constraints.hasBoundedWidth
            ? intendedWidth.clamp(0, availableWidth).toDouble()
            : intendedWidth;

        return Semantics(
          key: semanticsKey,
          container: true,
          explicitChildNodes: true,
          label: 'Application tabs',
          child: Material(
            color: Colors.transparent,
            child: AnimatedContainer(
              duration: animationDuration,
              curve: Curves.easeOutCubic,
              width: stripWidth,
              height: 40,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.bottomLeft,
                  minWidth: 0,
                  maxWidth: double.infinity,
                  minHeight: 40,
                  maxHeight: 40,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      for (
                        var index = 0;
                        index < tabs.length;
                        index++
                      ) ...<Widget>[
                        if (index > 0) const SizedBox(width: tabGap),
                        _AppTitleTabButton(
                          tab: tabs[index],
                          ordinal: index.toDouble(),
                          showLabel:
                              presentation ==
                                  _TitleTabPresentation.activeLabel &&
                              tabs[index].selected,
                          width:
                              presentation ==
                                      _TitleTabPresentation.activeLabel &&
                                  tabs[index].selected
                              ? expandedWidths[index]
                              : compactWidth,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static double _expandedWidth(
    String label,
    TextStyle style,
    TextScaler textScaler,
    TextDirection textDirection,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      maxLines: 1,
      textScaler: textScaler,
      textDirection: textDirection,
    )..layout();
    return (painter.width + 72).clamp(148, 400);
  }
}

enum _TitleTabPresentation { activeLabel, iconsOnly }

class _AppTitleTabButton extends StatefulWidget {
  const _AppTitleTabButton({
    required this.tab,
    required this.ordinal,
    required this.showLabel,
    required this.width,
  });

  final AppTitleTab tab;
  final double ordinal;
  final bool showLabel;
  final double width;

  @override
  State<_AppTitleTabButton> createState() => _AppTitleTabButtonState();
}

class _AppTitleTabButtonState extends State<_AppTitleTabButton> {
  late final FocusNode _focusNode;
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: '${widget.tab.label} application tab');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = ThemeSpecScope.maybeOf(context) ?? StandardSpec.theme;
    final selected = widget.tab.selected;
    final decoration = _tabDecoration(
      context,
      spec,
      selected: selected,
      hovered: _hovered,
      focused: _focused,
      pressed: _pressed,
    );
    final foreground = _tabForeground(
      spec,
      selected: selected,
      hovered: _hovered,
    );
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : spec.motion.interactionDuration;
    return Tooltip(
      message: widget.tab.label,
      excludeFromSemantics: true,
      child: Semantics(
        key: widget.tab.tabKey,
        button: true,
        selected: selected,
        label: widget.tab.label,
        sortKey: OrdinalSortKey(widget.ordinal),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: Listener(
            onPointerDown: (_) => setState(() => _pressed = true),
            onPointerUp: (_) => setState(() => _pressed = false),
            onPointerCancel: (_) => setState(() => _pressed = false),
            child: AnimatedContainer(
              key: AppTitleTabStrip.surfaceKey(widget.tab.label),
              duration: duration,
              curve: Curves.easeOutCubic,
              width: widget.width,
              height: 40,
              clipBehavior: Clip.antiAlias,
              decoration: decoration,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  InkWell(
                    onTap: widget.tab.onPressed,
                    focusNode: _focusNode,
                    onFocusChange: (focused) =>
                        setState(() => _focused = focused),
                    borderRadius: _tabRadius(spec),
                    focusColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    splashColor: foreground.withAlpha(28),
                    highlightColor: foreground.withAlpha(20),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        AnimatedAlign(
                          duration: duration,
                          curve: Curves.easeOutCubic,
                          alignment: widget.showLabel
                              ? Alignment.centerLeft
                              : Alignment.center,
                          child: AnimatedPadding(
                            duration: duration,
                            curve: Curves.easeOutCubic,
                            padding: EdgeInsets.only(
                              left: widget.showLabel ? 7 : 0,
                            ),
                            child: _TitleTabArtwork(
                              tab: widget.tab,
                              foreground: foreground,
                            ),
                          ),
                        ),
                        if (widget.showLabel)
                          Positioned(
                            left: 49,
                            top: 0,
                            right: 12,
                            bottom: 0,
                            child: ClipRect(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TweenAnimationBuilder<double>(
                                  key: ValueKey<String>(
                                    'app-title-tab-label-${widget.tab.label}',
                                  ),
                                  duration: duration,
                                  curve: Curves.easeOutCubic,
                                  tween: Tween<double>(begin: 0, end: 1),
                                  builder: (context, value, child) {
                                    return Opacity(
                                      opacity: value,
                                      child: Transform.translate(
                                        offset: Offset(4 * (1 - value), 0),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: Text(
                                    widget.tab.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    softWrap: false,
                                    style: _tabLabelStyle(
                                      spec,
                                      selected: selected,
                                    ).copyWith(color: foreground),
                                  ),
                                ),
                              ),
                            ),
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
    );
  }
}

class _TitleTabArtwork extends StatelessWidget {
  const _TitleTabArtwork({required this.tab, required this.foreground});

  final AppTitleTab tab;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final assetPath = tab.artworkAssetPath;
    if (assetPath == null) {
      return Icon(tab.icon, size: 23, color: foreground);
    }
    final rasterScale = MediaQuery.devicePixelRatioOf(context).clamp(3.0, 5.0);
    final rasterSize = (AppTitleTabStrip.artworkSize * rasterScale).ceil();
    return ClipRRect(
      key: AppTitleTabStrip.artworkKey(tab.label),
      borderRadius: BorderRadius.circular(8),
      child: Transform.scale(
        // Both retained artworks include generous ornamental framing. A small
        // crop keeps the actual cauldron/map symbol legible at title-bar size
        // and prevents the artwork frame from reading as a second tab border.
        scale: 1.18,
        child: Image.asset(
          assetPath,
          width: AppTitleTabStrip.artworkSize,
          height: AppTitleTabStrip.artworkSize,
          cacheWidth: rasterSize,
          cacheHeight: rasterSize,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          isAntiAlias: true,
          gaplessPlayback: true,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

TextStyle _tabLabelStyle(ThemeSpec spec, {required bool selected}) => TextStyle(
  color: spec.palette.text,
  fontFamily: spec.family == RetainedVisualFamily.sakuraNightGarden
      ? 'Georgia'
      : 'Segoe UI',
  fontSize: 13,
  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
  letterSpacing: spec.family == RetainedVisualFamily.sakuraNightGarden
      ? .1
      : .2,
);

BorderRadius _tabRadius(ThemeSpec spec) {
  final radius = switch (spec.family) {
    RetainedVisualFamily.illuminatedLedger => 3.0,
    RetainedVisualFamily.sakuraNightGarden => 7.0,
    RetainedVisualFamily.standard => 8.0,
  };
  return BorderRadius.only(
    topLeft: Radius.circular(radius),
    topRight: Radius.circular(radius),
    bottomLeft: const Radius.circular(2),
    bottomRight: const Radius.circular(2),
  );
}

Color _tabForeground(
  ThemeSpec spec, {
  required bool selected,
  required bool hovered,
}) {
  if (spec.family == RetainedVisualFamily.illuminatedLedger) {
    return selected
        ? const Color(0xFFFFEDBA)
        : hovered
        ? const Color(0xFFF5E2AE)
        : const Color(0xFFD8C696);
  }
  if (spec.family == RetainedVisualFamily.sakuraNightGarden) {
    return selected
        ? SakuraNightGardenSpec.warmIvory
        : hovered
        ? SakuraNightGardenSpec.paleBlossom
        : SakuraNightGardenSpec.mutedText;
  }
  return selected
      ? const Color(0xFFF1F0E9)
      : hovered
      ? const Color(0xFFDDE4E0)
      : const Color(0xFFB8C3BE);
}

@immutable
class _TitleTabPalette {
  const _TitleTabPalette({
    required this.accent,
    required this.surface,
    required this.selectedSurface,
    required this.hoverSurface,
    required this.pressedSurface,
    required this.divider,
  });

  final Color accent;
  final Color surface;
  final Color selectedSurface;
  final Color hoverSurface;
  final Color pressedSurface;
  final Color divider;
}

_TitleTabPalette _tabPalette(BuildContext context, ThemeSpec spec) {
  switch (spec.family) {
    case RetainedVisualFamily.standard:
      final settings = context.standardVisual;
      final accent = StandardSpec.accentBrush(
        settings.accentHue,
        alpha: 1,
        neon: settings.neon,
      );
      return _TitleTabPalette(
        accent: accent,
        surface: const Color(0xFF111C1A),
        selectedSurface: Color.alphaBlend(
          accent.withAlpha(32),
          const Color(0xFF1B2723),
        ),
        hoverSurface: Color.alphaBlend(
          accent.withAlpha(18),
          const Color(0xFF17221F),
        ),
        pressedSurface: Color.alphaBlend(
          accent.withAlpha(24),
          const Color(0xFF0D1715),
        ),
        divider: const Color(0xFF384640),
      );
    case RetainedVisualFamily.illuminatedLedger:
      return const _TitleTabPalette(
        accent: Color(0xFFD6B45A),
        surface: Color(0xFF0D2132),
        selectedSurface: Color(0xFF18364D),
        hoverSurface: Color(0xFF132B40),
        pressedSurface: Color(0xFF0A1B2B),
        divider: Color(0xFF40566A),
      );
    case RetainedVisualFamily.sakuraNightGarden:
      return const _TitleTabPalette(
        accent: SakuraNightGardenSpec.dustySakura,
        surface: SakuraNightGardenSpec.charcoalPlum,
        selectedSurface: SakuraNightGardenSpec.darkCherrywood,
        hoverSurface: SakuraNightGardenSpec.rosewood,
        pressedSurface: SakuraNightGardenSpec.nightCedar,
        divider: SakuraNightGardenSpec.copperHighlight,
      );
  }
}

BoxDecoration _tabDecoration(
  BuildContext context,
  ThemeSpec spec, {
  required bool selected,
  required bool hovered,
  required bool focused,
  required bool pressed,
}) {
  final palette = _tabPalette(context, spec);
  final color = pressed
      ? palette.pressedSurface
      : selected
      ? palette.selectedSurface
      : hovered
      ? palette.hoverSurface
      : palette.surface;
  final borderColor = focused
      ? palette.accent.withAlpha(245)
      : selected
      ? Color.alphaBlend(palette.accent.withAlpha(86), palette.divider)
      : hovered
      ? Color.alphaBlend(palette.accent.withAlpha(54), palette.divider)
      : palette.divider;
  return BoxDecoration(
    color: color,
    borderRadius: _tabRadius(spec),
    border: Border.all(color: borderColor, width: focused ? 1.4 : 1),
  );
}

class AppTitleBar extends StatefulWidget {
  const AppTitleBar({
    this.windowHost = const WindowHostService(),
    this.beforeClose,
    this.onCloseError,
    this.workspaceNavigation,
    this.trailing,
    super.key,
  });

  final WindowHostService windowHost;
  final Future<void> Function()? beforeClose;
  final ValueChanged<Object>? onCloseError;
  final Widget? workspaceNavigation;
  final Widget? trailing;

  static const Key materialKey = ValueKey<String>('app-title-bar-material');
  static const Key iconFrameKey = ValueKey<String>('app-title-bar-icon-frame');
  static const Key dragRegionKey = ValueKey<String>(
    'app-title-bar-drag-region',
  );
  static const Key workspaceNavigationHostKey = ValueKey<String>(
    'app-title-bar-workspace-navigation-host',
  );
  static const Key trailingHostKey = ValueKey<String>(
    'app-title-bar-trailing-host',
  );
  static const Key sakuraSprigKey = ValueKey<String>(
    'app-title-bar-sakura-sprig',
  );
  static Key captionGlyphKey(String glyph) =>
      ValueKey<String>('app-title-bar-caption-glyph-$glyph');

  @override
  State<AppTitleBar> createState() => _AppTitleBarState();
}

class _AppTitleBarState extends State<AppTitleBar> {
  bool _closing = false;
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshMaximized());
  }

  Future<void> _refreshMaximized() async {
    final value = await widget.windowHost.isMaximized();
    if (mounted && value != _maximized) setState(() => _maximized = value);
  }

  Future<void> _toggleMaximize() async {
    final value = await widget.windowHost.toggleMaximize();
    if (mounted && value != _maximized) setState(() => _maximized = value);
  }

  Future<void> _close() async {
    if (_closing) return;
    setState(() => _closing = true);
    try {
      if (widget.beforeClose case final beforeClose?) {
        await beforeClose().timeout(
          widget.windowHost.closeFlushTimeout,
          onTimeout: () => throw TimeoutException(
            'Close was canceled because saving did not finish within '
            '${widget.windowHost.closeFlushTimeout.inSeconds} seconds.',
          ),
        );
      }
      await widget.windowHost.close();
    } on Object catch (error) {
      widget.onCloseError?.call(error);
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = ThemeSpecScope.maybeOf(context);
    final family = spec?.family ?? RetainedVisualFamily.standard;
    final decoration = switch (family) {
      RetainedVisualFamily.illuminatedLedger => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            Color(0xFF0A2744),
            Color(0xFF123D69),
            Color(0xFF071D35),
          ],
          stops: <double>[0, .56, 1],
        ),
        border: Border(
          bottom: BorderSide(color: Color(0xFFC9A14A), width: 1.5),
        ),
      ),
      RetainedVisualFamily.sakuraNightGarden => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            Color(0xFF171415),
            SakuraNightGardenSpec.nightCedar,
            SakuraNightGardenSpec.canvasDeep,
          ],
          stops: <double>[0, .58, 1],
        ),
        border: Border(
          bottom: BorderSide(color: SakuraNightGardenSpec.rosewood, width: 1),
        ),
        image: DecorationImage(
          image: AssetImage(SakuraNightGardenSpec.blackenedCedarAssetPath),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          opacity: .42,
        ),
      ),
      RetainedVisualFamily.standard => BoxDecoration(
        gradient: StandardSpec.titleStripGradient(
          context.standardVisual.backgroundId,
        ),
      ),
    };
    final foreground = switch (family) {
      RetainedVisualFamily.illuminatedLedger => const Color(0xFFEAD8A4),
      RetainedVisualFamily.sakuraNightGarden => SakuraNightGardenSpec.warmIvory,
      RetainedVisualFamily.standard => const Color(0xFFFFF0D0),
    };
    final iconBorder = switch (family) {
      RetainedVisualFamily.sakuraNightGarden =>
        SakuraNightGardenSpec.copperHighlight.withAlpha(146),
      _ => const Color(0xFF375F4F),
    };
    return SizedBox(
      height: 40,
      child: DecoratedBox(
        key: AppTitleBar.materialKey,
        decoration: decoration,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (family == RetainedVisualFamily.sakuraNightGarden)
              const Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: CustomPaint(
                      painter: SakuraCedarGrainPainter(
                        density: .45,
                        highlight: Color(0x127A5A55),
                        shadow: Color(0x20000000),
                      ),
                    ),
                  ),
                ),
              ),
            Row(
              children: <Widget>[
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      GestureDetector(
                        key: AppTitleBar.dragRegionKey,
                        behavior: HitTestBehavior.opaque,
                        onDoubleTap: _toggleMaximize,
                        onPanStart: (_) =>
                            unawaited(widget.windowHost.beginDrag()),
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            if (family ==
                                RetainedVisualFamily.sakuraNightGarden)
                              const Positioned(
                                top: 4,
                                right: 10,
                                child: SakuraTitleSprigAsset(
                                  key: AppTitleBar.sakuraSprigKey,
                                ),
                              ),
                            Row(
                              children: <Widget>[
                                const SizedBox(width: 12),
                                if (widget.workspaceNavigation == null) ...[
                                  Container(
                                    key: AppTitleBar.iconFrameKey,
                                    width: 24,
                                    height: 24,
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(color: iconBorder),
                                    ),
                                    child: const Image(
                                      image: AssetImage(
                                        AppIdentity.appIconAssetPath,
                                      ),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    AppIdentity.displayName,
                                    style: TextStyle(
                                      color: foreground,
                                      fontFamily:
                                          family ==
                                              RetainedVisualFamily
                                                  .sakuraNightGarden
                                          ? 'Georgia'
                                          : 'Segoe UI',
                                      fontSize:
                                          family ==
                                              RetainedVisualFamily
                                                  .sakuraNightGarden
                                          ? 15
                                          : 14,
                                      fontWeight:
                                          family ==
                                              RetainedVisualFamily
                                                  .sakuraNightGarden
                                          ? FontWeight.w600
                                          : FontWeight.w700,
                                      letterSpacing:
                                          family ==
                                              RetainedVisualFamily
                                                  .sakuraNightGarden
                                          ? .1
                                          : 0,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (widget.workspaceNavigation case final navigation?)
                        Align(
                          key: AppTitleBar.workspaceNavigationHostKey,
                          alignment: Alignment.bottomLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12, right: 8),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 760),
                              child: navigation,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.trailing case final trailing?)
                  KeyedSubtree(
                    key: AppTitleBar.trailingHostKey,
                    child: trailing,
                  ),
                _CaptionButton(
                  label: 'Minimize',
                  glyph: 'minimize',
                  onPressed: widget.windowHost.minimize,
                ),
                _CaptionButton(
                  label: 'Maximize or restore',
                  glyph: _maximized ? 'restore' : 'maximize',
                  onPressed: _toggleMaximize,
                ),
                _CaptionButton(
                  label: 'Close',
                  glyph: 'close',
                  destructive: true,
                  onPressed: _closing ? null : _close,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.label,
    required this.glyph,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final String glyph;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final spec = ThemeSpecScope.maybeOf(context);
    final family = spec?.family ?? RetainedVisualFamily.standard;
    final standard = family == RetainedVisualFamily.standard
        ? context.standardVisual
        : null;
    final enabled = widget.onPressed != null;
    final BoxDecoration decoration;
    if (family == RetainedVisualFamily.illuminatedLedger) {
      decoration = BoxDecoration(
        color: _hovered
            ? widget.destructive
                  ? spec!.palette.danger
                  : spec!.palette.primaryBright.withAlpha(_pressed ? 220 : 154)
            : Colors.transparent,
      );
    } else if (family == RetainedVisualFamily.sakuraNightGarden) {
      decoration = BoxDecoration(
        color: !_hovered && !_pressed
            ? Colors.transparent
            : widget.destructive
            ? SakuraNightGardenSpec.emberBerry.withAlpha(_pressed ? 236 : 188)
            : (_pressed
                  ? SakuraNightGardenSpec.rosewood.withAlpha(218)
                  : SakuraNightGardenSpec.darkCherrywood.withAlpha(194)),
        border: _hovered && !widget.destructive
            ? const Border(
                bottom: BorderSide(
                  color: SakuraNightGardenSpec.dustySakura,
                  width: 1,
                ),
              )
            : null,
      );
    } else if (widget.destructive) {
      decoration = BoxDecoration(
        color: _pressed
            ? const Color(0xCC7F3038)
            : _hovered
            ? const Color(0xA65C272D)
            : Colors.transparent,
      );
    } else {
      decoration = BoxDecoration(
        gradient: _pressed
            ? StandardSpec.accentGlass(
                standard!.accentHue,
                topAlpha: 104,
                bottomAlpha: 36,
                neon: standard.neon,
              )
            : _hovered
            ? StandardSpec.accentGlass(
                standard!.accentHue,
                topAlpha: 72,
                bottomAlpha: 24,
                neon: standard.neon,
              )
            : null,
        color: _hovered || _pressed ? null : Colors.transparent,
      );
    }
    final foreground = switch (family) {
      RetainedVisualFamily.sakuraNightGarden =>
        widget.destructive && _hovered
            ? const Color(0xFFFFECE8)
            : SakuraNightGardenSpec.warmIvory,
      _ =>
        widget.destructive && _hovered
            ? const Color(0xFFFFE5DF)
            : const Color(0xFFFFF8EA),
    };
    return Tooltip(
      message: widget.label,
      child: Semantics(
        button: true,
        label: widget.label,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: Listener(
            onPointerDown: enabled
                ? (_) => setState(() => _pressed = true)
                : null,
            onPointerUp: enabled
                ? (_) => setState(() => _pressed = false)
                : null,
            onPointerCancel: enabled
                ? (_) => setState(() => _pressed = false)
                : null,
            child: AnimatedContainer(
              duration:
                  spec?.motion.interactionDuration ??
                  const Duration(milliseconds: 90),
              decoration: decoration,
              child: IconButton(
                style: ButtonStyle(
                  fixedSize: const WidgetStatePropertyAll(Size(52, 40)),
                  minimumSize: const WidgetStatePropertyAll(Size.zero),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
                  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  backgroundColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  foregroundColor: WidgetStatePropertyAll(
                    enabled ? foreground : foreground.withAlpha(104),
                  ),
                ),
                onPressed: widget.onPressed,
                icon: _CaptionGlyph(
                  widget.glyph,
                  repaintKey: AppTitleBar.captionGlyphKey(widget.glyph),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pixel-aligned caption artwork matching the retained Windows reference.
///
/// Caption controls deliberately keep their 52x40 hit targets while the
/// visible artwork uses the reference's measured 17x2 minimize rule,
/// 17x17 maximize frame, and 16x16 close silhouette.
class _CaptionGlyph extends StatelessWidget {
  const _CaptionGlyph(this.glyph, {required this.repaintKey});

  final String glyph;
  final Key repaintKey;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: repaintKey,
    child: SizedBox.square(
      dimension: 18,
      child: CustomPaint(
        painter: _CaptionGlyphPainter(
          glyph: glyph,
          color: IconTheme.of(context).color ?? Colors.white,
        ),
      ),
    ),
  );
}

class _CaptionGlyphPainter extends CustomPainter {
  const _CaptionGlyphPainter({required this.glyph, required this.color});

  final String glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false
      ..style = PaintingStyle.fill;
    switch (glyph) {
      case 'minimize':
        canvas.drawRect(const Rect.fromLTWH(1, 8, 17, 2), paint);
        break;
      case 'maximize':
        _drawFrame(canvas, const Rect.fromLTWH(1, 1, 17, 17), paint);
        break;
      case 'restore':
        _drawFrame(canvas, const Rect.fromLTWH(4, 1, 13, 13), paint);
        _drawFrame(canvas, const Rect.fromLTWH(1, 4, 13, 13), paint);
        break;
      case 'close':
        paint.isAntiAlias = true;
        canvas.drawPath(
          Path()
            ..moveTo(1, 2.5)
            ..lineTo(2.5, 1)
            ..lineTo(17, 15.5)
            ..lineTo(15.5, 17)
            ..close()
            ..moveTo(15.5, 1)
            ..lineTo(17, 2.5)
            ..lineTo(2.5, 17)
            ..lineTo(1, 15.5)
            ..close(),
          paint,
        );
        break;
    }
  }

  void _drawFrame(Canvas canvas, Rect rect, Paint paint) {
    canvas
      ..drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, 1), paint)
      ..drawRect(
        Rect.fromLTWH(rect.left, rect.bottom - 1, rect.width, 1),
        paint,
      )
      ..drawRect(Rect.fromLTWH(rect.left, rect.top, 1, rect.height), paint)
      ..drawRect(
        Rect.fromLTWH(rect.right - 1, rect.top, 1, rect.height),
        paint,
      );
  }

  @override
  bool shouldRepaint(_CaptionGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}
