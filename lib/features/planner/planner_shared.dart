import 'dart:async';

import 'package:bdo_craft_planner_flutter/visual/components/app_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/state/planner_application_controller.dart';
import '../../app/workspace/planner_gather_checklist_bridge.dart'
    show gatherNeededForPlan;
import '../../data/catalog/catalog_repository.dart';
import '../../data/opportunities/market_eligibility.dart';
import '../../domain/catalog/item_name_presentation.dart';
import '../../domain/catalog/temporarily_archived_items.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/planner/afk_weight_calculator.dart';
import '../../domain/planner/ingredient_quality.dart';
import '../../domain/planner/planner_models.dart';
import '../../domain/planner/reviewed_recipe_yields.dart';
import '../../domain/state/actual_batch_output.dart';
import '../../domain/state/craft_completion.dart';
import '../../domain/state/planner_state.dart';
import '../../shared/overlays/anchored_popover.dart';
import '../../visual/components/app_interaction_frame.dart';
import '../../visual/components/app_number_fade.dart';
import '../../visual/illuminated_ledger/ledger_ornament_painters.dart';
import '../../visual/visual.dart';
import '../opportunities/opportunity_silver_amount.dart';
import '../recipe_book/recipe_book_controller.dart';
import '../recipe_book/recipe_book_item_info.dart';
import '../recipe_book/recipe_book_item_info_view.dart';
import '../shared/market_region_selector.dart';
import '../shared/mode_item_icon.dart';
import '../shared/profile_game_icon.dart';
import '../shared/quality_grade_button.dart';
import '../shared/recipe_variant_selector.dart';
import '../shared/source_availability_badges.dart';
import '../shared/workshop_presentation.dart';
import 'need_material_order.dart';
import 'planner_completed_projection.dart';
import 'planner_contracts.dart';
import 'planner_inventory_input.dart';
import 'planner_keys.dart';
import 'planner_map_menu_presentation.dart';
import 'planner_market_summary.dart';
import 'planner_quantity_layout.dart';
import 'planner_review_panels.dart';

typedef SelectPlannerTarget = bool Function(String name);

typedef PlannerTargetOptionBuilder =
    Widget Function(
      BuildContext context,
      String name,
      bool selected,
      VoidCallback onSelected,
    );

typedef PlannerTargetFieldBuilder =
    Widget Function(
      BuildContext context,
      TextEditingController controller,
      FocusNode focusNode,
      ValueChanged<String> onChanged,
      VoidCallback onTap,
      ValueChanged<String> onSubmitted,
      FocusOnKeyEventCallback onKeyEvent,
      VoidCallback? onClear,
    );

/// Compact desktop height shared by the Standard Planner command controls.
///
/// Passing this into the field itself is important: a taller parent alone does
/// not make [InputDecorator]'s painted container consume the available space.
const double plannerStandardCommandControlHeight = 46;

/// Balanced selected-target label size for the taller Standard command field.
const double plannerStandardTargetFontSize = 16;

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
    this.hintText = 'Search craftable recipes',
    this.emptyText = 'No matching craftable recipes',
    this.popupWidth = 460,
    this.popupMaxHeight = 420,
    this.itemIconBuilder,
    this.optionBuilder,
    this.fieldBuilder,
    this.allowEmptySelection = false,
    super.key,
  }) : assert(popupWidth > 0),
       assert(popupMaxHeight > 0);

  final ModeFeatureController controller;
  final PlannerCommandTarget target;
  final String semanticLabel;
  final Key actionKey;
  final double? controlHeight;
  final String hintText;
  final String emptyText;
  final double popupWidth;
  final double popupMaxHeight;
  final Widget Function(BuildContext context, String name)? itemIconBuilder;
  final PlannerTargetOptionBuilder? optionBuilder;
  final PlannerTargetFieldBuilder? fieldBuilder;

  /// Optional material pickers may clear their target; Planner targets may not.
  final bool allowEmptySelection;

  @override
  State<PlannerTargetChooser> createState() => _PlannerTargetChooserState();
}

class _PlannerTargetChooserState extends State<PlannerTargetChooser> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  late final TextEditingController _text = TextEditingController(
    text: itemDisplayName(widget.target.value),
  );
  late final FocusNode _focus = FocusNode()..addListener(_focusChanged);
  int _highlighted = 0;
  bool _suppressAutomaticShow = false;

  List<String> get _matches {
    final query = _text.text.trim().toLowerCase();
    if (query.isEmpty) return widget.target.names;
    return widget.target.names
        .where((name) => itemDisplayName(name).toLowerCase().contains(query))
        .toList(growable: false);
  }

  @override
  void didUpdateWidget(PlannerTargetChooser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus &&
        _text.text != itemDisplayName(widget.target.value)) {
      _text.text = itemDisplayName(widget.target.value);
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
      if (_suppressAutomaticShow) return;
      _show();
      return;
    }
    // Menu buttons take focus on mouse-down. Keep the overlay and query intact
    // until the option receives mouse-up and completes its selection.
    if (_portal.isShowing) return;
    _suppressAutomaticShow = false;
    _commitOrRestore();
  }

  void _commitOrRestore() {
    final selected = widget.target.onSelected(stableItemName(_text.text));
    if (!selected) _text.text = itemDisplayName(widget.target.value);
  }

  void _show() {
    if (!_portal.isShowing) _portal.show();
  }

  void _showFromUser() {
    _suppressAutomaticShow = false;
    _show();
  }

  void _filterChanged(String _) {
    _suppressAutomaticShow = false;
    setState(() => _highlighted = 0);
    _show();
  }

  void _select(String name) {
    // The target commit rebuilds the planner synchronously. Suppress focus-
    // driven reopening before that commit starts; otherwise Windows can return
    // focus to the field during the rebuild and leave a one-item menu behind.
    _suppressAutomaticShow = true;
    if (!widget.target.onSelected(name)) {
      _suppressAutomaticShow = false;
      return;
    }
    _text.text = itemDisplayName(name);
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
    _portal.hide();
    if (!_focus.hasFocus) _focus.requestFocus();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final matches = _matches;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (matches.isNotEmpty) {
        _suppressAutomaticShow = false;
        setState(() => _highlighted = (_highlighted + 1) % matches.length);
        _show();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (matches.isNotEmpty) {
        _suppressAutomaticShow = false;
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
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _submit(_text.text);
      _portal.hide();
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  void _submit(String value) {
    // Keep an explicitly cleared picker empty on Tab/Enter. Opening its list
    // again (including with arrow keys) still selects the highlighted option.
    if (widget.allowEmptySelection &&
        value.trim().isEmpty &&
        !_portal.isShowing) {
      _clear();
      return;
    }
    final matches = _matches;
    final exact = widget.target.names.where(
      (name) =>
          name.toLowerCase() == stableItemName(value).trim().toLowerCase(),
    );
    if (exact.isNotEmpty) {
      _select(exact.first);
    } else if (matches.isNotEmpty) {
      _select(matches[_highlighted.clamp(0, matches.length - 1)]);
    }
  }

  void _clear() {
    _highlighted = 0;
    _select('');
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
                width: widget.popupWidth,
                height: (matches.length * 66 + 16)
                    .clamp(82, double.infinity)
                    .clamp(0, widget.popupMaxHeight)
                    .toDouble(),
                child: TapRegion(
                  groupId: this,
                  onTapOutside: (_) {
                    _portal.hide();
                    _commitOrRestore();
                  },
                  child: AppSurface(
                    role: AppSurfaceRole.popup,
                    semanticLabel: '${widget.semanticLabel} choices',
                    padding: const EdgeInsets.all(8),
                    child: matches.isEmpty
                        ? Center(
                            child: Text(
                              widget.emptyText,
                              style: spec.typography.body,
                            ),
                          )
                        : ListView.builder(
                            itemCount: matches.length,
                            itemBuilder: (context, index) {
                              final name = matches[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child:
                                    widget.optionBuilder?.call(
                                      context,
                                      name,
                                      index == _highlighted,
                                      () => _select(name),
                                    ) ??
                                    AppButton(
                                      selected: index == _highlighted,
                                      role: AppButtonRole.navigation,
                                      minimumSize: const Size.fromHeight(60),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      semanticLabel: 'Select $name',
                                      onPressed: () => _select(name),
                                      child: Row(
                                        children: <Widget>[
                                          widget.itemIconBuilder?.call(
                                                context,
                                                name,
                                              ) ??
                                              PlannerItemIcon(
                                                controller: widget.controller,
                                                name: name,
                                                size: 42,
                                              ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              itemDisplayName(name),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: spec.typography.body
                                                  .copyWith(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                    height: 1.15,
                                                  ),
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
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _showFromUser(),
              child:
                  widget.fieldBuilder?.call(
                    context,
                    _text,
                    _focus,
                    _filterChanged,
                    _showFromUser,
                    _submit,
                    _handleKey,
                    widget.allowEmptySelection ? _clear : null,
                  ) ??
                  PlannerTextField(
                    controller: _text,
                    focusNode: _focus,
                    hintText: widget.hintText,
                    semanticLabel: widget.semanticLabel,
                    suffix: Icon(
                      Icons.expand_more,
                      color: spec.palette.textMuted,
                      size: 22,
                    ),
                    onChanged: _filterChanged,
                    onTap: _showFromUser,
                    onSubmitted: _submit,
                    onKeyEvent: _handleKey,
                    fontSize: denseLayout ? 15 : plannerStandardTargetFontSize,
                    fontWeight: FontWeight.w700,
                    minimumHeight: widget.controlHeight,
                  ),
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

class PlannerTextField extends StatefulWidget {
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
    this.onTap,
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
  final VoidCallback? onTap;
  final ValueChanged<String>? onSubmitted;
  final FocusOnKeyEventCallback? onKeyEvent;

  @override
  State<PlannerTextField> createState() => _PlannerTextFieldState();

  Widget _buildField(
    BuildContext context,
    ScrollController textScroll,
    FocusNode? resolvedFocus,
    double textOpacity,
  ) {
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
      scrollController: textScroll,
      focusNode: resolvedFocus,
      keyboardType: keyboardType,
      textAlign: textAlign,
      textAlignVertical: TextAlignVertical.center,
      onChanged: onChanged,
      onTap: onTap,
      onSubmitted: onSubmitted,
      style: spec.typography.body.copyWith(
        color: textOpacity == 1
            ? null
            : (spec.typography.body.color ?? spec.palette.text).withValues(
                alpha:
                    (spec.typography.body.color ?? spec.palette.text).a *
                    textOpacity,
              ),
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

class _PlannerTextFieldState extends State<PlannerTextField> {
  // A numeric editor must not restore its containing list's vertical offset
  // as horizontal text scroll when a lazy row first enters the viewport.
  final _textScroll = ScrollController(keepScrollOffset: false);

  @override
  void dispose() {
    _textScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.keyboardType?.index == TextInputType.number.index
      ? AppNumberFade(
          controller: widget.controller,
          focusNode: widget.focusNode,
          builder: (focus, opacity) =>
              widget._buildField(context, _textScroll, focus, opacity),
        )
      : widget._buildField(context, _textScroll, widget.focusNode, 1);
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
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.visible,
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

class _PlannerPlanColumnsState extends State<PlannerPlanColumns>
    with SingleTickerProviderStateMixin {
  final ScrollController _queueScroll = ScrollController();
  final ScrollController _needScroll = ScrollController();
  final NeedMaterialOrder _needMaterialOrder = NeedMaterialOrder();
  final Map<String, TextEditingController> _ownedDraftControllers =
      <String, TextEditingController>{};
  String? _openChoiceAnchor;
  String? _changedSubstitute;
  late final AnimationController _choiceMotion = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 150),
  );
  late final CurvedAnimation _choiceCurve = CurvedAnimation(
    parent: _choiceMotion,
    curve: Curves.easeOutCubic,
  );
  late final Animation<double> _choiceStrength = Tween<double>(
    begin: 1,
    end: 0,
  ).animate(_choiceCurve);
  String? _marketMessage;
  Map<String, List<PlannerMarketRowDiagnostic>> _marketRowDiagnostics =
      const <String, List<PlannerMarketRowDiagnostic>>{};
  bool _marketLoading = false;
  bool _adoptMarketOrderWhenReady = false;
  Map<String, String> _previousGrades = const {};
  Map<String, String> _previousSubstitutes = const {};
  final Set<String> _pendingChoiceRefresh = {};
  bool _choiceRefreshScheduled = false;

  @override
  void initState() {
    super.initState();
    _rememberChoices();
    widget.controller.state.addListener(_choicesChanged);
  }

  void _rememberChoices() {
    _previousGrades = widget.controller.state.value.ingredientGrades;
    _previousSubstitutes = widget.controller.state.value.substituteChoices;
  }

  void _choicesChanged() {
    final state = widget.controller.state.value;
    for (final pair in [
      (_previousGrades, state.ingredientGrades),
      (_previousSubstitutes, state.substituteChoices),
    ]) {
      for (final key in {...pair.$1.keys, ...pair.$2.keys}) {
        if (pair.$1[key] != pair.$2[key]) {
          _pendingChoiceRefresh.add(key.toLowerCase());
        }
      }
    }
    _rememberChoices();
    if (_pendingChoiceRefresh.isEmpty || !widget.allowMarketActions) return;
    _adoptMarketOrderWhenReady = false;
    _scheduleChoiceRefresh();
  }

  void _scheduleChoiceRefresh() {
    if (_choiceRefreshScheduled || _marketLoading || !mounted) return;
    _choiceRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _choiceRefreshScheduled = false;
      if (!mounted || _marketLoading || _pendingChoiceRefresh.isEmpty) return;
      final keys = Set<String>.of(_pendingChoiceRefresh);
      _pendingChoiceRefresh.clear();
      final names = <String>{
        for (final step in widget.plan.steps)
          for (final ingredient in step.ingredients)
            if (keys.contains(
                  'recipe:${step.name}:${ingredient.original}'.toLowerCase(),
                ) ||
                keys.contains(
                  'recipe:${step.name}:${ingredient.substituteGroup}'
                      .toLowerCase(),
                ) ||
                keys.contains(ingredient.baseName.toLowerCase()))
              ingredient.name,
      };
      if (names.isNotEmpty) unawaited(_checkPrices(selectedNames: names));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didUpdateWidget(PlannerPlanColumns oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.state.removeListener(_choicesChanged);
      widget.controller.state.addListener(_choicesChanged);
      _pendingChoiceRefresh.clear();
      _rememberChoices();
    }
    final targetChanged = !_sameFolded(
      oldWidget.plan.target,
      widget.plan.target,
    );
    final resetIdentityChanged =
        oldWidget.scrollResetIdentity != widget.scrollResetIdentity;
    if (!targetChanged && !resetIdentityChanged) {
      // A quality changes the row name and quantity too. Keep that row where
      // the user clicked, including materials without substitute metadata.
      if (_pendingChoiceRefresh.isNotEmpty) {
        for (final before in oldWidget.plan.steps.expand(
          (step) => step.ingredients,
        )) {
          final key = 'recipe:${before.parentName}:${before.original}'
              .toLowerCase();
          if (!_pendingChoiceRefresh.contains(key)) continue;
          final after = widget.plan.steps
              .expand((step) => step.ingredients)
              .where(
                (item) =>
                    _sameFolded(item.parentName, before.parentName) &&
                    _sameFolded(item.original, before.original),
              )
              .firstOrNull;
          if (after == null || _sameFolded(before.name, after.name)) continue;
          if (!widget.plan.missing.any(
            (row) => _sameFolded(row.name, after.name),
          )) {
            continue;
          }
          _needMaterialOrder.stageSubstituteChoice(
            parentName: before.parentName,
            original: before.original,
            substituteGroup: before.substituteGroup,
            sourceName: before.name,
            sourceBaseName: before.name,
            selection: after.name,
          );
        }
      }
      return;
    }

    _openChoiceAnchor = null;
    _changedSubstitute = null;
    _choiceMotion.value = 1;
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
    widget.controller.state.removeListener(_choicesChanged);
    _choiceCurve.dispose();
    _choiceMotion.dispose();
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
    _showSubstituteFeedback(selection);
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
    _showSubstituteFeedback(selection);
  }

  void _showSubstituteFeedback(String selection) {
    setState(() => _changedSubstitute = selection);
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _choiceMotion.value = 1;
    } else {
      _choiceMotion.forward(from: 0);
    }
  }

  Future<void> _checkPrices({Set<String>? selectedNames}) async {
    if (_marketLoading) return;
    final controller = widget.controller;
    final region = controller.state.value.market.region;
    setState(() {
      _adoptMarketOrderWhenReady = selectedNames == null;
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
          materials: selectedNames == null ? widget.plan.missing : const [],
          forceRefresh: selectedNames != null,
          includeAlternatives: selectedNames == null,
          materialNames:
              selectedNames?.toList() ??
              widget.controller
                  .recipeRouteMarketNamesForPlan(widget.plan)
                  .toList(),
        ),
      );
      if (!mounted ||
          widget.controller != controller ||
          controller.state.value.market.region != region ||
          result.region != region) {
        return;
      }
      controller.replaceMarketValues(
        prices: result.prices,
        stock: result.stock,
        preorderPrices: result.preorderPrices,
        preorderObservedAt: result.preorderObservedAt,
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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Market check failed. Previous prices were kept.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _marketLoading = false);
        if (_pendingChoiceRefresh.isNotEmpty) _scheduleChoiceRefresh();
      }
    }
  }

  void _hidePrices() {
    widget.controller.setPricesVisible(false);
    setState(() => _marketMessage = null);
  }

  void _changeMarketRegion(String region) {
    if (_marketLoading || !widget.controller.setMarketRegion(region)) return;
    setState(() {
      _marketMessage = null;
      _marketRowDiagnostics = const {};
      _adoptMarketOrderWhenReady = false;
      _needMaterialOrder.reset();
    });
    if (widget.controller.priceRowsVisible.value) _checkPrices();
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
    final denseLayout = context.visualTheme.usesDenseSplitLayout;
    // Viewport changes only rearrange these panels. Their data and controls
    // should rebuild on state changes, not every pixel of a window drag.
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
        onRegionChanged: _changeMarketRegion,
        openChoiceAnchor: _openChoiceAnchor,
        onSubstituteSelected: _stageNeedSubstitute,
        onChoiceAnchorChanged: (value) =>
            setState(() => _openChoiceAnchor = value),
      ),
    );
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 760;
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
    return KeyedSubtree(
      key: widget.actionKey,
      child: _PlannerGatherScope(
        controller: widget.controller,
        plan: widget.plan,
        bonusPlan: widget.bonusPlan,
        child: _PlannerChoiceFeedbackScope(
          name: _changedSubstitute,
          strength: _choiceStrength,
          child: content,
        ),
      ),
    );
  }
}

class _PlannerChoiceFeedbackScope extends InheritedWidget {
  const _PlannerChoiceFeedbackScope({
    required this.name,
    required this.strength,
    required super.child,
  });

  final String? name;
  final Animation<double> strength;

  @override
  bool updateShouldNotify(_PlannerChoiceFeedbackScope oldWidget) =>
      name != oldWidget.name || strength != oldWidget.strength;
}

/// Paint-only feedback: values, focus and hit testing change immediately.
class _PlannerChoiceFeedback extends StatelessWidget {
  const _PlannerChoiceFeedback({required this.name, required this.child});

  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_PlannerChoiceFeedbackScope>();
    if (scope?.name == null ||
        !_sameFolded(scope!.name!, name) ||
        MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    final spec = context.visualTheme;
    return AnimatedBuilder(
      key: ValueKey<String>('planner-choice-feedback:$name'),
      animation: scope.strength,
      child: child,
      builder: (context, child) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          color: spec.palette.primaryBright.withValues(
            alpha: .08 * scope.strength.value,
          ),
          border: Border.all(
            color: spec.palette.primaryBright.withValues(
              alpha: .34 * scope.strength.value,
            ),
          ),
          borderRadius: BorderRadius.circular(spec.geometry.cardRadius),
        ),
        child: child,
      ),
    );
  }
}

class _QueuePanel extends StatefulWidget {
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
  State<_QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<_QueuePanel> {
  bool _completedExpanded = false;
  final _completedProjection = PlannerCompletedProjection();
  Set<String> _observedCompleted = const {};

  @override
  void initState() {
    super.initState();
    _rememberCompleted();
  }

  void _rememberCompleted() {
    _observedCompleted = {
      for (final name in widget.controller.state.value.completedSteps)
        name.trim().toLowerCase(),
    };
  }

  @override
  void didUpdateWidget(_QueuePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final completed = widget.controller.state.value.completedSteps;
    final newCompletion = completed.any(
      (name) => !_observedCompleted.contains(name.trim().toLowerCase()),
    );
    final restarted = _observedCompleted.isNotEmpty && completed.isEmpty;
    if (oldWidget.controller != widget.controller ||
        !_sameFolded(oldWidget.plan.target, widget.plan.target) ||
        oldWidget.plan.want != widget.plan.want ||
        oldWidget.bonusPlan != widget.bonusPlan ||
        newCompletion ||
        restarted) {
      _completedExpanded = false;
    }
    _rememberCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final plan = widget.plan;
    final steps = widget.steps;
    final allowCompletion = widget.allowCompletion;
    final bonusPlan = widget.bonusPlan;
    final title = widget.title;
    final countNoun = widget.countNoun;
    final scrollController = widget.scrollController;
    final completedNames =
        PlannerQuantityLayout.of(context) && allowCompletion && !bonusPlan
        ? _completedProjection.namesFor(controller)
        : const <String>[];
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final denseLayout = spec.usesDenseSplitLayout;
    final trailing = Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (completedNames.isNotEmpty)
          _CompletedCraftDisclosure(
            controller: controller,
            names: completedNames,
            expanded: _completedExpanded,
            onPressed: () =>
                setState(() => _completedExpanded = !_completedExpanded),
          ),
        if (controller.canUndoCompletion())
          PlannerUndoReview(
            controller: controller,
            onConflict: () => _showCompletionUndoConflict(context),
            anchorBuilder: (context, toggle, showing) => AppButton.label(
              'Undo',
              key: const ValueKey<String>('planner-undo-completion'),
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              semanticLabel:
                  'Undo completion of ${controller.lastCompletionName}',
              tooltip: 'Undo ${controller.lastCompletionName}',
              onPressed: toggle,
            ),
          ),
        if (allowCompletion)
          AppButton.label(
            'Restart queue',
            key: PlannerActionKeys.p07,
            role: ledger ? AppButtonRole.primary : AppButtonRole.secondary,
            minimumSize: Size(denseLayout ? 76 : 66, 38),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            semanticLabel: 'Restart queue and clear all completed-step marks',
            tooltip: 'Show the full queue again without changing owned items',
            onPressed: () {
              setState(() => _completedExpanded = false);
              controller.resetCompleted();
            },
          ),
      ],
    );
    final queueList = NotificationListener<ScrollStartNotification>(
      onNotification: (_) {
        AppOverlayCoordinatorScope.maybeOf(context)?.dismissTop();
        return false;
      },
      child: _QueuePresentationList(
        controller: controller,
        steps: steps,
        completedNames: _completedExpanded ? completedNames : const [],
        scrollController: scrollController,
        identity: (controller, plan.target, plan.want, bonusPlan),
        itemBuilder: (context, step, index, onComplete) {
          final completed = _containsFolded(
            controller.state.value.completedSteps,
            step.name,
          );
          return Padding(
            key: ValueKey<String>(
              '${onComplete == null ? 'completed-queue-content' : 'queue'}:${step.name}',
            ),
            padding: EdgeInsets.only(
              bottom: index + 1 < steps.length ? (denseLayout ? 8 : 14) : 0,
              right: denseLayout ? 8 : 0,
            ),
            child: _PlannerChoiceFeedback(
              name: step.name,
              child: _QueueStepCard(
                controller: controller,
                step: step,
                titleSubstituteSources: _incomingSubstituteSources(
                  plan,
                  step.name,
                ),
                index: index,
                completed: completed,
                expanded: widget.isExpanded(step, index),
                allowCompletion: allowCompletion,
                sessionTargetName: plan.target,
                sessionTargetAmount: plan.want,
                bonusPlan: bonusPlan,
                externalActions: widget.externalActions,
                openChoiceAnchor: widget.openChoiceAnchor,
                onSubstituteSelected: widget.onSubstituteSelected,
                onChoiceAnchorChanged: widget.onChoiceAnchorChanged,
                onToggleExpanded: () => widget.onToggleExpanded(step, index),
                onComplete: onComplete,
              ),
            ),
          );
        },
      ),
    );
    final queueListWithoutPlatformScrollbar = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: queueList,
    );
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: AppSurface(
        role: AppSurfaceRole.layout,
        semanticLabel: title,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LayoutBuilder(
              key: const ValueKey('planner-queue-header'),
              builder: (context, constraints) {
                // Keep the normal inline header, but give its extra actions
                // a bounded wrapping row when the compact pane cannot fit them.
                final wrapActions =
                    completedNames.isNotEmpty && constraints.maxWidth < 520;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeader(
                      title: title,
                      meta: bonusPlan
                          ? '${plan.steps.length} $countNoun'
                          : null,
                      trailing: wrapActions ? null : trailing,
                      prioritizeTitle: true,
                    ),
                    if (wrapActions) ...[
                      const SizedBox(height: 6),
                      Align(alignment: Alignment.centerRight, child: trailing),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Expanded(child: queueListWithoutPlatformScrollbar),
          ],
        ),
      ),
    );
  }
}

/// Compact disclosure of covered crafts in this queue, not all owned stock.
/// Artwork is decoration for this one keyboard-accessible button, not a second
/// click target or a second inventory editor.
class _CompletedCraftDisclosure extends StatelessWidget {
  const _CompletedCraftDisclosure({
    required this.controller,
    required this.names,
    required this.expanded,
    required this.onPressed,
  });

  final ModeFeatureController controller;
  final List<String> names;
  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final previews = names.take(3).toList(growable: false);
    return Semantics(
      expanded: expanded,
      child: AppButton(
        key: const ValueKey<String>('planner-completed-disclosure'),
        role: AppButtonRole.infoChip,
        selected: expanded,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        semanticLabel:
            '${expanded ? 'Hide' : 'Show'} ${names.length} covered or completed ${names.length == 1 ? 'step' : 'steps'} in this queue',
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: IgnorePointer(
                child: SizedBox(
                  width: 22 + (previews.length - 1) * 15,
                  height: 22,
                  child: Stack(
                    children: [
                      for (var i = 0; i < previews.length; i++)
                        Positioned(
                          left: i * 15,
                          top: 0,
                          child: ModeItemIcon(
                            key: ValueKey<String>(
                              'planner-completed-preview:${previews[i]}',
                            ),
                            controller: controller,
                            name: previews[i],
                            size: 22,
                            searchAcrossModes: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              'Completed ${names.length}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 3),
            Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 16),
          ],
        ),
      ),
    );
  }
}

typedef _QueuePresentationBuilder =
    Widget Function(
      BuildContext context,
      PlanStep step,
      int index,
      VoidCallback? onComplete,
    );

/// Keeps only a short, non-interactive success presentation after the actual
/// completion transaction has already updated the plan and shared inventory.
class _QueuePresentationList extends StatefulWidget {
  const _QueuePresentationList({
    required this.controller,
    required this.steps,
    required this.completedNames,
    required this.scrollController,
    required this.identity,
    required this.itemBuilder,
  });

  final ModeFeatureController controller;
  final List<PlanStep> steps;
  final List<String> completedNames;
  final ScrollController scrollController;
  final Object identity;
  final _QueuePresentationBuilder itemBuilder;

  @override
  State<_QueuePresentationList> createState() => _QueuePresentationListState();
}

class _QueuePresentationListState extends State<_QueuePresentationList> {
  final Map<String, ({PlanStep step, int index})> _completed = {};
  bool _motion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (!_motion) _completed.clear();
  }

  @override
  void didUpdateWidget(_QueuePresentationList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _completed.clear();
      return;
    }
    _completed.removeWhere(
      (name, _) =>
          !_containsFolded(widget.controller.state.value.completedSteps, name),
    );
  }

  void _complete(PlanStep step, int index) {
    if (_completed.containsKey(step.name.toLowerCase())) return;
    // No animation or timer is allowed to defer or repeat this transaction.
    if (!widget.controller.completeStep(step) || !mounted || !_motion) return;
    AppOverlayCoordinatorScope.maybeOf(context)?.dismissTop();
    setState(() {
      _completed[step.name.toLowerCase()] = (step: step, index: index);
    });
  }

  void _finish(String name) {
    if (!mounted || !_completed.containsKey(name)) return;
    setState(() => _completed.remove(name));
  }

  @override
  Widget build(BuildContext context) {
    final rows = <({PlanStep step, int index, bool completed})>[
      for (var index = 0; index < widget.steps.length; index++)
        (step: widget.steps[index], index: index, completed: false),
    ];
    for (final entry in _completed.values) {
      final existing = rows.indexWhere(
        (row) => _sameFolded(row.step.name, entry.step.name),
      );
      final row = (step: entry.step, index: entry.index, completed: true);
      if (existing >= 0) {
        rows[existing] = row;
      } else {
        rows.insert(entry.index.clamp(0, rows.length), row);
      }
    }
    if (rows.isEmpty && widget.completedNames.isEmpty) {
      return const _PlannerEmpty(
        message:
            'No craft steps are needed for the current target and inventory.',
      );
    }
    return ListView.builder(
      key: const PageStorageKey<String>('planner-craft-queue'),
      controller: widget.scrollController,
      itemCount: rows.length + widget.completedNames.length,
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final completedIndex = widget.completedNames.indexWhere(
          (name) => key.value == 'planner-completed-step:$name',
        );
        if (completedIndex >= 0) return completedIndex;
        final index = rows.indexWhere(
          (row) => key.value == 'queue:${row.step.name}',
        );
        return index < 0 ? null : index + widget.completedNames.length;
      },
      itemBuilder: (context, index) {
        if (index < widget.completedNames.length) {
          final name = widget.completedNames[index];
          return _CompletedCraftRow(
            key: ValueKey('planner-completed-step:$name'),
            controller: widget.controller,
            name: name,
          );
        }
        final row = rows[index - widget.completedNames.length];
        final child = widget.itemBuilder(
          context,
          row.step,
          row.index,
          row.completed ? null : () => _complete(row.step, row.index),
        );
        if (!row.completed) return child;
        return _QueueCompletionMotion(
          key: ValueKey<String>('queue:${row.step.name}'),
          name: row.step.name,
          onFinish: () => _finish(row.step.name.toLowerCase()),
          child: child,
        );
      },
    );
  }
}

class _QueueCompletionMotion extends StatefulWidget {
  const _QueueCompletionMotion({
    required this.name,
    required this.onFinish,
    required this.child,
    super.key,
  });

  final String name;
  final VoidCallback onFinish;
  final Widget child;

  @override
  State<_QueueCompletionMotion> createState() => _QueueCompletionMotionState();
}

class _QueueCompletionMotionState extends State<_QueueCompletionMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 160),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onFinish();
      });
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: const Interval(.25, 1, curve: Curves.easeInOutCubic),
  );
  late final Animation<double> _remaining = Tween<double>(
    begin: 1,
    end: 0,
  ).animate(_curve);

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    key: ValueKey<String>('planner-completion-feedback:${widget.name}'),
    child: ExcludeFocus(
      child: ExcludeSemantics(
        child: SizeTransition(
          sizeFactor: _remaining,
          alignment: Alignment.topCenter,
          child: FadeTransition(opacity: _remaining, child: widget.child),
        ),
      ),
    ),
  );
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
    required this.onComplete,
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
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final denseLayout = spec.usesDenseSplitLayout;
    final recipe = _resolveRecipe(controller, step.name);
    final incomingChoices =
        <({PlanStepIngredient source, Ingredient ingredient})>[
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
    bool isDeclaredQuality(
      ({PlanStepIngredient source, Ingredient ingredient}) choice,
    ) =>
        controller.declaredBlueIngredientPair(
          parentName: choice.source.parentName,
          ingredientName: choice.source.original,
        ) !=
        null;
    final qualityTitleChoices = incomingChoices
        .where(isDeclaredQuality)
        .toList();
    final titleChoices = incomingChoices
        .where((choice) => !isDeclaredQuality(choice))
        .toList();
    final primaryTitleChoice = titleChoices.isEmpty ? null : titleChoices.first;
    final processingChoice = controller.optionalProcessingRecipe(step.name);
    final titleAnchor = titleChoices.isEmpty && processingChoice == null
        ? null
        : 'queue-title:${step.name}';
    final titleChooserOpen =
        titleAnchor != null && openChoiceAnchor == titleAnchor;
    final hasVariants = recipe?.hasRecipeVariants ?? false;
    final routeSelection = hasVariants
        ? controller.recipeRouteSelection(step.name, requestedOutput: step.net)
        : null;
    final hasAutomaticRoutes = routeSelection?.hasComparison ?? false;
    final showTotalIngredients = recipe?.type == 'processing';
    final outputNote = recipe == null ? null : reviewedRecipeYieldNote(recipe);
    final ownedLayout = PlannerQuantityLayout.of(context);
    final cardInset = denseLayout ? 10.0 : 14.0;
    final variants = hasVariants
        ? RecipeVariantSelector(
            recipe: recipe!,
            selectedVariantId: controller.selectedRecipeVariantId(step.name),
            compact: denseLayout,
            isAutomatic:
                hasAutomaticRoutes && (routeSelection?.isAutomatic ?? false),
            onAutomaticSelected: hasAutomaticRoutes
                ? () => controller.selectAutomaticRecipeRoute(step.name)
                : null,
            onBatchSelected:
                hasAutomaticRoutes && routeSelection?.isAutomatic == true
                ? (batch) => controller.selectAutomaticRecipeRoute(
                    step.name,
                    batchMultiplier: batch,
                  )
                : null,
            onSelected: (variantId) => controller.selectRecipeVariant(
              recipeName: step.name,
              variantId: variantId,
            ),
          )
        : null;
    final summary = showTotalIngredients && step.batchSize == 1
        ? '${formatQuantity(step.count)} ${step.count == 1 ? 'batch' : 'batches'} · '
              'Makes ${formatQuantity(step.produced)} · '
              'Need ${formatQuantity(step.demand)}'
        : step.batchSize > 1
        ? 'Craft ${formatQuantity(step.count)} | '
              'Mass batches ${formatQuantity(step.batchCount)} x${step.batchSize} | '
              'Results in ${formatQuantity(step.produced)} | '
              'Need ${formatQuantity(step.demand)}'
        : 'Craft ${formatQuantity(step.count)} | '
              'Results in ${formatQuantity(step.produced)} | '
              'Need ${formatQuantity(step.demand)}';
    return AppInteractionFrame(
      selected: expanded && !completed,
      radius: 8,
      child: AppSurface(
        role: AppSurfaceRole.card,
        padding: ownedLayout ? EdgeInsets.zero : null,
        ornamentIndex: index,
        tone: completed
            ? AppSurfaceTone.success
            : step.ingredients.any((ingredient) => ingredient.missing > 0)
            ? AppSurfaceTone.warning
            : AppSurfaceTone.neutral,
        semanticLabel:
            '${step.name} craft step${completed ? ', completed' : ''}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: ownedLayout
                  ? EdgeInsets.fromLTRB(
                      cardInset,
                      cardInset,
                      cardInset,
                      expanded ? 0 : cardInset,
                    )
                  : EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (ownedLayout && variants != null) ...[
                    Align(alignment: Alignment.centerRight, child: variants),
                    const SizedBox(height: 10),
                  ],
                  ConstrainedBox(
                    key: ValueKey('planner-queue-heading:${step.name}'),
                    constraints: BoxConstraints(
                      minHeight: ownedLayout
                          ? 54
                          : denseLayout
                          ? 84
                          : 88,
                    ),
                    child: Row(
                      crossAxisAlignment: ownedLayout
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                      children: <Widget>[
                        if (ownedLayout)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: PlannerInventoryInput(
                              controller: controller,
                              itemName: step.name,
                              iconSize: denseLayout ? 48 : 54,
                              iconBuilder: (size) => PlannerItemIcon(
                                key: ValueKey(
                                  'planner-queue-icon:${step.name}',
                                ),
                                controller: controller,
                                name: step.name,
                                size: size,
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            key: ValueKey('planner-queue-icon:${step.name}'),
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
                              if (primaryTitleChoice != null ||
                                  processingChoice != null)
                                _CopyAndSwapName(
                                  onCopy: externalActions.copyName,
                                  swapKey: PlannerActionKeys.row(
                                    'P12',
                                    titleAnchor!,
                                  ),
                                  nameKey: PlannerActionKeys.row(
                                    'P10',
                                    step.name,
                                  ),
                                  name: step.name,
                                  fontSize: denseLayout ? 18 : 19,
                                  isShowing: titleChooserOpen,
                                  semanticLabel: primaryTitleChoice == null
                                      ? 'Choose how to get ${step.name}'
                                      : titleChoices.length > 1
                                      ? 'Choose recipe substitutions affecting '
                                            '${step.name}; ${titleChoices.length} '
                                            'choices; '
                                            '${titleChooserOpen ? 'open' : 'closed'}'
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
                              if (qualityTitleChoices.isEmpty)
                                _MethodPill(recipe: recipe)
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _MethodPill(recipe: recipe),
                                    for (final choice in qualityTitleChoices)
                                      _QualitySwatches(
                                        controller: controller,
                                        parentName: choice.source.parentName,
                                        ingredientName: choice.source.original,
                                        baseName: choice.source.baseName,
                                        selectedGrade: choice.source.grade,
                                        keyScope: 'queue-title:',
                                      ),
                                  ],
                                ),
                              if (ownedLayout) ...[
                                const SizedBox(height: 12),
                                PlannerCraftQuantities(step: step),
                              ],
                              if (hasVariants && !ownedLayout) ...<Widget>[
                                SizedBox(height: denseLayout ? 12 : 14),
                                variants!,
                              ],
                              if (routeSelection != null &&
                                  routeSelection.hasComparison) ...<Widget>[
                                const SizedBox(height: 6),
                                RecipeRouteCostComparison(
                                  selection: routeSelection,
                                  itemIconBuilder: (name, size) =>
                                      PlannerItemIcon(
                                        controller: controller,
                                        name: name,
                                        size: size,
                                      ),
                                ),
                              ],
                              if (!ownedLayout) ...[
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
                                    fontStyle: denseLayout
                                        ? FontStyle.normal
                                        : null,
                                    height: denseLayout ? 1.15 : null,
                                  ),
                                ),
                              ],
                              if (outputNote != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  outputNote,
                                  key: ValueKey(
                                    'planner-output-note:${step.name}',
                                  ),
                                  style: spec.typography.meta.copyWith(
                                    color: spec.palette.textMuted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (allowCompletion) ...<Widget>[
                          const SizedBox(width: 8),
                          AppCompletionControl(
                            key: PlannerActionKeys.row('P08', step.name),
                            completed: completed,
                            semanticLabel: completed
                                ? '${step.name} is done'
                                : 'Done with ${step.name}',
                            onPressed: completed ? null : onComplete,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (ownedLayout) ...[
                    const SizedBox(height: 12),
                    const WorkshopSectionRule(),
                  ],
                  if (titleChooserOpen) ...<Widget>[
                    SizedBox(height: denseLayout ? 5 : 7),
                    Padding(
                      padding: EdgeInsets.only(left: denseLayout ? 61 : 70),
                      child: titleChoices.isEmpty
                          ? _InlineSubstituteChooser(
                              controller: controller,
                              parentName: step.name,
                              currentName: step.name,
                              ingredient: _acquisitionAnchorIngredient(
                                step.name,
                              ),
                              onClose: () => onChoiceAnchorChanged(null),
                            )
                          : _QueueTitleSubstituteChooser(
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
                ],
              ),
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
                    _QueueIngredientBand(
                      key: ValueKey(
                        'planner-ingredient-band:${step.name}:$ingredientIndex',
                      ),
                      index: ingredientIndex,
                      last: ingredientIndex == step.ingredients.length - 1,
                      child: _PlannerChoiceFeedback(
                        name: step.ingredients[ingredientIndex].baseName,
                        child: _IngredientRow(
                          controller: controller,
                          ingredient: step.ingredients[ingredientIndex],
                          externalActions: externalActions,
                          openChoiceAnchor: openChoiceAnchor,
                          onSubstituteSelected: onSubstituteSelected,
                          onChoiceAnchorChanged: onChoiceAnchorChanged,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width alternating rows are part of the queue card, not nested cards.
/// Other shared callers (including Bonus) retain their existing spacing.
class _QueueIngredientBand extends StatelessWidget {
  const _QueueIngredientBand({
    required this.index,
    required this.last,
    required this.child,
    super.key,
  });

  final int index;
  final bool last;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final dense = spec.usesDenseSplitLayout;
    if (!PlannerQuantityLayout.of(context)) {
      return Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : (dense ? 6 : 8)),
        child: child,
      );
    }
    final base = spec.palette.surface;
    final light = base.computeLuminance() > .35;
    final stripe = Color.alphaBlend(
      spec.palette.primary.withValues(alpha: light ? .13 : .20),
      base,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: index.isEven ? stripe : base,
        borderRadius: last
            ? BorderRadius.vertical(
                bottom: Radius.circular(spec.geometry.cardRadius),
              )
            : BorderRadius.zero,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14, vertical: 7),
        child: child,
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
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final enlargement = textScale > 1.25 ? textScale : 1.0;
    final preferredWidth = (denseLayout ? 156.0 : 188.0) * enlargement;
    final height = (denseLayout ? 36.0 : 38.0) * enlargement;
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
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<AfkWeightProfile>(
    valueListenable: controller.owner.afkWeightProfile,
    builder: (context, profile, _) {
      final denseLayout = context.visualTheme.usesDenseSplitLayout;
      final height = denseLayout ? 36.0 : 38.0;
      return AnchoredPopover(
        overlayId: 'afk-load:${controller.mode.key}:${step.name}',
        preferredWidth: 736,
        maximumHeight: 680,
        margin: 22,
        gap: 12,
        placement: AnchoredPopoverPlacement.beside,
        consumeOutsideTap: true,
        popoverBuilder: (context, close) =>
            NotificationListener<ScrollNotification>(
              // OverlayPortal retains the queue's notification ancestors. Only
              // scrolling that underlying queue should dismiss this popup.
              onNotification: (_) => true,
              child: _AfkLoadCard(
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
                'AFK Weight for ${step.name}, '
                '${isShowing ? 'open' : 'closed'}',
            tooltip: 'Plan ingredients around your character weight',
            onPressed: toggle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ProfileIcon(
                  artwork: ProfileArtwork.weight,
                  size: showLabel ? 19 : 22,
                ),
                if (showLabel) ...<Widget>[
                  const SizedBox(width: 6),
                  const Text(
                    'AFK Weight',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(fontWeight: FontWeight.w700),
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

void _showCompletionUndoConflict(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(
      content: Text('Cannot undo: these items or the plan changed afterwards.'),
    ),
  );
}

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
  final _actualOutput = TextEditingController();
  String? _draftBatchKey;
  String? _outputError;
  bool _confirmLowOutput = false;

  @override
  void dispose() {
    _actualOutput.dispose();
    super.dispose();
  }

  void _clearOutput() {
    _actualOutput.clear();
    _outputError = null;
    _confirmLowOutput = false;
  }

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

  AfkCraftProgress _progress({int attemptsPerRound = 0}) =>
      controller.inventoryBatchProgress(
        step: step,
        target: widget.sessionTargetName,
        want: widget.sessionTargetAmount,
        progressKey: _progressKey,
        attemptsPerRound: attemptsPerRound,
      );

  AfkWeightSessionPlan _calculate({required int completedAttempts}) =>
      const AfkWeightCalculator().calculateSessionPlan(
        mode: controller.mode,
        step: scaleCraftStep(step, _progress().totalAttempts.toDouble()),
        recipe: recipe,
        rules: controller.owner.plannerRules,
        profile: profile,
        completedAttempts: completedAttempts,
        expectedOutputPerAttempt: step.count > 0
            ? step.produced / step.count
            : null,
      );

  void _completeLoad(AfkWeightSessionLoad load, {bool confirmed = false}) {
    final actual = parseActualBatchOutput(_actualOutput.text);
    if (actual == null) {
      setState(() => _outputError = 'Enter a whole amount, or leave blank.');
      return;
    }
    final expected = step.produced / step.count * load.attempts;
    if (!confirmed && actualBatchOutputNeedsConfirmation(actual, expected)) {
      setState(() => _confirmLowOutput = true);
      return;
    }
    final session = _calculate(completedAttempts: 0);
    final saved = controller.completeInventoryBatch(
      step: step,
      progress: _progress(attemptsPerRound: session.maxAttemptsPerLoad),
      completedBefore: load.completedAttemptsBefore,
      completedAfter: load.completedAttemptsAfter,
      bonus: widget.bonusPlan,
      actualOutput: actual,
      lowOutputConfirmed: confirmed,
    );
    if (mounted) {
      setState(() {
        if (saved) {
          _clearOutput();
        } else {
          _confirmLowOutput = false;
          _outputError = 'The batch changed. Check the amount and try again.';
        }
      });
    }
  }

  void _undoLoad() {
    if (!controller.undoCompletion(progressKey: _progressKey)) {
      _showCompletionUndoConflict(context);
    } else {
      setState(_clearOutput);
    }
  }

  void _resetProgress() {
    if (!controller.undoAllInventoryBatches(_progressKey)) {
      _showCompletionUndoConflict(context);
    } else {
      setState(_clearOutput);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => AppSurface(
        role: AppSurfaceRole.popup,
        padding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        semanticLabel: 'AFK Weight plan for ${recipe.name}',
        child: ValueListenableBuilder<ModeState>(
          valueListenable: controller.state,
          builder: (context, state, _) {
            final initialSession = _calculate(completedAttempts: 0);
            final progress = _progress(
              attemptsPerRound: initialSession.maxAttemptsPerLoad,
            );
            final session = _calculate(
              completedAttempts: progress.completedAttempts,
            );
            final showModes =
                profile.isConfigured &&
                session.maximumCapacity.available &&
                session.maxAttemptsPerLoad > 0;
            if (showModes && !session.complete && session.loadCount > 0) {
              final availableHeight = constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : 680.0;
              return _splitPlan(
                context,
                session,
                progress,
                availableHeight: availableHeight,
              );
            }

            final body = !profile.isConfigured
                ? _unconfigured(context)
                : !showModes
                ? _unavailable(context, session.maximumCapacity)
                : _needed(context, session, progress);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _header(context),
                ),
                const SizedBox(height: 11),
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    key: ValueKey<String>(
                      'planner-afk-scroll:${_mode.name}:'
                      '${session.completedAttempts}:${session.complete}',
                    ),
                    primary: false,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: body,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _splitPlan(
    BuildContext context,
    AfkWeightSessionPlan session,
    AfkCraftProgress? progress, {
    required double availableHeight,
  }) {
    final needed = _mode == _AfkLoadMode.needed;
    final completed = progress?.completedAttempts ?? 0;
    final total = session.requestedAttempts;
    final load = session.loadAt(0);
    final batchKey =
        '$_progressKey:${widget.sessionTargetAmount}:'
        '${controller.afkPlanSignature(step)}:${step.count}:${step.net}:'
        '$completed:${session.maxAttemptsPerLoad}:${load.attempts}';
    if (_draftBatchKey != batchKey) {
      _draftBatchKey = batchKey;
      _clearOutput();
    }
    final capacity = session.maximumCapacity;
    final stacks = needed ? load.ingredientStacks : capacity.ingredientStacks;
    final crafts = needed ? load.attempts : capacity.safeAttempts;
    final massCycles = needed ? load.massBatches : capacity.safeMassBatches;
    final totalBatches = session.maxAttemptsPerLoad <= 0
        ? 0
        : (total + session.maxAttemptsPerLoad - 1) ~/
              session.maxAttemptsPerLoad;
    final startWeight = needed ? load.startLoadLt : capacity.startLoadLt;
    final expectedOutput = needed
        ? load.expectedOutputStack
        : capacity.expectedOutputStack;
    final perAttemptQuantities = _perAttemptQuantities();
    final visibleRows = stacks.length.clamp(2, 6);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final scalingReserve = ((textScale - 1).clamp(0.0, 1.0)) * 260.0;
    final desiredHeight = 414.0 + (visibleRows - 2) * 62.0 + scalingReserve;
    final maxHeight = availableHeight.isFinite && availableHeight > 0
        ? availableHeight
        : 680.0;
    final height = desiredHeight.clamp(0.0, maxHeight).toDouble();
    final spec = context.visualTheme;
    final divider = spec.palette.trim.withAlpha(100);

    return SizedBox(
      key: const ValueKey<String>('planner-afk-split'),
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 270,
            child: DecoratedBox(
              key: const ValueKey<String>('planner-afk-dashboard'),
              decoration: BoxDecoration(
                color: spec.palette.surfaceRaised.withAlpha(188),
                border: Border(right: BorderSide(color: divider)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    key: const ValueKey<String>('planner-afk-dashboard-scroll'),
                    primary: false,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _splitRecipeHeader(context),
                            const SizedBox(height: 20),
                            _modeSelector(),
                            const SizedBox(height: 16),
                            Expanded(
                              child: _splitDashboardSummary(
                                context,
                                needed: needed,
                                crafts: crafts,
                                completed: completed,
                                total: total,
                                massCycles: massCycles,
                              ),
                            ),
                            _splitWeightSummary(
                              context,
                              startWeight: startWeight,
                              expectedOutput: expectedOutput,
                              conservative: capacity.usesConservativeOutput,
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
          Expanded(
            child: DecoratedBox(
              key: const ValueKey<String>('planner-afk-items-pane'),
              decoration: BoxDecoration(
                color: spec.palette.surfaceInset.withAlpha(118),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _splitItemsHeader(
                      context,
                      title: needed
                          ? 'Batch ${load.number} / $totalBatches'
                          : 'Estimated load',
                    ),
                    const SizedBox(height: 8),
                    _splitColumnLabels(
                      context,
                      totalHeading: needed ? 'BATCH TOTAL' : 'LOAD AMOUNT',
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: SingleChildScrollView(
                        key: ValueKey<String>(
                          'planner-afk-item-list:${_mode.name}:${load.number}',
                        ),
                        primary: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final stack in stacks)
                              _afkIngredientRow(
                                context,
                                stack,
                                perAttemptQuantities,
                                totalLabel: needed
                                    ? 'for this batch'
                                    : 'in estimated load',
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (needed) ...[
                      const SizedBox(height: 10),
                      _actualOutputRow(context, load),
                    ],
                    const SizedBox(height: 10),
                    _splitFooter(
                      needed: needed,
                      load: load,
                      completed: completed,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _splitRecipeHeader(BuildContext context) {
    final spec = context.visualTheme;
    return AnchoredPopoverDragRegion(
      key: const ValueKey<String>('planner-afk-drag-region'),
      child: Row(
        children: <Widget>[
          PlannerItemIcon(controller: controller, name: recipe.name, size: 58),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              itemDisplayName(recipe.name),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: spec.typography.section.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _splitDashboardSummary(
    BuildContext context, {
    required bool needed,
    required int crafts,
    required int completed,
    required int total,
    required int massCycles,
  }) {
    final spec = context.visualTheme;
    final fraction = needed
        ? total <= 0
              ? 0.0
              : (completed / total).clamp(0.0, 1.0)
        : 1.0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: spec.palette.trim.withAlpha(74)),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  formatQuantity(crafts.toDouble()),
                  key: ValueKey<String>(
                    needed
                        ? 'planner-afk-needed-attempts'
                        : 'planner-afk-safe-attempts',
                  ),
                  style: spec.typography.display.copyWith(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  needed ? 'crafts in this batch' : 'crafts in this load',
                  style: spec.typography.body.copyWith(
                    color: spec.palette.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (massCycles > 0) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    '${formatQuantity(massCycles.toDouble())} mass cycles '
                    'at x${step.batchSize}',
                    style: spec.typography.meta.copyWith(
                      color: spec.palette.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    needed
                        ? '${formatQuantity(completed.toDouble())} of '
                              '${formatQuantity(total.toDouble())} complete'
                        : 'One full load',
                    key: const ValueKey<String>('planner-afk-progress-copy'),
                    style: spec.typography.meta.copyWith(
                      color: spec.palette.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (needed)
                  Text(
                    '${(fraction * 100).round()}%',
                    key: const ValueKey<String>('planner-afk-progress-percent'),
                    style: spec.typography.meta.copyWith(
                      color: spec.palette.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            _AfkSessionProgress(
              completed: needed ? completed : 1,
              total: needed ? total : 1,
            ),
          ],
        ),
      ],
    );
  }

  Widget _splitWeightSummary(
    BuildContext context, {
    required double startWeight,
    required AfkLoadStack? expectedOutput,
    required bool conservative,
  }) {
    final spec = context.visualTheme;
    Widget metric(String label, String value, String key) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: spec.typography.meta.copyWith(fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              key: ValueKey<String>(key),
              textAlign: TextAlign.right,
              style: spec.typography.body.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return AppSurface(
      role: AppSurfaceRole.row,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          metric(
            'Ingredients',
            '${formatQuantity(startWeight)} LT',
            'planner-afk-total-weight',
          ),
          AppTooltip(
            message: expectedOutput == null
                ? 'No supported average is available for this recipe.'
                : 'About ${formatQuantity(expectedOutput.quantity.toDouble())} '
                      '${expectedOutput.itemName}. Main output only; extra drops '
                      'and current carried weight are not included.',
            child: metric(
              'Expected finish',
              expectedOutput == null
                  ? '—'
                  : '≈ ${formatQuantity(expectedOutput.loadLt)} LT',
              'planner-afk-expected-weight',
            ),
          ),
          metric(
            'Keep free',
            '${formatQuantity(profile.safetyBufferLt)} LT',
            'planner-afk-reserved-weight',
          ),
          const SizedBox(height: 4),
          AppTooltip(
            message: conservative
                ? 'The load uses a conservative main-output allowance because '
                      'output data is incomplete. Higher-grade results and '
                      'byproducts are not included; Keep free provides headroom, '
                      'not a guarantee. Expected finish is the main-item average.'
                : 'Recipe-average estimate, not a guaranteed maximum. '
                      'Ingredients are consumed as output accumulates. '
                      'Keep free is deducted once for variation and extra drops. '
                      'Your current carried weight is already allowed for.',
            child: Text(
              conservative
                  ? 'Conservative · extra drops unknown'
                  : 'Estimate · extra drops not included',
              key: const ValueKey<String>('planner-afk-estimate-note'),
              style: spec.typography.meta.copyWith(
                color: spec.palette.textMuted,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _splitItemsHeader(BuildContext context, {required String title}) {
    final spec = context.visualTheme;
    return Row(
      children: <Widget>[
        Expanded(
          child: AnchoredPopoverDragRegion(
            child: Text(
              title,
              key: const ValueKey<String>('planner-afk-round-label'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: spec.typography.section.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        AppButton(
          key: const ValueKey<String>('planner-afk-edit-profile'),
          role: AppButtonRole.icon,
          minimumSize: const Size(46, 40),
          padding: EdgeInsets.zero,
          tooltip: 'Edit weight settings',
          semanticLabel: 'Edit AFK weight settings',
          onPressed: externalActions.openAfkWeightSettings == null
              ? null
              : () {
                  onClose();
                  externalActions.openAfkWeightSettings!();
                },
          child: const Icon(Icons.tune_rounded, size: 18),
        ),
        const SizedBox(width: 6),
        AppButton(
          key: const ValueKey<String>('planner-afk-close'),
          role: AppButtonRole.icon,
          minimumSize: const Size(46, 40),
          padding: EdgeInsets.zero,
          tooltip: 'Close',
          semanticLabel: 'Close AFK Weight for ${recipe.name}',
          onPressed: onClose,
          child: const Icon(Icons.close_rounded, size: 20),
        ),
      ],
    );
  }

  Widget _splitColumnLabels(
    BuildContext context, {
    required String totalHeading,
  }) {
    final spec = context.visualTheme;
    final style = spec.typography.label.copyWith(
      color: spec.palette.textMuted,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: .35,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: <Widget>[
          Expanded(child: Text('ITEM', style: style)),
          SizedBox(
            width: 62,
            child: Text('EACH', textAlign: TextAlign.right, style: style),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(totalHeading, textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }

  Widget _splitFooter({
    required bool needed,
    required AfkWeightSessionLoad load,
    required int completed,
  }) {
    if (needed && _confirmLowOutput) {
      final expected = step.produced / step.count * load.attempts;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Below 80% of the estimate (${formatQuantity(expected)}). Keep this amount?',
            key: const ValueKey('planner-afk-output-warning'),
            style: context.visualTheme.typography.body.copyWith(
              color: context.visualTheme.palette.warning,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton.label(
                'Back',
                key: const ValueKey('planner-afk-output-back'),
                onPressed: () => setState(() => _confirmLowOutput = false),
              ),
              AppButton.label(
                'Keep amount',
                key: const ValueKey('planner-afk-output-confirm'),
                role: AppButtonRole.primary,
                onPressed: () => _completeLoad(load, confirmed: true),
              ),
            ],
          ),
        ],
      );
    }
    final finalAction = !needed || load.isFinal;
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        if (needed && completed > 0) ...<Widget>[
          AppButton.label(
            'Undo',
            key: const ValueKey<String>('planner-afk-undo-round'),
            minimumSize: const Size(84, 42),
            onPressed: controller.canUndoCompletion(progressKey: _progressKey)
                ? _undoLoad
                : null,
          ),
        ],
        SizedBox(
          width: 132,
          child: AppButton(
            key: const ValueKey<String>('planner-afk-complete-round'),
            role: AppButtonRole.primary,
            minimumSize: const Size(132, 46),
            semanticLabel: !needed
                ? 'Close maximum weight plan'
                : load.isFinal
                ? 'Finish this AFK Weight plan'
                : 'Mark this batch complete and show the next batch',
            onPressed: !needed ? onClose : () => _completeLoad(load),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(finalAction ? 'Done' : 'Next'),
                const SizedBox(width: 7),
                Icon(
                  finalAction ? Icons.check_rounded : Icons.arrow_forward,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  TextStyle _batchQuantityStyle(BuildContext context) => context
      .visualTheme
      .typography
      .body
      .copyWith(fontSize: 16, height: 1.2, fontWeight: FontWeight.w600);

  Widget _batchBand(BuildContext context, {required Widget child, Key? key}) =>
      Container(
        key: key,
        constraints: const BoxConstraints(minHeight: 54),
        color: Color.alphaBlend(
          context.visualTheme.palette.primary.withAlpha(16),
          context.visualTheme.palette.surfaceRaised.withAlpha(160),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: child,
      );

  Widget _actualOutputRow(BuildContext context, AfkWeightSessionLoad load) {
    final spec = context.visualTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Actually made',
          style: spec.typography.body.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _batchBand(
          context,
          key: const ValueKey('planner-afk-output-band'),
          child: Row(
            children: [
              PlannerItemIcon(
                controller: controller,
                name: recipe.name,
                size: 36,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  itemDisplayName(recipe.name),
                  style: spec.typography.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.18,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 100,
                child: Semantics(
                  label:
                      'Actually made ${recipe.name}. Blank or zero uses the estimate.',
                  child: TextField(
                    key: const ValueKey('planner-afk-actual-output'),
                    controller: _actualOutput,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    textAlignVertical: TextAlignVertical.center,
                    style: _batchQuantityStyle(context),
                    cursorColor: spec.palette.primaryBright,
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: _batchQuantityStyle(
                        context,
                      ).copyWith(color: spec.palette.textMuted),
                      isDense: true,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: InputBorder.none,
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: spec.palette.trim.withAlpha(160),
                        ),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: spec.palette.primaryBright,
                        ),
                      ),
                    ),
                    onChanged: (_) => setState(() {
                      _outputError = null;
                      _confirmLowOutput = false;
                    }),
                    // Enter finishes editing, never the batch. Completion is explicit.
                    onSubmitted: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_outputError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _outputError!,
              key: const ValueKey('planner-afk-output-error'),
              style: spec.typography.body.copyWith(color: spec.palette.warning),
            ),
          ),
      ],
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
                  size: 48,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    itemDisplayName(recipe.name),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: spec.typography.body.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
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
        AppButton.icon(
          key: const ValueKey<String>('planner-afk-close'),
          icon: const Icon(Icons.close_rounded, size: 20),
          tooltip: 'Close',
          semanticLabel: 'Close AFK Weight for ${recipe.name}',
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
    Map<String, double> quantities, {
    required String totalLabel,
  }) {
    final spec = context.visualTheme;
    final perAttempt = _perAttemptFor(stack, quantities);
    return Semantics(
      label:
          '${stack.itemName}, ${formatQuantity(perAttempt)} per craft, '
          '${formatQuantity(stack.quantity.toDouble())} $totalLabel',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: _batchBand(
            context,
            key: ValueKey('planner-afk-ingredient-band:${stack.itemName}'),
            child: Row(
              children: <Widget>[
                PlannerItemIcon(
                  controller: controller,
                  name: stack.itemName,
                  size: 36,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    stack.itemName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: spec.typography.body.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.18,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 62,
                  child: Text(
                    formatQuantity(perAttempt),
                    key: ValueKey<String>(
                      'planner-afk-per-craft:${stack.itemName}',
                    ),
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    style: _batchQuantityStyle(context),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 100,
                  child: Text(
                    formatQuantity(stack.quantity.toDouble()),
                    key: ValueKey<String>(
                      'planner-afk-total:${stack.itemName}',
                    ),
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    style: _batchQuantityStyle(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeSelector() => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: <Widget>[
      _modeButton(
        label: 'Needed',
        key: const ValueKey<String>('planner-afk-mode-needed'),
        mode: _AfkLoadMode.needed,
        tooltip: 'Only the items still needed',
      ),
      _modeButton(
        label: 'Load estimate',
        key: const ValueKey<String>('planner-afk-mode-maximum'),
        mode: _AfkLoadMode.maximum,
        tooltip: 'Estimated load with your Keep free reserve',
      ),
    ],
  );

  Widget _modeButton({
    required String label,
    required Key key,
    required _AfkLoadMode mode,
    required String tooltip,
  }) {
    final selected = _mode == mode;
    return AppButton(
      key: key,
      selected: selected,
      minimumSize: const Size(0, 34),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      tooltip: tooltip,
      semanticLabel: '$label, ${selected ? 'selected' : 'not selected'}',
      onPressed: () => setState(() => _mode = mode),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (selected) ...<Widget>[
            const Icon(Icons.check_rounded, size: 15),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: context.visualTheme.typography.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unconfigured(BuildContext context) {
    final spec = context.visualTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Add your character weight in Craft Profile to calculate each batch.',
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
              ? 'There is not enough free weight for this recipe.'
              : missing.isNotEmpty
              ? 'Missing weight data: ${missing.join(', ')}.'
              : 'This recipe does not have a usable amount.',
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
    if (session.complete) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSurface(
            role: AppSurfaceRole.row,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.task_alt_rounded,
                  size: 40,
                  color: spec.palette.success,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'All batches done',
                        style: spec.typography.section.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${formatQuantity(total.toDouble())} crafts completed',
                        style: spec.typography.meta.copyWith(
                          color: spec.palette.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _AfkSessionProgress(completed: total, total: total),
          const SizedBox(height: 13),
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton.label(
                  'Undo last batch',
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
    return _unavailable(context, session.maximumCapacity);
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
      label: '$completed of $total crafts complete',
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

class _PlannerGatherScope extends InheritedWidget {
  const _PlannerGatherScope({
    required this.controller,
    required this.plan,
    required this.bonusPlan,
    required super.child,
  });
  final ModeFeatureController controller;
  final PlanResult plan;
  final bool bonusPlan;

  PlannerGatherDemand demandFor(String name) {
    String identity(String value) => value.trim().toLowerCase();
    return PlannerGatherDemand(
      sourceId:
          'planner:${controller.mode.key}:${bonusPlan ? 'bonus' : 'plan'}:${plan.target.toLowerCase()}',
      sourceLabel: plan.target,
      materialName: name,
      neededQuantity: gatherNeededForPlan(plan, identity(name), identity),
      plannerMode: controller.mode,
      plannerTarget: plan.target,
      bonusPlan: bonusPlan,
    );
  }

  @override
  bool updateShouldNotify(_PlannerGatherScope oldWidget) =>
      oldWidget.plan != plan ||
      oldWidget.controller != controller ||
      oldWidget.bonusPlan != bonusPlan;
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
    final manualMaterialName = availability.manualMaterialName?.trim();
    final hasManualAlternative = manualMaterialName?.isNotEmpty == true;
    final manualDetail = hasManualAlternative
        ? 'Optional source for ${availability.materialName}'
        : availability.manualLocationCount > 0
        ? '${availability.manualLocationCount} mapped '
              '${availability.manualLocationCount == 1 ? 'location' : 'locations'}'
        : 'Open this material on the map';
    final manualActionLabel = hasManualAlternative
        ? 'Show $manualMaterialName'
        : availability.manualLocationCount > 0
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
    final menuWidth = plannerMapLookupMenuWidth(
      context: context,
      viewportSize: overlay.size,
      actionLabels: <String>[
        if (canOpenNpcVendors) 'Show NPC vendors',
        if (canOpenManual) manualActionLabel,
        if (canAddToChecklist) 'Add to to-do list',
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
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: PlannerMapMenuLabel(
              emblem: PlannerMapEmblem.npc,
              label: 'Show NPC vendors',
              detail: npcVendorDetail,
            ),
          ),
        if (canOpenNpcVendors && canOpenManual)
          const PopupMenuDivider(height: 1),
        if (canOpenManual)
          PopupMenuItem<_PlannerMapQuickAction>(
            key: PlannerActionKeys.mapLookupAction(
              widget.stableId,
              PlannerMapLookupSource.manualGathering.name,
            ),
            value: _PlannerMapQuickAction.manualGathering,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: PlannerMapMenuLabel(
              emblem: PlannerMapEmblem.gathering,
              label: manualActionLabel,
              detail: manualDetail,
            ),
          ),
        if ((canOpenNpcVendors || canOpenManual) &&
            (canAddToChecklist || canAddToPlannedNetwork))
          const PopupMenuDivider(height: 1),
        if (canAddToChecklist)
          PopupMenuItem<_PlannerMapQuickAction>(
            key: PlannerActionKeys.mapLookupAction(
              widget.stableId,
              'addToGatherChecklist',
            ),
            value: _PlannerMapQuickAction.addToGatherChecklist,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: const PlannerMapMenuLabel(
              emblem: PlannerMapEmblem.checklist,
              label: 'Add to to-do list',
              detail: checklistDetail,
            ),
          ),
        if (canAddToChecklist && canAddToPlannedNetwork)
          const PopupMenuDivider(height: 1),
        if (canAddToPlannedNetwork)
          PopupMenuItem<_PlannerMapQuickAction>(
            key: PlannerActionKeys.mapLookupAction(
              widget.stableId,
              'addToPlannedNetwork',
            ),
            value: _PlannerMapQuickAction.addToPlannedNetwork,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: PlannerMapMenuLabel(
              emblem: PlannerMapEmblem.network,
              label: 'Add to planned network',
              detail: plannedNetworkDetail,
            ),
          ),
      ],
    );
    if (selected == null || !mounted) return;
    if (selected == _PlannerMapQuickAction.addToGatherChecklist) {
      widget.externalActions.addToGatherChecklist?.call(
        PlannerGatherChecklistRequest(
          availability: availability,
          demand: context
              .getInheritedWidgetOfExactType<_PlannerGatherScope>()
              ?.demandFor(widget.materialName),
        ),
      );
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
        materialName:
            source == PlannerMapLookupSource.manualGathering &&
                hasManualAlternative
            ? manualMaterialName!
            : availability.materialName,
        resourceId: availability.resourceIdFor(source),
        source: source,
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
        domainIngredient != null &&
        ingredient.options.length > 1 &&
        controller.declaredBlueIngredientPair(
              parentName: ingredient.parentName,
              ingredientName: ingredient.original,
            ) ==
            null;
    final perCraftQuantity = domainIngredient == null
        ? null
        : controller
              .previewIngredientSelection(
                parentName: ingredient.parentName,
                ingredient: domainIngredient,
                selectedIngredient: ingredient,
              )
              .need;
    final stableId = '${ingredient.parentName}:${ingredient.key}';
    // Keep the right-aligned amount comfortably inside the card. Sakura's
    // fixed corner blossom occupies the final 54 px of the lowest row, so its
    // larger gutter also prevents short values from disappearing into it.
    final quantityRightInset = spec.isSakuraNightGarden
        ? SakuraQueueCornerAsset.authoredSize.width - 8
        : 18.0;
    final plannerLayout = PlannerQuantityLayout.of(context);
    final quantityStyle = spec.typography.meta.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: spec.palette.text,
      fontStyle: FontStyle.normal,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final perCraftValue = perCraftQuantity == null
        ? null
        : Text(
            'x${formatQuantity(perCraftQuantity)}',
            key: ValueKey<String>(
              'planner-ingredient-per-craft-quantity:'
              '${ingredient.parentName}:${ingredient.original}',
            ),
            style: plannerLayout
                ? quantityStyle
                : spec.typography.meta.copyWith(fontSize: 13),
          );
    final batchQuantity = Text(
      formatQuantity(ingredient.need),
      key: ValueKey<String>(
        'planner-ingredient-batch-quantity:'
        '${ingredient.parentName}:${ingredient.original}',
      ),
      style: plannerLayout
          ? quantityStyle
          : spec.typography.meta.copyWith(
              color: spec.palette.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
    );
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
            child: PlannerIngredientRowLayout(
              iconWidth: denseLayout ? 40 : 46,
              totalRightInset: quantityRightInset,
              showQuantityBadge: !plannerLayout,
              total: batchQuantity,
              icon: _ItemAcquisitionPopover(
                controller: controller,
                name: ingredient.name,
                stableId: '${ingredient.parentName}:${ingredient.key}',
                overlayScope: 'queue',
                size: denseLayout ? 40 : 46,
                showFrame: !plannerLayout,
                onOpening: () => onChoiceAnchorChanged(null),
              ),
              identity: PlannerIngredientIdentity(
                name: hasSubstitutes
                    ? PlannerOwnedChoices(
                        controller: controller,
                        parentName: ingredient.parentName,
                        ingredient: domainIngredient,
                        overlayScope: 'queue:$stableId',
                        options: _visibleSubstituteOptions(
                          controller,
                          domainIngredient,
                        ),
                        selected: _selectedSubstituteFor(
                          controller: controller,
                          parentName: ingredient.parentName,
                          currentName: ingredient.baseName,
                          ingredient: domainIngredient,
                        ),
                        beforeSelection: (selection) =>
                            onSubstituteSelected(ingredient, selection),
                        anchorBuilder: (context, toggle, showing) =>
                            _CopyAndSwapName(
                              onCopy: externalActions.copyName,
                              swapKey: PlannerActionKeys.row('P12', anchor),
                              nameKey: PlannerActionKeys.row(
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
                              isShowing: showing,
                              onToggle: () {
                                onChoiceAnchorChanged(null);
                                toggle();
                              },
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
                quantity: perCraftQuantity == null
                    ? null
                    : plannerLayout
                    ? Semantics(
                        label:
                            '${formatQuantity(perCraftQuantity)} needed for 1 craft',
                        excludeSemantics: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: perCraftValue,
                        ),
                      )
                    : AppTooltip(
                        message: 'Needed for 1 craft',
                        child: PlannerQuantityBadge(child: perCraftValue!),
                      ),
                quality:
                    _qualityGrades(
                      controller,
                      ingredient.parentName,
                      ingredient.baseName,
                    ).isEmpty
                    ? null
                    : _QualitySwatches(
                        controller: controller,
                        parentName: ingredient.parentName,
                        ingredientName: ingredient.original,
                        baseName: ingredient.baseName,
                        selectedGrade: ingredient.grade,
                      ),
              ),
            ),
          ),
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
    this.showFrame = true,
  });

  final ModeFeatureController controller;
  final String name;
  final String stableId;
  final String overlayScope;
  final double size;
  final VoidCallback onOpening;
  final bool showFrame;

  @override
  Widget build(BuildContext context) {
    final overlayId =
        '$overlayScope-acquisition:$stableId:${name.toLowerCase()}';
    return AnchoredPopover(
      overlayId: overlayId,
      preferredWidthBuilder: itemReferenceCardMaxWidth,
      contentSizedWidth: true,
      maximumHeight: itemReferenceCardHeight(context),
      margin: 24,
      gap: 12,
      placement: AnchoredPopoverPlacement.beside,
      consumeOutsideTap: true,
      popoverBuilder: (context, close) => _IngredientAcquisitionCard(
        controller: controller,
        stableId: stableId,
        name: name,
        onClose: close,
      ),
      anchorBuilder: (context, toggle, isShowing) => _IngredientInfoAnchor(
        key: PlannerActionKeys.row('P22', stableId),
        controller: controller,
        name: name,
        size: size,
        showFrame: showFrame,
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
    this.showFrame = true,
    super.key,
  });

  final ModeFeatureController controller;
  final String name;
  final double size;
  final bool isShowing;
  final VoidCallback onPressed;
  final bool showFrame;

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
              showFrame: showFrame,
            ),
          ),
        ),
      ),
    );
  }
}

/// A reference session exists only while its popup is mounted, not per row.
class _IngredientAcquisitionCard extends StatefulWidget {
  const _IngredientAcquisitionCard({
    required this.controller,
    required this.name,
    required this.stableId,
    required this.onClose,
  });

  final ModeFeatureController controller;
  final String name;
  final String stableId;
  final VoidCallback onClose;

  @override
  State<_IngredientAcquisitionCard> createState() =>
      _IngredientAcquisitionCardState();
}

class _IngredientAcquisitionCardState
    extends State<_IngredientAcquisitionCard> {
  late RecipeBookController _book;

  @override
  void initState() {
    super.initState();
    _createBook();
  }

  void _createBook() {
    _book = RecipeBookController(
      modeController: widget.controller,
      catalogRepository: CatalogRepository(widget.controller.owner.catalog),
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: const <String>[],
    );
  }

  @override
  void didUpdateWidget(_IngredientAcquisitionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _book.dispose();
      _createBook();
    }
  }

  @override
  void dispose() {
    _book.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _book,
    builder: (context, _) {
      final mode = widget.controller.mode;
      final info =
          _book.itemInfoFor(widget.name, mode: mode) ??
          RecipeBookItemInfo(title: widget.name, kind: 'Item', summary: '');
      return Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'How to obtain ${widget.name}',
        child: ItemReferenceCard(
          key: ValueKey<String>('planner-acquisition-card:${widget.stableId}'),
          controller: _book,
          mode: mode,
          name: widget.name,
          info: info,
          maxWidth: itemReferenceCardMaxWidth(context),
          spec: context.visualTheme,
          onClose: widget.onClose,
          headerDragKey: ValueKey<String>(
            'planner-acquisition-drag-region:${widget.stableId}',
          ),
        ),
      );
    },
  );
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
    required this.onRegionChanged,
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
  final ValueChanged<String> onRegionChanged;
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
            child: PlannerMarketSummary(
              silverIcon: PlannerItemIcon(
                controller: controller,
                name: 'Silver',
                size: 21,
                showFrame: false,
              ),
              hasUnknownPrices: plan.missing.any(
                (row) =>
                    row.missing > 0 &&
                    (!row.market.price.isFinite || row.market.price <= 0),
              ),
              total: plan.missing.fold<double>(
                0,
                (value, row) => value + row.market.total,
              ),
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
          child: _PlannerChoiceFeedback(
            name: row.choice?.baseName ?? row.name,
            child: _NeedRow(
              controller: controller,
              plan: plan,
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
          ),
        );
      },
    );
    final needListWithoutPlatformScrollbar = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: needList,
    );
    final headerActions = action == null
        ? null
        : Wrap(
            spacing: 10,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MarketRegionSelector(
                region: controller.state.value.market.region,
                onChanged: marketLoading ? null : onRegionChanged,
              ),
              action,
            ],
          );
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: AppSurface(
        role: AppSurfaceRole.layout,
        semanticLabel: title,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LayoutBuilder(
              builder: (context, constraints) {
                // At small panel widths keep the heading intact, then wrap the
                // controls below. SectionHeader handles enlarged text itself.
                final stacked =
                    constraints.maxWidth < 400 && headerActions != null;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeader(
                      title: title,
                      prioritizeTitle: true,
                      trailing: stacked ? null : headerActions,
                      titleBuilder: title == 'Need First'
                          ? (label) => PlannerShoppingList(
                              controller: controller,
                              anchorBuilder: (context, toggle, showing) =>
                                  InkWell(
                                    key: const ValueKey(
                                      'planner-shopping-open',
                                    ),
                                    onTap: toggle,
                                    child: Semantics(
                                      button: true,
                                      label: 'Open shopping list',
                                      child: label,
                                    ),
                                  ),
                            )
                          : null,
                    ),
                    if (stacked) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: headerActions,
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: materials.isEmpty && !showPrices
                  ? const _PlannerEmpty(
                      message:
                          'You have the materials, or they’re in your craft queue.',
                    )
                  : needListWithoutPlatformScrollbar,
            ),
          ],
        ),
      ),
    );
  }
}

class _NeedRow extends StatelessWidget {
  const _NeedRow({
    required this.controller,
    required this.plan,
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
  final PlanResult plan;
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
    final qualityInputs = plan.steps
        .expand((step) => step.ingredients)
        .where(
          (ingredient) =>
              _sameFolded(ingredient.name, row.name) &&
              controller
                  .availableIngredientGrades(
                    parentName: ingredient.parentName,
                    selectedName: ingredient.baseName,
                  )
                  .isNotEmpty,
        )
        .toList();
    final qualityInput = qualityInputs.firstOrNull;
    final processingChoice = controller.optionalProcessingRecipe(row.name);
    final anchor = choice == null
        ? processingChoice == null
              ? ''
              : 'missing-acquisition:${row.name}'
        : 'missing:${row.name}:${choice.substituteGroup}';
    final domainIngredient = choice == null
        ? processingChoice == null
              ? null
              : _acquisitionAnchorIngredient(row.name)
        : _resolveIngredient(
            controller,
            choice.parentName,
            choice.original,
            choice.substituteGroup,
          );
    final hasSubstitutes =
        domainIngredient != null &&
        (processingChoice != null || (choice?.options.length ?? 0) > 1) &&
        (choice == null ||
            controller.declaredBlueIngredientPair(
                  parentName: choice.parentName,
                  ingredientName: choice.original,
                ) ==
                null);
    final source = _sourceInfo(controller, row);
    final confirmedMarketUnlisted =
        controller.state.value.market.isItemUnlisted(row.name) ||
        _isReviewedNonMarketItem(controller, row.name) ||
        _isConfirmedMarketUnlisted(marketDiagnostics);
    final visibleMarketDiagnostics = confirmedMarketUnlisted
        ? const <PlannerMarketRowDiagnostic>[]
        : marketDiagnostics;
    final stockTone = !showPrices
        ? null
        : confirmedMarketUnlisted || _hasVendorSourcePills(row.market)
        ? AppSurfaceTone.success
        : !row.market.marketable || !row.market.stockKnown
        ? null
        : row.market.stock <= 0
        ? AppSurfaceTone.warning
        : AppSurfaceTone.success;
    final stableId = 'need:${row.key}';
    return _PlannerMapQuickLookupRegion(
      key: PlannerActionKeys.mapLookupRegion(stableId),
      materialName: row.name,
      stableId: stableId,
      externalActions: externalActions,
      child: AppInteractionFrame(
        radius: 7,
        child: _NeedMarketAccent(
          name: row.name,
          tone: stockTone,
          child: AppSurface(
            role: AppSurfaceRole.row,
            tone: stockTone ?? AppSurfaceTone.neutral,
            semanticLabel:
                '${row.name}, missing ${formatQuantity(row.missing)}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                PlannerNeedQuantities(
                  key: ValueKey('planner-need-quantities:${row.key}'),
                  stableId: row.key,
                  need: row.need,
                  have: row.have,
                  missing: row.missing,
                  leading: _ItemAcquisitionPopover(
                    controller: controller,
                    name: row.name,
                    stableId: 'need:${row.key}',
                    overlayScope: 'need',
                    size: 48,
                    onOpening: () => onChoiceAnchorChanged(null),
                  ),
                  identity: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: hasSubstitutes
                                ? choice != null && processingChoice == null
                                      ? PlannerOwnedChoices(
                                          controller: controller,
                                          parentName: choice.parentName,
                                          ingredient: domainIngredient,
                                          options: _visibleSubstituteOptions(
                                            controller,
                                            domainIngredient,
                                          ),
                                          selected: _selectedSubstituteFor(
                                            controller: controller,
                                            parentName: choice.parentName,
                                            currentName: choice.baseName,
                                            ingredient: domainIngredient,
                                          ),
                                          beforeSelection: (selection) =>
                                              onSubstituteSelected(
                                                row,
                                                selection,
                                              ),
                                          anchorBuilder:
                                              (
                                                context,
                                                toggle,
                                                showing,
                                              ) => _CopyAndSwapName(
                                                onCopy:
                                                    externalActions.copyName,
                                                swapKey: PlannerActionKeys.row(
                                                  'P12',
                                                  anchor,
                                                ),
                                                nameKey: PlannerActionKeys.row(
                                                  'P20',
                                                  row.name,
                                                ),
                                                name: row.name,
                                                fontSize: denseLayout
                                                    ? 16.5
                                                    : 17.5,
                                                isShowing: showing,
                                                onToggle: () {
                                                  onChoiceAnchorChanged(null);
                                                  toggle();
                                                },
                                              ),
                                        )
                                      : _CopyAndSwapName(
                                          onCopy: externalActions.copyName,
                                          swapKey: PlannerActionKeys.row(
                                            'P12',
                                            anchor,
                                          ),
                                          nameKey: PlannerActionKeys.row(
                                            'P20',
                                            row.name,
                                          ),
                                          name: row.name,
                                          semanticLabel: choice == null
                                              ? 'Choose how to get ${row.name}'
                                              : null,
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

                      if (qualityInput != null) ...[
                        const SizedBox(height: 6),
                        _QualitySwatches(
                          key: ValueKey('need-quality:${row.key}'),
                          controller: controller,
                          parentName: qualityInput.parentName,
                          ingredientName: qualityInput.original,
                          baseName: qualityInput.baseName,
                          selectedGrade: qualityInput.grade,
                          automatic: qualityInputs.every(
                            (input) => !controller.hasManualIngredientChoice(
                              parentName: input.parentName,
                              ingredientName: input.original,
                              selectedName: input.baseName,
                            ),
                          ),
                          onSelected: (grade) =>
                              controller.selectNeededIngredientGrade(
                                qualityInputs,
                                grade,
                              ),
                        ),
                      ],
                    ],
                  ),
                  marketDetails:
                      showPrices &&
                          _hasMarketPills(
                            row,
                            suppressCentralMarket: confirmedMarketUnlisted,
                          )
                      ? _MarketPills(
                          controller: controller,
                          row: row,
                          suppressCentralMarket: confirmedMarketUnlisted,
                        )
                      : null,
                  actions: _OwnedDraftActions(
                    key: PlannerActionKeys.row('P18', row.name),
                    controller: controller,
                    name: row.name,
                    textController: draftController,
                  ),
                ),
                if (showPrices && visibleMarketDiagnostics.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _MarketDiagnostics(diagnostics: visibleMarketDiagnostics),
                ],
                if (openChoiceAnchor == anchor && hasSubstitutes) ...<Widget>[
                  SizedBox(height: denseLayout ? 5 : 8),
                  Padding(
                    padding: EdgeInsets.only(left: denseLayout ? 52 : 58),
                    child: _InlineSubstituteChooser(
                      controller: controller,
                      parentName: choice?.parentName ?? row.name,
                      currentName: choice?.baseName ?? row.name,
                      ingredient: domainIngredient,
                      onBeforeSelection: choice == null
                          ? null
                          : (selection) => onSubstituteSelected(row, selection),
                      onClose: () => onChoiceAnchorChanged(null),
                    ),
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

class _CompletedCraftRow extends StatelessWidget {
  const _CompletedCraftRow({
    required this.controller,
    required this.name,
    super.key,
  });
  final ModeFeatureController controller;
  final String name;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        PlannerItemIcon(controller: controller, name: name, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            itemDisplayName(name),
            style: spec.typography.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 10),
        ExcludeSemantics(
          child: Icon(Icons.check, size: 18, color: spec.palette.success),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 8),
      child: AppSurface(
        role: AppSurfaceRole.row,
        tone: AppSurfaceTone.neutral,
        semanticLabel: '$name covered or completed in this queue',
        child: identity,
      ),
    );
  }
}

/// Only confirmed empty market stock gets the amber warning treatment.
/// Non-tradeable and vendor items share the available colour, without implying
/// that they can be purchased on the Central Market. Unknown stock is neutral.
/// The overlay keeps each theme's authored card material and hit targets intact.
class _NeedMarketAccent extends StatelessWidget {
  const _NeedMarketAccent({
    required this.name,
    required this.tone,
    required this.child,
  });
  final String name;
  final AppSurfaceTone? tone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (tone == null) return child;
    final spec = context.visualTheme;
    final unavailable = tone == AppSurfaceTone.warning;
    final color = unavailable
        ? spec.plannerOutOfStockAccent
        : spec.plannerAvailableAccent;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: color.withValues(alpha: .55)),
                borderRadius: BorderRadius.circular(spec.geometry.cardRadius),
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: unavailable ? .13 : .06),
                    color.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 3,
          bottom: 3,
          width: 4,
          child: IgnorePointer(
            child: DecoratedBox(
              key: ValueKey('planner-market-accent:$name'),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

bool _isReviewedNonMarketItem(ModeFeatureController controller, String name) {
  final recipeId = controller.recipeDefinition(name)?.marketId?.trim();
  if (recipeId != null && recipeId.isNotEmpty) {
    return reviewedNonMarketableOpportunityIds.contains(recipeId);
  }
  for (final entry in controller.owner.plannerRules.marketIds.entries) {
    if (_sameFolded(entry.key, name)) {
      return reviewedNonMarketableOpportunityIds.contains(entry.value.trim());
    }
  }
  return false;
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
    final added = widget.controller.addMissingAmount(widget.name, value);
    if (!added) {
      setState(() => _error = "Couldn't add right now");
      return;
    }
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
                      onSubmitted: (_) => _add(),
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
    preferredWidth: ItemDetailStyle.width(context),
    maximumHeight: itemReferenceCardHeight(context),
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
    return AppSurface(
      key: const ValueKey<String>('planner-source-info-card'),
      role: AppSurfaceRole.tooltip,
      tone: AppSurfaceTone.info,
      padding: const EdgeInsets.all(16),
      semanticLabel: 'Source information for ${request.name}',
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PlannerItemIcon(
                  controller: controller,
                  name: request.name,
                  size: ItemDetailStyle.headerIcon,
                ),
                const SizedBox(width: ItemDetailStyle.itemGap),
                Expanded(
                  child: AnchoredPopoverDragRegion(
                    key: const ValueKey<String>(
                      'planner-source-info-drag-region',
                    ),
                    child: Text(
                      request.name,
                      style: ItemDetailStyle.title(spec),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SourceInfoCloseButton(
                  semanticLabel: 'Close source information for ${request.name}',
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: ItemDetailStyle.sectionGap),
            Text('How to obtain', style: ItemDetailStyle.section(spec)),
            const SizedBox(height: 8),
            Text(
              _sourceInfoText(request),
              key: const ValueKey<String>('planner-source-info-body'),
              style: ItemDetailStyle.body(spec),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceInfoCloseButton extends StatelessWidget {
  const _SourceInfoCloseButton({
    required this.semanticLabel,
    required this.onPressed,
  });
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => AppButton(
    key: const ValueKey<String>('planner-source-info-close'),
    role: AppButtonRole.optionPill,
    minimumSize: const Size.square(30),
    padding: EdgeInsets.zero,
    semanticLabel: semanticLabel,
    tooltip: 'Close',
    onPressed: onPressed,
    child: const AppVectorGlyph('close', size: 11),
  );
}

class _CopyAndSwapName extends StatelessWidget {
  const _CopyAndSwapName({
    required this.name,
    required this.nameKey,
    required this.swapKey,
    required this.onCopy,
    required this.fontSize,
    required this.isShowing,
    required this.onToggle,
    this.color,
    this.semanticLabel,
  });
  final String name;
  final Key nameKey;
  final Key swapKey;
  final CopyPlannerName onCopy;
  final double fontSize;
  final bool isShowing;
  final VoidCallback onToggle;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: _CopyNameButton(
          key: nameKey,
          name: name,
          semanticPrefix: 'Copy ingredient',
          onCopy: onCopy,
          fontSize: fontSize,
          color: color,
        ),
      ),
      const SizedBox(width: 6),
      AppButton(
        key: swapKey,
        role: AppButtonRole.icon,
        semanticLabel: semanticLabel ?? 'Change ingredient $name',
        selected: isShowing,
        minimumSize: const Size(30, 28),
        padding: const EdgeInsets.all(5),
        onPressed: onToggle,
        child: const AppVectorGlyph('swap', size: 13),
      ),
    ],
  );
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
    final options = _visibleSubstituteOptions(
      widget.controller,
      widget.ingredient,
    );
    final processingChoice = widget.controller.optionalProcessingRecipe(
      widget.currentName,
    );
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
                  for (final option in options.where(
                    (_) => options.length > 1 || processingChoice == null,
                  ))
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
                  if (processingChoice != null)
                    _ProcessingAcquisitionOptions(
                      controller: widget.controller,
                      recipe: processingChoice,
                      onClose: widget.onClose,
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
    if (MediaQuery.disableAnimationsOf(context)) return panel;
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>(
        'planner-choice-entrance:${widget.ingredient.name}',
      ),
      tween: Tween<double>(begin: .84, end: 1),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: panel,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
    );
  }
}

Ingredient _acquisitionAnchorIngredient(String name) => Ingredient(
  name: name,
  quantity: 1,
  options: [name],
  substituteGroup: null,
  substituteRatios: const {},
);

class _ProcessingAcquisitionOptions extends StatelessWidget {
  const _ProcessingAcquisitionOptions({
    required this.controller,
    required this.recipe,
    required this.onClose,
  });
  final ModeFeatureController controller;
  final Recipe recipe;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final processing = controller.processesAcquisition(recipe.name);
    final formula = recipe.resolveVariant(
      controller.selectedRecipeVariantId(recipe.name),
    );
    final tooltip = <String>[
      formula.method ?? 'Processing',
      for (final ingredient in formula.ingredients)
        '${formatQuantity(ingredient.quantity)}× ${ingredient.name}',
      if (formula.outputMinimum != null && formula.outputMaximum != null)
        'Makes ${formatQuantity(formula.outputMinimum!)}–${formatQuantity(formula.outputMaximum!)} ${recipe.name}',
    ].join('\n');
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final process in [false, true])
          AppTooltip(
            message: process
                ? tooltip
                : 'Use the finished item. Market or workers.',
            child: AppButton(
              key: ValueKey(
                'acquisition-choice:${recipe.name}:${process ? 'process' : 'buy'}',
              ),
              selected: processing == process,
              role: AppButtonRole.optionPill,
              semanticLabel: '${process ? 'Process' : 'Buy'} ${recipe.name}',
              onPressed: () {
                controller.selectProcessingAcquisition(
                  recipe.name,
                  process: process,
                );
                onClose();
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PlannerItemIcon(
                    controller: controller,
                    name: process
                        ? formula.ingredients.first.name
                        : recipe.name,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Text(process ? 'Process' : 'Buy'),
                ],
              ),
            ),
          ),
      ],
    );
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
    required this.selectedGrade,
    this.onSelected,
    this.automatic,
    this.keyScope = '',
    super.key,
  });

  final ModeFeatureController controller;
  final String parentName;
  final String ingredientName;
  final String baseName;
  final String selectedGrade;
  final ValueChanged<String>? onSelected;
  final bool? automatic;
  final String keyScope;

  @override
  Widget build(BuildContext context) {
    final profile = controller.qualityProfile(
      parentName: parentName,
      selectedName: baseName,
    );
    final grades = _qualityGrades(controller, parentName, baseName);
    final declaredPair = controller.declaredBlueIngredientPair(
      parentName: parentName,
      ingredientName: ingredientName,
    );
    final displayedGrade = declaredPair == null
        ? selectedGrade
        : _sameFolded(baseName, declaredPair.blue)
        ? 'blue'
        : 'normal';
    final isAuto =
        automatic ??
        !controller.hasManualIngredientChoice(
          parentName: parentName,
          ingredientName: ingredientName,
          selectedName: baseName,
        );
    void select(String grade) {
      if (onSelected != null) {
        onSelected!(grade);
      } else {
        controller.selectIngredientGrade(
          parentName: parentName,
          ingredientName: ingredientName,
          selectedName: baseName,
          grade: grade,
        );
      }
    }

    return Semantics(
      key: PlannerActionKeys.row(
        'P14',
        '$keyScope${onSelected == null ? '' : 'need:'}$parentName:$ingredientName',
      ),
      container: true,
      label: 'Quality grade for $ingredientName',
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: <Widget>[
          AppButton(
            role: AppButtonRole.optionPill,
            minimumSize: const Size(36, 26),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            selected: isAuto,
            semanticLabel: 'Automatic ingredient choice',
            onPressed: () => select('auto'),
            child: const Text('Auto', style: TextStyle(fontSize: 12)),
          ),
          for (var index = 0; index < grades.length; index += 1) ...<Widget>[
            QualityGradeButton(
              label: grades[index].$2,
              grade: grades[index].$1,
              normalIsBlueFamily:
                  profile.family == IngredientQualityFamily.blue,
              selected: _sameFolded(displayedGrade, grades[index].$1),
              onPressed: () => select(grades[index].$1),
            ),
          ],
        ],
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

class _MarketPills extends StatelessWidget {
  const _MarketPills({
    required this.controller,
    required this.row,
    required this.suppressCentralMarket,
  });

  final ModeFeatureController controller;
  final MissingMaterial row;
  final bool suppressCentralMarket;

  @override
  Widget build(BuildContext context) {
    final market = row.market;
    final spec = context.visualTheme;
    final vendor = _hasVendorSourcePills(market);
    if (!vendor && suppressCentralMarket) return const SizedBox.shrink();
    Widget text(String value, {bool strong = false}) => Text(
      value,
      style: spec.typography.meta.copyWith(
        color: spec.palette.text,
        fontSize: 12.5,
        fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
        fontStyle: FontStyle.normal,
        height: 1.25,
      ),
    );
    final stock = SourceAvailabilityBadges(
      npc: vendor,
      stock: market.stockKnown ? market.stock.toInt() : null,
    );
    Widget amount(double? value, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label == 'Total') ...[text(label), const SizedBox(width: 5)],
        PlannerItemIcon(
          controller: controller,
          name: 'Silver',
          size: 18,
          showFrame: false,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: OpportunitySilverAmount(
            value: value,
            wholeSilver: true,
            style: spec.typography.meta.copyWith(
              color: spec.palette.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.normal,
            ),
          ),
        ),
        if (label == 'each') ...[const SizedBox(width: 5), text(label)],
      ],
    );
    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 14,
      runSpacing: 6,
      children: [
        stock,
        amount(market.price > 0 ? market.price : null, 'each'),
        amount(market.price > 0 ? market.total : null, 'Total'),
      ],
    );
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
      label: '$semanticPrefix ${itemDisplayName(name)}',
      child: InkWell(
        onTap: () async => onCopy(itemDisplayName(name)),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: EdgeInsets.zero,
          child: Text(
            itemDisplayName(name),
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
    this.showFrame = true,
    super.key,
  });

  final ModeFeatureController controller;
  final String name;
  final double size;
  final bool showFrame;

  @override
  Widget build(BuildContext context) {
    final icon = ModeItemIcon(
      controller: controller,
      name: name,
      size: size,
      searchAcrossModes: true,
      showFrame: showFrame,
    );
    return showFrame && size >= 42 ? WorkshopItemMount(child: icon) : icon;
  }
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
  final matches = <String, PlanStepIngredient>{};
  for (final parentStep in plan.steps) {
    for (final ingredient in parentStep.ingredients) {
      // A title may offer replacements for this item, never for a recipe
      // further up the chain that happens to consume it.
      if (!ingredient.craftable ||
          !_sameFolded(ingredient.name, stepName) ||
          ingredient.options.length < 2) {
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
  final npcPurchaseSummaries =
      acquisition == null ||
          acquisition.status.trim().toLowerCase() != 'reviewed'
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
  final saved = _stringFor(controller.state.value.substituteChoices, key);
  final options = _visibleSubstituteOptions(controller, ingredient);
  if (saved != null && options.any((option) => _sameFolded(option, saved))) {
    return saved;
  }
  return currentName;
}

List<String> _visibleSubstituteOptions(
  ModeFeatureController controller,
  Ingredient ingredient,
) => _distinctFolded(ingredient.options)
    .where(
      (name) => !isTemporarilyArchivedItem(
        name,
        itemId: controller.recipes.entries
            .where((entry) => _sameFolded(entry.key, name))
            .firstOrNull
            ?.value
            .marketId,
      ),
    )
    .toList(growable: false);

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

AppSurfaceTone _diagnosticTone(PlannerMarketDiagnosticSeverity severity) =>
    switch (severity) {
      PlannerMarketDiagnosticSeverity.info => AppSurfaceTone.info,
      PlannerMarketDiagnosticSeverity.warning => AppSurfaceTone.warning,
      PlannerMarketDiagnosticSeverity.error => AppSurfaceTone.danger,
    };
