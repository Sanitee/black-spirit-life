import 'package:flutter/material.dart';

import '../lodging/shop_lodging_catalog.dart';
import 'draggable_dialog_surface.dart';
import 'resource_map_chrome_theme.dart';

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

  int get _previewTotal =>
      _pearlPurchased + _loyaltyPurchased + (_otherBonus ?? 0);

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
    return DraggableAlertDialog(
      identity: 'shop-lodging-${widget.townName}',
      estimatedSize: const Size(438, 590),
      dialogKey: const ValueKey<String>('resource-map-shop-lodging-dialog'),
      backgroundColor: chrome.paperRaised,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 14, 4),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      titleIsDragHandle: false,
      title: Row(
        children: <Widget>[
          Expanded(
            child: DraggableDialogDragHandle(
              key: const ValueKey<String>(
                'resource-map-shop-lodging-drag-handle',
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.storefront_outlined,
                    size: 22,
                    color: chrome.accent,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Shop lodging · ${widget.townName}',
                      style: TextStyle(
                        color: chrome.ink,
                        fontFamily: chrome.headingFontFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
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
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Enter lodging you already own. The planner adds these beds '
                'before recommending CP houses.',
                style: TextStyle(
                  color: chrome.text,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              if (widget.legacyUnsplitBonus > 0) ...<Widget>[
                _ShopLodgingNotice(
                  text:
                      '${widget.legacyUnsplitBonus} older bonus '
                      '${widget.legacyUnsplitBonus == 1 ? 'bed is' : 'beds are'} '
                      'saved without a Shop / Loyalty / Other split. Saving '
                      'this setup replaces that older total.',
                ),
                const SizedBox(height: 8),
              ],
              if (catalogTown == null)
                const _ShopLodgingNotice(
                  text:
                      'No verified town-specific shop coupon is cataloged '
                      'here. You can still record event or other bonus beds.',
                )
              else ...<Widget>[
                _PurchasedCounterRow(
                  key: const ValueKey<String>(
                    'resource-map-shop-lodging-pearl',
                  ),
                  icon: Icons.diamond_outlined,
                  label: 'Pearl lodging',
                  value: _pearlPurchased,
                  maximum: pearlLimit,
                  onChanged: (value) {
                    setState(() => _pearlPurchased = value);
                  },
                ),
                if (loyaltyLimit != null) ...<Widget>[
                  Divider(height: 1, color: chrome.divider),
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
                      'Loyalty lodging',
                      style: TextStyle(
                        color: chrome.ink,
                        fontFamily: chrome.headingFontFamily,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'One verified town coupon',
                      style: TextStyle(color: chrome.muted, fontSize: 10.5),
                    ),
                    value: _loyaltyPurchased > 0,
                    onChanged: (value) {
                      setState(() {
                        _loyaltyPurchased = value ? loyaltyLimit : 0;
                      });
                    },
                  ),
                ],
              ],
              if (catalogTown != null)
                Divider(height: 1, color: chrome.divider),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.redeem_outlined,
                      size: 20,
                      color: chrome.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Other / event',
                            style: TextStyle(
                              color: chrome.ink,
                              fontFamily: chrome.headingFontFamily,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Choice boxes, events, or older bonus beds',
                            style: TextStyle(
                              color: chrome.muted,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 74,
                      child: TextField(
                        key: const ValueKey<String>(
                          'resource-map-shop-lodging-other',
                        ),
                        controller: _otherController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        textAlign: TextAlign.center,
                        onChanged: (_) {
                          setState(() => _otherError = null);
                        },
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
                  style: TextStyle(color: chrome.error, fontSize: 10.5),
                ),
              if (catalogTown != null) ...<Widget>[
                const SizedBox(height: 8),
                _ShopLodgingNotice(
                  text:
                      'F3 Pearl Shop → search “[Town] Worker’s Lodging”. '
                      'Enter purchased, not remaining: 2 remaining out of '
                      '$pearlLimit means ${pearlLimit >= 2 ? pearlLimit - 2 : 0} purchased.',
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Icon(Icons.bed_rounded, size: 17, color: chrome.positive),
                  const SizedBox(width: 6),
                  Text(
                    'Adds $_previewTotal bonus '
                    '${_previewTotal == 1 ? 'bed' : 'beds'}',
                    key: const ValueKey<String>(
                      'resource-map-shop-lodging-total',
                    ),
                    style: TextStyle(
                      color: chrome.positive,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: chrome.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(
                    color: chrome.ink,
                    fontFamily: chrome.headingFontFamily,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$value of $maximum purchased',
                  style: TextStyle(color: chrome.muted, fontSize: 10.5),
                ),
              ],
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
                fontSize: 14,
                fontWeight: FontWeight.w900,
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

class _ShopLodgingNotice extends StatelessWidget {
  const _ShopLodgingNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: chrome.muted,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: chrome.muted, fontSize: 10.5, height: 1.35),
          ),
        ),
      ],
    );
  }
}
