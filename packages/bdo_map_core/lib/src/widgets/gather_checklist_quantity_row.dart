import 'package:flutter/material.dart';

import '../checklist/gather_checklist_demand.dart';
import 'resource_map_chrome_theme.dart';
import 'resource_map_panel_metrics.dart';

/// Quantity controls are separate from the checklist's organizational checkbox.
class GatherChecklistQuantityRow extends StatefulWidget {
  const GatherChecklistQuantityRow({
    required this.resourceId,
    required this.quantity,
    required this.child,
    this.onRecord,
    super.key,
  });
  final String resourceId;
  final BdoGatherChecklistQuantity quantity;
  final BdoRecordGathered? onRecord;
  final Widget child;

  @override
  State<GatherChecklistQuantityRow> createState() =>
      _GatherChecklistQuantityRowState();
}

class _GatherChecklistQuantityRowState
    extends State<GatherChecklistQuantityRow> {
  final _amount = TextEditingController();
  bool _editing = false;
  bool _busy = false;
  String? _error;
  BdoGatherChecklistReceipt? _receipt;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    if (_busy || widget.onRecord == null) return;
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (amount == null || !amount.isFinite || amount <= 0) {
      setState(() => _error = 'Enter an amount above zero.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await widget.onRecord!(widget.resourceId, amount);
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _editing = false;
        _amount.clear();
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo() async {
    if (_busy || _receipt == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _receipt!.undo();
      if (mounted) setState(() => _receipt = null);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quantity = widget.quantity;
    final chrome = context.mapChrome;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.child,
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  for (final metric in [
                    ('Needed', quantity.needed),
                    ('Owned', quantity.owned),
                    ('Remaining', quantity.remaining),
                  ])
                    Semantics(
                      label: '${metric.$1} ${_number(metric.$2)}',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            metric.$1,
                            style: TextStyle(
                              color: chrome.muted,
                              fontSize: ResourceMapPanelMetrics.secondary,
                            ),
                          ),
                          Text(
                            _number(metric.$2),
                            style: TextStyle(
                              color: chrome.ink,
                              fontSize: ResourceMapPanelMetrics.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (quantity.canRecord && widget.onRecord != null)
                Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (!_editing)
                      TextButton(
                        key: ValueKey(
                          'gather-record-open:${widget.resourceId}',
                        ),
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _editing = true;
                                _error = null;
                              }),
                        child: const Text('Record gathered'),
                      ),
                    if (_receipt != null)
                      TextButton(
                        key: ValueKey(
                          'gather-record-undo:${widget.resourceId}',
                        ),
                        onPressed: _busy ? null : _undo,
                        child: const Text('Undo'),
                      ),
                  ],
                ),
              if (_editing)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 110,
                        child: TextField(
                          key: ValueKey(
                            'gather-record-amount:${widget.resourceId}',
                          ),
                          controller: _amount,
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: TextStyle(
                            color: chrome.ink,
                            fontSize: ResourceMapPanelMetrics.primary,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Gathered',
                            isDense: true,
                          ),
                          onSubmitted: (_) => _record(),
                        ),
                      ),
                      TextButton(
                        key: ValueKey(
                          'gather-record-save:${widget.resourceId}',
                        ),
                        onPressed: _busy ? null : _record,
                        child: Text(_busy ? 'Saving…' : 'Record'),
                      ),
                      IconButton(
                        tooltip: 'Cancel',
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _editing = false;
                                _error = null;
                              }),
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ],
                  ),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(
                    color: chrome.error,
                    fontSize: ResourceMapPanelMetrics.secondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _number(double? value) => value == null
    ? '—'
    : value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

String _message(Object error) => error is StateError
    ? error.message
    : error is ArgumentError
    ? '${error.message}'
    : 'Could not save inventory. Try again.';
