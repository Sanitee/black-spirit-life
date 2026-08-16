import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/state/planner_application_controller.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../visual/visual.dart';
import '../shared/mode_item_icon.dart';
import 'inventory_action_keys.dart';
import 'inventory_projection.dart';

/// Compact editable row for one item in one named storage.
///
/// The field edits only [locationAmount]. [totalAmount] is deliberately
/// read-only because lowering an aggregate cannot be assigned safely across
/// several storages.
class InventoryStorageItemRow extends StatefulWidget {
  const InventoryStorageItemRow({
    required this.controller,
    required this.item,
    required this.locationName,
    required this.locationAmount,
    required this.totalAmount,
    required this.index,
    required this.selected,
    required this.onSelected,
    required this.onMoveFocus,
    required this.onRegisterFocus,
    required this.onUnregisterFocus,
    required this.onCopy,
    required this.onCommitAmount,
    this.onEdit,
    super.key,
  });

  final ModeFeatureController controller;
  final InventoryItemRecord item;
  final String locationName;
  final double locationAmount;
  final double totalAmount;
  final int index;
  final bool selected;
  final ValueChanged<String> onSelected;
  final ValueChanged<int> onMoveFocus;
  final void Function(String name, FocusNode node) onRegisterFocus;
  final void Function(String name, FocusNode node) onUnregisterFocus;
  final Future<void> Function(String exactName) onCopy;
  final bool Function(String text) onCommitAmount;
  final VoidCallback? onEdit;

  @override
  State<InventoryStorageItemRow> createState() =>
      _InventoryStorageItemRowState();
}

class _InventoryStorageItemRowState extends State<InventoryStorageItemRow> {
  late final FocusNode _rowFocus = FocusNode(debugLabel: 'Inventory item row');
  late final FocusNode _amountFocus = FocusNode()..addListener(_focusChanged);
  late final TextEditingController _amount = TextEditingController(
    text: formatGroupedEditableQuantity(widget.locationAmount),
  );
  late String _lastCommitted = _amount.text;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.onRegisterFocus(widget.item.name, _rowFocus);
  }

  @override
  void didUpdateWidget(InventoryStorageItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.name != widget.item.name) {
      oldWidget.onUnregisterFocus(oldWidget.item.name, _rowFocus);
      widget.onRegisterFocus(widget.item.name, _rowFocus);
    }
    if (!_amountFocus.hasFocus &&
        oldWidget.locationAmount != widget.locationAmount) {
      final text = formatGroupedEditableQuantity(widget.locationAmount);
      _amount.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _lastCommitted = text;
      _error = null;
    }
  }

  @override
  void dispose() {
    widget.onUnregisterFocus(widget.item.name, _rowFocus);
    if (_amount.text != _lastCommitted) {
      final commit = widget.onCommitAmount;
      final value = _amount.text;
      scheduleMicrotask(() => commit(value));
    }
    _rowFocus.dispose();
    _amountFocus
      ..removeListener(_focusChanged)
      ..dispose();
    _amount.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!_amountFocus.hasFocus) _commit();
  }

  void _commit([String? _]) {
    final parsed = parsePlannerNumber(_amount.text);
    if (parsed == null || parsed < 0 || !widget.onCommitAmount(_amount.text)) {
      setState(() => _error = 'Use 0 or a positive number');
      return;
    }
    final text = formatGroupedEditableQuantity(parsed);
    _amount.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _lastCommitted = text;
    setState(() => _error = null);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      widget.onMoveFocus(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.onMoveFocus(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final hasOtherLocations =
        (widget.totalAmount - widget.locationAmount).abs() > 0.0000001;
    final locationText = formatQuantity(widget.locationAmount);
    final totalText = formatQuantity(widget.totalAmount);
    return FocusTraversalOrder(
      order: NumericFocusOrder(widget.index.toDouble()),
      child: Focus(
        key: InventoryActionKeys.row('I14', widget.item.name),
        focusNode: _rowFocus,
        onKeyEvent: _onKey,
        onFocusChange: (focused) {
          if (focused) widget.onSelected(widget.item.name);
        },
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          selected: widget.selected,
          label:
              '${widget.item.name}, $locationText in ${widget.locationName}, '
              '$totalText total',
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => widget.onSelected(widget.item.name),
            child: AppSurface(
              role: AppSurfaceRole.row,
              tone: widget.locationAmount > 0
                  ? AppSurfaceTone.success
                  : AppSurfaceTone.neutral,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: <Widget>[
                  ModeItemIcon(
                    controller: widget.controller,
                    name: widget.item.name,
                    size: 40,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: TextButton(
                      key: InventoryActionKeys.row('I09', widget.item.name),
                      onPressed: () => widget.onCopy(widget.item.name),
                      style: ButtonStyle(
                        alignment: Alignment.centerLeft,
                        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                        minimumSize: const WidgetStatePropertyAll(Size.zero),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: const WidgetStatePropertyAll(
                          Colors.transparent,
                        ),
                        overlayColor: const WidgetStatePropertyAll(
                          Colors.transparent,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: spec.typography.body.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.item.savedOnly
                                ? '${widget.item.smartGroup} · saved item'
                                : widget.item.smartGroup,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: spec.typography.meta.copyWith(
                              fontStyle: FontStyle.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (hasOtherLocations) ...<Widget>[
                    SizedBox(
                      width: 112,
                      child: Text(
                        'Total $totalText',
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: spec.typography.meta.copyWith(
                          fontStyle: FontStyle.normal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  SizedBox(
                    width: 132,
                    child: AppTextField(
                      key: InventoryActionKeys.row('I10', widget.item.name),
                      controller: _amount,
                      focusNode: _amountFocus,
                      semanticLabel:
                          'Amount of ${widget.item.name} in ${widget.locationName}',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.right,
                      onSubmitted: _commit,
                      suffixIcon: _error == null
                          ? null
                          : Tooltip(
                              message: _error!,
                              child: const Icon(Icons.error_outline, size: 17),
                            ),
                    ),
                  ),
                  if (widget.onEdit != null) ...<Widget>[
                    const SizedBox(width: 8),
                    SizedBox.square(
                      dimension: 38,
                      child: AppButton(
                        key: InventoryActionKeys.row('I11', widget.item.name),
                        role: AppButtonRole.icon,
                        minimumSize: const Size.square(38),
                        padding: const EdgeInsets.all(8),
                        semanticLabel: 'Edit ${widget.item.name}',
                        tooltip: 'Edit item settings',
                        onPressed: widget.onEdit,
                        child: const AppVectorGlyph('edit', size: 17),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
