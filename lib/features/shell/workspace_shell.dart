import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/craft_mode.dart';
import '../../visual/components/app_brand_lockup.dart';
import '../../visual/components/app_button.dart';
import '../../visual/components/app_vector_glyph.dart';
import '../../visual/components/retained_asset_image.dart';
import '../../visual/foundations/theme_spec.dart';
import '../../visual/illuminated_ledger/ledger_backdrop.dart';
import '../../visual/illuminated_ledger/ledger_spec.dart';
import '../../visual/sakura_night_garden/sakura_botanical_assets.dart';
import '../../visual/sakura_night_garden/sakura_material_painters.dart';
import '../../visual/sakura_night_garden/sakura_spec.dart';
import 'shell_models.dart';

/// Balanced Standard navigation label size within the retained 52 px rows.
const double standardNavigationLabelFontSize = 16;

/// Persistent, presentation-only workspace chrome.
///
/// The owning feature supplies the selected mode and destination, handles all
/// mutations through callbacks, and provides the complete destination body.
/// The visual background is intentionally owned by the parent layer.
class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({
    required this.mode,
    required this.destination,
    required this.onModeChanged,
    required this.onDestinationChanged,
    required this.child,
    this.showAdvancedDestinations = false,
    this.transition = ShellContentTransition.slide,
    this.transitionSpeed = ShellContentTransitionSpeed.normal,
    this.reduceMotion = false,
    super.key,
  });

  final CraftMode mode;
  final ShellDestination destination;
  final ValueChanged<CraftMode> onModeChanged;
  final ValueChanged<ShellDestination> onDestinationChanged;
  final Widget child;
  final bool showAdvancedDestinations;
  final ShellContentTransition transition;
  final ShellContentTransitionSpeed transitionSpeed;

  /// Explicit application preference. Platform animation suppression is also
  /// honored when it is available through [MediaQuery].
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    assert(
      destination.isAvailableFor(mode),
      '${destination.label} is not available in ${mode.label}.',
    );
    final spec = context.visualTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _WorkspaceMetrics.resolve(
          constraints: constraints,
          geometry: spec.geometry,
        );
        return Padding(
          key: WorkspaceShellKeys.root,
          padding: metrics.workspacePadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                key: metrics.compact
                    ? WorkspaceShellKeys.compactLayout
                    : WorkspaceShellKeys.referenceLayout,
                width: metrics.sidebarWidth,
                child: RepaintBoundary(
                  key: WorkspaceShellKeys.sidebar,
                  child: _WorkspaceSidebar(
                    mode: mode,
                    destination: destination,
                    compact: metrics.compact,
                    showAdvancedDestinations: showAdvancedDestinations,
                    onModeChanged: onModeChanged,
                    onDestinationChanged: onDestinationChanged,
                  ),
                ),
              ),
              SizedBox(width: metrics.contentGap),
              Expanded(
                child: RepaintBoundary(
                  key: WorkspaceShellKeys.contentHost,
                  child: _ContentTransitionHost(
                    destination: destination,
                    transition: transition,
                    transitionSpeed: transitionSpeed,
                    reduceMotion: reduceMotion,
                    child: child,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WorkspaceSidebar extends StatelessWidget {
  const _WorkspaceSidebar({
    required this.mode,
    required this.destination,
    required this.compact,
    required this.showAdvancedDestinations,
    required this.onModeChanged,
    required this.onDestinationChanged,
  });

  final CraftMode mode;
  final ShellDestination destination;
  final bool compact;
  final bool showAdvancedDestinations;
  final ValueChanged<CraftMode> onModeChanged;
  final ValueChanged<ShellDestination> onDestinationChanged;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.family == RetainedVisualFamily.illuminatedLedger;
    final sakura = spec.family == RetainedVisualFamily.sakuraNightGarden;
    final denseLayout = spec.usesDenseSplitLayout;
    final horizontalInset = compact ? 10.0 : 12.0;
    // Avalonia's 48 px rows plus 11 px StackPanel spacing advance by 59 px.
    // Flutter retains the measured 50 px row silhouette, so a 9 px gap keeps
    // every successive baseline and divider on that same vertical cadence.
    final navigationGap = denseLayout ? (compact ? 7.0 : 9.0) : 11.0;
    final navigationFontSize = denseLayout
        ? 16.0
        : (spec.typography.button.fontSize ?? 14.0);
    final textScale =
        MediaQuery.textScalerOf(context).scale(navigationFontSize) /
        navigationFontSize;
    final navigationHeight = denseLayout ? (compact ? 43.0 : 50.0) : 52.0;
    final brandNavigationGap = denseLayout
        ? (compact ? 40.0 : 48.0) / textScale.clamp(1.0, 1.5)
        : (compact ? 58.0 : 80.0) / textScale.clamp(1.0, 3.0);
    final visibleDestinations = <ShellDestination>[
      for (final entry in ShellDestination.values)
        if (entry.isVisibleFor(mode, showAdvanced: showAdvancedDestinations))
          entry,
    ];
    final navigationExtent =
        visibleDestinations.length * navigationHeight +
        math.max(0, visibleDestinations.length - 1) * navigationGap;
    // The authored sidebar botanicals cap at 290 px, with their existing
    // seven-pixel top and two-pixel bottom breathing room.
    final preferredOrnamentExtent = ledger || sakura ? 299.0 : 0.0;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Black Spirit Life workspace navigation',
      child: DecoratedBox(
        key: WorkspaceShellKeys.sidebarMaterial,
        decoration: switch (spec.family) {
          RetainedVisualFamily.illuminatedLedger => const BoxDecoration(
            // Match Avalonia's translucent inside-cover vellum. The page
            // texture and fold remain visible below this warm horizontal
            // wash; a dark canvas overlay makes the rail look grey and
            // visually disconnects it from the open ledger.
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[Color(0xB3FBE8BF), Color(0x8CF6E1B1)],
            ),
            border: Border(
              right: BorderSide(color: Color(0x9A9A702C), width: 1),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Color(0x28352516),
                blurRadius: 14,
                offset: Offset(5, 0),
              ),
            ],
          ),
          RetainedVisualFamily.sakuraNightGarden => const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[
                Color(0x5E1C1718),
                Color(0x4A151213),
                Color(0x5A0D0B0F),
              ],
              stops: <double>[0, .68, 1],
            ),
            border: Border(
              right: BorderSide(
                color: SakuraNightGardenSpec.rosewood,
                width: 1,
              ),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Color(0x52000000),
                blurRadius: 10,
                offset: Offset(4, 0),
              ),
            ],
            image: DecorationImage(
              image: AssetImage(SakuraNightGardenSpec.blackenedCedarAssetPath),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              opacity: .48,
            ),
          ),
          RetainedVisualFamily.standard => const BoxDecoration(
            color: Colors.transparent,
            border: Border(),
          ),
        },
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalInset,
            denseLayout
                ? 12
                : compact
                ? 12
                : 16,
            horizontalInset,
            compact ? 10 : 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.5,
                child: const AppBrandLockup(),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final middleHeight = constraints.maxHeight;
                    final maximumGap = math.max(
                      0.0,
                      middleHeight - navigationExtent,
                    );
                    final balancedGap =
                        (middleHeight -
                            preferredOrnamentExtent -
                            navigationExtent) /
                        2;
                    final leadingGap = math.min(
                      maximumGap,
                      math.max(brandNavigationGap, balancedGap),
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SizedBox(height: leadingGap),
                        Semantics(
                          key: WorkspaceShellKeys.navigation,
                          container: true,
                          explicitChildNodes: true,
                          label: 'Main navigation',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              for (final entry
                                  in visibleDestinations) ...<Widget>[
                                _NavigationButton(
                                  destination: entry,
                                  selected: destination == entry,
                                  height: navigationHeight,
                                  onPressed: () => onDestinationChanged(entry),
                                ),
                                if (entry != visibleDestinations.last)
                                  SizedBox(height: navigationGap),
                              ],
                            ],
                          ),
                        ),
                        if (ledger)
                          const Expanded(child: _LedgerSidebarMarginalia())
                        else if (sakura)
                          const Expanded(child: _SakuraSidebarBotanical())
                        else
                          const Spacer(),
                      ],
                    );
                  },
                ),
              ),
              _ModeSelector(
                mode: mode,
                compact: compact,
                onModeChanged: onModeChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Ledger botanical belongs to the sidebar's remaining instrument bay.
///
/// Avalonia clips this host between navigation and the bottom mode selector,
/// then bottom-centres the authored art at a 198 x 290 maximum. Keeping those
/// constraints here lets the art naturally shrink with the available height
/// at the supported compact window instead of overlapping feature content.
class _LedgerSidebarMarginalia extends StatelessWidget {
  const _LedgerSidebarMarginalia();

  static const double _aspectRatio = 2 / 3;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 7, 0, 2),
    child: ClipRect(
      key: WorkspaceShellKeys.ledgerMarginaliaHost,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 198, maxHeight: 290),
          child: const AspectRatio(
            aspectRatio: _aspectRatio,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: 0.78,
                  child: RetainedAssetImage(
                    assetPath: IlluminatedLedgerSpec.marginaliaAssetPath,
                    assetLabel: 'Illuminated Ledger marginalia',
                    imageKey: LedgerBackdrop.marginaliaKey,
                    failureKey: LedgerBackdrop.marginaliaFailureKey,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                    filterQuality: FilterQuality.high,
                    background: Color(0xFFE8D2A3),
                    foreground: Color(0xFF352516),
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

/// The Sakura branch occupies only the flexible instrument bay between the
/// navigation rows and workstation controls.
class _SakuraSidebarBotanical extends StatelessWidget {
  const _SakuraSidebarBotanical();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 7, 0, 2),
    child: LayoutBuilder(
      builder: (context, constraints) {
        var fitScale = constraints.maxHeight.isFinite
            ? constraints.maxHeight /
                  SakuraSidebarBotanicalAsset.authoredSize.height
            : 1.0;
        final widthScale = constraints.maxWidth.isFinite
            ? constraints.maxWidth /
                  SakuraSidebarBotanicalAsset.authoredSize.width
            : 1.0;
        if (widthScale < fitScale) fitScale = widthScale;
        fitScale = fitScale.clamp(0.0, 1.0);

        // Compact windows crop a still-readable branch instead of shrinking
        // its petals, stamens, and bark into unreadable pinpricks
        // that prompted the retained-art pass.
        final drawScale = fitScale < .72 ? .72 : fitScale;
        final drawWidth =
            SakuraSidebarBotanicalAsset.authoredSize.width * drawScale;
        final drawHeight =
            SakuraSidebarBotanicalAsset.authoredSize.height * drawScale;

        return ClipRect(
          key: WorkspaceShellKeys.sakuraBotanicalHost,
          child: OverflowBox(
            alignment: Alignment.bottomCenter,
            minWidth: 0,
            maxWidth: SakuraSidebarBotanicalAsset.authoredSize.width,
            minHeight: 0,
            maxHeight: SakuraSidebarBotanicalAsset.authoredSize.height,
            child: SizedBox(
              width: drawWidth,
              height: drawHeight,
              child: const FittedBox(
                fit: BoxFit.fill,
                child: SakuraSidebarBotanicalAsset(),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({
    required this.destination,
    required this.selected,
    required this.height,
    required this.onPressed,
  });

  final ShellDestination destination;
  final bool selected;
  final double height;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.family == RetainedVisualFamily.illuminatedLedger;
    final sakura = spec.family == RetainedVisualFamily.sakuraNightGarden;
    final denseLayout = spec.usesDenseSplitLayout;
    final navigationFontSize = denseLayout
        ? 16.0
        : (spec.typography.button.fontSize ?? 14.0);
    final textScale =
        MediaQuery.textScalerOf(context).scale(navigationFontSize) /
        navigationFontSize;
    final button = AppButton(
      key: destination.actionKey,
      role: AppButtonRole.sidebarNavigation,
      selected: selected,
      semanticLabel: destination.semanticLabel,
      onPressed: onPressed,
      minimumSize: Size(0, height),
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: textScale > 1.25 ? 8 : 11,
      ),
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            SizedBox.square(
              dimension: ledger
                  ? 30
                  : sakura
                  ? 24
                  : 18,
              child: Center(
                child: AppVectorGlyph(
                  _iconFor(destination),
                  size: ledger
                      ? 21
                      : sakura
                      ? 20
                      : 18,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                destination.label,
                style: ledger
                    ? const TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      )
                    : sakura
                    ? spec.typography.button.copyWith(
                        color: spec.palette.text,
                        fontSize: standardNavigationLabelFontSize,
                        fontWeight: FontWeight.w600,
                      )
                    : const TextStyle(
                        fontSize: standardNavigationLabelFontSize,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          if (sakura && selected)
            const Positioned(
              top: 0,
              bottom: 0,
              right: -18,
              width: 30,
              child: IgnorePointer(
                child: CustomPaint(painter: SakuraNavigationTabPainter()),
              ),
            ),
          Positioned.fill(child: button),
        ],
      ),
    );
  }

  String _iconFor(ShellDestination destination) => switch (destination) {
    ShellDestination.planner => 'compass',
    ShellDestination.bonusRecipes => 'spark',
    ShellDestination.inventory => 'vault',
    ShellDestination.recipeEditor => 'quill',
    ShellDestination.appearance => 'rosette',
    ShellDestination.data => 'profile',
    ShellDestination.about => 'info',
  };
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.mode,
    required this.compact,
    required this.onModeChanged,
  });

  final CraftMode mode;
  final bool compact;
  final ValueChanged<CraftMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ShellActionKeys.modeSelector,
      container: true,
      explicitChildNodes: true,
      label: 'Craft mode',
      value: mode.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (
                var index = 0;
                index < CraftMode.values.length;
                index++
              ) ...<Widget>[
                if (index > 0) SizedBox(width: compact ? 5 : 7),
                Expanded(
                  child: SizedBox(
                    height: compact ? 42 : 46,
                    child: AppButton(
                      key: ShellActionKeys.mode(CraftMode.values[index]),
                      role: AppButtonRole.modeSelector,
                      selected: mode == CraftMode.values[index],
                      semanticLabel:
                          'Switch to ${CraftMode.values[index].label}',
                      onPressed: () => onModeChanged(CraftMode.values[index]),
                      minimumSize: const Size(0, 40),
                      padding: EdgeInsets.zero,
                      child: AppVectorGlyph(
                        _iconFor(CraftMode.values[index]),
                        size: compact ? 18 : 20,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _iconFor(CraftMode mode) => switch (mode) {
    CraftMode.alchemy => 'flask',
    CraftMode.cooking => 'pot',
    CraftMode.processing => 'processing',
  };
}

class _ContentTransitionHost extends StatefulWidget {
  const _ContentTransitionHost({
    required this.destination,
    required this.transition,
    required this.transitionSpeed,
    required this.reduceMotion,
    required this.child,
  });

  final ShellDestination destination;
  final ShellContentTransition transition;
  final ShellContentTransitionSpeed transitionSpeed;
  final bool reduceMotion;
  final Widget child;

  @override
  State<_ContentTransitionHost> createState() => _ContentTransitionHostState();
}

class _ContentTransitionHostState extends State<_ContentTransitionHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    value: 1,
  );

  @override
  void didUpdateWidget(_ContentTransitionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destination != widget.destination &&
        !widget.reduceMotion &&
        widget.transition != ShellContentTransition.off) {
      _clock.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platformReducedMotion = MediaQuery.maybeOf(
      context,
    )?.disableAnimations;
    final immediate =
        widget.reduceMotion ||
        (platformReducedMotion ?? false) ||
        widget.transition == ShellContentTransition.off;

    final duration = widget.transitionSpeed.duration;
    if (_clock.duration != duration) _clock.duration = duration;
    if (immediate && _clock.isAnimating) _clock.stop();
    final begin = switch (widget.transition) {
      ShellContentTransition.slide => const Offset(0.025, 0),
      ShellContentTransition.lift => const Offset(0, 0.035),
      _ => Offset.zero,
    };
    final curve = CurvedAnimation(parent: _clock, curve: Curves.easeOutCubic);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        AnimatedBuilder(
          animation: _clock,
          child: SizedBox.expand(child: widget.child),
          builder: (context, content) => FadeTransition(
            opacity:
                immediate || widget.transition == ShellContentTransition.off
                ? const AlwaysStoppedAnimation<double>(1)
                : curve,
            child: SlideTransition(
              position: immediate
                  ? const AlwaysStoppedAnimation<Offset>(Offset.zero)
                  : Tween<Offset>(
                      begin: begin,
                      end: Offset.zero,
                    ).animate(curve),
              child: content,
            ),
          ),
        ),
        IgnorePointer(
          child: Semantics(
            key: immediate
                ? ShellActionKeys.immediateTransition
                : ShellActionKeys.animatedTransition,
            container: true,
            label: immediate
                ? 'Immediate workspace content'
                : '${widget.transition.label} workspace content transition',
            child: immediate
                ? const SizedBox.expand()
                : AnimatedSwitcher(
                    duration: duration,
                    child: SizedBox.expand(
                      key: ValueKey<ShellDestination>(widget.destination),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

@immutable
class _WorkspaceMetrics {
  const _WorkspaceMetrics({
    required this.workspacePadding,
    required this.sidebarWidth,
    required this.contentGap,
    required this.compact,
  });

  factory _WorkspaceMetrics.resolve({
    required BoxConstraints constraints,
    required ThemeGeometry geometry,
  }) {
    // Both retained desktop implementations preserve the same shell at the
    // supported 1200x752 minimum. Responsive decisions belong to each feature
    // view; compacting the shell here caused an app-wide geometry mismatch.
    const compact = false;
    final base = geometry.workspacePadding;

    return _WorkspaceMetrics(
      workspacePadding: base,
      sidebarWidth: geometry.sidebarWidth,
      contentGap: geometry.contentGap,
      compact: compact,
    );
  }

  final EdgeInsets workspacePadding;
  final double sidebarWidth;
  final double contentGap;
  final bool compact;
}
