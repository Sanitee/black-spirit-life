import 'dart:async';

import 'package:bdo_craft_planner_flutter/visual/components/app_tooltip.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/state/planner_application_controller.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../visual/components/app_interaction_frame.dart';
import '../../visual/visual.dart';
import '../shared/mode_item_icon.dart';
import '../shared/workshop_presentation.dart';
import 'inventory_action_keys.dart';
import 'inventory_amount_input_formatter.dart';
import 'inventory_projection.dart';

/// Compact editable row for one item in the shared Inventory.
class InventoryStorageItemRow extends StatefulWidget {
  const InventoryStorageItemRow({
    required this.controller,
    required this.item,
    required this.amount,
    required this.index,
    required this.selected,
    required this.onSelected,
    required this.onMoveFocus,
    required this.onRegisterFocus,
    required this.onUnregisterFocus,
    required this.onCopy,
    required this.onCommitAmount,
    required this.onRemove,
    this.onEdit,
    super.key,
  });

  final ModeFeatureController controller;
  final InventoryItemRecord item;
  final double amount;
  final int index;
  final bool selected;
  final ValueChanged<String> onSelected;
  final ValueChanged<int> onMoveFocus;
  final void Function(String name, FocusNode node) onRegisterFocus;
  final void Function(String name, FocusNode node) onUnregisterFocus;
  final Future<void> Function(String exactName) onCopy;
  final bool Function(String text) onCommitAmount;
  final VoidCallback? onRemove;
  final VoidCallback? onEdit;

  @override
  State<InventoryStorageItemRow> createState() =>
      _InventoryStorageItemRowState();
}

class _InventoryStorageItemRowState extends State<InventoryStorageItemRow> {
  late final FocusNode _rowFocus = FocusNode(debugLabel: 'Inventory item row');
  late final FocusNode _amountFocus = FocusNode()..addListener(_focusChanged);
  late final TextEditingController _amount = TextEditingController(
    text: formatGroupedEditableQuantity(widget.amount),
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
    if (!_amountFocus.hasFocus && oldWidget.amount != widget.amount) {
      final text = formatGroupedEditableQuantity(widget.amount);
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
    final amountText = formatQuantity(widget.amount);
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
          label: '${widget.item.name}, $amountText owned',
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => widget.onSelected(widget.item.name),
            child: AppInteractionFrame(
              selected: widget.selected,
              radius: 8,
              child: AppSoftTile(
                selected: widget.selected,
                child: LayoutBuilder(
                  builder: (context, constraints) => _buildContents(
                    context: context,
                    spec: spec,
                    availableWidth: constraints.maxWidth,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContents({
    required BuildContext context,
    required ThemeSpec spec,
    required double availableWidth,
  }) {
    final icon = WorkshopItemMount(
      child: ModeItemIcon(
        controller: widget.controller,
        name: widget.item.name,
        size: 48,
        searchAcrossModes: true,
        aliases: <String>[?widget.item.recipe?.qualityBase],
      ),
    );
    final nameStyle = spec.typography.body.copyWith(
      fontSize: 17,
      height: 1.2,
      fontWeight: FontWeight.w700,
    );
    final name = AppTooltip(
      message: widget.item.name,
      child: TextButton(
        key: InventoryActionKeys.row('I09', widget.item.name),
        onPressed: () => widget.onCopy(widget.item.name),
        style: ButtonStyle(
          alignment: Alignment.centerLeft,
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          minimumSize: const WidgetStatePropertyAll(Size.zero),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
        child: Text(
          widget.item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: nameStyle,
        ),
      ),
    );
    final amount = SizedBox(
      width: 100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Owned', style: spec.typography.meta),
          const SizedBox(height: 4),
          AppTextField(
            key: InventoryActionKeys.row('I10', widget.item.name),
            controller: _amount,
            focusNode: _amountFocus,
            semanticLabel: 'Owned amount for ${widget.item.name}',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const <TextInputFormatter>[
              InventoryAmountInputFormatter(),
            ],
            textAlign: TextAlign.right,
            onSubmitted: _commit,
            suffixIcon: _error == null
                ? null
                : AppTooltip(
                    message: _error!,
                    child: const Icon(Icons.error_outline, size: 17),
                  ),
          ),
        ],
      ),
    );
    final edit = widget.onEdit == null
        ? null
        : SizedBox.square(
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
          );
    final remove = PopupMenuButton<String>(
      key: ValueKey('inventory-more:${widget.item.name}'),
      tooltip: 'Actions for ${widget.item.name}',
      icon: Icon(Icons.more_horiz, color: spec.palette.textMuted, size: 22),
      color: spec.palette.surfaceRaised,
      onSelected: (_) => widget.onRemove?.call(),
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          key: InventoryActionKeys.row('I15', widget.item.name),
          value: 'remove',
          enabled: widget.onRemove != null,
          child: Text('Remove from Inventory', style: spec.typography.body),
        ),
      ],
      constraints: const BoxConstraints(minWidth: 190),
      padding: const EdgeInsets.all(6),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(38),
        maximumSize: const Size.square(38),
      ),
    );

    final inlineNameWidth =
        availableWidth - 48 - 10 - 14 - 100 - (edit == null ? 0 : 48) - 10 - 38;
    var stackControls = availableWidth < 350 || inlineNameWidth <= 0;
    if (!stackControls) {
      final inlineName = TextPainter(
        text: TextSpan(text: widget.item.name, style: nameStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 2,
      )..layout(maxWidth: inlineNameWidth);
      stackControls = inlineName.didExceedMaxLines;
      inlineName.dispose();
    }

    if (!stackControls) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          icon,
          const SizedBox(width: 10),
          Expanded(child: name),
          const SizedBox(width: 14),
          amount,
          if (edit != null) ...<Widget>[const SizedBox(width: 10), edit],
          const SizedBox(width: 10),
          remove,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        icon,
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              name,
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  amount,
                  if (edit != null) ...<Widget>[const SizedBox(width: 8), edit],
                  const SizedBox(width: 10),
                  remove,
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
