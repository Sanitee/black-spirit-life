import 'dart:math' as math;

import 'package:bdo_craft_planner_flutter/visual/components/app_tooltip.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/state/planner_application_controller.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../visual/visual.dart';
import '../inventory/inventory_amount_input_formatter.dart';

/// Abbreviates owned amounts without rounding up stock the user does not own.
String formatPlannerInventoryAmount(double value) {
  if (!value.isFinite || value < 0) return '0';
  final (divisor, suffix) = switch (value) {
    >= 1000000000 => (1000000000, 'B'),
    >= 1000000 => (1000000, 'M'),
    >= 1000 => (1000, 'k'),
    _ => (1, ''),
  };
  if (suffix.isEmpty) return formatGroupedEditableQuantity(value);
  final truncated = (value / divisor * 10).floor() / 10;
  final number = truncated.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return '$number$suffix';
}

/// An owned-total footer attached beneath its item artwork. Only the number
/// activates editing; the icon retains its own identity and interactions.
class PlannerInventoryInput extends StatefulWidget {
  const PlannerInventoryInput({
    required this.controller,
    required this.itemName,
    required this.iconBuilder,
    this.iconSize = 48,
    super.key,
  });

  final ModeFeatureController controller;
  final String itemName;
  final Widget Function(double size) iconBuilder;
  final double iconSize;

  @override
  State<PlannerInventoryInput> createState() => _PlannerInventoryInputState();
}

class _PlannerInventoryInputState extends State<PlannerInventoryInput> {
  final _text = TextEditingController();
  late final _focus = FocusNode()..addListener(_focusChanged);
  final _editScroll = ScrollController(keepScrollOffset: false);
  late double _observedOwned;
  bool _editing = false;
  bool _dirty = false;
  String? _error;

  double get _owned {
    final name = widget.itemName.trim().toLowerCase();
    for (final entry in widget.controller.state.value.inventory.entries) {
      if (entry.key.trim().toLowerCase() == name) return entry.value;
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _observedOwned = _owned;
    widget.controller.state.addListener(_inventoryChanged);
  }

  @override
  void didUpdateWidget(PlannerInventoryInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.state.removeListener(_inventoryChanged);
      widget.controller.state.addListener(_inventoryChanged);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.itemName != widget.itemName) {
      // A recycled card must never save the previous item's draft to a new item.
      _editing = false;
      _dirty = false;
      _error = null;
      _focus.unfocus();
      _observedOwned = _owned;
    }
  }

  void _inventoryChanged() {
    if (!mounted) return;
    final next = _owned;
    if (next == _observedOwned) return;
    _observedOwned = next;
    // Keep an active draft intact while other inventory entries are changed.
    setState(() {});
  }

  void _focusChanged() {
    if (!_focus.hasFocus && _editing) _finishEditing();
  }

  void _beginEdit() {
    final full = formatGroupedEditableQuantity(_owned);
    _text.value = TextEditingValue(
      text: full,
      selection: TextSelection(baseOffset: 0, extentOffset: full.length),
    );
    setState(() {
      _editing = true;
      _dirty = false;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _focus.requestFocus();
    });
  }

  void _finishEditing() {
    if (!_editing) return;
    if (_dirty) {
      if (widget.controller.owner.mutationsFrozen) {
        setState(() => _error = 'Edits are paused');
        return;
      }
      final parsed = parsePlannerNumber(_text.text);
      if (parsed == null || !parsed.isFinite || parsed < 0) {
        setState(() => _error = 'Use 0 or more');
        return;
      }
      if (!widget.controller.commitQueueInventory(
        widget.itemName,
        _text.text,
      )) {
        setState(() => _error = 'Could not update');
        return;
      }
    }
    setState(() {
      _editing = false;
      _dirty = false;
      _error = null;
    });
    _focus.unfocus();
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _dirty = false;
      _error = null;
    });
    _focus.unfocus();
  }

  @override
  void dispose() {
    widget.controller.state.removeListener(_inventoryChanged);
    // Committing may remove this queue row. Never write again during disposal
    // or save an unfinished draft when its mode/card is removed.
    _focus
      ..removeListener(_focusChanged)
      ..dispose();
    _text.dispose();
    _editScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final scale = scaler.scale(13) / 13;
    final amountStyle = spec.typography.meta.copyWith(
      fontSize: 13,
      height: 1.15,
      fontStyle: FontStyle.normal,
      color: spec.palette.text,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: amountStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final compact = formatPlannerInventoryAmount(_owned);
    final full = formatGroupedEditableQuantity(_owned);
    // Grow for larger text rather than clipping or shrinking the amount.
    final iconExtent = math.max(widget.iconSize, measure(compact) + 10);
    final editWidth = (measure(_text.text) + 12).clamp(28 * scale, 168 * scale);
    final width = _editing ? math.max(iconExtent, editWidth) : iconExtent;
    const footerRadius = BorderRadius.vertical(bottom: Radius.circular(4));
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            key: ValueKey('planner-inventory-icon-${widget.itemName}'),
            dimension: iconExtent,
            child: widget.iconBuilder(iconExtent),
          ),
          DecoratedBox(
            key: ValueKey('planner-inventory-footer-${widget.itemName}'),
            decoration: BoxDecoration(
              color: spec.palette.surfaceRaised,
              border: Border.all(color: spec.palette.trimBright),
              borderRadius: footerRadius,
            ),
            child: SizedBox(
              width: width,
              child: _editing
                  ? Focus(
                      onKeyEvent: (_, event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.escape) {
                          _cancelEdit();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Semantics(
                        label: '${widget.itemName} inventory',
                        child: TextField(
                          key: ValueKey(
                            'planner-inventory-editor-${widget.itemName}',
                          ),
                          controller: _text,
                          focusNode: _focus,
                          scrollController: _editScroll,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.done,
                          inputFormatters: const [
                            InventoryAmountInputFormatter(),
                          ],
                          textAlign: TextAlign.center,
                          style: amountStyle,
                          cursorColor: spec.palette.primaryBright,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: spec.palette.primaryBright,
                              ),
                            ),
                          ),
                          onChanged: (_) => setState(() {
                            _dirty = true;
                            _error = null;
                          }),
                          onEditingComplete: _finishEditing,
                          onSubmitted: (_) => _finishEditing(),
                          onTapOutside: (_) => _focus.unfocus(),
                        ),
                      ),
                    )
                  : AppTooltip(
                      message: full,
                      child: Semantics(
                        label: '${widget.itemName} inventory',
                        value: full,
                        button: true,
                        child: InkWell(
                          key: ValueKey(
                            'planner-inventory-amount-${widget.itemName}',
                          ),
                          onTap: _beginEdit,
                          borderRadius: footerRadius,
                          focusColor: spec.palette.primaryBright.withAlpha(72),
                          hoverColor: spec.palette.primaryBright.withAlpha(28),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            child: Text(
                              compact,
                              textAlign: TextAlign.center,
                              style: amountStyle,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: spec.typography.meta.copyWith(
                  color: spec.palette.danger,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
