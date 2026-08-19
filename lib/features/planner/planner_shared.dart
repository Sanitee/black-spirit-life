import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/state/planner_application_controller.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/planner/acquisition_recipe_resolution.dart';
import '../../domain/planner/afk_weight_calculator.dart';
import '../../domain/planner/ingredient_quality.dart';
import '../../domain/planner/planner_models.dart';
import '../../domain/state/planner_state.dart';
import '../../domain/state/state_copy.dart';
import '../../shared/overlays/anchored_popover.dart';
import '../../visual/illuminated_ledger/ledger_ornament_painters.dart';
import '../../visual/visual.dart';
import '../recipe_book/recipe_book_item_info.dart';
import '../shared/mode_item_icon.dart';
import '../shared/recipe_variant_selector.dart';
import 'need_material_order.dart';
import 'planner_contracts.dart';
import 'planner_keys.dart';

typedef SelectPlannerTarget = bool Function(String name);

/// Compact desktop height shared by the Standard Planner command controls.
///
/// Passing this into the field itself is important: a taller parent alone does
/// not make [InputDecorator]'s painted container consume the available space.
const double plannerStandardCommandControlHeight = 46;

/// Balanced selected-target label size for the taller Standard command field.
const double plannerStandardTargetFontSize = 15;

final class PlannerCommandTarget {
  const PlannerCommandTarget({
    required this.value,
    required this.names,
    required this.onSelected,
  });

  final String value;
  final List<String> names;
  final SelectPlannerTarget onSelected;
}

class PlannerTargetChooser extends StatefulWidget {
  const PlannerTargetChooser({
    required this.controller,
    required this.target,
    required this.semanticLabel,
    required this.actionKey,
    this.controlHeight,
    super.key,
  });

  final ModeFeatureController controller;
  final PlannerCommandTarget target;
  final String semanticLabel;
  final Key actionKey;
  final double? controlHeight;

  @override
  State<PlannerTargetChooser> createState() => _PlannerTargetChooserState();
}

class _PlannerTargetChooserState extends State<PlannerTargetChooser> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  late final TextEditingController _text = TextEditingController(
    text: widget.target.value,
  );
  late final FocusNode _focus = FocusNode()..addListener(_focusChanged);
  int _highlighted = 0;

  List<String> get _matches {
    final query = _text.text.trim().toLowerCase();
    if (query.isEmpty) return widget.target.names;
    return widget.target.names
        .where((name) => name.toLowerCase().contains(query))
        .toList(growable: false);
  }

  @override
  void didUpdateWidget(PlannerTargetChooser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && _text.text != widget.target.value) {
      _text.text = widget.target.value;
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_focusChanged)
      ..dispose();
    _text.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (_focus.hasFocus) {
      _show();
      return;
    }
    final selected = widget.target.onSelected(_text.text);
    if (!selected) _text.text = widget.target.value;
    _portal.hide();
  }

  void _show() {
    if (!_portal.isShowing) _portal.show();
  }

  void _filterChanged(String _) {
    setState(() => _highlighted = 0);
    _show();
  }

  void _select(String name) {
    if (!widget.target.onSelected(name)) return;
    _text.text = name;
    _text.selection = TextSelection.collapsed(offset: name.length);
    _portal.hide();
    _focus.requestFocus();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final matches = _matches;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (matches.isNotEmpty) {
        setState(() => _highlighted = (_highlighted + 1) % matches.length);
        _show();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (matches.isNotEmpty) {
        setState(
          () => _highlighted =
              (_highlighted - 1 + matches.length) % matches.length,
        );
        _show();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _portal.hide();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _submit(String value) {
    final matches = _matches;
    final exact = widget.target.names.where(
      (name) => name.toLowerCase() == value.trim().toLowerCase(),
    );
    if (exact.isNotEmpty) {
      _select(exact.first);
    } else if (matches.isNotEmpty) {
      _select(matches[_highlighted.clamp(0, matches.length - 1)]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final denseLayout = spec.usesDenseSplitLayout;
    return Semantics(
      key: widget.actionKey,
      container: true,
      textField: true,
      label: widget.semanticLabel,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) {
          final matches = _matches;
          return Positioned(
            left: 0,
            top: 0,
            child: CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, 6),
              showWhenUnlinked: false,
              child: SizedBox(
                width: 390,
                height: (matches.length * 44).clamp(56, 286).toDouble(),
                child: TapRegion(
                  groupId: this,
                  onTapOutside: (_) => _portal.hide(),
                  child: AppSurface(
                    role: AppSurfaceRole.popup,
                    semanticLabel: '${widget.semanticLabel} choices',
                    padding: const EdgeInsets.all(6),
                    child: matches.isEmpty
                        ? Center(
                            child: Text(
                              'No matching craftable recipes',
                              style: spec.typography.body,
                            ),
                          )
                        : ListView.builder(
                            itemCount: matches.length,
                            itemBuilder: (context, index) {
                              final name = matches[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: AppButton(
                                  selected: index == _highlighted,
                                  role: AppButtonRole.navigation,
                                  minimumSize: const Size.fromHeight(40),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
                                  ),
                                  semanticLabel: 'Select $name',
                                  onPressed: () => _select(name),
                                  child: Row(
                                    children: <Widget>[
                                      PlannerItemIcon(
                                        controller: widget.controller,
                                        name: name,
                                        size: 30,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ),
          );
        },
        child: TapRegion(
          groupId: this,
          child: CompositedTransformTarget(
            link: _link,
            child: PlannerTextField(
              controller: _text,
              focusNode: _focus,
              hintText: 'Search craftable recipes',
              semanticLabel: widget.semanticLabel,
              suffix: Icon(
                Icons.expand_more,
                color: spec.palette.textMuted,
                size: 19,
              ),
              onChanged: _filterChanged,
              onSubmitted: _submit,
              onKeyEvent: _handleKey,
              fontSize: denseLayout ? 13 : plannerStandardTargetFontSize,
              fontWeight: FontWeight.w700,
              minimumHeight: widget.controlHeight,
            ),
          ),
        ),
      ),
    );
  }
}

class PlannerNumberField extends StatefulWidget {
  const PlannerNumberField({
    required this.value,
    required this.onCommit,
    required this.semanticLabel,
    required this.actionKey,
    this.minimum = 1,
    this.width = 82,
    this.minimumHeight,
    super.key,
  });

  final num value;
  final bool Function(String text) onCommit;
  final String semanticLabel;
  final Key actionKey;
  final double minimum;
  final double width;
  final double? minimumHeight;

  @override
  State<PlannerNumberField> createState() => _PlannerNumberFieldState();
}

class _PlannerNumberFieldState extends State<PlannerNumberField> {
  late final TextEditingController _text = TextEditingController(
    text: formatGroupedEditableQuantity(widget.value.toDouble()),
  );
  late final FocusNode _focus = FocusNode(onKeyEvent: _handleKey)
    ..addListener(_focusChanged);
  String? _error;

  @override
  void didUpdateWidget(PlannerNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && oldWidget.value != widget.value) {
      _text.text = formatGroupedEditableQuantity(widget.value.toDouble());
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_focusChanged)
      ..dispose();
    _text.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!_focus.hasFocus) _commit();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      _commit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _commit() {
    final parsed = parsePlannerNumber(_text.text);
    final valid = parsed != null && widget.onCommit(_text.text);
    if (valid) {
      final normalized = parsed
          .floor()
          .clamp(widget.minimum.ceil(), 0x7fffffff)
          .toDouble();
      final display = formatGroupedEditableQuantity(normalized);
      _text.value = TextEditingValue(
        text: display,
        selection: TextSelection.collapsed(offset: display.length),
      );
      setState(() => _error = null);
      return;
    }
    setState(
      () => _error =
          'Enter a number of at least ${formatQuantity(widget.minimum)}',
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    key: widget.actionKey,
    width: widget.width,
    child: PlannerTextField(
      controller: _text,
      focusNode: _focus,
      semanticLabel: widget.semanticLabel,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.right,
      fontWeight: FontWeight.w700,
      minimumHeight: widget.minimumHeight,
      errorText: _error,
      onSubmitted: (_) => _commit(),
    ),
  );
}

class PlannerTextField extends StatelessWidget {
  const PlannerTextField({
    required this.controller,
    required this.semanticLabel,
    this.focusNode,
    this.hintText,
    this.errorText,
    this.prefix,
    this.suffix,
    this.keyboardType,
    this.textAlign = TextAlign.start,
    this.fontSize,
    this.fontWeight,
    this.minimumHeight,
    this.invalid = false,
    this.onChanged,
    this.onSubmitted,
    this.onKeyEvent,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String semanticLabel;
  final String? hintText;
  final String? errorText;
  final Widget? prefix;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextAlign textAlign;
  final double? fontSize;
  final FontWeight? fontWeight;
  final double? minimumHeight;
  final bool invalid;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusOnKeyEventCallback? onKeyEvent;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final denseLayout = spec.usesDenseSplitLayout;
    final standard = context.standardVisual;
    final controlFontSize = fontSize ?? spec.typography.body.fontSize ?? 14.0;
    final textScale =
        MediaQuery.textScalerOf(context).scale(controlFontSize) /
        controlFontSize;
    final enlargedText = textScale > 1.25;
    final naturalMinimumHeight = enlargedText ? 48.0 : 34.0;
    final resolvedMinimumHeight = minimumHeight == null
        ? naturalMinimumHeight
        : minimumHeight! > naturalMinimumHeight
        ? minimumHeight!
        : naturalMinimumHeight;
    final radius = spec.isStandard ? 6.0 : spec.geometry.fieldRadius;
    final enabledBorderColor = invalid
        ? spec.palette.danger
        : ledger || sakura
        ? spec.palette.trim.withAlpha(136)
        : StandardSpec.accentBrush(
            standard.accentHue,
            alpha: .32,
            neon: standard.neon,
          );
    final suffixGeometry = suffix == null && minimumHeight != null
        ? const SizedBox.shrink()
        : suffix;
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textAlign: textAlign,
      textAlignVertical: TextAlignVertical.center,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: spec.typography.body.copyWith(
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: denseLayout ? 1.15 : spec.typography.body.height,
        leadingDistribution: denseLayout
            ? TextLeadingDistribution.even
            : spec.typography.body.leadingDistribution,
      ),
      cursorColor: spec.palette.primaryBright,
      decoration: InputDecoration(
        // Dense InputDecorator lays the raw Georgia line against the top of a
        // taller desktop host. Let the normal single-line template be clamped
        // by the authored 38 px Ledger fields so TextAlignVertical.center can
        // place the visible baseline in the middle at every text scale.
        isDense: !denseLayout,
        hintText: hintText,
        hintStyle: spec.typography.body.copyWith(
          color: spec.palette.textMuted,
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: denseLayout ? 1.15 : spec.typography.body.height,
          leadingDistribution: denseLayout
              ? TextLeadingDistribution.even
              : spec.typography.body.leadingDistribution,
        ),
        errorText: errorText,
        errorStyle: spec.typography.meta.copyWith(color: spec.palette.danger),
        // Ledger's surrounding desktop layouts own the field height, so its
        // zero vertical inset lets TextAlignVertical.center place Georgia in
        // the authored hosts. Standard retains its established 11 px inset.
        contentPadding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: denseLayout ? 0 : 11,
        ),
        prefixIcon: prefix,
        prefixIconConstraints: BoxConstraints(
          minWidth: denseLayout ? 36 : 42,
          minHeight: 34,
        ),
        // An authored-height field without a visible suffix still needs a
        // zero-width geometry sentinel. Otherwise InputDecorator keeps its
        // painted container at the intrinsic 41 px while only the hit box
        // expands, recreating the lower lip the user reported.
        suffixIcon: suffixGeometry,
        // InputDecorator otherwise shrink-wraps its painted outline to the
        // 40 px text/suffix content even when the surrounding desktop control
        // is taller. Giving the target suffix the authored control height
        // makes the actual fill and border consume that full vertical area.
        suffixIconConstraints: BoxConstraints(
          minWidth: suffix == null ? 0 : 34,
          minHeight: minimumHeight ?? 34,
        ),
        filled: ledger || sakura,
        fillColor: ledger || sakura
            ? spec.palette.surfaceInset.withAlpha(218)
            : null,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: enabledBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(
            color: ledger || sakura
                ? invalid
                      ? spec.palette.danger
                      : spec.palette.primaryBright
                : invalid
                ? spec.palette.danger
                : StandardSpec.accentBrush(
                    standard.accentHue,
                    neon: standard.neon,
                  ),
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: spec.palette.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: spec.palette.danger, width: 1.5),
        ),
      ),
    );
    Widget result = Semantics(
      textField: true,
      label: semanticLabel,
      value: controller.text,
      child: onKeyEvent == null
          ? field
          : Focus(
              canRequestFocus: false,
              skipTraversal: true,
              includeSemantics: false,
              onKeyEvent: onKeyEvent,
              child: field,
            ),
    );
    if (spec.isStandard) {
      result = DecoratedBox(
        decoration: BoxDecoration(
          gradient: StandardSpec.accentGlass(
            standard.accentHue,
            topAlpha: 54,
            bottomAlpha: 18,
            neon: standard.neon,
          ),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: result,
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: resolvedMinimumHeight),
      child: result,
    );
  }
}

class PlannerToggle extends StatelessWidget {
  const PlannerToggle({
    required this.value,
    required this.label,
    required this.onChanged,
    required this.actionKey,
    super.key,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;
  final Key actionKey;

  static const Key standardMarkerKey = ValueKey<String>(
    'planner-toggle-standard-marker',
  );

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    if (sakura) {
      final markerBorder = value
          ? spec.palette.primaryBright
          : spec.palette.trim.withAlpha(168);
      return IntrinsicWidth(
        child: AppButton(
          key: actionKey,
          role: AppButtonRole.optionPill,
          selected: value,
          minimumSize: const Size(190, 40),
          padding: const EdgeInsets.fromLTRB(7, 2, 13, 2),
          semanticLabel: '$label, ${value ? 'on' : 'off'}',
          onPressed: () => onChanged(!value),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                key: standardMarkerKey,
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: value
                      ? SakuraNightGardenSpec.mossGradient
                      : SakuraNightGardenSpec.raisedSurfaceGradient,
                  border: Border.all(color: markerBorder),
                  shape: BoxShape.circle,
                  boxShadow: value ? spec.materials.lowShadow : null,
                ),
                alignment: Alignment.center,
                child: value
                    ? AppVectorGlyph(
                        'check',
                        size: 15,
                        color: spec.palette.text,
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  style: spec.typography.button.copyWith(
                    color: spec.palette.text,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (!ledger) {
      final standard = context.standardVisual;
      final markerBorder = StandardSpec.accentBrush(
        standard.accentHue,
        alpha: value ? .72 : .24,
        neon: standard.neon,
      );
      // AppButton normally fills a bounded horizontal offer. These two
      // command toggles live in a Wrap/Stack that can offer hundreds of spare
      // pixels, so measure them from their marker and label instead of turning
      // that spare space into an oversized pill.
      return IntrinsicWidth(
        child: AppButton(
          key: actionKey,
          role: AppButtonRole.optionPill,
          selected: value,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          semanticLabel: '$label, ${value ? 'on' : 'off'}',
          onPressed: () => onChanged(!value),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                key: standardMarkerKey,
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  gradient: StandardSpec.accentGlass(
                    standard.accentHue,
                    topAlpha: value ? 126 : 42,
                    bottomAlpha: value ? 46 : 12,
                    neon: standard.neon,
                  ),
                  border: Border.all(color: markerBorder),
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: value
                    ? const Icon(
                        Icons.check,
                        size: 12,
                        color: Color(0xFFF3EAE3),
                      )
                    : null,
              ),
              const SizedBox(width: 7),
              Text(
                label.toUpperCase(),
                style: spec.typography.button.copyWith(
                  color: spec.palette.text,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return AppButton(
      key: actionKey,
      role: AppButtonRole.optionPill,
      selected: value,
      minimumSize: const Size(190, 38),
      padding: const EdgeInsets.fromLTRB(4, 2, 13, 2),
      semanticLabel: '$label, ${value ? 'on' : 'off'}',
      onPressed: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox.square(
            dimension: 34,
            child: value
                ? CustomPaint(
                    painter: const LedgerWaxSealPainter(
                      enabled: true,
                      hovered: false,
                      pressed: false,
                      focused: false,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 17,
                      color: spec.palette.trimBright,
                    ),
                  )
                : Center(
                    child: Container(
                      width: 28,
                      height: 28,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        gradient: spec.materials.surfaceRaised,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: spec.palette.trim.withAlpha(42),
                          width: 1.2,
                        ),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: spec.palette.success.withAlpha(58),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontFamily: 'Georgia',
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PlannerPlanColumns extends StatefulWidget {
  const PlannerPlanColumns({
    required this.controller,
    required this.plan,
    required this.externalActions,
    required this.allowCompletion,
    required this.queueTitle,
    required this.needTitle,
    this.queueCountNoun = 'left',
    this.standardQueueFlex = 108,
    this.standardNeedFlex = 92,
    this.allowMarketActions = true,
    this.bonusPlan = false,
    this.scrollResetIdentity,
    this.completedPlan,
    this.actionKey,
    super.key,
  });

  final ModeFeatureController controller;
  final PlanResult plan;
  final PlanResult? completedPlan;
  final PlannerExternalActions externalActions;
  final bool allowCompletion;
  final String queueTitle;
  final String needTitle;
  final String queueCountNoun;
  final int standardQueueFlex;
  final int standardNeedFlex;
  final bool allowMarketActions;
  final bool bonusPlan;
  final Object? scrollResetIdentity;
  final Key? actionKey;

  @override
  State<PlannerPlanColumns> createState() => _PlannerPlanColumnsState();
}

class _PlannerPlanColumnsState extends State<PlannerPlanColumns> {
  final ScrollController _queueScroll = ScrollController();
  final ScrollController _needScroll = ScrollController();
  final NeedMaterialOrder _needMaterialOrder = NeedMaterialOrder();
  final Map<String, TextEditingController> _ownedDraftControllers =
      <String, TextEditingController>{};
  String? _openChoiceAnchor;
  String? _marketMessage;
  Map<String, List<PlannerMarketRowDiagnostic>> _marketRowDiagnostics =
      const <String, List<PlannerMarketRowDiagnostic>>{};
  bool _marketLoading = false;
  bool _adoptMarketOrderWhenReady = false;

  @override
  void didUpdateWidget(PlannerPlanColumns oldWidget) {
    super.didUpdateWidget(oldWidget);
    final targetChanged = !_sameFolded(
      oldWidget.plan.target,
      widget.plan.target,
    );
    final resetIdentityChanged =
        oldWidget.scrollResetIdentity != widget.scrollResetIdentity;
    if (!targetChanged && !resetIdentityChanged) return;

    _openChoiceAnchor = null;
    _needMaterialOrder.reset();
    _resetScroll(_queueScroll);
    _resetScroll(_needScroll);
  }

  void _resetScroll(ScrollController controller) {
    if (!controller.hasClients) return;
    controller.jumpTo(controller.position.minScrollExtent);
  }

  @override
  void dispose() {
    _queueScroll.dispose();
    _needScroll.dispose();
    for (final controller in _ownedDraftControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _ownedDraftController(String name) =>
      _ownedDraftControllers.putIfAbsent(
        name,
        () => TextEditingController(text: '0'),
      );

  List<PlanStep> get _visibleSteps {
    final completedPlan = widget.completedPlan;
    if (!widget.allowCompletion || completedPlan == null) {
      return widget.plan.steps;
    }
    final current = <String, PlanStep>{
      for (final step in widget.plan.steps) step.name.toLowerCase(): step,
    };
    return completedPlan.steps
        .map((step) => current[step.name.toLowerCase()])
        .whereType<PlanStep>()
        .toList(growable: false);
  }

  void _stageNeedSubstitute(MissingMaterial source, String selection) {
    _adoptMarketOrderWhenReady = false;
    _needMaterialOrder.stageSubstitute(source: source, selection: selection);
  }

  void _stageStepSubstitute(PlanStepIngredient source, String selection) {
    _adoptMarketOrderWhenReady = false;
    _needMaterialOrder.stageSubstituteChoice(
      parentName: source.parentName,
      original: source.original,
      substituteGroup: source.substituteGroup,
      sourceName: source.name,
      sourceBaseName: source.baseName,
      selection: selection,
    );
  }

  Future<void> _checkPrices() async {
    if (_marketLoading) return;
    setState(() {
      _adoptMarketOrderWhenReady = true;
      _marketLoading = true;
      _marketMessage = 'Checking current market data…';
      _marketRowDiagnostics =
          const <String, List<PlannerMarketRowDiagnostic>>{};
    });
    widget.controller.setPricesVisible(true);
    try {
      final result = await widget.externalActions.checkPrices(
        PlannerMarketRequest(
          controller: widget.controller,
          materials: widget.plan.missing,
        ),
      );
      widget.controller.replaceMarketValues(
        prices: result.prices,
        stock: result.stock,
        tradeMarketIds: result.tradeMarketIds,
        totalTrades: result.totalTrades,
        tradeObservedAt: result.tradeObservedAt,
        observedDailyTrades: result.observedDailyTrades,
        tradeObservationHours: result.tradeObservationHours,
        lastSoldAtEpochSeconds: result.lastSoldAtEpochSeconds,
        unlistedItemNames: result.unlistedItemNames,
        fetchedAt: result.fetchedAt,
        region: result.region,
      );
      if (!mounted) return;
      setState(() {
        if (_adoptMarketOrderWhenReady) _needMaterialOrder.reset();
        _adoptMarketOrderWhenReady = false;
        _marketMessage = result.summary;
        _marketRowDiagnostics = result.rowDiagnostics;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _adoptMarketOrderWhenReady = false;
        _marketMessage =
            'Market check failed. Cached values are still available. $error';
      });
    } finally {
      if (mounted) setState(() => _marketLoading = false);
    }
  }

  void _hidePrices() {
    widget.controller.setPricesVisible(false);
    setState(() => _marketMessage = null);
  }

  void _toggleStep(PlanStep step, int index) {
    final expanded = _stepExpanded(step, index);
    if (expanded &&
        index == 0 &&
        !_containsFolded(widget.controller.expandedSteps.value, step.name)) {
      setState(() => _openChoiceAnchor = 'collapsed:${step.name}');
      return;
    }
    if (_openChoiceAnchor == 'collapsed:${step.name}') {
      setState(() => _openChoiceAnchor = null);
      return;
    }
    widget.controller.toggleIngredients(step.name);
  }

  bool _stepExpanded(PlanStep step, int index) =>
      _containsFolded(widget.controller.expandedSteps.value, step.name) ||
      (index == 0 && _openChoiceAnchor != 'collapsed:${step.name}');

  @override
  Widget build(BuildContext context) {
    final orderedMissing = _needMaterialOrder.apply(widget.plan.missing);
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 760;
        final denseLayout = context.visualTheme.usesDenseSplitLayout;
        final queue = _QueuePanel(
          controller: widget.controller,
          plan: widget.plan,
          steps: _visibleSteps,
          externalActions: widget.externalActions,
          allowCompletion: widget.allowCompletion,
          bonusPlan: widget.bonusPlan,
          title: widget.queueTitle,
          countNoun: widget.queueCountNoun,
          scrollController: _queueScroll,
          openChoiceAnchor: _openChoiceAnchor,
          onSubstituteSelected: _stageStepSubstitute,
          onChoiceAnchorChanged: (value) =>
              setState(() => _openChoiceAnchor = value),
          isExpanded: _stepExpanded,
          onToggleExpanded: _toggleStep,
        );
        final need = ValueListenableBuilder<bool>(
          valueListenable: widget.controller.priceRowsVisible,
          builder: (context, showPrices, _) => _NeedPanel(
            controller: widget.controller,
            plan: widget.plan,
            materials: orderedMissing,
            externalActions: widget.externalActions,
            title: widget.needTitle,
            scrollController: _needScroll,
            ownedDraftController: _ownedDraftController,
            showPrices: showPrices,
            marketLoading: _marketLoading,
            marketMessage: _marketMessage,
            marketRowDiagnostics: _marketRowDiagnostics,
            allowMarketActions: widget.allowMarketActions,
            onCheckPrices: _checkPrices,
            onHidePrices: _hidePrices,
            openChoiceAnchor: _openChoiceAnchor,
            onSubstituteSelected: _stageNeedSubstitute,
            onChoiceAnchorChanged: (value) =>
                setState(() => _openChoiceAnchor = value),
          ),
        );
        if (horizontal) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                flex: denseLayout ? 96 : widget.standardQueueFlex,
                child: Padding(
                  padding: EdgeInsets.only(right: denseLayout ? 12 : 0),
                  child: queue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: denseLayout ? 104 : widget.standardNeedFlex,
                child: Padding(
                  padding: EdgeInsets.only(left: denseLayout ? 20 : 0),
                  child: need,
                ),
              ),
            ],
          );
        }
        return Column(
          children: <Widget>[
            Expanded(child: queue),
            const SizedBox(height: 12),
            Expanded(child: need),
          ],
        );
      },
    );
    return KeyedSubtree(key: widget.actionKey, child: content);
  }
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({
    required this.controller,
    required this.plan,
    required this.steps,
    required this.externalActions,
    required this.allowCompletion,
    required this.bonusPlan,
    required this.title,
    required this.countNoun,
    required this.scrollController,
    required this.openChoiceAnchor,
    required this.onSubstituteSelected,
    required this.onChoiceAnchorChanged,
    required this.isExpanded,
    required this.onToggleExpanded,
  });

  final ModeFeatureController controller;
  final PlanResult plan;
  final List<PlanStep> steps;
  final PlannerExternalActions externalActions;
  final bool allowCompletion;
  final bool bonusPlan;
  final String title;
  final String countNoun;
  final ScrollController scrollController;
  final String? openChoiceAnchor;
  final void Function(PlanStepIngredient source, String selection)
  onSubstituteSelected;
  final ValueChanged<String?> onChoiceAnchorChanged;
  final bool Function(PlanStep step, int index) isExpanded;
  final void Function(PlanStep step, int index) onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final denseLayout = spec.usesDenseSplitLayout;
    final trailing = allowCompletion
        ? AppButton.label(
            'Restart queue',
            key: PlannerActionKeys.p07,
            role: ledger ? AppButtonRole.primary : AppButtonRole.secondary,
            minimumSize: Size(denseLayout ? 76 : 66, 38),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            semanticLabel: 'Restart queue and clear all completed-step marks',
            tooltip: 'Show the full queue again without changing owned items',
            onPressed: controller.resetCompleted,
          )
        : null;
    final queueList = NotificationListener<ScrollStartNotification>(
      onNotification: (_) {
        AppOverlayCoordinatorScope.maybeOf(context)?.dismissTop();
        return false;
      },
      child: ListView.builder(
        key: const PageStorageKey<String>('planner-craft-queue'),
        controller: scrollController,
        itemCount: steps.length,
        itemBuilder: (context, index) {
          final step = steps[index];
          final completed = _containsFolded(
            controller.state.value.completedSteps,
            step.name,
          );
          return Padding(
            key: ValueKey<String>('queue:${step.name}'),
            padding: EdgeInsets.only(
              bottom: index + 1 < steps.length ? (denseLayout ? 8 : 14) : 0,
              right: denseLayout ? 8 : 0,
            ),
            child: _QueueStepCard(
              controller: controller,
              step: step,
              titleSubstituteSources: _incomingSubstituteSources(
                plan,
                step.name,
              ),
              index: index,
              completed: completed,
              expanded: isExpanded(step, index),
              allowCompletion: allowCompletion,
              sessionTargetName: plan.target,
              sessionTargetAmount: plan.want,
              bonusPlan: bonusPlan,
              externalActions: externalActions,
              openChoiceAnchor: openChoiceAnchor,
              onSubstituteSelected: onSubstituteSelected,
              onChoiceAnchorChanged: onChoiceAnchorChanged,
              onToggleExpanded: () => onToggleExpanded(step, index),
            ),
          );
        },
      ),
    );
    final queueListWithoutPlatformScrollbar = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: queueList,
    );
    return AppSurface(
      role: AppSurfaceRole.layout,
      semanticLabel: title,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: title,
            meta: '${plan.steps.length} $countNoun',
            trailing: trailing,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: steps.isEmpty
                ? const _PlannerEmpty(
                    message:
                        'No craft steps are needed for the current target and inventory.',
                  )
                : queueListWithoutPlatformScrollbar,
          ),
        ],
      ),
    );
  }
}

class _QueueStepCard extends StatelessWidget {
  const _QueueStepCard({
    required this.controller,
    required this.step,
    required this.titleSubstituteSources,
    required this.index,
    required this.completed,
    required this.expanded,
    required this.allowCompletion,
    required this.sessionTargetName,
    required this.sessionTargetAmount,
    required this.bonusPlan,
    required this.externalActions,
    required this.openChoiceAnchor,
    required this.onSubstituteSelected,
    required this.onChoiceAnchorChanged,
    required this.onToggleExpanded,
  });

  final ModeFeatureController controller;
  final PlanStep step;
  final List<PlanStepIngredient> titleSubstituteSources;
  final int index;
  final bool completed;
  final bool expanded;
  final bool allowCompletion;
  final String sessionTargetName;
  final int sessionTargetAmount;
  final bool bonusPlan;
  final PlannerExternalActions externalActions;
  final String? openChoiceAnchor;
  final void Function(PlanStepIngredient source, String selection)
  onSubstituteSelected;
  final ValueChanged<String?> onChoiceAnchorChanged;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final denseLayout = spec.usesDenseSplitLayout;
    final recipe = _resolveRecipe(controller, step.name);
    final titleChoices = <({PlanStepIngredient source, Ingredient ingredient})>[
      for (final source in titleSubstituteSources)
        if (_resolveIngredient(
              controller,
              source.parentName,
              source.original,
              source.substituteGroup,
            )
            case final ingredient?)
          (source: source, ingredient: ingredient),
    ];
    final primaryTitleChoice = titleChoices.isEmpty ? null : titleChoices.first;
    final titleAnchor = titleChoices.isEmpty
        ? null
        : 'queue-title:${step.name}';
    final titleChooserOpen =
        titleAnchor != null && openChoiceAnchor == titleAnchor;
    final hasVariants = recipe?.hasRecipeVariants ?? false;
    final summary = step.batchSize > 1
        ? 'Craft ${formatQuantity(step.count)} | '
              'Mass batches ${formatQuantity(step.batchCount)} x${step.batchSize} | '
              'Results in ${formatQuantity(step.produced)} | '
              'Need ${formatQuantity(step.demand)}'
        : 'Craft ${formatQuantity(step.count)} | '
              'Results in ${formatQuantity(step.produced)} | '
              'Need ${formatQuantity(step.demand)}';
    return AppSurface(
      role: AppSurfaceRole.card,
      ornamentIndex: index,
      tone: completed
          ? AppSurfaceTone.success
          : step.ingredients.any((ingredient) => ingredient.missing > 0)
          ? AppSurfaceTone.warning
          : AppSurfaceTone.neutral,
      semanticLabel: '${step.name} craft step${completed ? ', completed' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: denseLayout ? 84 : 88),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: denseLayout ? 52 : 58,
                  child: Align(
                    alignment: Alignment.center,
                    child: PlannerItemIcon(
                      controller: controller,
                      name: step.name,
                      size: denseLayout ? 48 : 54,
                    ),
                  ),
                ),
                SizedBox(width: denseLayout ? 9 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (primaryTitleChoice != null)
                        _SubstituteNameAnchor(
                          key: PlannerActionKeys.row('P12', titleAnchor!),
                          nameKey: PlannerActionKeys.row('P10', step.name),
                          name: step.name,
                          currentName: primaryTitleChoice.source.baseName,
                          ingredient: primaryTitleChoice.ingredient,
                          fontSize: denseLayout ? 18 : 19,
                          isShowing: titleChooserOpen,
                          semanticLabel: titleChoices.length > 1
                              ? 'Choose recipe substitutions affecting '
                                    '${step.name}; ${titleChoices.length} '
                                    'choices; '
                                    '${titleChooserOpen ? 'open' : 'closed'}'
                              : null,
                          tooltip: titleChoices.length > 1
                              ? 'More than one recipe choice contributes to '
                                    '${step.name}. Click to choose which one '
                                    'to change.'
                              : null,
                          onToggle: () => onChoiceAnchorChanged(
                            titleChooserOpen ? null : titleAnchor,
                          ),
                        )
                      else
                        _CopyNameButton(
                          key: PlannerActionKeys.row('P10', step.name),
                          name: step.name,
                          fontSize: denseLayout ? 18 : 19,
                          semanticPrefix: 'Copy queue item',
                          onCopy: externalActions.copyName,
                        ),
                      SizedBox(height: denseLayout ? 8 : 10),
                      _MethodPill(recipe: recipe),
                      if (hasVariants) ...<Widget>[
                        SizedBox(height: denseLayout ? 12 : 14),
                        RecipeVariantSelector(
                          recipe: recipe!,
                          selectedVariantId: controller.selectedRecipeVariantId(
                            step.name,
                          ),
                          compact: denseLayout,
                          axisSpacing: denseLayout ? 13 : 16,
                          onSelected: (variantId) =>
                              controller.selectRecipeVariant(
                                recipeName: step.name,
                                variantId: variantId,
                              ),
                        ),
                      ],
                      SizedBox(height: denseLayout ? 10 : 12),
                      Text(
                        summary,
                        key: ValueKey<String>(
                          'planner-step-summary:${step.name}',
                        ),
                        style: spec.typography.meta.copyWith(
                          color: denseLayout
                              ? spec.palette.textMuted
                              : const Color(0xFFC0D5CE),
                          fontSize: denseLayout ? 13 : 14,
                          fontWeight: FontWeight.w600,
                          fontStyle: denseLayout ? FontStyle.normal : null,
                          height: denseLayout ? 1.15 : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (allowCompletion) ...<Widget>[
                  const SizedBox(width: 8),
                  AppCompletionControl(
                    key: PlannerActionKeys.row('P08', step.name),
                    completed: completed,
                    semanticLabel: completed
                        ? 'Undo Done for ${step.name}'
                        : 'Done with ${step.name}',
                    onPressed: () => controller.toggleCompleted(step.name),
                  ),
                ],
              ],
            ),
          ),
          if (titleChooserOpen && titleChoices.isNotEmpty) ...<Widget>[
            SizedBox(height: denseLayout ? 5 : 7),
            Padding(
              padding: EdgeInsets.only(left: denseLayout ? 61 : 70),
              child: _QueueTitleSubstituteChooser(
                controller: controller,
                stepName: step.name,
                choices: titleChoices,
                onSubstituteSelected: onSubstituteSelected,
                onClose: () => onChoiceAnchorChanged(null),
              ),
            ),
          ],
          SizedBox(height: denseLayout ? 13 : 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final showAfkLabel =
                  constraints.maxWidth >= 330 &&
                  MediaQuery.textScalerOf(context).scale(1) <= 1.3;
              return Row(
                children: <Widget>[
                  Flexible(
                    child: _IngredientToggle(
                      key: PlannerActionKeys.row('P09', step.name),
                      expanded: expanded,
                      onPressed: onToggleExpanded,
                    ),
                  ),
                  if (recipe != null) ...<Widget>[
                    const SizedBox(width: 12),
                    _AfkLoadPopover(
                      controller: controller,
                      step: step,
                      recipe: recipe,
                      sessionTargetName: sessionTargetName,
                      sessionTargetAmount: sessionTargetAmount,
                      bonusPlan: bonusPlan,
                      externalActions: externalActions,
                      showLabel: showAfkLabel,
                    ),
                  ],
                ],
              );
            },
          ),
          AppRevealTransition(
            key: ValueKey<String>('planner-ingredient-reveal:${step.name}'),
            visible: expanded,
            expandVertically: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(height: denseLayout ? 13 : 16),
                for (
                  var ingredientIndex = 0;
                  ingredientIndex < step.ingredients.length;
                  ingredientIndex += 1
                )
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: ingredientIndex == step.ingredients.length - 1
                          ? 0
                          : denseLayout
                          ? 6
                          : 8,
                    ),
                    child: _IngredientRow(
                      controller: controller,
                      ingredient: step.ingredients[ingredientIndex],
                      externalActions: externalActions,
                      openChoiceAnchor: openChoiceAnchor,
                      onSubstituteSelected: onSubstituteSelected,
                      onChoiceAnchorChanged: onChoiceAnchorChanged,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IngredientToggle extends StatelessWidget {
  const _IngredientToggle({
    required this.expanded,
    required this.onPressed,
    super.key,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final denseLayout = spec.usesDenseSplitLayout;
    final preferredWidth = denseLayout ? 156.0 : 188.0;
    final height = denseLayout ? 36.0 : 38.0;
    return SizedBox(
      width: preferredWidth,
      height: height,
      child: AppButton(
        role: AppButtonRole.ingredientToggle,
        minimumSize: Size(0, height),
        padding: EdgeInsets.symmetric(
          horizontal: denseLayout ? 8 : 13,
          vertical: denseLayout ? 5 : 8,
        ),
        semanticLabel: expanded ? 'Hide Ingredients' : 'Show Ingredients',
        onPressed: onPressed,
        child: Row(
          children: <Widget>[
            Text(
              expanded ? '-' : '+',
              style: ledger ? _ledgerIngredientToggleTextStyle : null,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                expanded ? 'Hide Ingredients' : 'Show Ingredients',
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: ledger ? _ledgerIngredientToggleTextStyle : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AfkLoadPopover extends StatelessWidget {
  const _AfkLoadPopover({
    required this.controller,
    required this.step,
    required this.recipe,
    required this.sessionTargetName,
    required this.sessionTargetAmount,
    required this.bonusPlan,
    required this.externalActions,
    required this.showLabel,
  });

  final ModeFeatureController controller;
  final PlanStep step;
  final Recipe recipe;
  final String sessionTargetName;
  final int sessionTargetAmount;
  final bool bonusPlan;
  final PlannerExternalActions externalActions;
  final bool showLabel;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AfkWeightProfile>(
        valueListenable: controller.owner.afkWeightProfile,
        builder: (context, profile, _) {
          final denseLayout = context.visualTheme.usesDenseSplitLayout;
          final height = denseLayout ? 36.0 : 38.0;
          return AnchoredPopover(
            overlayId: 'afk-load:${controller.mode.key}:${step.name}',
            preferredWidth: 452,
            maximumHeight: 540,
            margin: 22,
            gap: 12,
            placement: AnchoredPopoverPlacement.beside,
            consumeOutsideTap: true,
            popoverBuilder: (context, close) => _AfkLoadCard(
              controller: controller,
              step: step,
              recipe: recipe,
              profile: profile,
              sessionTargetName: sessionTargetName,
              sessionTargetAmount: sessionTargetAmount,
              bonusPlan: bonusPlan,
              externalActions: externalActions,
              onClose: close,
            ),
            anchorBuilder: (context, toggle, isShowing) => SizedBox(
              width: showLabel ? null : height,
              height: height,
              child: AppButton(
                key: ValueKey<String>(
                  'planner-afk-load:${controller.mode.key}:${step.name}',
                ),
                role: AppButtonRole.secondary,
                selected: isShowing,
                minimumSize: Size(0, height),
                padding: showLabel
                    ? EdgeInsets.symmetric(
                        horizontal: denseLayout ? 10 : 12,
                        vertical: 5,
                      )
                    : EdgeInsets.zero,
                semanticLabel:
                    'AFK Load for ${step.name}, '
                    '${isShowing ? 'open' : 'closed'}',
                tooltip: 'Plan-aware AFK ingredient loads',
                onPressed: toggle,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.scale_outlined,
                      size: 17,
                      color: profile.isConfigured
                          ? null
                          : context.visualTheme.palette.warning,
                    ),
                    if (showLabel) ...<Widget>[
                      const SizedBox(width: 6),
                      const Text(
                        'AFK Load',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                    if (!profile.isConfigured && showLabel) ...<Widget>[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.brightness_1,
                        size: 6,
                        color: context.visualTheme.palette.warning,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
}

enum _AfkLoadMode { needed, maximum }

class _AfkLoadCard extends StatefulWidget {
  const _AfkLoadCard({
    required this.controller,
    required this.step,
    required this.recipe,
    required this.profile,
    required this.sessionTargetName,
    required this.sessionTargetAmount,
    required this.bonusPlan,
    required this.externalActions,
    required this.onClose,
  });

  final ModeFeatureController controller;
  final PlanStep step;
  final Recipe recipe;
  final AfkWeightProfile profile;
  final String sessionTargetName;
  final int sessionTargetAmount;
  final bool bonusPlan;
  final PlannerExternalActions externalActions;
  final VoidCallback onClose;

  @override
  State<_AfkLoadCard> createState() => _AfkLoadCardState();
}

class _AfkLoadCardState extends State<_AfkLoadCard> {
  _AfkLoadMode _mode = _AfkLoadMode.needed;

  ModeFeatureController get controller => widget.controller;
  PlanStep get step => widget.step;
  Recipe get recipe => widget.recipe;
  AfkWeightProfile get profile => widget.profile;
  PlannerExternalActions get externalActions => widget.externalActions;
  VoidCallback get onClose => widget.onClose;

  String get _progressKey => AfkCraftProgress.sessionKeyFor(
    targetName: widget.sessionTargetName,
    recipeName: recipe.name,
    bonus: widget.bonusPlan,
  );

  String get _planSignature {
    final attemptCount = step.count <= 0 ? 1.0 : step.count;
    return <String>[
      recipe.name.trim(),
      controller.selectedRecipeVariantId(recipe.name) ?? '',
      recipe.type.trim(),
      recipe.method?.trim() ?? '',
      recipe.baseOutput.toStringAsFixed(8),
      recipe.outputMinimum?.toStringAsFixed(8) ?? '',
      recipe.outputMaximum?.toStringAsFixed(8) ?? '',
      step.batchSize.toString(),
      for (final ingredient in step.ingredients)
        <String>[
          ingredient.key,
          ingredient.name,
          ingredient.baseName,
          ingredient.grade,
          (ingredient.need / attemptCount).toStringAsFixed(8),
        ].join(':'),
    ].join('|');
  }

  AfkWeightSessionPlan _calculate({required int completedAttempts}) =>
      const AfkWeightCalculator().calculateSessionPlan(
        mode: controller.mode,
        step: step,
        recipe: recipe,
        rules: controller.owner.plannerRules,
        profile: profile,
        completedAttempts: completedAttempts,
      );

  ModeState _reconcile(ModeState state, AfkWeightSessionPlan session) =>
      state.reconcileAfkCraftProgress(
        targetName: widget.sessionTargetName,
        targetAmount: widget.sessionTargetAmount,
        recipeName: recipe.name,
        planSignature: _planSignature,
        totalAttempts: session.requestedAttempts,
        attemptsPerRound: session.maxAttemptsPerLoad,
        progressKey: _progressKey,
      );

  void _completeLoad(AfkWeightSessionLoad load) {
    controller.updateState((state) {
      final session = _calculate(completedAttempts: 0);
      return _reconcile(state, session).completeAfkCraftThrough(
        recipe.name,
        load.completedAttemptsAfter,
        progressKey: _progressKey,
      );
    }, immediate: true);
  }

  void _undoLoad() {
    controller.updateState((state) {
      final session = _calculate(completedAttempts: 0);
      return _reconcile(
        state,
        session,
      ).undoLastAfkCraftRound(recipe.name, progressKey: _progressKey);
    }, immediate: true);
  }

  void _resetProgress() {
    controller.updateState((state) {
      final session = _calculate(completedAttempts: 0);
      return _reconcile(
        state,
        session,
      ).resetAfkCraftProgress(recipe.name, progressKey: _progressKey);
    }, immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      role: AppSurfaceRole.popup,
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      semanticLabel: 'AFK Load plan for ${recipe.name}',
      child: ValueListenableBuilder<ModeState>(
        valueListenable: controller.state,
        builder: (context, state, _) {
          final initialSession = _calculate(completedAttempts: 0);
          final reconciled = _reconcile(state, initialSession);
          final progress = reconciled.afkCraftProgressFor(
            recipe.name,
            progressKey: _progressKey,
          );
          final session = _calculate(
            completedAttempts: progress?.completedAttempts ?? 0,
          );
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _header(context),
                const SizedBox(height: 12),
                if (!profile.isConfigured)
                  _unconfigured(context)
                else if (!session.maximumCapacity.available ||
                    session.maxAttemptsPerLoad <= 0)
                  _unavailable(context, session.maximumCapacity)
                else ...<Widget>[
                  _modeSelector(),
                  const SizedBox(height: 14),
                  if (_mode == _AfkLoadMode.needed)
                    _needed(context, session, progress)
                  else
                    _recommendation(context, session.maximumCapacity),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context) {
    final spec = context.visualTheme;
    return Row(
      children: <Widget>[
        Expanded(
          child: AnchoredPopoverDragRegion(
            key: const ValueKey<String>('planner-afk-drag-region'),
            child: Row(
              children: <Widget>[
                PlannerItemIcon(
                  controller: controller,
                  name: recipe.name,
                  size: 38,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'AFK LOAD',
                        style: spec.typography.meta.copyWith(
                          color: spec.palette.primaryBright,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .35,
                        ),
                      ),
                      Text(
                        recipe.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: spec.typography.body.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        AppButton.icon(
          key: const ValueKey<String>('planner-afk-edit-profile'),
          icon: const Icon(Icons.tune_rounded, size: 18),
          tooltip: 'Edit weight settings',
          semanticLabel: 'Edit AFK weight settings',
          onPressed: externalActions.openAfkWeightSettings == null
              ? null
              : () {
                  onClose();
                  externalActions.openAfkWeightSettings!();
                },
        ),
        const SizedBox(width: 5),
        _SourceInfoCloseButton(
          semanticLabel: 'Close AFK Load for ${recipe.name}',
          onPressed: onClose,
        ),
      ],
    );
  }

  Map<String, double> _perAttemptQuantities() {
    final quantities = <String, double>{};
    final fallbackDivisor = step.count.isFinite && step.count > 0
        ? step.count
        : 1.0;
    for (final planned in step.ingredients) {
      final source = _resolveIngredient(
        controller,
        planned.parentName,
        planned.original,
        planned.substituteGroup,
      );
      final preview = source == null
          ? null
          : controller.previewIngredientSelection(
              parentName: planned.parentName,
              ingredient: source,
            );
      final name = (preview?.name ?? planned.name).trim();
      final quantity = preview?.need ?? planned.need / fallbackDivisor;
      if (name.isEmpty || !quantity.isFinite || quantity <= 0) continue;
      quantities.update(
        name.toLowerCase(),
        (current) => current + quantity,
        ifAbsent: () => quantity,
      );
    }
    return quantities;
  }

  double _perAttemptFor(AfkLoadStack stack, Map<String, double> quantities) =>
      quantities[stack.itemName.trim().toLowerCase()] ??
      stack.perAttemptQuantity;

  Widget _afkIngredientRow(
    BuildContext context,
    AfkLoadStack stack,
    Map<String, double> quantities,
  ) {
    final spec = context.visualTheme;
    final perAttempt = _perAttemptFor(stack, quantities);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 30,
            child: PlannerItemIcon(
              controller: controller,
              name: stack.itemName,
              size: 27,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              stack.itemName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: spec.typography.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 84,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${formatQuantity(perAttempt)} / attempt',
                key: ValueKey<String>(
                  'planner-afk-per-attempt:${stack.itemName}',
                ),
                style: spec.typography.meta.copyWith(
                  color: spec.palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${formatQuantity(stack.quantity.toDouble())} x',
            key: ValueKey<String>('planner-afk-total:${stack.itemName}'),
            style: spec.typography.body.copyWith(
              color: spec.palette.primaryBright,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 58,
            child: Text(
              '${formatQuantity(stack.loadLt)} LT',
              textAlign: TextAlign.right,
              style: spec.typography.meta.copyWith(
                color: spec.palette.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeSelector() => Row(
    children: <Widget>[
      Expanded(
        child: AppButton.label(
          'Needed',
          key: const ValueKey<String>('planner-afk-mode-needed'),
          selected: _mode == _AfkLoadMode.needed,
          minimumSize: const Size(0, 36),
          tooltip: 'Load only what the current Planner target still needs',
          onPressed: () => setState(() => _mode = _AfkLoadMode.needed),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: AppButton.label(
          'Maximum',
          key: const ValueKey<String>('planner-afk-mode-maximum'),
          selected: _mode == _AfkLoadMode.maximum,
          minimumSize: const Size(0, 36),
          tooltip: 'Fill safe capacity for leveling or recipe spam',
          onPressed: () => setState(() => _mode = _AfkLoadMode.maximum),
        ),
      ),
    ],
  );

  Widget _unconfigured(BuildContext context) {
    final spec = context.visualTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Set your character weight once in Craft Profile. Every queue recipe will '
          'then calculate its own safe AFK load.',
          style: spec.typography.body.copyWith(
            color: spec.palette.textMuted,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        AppButton.label(
          'Open weight settings',
          key: const ValueKey<String>('planner-afk-open-settings'),
          role: AppButtonRole.primary,
          minimumSize: const Size(0, 40),
          onPressed: externalActions.openAfkWeightSettings == null
              ? null
              : () {
                  onClose();
                  externalActions.openAfkWeightSettings!();
                },
        ),
      ],
    );
  }

  Widget _unavailable(BuildContext context, AfkWeightCalculation result) {
    final spec = context.visualTheme;
    final missing = result.missingWeightItems;
    final capacityUnavailable = result.warnings.contains(
      AfkWeightWarning.noUsableCapacity,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          capacityUnavailable
              ? 'There is no safe capacity left after your carried weight and buffer.'
              : missing.isNotEmpty
              ? 'A safe load cannot be calculated because exact weight data is missing for ${missing.join(', ')}.'
              : 'This queue step does not contain a usable recipe amount.',
          style: spec.typography.body.copyWith(
            color: spec.palette.warning,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        AppButton.label(
          'Edit weight settings',
          key: const ValueKey<String>('planner-afk-edit-settings'),
          minimumSize: const Size(0, 40),
          onPressed: externalActions.openAfkWeightSettings == null
              ? null
              : () {
                  onClose();
                  externalActions.openAfkWeightSettings!();
                },
        ),
      ],
    );
  }

  Widget _needed(
    BuildContext context,
    AfkWeightSessionPlan session,
    AfkCraftProgress? progress,
  ) {
    final spec = context.visualTheme;
    final completed = progress?.completedAttempts ?? 0;
    final total = session.requestedAttempts;
    final totalRounds = session.maxAttemptsPerLoad <= 0
        ? 0
        : (total + session.maxAttemptsPerLoad - 1) ~/
              session.maxAttemptsPerLoad;

    if (session.complete) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Icon(Icons.task_alt_rounded, size: 34, color: spec.palette.success),
          const SizedBox(height: 8),
          Text(
            'Plan finished',
            textAlign: TextAlign.center,
            style: spec.typography.section.copyWith(
              color: spec.palette.success,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$total recipe attempts checked off for '
            '${formatQuantity(widget.sessionTargetAmount.toDouble())} '
            '${widget.sessionTargetName}',
            textAlign: TextAlign.center,
            style: spec.typography.meta.copyWith(color: spec.palette.textMuted),
          ),
          const SizedBox(height: 12),
          _AfkSessionProgress(completed: total, total: total),
          const SizedBox(height: 13),
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton.label(
                  'Undo last round',
                  key: const ValueKey<String>('planner-afk-undo-round'),
                  minimumSize: const Size(0, 40),
                  onPressed: completed > 0 ? _undoLoad : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton.label(
                  'Start over',
                  key: const ValueKey<String>('planner-afk-reset-progress'),
                  minimumSize: const Size(0, 40),
                  onPressed: completed > 0 ? _resetProgress : null,
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (session.loadCount == 0) {
      return _unavailable(context, session.maximumCapacity);
    }

    final load = session.loadAt(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'For ${formatQuantity(widget.sessionTargetAmount.toDouble())} '
          '${widget.sessionTargetName}',
          key: const ValueKey<String>('planner-afk-goal-label'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: spec.typography.meta.copyWith(
            color: spec.palette.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Round ${load.number} of $totalRounds',
                    key: const ValueKey<String>('planner-afk-round-label'),
                    style: spec.typography.meta.copyWith(
                      color: spec.palette.primaryBright,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${formatQuantity(load.attempts.toDouble())} attempts',
                    key: const ValueKey<String>('planner-afk-needed-attempts'),
                    style: spec.typography.display.copyWith(
                      color: spec.palette.success,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${formatQuantity(completed.toDouble())} / '
              '${formatQuantity(total.toDouble())} done',
              style: spec.typography.meta.copyWith(
                color: spec.palette.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (load.massBatches > 0) ...<Widget>[
          const SizedBox(height: 3),
          Text(
            '${formatQuantity(load.massBatches.toDouble())} mass cycles '
            'at x${step.batchSize}',
            style: spec.typography.meta.copyWith(color: spec.palette.textMuted),
          ),
        ],
        const SizedBox(height: 8),
        _AfkSessionProgress(completed: completed, total: total),
        const SizedBox(height: 13),
        _ingredientList(context, load.ingredientStacks),
        const SizedBox(height: 8),
        _loadStats(
          start: profile.currentCarriedWeightLt + load.startLoadLt,
          finish: profile.currentCarriedWeightLt + load.finishLoadLt,
          safeStop: session.maximumCapacity.stopWeightLt,
        ),
        if (!load.isFinal) ...<Widget>[
          const SizedBox(height: 9),
          Text(
            'Unload the crafted output before starting the next round.',
            style: spec.typography.meta.copyWith(
              color: spec.palette.textMuted,
              height: 1.3,
            ),
          ),
        ],
        const SizedBox(height: 13),
        AppButton.label(
          'Mark round done',
          key: const ValueKey<String>('planner-afk-complete-round'),
          role: AppButtonRole.primary,
          minimumSize: const Size(0, 42),
          onPressed: () => _completeLoad(load),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: AppButton.label(
                'Copy this round',
                key: const ValueKey<String>('planner-afk-copy-load'),
                minimumSize: const Size(0, 38),
                onPressed: externalActions.copyAfkLoad == null
                    ? null
                    : () => externalActions.copyAfkLoad!(
                        _copyNeededText(
                          session,
                          load,
                          recipe,
                          step,
                          totalRounds: totalRounds,
                          targetName: widget.sessionTargetName,
                          targetAmount: widget.sessionTargetAmount,
                        ),
                      ),
              ),
            ),
            if (completed > 0) ...<Widget>[
              const SizedBox(width: 8),
              AppButton.icon(
                key: const ValueKey<String>('planner-afk-undo-round'),
                icon: const Icon(Icons.undo_rounded, size: 18),
                tooltip: 'Undo last completed round',
                semanticLabel: 'Undo last completed AFK round',
                onPressed: _undoLoad,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _ingredientList(BuildContext context, Iterable<AfkLoadStack> stacks) {
    final spec = context.visualTheme;
    final perAttemptQuantities = _perAttemptQuantities();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'LOAD THESE INGREDIENTS',
          style: spec.typography.label.copyWith(
            color: spec.palette.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: .45,
          ),
        ),
        const SizedBox(height: 6),
        for (final stack in stacks)
          _afkIngredientRow(context, stack, perAttemptQuantities),
      ],
    );
  }

  Widget _loadStats({
    required double start,
    required double finish,
    required double safeStop,
  }) => Row(
    children: <Widget>[
      Expanded(
        child: _AfkLoadStat(
          label: 'Start',
          value: '${formatQuantity(start)} LT',
        ),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: _AfkLoadStat(
          label: 'Finish',
          value: '${formatQuantity(finish)} LT',
        ),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: _AfkLoadStat(
          label: 'Safe stop',
          value: '${formatQuantity(safeStop)} LT',
        ),
      ),
    ],
  );

  Widget _recommendation(BuildContext context, AfkWeightCalculation result) {
    final spec = context.visualTheme;
    final perAttemptQuantities = _perAttemptQuantities();
    final massProcessing = result.safeMassBatches > 0;
    final headline = massProcessing
        ? '${formatQuantity(result.safeMassBatches.toDouble())} mass cycles'
        : '${formatQuantity(result.safeAttempts.toDouble())} attempts';
    final subline = massProcessing
        ? '${formatQuantity(result.safeAttempts.toDouble())} recipe attempts '
              'at x${step.batchSize}'
        : 'maximum safe recipe attempts';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          headline,
          key: const ValueKey<String>('planner-afk-safe-attempts'),
          style: spec.typography.display.copyWith(
            color: result.safeAttempts > 0
                ? spec.palette.success
                : spec.palette.warning,
            fontSize: 25,
            fontWeight: FontWeight.w800,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subline,
          style: spec.typography.meta.copyWith(
            color: spec.palette.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          'Capacity mode ignores the current Planner target. Use it for '
          'leveling, recipe spam, or consuming as many ingredients as possible.',
          style: spec.typography.meta.copyWith(
            color: spec.palette.textMuted,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 13),
        Text(
          'LOAD THESE INGREDIENTS',
          style: spec.typography.label.copyWith(
            color: spec.palette.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: .45,
          ),
        ),
        const SizedBox(height: 6),
        for (final stack in result.ingredientStacks)
          _afkIngredientRow(context, stack, perAttemptQuantities),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _AfkLoadStat(
                label: 'Start',
                value: '${formatQuantity(result.startingTotalLt)} LT',
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: _AfkLoadStat(
                label: 'Finish',
                value: '${formatQuantity(result.finishingTotalLt)} LT',
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: _AfkLoadStat(
                label: 'Safe stop',
                value: '${formatQuantity(result.stopWeightLt)} LT',
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          _confidenceText(result),
          style: spec.typography.meta.copyWith(
            color: result.isIncomplete
                ? spec.palette.warning
                : spec.palette.textMuted,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 13),
        Row(
          children: <Widget>[
            Expanded(
              child: AppButton.label(
                'Copy maximum load',
                key: const ValueKey<String>('planner-afk-copy-load'),
                role: AppButtonRole.primary,
                minimumSize: const Size(0, 40),
                onPressed:
                    result.safeAttempts <= 0 ||
                        externalActions.copyAfkLoad == null
                    ? null
                    : () => externalActions.copyAfkLoad!(
                        _copyMaximumText(result, recipe, step),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AfkSessionProgress extends StatelessWidget {
  const _AfkSessionProgress({required this.completed, required this.total});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = context.visualTheme.palette;
    final fraction = total <= 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);
    return Semantics(
      label: '$completed of $total recipe attempts complete',
      child: SizedBox(
        height: 6,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: ColoredBox(
            color: palette.trim.withAlpha(72),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction,
                heightFactor: 1,
                child: ColoredBox(color: palette.success),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AfkLoadStat extends StatelessWidget {
  const _AfkLoadStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return AppSurface(
      role: AppSurfaceRole.row,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            style: spec.typography.meta.copyWith(
              color: spec.palette.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: spec.typography.body.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String _confidenceText(AfkWeightCalculation result) {
  final parts = <String>[];
  if (result.confidence == AfkWeightConfidence.modelled) {
    parts.add('The main output uses a conservative recorded-data fallback.');
  } else {
    parts.add('The main output uses its recorded maximum.');
  }
  if (result.warnings.contains(AfkWeightWarning.byproductsUnmodelled)) {
    parts.add(
      'Byproducts are not included, so keep a larger buffer for recipes that create them.',
    );
  }
  return parts.join(' ');
}

String _copyNeededText(
  AfkWeightSessionPlan session,
  AfkWeightSessionLoad load,
  Recipe recipe,
  PlanStep step, {
  required int totalRounds,
  required String targetName,
  required int targetAmount,
}) {
  final start =
      session.maximumCapacity.currentCarriedWeightLt + load.startLoadLt;
  final finish =
      session.maximumCapacity.currentCarriedWeightLt + load.finishLoadLt;
  final lines = <String>[
    'AFK Load - ${recipe.name}',
    'Planner goal: $targetAmount x $targetName',
    'This recipe: ${session.requestedAttempts} attempts',
    'Round ${load.number} of $totalRounds: ${load.attempts} attempts',
    'Progress after this round: ${load.completedAttemptsAfter} / '
        '${session.requestedAttempts} attempts',
    if (load.massBatches > 0)
      'Mass cycles: ${load.massBatches} x ${step.batchSize}',
    '',
    'Load:',
    for (final stack in load.ingredientStacks)
      '- ${stack.quantity} x ${stack.itemName} '
          '(${formatQuantity(stack.loadLt)} LT)',
    '',
    'Start: ${formatQuantity(start)} LT',
    'Finish: ${formatQuantity(finish)} LT',
    'Safe stop: ${formatQuantity(session.maximumCapacity.stopWeightLt)} LT',
    if (!load.isFinal) 'Unload crafted output before the next round.',
    _confidenceText(session.maximumCapacity),
  ];
  return lines.join('\n');
}

String _copyMaximumText(
  AfkWeightCalculation result,
  Recipe recipe,
  PlanStep step,
) {
  final lines = <String>[
    'AFK Load — ${recipe.name}',
    'Maximum safe load',
    'Safe attempts: ${result.safeAttempts}',
    if (result.safeMassBatches > 0)
      'Mass cycles: ${result.safeMassBatches} × ${step.batchSize}',
    '',
    'Load:',
    for (final stack in result.ingredientStacks)
      '- ${stack.quantity} × ${stack.itemName} '
          '(${formatQuantity(stack.loadLt)} LT)',
    '',
    'Start: ${formatQuantity(result.startingTotalLt)} LT',
    'Finish: ${formatQuantity(result.finishingTotalLt)} LT',
    'Safe stop: ${formatQuantity(result.stopWeightLt)} LT',
    _confidenceText(result),
  ];
  return lines.join('\n');
}

const _ledgerIngredientToggleTextStyle = TextStyle(
  fontFamily: 'Georgia',
  fontSize: 12,
  fontWeight: FontWeight.w700,
);

enum _PlannerMapQuickAction {
  npcVendors,
  manualGathering,
  addToGatherChecklist,
  addToPlannedNetwork,
}

class _PlannerMapQuickLookupRegion extends StatefulWidget {
  const _PlannerMapQuickLookupRegion({
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
  State<_PlannerMapQuickLookupRegion> createState() =>
      _PlannerMapQuickLookupRegionState();
}

class _PlannerMapQuickLookupRegionState
    extends State<_PlannerMapQuickLookupRegion> {
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
    if (!mounted) return;
    if (!availability.hasAnySource) return;
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

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    required this.controller,
    required this.ingredient,
    required this.externalActions,
    required this.openChoiceAnchor,
    required this.onSubstituteSelected,
    required this.onChoiceAnchorChanged,
  });

  final ModeFeatureController controller;
  final PlanStepIngredient ingredient;
  final PlannerExternalActions externalActions;
  final String? openChoiceAnchor;
  final void Function(PlanStepIngredient source, String selection)
  onSubstituteSelected;
  final ValueChanged<String?> onChoiceAnchorChanged;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final denseLayout = spec.usesDenseSplitLayout;
    final anchor =
        'step:${ingredient.parentName}:${ingredient.substituteGroup}';
    final domainIngredient = _resolveIngredient(
      controller,
      ingredient.parentName,
      ingredient.original,
      ingredient.substituteGroup,
    );
    final hasSubstitutes =
        domainIngredient != null && ingredient.options.length > 1;
    final perAttemptQuantity = domainIngredient == null
        ? null
        : controller
              .previewIngredientSelection(
                parentName: ingredient.parentName,
                ingredient: domainIngredient,
              )
              .need;
    final chooserOpen = openChoiceAnchor == anchor;
    final stableId = '${ingredient.parentName}:${ingredient.key}';
    // Keep the right-aligned amount comfortably inside the card. Sakura's
    // fixed corner blossom occupies the final 54 px of the lowest row, so its
    // larger gutter also prevents short values from disappearing into it.
    final quantityRightInset = spec.isSakuraNightGarden
        ? SakuraQueueCornerAsset.authoredSize.width - 8
        : 18.0;
    return _PlannerMapQuickLookupRegion(
      key: PlannerActionKeys.mapLookupRegion('queue:$stableId'),
      materialName: ingredient.name,
      stableId: 'queue:$stableId',
      externalActions: externalActions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: denseLayout ? 42 : 48),
            child: Row(
              children: <Widget>[
                _ItemAcquisitionPopover(
                  controller: controller,
                  name: ingredient.name,
                  stableId: '${ingredient.parentName}:${ingredient.key}',
                  overlayScope: 'queue',
                  size: denseLayout ? 40 : 46,
                  onOpening: () => onChoiceAnchorChanged(null),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Flexible(
                        child: hasSubstitutes
                            ? _SubstituteNameAnchor(
                                key: PlannerActionKeys.row('P12', anchor),
                                nameKey: PlannerActionKeys.row(
                                  'P11',
                                  '${ingredient.parentName}:${ingredient.key}',
                                ),
                                name: ingredient.name,
                                currentName: ingredient.baseName,
                                ingredient: domainIngredient,
                                fontSize: 17,
                                color: !spec.isStandard
                                    ? null
                                    : ingredient.missing > 0
                                    ? const Color(0xFFFFE6C8)
                                    : const Color(0xFFD8FFE2),
                                isShowing: chooserOpen,
                                onToggle: () => onChoiceAnchorChanged(
                                  chooserOpen ? null : anchor,
                                ),
                              )
                            : _CopyNameButton(
                                key: PlannerActionKeys.row(
                                  'P11',
                                  '${ingredient.parentName}:${ingredient.key}',
                                ),
                                name: ingredient.name,
                                fontSize: 17,
                                color: !spec.isStandard
                                    ? null
                                    : ingredient.missing > 0
                                    ? const Color(0xFFFFE6C8)
                                    : const Color(0xFFD8FFE2),
                                semanticPrefix: 'Copy ingredient',
                                onCopy: externalActions.copyName,
                              ),
                      ),
                      if (_qualityGrades(
                        controller,
                        ingredient.parentName,
                        ingredient.baseName,
                      ).isNotEmpty) ...<Widget>[
                        const SizedBox(width: 6),
                        _QualitySwatches(
                          controller: controller,
                          parentName: ingredient.parentName,
                          ingredientName: ingredient.original,
                          baseName: ingredient.baseName,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (perAttemptQuantity != null) ...<Widget>[
                  Padding(
                    padding: EdgeInsets.only(right: quantityRightInset),
                    child: SizedBox(
                      width: 86,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          formatQuantity(perAttemptQuantity),
                          key: ValueKey<String>(
                            'planner-ingredient-batch-quantity:'
                            '${ingredient.parentName}:${ingredient.original}',
                          ),
                          style: spec.typography.meta.copyWith(
                            color: spec.palette.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (chooserOpen && domainIngredient != null) ...<Widget>[
            SizedBox(height: denseLayout ? 4 : 6),
            Padding(
              padding: EdgeInsets.only(left: denseLayout ? 44 : 50),
              child: _InlineSubstituteChooser(
                controller: controller,
                parentName: ingredient.parentName,
                currentName: ingredient.baseName,
                ingredient: domainIngredient,
                onBeforeSelection: (selection) =>
                    onSubstituteSelected(ingredient, selection),
                onClose: () => onChoiceAnchorChanged(null),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemAcquisitionPopover extends StatelessWidget {
  const _ItemAcquisitionPopover({
    required this.controller,
    required this.name,
    required this.stableId,
    required this.overlayScope,
    required this.size,
    required this.onOpening,
  });

  final ModeFeatureController controller;
  final String name;
  final String stableId;
  final String overlayScope;
  final double size;
  final VoidCallback onOpening;

  @override
  Widget build(BuildContext context) {
    final details = _ingredientAcquisitionDetails(controller, name);
    final overlayId =
        '$overlayScope-acquisition:$stableId:${name.toLowerCase()}';
    return AnchoredPopover(
      overlayId: overlayId,
      preferredWidth: 350,
      maximumHeight: 430,
      margin: 24,
      gap: 12,
      placement: AnchoredPopoverPlacement.beside,
      consumeOutsideTap: true,
      popoverBuilder: (context, close) => _IngredientAcquisitionCard(
        controller: controller,
        stableId: stableId,
        details: details,
        onClose: close,
      ),
      anchorBuilder: (context, toggle, isShowing) => _IngredientInfoAnchor(
        key: PlannerActionKeys.row('P22', stableId),
        controller: controller,
        name: name,
        size: size,
        isShowing: isShowing,
        onPressed: () {
          if (!isShowing) onOpening();
          toggle();
        },
      ),
    );
  }
}

class _IngredientInfoAnchor extends StatelessWidget {
  const _IngredientInfoAnchor({
    required this.controller,
    required this.name,
    required this.size,
    required this.isShowing,
    required this.onPressed,
    super.key,
  });

  final ModeFeatureController controller;
  final String name;
  final double size;
  final bool isShowing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final highlight = spec.palette.trimBright.withAlpha(isShowing ? 210 : 92);
    return Semantics(
      button: true,
      toggled: isShowing,
      label:
          'How to obtain $name, ${isShowing ? 'open' : 'closed'}. '
          'Click the item icon for details.',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          splashFactory: NoSplash.splashFactory,
          hoverColor: highlight.withAlpha(22),
          focusColor: highlight.withAlpha(34),
          highlightColor: highlight.withAlpha(28),
          borderRadius: BorderRadius.circular(spec.geometry.fieldRadius),
          onTap: onPressed,
          child: Container(
            width: size,
            height: size,
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(spec.geometry.fieldRadius),
              border: isShowing
                  ? Border.all(color: highlight, width: 1.2)
                  : null,
            ),
            child: PlannerItemIcon(
              controller: controller,
              name: name,
              size: size,
            ),
          ),
        ),
      ),
    );
  }
}

class _IngredientAcquisitionCard extends StatelessWidget {
  const _IngredientAcquisitionCard({
    required this.controller,
    required this.stableId,
    required this.details,
    required this.onClose,
  });

  final ModeFeatureController controller;
  final String stableId;
  final _IngredientAcquisitionDetails details;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final standard = context.standardVisual;
    final titleColor = ledger
        ? const Color(0xFF6B2E29)
        : sakura
        ? spec.palette.text
        : const Color(0xFFFFF1CF);
    final bodyColor = ledger
        ? const Color(0xFF65543F)
        : sakura
        ? spec.palette.textMuted
        : const Color(0xFFD6EEE4);
    final content = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: AnchoredPopoverDragRegion(
                  key: ValueKey<String>(
                    'planner-acquisition-drag-region:$stableId',
                  ),
                  child: Row(
                    children: <Widget>[
                      PlannerItemIcon(
                        controller: controller,
                        name: details.name,
                        size: 38,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (details.kind.isNotEmpty)
                              Text(
                                details.kind,
                                style: spec.typography.meta.copyWith(
                                  color: bodyColor.withAlpha(190),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            Text(
                              details.name,
                              style:
                                  (ledger
                                          ? const TextStyle(
                                              fontFamily: 'Georgia',
                                              fontSize: 17,
                                              fontWeight: FontWeight.w700,
                                            )
                                          : spec.typography.body.copyWith(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                            ))
                                      .copyWith(color: titleColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SourceInfoCloseButton(
                semanticLabel:
                    'Close acquisition information for ${details.name}',
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            'How to Obtain',
            style: spec.typography.body.copyWith(
              color: titleColor,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          for (var index = 0; index < details.lines.length; index += 1)
            Padding(
              padding: EdgeInsets.only(
                bottom: index + 1 == details.lines.length ? 0 : 7,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      '•',
                      style: TextStyle(
                        color: sakura
                            ? spec.palette.trimBright
                            : ledger
                            ? const Color(0xFF9A6639)
                            : const Color(0xFFF0C67D),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      details.lines[index],
                      key: index == 0
                          ? ValueKey<String>(
                              'planner-acquisition-body:$stableId',
                            )
                          : null,
                      style: spec.typography.body.copyWith(
                        color: bodyColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.28,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    final decoration = BoxDecoration(
      gradient: ledger
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color.fromARGB(249, 255, 247, 223),
                Color.fromARGB(168, 231, 211, 171),
              ],
            )
          : sakura
          ? SakuraNightGardenSpec.raisedSurfaceGradient
          : StandardSpec.glassGradient(topAlpha: 210, bottomAlpha: 92),
      borderRadius: BorderRadius.circular(
        ledger
            ? 2
            : sakura
            ? spec.geometry.cardRadius
            : 8,
      ),
      border: Border.all(
        color: ledger
            ? const Color(0xFFB9903E)
            : sakura
            ? spec.palette.trim
            : StandardSpec.accentBrush(
                standard.accentHue,
                alpha: .48,
                neon: standard.neon,
              ),
      ),
      boxShadow: ledger
          ? const <BoxShadow>[
              BoxShadow(
                color: Color(0x60352516),
                blurRadius: 28,
                offset: Offset(0, 10),
              ),
            ]
          : sakura
          ? spec.materials.highShadow
          : const <BoxShadow>[
              BoxShadow(
                color: Color(0x73000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
    );
    Widget card = Container(
      key: ValueKey<String>('planner-acquisition-card:$stableId'),
      decoration: decoration,
      child: ledger
          ? CustomPaint(
              foregroundPainter: const LedgerOrnamentFramePainter(),
              child: content,
            )
          : content,
    );
    card = Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'How to obtain ${details.name}',
      child: card,
    );
    return card;
  }
}

final class _IngredientAcquisitionDetails {
  const _IngredientAcquisitionDetails({
    required this.name,
    required this.kind,
    required this.lines,
  });

  final String name;
  final String kind;
  final List<String> lines;
}

_IngredientAcquisitionDetails _ingredientAcquisitionDetails(
  ModeFeatureController controller,
  String name,
) {
  final resolved = resolveAcquisitionRecipe(
    name: name,
    currentMode: controller.mode,
    recipesByMode: <CraftMode, Map<String, Recipe>>{
      for (final mode in CraftMode.values)
        mode: controller.owner.modes[mode]!.recipes,
    },
  );
  final recipe = resolved?.recipe;
  final canonicalName = resolved?.name ?? name;
  final itemInfo = recipeBookInfoFor(
    name: canonicalName,
    recipe: recipe,
    searchTerms: const <String>[],
    consumerRecipes: const <Recipe>[],
  );
  final source = controller.resolveItemSource(name, recipe: recipe);
  final lines = <String>[];
  for (final line in itemInfo?.howToObtain ?? const <String>[]) {
    _addDistinctAcquisitionLine(lines, line);
  }
  for (final line
      in controller
              .resolveItemAcquisition(canonicalName)
              ?.displayableSummaries ??
          const <String>[]) {
    _addDistinctAcquisitionLine(lines, line);
  }
  _addDistinctAcquisitionLine(lines, source.sourceNote);
  final vendor = source.vendor?.trim() ?? '';
  final location = source.location?.trim() ?? '';
  if (vendor.isNotEmpty) {
    _addDistinctAcquisitionLine(
      lines,
      'Buy from $vendor${location.isEmpty ? '' : ' in $location'}.',
    );
  }
  if (lines.isEmpty) {
    lines.add('No acquisition note has been saved for this custom ingredient.');
  }
  return _IngredientAcquisitionDetails(
    name: canonicalName,
    kind: itemInfo?.kind.trim() ?? recipe?.group?.trim() ?? 'Ingredient',
    lines: List<String>.unmodifiable(lines),
  );
}

void _addDistinctAcquisitionLine(List<String> lines, String? candidate) {
  final line = candidate?.trim() ?? '';
  if (line.isEmpty) return;
  final folded = line.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (lines.any(
    (existing) =>
        existing.toLowerCase().replaceAll(RegExp(r'\s+'), ' ') == folded,
  )) {
    return;
  }
  lines.add(line);
}

class _NeedPanel extends StatelessWidget {
  const _NeedPanel({
    required this.controller,
    required this.plan,
    required this.materials,
    required this.externalActions,
    required this.title,
    required this.scrollController,
    required this.ownedDraftController,
    required this.showPrices,
    required this.marketLoading,
    required this.marketMessage,
    required this.marketRowDiagnostics,
    required this.allowMarketActions,
    required this.onCheckPrices,
    required this.onHidePrices,
    required this.openChoiceAnchor,
    required this.onSubstituteSelected,
    required this.onChoiceAnchorChanged,
  });

  final ModeFeatureController controller;
  final PlanResult plan;
  final List<MissingMaterial> materials;
  final PlannerExternalActions externalActions;
  final String title;
  final ScrollController scrollController;
  final TextEditingController Function(String name) ownedDraftController;
  final bool showPrices;
  final bool marketLoading;
  final String? marketMessage;
  final Map<String, List<PlannerMarketRowDiagnostic>> marketRowDiagnostics;
  final bool allowMarketActions;
  final Future<void> Function() onCheckPrices;
  final VoidCallback onHidePrices;
  final String? openChoiceAnchor;
  final void Function(MissingMaterial source, String selection)
  onSubstituteSelected;
  final ValueChanged<String?> onChoiceAnchorChanged;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final denseLayout = spec.usesDenseSplitLayout;
    final action = !allowMarketActions
        ? null
        : showPrices
        ? AppButton.label(
            'Hide Prices',
            key: PlannerActionKeys.p16,
            minimumSize: Size(denseLayout ? 104 : 86, 38),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            onPressed: marketLoading ? null : onHidePrices,
          )
        : AppButton.label(
            marketLoading ? 'Checking…' : 'Check Prices',
            key: PlannerActionKeys.p15,
            minimumSize: Size(denseLayout ? 112 : 86, 38),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            onPressed: marketLoading ? null : onCheckPrices,
          );
    final itemCount = materials.length + (showPrices ? 1 : 0);
    final needList = ListView.builder(
      key: const PageStorageKey<String>('planner-need-first'),
      controller: scrollController,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == materials.length) {
          return Padding(
            padding: EdgeInsets.only(right: denseLayout ? 8 : 0),
            child: _MarketSummary(
              plan: plan,
              message: marketMessage,
              loading: marketLoading,
              fetchedAt: controller.state.value.market.fetchedAt,
              region: controller.state.value.market.region,
            ),
          );
        }
        final row = materials[index];
        return Padding(
          key: ValueKey<String>('need:${row.key}'),
          padding: EdgeInsets.only(
            bottom: index + 1 < itemCount ? (denseLayout ? 6 : 10) : 0,
            right: denseLayout ? 8 : 0,
          ),
          child: _NeedRow(
            controller: controller,
            row: row,
            externalActions: externalActions,
            draftController: ownedDraftController(row.name),
            showPrices: showPrices,
            marketDiagnostics: _marketDiagnosticsFor(
              marketRowDiagnostics,
              row.name,
            ),
            openChoiceAnchor: openChoiceAnchor,
            onSubstituteSelected: onSubstituteSelected,
            onChoiceAnchorChanged: onChoiceAnchorChanged,
          ),
        );
      },
    );
    final needListWithoutPlatformScrollbar = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: needList,
    );
    final missingMeta = '${materials.length} missing';
    final headerTextSize = spec.typography.section.fontSize ?? 25;
    final enlargedHeaderText =
        MediaQuery.textScalerOf(context).scale(headerTextSize) /
            headerTextSize >
        1.25;
    final splitDenseHeaderAction =
        denseLayout && enlargedHeaderText && action != null;
    final denseHeaderTrailing = denseLayout && action != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(
                missingMeta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: spec.typography.meta.copyWith(
                  color: spec.palette.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.normal,
                ),
              ),
              const SizedBox(width: 10),
              action,
            ],
          )
        : action;
    return AppSurface(
      role: AppSurfaceRole.layout,
      semanticLabel: title,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: title,
            meta: denseLayout && action != null && !splitDenseHeaderAction
                ? null
                : missingMeta,
            trailing: splitDenseHeaderAction ? null : denseHeaderTrailing,
          ),
          if (splitDenseHeaderAction) ...<Widget>[
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerRight, child: action),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: materials.isEmpty && !showPrices
                ? const _PlannerEmpty(
                    message:
                        'All base materials are covered by inventory or craft steps.',
                  )
                : needListWithoutPlatformScrollbar,
          ),
        ],
      ),
    );
  }
}

class _NeedRow extends StatelessWidget {
  const _NeedRow({
    required this.controller,
    required this.row,
    required this.externalActions,
    required this.draftController,
    required this.showPrices,
    required this.marketDiagnostics,
    required this.openChoiceAnchor,
    required this.onSubstituteSelected,
    required this.onChoiceAnchorChanged,
  });

  final ModeFeatureController controller;
  final MissingMaterial row;
  final PlannerExternalActions externalActions;
  final TextEditingController draftController;
  final bool showPrices;
  final List<PlannerMarketRowDiagnostic> marketDiagnostics;
  final String? openChoiceAnchor;
  final void Function(MissingMaterial source, String selection)
  onSubstituteSelected;
  final ValueChanged<String?> onChoiceAnchorChanged;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final denseLayout = spec.usesDenseSplitLayout;
    final choice = row.choice;
    final anchor = choice == null
        ? ''
        : 'missing:${row.name}:${choice.substituteGroup}';
    final domainIngredient = choice == null
        ? null
        : _resolveIngredient(
            controller,
            choice.parentName,
            choice.original,
            choice.substituteGroup,
          );
    final hasSubstitutes =
        domainIngredient != null && choice != null && choice.options.length > 1;
    final source = _sourceInfo(controller, row);
    final confirmedMarketUnlisted =
        controller.state.value.market.isItemUnlisted(row.name) ||
        _isConfirmedMarketUnlisted(marketDiagnostics);
    final visibleMarketDiagnostics = _withConfirmedMarketUnlistedDiagnostic(
      marketDiagnostics,
      confirmed: confirmedMarketUnlisted,
    );
    final stableId = 'need:${row.key}';
    return _PlannerMapQuickLookupRegion(
      key: PlannerActionKeys.mapLookupRegion(stableId),
      materialName: row.name,
      stableId: stableId,
      externalActions: externalActions,
      child: AppSurface(
        role: AppSurfaceRole.row,
        tone: _toneFor(row),
        semanticLabel: '${row.name}, missing ${formatQuantity(row.missing)}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: denseLayout ? 50 : 54,
                  child: Align(
                    alignment: Alignment.center,
                    child: _ItemAcquisitionPopover(
                      controller: controller,
                      name: row.name,
                      stableId: 'need:${row.key}',
                      overlayScope: 'need',
                      size: denseLayout ? 46 : 50,
                      onOpening: () => onChoiceAnchorChanged(null),
                    ),
                  ),
                ),
                SizedBox(width: denseLayout ? 8 : 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: hasSubstitutes
                                ? _SubstituteNameAnchor(
                                    key: PlannerActionKeys.row('P12', anchor),
                                    nameKey: PlannerActionKeys.row(
                                      'P20',
                                      row.name,
                                    ),
                                    name: row.name,
                                    currentName: choice.baseName,
                                    ingredient: domainIngredient,
                                    fontSize: denseLayout ? 16.5 : 17.5,
                                    isShowing: openChoiceAnchor == anchor,
                                    onToggle: () => onChoiceAnchorChanged(
                                      openChoiceAnchor == anchor
                                          ? null
                                          : anchor,
                                    ),
                                  )
                                : _CopyNameButton(
                                    key: PlannerActionKeys.row('P20', row.name),
                                    name: row.name,
                                    fontSize: denseLayout ? 16.5 : 17.5,
                                    semanticPrefix: 'Copy Need First item',
                                    onCopy: externalActions.copyName,
                                  ),
                          ),
                          if (source.hasDetails) ...<Widget>[
                            const SizedBox(width: 5),
                            _AnchoredSourceInfoButton(
                              key: PlannerActionKeys.row('P17', row.name),
                              controller: controller,
                              request: source,
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: denseLayout ? 3 : 6),
                      Text(
                        'Need ${formatQuantity(row.need)} | '
                        'Have ${formatQuantity(row.have)} | '
                        'Missing ${formatQuantity(row.missing)}',
                        style: spec.typography.meta.copyWith(
                          color: denseLayout
                              ? spec.palette.textMuted
                              : const Color(0xFFC5D7CF),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontStyle: denseLayout ? FontStyle.normal : null,
                          height: denseLayout ? 1.15 : null,
                        ),
                      ),
                      if (showPrices &&
                          _hasMarketPills(
                            row,
                            suppressCentralMarket: confirmedMarketUnlisted,
                          )) ...<Widget>[
                        const SizedBox(height: 5),
                        _MarketPills(
                          row: row,
                          suppressCentralMarket: confirmedMarketUnlisted,
                        ),
                      ],
                      if (showPrices &&
                          visibleMarketDiagnostics.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 5),
                        _MarketDiagnostics(
                          diagnostics: visibleMarketDiagnostics,
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: denseLayout ? 8 : 10),
                _OwnedDraftActions(
                  key: PlannerActionKeys.row('P18', row.name),
                  controller: controller,
                  name: row.name,
                  textController: draftController,
                ),
              ],
            ),
            if (openChoiceAnchor == anchor &&
                domainIngredient != null &&
                choice != null) ...<Widget>[
              SizedBox(height: denseLayout ? 5 : 8),
              Padding(
                padding: EdgeInsets.only(left: denseLayout ? 52 : 58),
                child: _InlineSubstituteChooser(
                  controller: controller,
                  parentName: choice.parentName,
                  currentName: choice.baseName,
                  ingredient: domainIngredient,
                  onBeforeSelection: (selection) =>
                      onSubstituteSelected(row, selection),
                  onClose: () => onChoiceAnchorChanged(null),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OwnedDraftActions extends StatefulWidget {
  const _OwnedDraftActions({
    required this.controller,
    required this.name,
    required this.textController,
    super.key,
  });

  final ModeFeatureController controller;
  final String name;
  final TextEditingController textController;

  @override
  State<_OwnedDraftActions> createState() => _OwnedDraftActionsState();
}

class _OwnedDraftActionsState extends State<_OwnedDraftActions> {
  late final FocusNode _focus = FocusNode(onKeyEvent: _handleKey)
    ..addListener(_focusChanged);
  String? _error;

  TextEditingController get _text => widget.textController;

  @override
  void dispose() {
    _focus
      ..removeListener(_focusChanged)
      ..dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (_focus.hasFocus) {
      _text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _text.text.length,
      );
      return;
    }
    _validate();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    final direction = HardwareKeyboard.instance.isShiftPressed
        ? TraversalDirection.up
        : TraversalDirection.down;
    return node.focusInDirection(direction)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  bool _validate() {
    if (_text.text.trim().isEmpty) {
      _text.value = const TextEditingValue(
        text: '0',
        selection: TextSelection.collapsed(offset: 1),
      );
    }
    final value = parsePlannerNumber(_text.text);
    final valid = value != null && value >= 0;
    if (valid) {
      final display = formatGroupedEditableQuantity(value);
      _text.value = TextEditingValue(
        text: display,
        selection: TextSelection.collapsed(offset: display.length),
      );
    }
    setState(() => _error = valid ? null : 'Enter a nonnegative amount');
    return valid;
  }

  void _add() {
    if (!_validate()) return;
    final value = parsePlannerNumber(_text.text)!;
    if (value <= 0) {
      setState(() => _error = 'Enter an amount greater than zero to add');
      return;
    }
    widget.controller.addMissingAmount(widget.name, value);
    _text.value = const TextEditingValue(
      text: '0',
      selection: TextSelection.collapsed(offset: 1),
    );
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final bodyFontSize = spec.typography.body.fontSize ?? 14.0;
    final textScale =
        MediaQuery.textScalerOf(context).scale(bodyFontSize) / bodyFontSize;
    final referenceGeometry = textScale <= 1.25;
    final denseLayout = spec.usesDenseSplitLayout;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: denseLayout ? 82 : 92,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 82,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    height: referenceGeometry ? 38 : null,
                    child: PlannerTextField(
                      controller: _text,
                      focusNode: _focus,
                      semanticLabel:
                          'Amount of ${widget.name} to add to owned inventory',
                      hintText: '0',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.right,
                      fontWeight: FontWeight.w700,
                      minimumHeight: referenceGeometry ? 38 : null,
                      invalid: _error != null,
                      onSubmitted: (_) => _validate(),
                    ),
                  ),
                  if (_error case final error?) ...<Widget>[
                    const SizedBox(height: 3),
                    Semantics(
                      liveRegion: true,
                      label: error,
                      child: Text(
                        error,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: spec.typography.meta.copyWith(
                          color: spec.palette.danger,
                          fontSize: 10,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: denseLayout ? 8 : 10),
        AppButton(
          key: PlannerActionKeys.row('P19', widget.name),
          role: denseLayout ? AppButtonRole.primary : AppButtonRole.secondary,
          semanticLabel: 'Add ${widget.name} to owned inventory',
          minimumSize: Size(denseLayout ? 72 : 78, 38),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          onPressed: _add,
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppVectorGlyph('add', size: 13),
                SizedBox(width: 4),
                Text('Add'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AnchoredSourceInfoButton extends StatelessWidget {
  const _AnchoredSourceInfoButton({
    required this.controller,
    required this.request,
    super.key,
  });

  final ModeFeatureController controller;
  final PlannerSourceInfoRequest request;

  @override
  Widget build(BuildContext context) => AnchoredPopover(
    overlayId: 'source:${request.name}',
    preferredWidth: 330,
    maximumHeight: 360,
    margin: 24,
    gap: 16,
    placement: AnchoredPopoverPlacement.beside,
    dismissOnEscape: false,
    consumeOutsideTap: true,
    popoverBuilder: (context, close) => _SourceInfoCard(
      controller: controller,
      request: request,
      onClose: close,
    ),
    anchorBuilder: (context, toggle, isShowing) => AppButton(
      role: AppButtonRole.infoChip,
      minimumSize: const Size.square(20),
      padding: EdgeInsets.zero,
      semanticLabel:
          'Source information for ${request.name}, ${isShowing ? 'open' : 'closed'}',
      tooltip: _sourceInfoText(request),
      onPressed: toggle,
      child: const Text(
        '?',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    ),
  );
}

class _SourceInfoCard extends StatelessWidget {
  const _SourceInfoCard({
    required this.controller,
    required this.request,
    required this.onClose,
  });

  final ModeFeatureController controller;
  final PlannerSourceInfoRequest request;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final standard = context.standardVisual;
    final close = _SourceInfoCloseButton(
      semanticLabel: 'Close source information for ${request.name}',
      onPressed: onClose,
    );
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: AnchoredPopoverDragRegion(
            key: const ValueKey<String>('planner-source-info-drag-region'),
            child: Row(
              children: <Widget>[
                if (ledger || sakura) ...<Widget>[
                  SizedBox(
                    width: 38,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: PlannerItemIcon(
                        controller: controller,
                        name: request.name,
                        size: 34,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    request.name,
                    style: TextStyle(
                      color: ledger
                          ? const Color(0xFF6B2E29)
                          : sakura
                          ? spec.palette.text
                          : const Color(0xFFFFF1CF),
                      fontFamily: ledger || sakura ? 'Georgia' : 'Segoe UI',
                      fontSize: ledger ? 14 : 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        close,
      ],
    );
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          header,
          const SizedBox(height: 6),
          Text(
            _sourceInfoText(request),
            key: const ValueKey<String>('planner-source-info-body'),
            style: TextStyle(
              color: ledger
                  ? const Color(0xFF65543F)
                  : sakura
                  ? spec.palette.textMuted
                  : const Color(0xFFD6EEE4),
              fontFamily: ledger ? 'Georgia' : 'Segoe UI',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
    final decoration = BoxDecoration(
      gradient: ledger
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color.fromARGB(249, 255, 247, 223),
                Color.fromARGB(168, 231, 211, 171),
              ],
            )
          : sakura
          ? SakuraNightGardenSpec.raisedSurfaceGradient
          : StandardSpec.glassGradient(topAlpha: 196, bottomAlpha: 72),
      borderRadius: BorderRadius.circular(
        ledger
            ? 2
            : sakura
            ? spec.geometry.cardRadius
            : 8,
      ),
      border: Border.all(
        color: ledger
            ? const Color(0xFFB9903E)
            : sakura
            ? spec.palette.trim
            : StandardSpec.accentBrush(
                standard.accentHue,
                alpha: .45,
                neon: standard.neon,
              ),
      ),
      boxShadow: ledger
          ? const <BoxShadow>[
              BoxShadow(
                color: Color(0x60352516),
                blurRadius: 28,
                offset: Offset(0, 10),
              ),
            ]
          : sakura
          ? spec.materials.highShadow
          : const <BoxShadow>[],
    );
    Widget card = Container(
      key: const ValueKey<String>('planner-source-info-card'),
      decoration: decoration,
      child: ledger
          ? CustomPaint(
              foregroundPainter: const LedgerOrnamentFramePainter(),
              child: content,
            )
          : content,
    );
    card = Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Source information for ${request.name}',
      child: card,
    );
    return card;
  }
}

class _SourceInfoCloseButton extends StatefulWidget {
  const _SourceInfoCloseButton({
    required this.semanticLabel,
    required this.onPressed,
  });

  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  State<_SourceInfoCloseButton> createState() => _SourceInfoCloseButtonState();
}

class _SourceInfoCloseButtonState extends State<_SourceInfoCloseButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final standard = context.standardVisual;
    final size = spec.usesDenseSplitLayout ? 30.0 : 22.0;
    final overlay = _pressed
        ? const Color(0x24000000)
        : _hovered
        ? const Color(0x1AFFFFFF)
        : Colors.transparent;
    final closeGlyph = ColoredBox(
      color: overlay,
      child: Center(
        child: AppVectorGlyph(
          'close',
          size: 13,
          color: ledger
              ? const Color(0xFFFFF4D8)
              : sakura
              ? spec.palette.text
              : const Color(0xFFFFF1CF),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            key: const ValueKey<String>('planner-source-info-close'),
            duration: spec.motion.interactionDuration,
            width: size,
            height: size,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: ledger
                  ? spec.materials.primary
                  : sakura
                  ? SakuraNightGardenSpec.raisedSurfaceGradient
                  : StandardSpec.glassGradient(topAlpha: 34, bottomAlpha: 10),
              borderRadius: BorderRadius.circular(
                ledger
                    ? 2
                    : sakura
                    ? spec.geometry.buttonRadius
                    : 999,
              ),
              border: Border.all(
                color: ledger
                    ? const Color(0xFFB9903E)
                    : sakura
                    ? spec.palette.trim
                    : StandardSpec.accentBrush(
                        standard.accentHue,
                        alpha: .32,
                        neon: standard.neon,
                      ),
              ),
              boxShadow: spec.usesDenseSplitLayout
                  ? spec.materials.lowShadow
                  : null,
            ),
            child: closeGlyph,
          ),
        ),
      ),
    );
  }
}

class _SubstituteNameAnchor extends StatefulWidget {
  const _SubstituteNameAnchor({
    required this.name,
    required this.nameKey,
    required this.currentName,
    required this.ingredient,
    required this.fontSize,
    required this.isShowing,
    required this.onToggle,
    this.color,
    this.semanticLabel,
    this.tooltip,
    super.key,
  });

  final String name;
  final Key nameKey;
  final String currentName;
  final Ingredient ingredient;
  final double fontSize;
  final Color? color;
  final String? semanticLabel;
  final String? tooltip;
  final bool isShowing;
  final VoidCallback onToggle;

  @override
  State<_SubstituteNameAnchor> createState() => _SubstituteNameAnchorState();
}

class _SubstituteNameAnchorState extends State<_SubstituteNameAnchor> {
  late final FocusNode _focus = FocusNode();
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _activate() {
    if (mounted) setState(() => _pressed = false);
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final standard = context.standardVisual;
    final highlighted = _hovered || _focused || widget.isShowing;
    final focusColor = ledger
        ? const Color(0xFFD6B45A)
        : sakura
        ? spec.palette.primaryBright
        : StandardSpec.accentBrush(standard.accentHue, neon: standard.neon);
    final indicatorColor = highlighted
        ? focusColor
        : ledger
        ? const Color(0xFF9B7832)
        : sakura
        ? spec.palette.textMuted
        : StandardSpec.accentBrush(
            standard.accentHue,
            alpha: .5,
            neon: standard.neon,
          );
    final outlineColor = _focused
        ? ledger
              ? const Color(0xFFB9903E)
              : focusColor
        : Colors.transparent;
    final interactionOverlay = _pressed
        ? const Color(0x28000000)
        : _hovered
        ? const Color(0x16FFFFFF)
        : Colors.transparent;
    final options = _distinctFolded(widget.ingredient.options);
    Widget control = Semantics(
      button: true,
      toggled: widget.isShowing,
      label:
          widget.semanticLabel ??
          'Choose substitute for ${widget.ingredient.name}; current ${widget.currentName}; ${widget.isShowing ? 'open' : 'closed'}',
      child: FocusableActionDetector(
        focusNode: _focus,
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            _focus.requestFocus();
            setState(() => _pressed = true);
          },
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: _activate,
          child: AnimatedContainer(
            duration: spec.motion.interactionDuration,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: BoxDecoration(
              color: interactionOverlay,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: outlineColor),
            ),
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      widget.name,
                      key: widget.nameKey,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: spec.typography.body.copyWith(
                        color: ledger ? const Color(0xFF6B2E29) : widget.color,
                        fontSize: widget.fontSize,
                        fontWeight: FontWeight.w700,
                        height: spec.usesDenseSplitLayout ? 1.15 : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IgnorePointer(
                    child: ExcludeSemantics(
                      child: AppVectorGlyph(
                        'swap',
                        size: 11,
                        color: indicatorColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    control = Tooltip(
      message:
          widget.tooltip ??
          'Other ingredients can be used.\n'
              'Current: ${widget.currentName}\n'
              '${options.join(', ')}',
      child: control,
    );
    return control;
  }
}

class _QueueTitleSubstituteChooser extends StatelessWidget {
  const _QueueTitleSubstituteChooser({
    required this.controller,
    required this.stepName,
    required this.choices,
    required this.onSubstituteSelected,
    required this.onClose,
  });

  final ModeFeatureController controller;
  final String stepName;
  final List<({PlanStepIngredient source, Ingredient ingredient})> choices;
  final void Function(PlanStepIngredient source, String selection)
  onSubstituteSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (choices.length == 1) {
      final choice = choices.single;
      return _InlineSubstituteChooser(
        controller: controller,
        parentName: choice.source.parentName,
        currentName: choice.source.baseName,
        ingredient: choice.ingredient,
        onBeforeSelection: (selection) =>
            onSubstituteSelected(choice.source, selection),
        onClose: onClose,
      );
    }

    final spec = context.visualTheme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Recipe choices affecting $stepName',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Choose which recipe choice to change',
            style: spec.typography.meta.copyWith(
              color: spec.palette.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (var index = 0; index < choices.length; index += 1) ...<Widget>[
            if (index > 0) const SizedBox(height: 10),
            Text(
              '${choices[index].source.parentName} · '
              'currently ${choices[index].source.baseName}',
              style: spec.typography.body.copyWith(
                color: spec.palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            _InlineSubstituteChooser(
              controller: controller,
              parentName: choices[index].source.parentName,
              currentName: choices[index].source.baseName,
              ingredient: choices[index].ingredient,
              optionKeyScope:
                  '${choices[index].source.parentName}:'
                  '${choices[index].source.substituteGroup}',
              onBeforeSelection: (selection) =>
                  onSubstituteSelected(choices[index].source, selection),
              onClose: onClose,
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineSubstituteChooser extends StatefulWidget {
  const _InlineSubstituteChooser({
    required this.controller,
    required this.parentName,
    required this.currentName,
    required this.ingredient,
    required this.onClose,
    this.onBeforeSelection,
    this.optionKeyScope,
  });

  final ModeFeatureController controller;
  final String parentName;
  final String currentName;
  final Ingredient ingredient;
  final VoidCallback onClose;
  final ValueChanged<String>? onBeforeSelection;
  final String? optionKeyScope;

  @override
  State<_InlineSubstituteChooser> createState() =>
      _InlineSubstituteChooserState();
}

class _InlineSubstituteChooserState extends State<_InlineSubstituteChooser> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final options = _distinctFolded(widget.ingredient.options);
    final selected = _selectedSubstituteFor(
      controller: widget.controller,
      parentName: widget.parentName,
      currentName: widget.currentName,
      ingredient: widget.ingredient,
    );
    final decoration = BoxDecoration(
      gradient: ledger
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color.fromARGB(161, 255, 247, 223),
                Color.fromARGB(122, 231, 211, 171),
              ],
            )
          : sakura
          ? SakuraNightGardenSpec.surfaceGradient
          : StandardSpec.glassGradient(topAlpha: 54, bottomAlpha: 18),
      borderRadius: BorderRadius.circular(
        ledger
            ? 2
            : sakura
            ? spec.geometry.cardRadius
            : 10,
      ),
      border: Border.all(
        color: ledger
            ? const Color(0x8EB9903E)
            : sakura
            ? spec.palette.trim.withAlpha(184)
            : const Color(0x406ED6A7),
      ),
      boxShadow: ledger
          ? const <BoxShadow>[
              BoxShadow(
                color: Color(0x30352516),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ]
          : sakura
          ? spec.materials.lowShadow
          : const <BoxShadow>[],
    );
    Widget panel = Container(
      key: ValueKey<String>(
        'planner-substitute-panel:${widget.parentName}:${widget.ingredient.name}',
      ),
      decoration: decoration,
      child: CustomPaint(
        foregroundPainter: ledger ? const LedgerOrnamentFramePainter() : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth
                  .clamp(0.0, 174.0)
                  .toDouble();
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final option in options)
                    SizedBox(
                      width: itemWidth,
                      height: spec.usesDenseSplitLayout ? 52 : 44,
                      child: _SubstituteOption(
                        key: PlannerActionKeys.row(
                          'P13',
                          widget.optionKeyScope == null
                              ? option
                              : '${widget.optionKeyScope}:$option',
                        ),
                        controller: widget.controller,
                        option: option,
                        ratio: _ratioFor(widget.ingredient, option),
                        selected: _sameFolded(option, selected),
                        onPressed: () {
                          widget.onBeforeSelection?.call(option);
                          widget.controller.selectSubstitute(
                            parentName: widget.parentName,
                            ingredient: widget.ingredient,
                            selection: option,
                          );
                          widget.onClose();
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    panel = Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Substitute choices for ${widget.ingredient.name}',
      child: panel,
    );
    return panel;
  }
}

class _SubstituteOption extends StatefulWidget {
  const _SubstituteOption({
    required this.controller,
    required this.option,
    required this.ratio,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final ModeFeatureController controller;
  final String option;
  final double ratio;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_SubstituteOption> createState() => _SubstituteOptionState();
}

class _SubstituteOptionState extends State<_SubstituteOption> {
  late final FocusNode _focus = FocusNode();
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _activate() {
    if (mounted) setState(() => _pressed = false);
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final standard = context.standardVisual;
    final restingBorder = ledger
        ? widget.selected
              ? const Color(0xFFD6B45A)
              : const Color(0x6FA77E2E)
        : sakura
        ? widget.selected
              ? spec.palette.primaryBright
              : spec.palette.trim.withAlpha(160)
        : widget.selected
        ? StandardSpec.accentBrush(
            standard.accentHue,
            alpha: .85,
            neon: standard.neon,
          )
        : const Color(0x477B9A82);
    final border = _focused
        ? ledger
              ? spec.palette.primaryBright
              : sakura
              ? spec.palette.primaryBright
              : StandardSpec.accentBrush(
                  standard.accentHue,
                  neon: standard.neon,
                )
        : restingBorder;
    final interactionOverlay = _pressed
        ? const Color(0x28000000)
        : _hovered
        ? const Color(0x1EFFFFFF)
        : Colors.transparent;
    final content = Row(
      children: <Widget>[
        PlannerItemIcon(
          controller: widget.controller,
          name: widget.option,
          size: 26,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.option,
            maxLines: 2,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: ledger
                  ? widget.selected
                        ? const Color(0xFFF7EAC7)
                        : const Color(0xFF352516)
                  : sakura
                  ? spec.palette.text
                  : const Color(0xFFFFF4D8),
              fontFamily: ledger ? 'Georgia' : 'Segoe UI',
              fontSize: widget.option.length > 18 ? 11.5 : 13,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
        ),
        if (widget.selected) ...<Widget>[
          const SizedBox(width: 5),
          const AppVectorGlyph('check', size: 13, color: Color(0xFFDFFFE5)),
        ],
      ],
    );
    return Semantics(
      button: true,
      selected: widget.selected,
      label:
          'Use ${widget.option} substitute, ratio ${formatQuantity(widget.ratio)}',
      child: FocusableActionDetector(
        focusNode: _focus,
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            _focus.requestFocus();
            setState(() => _pressed = true);
          },
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: _activate,
          child: AnimatedContainer(
            duration: spec.motion.interactionDuration,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: ledger
                  ? widget.selected
                        ? spec.materials.primary
                        : _ledgerRaisedVellumGradient
                  : sakura
                  ? widget.selected
                        ? SakuraNightGardenSpec.sakuraLacquerGradient
                        : SakuraNightGardenSpec.raisedSurfaceGradient
                  : StandardSpec.glassGradient(
                      topAlpha: widget.selected ? 96 : 42,
                      bottomAlpha: widget.selected ? 30 : 14,
                    ),
              borderRadius: BorderRadius.circular(
                ledger
                    ? 2
                    : sakura
                    ? spec.geometry.buttonRadius
                    : 8,
              ),
              border: Border.all(color: border),
            ),
            child: ColoredBox(color: interactionOverlay, child: content),
          ),
        ),
      ),
    );
  }
}

class _QualitySwatches extends StatelessWidget {
  const _QualitySwatches({
    required this.controller,
    required this.parentName,
    required this.ingredientName,
    required this.baseName,
  });

  final ModeFeatureController controller;
  final String parentName;
  final String ingredientName;
  final String baseName;

  @override
  Widget build(BuildContext context) {
    final profile = controller.qualityProfile(
      parentName: parentName,
      selectedName: baseName,
    );
    final grades = _qualityGrades(controller, parentName, baseName);
    final current = controller.selectedIngredientGrade(
      parentName: parentName,
      ingredientName: ingredientName,
      selectedName: baseName,
    );
    return Semantics(
      key: PlannerActionKeys.row('P14', '$parentName:$ingredientName'),
      container: true,
      label: 'Quality grade for $ingredientName',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var index = 0; index < grades.length; index += 1) ...<Widget>[
            _QualityButton(
              label: grades[index].$2,
              grade: grades[index].$1,
              normalIsBlueFamily:
                  profile.family == IngredientQualityFamily.blue,
              selected: _sameFolded(current, grades[index].$1),
              onPressed: () => controller.selectIngredientGrade(
                parentName: parentName,
                ingredientName: ingredientName,
                grade: grades[index].$1,
              ),
            ),
            if (index != grades.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _QualityButton extends StatelessWidget {
  const _QualityButton({
    required this.label,
    required this.grade,
    required this.normalIsBlueFamily,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final String grade;
  final bool normalIsBlueFamily;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final (fill, restingBorder) = _qualitySwatchColors(
      grade,
      normalIsBlueFamily: normalIsBlueFamily,
    );
    final outerRadius = BorderRadius.circular(ledger ? 2 : 5);
    final innerRadius = BorderRadius.circular(ledger ? 1 : 3);

    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label quality',
        child: InkWell(
          onTap: onPressed,
          borderRadius: outerRadius,
          child: Container(
            width: spec.usesDenseSplitLayout ? 26 : 24,
            height: spec.usesDenseSplitLayout ? 26 : 24,
            decoration: BoxDecoration(
              gradient: ledger
                  ? _ledgerRaisedVellumGradient
                  : sakura
                  ? SakuraNightGardenSpec.raisedSurfaceGradient
                  : StandardSpec.glassGradient(
                      topAlpha: selected ? 74 : 42,
                      bottomAlpha: selected ? 28 : 12,
                    ),
              borderRadius: outerRadius,
              border: Border.all(
                color: ledger
                    ? selected
                          ? const Color(0xFFD2B15A)
                          : const Color(0x8A7A5B2A)
                    : sakura
                    ? selected
                          ? spec.palette.primaryBright
                          : spec.palette.trim.withAlpha(154)
                    : selected
                    ? const Color(0xB8FFE7A3)
                    : const Color(0x664E8A77),
              ),
            ),
            alignment: Alignment.center,
            child: Container(
              width: spec.usesDenseSplitLayout ? 12 : 16,
              height: spec.usesDenseSplitLayout ? 12 : 16,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: innerRadius,
                border: Border.all(
                  color: selected
                      ? ledger
                            ? const Color(0xFF7C5B24)
                            : sakura
                            ? spec.palette.text
                            : const Color(0xFFFFF0B9)
                      : restingBorder,
                  width: selected ? 2 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _ledgerRaisedVellumGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: <Color>[Color(0xFFF8EAC8), Color(0xFFEBD4A3), Color(0xFFD8BC83)],
  stops: <double>[0, .62, 1],
);

(Color, Color) _qualitySwatchColors(
  String grade, {
  required bool normalIsBlueFamily,
}) => switch (grade) {
  'high' => (const Color(0xAA6FC17A), const Color(0xB9A9E890)),
  'special' => (const Color(0xAA558FD5), const Color(0xB9A8C8FF)),
  'blue' => (const Color(0xAA4D73D2), const Color(0xB9BBCDFF)),
  _ when normalIsBlueFamily => (
    const Color(0xAA4FAF72),
    const Color(0xB9A9E890),
  ),
  _ => (const Color(0xAA909090), const Color(0xB9CBCBCB)),
};

class _MarketPills extends StatelessWidget {
  const _MarketPills({required this.row, required this.suppressCentralMarket});

  final MissingMaterial row;
  final bool suppressCentralMarket;

  @override
  Widget build(BuildContext context) {
    final market = row.market;
    final pills = <Widget>[];
    if (_hasVendorSourcePills(market)) {
      pills.add(
        const _StatusPill(label: 'Vendor item', tone: AppSurfaceTone.neutral),
      );
      pills.add(
        _StatusPill(
          label: market.price > 0
              ? '${formatSilver(market.price)} each'
              : 'No price',
          tone: AppSurfaceTone.info,
        ),
      );
      pills.add(
        _StatusPill(
          label: market.price > 0
              ? 'Total ${formatSilver(market.total)}'
              : 'Total -',
          tone: AppSurfaceTone.neutral,
        ),
      );
    } else if (!suppressCentralMarket) {
      final stockTone = !market.stockKnown
          ? AppSurfaceTone.info
          : market.stock >= row.missing
          ? AppSurfaceTone.success
          : market.stock > 0
          ? AppSurfaceTone.warning
          : AppSurfaceTone.danger;
      pills.add(
        _StatusPill(
          label: !market.stockKnown
              ? 'Stock unknown'
              : market.stock > 0
              ? '${formatQuantity(market.stock)} in stock'
              : '0 in stock',
          tone: stockTone,
        ),
      );
      pills.add(
        _StatusPill(
          label: market.price > 0
              ? '${formatSilver(market.price)} each'
              : 'No price',
          tone: AppSurfaceTone.info,
        ),
      );
      pills.add(
        _StatusPill(
          label: market.price > 0
              ? 'Total ${formatSilver(market.stockKnown ? market.total : row.missing * market.price)}'
              : 'Total -',
          tone: AppSurfaceTone.neutral,
        ),
      );
    }
    return Wrap(spacing: 6, runSpacing: 4, children: pills);
  }
}

bool _hasMarketPills(
  MissingMaterial row, {
  required bool suppressCentralMarket,
}) =>
    _hasVendorSourcePills(row.market) ||
    (row.market.marketable && !suppressCentralMarket);

bool _hasVendorSourcePills(MarketMaterialState market) =>
    market.hasSourceInfo && market.status == 'vendor';

bool _isConfirmedMarketUnlisted(
  Iterable<PlannerMarketRowDiagnostic> diagnostics,
) => diagnostics.any((diagnostic) => diagnostic.isMarketUnlisted);

const _confirmedMarketUnlistedDiagnostic = PlannerMarketRowDiagnostic(
  message: "Can't be registered on the Central Market.",
  severity: PlannerMarketDiagnosticSeverity.info,
  isMarketUnlisted: true,
);

List<PlannerMarketRowDiagnostic> _withConfirmedMarketUnlistedDiagnostic(
  List<PlannerMarketRowDiagnostic> diagnostics, {
  required bool confirmed,
}) {
  if (!confirmed || _isConfirmedMarketUnlisted(diagnostics)) {
    return diagnostics;
  }
  return List<PlannerMarketRowDiagnostic>.unmodifiable(
    <PlannerMarketRowDiagnostic>[
      _confirmedMarketUnlistedDiagnostic,
      ...diagnostics,
    ],
  );
}

class _MarketDiagnostics extends StatelessWidget {
  const _MarketDiagnostics({required this.diagnostics});

  final List<PlannerMarketRowDiagnostic> diagnostics;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < diagnostics.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(height: 5),
          Semantics(
            label: 'Market diagnostic: ${diagnostics[index].message}',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: spec.palette
                    .forTone(_diagnosticTone(diagnostics[index].severity))
                    .withAlpha(32),
                borderRadius: BorderRadius.circular(spec.geometry.cardRadius),
                border: Border.all(
                  color: spec.palette
                      .forTone(_diagnosticTone(diagnostics[index].severity))
                      .withAlpha(128),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  diagnostics[index].message,
                  style: spec.typography.meta.copyWith(
                    color: spec.palette.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MarketSummary extends StatelessWidget {
  const _MarketSummary({
    required this.plan,
    required this.message,
    required this.loading,
    required this.fetchedAt,
    required this.region,
  });

  final PlanResult plan;
  final String? message;
  final bool loading;
  final int fetchedAt;
  final String region;

  @override
  Widget build(BuildContext context) {
    final total = plan.missing.fold<double>(
      0,
      (value, row) => value + row.market.total,
    );
    final trimmedMessage = message?.trim() ?? '';
    final meta = trimmedMessage;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: AppSurface(
        role: AppSurfaceRole.row,
        tone: loading ? AppSurfaceTone.info : AppSurfaceTone.neutral,
        semanticLabel: 'Market price summary',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Estimated Cost',
                    style: context.visualTheme.typography.label,
                  ),
                  Text(
                    formatSilver(total),
                    style: context.visualTheme.typography.section.copyWith(
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    'Last fetched ${formatMarketFetchedAt(fetchedAt)} · '
                    'Region ${region.trim().isEmpty ? '—' : region.toUpperCase()}',
                    style: context.visualTheme.typography.meta,
                  ),
                ],
              ),
            ),
            if (meta.isNotEmpty) ...<Widget>[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  meta,
                  textAlign: TextAlign.right,
                  style: context.visualTheme.typography.meta.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.tone});

  final String label;
  final AppSurfaceTone tone;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final standard = spec.isStandard;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final color = spec.palette.forTone(tone);
    final fill = standard
        ? switch (tone) {
            AppSurfaceTone.success => const Color(0x97306F43),
            AppSurfaceTone.warning => const Color(0x925D4A25),
            AppSurfaceTone.danger => const Color(0x98553532),
            AppSurfaceTone.info => const Color(0x87224E48),
            AppSurfaceTone.neutral => const Color(0x7E4D4720),
          }
        : ledger
        ? switch (tone) {
            AppSurfaceTone.success => const Color(0xFFDDE6C7),
            AppSurfaceTone.warning => const Color(0xFFEEE0B7),
            AppSurfaceTone.danger => const Color(0xFFEACDC4),
            AppSurfaceTone.info => const Color(0xFFD9DFD2),
            AppSurfaceTone.neutral => const Color(0xFFE4D6B5),
          }
        : sakura
        ? switch (tone) {
            AppSurfaceTone.success => const Color(0x66424E3E),
            AppSurfaceTone.warning => const Color(0x664E382E),
            AppSurfaceTone.danger => const Color(0x66542A39),
            AppSurfaceTone.info => const Color(0x663A3544),
            AppSurfaceTone.neutral => const Color(0x66342B32),
          }
        : color.withAlpha(42);
    final outline = standard
        ? switch (tone) {
            AppSurfaceTone.success => const Color(0xC27EE18D),
            AppSurfaceTone.warning => const Color(0xC2D4AE55),
            AppSurfaceTone.danger => const Color(0xC8D98278),
            AppSurfaceTone.info => const Color(0xB06FE6D1),
            AppSurfaceTone.neutral => const Color(0xB6D8C66E),
          }
        : ledger
        ? switch (tone) {
            AppSurfaceTone.success => const Color(0x7D647B35),
            AppSurfaceTone.warning => const Color(0x8EB9903E),
            AppSurfaceTone.danger => const Color(0x9DA45648),
            AppSurfaceTone.info => const Color(0x726B765A),
            AppSurfaceTone.neutral => const Color(0x7D8A6A32),
          }
        : sakura
        ? color.withAlpha(190)
        : color.withAlpha(144);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(
          standard
              ? 999
              : ledger
              ? 2
              : 5,
        ),
        border: Border.all(color: outline),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: standard ? 9 : 8,
          vertical: standard ? 4 : 2,
        ),
        child: Text(
          label,
          style: spec.typography.meta.copyWith(
            color: standard
                ? tone == AppSurfaceTone.danger
                      ? const Color(0xFFFFD2C8)
                      : const Color(0xFFFFF0B8)
                : ledger
                ? const Color(0xFF6A5230)
                : sakura
                ? spec.palette.text
                : tone == AppSurfaceTone.neutral
                ? spec.palette.textMuted
                : color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            fontStyle: standard ? null : FontStyle.normal,
            height: standard ? null : 1.1,
          ),
        ),
      ),
    );
  }
}

class _MethodPill extends StatelessWidget {
  const _MethodPill({required this.recipe});

  final Recipe? recipe;

  @override
  Widget build(BuildContext context) {
    final method = recipe?.method?.trim();
    final type = recipe?.type.replaceAll('_', ' ').trim();
    final label = method != null && method.isNotEmpty
        ? _displayMethod(method)
        : type != null && type.isNotEmpty
        ? _displayMethod(type)
        : 'Recipe';
    return Align(
      alignment: Alignment.centerLeft,
      child: _StatusPill(
        label: label,
        tone: recipe?.type == 'processing'
            ? AppSurfaceTone.info
            : AppSurfaceTone.warning,
      ),
    );
  }
}

String _displayMethod(String method) {
  final normalized = method.replaceAll('_', ' ').trim();
  return switch (normalized.toLowerCase()) {
    'alchemy' => 'Residence Alchemy',
    'cooking' => 'Cooking',
    _ => normalized,
  };
}

class _CopyNameButton extends StatelessWidget {
  const _CopyNameButton({
    required this.name,
    required this.semanticPrefix,
    required this.onCopy,
    this.fontSize,
    this.color,
    super.key,
  });

  final String name;
  final String semanticPrefix;
  final CopyPlannerName onCopy;
  final double? fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    return Semantics(
      button: true,
      label: '$semanticPrefix $name',
      child: InkWell(
        onTap: () async => onCopy(name),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: EdgeInsets.zero,
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: spec.typography.body.copyWith(
              color: ledger ? const Color(0xFF6B2E29) : color,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              height: spec.usesDenseSplitLayout ? 1.15 : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlannerEmpty extends StatelessWidget {
  const _PlannerEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      liveRegion: true,
      label: message,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: context.visualTheme.typography.body.copyWith(
            color: context.visualTheme.palette.textMuted,
          ),
        ),
      ),
    ),
  );
}

class PlannerItemIcon extends StatelessWidget {
  const PlannerItemIcon({
    required this.controller,
    required this.name,
    this.size = 42,
    super.key,
  });

  final ModeFeatureController controller;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) =>
      ModeItemIcon(controller: controller, name: name, size: size);
}

Recipe? _resolveRecipe(ModeFeatureController controller, String name) {
  return controller.selectedRecipe(name);
}

Ingredient? _resolveIngredient(
  ModeFeatureController controller,
  String parentName,
  String original,
  String group,
) {
  final recipe = _resolveRecipe(controller, parentName);
  if (recipe == null) return null;
  for (final ingredient in recipe.ingredients) {
    if (_sameFolded(ingredient.name, original) ||
        _sameFolded(ingredient.substituteGroup ?? ingredient.name, group)) {
      return ingredient;
    }
  }
  return null;
}

List<PlanStepIngredient> _incomingSubstituteSources(
  PlanResult plan,
  String stepName,
) {
  final incoming = <String, List<PlanStepIngredient>>{};
  for (final parentStep in plan.steps) {
    for (final ingredient in parentStep.ingredients) {
      if (!ingredient.craftable) continue;
      incoming
          .putIfAbsent(
            ingredient.name.trim().toLowerCase(),
            () => <PlanStepIngredient>[],
          )
          .add(ingredient);
    }
  }

  final matches = <String, PlanStepIngredient>{};
  final pending = <String>[stepName.trim().toLowerCase()];
  final visited = <String>{};
  while (pending.isNotEmpty) {
    final childName = pending.removeLast();
    if (!visited.add(childName)) continue;
    final sources = incoming[childName];
    if (sources == null) continue;
    for (final ingredient in sources) {
      if (ingredient.options.length < 2) {
        pending.add(ingredient.parentName.trim().toLowerCase());
        continue;
      }
      final identity = <String>[
        ingredient.parentName,
        ingredient.substituteGroup,
        ingredient.original,
      ].map((value) => value.trim().toLowerCase()).join('\u0000');
      matches[identity] = ingredient;
    }
  }
  final result = matches.values.toList(growable: false);
  result.sort((left, right) {
    final parent = left.parentName.toLowerCase().compareTo(
      right.parentName.toLowerCase(),
    );
    if (parent != 0) return parent;
    return left.substituteGroup.toLowerCase().compareTo(
      right.substituteGroup.toLowerCase(),
    );
  });
  return result;
}

PlannerSourceInfoRequest _sourceInfo(
  ModeFeatureController controller,
  MissingMaterial row,
) {
  final recipe = _resolveRecipe(controller, row.name);
  final source = controller.resolveItemSource(row.name, recipe: recipe);
  final vendor = source.vendor?.trim();
  final acquisition = controller.resolveItemAcquisition(row.name);
  final npcPurchaseSummaries = acquisition == null
      ? const <String>[]
      : acquisition.routes
            .where(
              (route) =>
                  route.isDisplayable &&
                  route.kind.trim().toLowerCase() == 'npc_purchase',
            )
            .map((route) => route.summary.trim())
            .where((summary) => summary.isNotEmpty)
            .toList(growable: false);
  if ((vendor == null || vendor.isEmpty) && npcPurchaseSummaries.isEmpty) {
    return PlannerSourceInfoRequest(
      name: row.name,
      category: recipe?.group?.trim().isNotEmpty == true
          ? recipe!.group!.trim()
          : row.category,
      role: '',
      sourceNote: null,
      vendor: null,
      location: null,
      npcPrice: 0,
    );
  }
  final sourceNotes = <String>[];

  void addSourceNote(String? candidate) {
    final note = candidate?.trim();
    if (note == null || note.isEmpty) return;
    if (sourceNotes.any(
      (existing) =>
          _containsFoldedText(existing, note) ||
          _containsFoldedText(note, existing),
    )) {
      return;
    }
    sourceNotes.add(note);
  }

  if (vendor != null && vendor.isNotEmpty) {
    addSourceNote(source.sourceNote);
  }
  for (final summary in npcPurchaseSummaries) {
    addSourceNote(summary);
  }
  return PlannerSourceInfoRequest(
    name: row.name,
    category: recipe?.group?.trim().isNotEmpty == true
        ? recipe!.group!.trim()
        : row.category,
    role: source.role ?? '',
    sourceNote: sourceNotes.isEmpty ? null : sourceNotes.join('\n'),
    vendor: vendor,
    location: source.location,
    npcPrice: source.npcPrice,
  );
}

String _sourceInfoText(PlannerSourceInfoRequest request) {
  final lines = <String>[];
  final note = request.sourceNote?.trim();
  if (note != null && note.isNotEmpty) lines.add(note);

  final vendor = request.vendor?.trim();
  final location = request.location?.trim();
  if (vendor != null && vendor.isNotEmpty) {
    lines.add(
      'Vendor: $vendor'
      '${location != null && location.isNotEmpty ? ' - $location' : ''}',
    );
  } else if (location != null && location.isNotEmpty) {
    lines.add('Location: $location');
  }

  final role = request.role.trim();
  if (role.isNotEmpty &&
      !lines.any((line) => _containsFoldedText(line, role))) {
    lines.add(role);
  }
  return lines.isEmpty
      ? 'No saved source details for ${request.name}.'
      : lines.join('\n');
}

List<(String, String)> _qualityGrades(
  ModeFeatureController controller,
  String parentName,
  String baseName,
) => controller
    .availableIngredientGrades(parentName: parentName, selectedName: baseName)
    .map(
      (grade) => (
        grade,
        switch (grade) {
          'high' => 'High Grade',
          'special' => 'Special Grade',
          'blue' => 'Blue Grade',
          _ => 'Normal',
        },
      ),
    )
    .toList(growable: false);

String _selectedSubstituteFor({
  required ModeFeatureController controller,
  required String parentName,
  required String currentName,
  required Ingredient ingredient,
}) {
  final key =
      'recipe:$parentName:${ingredient.substituteGroup ?? ingredient.name}';
  return _stringFor(controller.state.value.substituteChoices, key) ??
      currentName;
}

String? _stringFor(Map<String, String> values, String key) {
  final exact = values[key];
  if (exact != null) return exact;
  for (final entry in values.entries) {
    if (_sameFolded(entry.key, key)) return entry.value;
  }
  return null;
}

double _ratioFor(Ingredient ingredient, String option) {
  final value = _numberFor(ingredient.substituteRatios, option);
  return value > 0 ? value : 1;
}

double _numberFor(Map<String, double> values, String name) {
  final exact = values[name];
  if (exact != null) return exact;
  for (final entry in values.entries) {
    if (_sameFolded(entry.key, name)) return entry.value;
  }
  return 0;
}

List<String> _distinctFolded(Iterable<String> values) {
  final seen = <String>{};
  return values
      .where((value) => value.trim().isNotEmpty)
      .where((value) => seen.add(value.trim().toLowerCase()))
      .toList(growable: false);
}

bool _containsFolded(Iterable<String> values, String name) =>
    values.any((value) => _sameFolded(value, name));

List<PlannerMarketRowDiagnostic> _marketDiagnosticsFor(
  Map<String, List<PlannerMarketRowDiagnostic>> values,
  String name,
) {
  final exact = values[name];
  if (exact != null) return exact;
  for (final entry in values.entries) {
    if (_sameFolded(entry.key, name)) return entry.value;
  }
  return const <PlannerMarketRowDiagnostic>[];
}

bool _sameFolded(String left, String right) =>
    left.trim().toLowerCase() == right.trim().toLowerCase();

bool _containsFoldedText(String? value, String part) =>
    value != null &&
    value.trim().toLowerCase().contains(part.trim().toLowerCase());

AppSurfaceTone _toneFor(MissingMaterial row) => switch (row.market.status) {
  'ready' || 'covered' => AppSurfaceTone.success,
  'partial' || 'priced' => AppSurfaceTone.warning,
  'vendor' => AppSurfaceTone.info,
  _ => AppSurfaceTone.danger,
};

AppSurfaceTone _diagnosticTone(PlannerMarketDiagnosticSeverity severity) =>
    switch (severity) {
      PlannerMarketDiagnosticSeverity.info => AppSurfaceTone.info,
      PlannerMarketDiagnosticSeverity.warning => AppSurfaceTone.warning,
      PlannerMarketDiagnosticSeverity.error => AppSurfaceTone.danger,
    };
