import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/state/planner_application_controller.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../visual/visual.dart';
import '../inventory/inventory_amount_input_formatter.dart';
import '../planner/planner_inventory_input.dart'
    show formatPlannerInventoryAmount;

/// Edits the Planner's shared Inventory without treating owned inputs as free.
class OpportunityInventoryInput extends StatefulWidget {
  const OpportunityInventoryInput({
    required this.controller,
    required this.itemName,
    required this.iconBuilder,
    super.key,
  });

  final ModeFeatureController controller;
  final String itemName;
  final Widget Function(double size) iconBuilder;

  @override
  State<OpportunityInventoryInput> createState() =>
      _OpportunityInventoryInputState();
}

class _OpportunityInventoryInputState extends State<OpportunityInventoryInput> {
  late final _text = TextEditingController(text: _compact(_owned));
  late final _focus = FocusNode()..addListener(_focusChanged);
  // A newly mounted editor must not restore the surrounding recipe dialog's
  // vertical PageStorage offset as its own horizontal text position.
  final _editScroll = ScrollController(keepScrollOffset: false);
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

  static String _compact(double value) => formatPlannerInventoryAmount(value);

  @override
  void initState() {
    super.initState();
    widget.controller.state.addListener(_inventoryChanged);
  }

  @override
  void didUpdateWidget(OpportunityInventoryInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.state.removeListener(_inventoryChanged);
      widget.controller.state.addListener(_inventoryChanged);
    }
    if (!_focus.hasFocus && !_dirty) _text.text = _compact(_owned);
  }

  void _inventoryChanged() {
    if (!mounted) return;
    if (!_focus.hasFocus && !_dirty) _text.text = _compact(_owned);
    setState(() {});
  }

  void _focusChanged() {
    if (_focus.hasFocus) {
      if (!_dirty) {
        final full = formatGroupedEditableQuantity(_owned);
        _text.value = TextEditingValue(
          text: full,
          selection: TextSelection(baseOffset: 0, extentOffset: full.length),
        );
      }
    } else if (_commit()) {
      _text.text = _compact(_owned);
      _editing = false;
    }
    if (mounted) setState(() {});
  }

  void _beginEdit() {
    final full = formatGroupedEditableQuantity(_owned);
    _text.value = TextEditingValue(
      text: full,
      selection: TextSelection(baseOffset: 0, extentOffset: full.length),
    );
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _focus.requestFocus();
    });
  }

  void _cancelEdit() {
    _dirty = false;
    _error = null;
    _focus.unfocus();
    setState(() => _editing = false);
  }

  bool _commit() {
    if (!_dirty) return true;
    if (widget.controller.owner.mutationsFrozen) {
      setState(() => _error = 'Edits are paused');
      return false;
    }
    final parsed = parsePlannerNumber(_text.text);
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      setState(() => _error = 'Use 0 or more');
      return false;
    }
    if (!widget.controller.commitInventory(widget.itemName, _text.text)) {
      setState(() => _error = 'Could not update');
      return false;
    }
    _dirty = false;
    _error = null;
    return true;
  }

  @override
  void dispose() {
    widget.controller.state.removeListener(_inventoryChanged);
    // Closing the detail or opening a substitute can remove a focused field
    // before a blur arrives. Keep valid pending edits, as Inventory rows do.
    if (_dirty) {
      final controller = widget.controller;
      final name = widget.itemName;
      final text = _text.text;
      final parsed = parsePlannerNumber(text);
      if (parsed != null && parsed.isFinite && parsed >= 0) {
        scheduleMicrotask(() {
          if (!controller.owner.mutationsFrozen) {
            controller.commitInventory(name, text);
          }
        });
      }
    }
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
      height: 1.3,
      color: spec.palette.text,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final full = formatGroupedEditableQuantity(_owned);
    final compactMeasurement = TextPainter(
      text: TextSpan(text: _compact(_owned), style: amountStyle),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final iconExtent = math.max(48.0, compactMeasurement.width + 10);
    compactMeasurement.dispose();
    final measurement = TextPainter(
      text: TextSpan(text: _text.text, style: amountStyle),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final editWidth = math
        .max(28 * scale, measurement.width + 12 * scale)
        .clamp(28 * scale, 168 * scale);
    measurement.dispose();
    final fieldHeight = math.max(24.0, scaler.scale(13) * 1.3 + 8);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.iconBuilder(iconExtent),
        Container(
          key: const ValueKey('inventory-amount-frame'),
          width: _editing ? math.max(iconExtent, editWidth) : iconExtent,
          height: fieldHeight,
          decoration: BoxDecoration(
            color: spec.palette.surfaceRaised,
            border: Border.all(color: spec.palette.trimBright),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(4),
            ),
          ),
          child: _editing
              ? SizedBox(
                  width: editWidth,
                  child: Focus(
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
                        controller: _text,
                        focusNode: _focus,
                        scrollController: _editScroll,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: const [
                          InventoryAmountInputFormatter(),
                        ],
                        textAlign: TextAlign.center,
                        textAlignVertical: TextAlignVertical.center,
                        strutStyle: const StrutStyle(
                          fontSize: 13,
                          height: 1.3,
                          forceStrutHeight: true,
                        ),
                        style: amountStyle,
                        cursorColor: spec.palette.primary,
                        decoration: InputDecoration(
                          isDense: true,
                          isCollapsed: true,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 3,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: spec.palette.primary),
                          ),
                        ),
                        onChanged: (_) => setState(() {
                          _dirty = true;
                          _error = null;
                        }),
                        onSubmitted: (_) {
                          if (_commit()) _focus.unfocus();
                        },
                        onTapOutside: (_) => _focus.unfocus(),
                      ),
                    ),
                  ),
                )
              : Semantics(
                  label: '${widget.itemName} inventory',
                  value: full,
                  button: true,
                  child: InkWell(
                    key: const ValueKey('inventory-amount-button'),
                    onTap: _beginEdit,
                    borderRadius: BorderRadius.circular(3),
                    child: Center(
                      child: Text(
                        _compact(_owned),
                        style: amountStyle,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 3),
          Text(
            _error!,
            style: spec.typography.meta.copyWith(color: spec.palette.danger),
          ),
        ],
      ],
    );
  }
}
