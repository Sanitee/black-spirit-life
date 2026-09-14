import 'package:flutter/material.dart';

import '../lodging/shop_lodging_catalog.dart';
import 'draggable_dialog_surface.dart';
import 'resource_map_chrome_theme.dart';
import 'resource_map_panel_metrics.dart';

/// Player-owned shop lodging for one town.
///
/// This is deliberately separate from the product catalog: catalog limits are
/// shared facts, while these counts belong to the player's saved setup.
final class WorkerLodgingShopSetup {
  const WorkerLodgingShopSetup({
    this.pearlPurchased = 0,
    this.loyaltyPurchased = 0,
    this.otherBonus = 0,
  });

  final int pearlPurchased;
  final int loyaltyPurchased;
  final int otherBonus;

  int get totalBonus => pearlPurchased + loyaltyPurchased + otherBonus;
}

/// Compact editor for one town's purchased and event worker lodging.
class WorkerLodgingShopSetupDialog extends StatefulWidget {
  const WorkerLodgingShopSetupDialog({
    required this.townName,
    required this.initialValue,
    required this.onSave,
    this.catalogTown,
    this.legacyUnsplitBonus = 0,
    super.key,
  });

  final String townName;
  final WorkerLodgingShopTown? catalogTown;
  final WorkerLodgingShopSetup initialValue;
  final int legacyUnsplitBonus;
  final ValueChanged<WorkerLodgingShopSetup> onSave;

  @override
  State<WorkerLodgingShopSetupDialog> createState() =>
      _WorkerLodgingShopSetupDialogState();
}

class _WorkerLodgingShopSetupDialogState
    extends State<WorkerLodgingShopSetupDialog> {
  late int _pearlPurchased;
  late int _loyaltyPurchased;
  late final TextEditingController _otherController;
  String? _otherError;

  @override
  void initState() {
    super.initState();
    final pearlLimit = widget.catalogTown?.pearlCouponLimit ?? 0;
    final loyaltyLimit = widget.catalogTown?.loyaltyCouponLimit ?? 0;
    _pearlPurchased = widget.initialValue.pearlPurchased.clamp(0, pearlLimit);
    _loyaltyPurchased = widget.initialValue.loyaltyPurchased.clamp(
      0,
      loyaltyLimit,
    );
    _otherController = TextEditingController(
      text:
          '${widget.initialValue.otherBonus < 0 ? 0 : widget.initialValue.otherBonus}',
    );
  }

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  int? get _otherBonus {
    final parsed = int.tryParse(_otherController.text.trim());
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  void _save() {
    final other = _otherBonus;
    if (other == null) {
      setState(() {
        _otherError = 'Enter a whole number of 0 or more.';
      });
      return;
    }
    widget.onSave(
      WorkerLodgingShopSetup(
        pearlPurchased: _pearlPurchased,
        loyaltyPurchased: _loyaltyPurchased,
        otherBonus: other,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final catalogTown = widget.catalogTown;
    final pearlLimit = catalogTown?.pearlCouponLimit ?? 0;
    final loyaltyLimit = catalogTown?.loyaltyCouponLimit;
    final help = <String>[
      'Enter purchased coupons, not the remaining shop allowance.',
      if (catalogTown == null)
        'No verified town coupon is cataloged. Other bonus beds can still be recorded.',
      if (widget.legacyUnsplitBonus > 0)
        'Saving replaces the older unsplit total of ${widget.legacyUnsplitBonus} bonus beds.',
    ].join('\n');
    return DraggableAlertDialog(
      identity: 'shop-lodging-${widget.townName}',
      estimatedSize: const Size(380, 310),
      dialogKey: const ValueKey<String>('resource-map-shop-lodging-dialog'),
      backgroundColor: chrome.paperRaised,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      titleIsDragHandle: false,
      title: Row(
        children: [
          Expanded(
            child: DraggableDialogDragHandle(
              key: const ValueKey<String>(
                'resource-map-shop-lodging-drag-handle',
              ),
              child: Text(
                'Shop lodging · ${widget.townName}',
                style: TextStyle(
                  color: chrome.ink,
                  fontFamily: chrome.headingFontFamily,
                  fontSize: ResourceMapPanelMetrics.heading,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Tooltip(
            message: help,
            child: Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: chrome.muted,
            ),
          ),
          IconButton(
            key: const ValueKey<String>('resource-map-shop-lodging-close'),
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 19),
          ),
        ],
      ),
      content: SizedBox(
        width: 330,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (catalogTown != null) ...[
                _PurchasedCounterRow(
                  key: const ValueKey<String>(
                    'resource-map-shop-lodging-pearl',
                  ),
                  icon: Icons.diamond_outlined,
                  label: 'Pearl purchased',
                  value: _pearlPurchased,
                  maximum: pearlLimit,
                  onChanged: (value) => setState(() => _pearlPurchased = value),
                ),
                if (loyaltyLimit != null)
                  SwitchListTile(
                    key: const ValueKey<String>(
                      'resource-map-shop-lodging-loyalty',
                    ),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    secondary: Icon(
                      Icons.loyalty_outlined,
                      size: 20,
                      color: chrome.primary,
                    ),
                    title: Text(
                      'Loyalty purchased',
                      style: TextStyle(
                        color: chrome.ink,
                        fontSize: ResourceMapPanelMetrics.primary,
                      ),
                    ),
                    value: _loyaltyPurchased > 0,
                    onChanged: (value) => setState(
                      () => _loyaltyPurchased = value ? loyaltyLimit : 0,
                    ),
                  ),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.redeem_outlined,
                      size: 20,
                      color: chrome.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Other / event',
                        style: TextStyle(
                          color: chrome.ink,
                          fontSize: ResourceMapPanelMetrics.primary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: TextField(
                        key: const ValueKey<String>(
                          'resource-map-shop-lodging-other',
                        ),
                        controller: _otherController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: ResourceMapPanelMetrics.primary,
                        ),
                        onChanged: (_) => setState(() => _otherError = null),
                        onSubmitted: (_) => _save(),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '0',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_otherError case final error?)
                Text(
                  error,
                  key: const ValueKey<String>(
                    'resource-map-shop-lodging-error',
                  ),
                  style: TextStyle(
                    color: chrome.error,
                    fontSize: ResourceMapPanelMetrics.secondary,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('resource-map-shop-lodging-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _PurchasedCounterRow extends StatelessWidget {
  const _PurchasedCounterRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.maximum,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String label;
  final int value;
  final int maximum;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: chrome.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Tooltip(
              message: 'Up to $maximum purchased',
              child: Text(
                label,
                style: TextStyle(
                  color: chrome.ink,
                  fontSize: ResourceMapPanelMetrics.primary,
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey<String>(
              'resource-map-shop-lodging-pearl-minus',
            ),
            tooltip: 'One fewer purchased',
            visualDensity: VisualDensity.compact,
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          SizedBox(
            width: 24,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: chrome.ink,
                fontSize: ResourceMapPanelMetrics.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey<String>('resource-map-shop-lodging-pearl-plus'),
            tooltip: 'One more purchased',
            visualDensity: VisualDensity.compact,
            onPressed: value < maximum ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}
