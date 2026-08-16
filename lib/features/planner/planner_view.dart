import 'package:flutter/material.dart';

import '../../app/state/planner_application_controller.dart';
import '../../domain/state/state_copy.dart';
import '../../visual/visual.dart';
import 'planner_contracts.dart';
import 'planner_keys.dart';
import 'planner_shared.dart';

class PlannerView extends StatelessWidget {
  const PlannerView({
    required this.controller,
    required this.externalActions,
    super.key,
  });

  final ModeFeatureController controller;
  final PlannerExternalActions externalActions;

  @override
  Widget build(BuildContext context) {
    final denseLayout = context.visualTheme.usesDenseSplitLayout;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        controller.state,
        controller.plan,
        controller.expandedSteps,
      ]),
      builder: (context, _) {
        final state = controller.state.value;
        final plan = controller.plan.value;
        final completedPlan = state.completedSteps.isEmpty
            ? plan
            : controller.owner.assembly.build(
                catalog: controller.owner.catalog,
                mode: controller.mode,
                state: state.copyWith(completedSteps: const <String>{}),
              );
        return Semantics(
          container: true,
          explicitChildNodes: true,
          label: '${controller.mode.label} Planner',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _PlannerCommandBand(
                controller: controller,
                externalActions: externalActions,
              ),
              SizedBox(height: denseLayout ? 44 : 33),
              Expanded(
                child: PlannerPlanColumns(
                  actionKey: PlannerActionKeys.p21,
                  controller: controller,
                  plan: plan,
                  completedPlan: completedPlan,
                  externalActions: externalActions,
                  allowCompletion: true,
                  queueTitle: 'Craft Queue',
                  needTitle: 'Need First',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlannerCommandBand extends StatelessWidget {
  const _PlannerCommandBand({
    required this.controller,
    required this.externalActions,
  });

  final ModeFeatureController controller;
  final PlannerExternalActions externalActions;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final denseLayout = spec.usesDenseSplitLayout;
    final bodyFontSize = spec.typography.body.fontSize ?? 14.0;
    final textScale =
        MediaQuery.textScalerOf(context).scale(bodyFontSize) / bodyFontSize;
    final state = controller.state.value;
    final targetChooser = PlannerTargetChooser(
      controller: controller,
      semanticLabel: 'Craft target',
      actionKey: PlannerActionKeys.p01,
      controlHeight: denseLayout ? null : plannerStandardCommandControlHeight,
      target: PlannerCommandTarget(
        value: state.target,
        names: controller.craftableNames,
        onSelected: controller.selectTarget,
      ),
    );
    final Widget targetField = denseLayout
        ? targetChooser
        : ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: plannerStandardCommandControlHeight,
            ),
            child: targetChooser,
          );
    final recipes = AppButton(
      key: PlannerActionKeys.p03,
      role: ledger ? AppButtonRole.primary : AppButtonRole.secondary,
      minimumSize: Size(
        denseLayout ? 112 : 102,
        denseLayout ? 48 : plannerStandardCommandControlHeight,
      ),
      semanticLabel: 'Recipes',
      onPressed: () => externalActions.openRecipeBook(
        RecipeBookRequest(
          controller: controller,
          context: RecipeBookCallingContext.planner,
          allowedTargets: controller.craftableNames,
        ),
      ),
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppVectorGlyph('book', size: 16),
            SizedBox(width: 7),
            Text('Recipes'),
          ],
        ),
      ),
    );
    final amount = PlannerNumberField(
      value: state.want,
      width: denseLayout ? 78 : 86,
      semanticLabel: 'Requested amount',
      actionKey: PlannerActionKeys.p02,
      minimumHeight: denseLayout ? null : plannerStandardCommandControlHeight,
      onCommit: controller.commitAmount,
    );
    final rebuild = AppButton(
      key: PlannerActionKeys.p04,
      role: AppButtonRole.primary,
      minimumSize: denseLayout
          ? const Size.square(36)
          : const Size(48, plannerStandardCommandControlHeight),
      padding: EdgeInsets.zero,
      semanticLabel: 'Build or recalculate plan',
      tooltip: 'Recalculate',
      onPressed: controller.recalculate,
      child: const AppVectorGlyph('calc', size: 23),
    );
    final fullTarget = PlannerToggle(
      actionKey: PlannerActionKeys.p05,
      value: state.ignoreTargetInventory,
      label: 'Full target amount',
      onChanged: controller.setFullTargetAmount,
    );
    final ignoreOwned = PlannerToggle(
      actionKey: PlannerActionKeys.p06,
      value: state.ignoreIngredientInventory,
      label: 'Ignore owned ingredients',
      onChanged: controller.setIgnoreOwnedIngredients,
    );
    final toggles = Wrap(
      spacing: 8,
      runSpacing: 7,
      alignment: WrapAlignment.end,
      children: <Widget>[fullTarget, ignoreOwned],
    );

    return AppSurface(
      // Dense full themes place authored controls directly on their workspace
      // material. Standard deliberately keeps its surrounding glass band.
      role: denseLayout ? AppSurfaceRole.layout : AppSurfaceRole.commandBand,
      padding: denseLayout
          ? const EdgeInsets.all(12)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      semanticLabel: 'Planner commands',
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (denseLayout && constraints.maxWidth >= 820 && textScale <= 1.25) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 96,
                  child: SizedBox(
                    height: 72,
                    child: LayoutBuilder(
                      builder: (context, leftConstraints) => Stack(
                        children: <Widget>[
                          const Positioned(
                            left: 64,
                            top: 0,
                            child: _CommandLabel('Craft Target'),
                          ),
                          Positioned(
                            left: 0,
                            top: 18,
                            width: 54,
                            height: 54,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: PlannerItemIcon(
                                controller: controller,
                                name: state.target,
                                size: 54,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 64,
                            right: 122,
                            top: 18,
                            height: 48,
                            child: targetField,
                          ),
                          Positioned(
                            right: 0,
                            top: 18,
                            width: 112,
                            height: 48,
                            child: recipes,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 104,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: SizedBox(
                      height: 72,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          const Positioned(
                            left: 0,
                            top: 0,
                            width: 78,
                            child: _CommandLabel('Amount'),
                          ),
                          Positioned(
                            left: 0,
                            top: 18,
                            width: 86,
                            height: 54,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: 78,
                                height: 38,
                                child: amount,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 98,
                            top: 18,
                            width: 68,
                            height: 54,
                            child: Center(
                              child: SizedBox(
                                width: 68,
                                height: 48,
                                child: rebuild,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 178,
                            right: 4,
                            top: 4,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: <Widget>[
                                fullTarget,
                                const SizedBox(height: 8),
                                ignoreOwned,
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          if (!denseLayout &&
              constraints.maxWidth >= 1110 &&
              textScale <= 1.25) {
            return SizedBox(
              // Labels and the compact controls consume the whole band. The
              // fields also pass this height into InputDecorator, preventing
              // an unpainted lower strip from reading as a drop shadow.
              height: 70,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  const Positioned(
                    left: 70,
                    top: 1,
                    child: _CommandLabel('Craft Target'),
                  ),
                  const Positioned(
                    left: 608,
                    top: 1,
                    child: _CommandLabel('Amount'),
                  ),
                  Positioned(
                    left: 0,
                    top: 23,
                    width: 58,
                    height: plannerStandardCommandControlHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: PlannerItemIcon(
                        controller: controller,
                        name: state.target,
                        size: plannerStandardCommandControlHeight,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 70,
                    top: 23,
                    width: 390,
                    height: plannerStandardCommandControlHeight,
                    child: targetField,
                  ),
                  Positioned(
                    left: 472,
                    top: 23,
                    width: 102,
                    height: plannerStandardCommandControlHeight,
                    child: recipes,
                  ),
                  Positioned(
                    left: 608,
                    top: 23,
                    width: 86,
                    height: plannerStandardCommandControlHeight,
                    child: amount,
                  ),
                  Positioned(
                    left: 706,
                    top: 23,
                    width: 48,
                    height: plannerStandardCommandControlHeight,
                    child: rebuild,
                  ),
                  Positioned(
                    left: 786,
                    right: 0,
                    top: 0,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          fullTarget,
                          const SizedBox(height: 6),
                          ignoreOwned,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          if (constraints.maxWidth >= 1100) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                PlannerItemIcon(
                  controller: controller,
                  name: state.target,
                  size: 54,
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 390,
                  child: _LabeledControl(
                    label: 'Craft Target',
                    child: targetField,
                  ),
                ),
                const SizedBox(width: 12),
                recipes,
                const SizedBox(width: 12),
                _LabeledControl(label: 'Amount', child: amount),
                const SizedBox(width: 10),
                SizedBox(width: 48, height: 48, child: rebuild),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 252),
                  child: toggles,
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  PlannerItemIcon(
                    controller: controller,
                    name: state.target,
                    size: 54,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _LabeledControl(
                      label: 'Craft Target',
                      child: targetField,
                    ),
                  ),
                  const SizedBox(width: 8),
                  recipes,
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  _LabeledControl(label: 'Amount', child: amount),
                  const SizedBox(width: 7),
                  rebuild,
                  const SizedBox(width: 9),
                  Expanded(child: toggles),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LabeledControl extends StatelessWidget {
  const _LabeledControl({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[_CommandLabel(label), const SizedBox(height: 3), child],
  );
}

class _CommandLabel extends StatelessWidget {
  const _CommandLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    return Text(
      label.toUpperCase(),
      style: spec.typography.label.copyWith(
        color: ledger
            ? const Color(0xFF6F501F)
            : spec.isSakuraNightGarden
            ? spec.palette.trimBright
            : const Color(0xFFD7C783),
        fontSize: spec.usesDenseSplitLayout ? 11 : 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
