import 'package:flutter/material.dart';

import '../../app/state/planner_application_controller.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../domain/models/craft_mode.dart';
import '../../visual/visual.dart';
import 'inventory_screenshot_recognition.dart';

final class InventoryScreenshotReview {
  InventoryScreenshotReview({
    required this.locationName,
    required Map<String, double> quantities,
  }) : quantities = Map<String, double>.unmodifiable(quantities);

  final String locationName;
  final Map<String, double> quantities;
}

Future<InventoryScreenshotReview?> showInventoryScreenshotImportDialog(
  BuildContext context, {
  required ModeFeatureController controller,
  required InventoryScreenshotAnalysis analysis,
}) => showDialog<InventoryScreenshotReview>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _InventoryScreenshotImportDialog(
    controller: controller,
    analysis: analysis,
  ),
);

class _InventoryScreenshotImportDialog extends StatefulWidget {
  const _InventoryScreenshotImportDialog({
    required this.controller,
    required this.analysis,
  });

  final ModeFeatureController controller;
  final InventoryScreenshotAnalysis analysis;

  @override
  State<_InventoryScreenshotImportDialog> createState() =>
      _InventoryScreenshotImportDialogState();
}

class _InventoryScreenshotImportDialogState
    extends State<_InventoryScreenshotImportDialog> {
  late final TextEditingController _location;
  late final List<_ReviewRow> _rows;
  late final List<String> _itemNames;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final storage = widget.controller.inventoryStorage;
    final suggested = widget.analysis.draft.suggestedLocationName?.trim();
    _location = TextEditingController(
      text: suggested == null || suggested.isEmpty
          ? storage.selectedLocation.name
          : suggested,
    );
    _rows = <_ReviewRow>[
      for (final row in widget.analysis.draft.rows) _ReviewRow(row),
    ];
    final names = <String>{
      for (final mode in CraftMode.values)
        ...widget.controller.owner.catalog.forMode(mode).items.keys,
      ...widget.controller.state.value.inventory.keys,
    }.toList()..sort(_compareNames);
    _itemNames = List<String>.unmodifiable(names);
  }

  @override
  void dispose() {
    _location.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_submitting) return;
    final location = _location.text.trim();
    if (location.isEmpty) {
      setState(() => _error = 'Enter the storage or character name.');
      return;
    }
    final quantities = <String, double>{};
    for (final row in _rows.where((row) => row.include)) {
      final name = row.selectedName?.trim();
      final amount = parsePlannerNumber(row.amount.text);
      if (name == null || name.isEmpty) {
        setState(() => _error = 'Choose an item for every included slot.');
        return;
      }
      if (amount == null || amount < 0) {
        setState(() => _error = 'Check the highlighted item amounts.');
        return;
      }
      quantities[name] = amount;
    }
    if (quantities.isEmpty) {
      setState(() => _error = 'Select at least one recognized item to import.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    Navigator.of(context).pop(
      InventoryScreenshotReview(locationName: location, quantities: quantities),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final existingLocations = widget.controller.inventoryStorage.locations
        .where((location) => !location.isUnassigned)
        .map((location) => location.name)
        .toList(growable: false);
    final unresolved = _rows
        .where((row) => row.include && row.selectedName == null)
        .length;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 720),
        child: AppSurface(
          role: AppSurfaceRole.modal,
          semanticLabel: 'Review recognized inventory screenshot',
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SectionHeader(
                title: 'Review storage screenshot',
                trailing: AppButton(
                  role: AppButtonRole.optionPill,
                  semanticLabel: 'Close screenshot review',
                  tooltip: 'Close',
                  minimumSize: const Size.square(34),
                  padding: EdgeInsets.zero,
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const AppVectorGlyph('close', size: 13),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Choose the storage once, then correct only the slots that are uncertain.',
                style: spec.typography.body,
              ),
              const SizedBox(height: 14),
              Text('STORAGE OR CHARACTER', style: spec.typography.label),
              const SizedBox(height: 4),
              AppTextField(
                key: const ValueKey<String>('inventory-import-location'),
                controller: _location,
                semanticLabel: 'Storage or character name',
                hintText: 'Example: Calpheon City Storage',
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              if (existingLocations.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: <Widget>[
                    for (final name in existingLocations)
                      AppButton.label(
                        name,
                        role: AppButtonRole.optionPill,
                        minimumSize: const Size(0, 32),
                        onPressed: _submitting
                            ? null
                            : () => setState(() => _location.text = name),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Text('RECOGNIZED ITEMS', style: spec.typography.label),
                  const Spacer(),
                  Text(
                    '${_rows.length} slots${unresolved > 0 ? ' · $unresolved need a choice' : ''}',
                    style: spec.typography.meta,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Expanded(
                child: _rows.isEmpty
                    ? AppSurface(
                        role: AppSurfaceRole.row,
                        tone: AppSurfaceTone.warning,
                        child: const Text(
                          'No item amounts were found. Try a screenshot with the storage grid and amounts clearly visible.',
                        ),
                      )
                    : ListView.separated(
                        key: const ValueKey<String>('inventory-import-rows'),
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _buildRow(
                          context,
                          index: index,
                          review: _rows[index],
                        ),
                      ),
              ),
              if (_error case final error?) ...<Widget>[
                const SizedBox(height: 10),
                AppSurface(
                  role: AppSurfaceRole.row,
                  tone: AppSurfaceTone.danger,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Text(error),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  AppButton.label(
                    'Cancel',
                    role: AppButtonRole.secondary,
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  AppButton.label(
                    'Save reviewed items',
                    key: const ValueKey<String>('inventory-import-save'),
                    role: AppButtonRole.primary,
                    onPressed: _submitting ? null : _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context, {
    required int index,
    required _ReviewRow review,
  }) {
    final spec = context.visualTheme;
    final suggested = review.source.matches
        .take(3)
        .map((match) => match.name)
        .join(', ');
    return AppSurface(
      role: AppSurfaceRole.row,
      tone: review.source.needsReview
          ? AppSurfaceTone.warning
          : AppSurfaceTone.neutral,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              review.source.previewPng,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              semanticLabel: 'Screenshot item in slot ${review.source.slot}',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: 40,
                  child: AppSearchSelect<String>(
                    key: ValueKey<String>('inventory-import-item-$index'),
                    controller: review.item,
                    items: _itemNames,
                    value: review.selectedName,
                    labelFor: (value) => value,
                    hintText: review.source.needsReview
                        ? 'Which item is this?'
                        : 'Choose item',
                    semanticLabel: 'Item name for slot ${review.source.slot}',
                    enabled: review.include && !_submitting,
                    onQueryChanged: (_) {
                      review.selectedName = null;
                      if (_error != null) setState(() => _error = null);
                    },
                    onSelected: (value) => setState(() {
                      review.selectedName = value;
                      _error = null;
                    }),
                  ),
                ),
                if (suggested.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    review.source.needsReview
                        ? 'Likely: $suggested'
                        : 'Matched from the item artwork',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: spec.typography.meta,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 126,
            child: AppTextField(
              key: ValueKey<String>('inventory-import-amount-$index'),
              controller: review.amount,
              semanticLabel:
                  'Amount for ${review.selectedName ?? 'slot ${review.source.slot}'}',
              enabled: review.include && !_submitting,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 82,
            child: AppToggle(
              value: review.include,
              label: 'Use',
              switchAtEnd: true,
              onChanged: _submitting
                  ? null
                  : (value) => setState(() {
                      review.include = value;
                      _error = null;
                    }),
            ),
          ),
        ],
      ),
    );
  }
}

final class _ReviewRow {
  _ReviewRow(this.source)
    : include = source.matches.isNotEmpty,
      selectedName = source.needsReview ? null : source.matches.first.name,
      item = TextEditingController(
        text: source.needsReview || source.matches.isEmpty
            ? ''
            : source.matches.first.name,
      ),
      amount = TextEditingController(
        text: formatGroupedEditableQuantity(source.quantity.toDouble()),
      );

  final InventoryScreenshotRow source;
  final TextEditingController item;
  final TextEditingController amount;
  bool include;
  String? selectedName;

  void dispose() {
    item.dispose();
    amount.dispose();
  }
}

int _compareNames(String left, String right) {
  final folded = left.toLowerCase().compareTo(right.toLowerCase());
  return folded != 0 ? folded : left.compareTo(right);
}
