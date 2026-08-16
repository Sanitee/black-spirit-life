import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

import '../../app/state/planner_application_controller.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/state/state_copy.dart';
import '../../visual/visual.dart';
import 'planner_contracts.dart';
import 'planner_keys.dart';
import 'planner_shared.dart';

class BonusView extends StatefulWidget {
  const BonusView({
    required this.controller,
    required this.externalActions,
    super.key,
  });

  final ModeFeatureController controller;
  final PlannerExternalActions externalActions;

  @override
  State<BonusView> createState() => _BonusViewState();
}

class _BonusViewState extends State<BonusView> {
  static const Map<CraftMode, List<String>> _questPools =
      <CraftMode, List<String>>{
        CraftMode.alchemy: <String>[
          'Clear Liquid Reagent',
          'Pure Powder Reagent',
          "Clown's Blood",
        ],
        CraftMode.cooking: <String>[
          'Beer',
          'Grilled Bird Meat',
          'Pickled Vegetables',
        ],
        CraftMode.processing: <String>[],
      };

  int _rebuildRevision = 0;

  List<String> get _pool {
    final craftable = widget.controller.craftableNames;
    return _questPools[widget.controller.mode]!
        .map((name) {
          for (final candidate in craftable) {
            if (_sameName(candidate, name)) return candidate;
          }
          return null;
        })
        .whereType<String>()
        .toList(growable: false);
  }

  String _targetFor(List<String> pool) {
    final current = widget.controller.state.value.bonusTarget;
    for (final name in pool) {
      if (_sameName(name, current)) return name;
    }
    return pool.isEmpty ? '' : pool.first;
  }

  bool _selectBonusTarget(String name) {
    final pool = _pool;
    String? match;
    for (final candidate in pool) {
      if (_sameName(candidate, name)) {
        match = candidate;
        break;
      }
    }
    if (match == null) return false;
    widget.controller.updateState(
      (state) => state.copyWith(bonusTarget: match),
      immediate: true,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.mode == CraftMode.processing) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.controller.state,
        widget.controller.expandedSteps,
      ]),
      builder: (context, _) {
        final state = widget.controller.state.value;
        final pool = _pool;
        final target = _targetFor(pool);
        final denseLayout = context.visualTheme.usesDenseSplitLayout;
        final plan = widget.controller.owner.assembly.build(
          catalog: widget.controller.owner.catalog,
          mode: widget.controller.mode,
          state: state,
          targetOverride: target,
          wantOverride: state.bonusWant,
        );
        final planScrollIdentity = (
          _rebuildRevision,
          plan.target.trim().toLowerCase(),
          plan.want,
          plan.steps
              .map((step) => step.name.trim().toLowerCase())
              .join('\u001f'),
          plan.missing
              .map((row) => row.name.trim().toLowerCase())
              .join('\u001f'),
        );
        return Semantics(
          container: true,
          explicitChildNodes: true,
          label: '${widget.controller.mode.label} Bonus Recipes',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _BonusCommandBand(
                key: const ValueKey<String>('bonus-command-band'),
                controller: widget.controller,
                externalActions: widget.externalActions,
                pool: pool,
                target: target,
                onTargetSelected: _selectBonusTarget,
                onRebuild: () => setState(() => _rebuildRevision += 1),
              ),
              SizedBox(
                key: const ValueKey<String>('bonus-command-gap'),
                height: denseLayout ? 24 : 48,
              ),
              Expanded(
                child: pool.isEmpty
                    ? _BonusEmpty(
                        mode: widget.controller.mode,
                        showEditor: widget.controller.advancedEditorEnabled,
                      )
                    : PlannerPlanColumns(
                        key: const ValueKey<String>('bonus-plan-columns'),
                        actionKey: BonusActionKeys.b07,
                        controller: widget.controller,
                        plan: plan,
                        scrollResetIdentity: planScrollIdentity,
                        externalActions: widget.externalActions,
                        allowCompletion: false,
                        bonusPlan: true,
                        queueTitle: 'Craft Queue',
                        needTitle: 'Need First',
                        queueCountNoun: 'steps',
                        standardQueueFlex: 106,
                        standardNeedFlex: 94,
                        allowMarketActions: false,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BonusCommandBand extends StatelessWidget {
  const _BonusCommandBand({
    required this.controller,
    required this.externalActions,
    required this.pool,
    required this.target,
    required this.onTargetSelected,
    required this.onRebuild,
    super.key,
  });

  final ModeFeatureController controller;
  final PlannerExternalActions externalActions;
  final List<String> pool;
  final String target;
  final SelectPlannerTarget onTargetSelected;
  final VoidCallback onRebuild;

  @override
  Widget build(BuildContext context) {
    final state = controller.state.value;
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final denseLayout = spec.usesDenseSplitLayout;
    final compactDenseText =
        denseLayout && MediaQuery.textScalerOf(context).scale(1) <= 1.25;
    final targetField = pool.isEmpty
        ? _NoBonusTarget(mode: controller.mode)
        : PlannerTargetChooser(
            controller: controller,
            semanticLabel: 'Bonus recipe target',
            actionKey: BonusActionKeys.b01,
            controlHeight: denseLayout
                ? null
                : plannerStandardCommandControlHeight,
            target: PlannerCommandTarget(
              value: target,
              names: pool,
              onSelected: onTargetSelected,
            ),
          );
    final recipes = AppButton(
      key: BonusActionKeys.b03,
      role: ledger ? AppButtonRole.primary : AppButtonRole.secondary,
      minimumSize: const Size(0, plannerStandardCommandControlHeight),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      onPressed: pool.isEmpty
          ? null
          : () => externalActions.openRecipeBook(
              RecipeBookRequest(
                controller: controller,
                context: RecipeBookCallingContext.bonus,
                allowedTargets: List<String>.unmodifiable(pool),
              ),
            ),
      child: _buttonContent('book', 'Recipes'),
    );
    final rebuild = denseLayout
        ? AppButton(
            key: BonusActionKeys.b04,
            role: ledger ? AppButtonRole.primary : AppButtonRole.secondary,
            minimumSize: const Size(0, plannerStandardCommandControlHeight),
            padding: EdgeInsets.zero,
            semanticLabel: 'Rebuild bonus plan',
            tooltip: 'Rebuild bonus plan',
            onPressed: pool.isEmpty ? null : onRebuild,
            child: const AppVectorGlyph('calc', size: 23),
          )
        : AppButton.icon(
            key: BonusActionKeys.b04,
            icon: const AppVectorGlyph('calc', size: 18),
            semanticLabel: 'Rebuild bonus plan',
            tooltip: 'Rebuild bonus plan',
            onPressed: pool.isEmpty ? null : onRebuild,
          );
    final finalAction = pool.isEmpty
        ? controller.advancedEditorEnabled
              ? AppButton(
                  key: BonusActionKeys.b06,
                  minimumSize: const Size(
                    0,
                    plannerStandardCommandControlHeight,
                  ),
                  onPressed: () => controller.navigate('editor'),
                  child: _buttonContent(
                    'edit',
                    'Recipe Editor',
                    scaleDown: compactDenseText,
                  ),
                )
              : const SizedBox.shrink()
        : AppButton(
            key: BonusActionKeys.b05,
            role: AppButtonRole.primary,
            minimumSize: const Size(0, plannerStandardCommandControlHeight),
            onPressed: () {
              if (!_sameName(controller.state.value.bonusTarget, target)) {
                onTargetSelected(target);
              }
              controller.useBonusAsTarget();
              // The transfer contract includes navigation, not merely a state
              // copy. Keep the public control's observable postcondition
              // explicit even if a future controller implementation changes.
              if (controller.state.value.view != 'plan') {
                controller.navigate('plan');
              }
            },
            child: _buttonContent(
              'target',
              'Use As Target',
              scaleDown: compactDenseText,
            ),
          );
    return AppSurface(
      role: AppSurfaceRole.commandBand,
      semanticLabel: 'Bonus recipe commands',
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final enlargedText = textScale > 1.25;
          if (enlargedText) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: constraints.maxWidth,
                  child: _targetGroup(context, targetField),
                ),
                const SizedBox(height: 10),
                _amountGroup(
                  context,
                  state.bonusWant,
                  (86 * textScale).clamp(100, constraints.maxWidth).toDouble(),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 112),
                      child: recipes,
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 48),
                      child: rebuild,
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 150),
                      child: finalAction,
                    ),
                  ],
                ),
              ],
            );
          }
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(child: _targetGroup(context, targetField)),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 106,
                      height: plannerStandardCommandControlHeight,
                      child: recipes,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    SizedBox(
                      width: 82,
                      child: _amountGroup(context, state.bonusWant, 82),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 52,
                      height: plannerStandardCommandControlHeight,
                      child: rebuild,
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 156,
                      height: plannerStandardCommandControlHeight,
                      child: finalAction,
                    ),
                  ],
                ),
              ],
            );
          }
          if (denseLayout) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 96,
                  child: Column(
                    key: const ValueKey<String>('bonus-command-target'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _fieldLabel(context, 'Bonus Target'),
                      const SizedBox(height: 5),
                      SizedBox(
                        height: _targetIconSize(context),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            Expanded(
                              child: _targetControlRow(context, targetField),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 112,
                              height: plannerStandardCommandControlHeight,
                              child: recipes,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 104,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20, right: 4),
                    child: Column(
                      key: const ValueKey<String>('bonus-command-amount'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _fieldLabel(context, 'Amount'),
                        const SizedBox(height: 5),
                        SizedBox(
                          height: _targetIconSize(context),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              SizedBox(
                                width: 86,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _amountControl(
                                    context,
                                    state.bonusWant,
                                    78,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 48,
                                height: plannerStandardCommandControlHeight,
                                child: rebuild,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: SizedBox(
                                    width: 176,
                                    height: plannerStandardCommandControlHeight,
                                    child: finalAction,
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
              ],
            );
          }
          const targetWidth = 490.0;
          const recipesWidth = 122.0;
          const amountColumnWidth = 86.0;
          const amountFieldWidth = 78.0;
          const rebuildWidth = 68.0;
          const finalWidth = 206.0;
          const spacing = 13.0;
          const referenceWidth =
              targetWidth +
              recipesWidth +
              amountColumnWidth +
              rebuildWidth +
              finalWidth +
              spacing * 4;
          final referenceControls = SizedBox(
            width: referenceWidth,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                SizedBox(
                  width: targetWidth,
                  child: _targetGroup(context, targetField),
                ),
                const SizedBox(width: spacing),
                SizedBox(
                  width: recipesWidth,
                  height: plannerStandardCommandControlHeight,
                  child: recipes,
                ),
                const SizedBox(width: spacing),
                SizedBox(
                  width: amountColumnWidth,
                  child: _amountGroup(
                    context,
                    state.bonusWant,
                    amountFieldWidth,
                  ),
                ),
                const SizedBox(width: spacing),
                SizedBox(
                  width: rebuildWidth,
                  height: plannerStandardCommandControlHeight,
                  child: rebuild,
                ),
                const SizedBox(width: spacing),
                SizedBox(
                  width: finalWidth,
                  height: plannerStandardCommandControlHeight,
                  child: finalAction,
                ),
              ],
            ),
          );
          if (constraints.maxWidth >= referenceWidth) {
            return Align(
              alignment: Alignment.bottomLeft,
              child: referenceControls,
            );
          }
          // Avalonia retains the same command geometry at 1200x752 and lets
          // the window edge clip the final action. OverflowBox reproduces that
          // behavior without a RenderFlex overflow or changing semantics.
          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.bottomLeft,
              fit: OverflowBoxFit.deferToChild,
              minWidth: referenceWidth,
              maxWidth: referenceWidth,
              child: referenceControls,
            ),
          );
        },
      ),
    );
  }

  Widget _targetGroup(BuildContext context, Widget targetField) => Column(
    key: const ValueKey<String>('bonus-command-target'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _fieldLabel(context, 'Bonus Target'),
      const SizedBox(height: 5),
      _targetControlRow(context, targetField),
    ],
  );

  Widget _targetControlRow(BuildContext context, Widget targetField) => Row(
    children: <Widget>[
      SizedBox(
        width: 58,
        height: _targetIconSize(context),
        child: target.isEmpty
            ? SizedBox.square(dimension: _targetIconSize(context))
            : Align(
                child: PlannerItemIcon(
                  controller: controller,
                  name: target,
                  size: _targetIconSize(context),
                ),
              ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) => Align(
            child: SizedBox(
              width: constraints.maxWidth.clamp(0, 390).toDouble(),
              height: _referenceControlHeight(context),
              child: targetField,
            ),
          ),
        ),
      ),
    ],
  );

  Widget _amountGroup(BuildContext context, num value, double width) => Column(
    key: const ValueKey<String>('bonus-command-amount'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _fieldLabel(context, 'Amount'),
      const SizedBox(height: 5),
      Align(
        alignment: Alignment.centerLeft,
        child: _amountControl(context, value, width),
      ),
    ],
  );

  Widget _amountControl(BuildContext context, num value, double width) =>
      SizedBox(
        height: _referenceControlHeight(context),
        child: PlannerNumberField(
          value: value,
          width: width,
          minimumHeight: context.visualTheme.usesDenseSplitLayout
              ? null
              : plannerStandardCommandControlHeight,
          semanticLabel: 'Bonus requested amount',
          actionKey: BonusActionKeys.b02,
          onCommit: (next) => controller.commitAmount(next, bonus: true),
        ),
      );

  double? _referenceControlHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1) > 1.25
      ? null
      : context.visualTheme.usesDenseSplitLayout
      ? 38
      : plannerStandardCommandControlHeight;

  double _targetIconSize(BuildContext context) =>
      context.visualTheme.usesDenseSplitLayout
      ? 54
      : plannerStandardCommandControlHeight;

  Widget _fieldLabel(BuildContext context, String label) => Text(
    label.toUpperCase(),
    maxLines: 1,
    style: context.visualTheme.typography.label.copyWith(
      color: context.visualTheme.isIlluminatedLedger
          ? const Color(0xFF806633)
          : context.visualTheme.isSakuraNightGarden
          ? context.visualTheme.palette.trimBright
          : const Color(0xffd7c783),
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
  );

  Widget _buttonContent(String glyph, String label, {bool scaleDown = false}) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        AppVectorGlyph(glyph, size: 16),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
    return scaleDown
        ? FittedBox(fit: BoxFit.scaleDown, child: content)
        : content;
  }
}

class _NoBonusTarget extends StatelessWidget {
  const _NoBonusTarget({required this.mode});

  final CraftMode mode;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final standard = context.standardVisual;
    return Semantics(
      liveRegion: true,
      label: 'No usable ${mode.label} bonus quest recipes',
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          gradient: ledger
              ? spec.materials.surfaceRaised
              : sakura
              ? SakuraNightGardenSpec.raisedSurfaceGradient
              : StandardSpec.accentGlass(
                  standard.accentHue,
                  topAlpha: 54,
                  bottomAlpha: 18,
                  neon: standard.neon,
                ),
          borderRadius: BorderRadius.circular(
            ledger
                ? 2
                : sakura
                ? spec.geometry.fieldRadius
                : 6,
          ),
          border: Border.all(
            color: ledger
                ? spec.palette.trim.withAlpha(136)
                : sakura
                ? spec.palette.trim.withAlpha(176)
                : StandardSpec.accentBrush(
                    standard.accentHue,
                    alpha: .32,
                    neon: standard.neon,
                  ),
          ),
        ),
        child: Text(
          'No bonus quest recipe data',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: spec.typography.body.copyWith(
            color: spec.palette.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _BonusEmpty extends StatelessWidget {
  const _BonusEmpty({required this.mode, required this.showEditor});

  final CraftMode mode;
  final bool showEditor;

  String get _pathMessage => switch (mode) {
    CraftMode.cooking => 'No bonus quest recipe matches the current filters.',
    CraftMode.processing =>
      'Bonus recipes are only available for Alchemy and Cooking.',
    CraftMode.alchemy =>
      'No alchemy bonus quest formulas are present in the current recipe '
          'data.${showEditor ? ' Add the quest recipe in Recipe Editor to plan it here.' : ''}',
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final denseLayout = context.visualTheme.usesDenseSplitLayout;
      final path = _BonusEmptyPanel(
        key: const ValueKey<String>('bonus-empty-path'),
        semanticLabel: 'Craft queue is empty',
        message: _pathMessage,
      );
      const missing = _BonusEmptyPanel(
        key: ValueKey<String>('bonus-empty-need'),
        semanticLabel: 'Need first is empty',
        message:
            'Bonus quest materials will appear here once a bonus quest recipe '
            'is available.',
      );
      if (constraints.maxWidth < 760) {
        return Column(
          children: <Widget>[
            Expanded(child: path),
            const SizedBox(height: 12),
            const Expanded(child: missing),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            flex: denseLayout ? 96 : 106,
            child: Padding(
              padding: EdgeInsets.only(right: denseLayout ? 12 : 0),
              child: path,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: denseLayout ? 104 : 94,
            child: Padding(
              padding: EdgeInsets.only(left: denseLayout ? 20 : 0),
              child: missing,
            ),
          ),
        ],
      );
    },
  );
}

class _BonusEmptyPanel extends StatelessWidget {
  const _BonusEmptyPanel({
    required this.semanticLabel,
    required this.message,
    super.key,
  });

  final String semanticLabel;
  final String message;

  @override
  Widget build(BuildContext context) => AppSurface(
    role: AppSurfaceRole.layout,
    semanticLabel: semanticLabel,
    padding: const EdgeInsets.all(12),
    child: Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: context.visualTheme.typography.body.copyWith(
          color: context.visualTheme.palette.textMuted,
        ),
      ),
    ),
  );
}

bool _sameName(String left, String right) =>
    left.trim().toLowerCase() == right.trim().toLowerCase();
