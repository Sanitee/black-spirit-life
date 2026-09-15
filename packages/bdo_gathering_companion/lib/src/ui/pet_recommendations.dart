import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/pets.dart';
import 'hover_pinned_details.dart';
import 'theme.dart';

/// Applicable pet choices. Pet selection stays separate from buff arithmetic.
class PetRecommendations extends StatelessWidget {
  const PetRecommendations({
    super.key,
    required this.methodId,
    this.spotId,
    this.framed = true,
    this.pets,
    this.selectedIds = const {},
    this.onToggle,
    this.onClear,
  });

  final String methodId;
  final String? spotId;

  /// Framed group for the buff picker; an unframed strip for the field guide.
  final bool framed;

  /// Allows a containing app to provide its catalog after future integration.
  final List<PetRecommendation>? pets;

  /// IDs marked as used in the current session. No tier is implied.
  final Set<String> selectedIds;

  /// Enables click-to-toggle selection. Omit for an informational-only strip.
  final ValueChanged<PetRecommendation>? onToggle;

  /// Clears the current applicable selections. Hidden, inapplicable IDs do not
  /// make this action appear; callers should reconcile them when context moves.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => pets != null
      ? _group(context, pets!)
      : FutureBuilder<List<PetRecommendation>>(
          future: PetCatalog.load(),
          builder: (context, snapshot) =>
              _group(context, snapshot.data ?? const []),
        );

  Widget _group(BuildContext context, List<PetRecommendation> catalog) {
    final matching = catalog
        .where((pet) => pet.appliesTo(methodId: methodId, spotId: spotId))
        .toList();
    if (matching.isEmpty) return const SizedBox.shrink();
    final selectedMatching = matching.any(
      (pet) => selectedIds.contains(pet.id),
    );
    final heading = _PetHeading(
      showClear: selectedMatching && onClear != null,
      reserveClearSpace: onToggle != null || onClear != null,
      onClear: onClear,
    );
    final icons = Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final pet in matching)
          _PetIcon(
            pet: pet,
            isSelected: selectedIds.contains(pet.id),
            onToggle: onToggle == null ? null : () => onToggle!(pet),
          ),
      ],
    );
    if (framed) {
      return Container(
        key: const ValueKey('pet-recommendations'),
        width: double.infinity,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          gradient: context.glass.groupGradient,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.glass.insetLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [heading, const SizedBox(height: 2), icons],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidth =
            math.max(58.0, MediaQuery.textScalerOf(context).scale(60)) +
            (onToggle != null || onClear != null ? 48 : 0);
        final naturalWidth = labelWidth + 8 + matching.length * 48 - 4;
        return SizedBox(
          key: const ValueKey('pet-recommendations'),
          width: math.min(naturalWidth, constraints.maxWidth),
          child: constraints.maxWidth >= naturalWidth
              ? Row(
                  children: [
                    SizedBox(width: labelWidth, child: heading),
                    const SizedBox(width: 8),
                    Expanded(child: icons),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heading, const SizedBox(height: 4), icons],
                ),
        );
      },
    );
  }
}

class _PetHeading extends StatelessWidget {
  const _PetHeading({
    required this.showClear,
    required this.reserveClearSpace,
    required this.onClear,
  });

  final bool showClear;
  final bool reserveClearSpace;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: math.max(
      MediaQuery.textScalerOf(context).scale(18),
      reserveClearSpace ? 48 : 18,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Flexible(
          child: Text(
            'Pets',
            style: TextStyle(
              fontSize: 14,
              color: muted,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
        if (showClear) ...[
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey('clear-pets'),
            tooltip: 'Clear pets',
            onPressed: onClear,
            icon: const Icon(Icons.clear, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    ),
  );
}

class _PetIcon extends StatelessWidget {
  const _PetIcon({
    required this.pet,
    required this.isSelected,
    required this.onToggle,
  });

  final PetRecommendation pet;
  final bool isSelected;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    void details() => showPetInfo(context, pet);
    final selectionEnabled = onToggle != null;
    final primaryAction = onToggle ?? details;
    return Semantics(
      key: ValueKey('pet-icon-${pet.id}'),
      label: '${pet.name}: ${pet.summary}',
      hint: selectionEnabled
          ? 'Toggle pet used. Long press or Shift F10 for details.'
          : 'View pet details.',
      button: true,
      selected: selectionEnabled || isSelected ? isSelected : null,
      onTap: primaryAction,
      onLongPress: details,
      excludeSemantics: true,
      child: HoverPinnedDetails(
        hoverKey: ValueKey('pet-hover-card-${pet.id}'),
        onPin: details,
        cardBuilder: (context) => _PetHoverCard(pet),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.f10, shift: true): details,
          },
          child: GlassControl(
            selected: isSelected,
            radius: 6,
            child: InkWell(
              onTap: primaryAction,
              onLongPress: details,
              excludeFromSemantics: true,
              borderRadius: BorderRadius.circular(6),
              child: SizedBox.square(
                dimension: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    GameIcon(pet.icon, size: 40),
                    if (isSelected)
                      Positioned(
                        right: 1,
                        bottom: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: context.glass.popup,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_circle,
                            size: 16,
                            color: accent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showPetInfo(BuildContext context, PetRecommendation pet) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: ValueKey('pet-details-${pet.id}'),
        title: _PetDetailsTitle(pet, iconSize: 48),
        content: SizedBox(
          width: 390,
          child: SingleChildScrollView(child: _PetDetailsSections(pet)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );

class _PetHoverCard extends StatelessWidget {
  const _PetHoverCard(this.pet);

  final PetRecommendation pet;

  @override
  Widget build(BuildContext context) => Material(
    color: context.glass.popup,
    elevation: 12,
    shadowColor: Colors.black.withValues(
      alpha: context.glass.shadowOpacity + .08,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: context.glass.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400, maxHeight: 620),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PetDetailsTitle(pet),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(child: _PetDetailsSections(pet)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PetDetailsTitle extends StatelessWidget {
  const _PetDetailsTitle(this.pet, {this.iconSize = 36});

  final PetRecommendation pet;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      GameIcon(pet.icon, size: iconSize),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          pet.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

class _PetDetailsSections extends StatelessWidget {
  const _PetDetailsSections(this.pet);

  final PetRecommendation pet;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Why it helps',
        style: TextStyle(
          color: accent,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 7),
      Text(pet.summary, style: const TextStyle(fontSize: 14, height: 1.28)),
      if (pet.details.isNotEmpty) ...[
        const Divider(height: 16),
        const Text(
          'Details',
          style: TextStyle(
            color: accent,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        for (final detail in pet.details)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              detail,
              style: const TextStyle(fontSize: 14, height: 1.28),
            ),
          ),
      ],
    ],
  );
}
