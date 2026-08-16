import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/state/planner_application_controller.dart';
import '../../data/catalog/catalog_repository.dart';
import '../../data/icons/custom_icon_store.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/state/planner_state.dart';
import '../../visual/visual.dart';
import 'custom_icon_store_scope.dart';

abstract final class ModeItemIconKeys {
  static Key image(String name) =>
      ValueKey<String>('mode-item-icon:image:${name.toLowerCase()}');

  static Key loading(String name) =>
      ValueKey<String>('mode-item-icon:loading:${name.toLowerCase()}');

  static Key failure(String name) =>
      ValueKey<String>('mode-item-icon:failure:${name.toLowerCase()}');
}

typedef CustomIconBytesLoader =
    Future<Uint8List> Function(
      CustomIconStore store,
      CustomIconReference reference,
    );

Future<Uint8List> _loadCustomIconBytes(
  CustomIconStore store,
  CustomIconReference reference,
) => store.readValidatedBytesAsync(reference);

/// Shared mode-aware item artwork used by planner, inventory, and Recipe Book.
/// Resolution is content-only: retained themes still own the frame materials.
class ModeItemIcon extends StatefulWidget {
  const ModeItemIcon({
    required this.controller,
    required this.name,
    required this.size,
    this.catalogRepository,
    this.searchAcrossModes = false,
    this.fallbackIcon,
    this.showFrame = true,
    this.customIconLoader = _loadCustomIconBytes,
    super.key,
  });

  final ModeFeatureController controller;
  final String name;
  final double size;
  final CatalogRepository? catalogRepository;
  final bool searchAcrossModes;
  final IconData? fallbackIcon;
  final bool showFrame;
  final CustomIconBytesLoader customIconLoader;

  @override
  State<ModeItemIcon> createState() => _ModeItemIconState();
}

class _ModeItemIconState extends State<ModeItemIcon> {
  CustomIconStore? _iconStore;
  _IconRequest? _request;
  late _IconResolution _resolution;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _resolution = _IconResolutionLoading('${widget.name} icon loading.');
    widget.controller.state.addListener(_stateChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _iconStore = CustomIconStoreScope.maybeOf(context);
    _synchronize(rebuild: false);
  }

  @override
  void didUpdateWidget(ModeItemIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.state.removeListener(_stateChanged);
      widget.controller.state.addListener(_stateChanged);
    }
    _synchronize(rebuild: false, revalidateCustom: true);
  }

  @override
  void dispose() {
    _generation += 1;
    widget.controller.state.removeListener(_stateChanged);
    super.dispose();
  }

  void _stateChanged() => _synchronize(rebuild: true);

  void _synchronize({required bool rebuild, bool revalidateCustom = false}) {
    final catalog =
        widget.catalogRepository ??
        _CatalogRepositories.instance.resolve(widget.controller.owner.catalog);
    final next = _resolveRequest(
      controller: widget.controller,
      catalogRepository: catalog,
      iconStore: _iconStore,
      customIconLoader: widget.customIconLoader,
      name: widget.name,
      searchAcrossModes: widget.searchAcrossModes,
    );
    final sameRequest = _request?.matches(next) ?? false;
    if (sameRequest && !(revalidateCustom && next is _CustomIconRequest)) {
      return;
    }
    _request = next;
    final generation = ++_generation;
    switch (next) {
      case _ImmediateIconRequest(:final resolution):
        _resolution = resolution;
        if (rebuild && mounted) setState(() {});
      case _CustomIconRequest():
        if (!sameRequest) {
          _resolution = _IconResolutionLoading(
            '${widget.name} custom icon loading.',
          );
          if (rebuild && mounted) setState(() {});
        }
        _loadCustom(next, generation);
    }
  }

  Future<void> _loadCustom(_CustomIconRequest request, int generation) async {
    late _IconResolution result;
    try {
      final bytes = await request.loader(request.store, request.reference);
      result = _ResolvedIcon(
        bytes: bytes,
        semanticLabel: '${widget.name} custom icon',
      );
    } on CustomIconValidationException catch (error) {
      result = _IconResolutionFailure(
        'The saved custom icon for ${widget.name} is invalid or missing. '
        '${error.message}',
      );
    } on Object catch (error) {
      result = _IconResolutionFailure(
        'The saved custom icon for ${widget.name} is invalid or missing. '
        'The icon could not be loaded: $error',
      );
    }
    if (!mounted ||
        generation != _generation ||
        !(_request?.matches(request) ?? false)) {
      return;
    }
    if (_sameResolution(_resolution, result)) return;
    setState(() => _resolution = result);
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final content = switch (_resolution) {
      _ResolvedIcon(:final bytes) => Image.memory(
        bytes,
        key: ModeItemIconKeys.image(widget.name),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => _IconFailure(
          key: ModeItemIconKeys.failure(widget.name),
          message:
              'The configured icon for ${widget.name} could not be decoded.',
          size: widget.size,
          fallbackIcon: widget.fallbackIcon,
        ),
      ),
      _IconResolutionLoading() => _IconLoading(
        key: ModeItemIconKeys.loading(widget.name),
        size: widget.size,
      ),
      _IconResolutionFailure(:final message) => _IconFailure(
        key: ModeItemIconKeys.failure(widget.name),
        message: message,
        size: widget.size,
        fallbackIcon: widget.fallbackIcon,
      ),
    };
    final image = !widget.showFrame
        ? SizedBox.square(dimension: widget.size, child: content)
        : switch (spec.family) {
            RetainedVisualFamily.standard => SizedBox.square(
              dimension: widget.size,
              child: content,
            ),
            RetainedVisualFamily.illuminatedLedger => Container(
              width: widget.size,
              height: widget.size,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: spec.palette.surfaceInset,
                borderRadius: BorderRadius.circular(spec.geometry.fieldRadius),
                border: Border.all(
                  color: spec.palette.trimBright.withAlpha(126),
                ),
              ),
              child: content,
            ),
            RetainedVisualFamily.sakuraNightGarden => Container(
              width: widget.size,
              height: widget.size,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: spec.palette.surfaceInset,
                gradient: spec.materials.surfaceRaised,
                borderRadius: BorderRadius.circular(spec.geometry.fieldRadius),
                border: Border.all(
                  color: spec.palette.trimBright.withAlpha(176),
                  width: 1.1,
                ),
                boxShadow: spec.materials.lowShadow,
              ),
              child: Padding(padding: const EdgeInsets.all(1), child: content),
            ),
          };
    return Semantics(
      image: true,
      label: _resolution.semanticLabel,
      child: image,
    );
  }
}

class _IconLoading extends StatelessWidget {
  const _IconLoading({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox.square(
      dimension: size * .38,
      child: CircularProgressIndicator(
        strokeWidth: 1.5,
        color: context.visualTheme.palette.trimBright,
      ),
    ),
  );
}

class _IconFailure extends StatelessWidget {
  const _IconFailure({
    required this.message,
    required this.size,
    this.fallbackIcon,
    super.key,
  });

  final String message;
  final double size;
  final IconData? fallbackIcon;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: message,
    child: Semantics(
      label: message,
      child: Icon(
        fallbackIcon ?? Icons.broken_image_outlined,
        size: size * .5,
        color: fallbackIcon == null
            ? context.visualTheme.palette.warning
            : context.visualTheme.palette.trimBright,
      ),
    ),
  );
}

sealed class _IconResolution {
  const _IconResolution(this.semanticLabel);

  final String semanticLabel;
}

final class _ResolvedIcon extends _IconResolution {
  const _ResolvedIcon({required this.bytes, required String semanticLabel})
    : super(semanticLabel);

  final Uint8List bytes;
}

final class _IconResolutionLoading extends _IconResolution {
  const _IconResolutionLoading(super.semanticLabel);
}

final class _IconResolutionFailure extends _IconResolution {
  const _IconResolutionFailure(this.message) : super(message);

  final String message;
}

bool _sameResolution(_IconResolution current, _IconResolution next) =>
    switch ((current, next)) {
      (
        _ResolvedIcon(bytes: final currentBytes),
        _ResolvedIcon(bytes: final nextBytes),
      ) =>
        identical(currentBytes, nextBytes),
      (
        _IconResolutionFailure(message: final currentMessage),
        _IconResolutionFailure(message: final nextMessage),
      ) =>
        currentMessage == nextMessage,
      (_IconResolutionLoading(), _IconResolutionLoading()) => true,
      _ => false,
    };

sealed class _IconRequest {
  const _IconRequest();

  bool matches(_IconRequest other);
}

final class _CustomIconRequest extends _IconRequest {
  const _CustomIconRequest({
    required this.store,
    required this.reference,
    required this.loader,
  });

  final CustomIconStore store;
  final CustomIconReference reference;
  final CustomIconBytesLoader loader;

  @override
  bool matches(_IconRequest other) =>
      other is _CustomIconRequest &&
      identical(store, other.store) &&
      identical(loader, other.loader) &&
      _referenceSignature(reference) == _referenceSignature(other.reference);
}

final class _ImmediateIconRequest extends _IconRequest {
  const _ImmediateIconRequest({
    required this.owner,
    required this.signature,
    required this.resolution,
  });

  final Object owner;
  final String signature;
  final _IconResolution resolution;

  @override
  bool matches(_IconRequest other) =>
      other is _ImmediateIconRequest &&
      identical(owner, other.owner) &&
      signature == other.signature;
}

_IconRequest _resolveRequest({
  required ModeFeatureController controller,
  required CatalogRepository catalogRepository,
  required CustomIconStore? iconStore,
  required CustomIconBytesLoader customIconLoader,
  required String name,
  required bool searchAcrossModes,
}) {
  final state = controller.state.value;
  final custom = _foldedEntry(state.customIcons, name);
  if (custom != null) {
    if (iconStore == null) {
      return _ImmediateIconRequest(
        owner: controller,
        signature: 'custom-unavailable:${_referenceSignature(custom.value)}',
        resolution: _IconResolutionFailure(
          'The saved custom icon for $name is unavailable because its icon '
          'store is not connected.',
        ),
      );
    }
    return _CustomIconRequest(
      store: iconStore,
      reference: custom.value,
      loader: customIconLoader,
    );
  }

  final alias = _foldedEntry(state.iconAliases, name)?.value.trim();
  final aliases = alias == null || alias.isEmpty
      ? const <String>[]
      : <String>[alias];
  final uri = searchAcrossModes
      ? catalogRepository.iconDataUriAcrossModes(
          controller.mode,
          name,
          aliases: aliases,
        )
      : catalogRepository.iconDataUri(controller.mode, name, aliases: aliases);
  final signature =
      '${controller.mode.key}\u0000${searchAcrossModes ? 'all' : 'mode'}'
      '\u0000${name.toLowerCase()}\u0000${alias ?? ''}';
  if (uri == null) {
    return _ImmediateIconRequest(
      owner: catalogRepository,
      signature: signature,
      resolution: _IconResolutionFailure(
        alias == null || alias.isEmpty
            ? 'No icon artwork is available for $name.'
            : 'The saved icon alias for $name does not resolve to available '
                  'artwork ($alias).',
      ),
    );
  }
  final bytes = _DataUriIconCache.instance.resolve(uri);
  if (bytes == null) {
    return _ImmediateIconRequest(
      owner: catalogRepository,
      signature: signature,
      resolution: _IconResolutionFailure(
        'The configured icon artwork for $name is invalid.',
      ),
    );
  }
  return _ImmediateIconRequest(
    owner: catalogRepository,
    signature: signature,
    resolution: _ResolvedIcon(bytes: bytes, semanticLabel: '$name icon'),
  );
}

String _referenceSignature(CustomIconReference reference) =>
    '${reference.relativePath}\u0000${reference.sha256.toUpperCase()}'
    '\u0000${reference.mediaType.toLowerCase()}\u0000${reference.byteCount}'
    '\u0000${reference.width ?? ''}\u0000${reference.height ?? ''}';

MapEntry<String, T>? _foldedEntry<T>(Map<String, T> values, String name) {
  final exact = values[name];
  if (exact != null) return MapEntry<String, T>(name, exact);
  final folded = name.toLowerCase();
  for (final entry in values.entries) {
    if (entry.key.toLowerCase() == folded) return entry;
  }
  return null;
}

final class _CatalogRepositories {
  _CatalogRepositories._();

  static final _CatalogRepositories instance = _CatalogRepositories._();
  final Expando<CatalogRepository> _values = Expando<CatalogRepository>(
    'mode-item-icon-catalog-repository',
  );

  CatalogRepository resolve(CatalogSnapshot snapshot) {
    final cached = _values[snapshot];
    if (cached != null) return cached;
    final created = CatalogRepository(snapshot);
    _values[snapshot] = created;
    return created;
  }
}

final class _DataUriIconCache {
  _DataUriIconCache._();

  static final _DataUriIconCache instance = _DataUriIconCache._();
  static const int _limit = 256;
  final LinkedHashMap<String, Uint8List> _values =
      LinkedHashMap<String, Uint8List>();

  Uint8List? resolve(String source) {
    final cached = _values.remove(source);
    if (cached != null) {
      _values[source] = cached;
      return cached;
    }
    try {
      final data = UriData.parse(source);
      if (!data.isBase64 || !data.mimeType.toLowerCase().startsWith('image/')) {
        return null;
      }
      final bytes = data.contentAsBytes();
      if (bytes.isEmpty) return null;
      _values[source] = bytes;
      if (_values.length > _limit) _values.remove(_values.keys.first);
      return bytes;
    } on FormatException {
      return null;
    }
  }
}
