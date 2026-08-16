import '../../domain/migration/avalonia_v1_migration.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/state/planner_state.dart';
import '../icons/custom_icon_store.dart';
import 'portable_v4_codec.dart';

final class PortableImportPreview {
  PortableImportPreview({
    required this.result,
    required Iterable<PendingCustomIcon> pendingIcons,
  }) : pendingIcons = List<PendingCustomIcon>.unmodifiable(pendingIcons);

  final PortableImportResult result;
  final List<PendingCustomIcon> pendingIcons;
}

/// Keeps custom-icon file writes outside the pure portable codec. Preview is
/// read-only; normalized app-owned files are created only after confirmation.
final class PortableCustomIconBridge {
  const PortableCustomIconBridge({
    required this.iconStore,
    this.codec = const PortableV4Codec(),
  });

  final CustomIconStore iconStore;
  final PortableV4Codec codec;

  String export(CustomIconReference reference) =>
      iconStore.exportDataUri(reference);

  PortableImportPreview preview(
    PlannerState current,
    String source, {
    required bool confirmLegacyFullReplacement,
  }) {
    final pending = <PendingCustomIcon>[];
    final result = codec.import(
      current,
      source,
      confirmLegacyFullReplacement: confirmLegacyFullReplacement,
      iconImporter: (icon) {
        pending.add(icon);
        return _previewReference(icon);
      },
    );
    return PortableImportPreview(result: result, pendingIcons: pending);
  }

  Future<PortableImportResult> materializeImport(
    PlannerState current,
    String source, {
    required bool confirmLegacyFullReplacement,
  }) async {
    final probe = preview(
      current,
      source,
      confirmLegacyFullReplacement: confirmLegacyFullReplacement,
    );
    if (probe.pendingIcons.isEmpty) return probe.result;

    final imported = <String, CustomIconReference>{};
    try {
      for (final pending in probe.pendingIcons) {
        imported[_key(pending)] = await iconStore.importDataUri(
          pending.dataUri,
          sourceName: pending.itemName,
        );
      }
    } on Object {
      await _discardNewReferences(current, imported.values);
      rethrow;
    }
    try {
      return codec.import(
        current,
        source,
        confirmLegacyFullReplacement: confirmLegacyFullReplacement,
        iconImporter: (icon) => imported[_key(icon)]!,
      );
    } on Object {
      await _discardNewReferences(current, imported.values);
      rethrow;
    }
  }

  /// Removes app-owned icon files introduced by an import that could not be
  /// committed. Files already referenced by [current] are never removed.
  Future<void> discardUncommittedImport(
    PlannerState current,
    PlannerState imported,
  ) => _discardNewReferences(current, _references(imported));

  Future<void> _discardNewReferences(
    PlannerState current,
    Iterable<CustomIconReference> candidates,
  ) async {
    final retained = _references(
      current,
    ).map((reference) => reference.relativePath.toLowerCase()).toSet();
    final discarded = <String>{};
    for (final reference in candidates) {
      final path = reference.relativePath.toLowerCase();
      if (retained.contains(path) || !discarded.add(path)) continue;
      await iconStore.remove(reference);
    }
  }
}

CustomIconReference _previewReference(PendingCustomIcon icon) {
  final seed = icon.jsonPath.codeUnits.fold<int>(
    0,
    (sum, value) => sum + value,
  );
  final hash = seed.toRadixString(16).padLeft(64, '0').substring(0, 64);
  return CustomIconReference(
    relativePath: 'icons/$hash.png',
    sha256: hash.toUpperCase(),
    mediaType: 'image/png',
    byteCount: 1,
    width: 1,
    height: 1,
  );
}

String _key(PendingCustomIcon icon) =>
    '${icon.mode.key}\u0000${icon.itemName}\u0000${icon.jsonPath}';

Iterable<CustomIconReference> _references(PlannerState state) sync* {
  for (final mode in CraftMode.values) {
    yield* state.forMode(mode).customIcons.values;
  }
}
