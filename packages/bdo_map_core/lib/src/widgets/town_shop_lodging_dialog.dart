import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lodging/shop_lodging_catalog.dart';
import '../network/worker_capacity_assessment.dart';
import 'draggable_dialog_surface.dart';
import 'resource_map_chrome_theme.dart';
import 'resource_map_panel_metrics.dart';
import 'shop_lodging_setup_dialog.dart';

typedef TownExistingWorkerEditor =
    Future<Map<String, BdoTownWorkerCapacity>?> Function(
      Map<String, BdoTownWorkerCapacity> currentDraft,
    );

/// Edits shop lodging as one transaction, without changing worker assignments.
class TownShopLodgingDialog extends StatefulWidget {
  const TownShopLodgingDialog({
    required this.initialValues,
    required this.knownSlotCountsByTownNodeId,
    this.onOpenExistingWorkers,
    super.key,
  });

  final Map<String, BdoTownWorkerCapacity> initialValues;

  /// Free town slots plus active owned housing, excluding bonus lodging.
  final Map<String, int> knownSlotCountsByTownNodeId;

  /// Returns draft values only; the enclosing Save remains the commit point.
  final TownExistingWorkerEditor? onOpenExistingWorkers;

  @override
  State<TownShopLodgingDialog> createState() => _TownShopLodgingDialogState();
}

class _TownShopLodgingDialogState extends State<TownShopLodgingDialog> {
  late Map<String, BdoTownWorkerCapacity> _draft;
  late final List<WorkerLodgingShopTown> _towns;
  final _scrollController = ScrollController();
  bool _editingWorkers = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _draft = Map.of(widget.initialValues);
    _towns = List.of(WorkerLodgingShopCatalog.towns)
      ..sort((a, b) => a.townName.compareTo(b.townName));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int _knownSlots(String townId) =>
      math.max<int>(0, widget.knownSlotCountsByTownNodeId[townId] ?? 0);

  bool _needsReview(BdoTownWorkerCapacity? value) =>
      value != null &&
      (!value.usesKnownTownLodging ||
          (!value.hasBonusLodgingBreakdown &&
              (value.bonusLodgingSlotCount ?? 0) != 0));

  void _setSources(
    String townId, {
    required int? pearl,
    required int? loyalty,
    required int? other,
  }) {
    final previous = _draft[townId];
    final hired =
        previous?.hiredWorkerCount ?? previous?.availableWorkerCount ?? 0;
    final bonus =
        math.max<int>(0, pearl ?? 0) +
        math.max<int>(0, loyalty ?? 0) +
        math.max<int>(0, other ?? 0);
    setState(() {
      _draft[townId] = BdoTownWorkerCapacity(
        availableWorkerCount: hired,
        freeLodgingSlotCount: math.max<int>(
          0,
          _knownSlots(townId) + bonus - hired,
        ),
        hiredWorkerCount: previous == null ? 0 : previous.hiredWorkerCount,
        bonusLodgingSlotCount: bonus,
        pearlLodgingPurchasedCount: pearl,
        loyaltyLodgingPurchasedCount: loyalty,
        otherBonusLodgingSlotCount: other,
      );
    });
  }

  Future<void> _reviewTown(WorkerLodgingShopTown town) async {
    final previous = _draft[town.townNodeId];
    final initial = WorkerLodgingShopSetup(
      pearlPurchased: previous?.pearlLodgingPurchasedCount ?? 0,
      loyaltyPurchased: previous?.loyaltyLodgingPurchasedCount ?? 0,
      otherBonus: previous?.otherBonusLodgingSlotCount ?? 0,
    );
    final legacyBonus = previous == null || previous.hasBonusLodgingBreakdown
        ? 0
        : previous.usesKnownTownLodging
        ? previous.effectiveBonusLodgingSlotCount
        : math.max<int>(
            0,
            previous.availableWorkerCount +
                previous.freeLodgingSlotCount -
                _knownSlots(town.townNodeId),
          );
    WorkerLodgingShopSetup? edited;
    final chrome = context.mapChrome.withUiOpacity(1);
    await showDialog<void>(
      context: context,
      builder: (context) => ResourceMapChromeTheme(
        data: chrome,
        child: WorkerLodgingShopSetupDialog(
          townName: town.townName,
          catalogTown: town,
          initialValue: initial,
          legacyUnsplitBonus: legacyBonus,
          onSave: (value) => edited = value,
        ),
      ),
    );
    if (!mounted || edited == null) return;
    final value = edited!;
    final displayedPearl = initial.pearlPurchased.clamp(
      0,
      town.pearlCouponLimit,
    );
    final displayedLoyalty = initial.loyaltyPurchased.clamp(
      0,
      town.loyaltyCouponLimit ?? 0,
    );
    final displayedOther = math.max<int>(0, initial.otherBonus);
    if (value.pearlPurchased == displayedPearl &&
        value.loyaltyPurchased == displayedLoyalty &&
        value.otherBonus == displayedOther) {
      return;
    }
    // The older editor clamps its controls. Do not let an unrelated edit
    // silently erase a saved value outside the current catalog's limits.
    final hasBreakdown = previous?.hasBonusLodgingBreakdown ?? false;
    int? retainUnchanged(int result, int displayed, int? saved) =>
        hasBreakdown && result == displayed ? saved : result;
    _setSources(
      town.townNodeId,
      pearl: retainUnchanged(
        value.pearlPurchased,
        displayedPearl,
        previous?.pearlLodgingPurchasedCount,
      ),
      loyalty: retainUnchanged(
        value.loyaltyPurchased,
        displayedLoyalty,
        previous?.loyaltyLodgingPurchasedCount,
      ),
      other: retainUnchanged(
        value.otherBonus,
        displayedOther,
        previous?.otherBonusLodgingSlotCount,
      ),
    );
  }

  Future<void> _openExistingWorkers() async {
    final open = widget.onOpenExistingWorkers;
    if (open == null || _editingWorkers) return;
    setState(() => _editingWorkers = true);
    try {
      final updated = await open(Map.unmodifiable(_draft));
      if (!mounted || updated == null) return;
      setState(() => _draft = Map.of(updated));
    } finally {
      if (mounted) setState(() => _editingWorkers = false);
    }
  }

  void _save() {
    if (_finished || _editingWorkers) return;
    _finished = true;
    Navigator.of(context).pop(Map<String, BdoTownWorkerCapacity>.of(_draft));
  }

  @override
  Widget build(BuildContext context) {
    return ResourceMapChromeTheme(
      data: context.mapChrome.withUiOpacity(1),
      child: Builder(builder: _buildDialog),
    );
  }

  Widget _buildDialog(BuildContext context) {
    final chrome = context.mapChrome;
    final media = MediaQuery.of(context);
    final scale = media.textScaler.scale(14) / 14;
    final width = math.max<double>(
      240.0,
      math.min<double>(
        500.0 * math.min<double>(scale, 1.5),
        media.size.width - 80.0,
      ),
    );
    final listHeight = math.max<double>(
      100.0,
      math.min<double>(
        360.0,
        media.size.height - 230.0 * math.max<double>(1.0, scale),
      ),
    );
    final pearlWidth = 104.0 * math.min(math.max(1.0, scale), 1.35);
    final loyaltyWidth = 80.0 * math.min(math.max(1.0, scale), 1.3);
    return DraggableAlertDialog(
      identity: 'town-shop-lodging',
      dialogKey: const ValueKey('resource-map-town-lodging-dialog'),
      estimatedSize: Size(
        width + 40,
        listHeight + 180.0 * math.max<double>(1.0, scale),
      ),
      backgroundColor: chrome.paperRaised,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      titlePadding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      titleIsDragHandle: false,
      title: Row(
        children: [
          Expanded(
            child: DraggableDialogDragHandle(
              key: const ValueKey('resource-map-town-lodging-drag-handle'),
              child: Text(
                'Extra lodging',
                style: chrome.headingStyle(
                  fontSize: ResourceMapPanelMetrics.heading,
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('resource-map-town-lodging-close'),
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, size: 19, color: chrome.ink),
          ),
        ],
      ),
      content: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Purchased slots',
              style: TextStyle(
                color: chrome.muted,
                fontSize: ResourceMapPanelMetrics.secondary,
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: chrome.muted,
                  fontSize: ResourceMapPanelMetrics.secondary,
                ),
                child: Row(
                  children: [
                    const Expanded(child: Text('Town')),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: pearlWidth,
                      child: const Text('Pearl', textAlign: TextAlign.center),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: loyaltyWidth,
                      child: const Text('Loyalty', textAlign: TextAlign.center),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: listHeight,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: ListView.builder(
                  key: const ValueKey('resource-map-town-lodging-list'),
                  controller: _scrollController,
                  itemCount: _towns.length,
                  itemBuilder: (context, index) => _townRow(
                    context,
                    _towns[index],
                    pearlWidth: pearlWidth,
                    loyaltyWidth: loyaltyWidth,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: width + 8,
          child: Row(
            children: [
              if (widget.onOpenExistingWorkers != null)
                Flexible(
                  child: TextButton(
                    key: const ValueKey('resource-map-town-lodging-workers'),
                    onPressed: _editingWorkers ? null : _openExistingWorkers,
                    child: const Text('Existing workers'),
                  ),
                ),
              const Spacer(),
              TextButton(
                key: const ValueKey('resource-map-town-lodging-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('resource-map-town-lodging-save'),
                onPressed: _editingWorkers ? null : _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _townRow(
    BuildContext context,
    WorkerLodgingShopTown town, {
    required double pearlWidth,
    required double loyaltyWidth,
  }) {
    final chrome = context.mapChrome;
    final value = _draft[town.townNodeId];
    final pearl = value?.pearlLodgingPurchasedCount ?? 0;
    final loyalty = value?.loyaltyLodgingPurchasedCount ?? 0;
    final other = value?.otherBonusLodgingSlotCount ?? 0;
    final review = _needsReview(value);
    final hasExtraDetails =
        other != 0 ||
        pearl < 0 ||
        pearl > town.pearlCouponLimit ||
        loyalty < 0 ||
        loyalty > (town.loyaltyCouponLimit ?? 0);
    final owned = (value?.effectiveBonusLodgingSlotCount ?? 0) > 0;
    final townName = Text(
      town.townName,
      style: TextStyle(
        color: chrome.ink,
        fontSize: ResourceMapPanelMetrics.primary,
        fontWeight: FontWeight.w600,
      ),
    );
    return Container(
      key: ValueKey('resource-map-town-lodging-row-${town.townNodeId}'),
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: owned ? chrome.primary.withValues(alpha: .07) : null,
        border: Border(top: BorderSide(color: chrome.softOutline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                townName,
                if (hasExtraDetails && !review)
                  InkWell(
                    key: ValueKey(
                      'resource-map-town-lodging-details-${town.townNodeId}',
                    ),
                    onTap: () => _reviewTown(town),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        other > 0
                            ? '+$other other · Edit'
                            : 'Review saved lodging',
                        style: TextStyle(
                          color: chrome.primary,
                          fontSize: ResourceMapPanelMetrics.secondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (review)
            SizedBox(
              width: pearlWidth + 12 + loyaltyWidth,
              child: TextButton(
                key: ValueKey(
                  'resource-map-town-lodging-review-${town.townNodeId}',
                ),
                onPressed: () => _reviewTown(town),
                child: const Text('Review saved lodging'),
              ),
            )
          else ...[
            SizedBox(
              width: pearlWidth,
              child: _PearlCounter(
                town: town,
                value: pearl,
                onChanged: (next) => _setSources(
                  town.townNodeId,
                  pearl: next,
                  loyalty: value?.loyaltyLodgingPurchasedCount,
                  other: value?.otherBonusLodgingSlotCount,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: loyaltyWidth,
              child: town.hasVerifiedLoyaltyCoupon
                  ? Semantics(
                      label: '${town.townName} Loyalty slot purchased',
                      child: Checkbox(
                        key: ValueKey(
                          'resource-map-town-lodging-loyalty-${town.townNodeId}',
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        value: loyalty > 0,
                        activeColor: chrome.primary,
                        checkColor: chrome.onPrimary,
                        onChanged: (checked) => _setSources(
                          town.townNodeId,
                          pearl: value?.pearlLodgingPurchasedCount,
                          loyalty: checked == true
                              ? town.loyaltyCouponLimit
                              : 0,
                          other: value?.otherBonusLodgingSlotCount,
                        ),
                      ),
                    )
                  : Tooltip(
                      message:
                          'A town-specific Loyalty coupon is not confirmed in the bundled catalog.',
                      child: Text(
                        loyalty != 0 ? '$loyalty' : '—',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: chrome.muted,
                          fontSize: ResourceMapPanelMetrics.primary,
                        ),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PearlCounter extends StatelessWidget {
  const _PearlCounter({
    required this.town,
    required this.value,
    required this.onChanged,
  });

  final WorkerLodgingShopTown town;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: chrome.controlInset,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: chrome.softOutline),
      ),
      child: Row(
        children: [
          IconButton(
            key: ValueKey(
              'resource-map-town-lodging-pearl-minus-${town.townNodeId}',
            ),
            tooltip: '${town.townName}: one fewer Pearl slot',
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
            constraints: const BoxConstraints.tightFor(width: 30, height: 32),
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.remove_rounded,
              size: 18,
              color: value > 0 ? chrome.primary : chrome.muted,
            ),
          ),
          Expanded(
            child: Text(
              '$value',
              key: ValueKey(
                'resource-map-town-lodging-pearl-count-${town.townNodeId}',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: chrome.ink,
                fontSize: ResourceMapPanelMetrics.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            key: ValueKey(
              'resource-map-town-lodging-pearl-plus-${town.townNodeId}',
            ),
            tooltip: '${town.townName}: one more Pearl slot',
            onPressed: value < town.pearlCouponLimit
                ? () => onChanged(value + 1)
                : null,
            constraints: const BoxConstraints.tightFor(width: 30, height: 32),
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.add_rounded,
              size: 18,
              color: value < town.pearlCouponLimit
                  ? chrome.primary
                  : chrome.muted,
            ),
          ),
        ],
      ),
    );
  }
}
