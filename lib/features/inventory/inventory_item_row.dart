import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/state/planner_application_controller.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../visual/visual.dart';
import '../shared/mode_item_icon.dart';
import 'inventory_action_keys.dart';
import 'inventory_projection.dart';

class InventoryItemRow extends StatefulWidget {
  const InventoryItemRow({
    required this.controller,
    required this.item,
    required this.categories,
    required this.categoryWidth,
    required this.index,
    required this.compact,
    required this.fixedStandardColumns,
    required this.selected,
    required this.showDeleteTool,
    required this.sourceNoteDebounce,
    required this.onRegisterFocus,
    required this.onUnregisterFocus,
    required this.onSelected,
    required this.onMoveFocus,
    required this.onCopy,
    required this.onCommitOwned,
    required this.onCategoryChanged,
    required this.onSourceNoteCommitted,
    required this.onHideOrDelete,
    super.key,
  });

  final ModeFeatureController controller;
  final InventoryItemRecord item;
  final List<String> categories;
  final double categoryWidth;
  final int index;
  final bool compact;
  final bool fixedStandardColumns;
  final bool selected;
  final bool showDeleteTool;
  final Duration sourceNoteDebounce;
  final void Function(String name, FocusNode node) onRegisterFocus;
  final void Function(String name, FocusNode node) onUnregisterFocus;
  final ValueChanged<String> onSelected;
  final ValueChanged<int> onMoveFocus;
  final Future<void> Function(String exactName) onCopy;
  final bool Function(String text) onCommitOwned;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onSourceNoteCommitted;
  final VoidCallback onHideOrDelete;

  @override
  State<InventoryItemRow> createState() => _InventoryItemRowState();
}

class _InventoryItemRowState extends State<InventoryItemRow> {
  late final FocusNode _rowFocus = FocusNode(debugLabel: 'Inventory row');
  late final FocusNode _ownedFocus = FocusNode()..addListener(_ownedFocusLost);
  late final FocusNode _sourceFocus = FocusNode();
  late final TextEditingController _ownedText = TextEditingController(
    text: formatGroupedEditableQuantity(widget.item.owned),
  );
  late final TextEditingController _sourceText = TextEditingController(
    text: widget.item.sourceNote ?? '',
  );
  Timer? _sourceTimer;
  String? _ownedError;
  late String _lastCommittedOwned;
  String _lastCommittedSource = '';

  @override
  void initState() {
    super.initState();
    _lastCommittedOwned = _ownedText.text;
    _lastCommittedSource = widget.item.sourceNote ?? '';
    widget.onRegisterFocus(widget.item.name, _rowFocus);
  }

  @override
  void didUpdateWidget(InventoryItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.name != widget.item.name) {
      widget.onUnregisterFocus(oldWidget.item.name, _rowFocus);
      widget.onRegisterFocus(widget.item.name, _rowFocus);
    }
    if (!_ownedFocus.hasFocus && oldWidget.item.owned != widget.item.owned) {
      _ownedText.text = formatGroupedEditableQuantity(widget.item.owned);
      _lastCommittedOwned = _ownedText.text;
    }
    final source = widget.item.sourceNote ?? '';
    if (!_sourceFocus.hasFocus &&
        _sourceText.text != source &&
        _sourceTimer == null) {
      _sourceText.value = TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: source.length),
      );
      _lastCommittedSource = source;
    }
  }

  @override
  void dispose() {
    widget.onUnregisterFocus(widget.item.name, _rowFocus);
    _sourceTimer?.cancel();
    final pendingOwned = _ownedText.text;
    if (pendingOwned != _lastCommittedOwned) {
      final commit = widget.onCommitOwned;
      scheduleMicrotask(() => commit(pendingOwned));
    }
    final pending = _sourceText.text;
    if (pending != _lastCommittedSource) {
      final commit = widget.onSourceNoteCommitted;
      scheduleMicrotask(() => commit(pending));
    }
    _rowFocus.dispose();
    _ownedFocus
      ..removeListener(_ownedFocusLost)
      ..dispose();
    _sourceFocus.dispose();
    _ownedText.dispose();
    _sourceText.dispose();
    super.dispose();
  }

  void _ownedFocusLost() {
    if (!_ownedFocus.hasFocus) _commitOwned();
  }

  void _commitOwned([String? _]) {
    final parsed = parsePlannerNumber(_ownedText.text);
    final accepted = parsed != null && widget.onCommitOwned(_ownedText.text);
    if (accepted) {
      final display = formatGroupedEditableQuantity(parsed);
      _ownedText.value = TextEditingValue(
        text: display,
        selection: TextSelection.collapsed(offset: display.length),
      );
      _lastCommittedOwned = _ownedText.text;
      setState(() => _ownedError = null);
      return;
    }
    setState(() => _ownedError = 'Use 0 or a positive number');
  }

  void _sourceChanged(String _) {
    _sourceTimer?.cancel();
    _sourceTimer = Timer(widget.sourceNoteDebounce, _commitSource);
  }

  void _commitSource([String? _]) {
    _sourceTimer?.cancel();
    _sourceTimer = null;
    final value = _sourceText.text;
    if (value == _lastCommittedSource) return;
    _lastCommittedSource = value;
    widget.onSourceNoteCommitted(value);
  }

  KeyEventResult _onRowKey(FocusNode node, KeyEvent event) {
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
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      widget.onCopy(widget.item.name);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final standard = context.visualTheme.isStandard;
    final tone = widget.item.owned > 0
        ? AppSurfaceTone.success
        : AppSurfaceTone.neutral;
    return FocusTraversalOrder(
      order: NumericFocusOrder(widget.index.toDouble()),
      child: Focus(
        key: InventoryActionKeys.row('I14', widget.item.name),
        focusNode: _rowFocus,
        onKeyEvent: _onRowKey,
        onFocusChange: (focused) {
          if (focused) widget.onSelected(widget.item.name);
        },
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          selected: widget.selected,
          label:
              '${widget.item.name}, ${widget.item.category}, '
              '${formatQuantity(widget.item.owned)} owned',
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTap: () {
              _rowFocus.requestFocus();
              widget.onSelected(widget.item.name);
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: widget.fixedStandardColumns ? 90 : 0,
              ),
              child: AppSurface(
                role: AppSurfaceRole.card,
                tone: tone,
                // In Standard the source field is the card's lower edge. A
                // second eight-pixel strip beneath it read as a detached drop
                // shadow, especially over atmospheric backdrops. Let the
                // control consume that authored space; Ledger keeps its
                // manuscript inset.
                padding: EdgeInsets.fromLTRB(10, 8, 10, standard ? 0 : 8),
                child: widget.compact
                    ? _compact(context)
                    : widget.fixedStandardColumns
                    ? _fixedWide(context)
                    : _fluidWide(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fixedWide(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 40,
            child: Align(
              alignment: Alignment.centerLeft,
              child: InventoryItemIcon(
                controller: widget.controller,
                name: widget.item.name,
                size: 36,
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(width: 250, child: _nameAction(context)),
          const SizedBox(width: 14),
          SizedBox(width: 100, child: _ownedField()),
          const SizedBox(width: 14),
          SizedBox(width: widget.categoryWidth, child: _categorySelect()),
          const SizedBox(width: 14),
          SizedBox(
            width: 46,
            child: Align(
              alignment: Alignment.centerLeft,
              child: widget.showDeleteTool ? _deleteButton() : null,
            ),
          ),
        ],
      ),
      const SizedBox(height: 7),
      Padding(
        padding: const EdgeInsets.only(left: 54),
        child: SizedBox(
          width:
              (widget.showDeleteTool ? 628 : 568) +
              (widget.categoryWidth - 190),
          child: _sourceField(),
        ),
      ),
    ],
  );

  Widget _fluidWide(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Row(
        children: <Widget>[
          SizedBox(
            width: 40,
            child: Align(
              alignment: Alignment.centerLeft,
              child: InventoryItemIcon(
                controller: widget.controller,
                name: widget.item.name,
                size: 36,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: _nameAction(context)),
          const SizedBox(width: 14),
          SizedBox(width: 104, child: _ownedField()),
          const SizedBox(width: 14),
          SizedBox(width: widget.categoryWidth, child: _categorySelect()),
          const SizedBox(width: 14),
          SizedBox(
            width: 46,
            child: Align(
              alignment: Alignment.centerLeft,
              child: widget.showDeleteTool ? _deleteButton() : null,
            ),
          ),
        ],
      ),
      const SizedBox(height: 7),
      Padding(
        padding: EdgeInsets.only(
          left: 54,
          right: widget.showDeleteTool ? 0 : 60,
        ),
        child: _sourceField(),
      ),
    ],
  );

  Widget _compact(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Row(
        children: <Widget>[
          InventoryItemIcon(
            controller: widget.controller,
            name: widget.item.name,
            size: 38,
          ),
          const SizedBox(width: 8),
          Expanded(child: _nameAction(context)),
          if (widget.showDeleteTool) ...<Widget>[
            const SizedBox(width: 7),
            _deleteButton(),
          ],
        ],
      ),
      const SizedBox(height: 7),
      Row(
        children: <Widget>[
          SizedBox(width: 104, child: _ownedField()),
          const SizedBox(width: 8),
          Expanded(child: _categorySelect()),
        ],
      ),
      const SizedBox(height: 7),
      _sourceField(),
    ],
  );

  Widget _nameAction(BuildContext context) {
    final spec = context.visualTheme;
    final standard = spec.isStandard;
    return Semantics(
      label: 'I09 Copy exact item name ${widget.item.name}',
      button: true,
      excludeSemantics: true,
      child: Tooltip(
        message: 'Copy ${widget.item.name}',
        child: TextButton(
          key: InventoryActionKeys.row('I09', widget.item.name),
          onPressed: () => widget.onCopy(widget.item.name),
          style: ButtonStyle(
            alignment: Alignment.centerLeft,
            padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
              EdgeInsets.zero,
            ),
            minimumSize: const WidgetStatePropertyAll<Size>(Size.zero),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: const WidgetStatePropertyAll<Color>(
              Colors.transparent,
            ),
            overlayColor: const WidgetStatePropertyAll<Color>(
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
                  color: standard ? const Color(0xFFFFF0D0) : spec.palette.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.item.category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: spec.typography.meta.copyWith(
                  color: standard
                      ? const Color(0xFFAFC0BA)
                      : spec.palette.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.normal,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ownedField() => KeyedSubtree(
    key: InventoryActionKeys.row('I10', widget.item.name),
    child: SizedBox(
      height: _referenceControlHeight(38),
      child: AppTextField(
        controller: _ownedText,
        focusNode: _ownedFocus,
        minimumHeight: _referenceControlHeight(38),
        semanticLabel: 'I10 Owned amount for ${widget.item.name}',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.right,
        onSubmitted: _commitOwned,
        suffixIcon: _ownedError == null
            ? null
            : Tooltip(
                message: _ownedError!,
                child: const Icon(Icons.error_outline, size: 17),
              ),
      ),
    ),
  );

  Widget _categorySelect() => KeyedSubtree(
    key: InventoryActionKeys.row('I11', widget.item.name),
    child: SizedBox(
      height: _referenceControlHeight(38),
      child: AppSelect<String>(
        value: widget.item.category,
        items: widget.categories,
        labelFor: (value) => value,
        semanticLabel: 'I11 Category for ${widget.item.name}',
        onChanged: (value) {
          if (value != null) widget.onCategoryChanged(value);
        },
      ),
    ),
  );

  Widget _sourceField() => KeyedSubtree(
    key: InventoryActionKeys.row('I12', widget.item.name),
    child: SizedBox(
      height: _referenceControlHeight(
        context.visualTheme.usesDenseSplitLayout ? 30 : 38,
      ),
      child: AppTextField(
        controller: _sourceText,
        focusNode: _sourceFocus,
        emphasis: AppTextFieldEmphasis.subdued,
        semanticLabel: 'I12 Source note for ${widget.item.name}',
        hintText: 'Optional source note',
        textStyle: context.visualTheme.typography.body.copyWith(
          fontSize: 12,
          height: 1.1,
        ),
        onChanged: _sourceChanged,
        onSubmitted: _commitSource,
      ),
    ),
  );

  double? _referenceControlHeight(double height) =>
      MediaQuery.textScalerOf(context).scale(1) <= 1.25 ? height : null;

  Widget _deleteButton() => SizedBox(
    width: 42,
    height: 38,
    child: AppButton(
      key: InventoryActionKeys.row('I13', widget.item.name),
      role: AppButtonRole.icon,
      minimumSize: const Size(42, 38),
      padding: const EdgeInsets.all(8),
      semanticLabel: 'I13 Hide ${widget.item.name}',
      tooltip: 'Hide item',
      onPressed: widget.onHideOrDelete,
      child: const AppVectorGlyph('trash', size: 18),
    ),
  );
}

class InventoryItemIcon extends StatelessWidget {
  const InventoryItemIcon({
    required this.controller,
    required this.name,
    this.size = 40,
    super.key,
  });

  final ModeFeatureController controller;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) =>
      ModeItemIcon(controller: controller, name: name, size: size);
}
