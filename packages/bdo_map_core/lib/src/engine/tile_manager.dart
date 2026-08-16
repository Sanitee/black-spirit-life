import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../model/map_geometry.dart';
import '../model/tile_source.dart';
import 'tile_cache.dart';

enum BdoTileServiceState {
  idle,
  loading,
  online,
  cachedOnly,
  offlineMissing,
  degraded,
}

class BdoDecodedTile {
  const BdoDecodedTile({
    required this.coordinate,
    required this.image,
    required this.decodedBytes,
    required this.loadedAt,
    required this.fromDisk,
  });

  final BdoTileCoordinate coordinate;
  final ui.Image image;
  final int decodedBytes;
  final DateTime loadedAt;
  final bool fromDisk;
}

class BdoTileManager extends ChangeNotifier {
  BdoTileManager({
    required this.source,
    required this.diskCache,
    http.Client? client,
    this.maximumDecodedBytes = 48 * 1024 * 1024,
    this.maximumConcurrentRequests = 6,
  }) : assert(maximumDecodedBytes > 0),
       assert(maximumConcurrentRequests > 0),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final BdoTileSource source;
  final BdoMapDiskCache diskCache;
  final int maximumDecodedBytes;
  final int maximumConcurrentRequests;
  http.Client _client;
  final bool _ownsClient;

  final LinkedHashMap<BdoTileCoordinate, BdoDecodedTile> _memory =
      LinkedHashMap<BdoTileCoordinate, BdoDecodedTile>();
  final List<_QueuedTile> _queue = <_QueuedTile>[];
  final Set<BdoTileCoordinate> _active = <BdoTileCoordinate>{};
  final Map<BdoTileCoordinate, _TileFailure> _failures =
      <BdoTileCoordinate, _TileFailure>{};
  final Set<BdoTileCoordinate> _offlineMisses = <BdoTileCoordinate>{};
  Set<BdoTileCoordinate> _wanted = <BdoTileCoordinate>{};
  Set<BdoTileCoordinate> _visible = <BdoTileCoordinate>{};
  ({
    int zoom,
    int minimumX,
    int maximumX,
    int minimumY,
    int maximumY,
    int prefetchRing,
  })?
  _viewportSignature;
  int _viewportBuildCount = 0;
  int _decodedBytes = 0;
  int _decodedTileRevision = 0;
  int _cacheEpoch = 0;
  int _networkEpoch = 0;
  bool _networkEnabled = true;
  bool _disposed = false;
  bool _hasNetworkSuccess = false;
  bool _hasCacheSuccess = false;

  int get decodedBytes => _decodedBytes;
  int get decodedTileCount => _memory.length;
  int get decodedTileRevision => _decodedTileRevision;
  int get activeRequestCount => _active.length;
  int get queuedRequestCount => _queue.length;
  bool get networkEnabled => _networkEnabled;
  int get failedVisibleTileCount =>
      _visible.where(_failures.containsKey).length;
  int get offlineMissingVisibleTileCount =>
      _visible.where(_offlineMisses.contains).length;
  Set<BdoTileCoordinate> get visibleCoordinates =>
      Set<BdoTileCoordinate>.unmodifiable(_visible);

  @visibleForTesting
  int get debugViewportBuildCount => _viewportBuildCount;

  BdoTileServiceState get serviceState {
    if (_active.isNotEmpty || _queue.isNotEmpty) {
      return BdoTileServiceState.loading;
    }
    if (!_networkEnabled && offlineMissingVisibleTileCount > 0) {
      return BdoTileServiceState.offlineMissing;
    }
    if (failedVisibleTileCount > 0) {
      return BdoTileServiceState.degraded;
    }
    if (!_networkEnabled) {
      return BdoTileServiceState.cachedOnly;
    }
    if (_hasNetworkSuccess) {
      return BdoTileServiceState.online;
    }
    if (_hasCacheSuccess) {
      return BdoTileServiceState.cachedOnly;
    }
    return BdoTileServiceState.idle;
  }

  set networkEnabled(bool value) {
    if (_networkEnabled == value) {
      return;
    }
    _networkEnabled = value;
    _networkEpoch += 1;
    if (!value && _ownsClient) {
      _client.close();
      _client = http.Client();
    }
    if (value) {
      _offlineMisses.removeAll(_wanted);
    }
    // Cached-only mode still drains disk reads; only the HTTP fallback stops.
    _enqueueMissing();
    _notify();
    _pump();
  }

  BdoDecodedTile? tile(BdoTileCoordinate coordinate) {
    final existing = _memory.remove(coordinate);
    if (existing == null) {
      return null;
    }
    _memory[coordinate] = existing;
    return existing;
  }

  BdoDecodedTile? nearestAncestor(BdoTileCoordinate coordinate) {
    var x = coordinate.x;
    var y = coordinate.y;
    for (
      var zoom = coordinate.zoom - 1;
      zoom >= source.minimumZoom;
      zoom -= 1
    ) {
      x = _floorDivide(x, 2);
      y = _floorDivide(y, 2);
      final ancestor = tile(BdoTileCoordinate(zoom: zoom, x: x, y: y));
      if (ancestor != null) {
        return ancestor;
      }
    }
    return null;
  }

  void updateViewport({
    required BdoMapBounds visibleBounds,
    required int zoom,
    int prefetchRing = 1,
  }) {
    if (_disposed) {
      return;
    }
    final clampedZoom = zoom.clamp(source.minimumZoom, source.maximumZoom);
    final span = source.worldUnitsPerTile(clampedZoom);
    final minimumX = (visibleBounds.left / span).floor();
    final maximumX = ((visibleBounds.right - 0.0001) / span).floor();
    final minimumY = (visibleBounds.top / span).floor();
    final maximumY = ((visibleBounds.bottom - 0.0001) / span).floor();
    final signature = (
      zoom: clampedZoom,
      minimumX: minimumX,
      maximumX: maximumX,
      minimumY: minimumY,
      maximumY: maximumY,
      prefetchRing: prefetchRing,
    );
    if (signature == _viewportSignature) {
      return;
    }
    _viewportSignature = signature;
    _viewportBuildCount += 1;
    final visible = <BdoTileCoordinate>{};
    final wanted = <BdoTileCoordinate>{};
    final centerX = (minimumX + maximumX) / 2;
    final centerY = (minimumY + maximumY) / 2;
    final queued = <_QueuedTile>[];

    for (var y = minimumY - prefetchRing; y <= maximumY + prefetchRing; y++) {
      for (var x = minimumX - prefetchRing; x <= maximumX + prefetchRing; x++) {
        final coordinate = BdoTileCoordinate(zoom: clampedZoom, x: x, y: y);
        if (!source.contains(coordinate)) {
          continue;
        }
        final isVisible =
            x >= minimumX && x <= maximumX && y >= minimumY && y <= maximumY;
        if (isVisible) {
          visible.add(coordinate);
        }
        wanted.add(coordinate);
        queued.add(
          _QueuedTile(
            coordinate: coordinate,
            priority:
                (isVisible ? 0 : 1000) +
                ((x - centerX).abs() + (y - centerY).abs()) * 10,
          ),
        );
      }
    }

    // Retain low-resolution parents for an immediate, non-blank fallback.
    var parents = Set<BdoTileCoordinate>.from(visible);
    for (
      var parentZoom = clampedZoom - 1;
      parentZoom >= source.minimumZoom;
      parentZoom--
    ) {
      parents = parents
          .map(
            (coordinate) => BdoTileCoordinate(
              zoom: parentZoom,
              x: _floorDivide(coordinate.x, 2),
              y: _floorDivide(coordinate.y, 2),
            ),
          )
          .where(source.contains)
          .toSet();
      for (final coordinate in parents) {
        wanted.add(coordinate);
        queued.add(
          _QueuedTile(
            coordinate: coordinate,
            priority: 2000 + (clampedZoom - parentZoom) * 100,
          ),
        );
      }
    }

    if (setEquals(visible, _visible) && setEquals(wanted, _wanted)) {
      return;
    }
    _visible = visible;
    _wanted = wanted;
    _queue
      ..clear()
      ..addAll(
        queued.where(
          (request) =>
              !_memory.containsKey(request.coordinate) &&
              !_active.contains(request.coordinate),
        ),
      )
      ..sort((a, b) => a.priority.compareTo(b.priority));
    _pump();
    _notify();
  }

  void retryVisible() {
    for (final coordinate in _visible) {
      _failures.remove(coordinate);
    }
    _enqueueMissing();
    _pump();
    _notify();
  }

  /// Clears downloaded and decoded tiles without touching map overlays or
  /// planner state. Downloads are paused so the cache does not immediately
  /// refill; the user can explicitly enable them again.
  Future<int> clearCache() async {
    if (_disposed) {
      return 0;
    }
    _cacheEpoch += 1;
    _networkEpoch += 1;
    _networkEnabled = false;
    if (_ownsClient) {
      _client.close();
      _client = http.Client();
    }
    _queue.clear();
    _failures.clear();
    _offlineMisses
      ..clear()
      ..addAll(_visible);
    _hasCacheSuccess = false;
    _hasNetworkSuccess = false;
    for (final tile in _memory.values) {
      tile.image.dispose();
    }
    _memory.clear();
    _decodedBytes = 0;
    _notify();
    final removedBytes = await diskCache.clear();
    _notify();
    return removedBytes;
  }

  void _enqueueMissing() {
    for (final coordinate in _wanted) {
      if (_memory.containsKey(coordinate) ||
          _active.contains(coordinate) ||
          _queue.any((request) => request.coordinate == coordinate)) {
        continue;
      }
      _queue.add(
        _QueuedTile(
          coordinate: coordinate,
          priority: _visible.contains(coordinate) ? 0 : 1000,
        ),
      );
    }
    _queue.sort((a, b) => a.priority.compareTo(b.priority));
  }

  void _pump() {
    if (_disposed) {
      return;
    }
    while (_queue.isNotEmpty) {
      final usefulActive = _active.where(_wanted.contains).length;
      final belowNormalLimit = _active.length < maximumConcurrentRequests;
      final mayOverlapStale =
          usefulActive < 2 && _active.length < maximumConcurrentRequests + 2;
      if (!belowNormalLimit && !mayOverlapStale) {
        break;
      }
      final request = _queue.removeAt(0);
      if (_memory.containsKey(request.coordinate) ||
          _active.contains(request.coordinate)) {
        continue;
      }
      final failure = _failures[request.coordinate];
      if (failure != null && DateTime.now().isBefore(failure.retryAfter)) {
        continue;
      }
      _active.add(request.coordinate);
      unawaited(_load(request));
    }
  }

  Future<void> _load(_QueuedTile request) async {
    final cacheEpoch = _cacheEpoch;
    final networkEpoch = _networkEpoch;
    Uint8List? encoded;
    var fromDisk = false;
    try {
      encoded = await diskCache.read(
        request.coordinate,
        extension: source.fileExtension,
      );
      fromDisk = encoded != null;
      if (encoded == null && _networkEnabled) {
        encoded = await _download(request.coordinate);
        if (networkEpoch != _networkEpoch) {
          if (!_networkEnabled) {
            _offlineMisses.add(request.coordinate);
          }
          return;
        }
      }
      if (encoded == null) {
        if (!_networkEnabled) {
          _offlineMisses.add(request.coordinate);
        }
        return;
      }
      ui.Image image;
      try {
        image = await _decode(encoded);
      } catch (_) {
        if (!fromDisk) {
          rethrow;
        }
        await diskCache.remove(
          request.coordinate,
          extension: source.fileExtension,
        );
        if (!_networkEnabled || cacheEpoch != _cacheEpoch) {
          rethrow;
        }
        encoded = await _download(request.coordinate);
        if (networkEpoch != _networkEpoch) {
          if (!_networkEnabled) {
            _offlineMisses.add(request.coordinate);
          }
          return;
        }
        fromDisk = false;
        image = await _decode(encoded);
      }
      if (!fromDisk && cacheEpoch == _cacheEpoch) {
        await diskCache.write(
          request.coordinate,
          encoded,
          extension: source.fileExtension,
        );
      }
      if (_disposed || cacheEpoch != _cacheEpoch) {
        image.dispose();
        return;
      }
      final decoded = BdoDecodedTile(
        coordinate: request.coordinate,
        image: image,
        decodedBytes: image.width * image.height * 4,
        loadedAt: DateTime.now(),
        fromDisk: fromDisk,
      );
      _insert(decoded);
      _failures.remove(request.coordinate);
      _offlineMisses.remove(request.coordinate);
      if (fromDisk) {
        _hasCacheSuccess = true;
      } else {
        _hasNetworkSuccess = true;
      }
    } catch (error) {
      if (networkEpoch != _networkEpoch) {
        if (!_networkEnabled) {
          _offlineMisses.add(request.coordinate);
        }
      } else {
        final previous = _failures[request.coordinate];
        final attempt = (previous?.attempt ?? 0) + 1;
        final seconds = (1 << attempt.clamp(0, 6)).clamp(2, 60);
        _failures[request.coordinate] = _TileFailure(
          attempt: attempt,
          retryAfter: DateTime.now().add(Duration(seconds: seconds)),
          error: error,
        );
      }
    } finally {
      _active.remove(request.coordinate);
      if ((cacheEpoch != _cacheEpoch || networkEpoch != _networkEpoch) &&
          !_disposed &&
          _networkEnabled) {
        _enqueueMissing();
      }
      _pump();
      _notify();
    }
  }

  Future<Uint8List> _download(BdoTileCoordinate coordinate) async {
    final uri = source.uriFor(coordinate);
    final response = await _client
        .get(uri, headers: source.headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Tile request returned HTTP ${response.statusCode}.',
        uri,
      );
    }
    if (response.bodyBytes.isEmpty ||
        response.bodyBytes.length > 4 * 1024 * 1024) {
      throw const FormatException('Tile payload size is invalid.');
    }
    return response.bodyBytes;
  }

  Future<ui.Image> _decode(Uint8List encoded) async {
    final codec = await ui.instantiateImageCodec(
      encoded,
      targetWidth: source.tileSize,
      targetHeight: source.tileSize,
    );
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  void _insert(BdoDecodedTile tile) {
    final replaced = _memory.remove(tile.coordinate);
    if (replaced != null) {
      _decodedBytes -= replaced.decodedBytes;
      replaced.image.dispose();
    }
    _memory[tile.coordinate] = tile;
    _decodedBytes += tile.decodedBytes;
    _decodedTileRevision += 1;

    while (_decodedBytes > maximumDecodedBytes && _memory.length > 1) {
      BdoTileCoordinate? evictionKey;
      for (final candidate in _memory.keys) {
        if (!_visible.contains(candidate)) {
          evictionKey = candidate;
          break;
        }
      }
      evictionKey ??= _memory.keys.first;
      final evicted = _memory.remove(evictionKey);
      if (evicted != null) {
        _decodedBytes -= evicted.decodedBytes;
        evicted.image.dispose();
      }
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsClient) {
      _client.close();
    }
    for (final tile in _memory.values) {
      tile.image.dispose();
    }
    _memory.clear();
    _queue.clear();
    _offlineMisses.clear();
    super.dispose();
  }
}

class _QueuedTile {
  const _QueuedTile({required this.coordinate, required this.priority});

  final BdoTileCoordinate coordinate;
  final double priority;
}

class _TileFailure {
  const _TileFailure({
    required this.attempt,
    required this.retryAfter,
    required this.error,
  });

  final int attempt;
  final DateTime retryAfter;
  final Object error;
}

int _floorDivide(int value, int divisor) {
  final quotient = value ~/ divisor;
  final remainder = value % divisor;
  return remainder == 0 || value >= 0 ? quotient : quotient - 1;
}
