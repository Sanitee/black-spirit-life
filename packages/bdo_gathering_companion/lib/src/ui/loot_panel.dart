import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/models.dart';
import '../services/loot_recognizer.dart';
import '../services/native_bridge.dart';
import 'field_desk_materials.dart';
import 'theme.dart';

const _maximumAmount = 999999999999;
const _batchHelp =
    'Only amounts absent from your final inventory screenshot, such as maid deposits.';

int? _amount(String value, {bool positive = false}) {
  final trimmed = value.trim();
  if (!RegExp(
    r'^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+|[0-9]{1,3}(?: [0-9]{3})+)$',
  ).hasMatch(trimmed)) {
    return null;
  }
  final result = int.tryParse(trimmed.replaceAll(RegExp(r'[, ]'), ''));
  if (result == null ||
      result < (positive ? 1 : 0) ||
      result > _maximumAmount) {
    return null;
  }
  return result;
}

/// Local image review and explicit inventory accounting for one session.
/// Images and duplicate fingerprints never enter the saved session data.
class LootPanel extends StatefulWidget {
  const LootPanel({
    super.key,
    required this.catalog,
    required this.entries,
    required this.onChanged,
    this.suggestedItems = const [],
    this.onValidityChanged,
    this.scrollable = false,
  });

  final Catalog catalog;
  final Map<String, LootEntry> entries;
  final VoidCallback onChanged;
  final List<GameItem> suggestedItems;
  final ValueChanged<bool>? onValidityChanged;

  /// Keep the header visible inside a parent with a bounded height.
  final bool scrollable;

  @override
  State<LootPanel> createState() => _LootPanelState();
}

class _LootPanelState extends State<LootPanel> {
  final _recognizer = LootRecognizer();
  final _appliedFingerprints = <String>{};
  bool _busy = false;
  String? _error;
  final _manualSearch = TextEditingController();
  final _manualAmount = TextEditingController();
  final _itemFocus = FocusNode();
  final _amountFocus = FocusNode();
  final _scroll = ScrollController();
  GameItem? _manualItem;
  bool _setTotal = true, _showOther = false;
  final _totals = <String, TextEditingController>{};
  final _entryValues = <String, String?>{};
  final _pendingItems = <String, GameItem>{};
  final _invalidTotals = <String>{};
  bool? _reportedValidity;
  bool _validityScheduled = false;

  bool get _canAdd {
    final amount = _amount(_manualAmount.text, positive: !_setTotal);
    if (_busy || _manualItem == null || amount == null) return false;
    if (_setTotal) return true;
    final entry = widget.entries[_manualItem!.id];
    return (entry?.sentAway ?? 0) + amount <= _maximumAmount &&
        (entry?.overrideTotal != null ||
            (entry?.rawTotal ?? 0) + amount <= _maximumAmount);
  }

  bool get _valid =>
      !_busy &&
      _invalidTotals.isEmpty &&
      widget.entries.values.every(
        (entry) => entry.rawTotal >= 0 && entry.rawTotal <= _maximumAmount,
      ) &&
      _manualAmount.text.trim().isEmpty;

  List<GameItem> get _items {
    final result = <String, GameItem>{
      for (final item in widget.suggestedItems) item.id: item,
    };
    final existing = widget.entries.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final entry in existing) {
      result.putIfAbsent(
        entry.id,
        () =>
            GameItem({'id': entry.id, 'name': entry.name, 'icon': entry.icon}),
      );
    }
    for (final item in _pendingItems.values) {
      result.putIfAbsent(item.id, () => item);
    }
    return result.values.toList();
  }

  String? _entryValue(LootEntry? entry) => entry == null
      ? null
      : '${entry.start}/${entry.remaining}/${entry.sentAway}/${entry.overrideTotal}/${entry.hasInventorySnapshot}/${entry.isApproximate}/${entry.observationsApproximate}';

  void _reportValidity({bool defer = false}) {
    if (defer) {
      if (_validityScheduled) return;
      _validityScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _validityScheduled = false;
        if (mounted) _reportValidity();
      });
      return;
    }
    final valid = _valid;
    if (_reportedValidity != valid) {
      _reportedValidity = valid;
      widget.onValidityChanged?.call(valid);
    }
  }

  void _syncTotals() {
    final items = _items;
    final visibleIds = items.map((item) => item.id).toSet();
    for (final id
        in _totals.keys.where((id) => !visibleIds.contains(id)).toList()) {
      _totals.remove(id)!.dispose();
      _entryValues.remove(id);
      _invalidTotals.remove(id);
    }
    for (final item in items) {
      final entry = widget.entries[item.id];
      final value = _entryValue(entry);
      final fresh = !_totals.containsKey(item.id);
      final field = _totals.putIfAbsent(item.id, TextEditingController.new);
      if (fresh || _entryValues[item.id] != value) {
        field.text = entry == null ? '' : countText(entry.rawTotal);
        _invalidTotals.remove(item.id);
      }
      _entryValues[item.id] = value;
    }
  }

  @override
  void initState() {
    super.initState();
    _syncTotals();
    _reportValidity(defer: true);
  }

  @override
  void didUpdateWidget(covariant LootPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entries, widget.entries)) {
      _appliedFingerprints.clear();
      _error = null;
      _pendingItems.clear();
      _invalidTotals.clear();
      _entryValues.clear();
      for (final field in _totals.values) {
        field.dispose();
      }
      _totals.clear();
      _manualAmount.clear();
    }
    _syncTotals();
    if (oldWidget.onValidityChanged == null &&
        widget.onValidityChanged != null) {
      _reportedValidity = null;
    }
    _reportValidity(defer: true);
  }

  @override
  void dispose() {
    _recognizer.dispose();
    _appliedFingerprints.clear();
    _manualSearch.dispose();
    _manualAmount.dispose();
    _itemFocus.dispose();
    _amountFocus.dispose();
    _scroll.dispose();
    for (final field in _totals.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _readImage({required bool clipboard}) async {
    if (_busy) return;
    final sessionEntries = widget.entries;
    setState(() {
      _busy = true;
      _error = null;
    });
    _reportValidity();
    try {
      Uint8List? bytes;
      var fileName = 'clipboard.png';
      if (clipboard) {
        bytes = await NativeBridge.readClipboardImage();
        if (bytes == null || bytes.isEmpty) {
          throw const FormatException(
            'No image on the clipboard. Copy a screenshot first, or choose an image file.',
          );
        }
      } else {
        final path = await NativeBridge.pickImage();
        if (path == null) return;
        final file = File(path);
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
          throw const FormatException('That image could not be opened.');
        }
        if (stat.size > LootRecognizer.maximumScreenshotBytes) {
          throw const FormatException(
            'Choose a screenshot smaller than 16 MB.',
          );
        }
        bytes = await file.readAsBytes();
        fileName = path.split(RegExp(r'[/\\]')).last;
      }
      if (!mounted || !identical(sessionEntries, widget.entries)) return;
      final fingerprint = sha256.convert(bytes).toString();
      if (_appliedFingerprints.contains(fingerprint)) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('This screenshot was already used'),
            content: const Text(
              'The exact same image was applied to this session. A final inventory snapshot replaces amounts, but adding it as another maid deposit could count the same loot twice.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Review again'),
              ),
            ],
          ),
        );
        if (proceed != true || !mounted) return;
      }
      final result = await _recognizer.scanBytes(bytes, fileName: fileName);
      if (!mounted || !identical(sessionEntries, widget.entries)) return;
      if (result.rows.isEmpty) {
        setState(() {
          _error = result.warnings.isEmpty
              ? 'No items found. Try a clear inventory crop, or enter items manually.'
              : result.warnings.join(' ');
        });
        return;
      }
      final reviewed = await showDialog<_ReviewedLoot>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _ReviewDialog(
          catalog: widget.catalog,
          result: result,
          image: bytes!,
        ),
      );
      if (!mounted ||
          reviewed == null ||
          !identical(sessionEntries, widget.entries)) {
        return;
      }
      for (final row in reviewed.rows) {
        final entry = widget.entries.putIfAbsent(
          row.item.id,
          () => LootEntry(
            id: row.item.id,
            name: row.item.name,
            icon: row.item.icon,
          ),
        );
        switch (reviewed.mode) {
          case _InventoryMode.snapshot:
            entry.setSnapshot(row.quantity, approximate: row.isApproximate);
          case _InventoryMode.batch:
            entry.recordMaidDeposit(
              row.quantity,
              approximate: row.isApproximate,
            );
          case _InventoryMode.start:
            entry.setStart(row.quantity, approximate: row.isApproximate);
        }
        _entryValues.remove(row.item.id);
      }
      _appliedFingerprints.add(fingerprint);
      _syncTotals();
      widget.onChanged();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.message ?? 'The desktop image action failed.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The screenshot could not be read. Try another crop, or enter the amounts manually.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reportValidity();
      }
    }
  }

  void _addInline() {
    if (!_canAdd) return;
    final item = _manualItem!;
    final amount = _amount(_manualAmount.text, positive: !_setTotal)!;
    final entry = widget.entries.putIfAbsent(
      item.id,
      () => LootEntry(id: item.id, name: item.name, icon: item.icon),
    );
    if (_setTotal) {
      entry.overrideTotal = amount;
      entry.isApproximate = false;
    } else {
      entry.recordMaidDeposit(amount);
    }
    setState(() {
      _error = null;
      _manualAmount.clear();
      _entryValues.remove(item.id);
      _syncTotals();
    });
    _reportValidity();
    widget.onChanged();
    _amountFocus.requestFocus();
  }

  Future<void> _edit(LootEntry entry) async {
    final sessionEntries = widget.entries;
    final result = await showDialog<_EditedLoot>(
      context: context,
      builder: (context) => _EditDialog(entry: entry),
    );
    if (!mounted ||
        result == null ||
        !identical(sessionEntries, widget.entries)) {
      return;
    }
    if (result.remove) {
      widget.entries.remove(entry.id);
      _pendingItems.remove(entry.id);
      _totals[entry.id]?.clear();
    } else {
      entry
        ..start = result.start
        ..remaining = result.remaining
        ..hasInventorySnapshot = true
        ..sentAway = result.sentAway
        ..overrideTotal = result.overrideTotal;
      if (result.overrideTotal != null) entry.isApproximate = false;
    }
    _entryValues.remove(entry.id);
    _invalidTotals.remove(entry.id);
    setState(_syncTotals);
    _reportValidity();
    widget.onChanged();
  }

  void _changeTotal(GameItem item, String text) {
    final value = _amount(text);
    setState(() {
      if (text.trim().isEmpty) {
        _invalidTotals.remove(item.id);
        _pendingItems.remove(item.id);
        final entry = widget.entries[item.id];
        if (entry != null &&
            (entry.hasInventorySnapshot ||
                entry.start != 0 ||
                entry.remaining != 0 ||
                entry.sentAway != 0)) {
          entry.overrideTotal = null;
          _totals[item.id]!.text = countText(entry.rawTotal);
        } else {
          widget.entries.remove(item.id);
        }
        _entryValues[item.id] = _entryValue(widget.entries[item.id]);
      } else if (value == null) {
        _pendingItems[item.id] = item;
        _invalidTotals.add(item.id);
      } else {
        final entry = widget.entries.putIfAbsent(
          item.id,
          () => LootEntry(id: item.id, name: item.name, icon: item.icon),
        );
        entry.overrideTotal = value;
        entry.isApproximate = false;
        _pendingItems[item.id] = item;
        _invalidTotals.remove(item.id);
        _entryValues[item.id] = _entryValue(entry);
      }
    });
    _reportValidity();
    widget.onChanged();
  }

  Future<void> _maidDeposit(GameItem item) async {
    final sessionEntries = widget.entries;
    final entry = widget.entries[item.id];
    final amount = await showDialog<int>(
      context: context,
      builder: (context) => _MaidDepositDialog(item: item, entry: entry),
    );
    if (!mounted ||
        amount == null ||
        !identical(sessionEntries, widget.entries)) {
      return;
    }
    final target = widget.entries.putIfAbsent(
      item.id,
      () => LootEntry(id: item.id, name: item.name, icon: item.icon),
    );
    target.recordMaidDeposit(amount);
    setState(_syncTotals);
    _reportValidity();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final header = FieldDeskSectionHeading(
      title: 'Loot',
      prominent: true,
      action: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          TextButton.icon(
            key: const ValueKey('paste-screenshot'),
            onPressed: _busy ? null : () => _readImage(clipboard: true),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.content_paste, size: 16),
            label: Text(
              _busy ? 'Checking…' : 'Paste screenshot',
              style: const TextStyle(fontSize: 14),
            ),
          ),
          TextButton.icon(
            key: const ValueKey('open-screenshot'),
            onPressed: _busy ? null : () => _readImage(clipboard: false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.image_outlined, size: 19),
            label: const Text(
              'Open screenshot',
              style: TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isNotEmpty) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final minimumColumnWidth = MediaQuery.textScalerOf(
                context,
              ).scale(306);
              final columns = ((constraints.maxWidth + 14) / minimumColumnWidth)
                  .floor()
                  .clamp(1, 4);
              final width =
                  (constraints.maxWidth - (columns - 1) * 14) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  for (final item in items)
                    SizedBox(width: width, child: _quantityRow(item)),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
        ],
        TextButton.icon(
          key: const ValueKey('other-item'),
          onPressed: _busy
              ? null
              : () => setState(() => _showOther = !_showOther),
          icon: Icon(_showOther ? Icons.expand_less : Icons.add, size: 17),
          label: const Text('Other item'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        if (_showOther)
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 570;
              final itemWidth = constraints.maxWidth - (wide ? 318 : 116);
              final item = _inlineItem(itemWidth);
              final amount = SizedBox(
                width: 108,
                height: 46,
                child: TextField(
                  key: const ValueKey('manual-quantity'),
                  controller: _manualAmount,
                  focusNode: _amountFocus,
                  enabled: !_busy,
                  style: const TextStyle(fontSize: 15),
                  keyboardType: TextInputType.number,
                  onChanged: (_) {
                    setState(() {});
                    _reportValidity();
                  },
                  onSubmitted: (_) => _addInline(),
                  decoration: InputDecoration(
                    hintText: 'Amount',
                    errorText:
                        _manualAmount.text.trim().isNotEmpty &&
                            _amount(_manualAmount.text, positive: !_setTotal) ==
                                null
                        ? 'Invalid'
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                ),
              );
              final mode = Tooltip(
                message: _setTotal
                    ? 'Replace the whole amount gathered for this item.'
                    : _batchHelp,
                child: Container(
                  width: 140,
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    border: Border.all(color: context.glass.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<bool>(
                      key: const ValueKey('manual-mode'),
                      value: _setTotal,
                      isDense: true,
                      isExpanded: true,
                      iconSize: 16,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.gatheringColors.ink,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: false,
                          child: Text('Maid deposit'),
                        ),
                        DropdownMenuItem(value: true, child: Text('Set total')),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) {
                              setState(() => _setTotal = value ?? true);
                              _reportValidity();
                            },
                    ),
                  ),
                ),
              );
              final add = Tooltip(
                message: _setTotal
                    ? 'Set total · Enter'
                    : 'Add maid deposit · Enter',
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: FilledButton(
                    key: const ValueKey('manual-add'),
                    onPressed: _canAdd ? _addInline : null,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(46, 46),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Icon(_setTotal ? Icons.check : Icons.add, size: 19),
                  ),
                ),
              );
              if (wide) {
                return Row(
                  children: [
                    item,
                    const SizedBox(width: 8),
                    amount,
                    const SizedBox(width: 8),
                    mode,
                    const SizedBox(width: 8),
                    add,
                  ],
                );
              }
              return Column(
                children: [
                  Row(children: [item, const SizedBox(width: 8), amount]),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Spacer(),
                      mode,
                      const SizedBox(width: 8),
                      add,
                    ],
                  ),
                ],
              );
            },
          ),
        if (_showOther &&
            !_setTotal &&
            widget.entries[_manualItem?.id]?.overrideTotal != null)
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Included in your overall total; used when you import inventory.',
              style: TextStyle(
                fontSize: 12,
                color: context.gatheringColors.muted,
              ),
            ),
          ),
        if (_busy) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (_error case final error?) ...[
          const SizedBox(height: 8),
          _Notice(error, warning: true),
        ],
      ],
    );
    return Column(
      mainAxisSize: widget.scrollable ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 6),
        if (widget.scrollable)
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                key: const ValueKey('loot-body-scroll'),
                controller: _scroll,
                primary: false,
                child: body,
              ),
            ),
          )
        else
          body,
      ],
    );
  }

  Widget _quantityRow(GameItem item) {
    final entry = widget.entries[item.id];
    final invalid = _invalidTotals.contains(item.id);
    final negative = entry != null && entry.rawTotal < 0;
    final help = entry?.overrideTotal != null
        ? 'Total gathered for the whole session. Clearing it restores recorded inventory and maid deposits.'
        : '${countText(entry?.remaining ?? 0)} in bag − ${countText(entry?.start ?? 0)} starting + ${countText(entry?.sentAway ?? 0)} maid deposits. Type the whole total gathered to replace this calculation.';
    return DecoratedBox(
      key: ValueKey('loot-row-${item.id}'),
      decoration: context.glass.segmentedDecoration(
        BoxDecoration(
          gradient: context.glass.controlGradient,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.glass.line),
        ),
        leadingWidth: 44,
        leadingHeight: 56,
        trailingWidth: 138,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Tooltip(
                  message: item.name,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: GlassArtworkWell(
                      child: GameIcon(item.icon, size: 40),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Tooltip(
                    message: item.name,
                    child: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: help,
                  child: SizedBox(
                    width: 106,
                    child: TextField(
                      key: ValueKey('loot-total-${item.id}'),
                      controller: _totals[item.id],
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: negative
                            ? Theme.of(context).colorScheme.error
                            : context.gatheringColors.ink,
                      ),
                      onChanged: (text) => _changeTotal(item, text),
                      decoration: InputDecoration(
                        hintText: 'Total',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: context.gatheringColors.muted,
                        ),
                        prefixText: entry?.isApproximate == true ? '≈ ' : null,
                        isDense: true,
                        errorText: invalid ? 'Whole number' : null,
                        errorStyle: const TextStyle(fontSize: 10),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 11,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 30,
                  child: PopupMenuButton<String>(
                    key: ValueKey('loot-actions-${item.id}'),
                    tooltip: 'Options for ${item.name}',
                    enabled: !_busy,
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    onSelected: (action) {
                      if (action == 'maid') _maidDeposit(item);
                      if (action == 'edit' && entry != null) _edit(entry);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'maid',
                        enabled: !invalid,
                        child: const Tooltip(
                          message: _batchHelp,
                          child: Text('Add maid deposit'),
                        ),
                      ),
                      if (entry != null)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Inventory details'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (negative)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Starting stock exceeds recorded loot. Check amounts.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _inlineItem(double width) => SizedBox(
    width: width,
    child: RawAutocomplete<GameItem>(
      textEditingController: _manualSearch,
      focusNode: _itemFocus,
      displayStringForOption: (item) => item.name,
      optionsBuilder: (value) =>
          _busy ? const <GameItem>[] : _search(widget.catalog, value.text),
      onSelected: (item) {
        setState(() => _manualItem = item);
        _amountFocus.requestFocus();
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
          SizedBox(
            height: 46,
            child: TextField(
              key: const ValueKey('manual-item'),
              controller: controller,
              focusNode: focusNode,
              enabled: !_busy,
              style: const TextStyle(fontSize: 15),
              onChanged: (value) {
                if (_manualItem?.name != value) {
                  setState(() => _manualItem = null);
                }
              },
              onSubmitted: (_) => onSubmitted(),
              decoration: InputDecoration(
                hintText: 'Search items…',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                prefixIcon: _manualItem == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.all(6),
                        child: GameIcon(_manualItem!.icon, size: 32),
                      ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 40,
                  maxWidth: 44,
                ),
              ),
            ),
          ),
      optionsViewBuilder: (context, select, options) {
        final matches = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            color: context.glass.panel,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: width,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(4),
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final item = matches[index];
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      selected:
                          AutocompleteHighlightedOption.of(context) == index,
                      selectedTileColor: context.glass.accentSelection,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: GameIcon(item.icon, size: 36),
                      title: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                      onTap: () => select(item),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.warning = false});
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: warning
          ? context.gatheringColors.gold.withValues(alpha: .10)
          : context.glass.inset,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: warning
            ? context.gatheringColors.gold.withValues(alpha: .5)
            : context.glass.line,
      ),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 14,
        color: warning
            ? context.gatheringColors.gold
            : context.gatheringColors.muted,
      ),
    ),
  );
}

class _MaidDepositDialog extends StatefulWidget {
  const _MaidDepositDialog({required this.item, this.entry});
  final GameItem item;
  final LootEntry? entry;
  @override
  State<_MaidDepositDialog> createState() => _MaidDepositDialogState();
}

class _MaidDepositDialogState extends State<_MaidDepositDialog> {
  final _quantity = TextEditingController();
  int? get _value => _amount(_quantity.text, positive: true);
  bool get _valid =>
      _value != null &&
      (widget.entry?.sentAway ?? 0) + _value! <= _maximumAmount &&
      (widget.entry?.overrideTotal != null ||
          (widget.entry?.rawTotal ?? 0) + _value! <= _maximumAmount);
  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  void _apply() {
    if (_valid) Navigator.pop(context, _value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Expanded(child: Text('Add maid deposit')),
        Tooltip(message: _batchHelp, child: Icon(Icons.info_outline, size: 19)),
      ],
    ),
    content: SizedBox(
      width: 370,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GameIcon(widget.item.icon, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.item.name,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('maid-quantity'),
            controller: _quantity,
            autofocus: true,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _apply(),
            decoration: InputDecoration(
              labelText: 'Amount sent away',
              errorText: _quantity.text.isNotEmpty && !_valid
                  ? 'Enter a positive whole amount.'
                  : null,
            ),
          ),
          if (widget.entry?.overrideTotal != null) ...[
            const SizedBox(height: 12),
            Text(
              'Included in your overall total; used when you import inventory.',
              style: TextStyle(
                fontSize: 12,
                color: context.gatheringColors.muted,
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('maid-add'),
        onPressed: _valid ? _apply : null,
        child: const Text('Add deposit'),
      ),
    ],
  );
}

enum _InventoryMode { snapshot, batch, start }

class _LootAmount {
  const _LootAmount(this.item, this.quantity, {this.isApproximate = false});
  final GameItem item;
  final int quantity;
  final bool isApproximate;
}

class _ReviewedLoot {
  const _ReviewedLoot(this.mode, this.rows);
  final _InventoryMode mode;
  final List<_LootAmount> rows;
}

class _ReviewRow {
  _ReviewRow(LootScanRow source, Catalog catalog)
    : quantity = TextEditingController(text: source.quantity?.toString() ?? ''),
      needsReview = source.needsReview,
      checked = !source.needsReview,
      isApproximate = source.isApproximate,
      note = source.note,
      originalName = source.name {
    item = catalog.items
        .where((i) => i.id == source.itemId?.toString())
        .firstOrNull;
    if (item == null && source.itemId != null) {
      item = GameItem({
        'id': source.itemId,
        'name': source.name,
        'icon': source.iconAsset ?? '',
      });
    }
  }
  GameItem? item;
  final TextEditingController quantity;
  final bool needsReview;
  final String? note;
  final String originalName;
  bool checked;
  bool isApproximate;
  bool excluded = false;
  void dispose() => quantity.dispose();
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({
    required this.catalog,
    required this.result,
    required this.image,
  });
  final Catalog catalog;
  final LootScanResult result;
  final Uint8List image;
  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late final _rows = widget.result.rows
      .map((row) => _ReviewRow(row, widget.catalog))
      .toList();
  final _scroll = ScrollController();
  var _mode = _InventoryMode.snapshot;
  bool _showImage = false;

  List<_ReviewRow> get _included =>
      _rows.where((row) => !row.excluded).toList();
  bool _valid(_ReviewRow row) =>
      row.item != null &&
      row.checked &&
      _amount(row.quantity.text, positive: _mode == _InventoryMode.batch) !=
          null;
  bool get _canApply {
    if (_included.isEmpty || !_included.every(_valid)) return false;
    final totals = <String, int>{};
    for (final row in _included) {
      final id = row.item!.id;
      totals[id] = (totals[id] ?? 0) + _amount(row.quantity.text)!;
      if (totals[id]! > _maximumAmount) return false;
    }
    return true;
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    MemoryImage(widget.image).evict();
    _scroll.dispose();
    super.dispose();
  }

  void _apply() {
    if (!_canApply) return;
    final combined = <String, _LootAmount>{};
    for (final row in _included) {
      final item = row.item!;
      combined[item.id] = _LootAmount(
        item,
        (combined[item.id]?.quantity ?? 0) + _amount(row.quantity.text)!,
        isApproximate:
            row.isApproximate || (combined[item.id]?.isApproximate ?? false),
      );
    }
    Navigator.pop(context, _ReviewedLoot(_mode, combined.values.toList()));
  }

  Future<void> _choose(_ReviewRow row) async {
    final item = await showDialog<GameItem>(
      context: context,
      builder: (context) => _ItemPicker(catalog: widget.catalog),
    );
    if (!mounted || item == null) return;
    setState(() => row.item = item);
  }

  @override
  Widget build(BuildContext context) {
    final needsCheck = _included.where((row) => !_valid(row)).length;
    return _DialogFrame(
      title: 'Review your screenshot',
      subtitle:
          '${_included.length} included rows${needsCheck > 0 ? ' · $needsCheck need checking' : ' · ready to apply'}',
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: _canApply ? _apply : null,
          child: const Text('Apply checked items'),
        ),
      ],
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          controller: _scroll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'What do these amounts represent?',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              RadioGroup<_InventoryMode>(
                groupValue: _mode,
                onChanged: (value) {
                  if (value != null) setState(() => _mode = value);
                },
                child: Column(
                  children: const [
                    RadioListTile<_InventoryMode>(
                      value: _InventoryMode.snapshot,
                      title: Text('Final inventory'),
                      subtitle: Text(
                        'Replace the inventory amount; subtract starting stock.',
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<_InventoryMode>(
                      value: _InventoryMode.batch,
                      title: Text('Maid deposit'),
                      subtitle: Text(_batchHelp),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<_InventoryMode>(
                      value: _InventoryMode.start,
                      title: Text('Starting inventory'),
                      subtitle: Text(
                        'Use before gathering. Set both starting and current stock for these items.',
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const _Notice(
                'Only listed items are updated. Include all stacks of each item. Repeated rows for the same item are combined.',
              ),
              if (widget.result.warnings.isNotEmpty) ...[
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Reader notes',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.gatheringColors.muted,
                    ),
                  ),
                  children: [
                    for (final note in widget.result.warnings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            note,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.gatheringColors.muted,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              TextButton(
                onPressed: () => setState(() => _showImage = !_showImage),
                child: Text(
                  _showImage
                      ? 'Hide screenshot'
                      : 'View screenshot for comparison',
                ),
              ),
              if (_showImage) ...[
                SizedBox(
                  height: 240,
                  width: double.infinity,
                  child: InteractiveViewer(
                    maxScale: 6,
                    child: Image.memory(
                      widget.image,
                      fit: BoxFit.contain,
                      errorBuilder: (_, error, stack) =>
                          const Text('Preview unavailable.'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              for (var i = 0; i < _rows.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _row(_rows[i], i),
              ],
              const SizedBox(height: 12),
              Text(
                'The image is held only while this review is open. No screenshot file is saved.',
                style: TextStyle(
                  color: context.gatheringColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(_ReviewRow row, int index) {
    final incomplete = !row.excluded && !_valid(row);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: row.excluded ? context.glass.inset : context.glass.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: incomplete
              ? context.gatheringColors.gold.withValues(alpha: .7)
              : context.glass.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 3,
                  children: [
                    Text(
                      'Slot ${index + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.gatheringColors.muted,
                      ),
                    ),
                    if (row.needsReview && !row.excluded)
                      Text(
                        row.checked ? 'Checked' : 'Check item and amount',
                        style: TextStyle(
                          fontSize: 11,
                          color: row.checked
                              ? context.gatheringColors.accent
                              : context.gatheringColors.gold,
                        ),
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => row.excluded = !row.excluded),
                child: Text(row.excluded ? 'Include' : 'Exclude'),
              ),
            ],
          ),
          if (row.excluded)
            Text(
              '${row.item?.name ?? row.originalName} · excluded',
              style: TextStyle(color: context.gatheringColors.muted),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final selector = OutlinedButton(
                  onPressed: () => _choose(row),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(8),
                  ),
                  child: Row(
                    children: [
                      GameIcon(row.item?.icon ?? '', size: 32),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          row.item?.name ?? 'Choose the correct item',
                          maxLines: 3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Change',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.gatheringColors.muted,
                        ),
                      ),
                    ],
                  ),
                );
                final quantity = TextField(
                  key: ValueKey('scan-quantity-$index'),
                  controller: row.quantity,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => row.isApproximate = false),
                  decoration: const InputDecoration(labelText: 'Amount'),
                );
                if (constraints.maxWidth < 450) {
                  return Column(
                    children: [selector, const SizedBox(height: 10), quantity],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: selector),
                    const SizedBox(width: 12),
                    SizedBox(width: 150, child: quantity),
                  ],
                );
              },
            ),
            if (row.note case final note?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  note,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.gatheringColors.muted,
                  ),
                ),
              ),
            if (row.isApproximate)
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  '≈ Minimum amount. Enter an exact count if you know it.',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.gatheringColors.gold,
                  ),
                ),
              ),
            if (row.needsReview)
              CheckboxListTile(
                value: row.checked,
                onChanged: (value) =>
                    setState(() => row.checked = value ?? false),
                title: const Text(
                  'I checked this item and amount',
                  style: TextStyle(fontSize: 12),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
        ],
      ),
    );
  }
}

class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.title,
    this.subtitle,
    required this.child,
    required this.actions,
    this.width = 760,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final double width;
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(18),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: width,
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(
                subtitle!,
                style: TextStyle(
                  color: context.gatheringColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Flexible(child: child),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

List<GameItem> _search(Catalog catalog, String query) {
  final terms = query.trim().toLowerCase().split(RegExp(r'\s+'));
  return catalog.items
      .where((item) {
        final haystack = '${item.name} ${item.id}'.toLowerCase();
        return terms.every(haystack.contains);
      })
      .take(60)
      .toList();
}

class _ItemPicker extends StatefulWidget {
  const _ItemPicker({required this.catalog});
  final Catalog catalog;
  @override
  State<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<_ItemPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final items = _search(widget.catalog, _query);
    return _DialogFrame(
      title: 'Choose a game item',
      width: 560,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            autofocus: true,
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              labelText: 'Search items',
              hintText: 'Meat, hide, sap, item name…',
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: SizedBox(
              height: 360,
              child: items.isEmpty
                  ? const Center(
                      child: Text('No matching item. Try a shorter name.'),
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          leading: GameIcon(item.icon, size: 34),
                          title: Text(item.name),
                          dense: true,
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditedLoot {
  const _EditedLoot({
    this.remove = false,
    this.start = 0,
    this.remaining = 0,
    this.sentAway = 0,
    this.overrideTotal,
  });
  final bool remove;
  final int start, remaining, sentAway;
  final int? overrideTotal;
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.entry});
  final LootEntry entry;
  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _start = TextEditingController(
    text: widget.entry.start.toString(),
  );
  late final _remaining = TextEditingController(
    text: widget.entry.remaining.toString(),
  );
  late final _sent = TextEditingController(
    text: widget.entry.sentAway.toString(),
  );
  late final _total = TextEditingController(
    text: (widget.entry.overrideTotal ?? widget.entry.total).toString(),
  );
  late bool _override = widget.entry.overrideTotal != null;
  bool get _valid =>
      [_start, _remaining, _sent].every((c) => _amount(c.text) != null) &&
      (!_override || _amount(_total.text) != null);
  int get _calculated =>
      (_amount(_remaining.text) ?? 0) -
      (_amount(_start.text) ?? 0) +
      (_amount(_sent.text) ?? 0);
  int get _result => _override ? (_amount(_total.text) ?? 0) : _calculated;
  @override
  void dispose() {
    for (final c in [_start, _remaining, _sent, _total]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool enabled = true,
  }) => TextField(
    controller: controller,
    enabled: enabled,
    keyboardType: TextInputType.number,
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(labelText: label),
  );

  @override
  Widget build(BuildContext context) => _DialogFrame(
    title: widget.entry.name,
    subtitle: 'Edit the observations or enter one final session total.',
    width: 570,
    actions: [
      TextButton(
        onPressed: () =>
            Navigator.pop(context, const _EditedLoot(remove: true)),
        child: const Text('Remove item'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: !_valid
            ? null
            : () => Navigator.pop(
                context,
                _EditedLoot(
                  start: _amount(_start.text)!,
                  remaining: _amount(_remaining.text)!,
                  sentAway: _amount(_sent.text)!,
                  overrideTotal: _override ? _amount(_total.text) : null,
                ),
              ),
        child: const Text('Save changes'),
      ),
    ],
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field('Starting inventory', _start, enabled: !_override),
          const SizedBox(height: 12),
          _field(
            'Final inventory / still in your bag',
            _remaining,
            enabled: !_override,
          ),
          const SizedBox(height: 12),
          _field('Maid deposits / sent away', _sent, enabled: !_override),
          const SizedBox(height: 8),
          Text(
            _batchHelp,
            style: TextStyle(
              color: context.gatheringColors.muted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _override,
            onChanged: (value) => setState(() => _override = value),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Use a manual session total',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: const Text(
              'Overrides the inventory calculation for this item.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          if (_override) ...[
            const SizedBox(height: 10),
            _field('Whole session total', _total),
          ],
          const SizedBox(height: 16),
          if (!_override && widget.entry.observationsApproximate) ...[
            const _Notice(
              'Some observations came from abbreviated game counts. Set an exact whole session total to remove this approximation.',
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'Session total: ${countText(_result)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _result < 0
                  ? Theme.of(context).colorScheme.error
                  : context.gatheringColors.accent,
            ),
          ),
          if (_result < 0) ...[
            const SizedBox(height: 10),
            const _Notice(
              'This calculation is negative. Correct the observations before saving the session.',
              warning: true,
            ),
          ],
        ],
      ),
    ),
  );
}
