import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../assets.dart';
import '../domain/models.dart';
import '../domain/world_map.dart';
import '../recipe_checklist.dart';
import '../ui/theme.dart';

/// Source-recorded world nodes and area anchors, using world X / -Z tiles.
/// Map tile bytes remain only in a bounded RAM cache.
class SpotMap extends StatefulWidget {
  const SpotMap({
    super.key,
    required this.spots,
    required this.selected,
    required this.methods,
    this.onSelect,
    this.nodes = const [],
    this.overview = false,
    this.onExpand,
    this.preview = false,
    this.viewInsets = EdgeInsets.zero,
    this.locationPoints = const [],
  });
  final List<Spot> spots;
  final Spot? selected;
  final List<Method> methods;
  final ValueChanged<Spot>? onSelect;
  final List<WorldNode> nodes;
  final bool overview;
  final VoidCallback? onExpand;

  /// Passive location artwork for the chosen-spot header. No map controls,
  /// labels, or interactive markers are painted in this mode.
  final bool preview;

  /// Floating map tools may cover an edge without shrinking the actual map.
  /// Fit, focus and button zoom use the remaining visible area as their anchor.
  final EdgeInsets viewInsets;
  final List<GatheringRecipePoint> locationPoints;
  @override
  State<SpotMap> createState() => _SpotMapState();
}

class _SpotMapState extends State<SpotMap> {
  Offset _center = Offset.zero;
  double _zoom = 3;
  Size _size = Size.zero;
  bool _needsFit = false, _autoFit = false;
  final _images = <String, Uint8List>{};
  final _queued = <String>{}, _failed = <String>{};
  final _queue = Queue<String>();
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  int _active = 0, _bytes = 0;
  double get _scale => 256 / 3276800 * math.pow(2, _zoom);
  Rect get _usableBounds {
    final left = widget.viewInsets.left
        .clamp(0.0, math.max(0.0, _size.width - 1))
        .toDouble();
    final top = widget.viewInsets.top
        .clamp(0.0, math.max(0.0, _size.height - 1))
        .toDouble();
    return Rect.fromLTRB(
      left,
      top,
      (_size.width - widget.viewInsets.right).clamp(
        left + 1,
        math.max(left + 1, _size.width),
      ),
      (_size.height - widget.viewInsets.bottom).clamp(
        top + 1,
        math.max(top + 1, _size.height),
      ),
    );
  }

  Offset get _middle => _usableBounds.center;
  Offset _screen(double x, double z) =>
      _middle + (Offset(x, -z) - _center) * _scale;
  bool _visible(Offset p, double margin) =>
      p.dx >= -margin &&
      p.dy >= -margin &&
      p.dx <= _size.width + margin &&
      p.dy <= _size.height + margin;

  @override
  void initState() {
    super.initState();
    _focus();
  }

  @override
  void didUpdateWidget(SpotMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locationPoints != widget.locationPoints) {
      _needsFit = _autoFit = true;
    }
    if (oldWidget.selected?.id != widget.selected?.id) {
      _focus();
    } else if (widget.overview &&
        oldWidget.spots.map((s) => s.id).join('|') !=
            widget.spots.map((s) => s.id).join('|')) {
      _needsFit = _autoFit = true;
    }
    if (oldWidget.viewInsets != widget.viewInsets && _autoFit) {
      _needsFit = true;
    }
  }

  void _focus() {
    final s = widget.selected;
    if (s?.mapped == true) {
      _center = Offset(s!.x!, -s.z!);
      _zoom = 6.1;
      _needsFit = _autoFit = false;
    } else {
      _needsFit = _autoFit = true;
    }
  }

  void _fit() {
    _needsFit = false;
    final points = widget.locationPoints.isNotEmpty
        ? widget.locationPoints.map((p) => (x: p.x, z: p.z)).toList()
        : widget.spots
              .where((s) => s.mapped)
              .map((s) => (x: s.x!, z: s.z!))
              .toList();
    if (points.isEmpty) {
      _center = Offset.zero;
      _zoom = 3;
      return;
    }
    final left = points.map((s) => s.x).reduce(math.min),
        right = points.map((s) => s.x).reduce(math.max);
    final top = points.map((s) => -s.z).reduce(math.min),
        bottom = points.map((s) => -s.z).reduce(math.max);
    _center = Offset((left + right) / 2, (top + bottom) / 2);
    if (right - left < 1 && bottom - top < 1) {
      _zoom = 6.1;
      return;
    }
    final usable = _usableBounds;
    final padding = math.min(68.0, usable.shortestSide * .24);
    final scale = math.min(
      math.max(1.0, usable.width - 2 * padding) / math.max(1.0, right - left),
      math.max(1.0, usable.height - 2 * padding) / math.max(1.0, bottom - top),
    );
    _zoom = (math.log(scale * 3276800 / 256) / math.ln2).clamp(-1.0, 7.0);
  }

  void _changeZoom(double next, Offset anchor) {
    final target = next.clamp(-1.0, 8.2);
    if (target == _zoom) return;
    final delta = anchor - _middle,
        world = _center + (anchor - _middle) / _scale;
    setState(() {
      _autoFit = false;
      _zoom = target;
      _center = world - delta / _scale;
    });
  }

  void _recenter() => setState(() {
    _failed.clear();
    if (widget.overview || widget.selected == null) {
      _needsFit = _autoFit = true;
    } else {
      _focus();
    }
  });

  void _request(String key) {
    if (_images.containsKey(key) ||
        _queued.contains(key) ||
        _failed.contains(key) ||
        _queue.length >= 64) {
      return;
    }
    _queued.add(key);
    _queue.add(key);
    _pump();
  }

  void _pump() {
    while (_active < 4 && _queue.isNotEmpty) {
      _active++;
      _load(_queue.removeFirst());
    }
  }

  Future<void> _load(String key) async {
    try {
      final request = await _client.getUrl(
        Uri.parse('https://shrddr.github.io/maptiles/$key.webp'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 18),
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw const HttpException('Tile unavailable');
      }
      final builder = BytesBuilder(copy: false);
      await for (final bytes in response.timeout(const Duration(seconds: 18))) {
        if (builder.length + bytes.length > 3 * 1024 * 1024) {
          throw const HttpException('Tile exceeds limit');
        }
        builder.add(bytes);
      }
      final bytes = builder.takeBytes();
      if (!mounted) return;
      _images[key] = bytes;
      _bytes += bytes.length;
      while (_bytes > 32 * 1024 * 1024 && _images.length > 1) {
        _bytes -= _images.remove(_images.keys.first)!.length;
      }
    } catch (_) {
      _failed.add(key);
      if (_failed.length > 256) _failed.remove(_failed.first);
    } finally {
      _queued.remove(key);
      _active--;
      if (mounted) {
        setState(() {});
        _pump();
      }
    }
  }

  @override
  void dispose() {
    _queue.clear();
    _client.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Listener(
      key: const ValueKey('spot-map-viewport'),
      behavior: HitTestBehavior.opaque,
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
          // Register at the map ancestor so every child consumes the wheel
          // before an enclosing page Scrollable can claim the same event.
          GestureBinding.instance.pointerSignalResolver.register(event, (
            signal,
          ) {
            final scroll = signal as PointerScrollEvent;
            _changeZoom(
              _zoom - scroll.scrollDelta.dy * .0025,
              scroll.localPosition,
            );
          });
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final resized = size != _size;
          _size = size;
          if (_needsFit || (_autoFit && resized)) _fit();
          final groups = _groups();
          final occupied = <Rect>[
            if (widget.viewInsets.left > 0)
              Rect.fromLTWH(0, 0, widget.viewInsets.left, _size.height),
            if (widget.viewInsets.top > 0)
              Rect.fromLTWH(0, 0, _size.width, widget.viewInsets.top),
            if (widget.viewInsets.right > 0)
              Rect.fromLTWH(
                _usableBounds.right,
                0,
                widget.viewInsets.right,
                _size.height,
              ),
            if (widget.viewInsets.bottom > 0)
              Rect.fromLTWH(
                0,
                _usableBounds.bottom,
                _size.width,
                widget.viewInsets.bottom,
              ),
            Rect.fromLTWH(
              _usableBounds.right - 52,
              _usableBounds.top,
              52,
              widget.onExpand == null ? 124 : 160,
            ),
            for (final group in groups)
              Rect.fromCircle(
                center: _screen(group.first.x!, group.first.z!),
                radius: group.any((s) => s.id == widget.selected?.id) ? 26 : 23,
              ),
            for (final group in groups)
              if (group.any((s) => s.id == widget.selected?.id))
                _selectedLabelRect(
                  widget.selected!,
                  _screen(group.first.x!, group.first.z!),
                ),
          ];
          final annotations = <Widget>[
            if (!widget.preview && _zoom >= 5.4)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _NodeConnections(
                      widget.nodes,
                      _center,
                      _scale,
                      _middle,
                    ),
                  ),
                ),
              ),
            if (!widget.preview) ..._nodeWidgets(occupied),
            if (!widget.preview)
              for (final group in groups) ..._markers(group),
            if (!widget.preview)
              for (final point in widget.locationPoints)
                if (_visible(_screen(point.x, point.z), 8))
                  Positioned(
                    left: _screen(point.x, point.z).dx - 5,
                    top: _screen(point.x, point.z).dy - 5,
                    child: Tooltip(
                      message: point.label,
                      child: Container(
                        key: ValueKey('recipe-location-${point.id}'),
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFF1D295),
                          border: Border.all(
                            color: const Color(0xFF332622),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
          ];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (e) => setState(() {
              _autoFit = false;
              _center -= e.delta / _scale;
            }),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: widget.preview
                      ? const CompanionBackdrop(child: SizedBox.expand())
                      : const ColoredBox(color: Color(0xFF304448)),
                ),
                ..._tiles(),
                if (widget.viewInsets == EdgeInsets.zero)
                  ...annotations
                else if (!widget.preview)
                  Positioned.fill(
                    // Only annotations are clipped. Terrain remains visible
                    // beneath the floating glass, without symbols competing
                    // with its text or accepting taps through the reading lane.
                    child: ClipRect(
                      key: const ValueKey('spot-map-annotation-clip'),
                      clipper: _MapAnnotationClipper(_usableBounds),
                      clipBehavior: Clip.hardEdge,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: annotations,
                      ),
                    ),
                  ),
                if (!widget.preview)
                  Positioned(
                    top: _usableBounds.top + 9,
                    right: _size.width - _usableBounds.right + 9,
                    child: Column(
                      children: [
                        _control(
                          'map-zoom-in',
                          Icons.add,
                          'Zoom in',
                          () => _changeZoom(_zoom + .5, _middle),
                        ),
                        const SizedBox(height: 4),
                        _control(
                          'map-zoom-out',
                          Icons.remove,
                          'Zoom out',
                          () => _changeZoom(_zoom - .5, _middle),
                        ),
                        const SizedBox(height: 4),
                        _control(
                          'map-recenter',
                          Icons.center_focus_strong,
                          'Recenter map',
                          _recenter,
                        ),
                        if (widget.onExpand != null) ...[
                          const SizedBox(height: 4),
                          _control(
                            'expand-spot-map',
                            Icons.open_in_full,
                            'Expand map',
                            widget.onExpand!,
                          ),
                        ],
                      ],
                    ),
                  ),
                if (!widget.preview && _images.isEmpty && _active > 0)
                  Positioned(
                    left: _usableBounds.left + 12,
                    top: _usableBounds.top + 12,
                    child: const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );

  List<Widget> _tiles() {
    final level = _zoom.floor().clamp(0, 7), needed = <String>[];
    final span = 3276800 / math.pow(2, level),
        pixels = 3276800 / math.pow(2, level) * _scale;
    final topLeft = _center - _middle / _scale;
    final bottomRight =
        _center + (Offset(_size.width, _size.height) - _middle) / _scale;
    final tiles = <Widget>[];
    for (
      var x = (topLeft.dx / span).floor();
      x <= (bottomRight.dx / span).floor();
      x++
    ) {
      for (
        var y = (topLeft.dy / span).floor();
        y <= (bottomRight.dy / span).floor();
        y++
      ) {
        if (x * span > 1484800 ||
            (x + 1) * span < -1715200 ||
            y * span > 896000 ||
            (y + 1) * span < -1817600) {
          continue;
        }
        final key = '$level/${x}_$y';
        needed.add(key);
        final bytes = _images[key];
        if (bytes == null) continue;
        final p = _screen(x * span, -y * span);
        tiles.add(
          Positioned(
            left: p.dx,
            top: p.dy,
            width: pixels + .5,
            height: pixels + .5,
            child: Image.memory(
              bytes,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        );
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        for (final key in needed) {
          _request(key);
        }
      }
    });
    return tiles;
  }

  List<List<Spot>> _groups() {
    final spots = widget.spots.where((s) => s.mapped).toList();
    if (widget.selected?.mapped == true &&
        !spots.any((s) => s.id == widget.selected!.id)) {
      spots.add(widget.selected!);
    }
    spots.sort((a, b) {
      final aSelected = a.id == widget.selected?.id;
      final bSelected = b.id == widget.selected?.id;
      if (aSelected != bSelected) return aSelected ? -1 : 1;
      return a.priority.compareTo(b.priority);
    });
    final groups = <List<Spot>>[];
    for (final spot in spots) {
      final p = _screen(spot.x!, spot.z!);
      if (!_visible(p, 60)) continue;
      final group = groups
          .where((g) => (_screen(g.first.x!, g.first.z!) - p).distance < 46)
          .firstOrNull;
      if (group == null) {
        groups.add([spot]);
      } else {
        group.add(spot);
      }
    }
    groups.sort((a, b) {
      final aSelected = a.any((s) => s.id == widget.selected?.id);
      final bSelected = b.any((s) => s.id == widget.selected?.id);
      return aSelected == bSelected ? 0 : (aSelected ? 1 : -1);
    });
    return groups;
  }

  List<Widget> _nodeWidgets(List<Rect> occupied) {
    final spotNodes = widget.spots.map((spot) => spot.nodeName).toSet();
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final nearby = widget.nodes
        .where((n) => _visible(_screen(n.x, n.z), 28))
        .toList();
    nearby.sort((a, b) {
      final aSelected = a.name == widget.selected?.nodeName,
          bSelected = b.name == widget.selected?.nodeName;
      if (aSelected != bSelected) return aSelected ? -1 : 1;
      if (a.isSettlement != b.isSettlement) return a.isSettlement ? -1 : 1;
      return (_screen(a.x, a.z) - _middle).distance.compareTo(
        (_screen(b.x, b.z) - _middle).distance,
      );
    });
    final result = <Widget>[], drawn = <Offset>[];
    for (final node in nearby.take(180)) {
      if (_zoom < 5.4 &&
          !node.isSettlement &&
          !spotNodes.contains(node.name) &&
          node.name != widget.selected?.nodeName) {
        continue;
      }
      final p = _screen(node.x, node.z);
      if (drawn.any(
        (other) => (other - p).distance < (_zoom < 5.4 ? 30 : 20),
      )) {
        continue;
      }
      drawn.add(p);
      final dimension = node.isSettlement ? 30.0 : 28.0;
      result.add(
        Positioned(
          left: p.dx - dimension / 2,
          top: p.dy - dimension / 2,
          child: Semantics(
            key: ValueKey('map-node-${node.id}'),
            button: true,
            label: node.name,
            child: Tooltip(
              message: node.name,
              child: GestureDetector(
                onTap: () => setState(() {
                  _autoFit = false;
                  _center = Offset(node.x, -node.z);
                  _zoom = math.max(_zoom, 6.1);
                }),
                child: SizedBox.square(
                  dimension: dimension,
                  child: Image.asset(
                    node.icon,
                    package: gatheringAssetPackage,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      if (_zoom < 6.0 &&
          !node.isSettlement &&
          node.name != widget.selected?.nodeName) {
        continue;
      }
      final style = TextStyle(
        inherit: false,
        fontFamily: 'Segoe UI',
        fontSize: node.isSettlement ? 13 : 12,
        height: 1.2,
        letterSpacing: 0,
        fontWeight: node.isSettlement ? FontWeight.w600 : FontWeight.w500,
        color: context.glass.adapt(
          const Color(0xFFF4F0DF),
          context.gatheringColors.ink,
        ),
      );
      final text = TextPainter(
        text: TextSpan(text: node.name, style: style),
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final width = text.width.ceilToDouble() + 12,
          height = text.height.ceilToDouble() + 6;
      text.dispose();
      final alternatives = [
        Rect.fromLTWH(
          p.dx - width / 2,
          p.dy + dimension / 2 + 2,
          width,
          height,
        ),
        Rect.fromLTWH(
          p.dx - width / 2,
          p.dy - dimension / 2 - height - 2,
          width,
          height,
        ),
        Rect.fromLTWH(
          p.dx + dimension / 2 + 3,
          p.dy - height / 2,
          width,
          height,
        ),
      ];
      final label = alternatives
          .where(
            (r) =>
                r.left >= 4 &&
                r.top >= 4 &&
                r.right <= _size.width - 4 &&
                r.bottom <= _size.height - 4 &&
                !occupied.any((o) => o.overlaps(r.inflate(2))),
          )
          .firstOrNull;
      if (label == null) continue;
      occupied.add(label);
      result.add(
        Positioned.fromRect(
          rect: label,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.glass.popup,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                child: Text(
                  node.name,
                  key: ValueKey('map-node-label-${node.id}'),
                  style: style,
                  textScaler: textScaler,
                  textDirection: textDirection,
                  softWrap: false,
                  maxLines: 1,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return result;
  }

  String _icon(Spot spot) => spot.icon.isNotEmpty
      ? spot.icon
      : widget.methods
                .where((m) => spot.methodIds.contains(m.id))
                .firstOrNull
                ?.icon ??
            '';

  TextStyle get _spotTitleStyle => TextStyle(
    inherit: false,
    fontFamily: 'Segoe UI',
    fontSize: 14,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: context.gatheringColors.ink,
  );
  TextStyle get _spotNodeStyle => TextStyle(
    inherit: false,
    fontFamily: 'Segoe UI',
    fontSize: 12,
    height: 1.2,
    color: context.gatheringColors.muted,
  );

  Rect _selectedLabelRect(Spot spot, Offset point) {
    final lines = [
      TextSpan(text: spot.displayName, style: _spotTitleStyle),
      TextSpan(text: spot.nodeName, style: _spotNodeStyle),
    ];
    var textWidth = 0.0, textHeight = 0.0;
    for (final line in lines) {
      final painter = TextPainter(
        text: line,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      textWidth = math.max(textWidth, painter.width);
      textHeight += painter.height;
      painter.dispose();
    }
    final width = math.min(
      textWidth.ceilToDouble() + 20,
      math.min(160.0, _size.width - 16),
    );
    final height = textHeight.ceilToDouble() + 10;
    return Rect.fromLTWH(
      (point.dx - width / 2).clamp(8.0, math.max(8.0, _size.width - width - 8)),
      (point.dy + 27).clamp(4.0, math.max(4.0, _size.height - height - 4)),
      width,
      height,
    );
  }

  List<Widget> _markers(List<Spot> group) {
    final selected = group.any((s) => s.id == widget.selected?.id);
    final spot = selected
        ? group.firstWhere((s) => s.id == widget.selected!.id)
        : group.first;
    // Clusters retain a real anchor, never a manufactured average coordinate.
    final p = _screen(group.first.x!, group.first.z!),
        dimension = selected ? 44.0 : 38.0;
    final marker = Positioned(
      left: p.dx - dimension / 2,
      top: p.dy - dimension / 2,
      child: Semantics(
        key: ValueKey(
          group.length == 1
              ? 'map-spot-${spot.id}'
              : 'map-cluster-${group.first.id}',
        ),
        button: true,
        selected: selected,
        label: group.length == 1
            ? spot.displayName
            : '${group.length} gathering spots',
        child: Tooltip(
          message: group
              .map((s) => '${s.displayName} · ${s.nodeName}')
              .join('\n'),
          child: Material(
            color: context.glass.popup,
            borderRadius: BorderRadius.circular(11),
            elevation: selected ? 5 : 3,
            child: InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: () => group.length == 1
                  ? widget.onSelect?.call(spot)
                  : _choose(group),
              child: Container(
                width: dimension,
                height: dimension,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: selected
                        ? context.gatheringColors.gold
                        : const Color(0xFFC1C4AE),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: GameIcon(_icon(spot), size: dimension - 6),
                    ),
                    if (group.length > 1)
                      Positioned(
                        right: -10,
                        top: -10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: context.gatheringColors.gold,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${group.length}',
                            style: TextStyle(
                              color:
                                  context.gatheringColors.gold
                                          .computeLuminance() >
                                      .3
                                  ? const Color(0xFF192625)
                                  : const Color(0xFFFFFCF4),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
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
    if (!selected) return [marker];
    return [
      marker,
      Positioned.fromRect(
        rect: _selectedLabelRect(spot, p),
        child: IgnorePointer(
          child: Container(
            key: ValueKey('map-spot-label-${spot.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: context.glass.popup,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  spot.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: _spotTitleStyle,
                ),
                Text(
                  spot.nodeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: _spotNodeStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Future<void> _choose(List<Spot> spots) async {
    final choice = await showDialog<Spot>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(
          spots.map((s) => s.nodeName).toSet().length == 1
              ? spots.first.nodeName
              : 'Choose a spot',
        ),
        children: spots
            .map(
              (spot) => SimpleDialogOption(
                key: ValueKey('map-choose-${spot.id}'),
                onPressed: () => Navigator.pop(context, spot),
                child: Row(
                  children: [
                    GameIcon(_icon(spot), size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spot.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            spot.nodeName,
                            style: TextStyle(
                              color: context.gatheringColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
    if (mounted && choice != null) widget.onSelect?.call(choice);
  }

  Widget _control(String key, IconData icon, String tip, VoidCallback action) =>
      Material(
        color: context.glass.popup,
        borderRadius: BorderRadius.circular(7),
        child: SizedBox.square(
          dimension: 32,
          child: GatheringQuietIconButton(
            key: ValueKey(key),
            onPressed: action,
            tooltip: tip,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(icon, size: 19),
          ),
        ),
      );
}

class _MapAnnotationClipper extends CustomClipper<Rect> {
  const _MapAnnotationClipper(this.bounds);
  final Rect bounds;

  @override
  Rect getClip(Size size) => bounds.intersect(Offset.zero & size);

  @override
  bool shouldReclip(_MapAnnotationClipper oldClipper) =>
      oldClipper.bounds != bounds;
}

class _NodeConnections extends CustomPainter {
  _NodeConnections(this.nodes, this.center, this.scale, this.middle);
  final List<WorldNode> nodes;
  final Offset center;
  final double scale;
  final Offset middle;
  @override
  void paint(Canvas canvas, Size size) {
    final byId = {for (final node in nodes) node.id: node}, drawn = <String>{};
    final visible = Offset.zero & size;
    Offset screen(WorldNode n) => middle + (Offset(n.x, -n.z) - center) * scale;
    final paint = Paint()
      ..color = const Color(0x788FA49F)
      ..strokeWidth = 1.15;
    for (final node in nodes) {
      for (final targetId in node.links) {
        final target = byId[targetId];
        if (target == null) continue;
        final key = node.id.compareTo(targetId) < 0
            ? '${node.id}:$targetId'
            : '$targetId:${node.id}';
        if (!drawn.add(key)) continue;
        final from = screen(node), to = screen(target);
        if (Rect.fromPoints(from, to).inflate(2).overlaps(visible)) {
          canvas.drawLine(from, to, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_NodeConnections old) =>
      old.nodes != nodes ||
      old.center != center ||
      old.scale != scale ||
      old.middle != middle;
}
