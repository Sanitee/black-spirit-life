import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Paint-only protection for glass: terrain remains visible, while annotations
/// beneath the few reading planes are omitted. No map records are filtered.
class ResourceMapAnnotationOcclusion extends ChangeNotifier {
  final Map<Object, Rect> _planes = {};
  bool _pending = false;
  bool _disposed = false;
  Path? _cachedPath;
  Rect? _cachedViewport;

  void update(Object owner, Rect? rect) {
    if (_disposed || _planes[owner] == rect) return;
    if (rect == null) {
      _planes.remove(owner);
    } else {
      _planes[owner] = rect;
    }
    _cachedPath = null;
    if (_pending) return;
    _pending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      if (!_disposed) notifyListeners();
    });
  }

  Path visiblePath(Offset origin, Size size) {
    final viewport = origin & size;
    if (_cachedPath != null && _cachedViewport == viewport) return _cachedPath!;
    var path = Path()..addRect(Offset.zero & size);
    for (final rect in _planes.values) {
      if (!rect.overlaps(viewport)) continue;
      path = Path.combine(
        PathOperation.difference,
        path,
        Path()..addRRect(
          RRect.fromRectAndRadius(
            rect.shift(-origin),
            const Radius.circular(10),
          ),
        ),
      );
    }
    _cachedViewport = viewport;
    return _cachedPath = path;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class ResourceMapAnnotationScope extends StatefulWidget {
  const ResourceMapAnnotationScope({required this.child, super.key});
  final Widget child;

  static ResourceMapAnnotationOcclusion? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AnnotationScope>()?.occlusion;

  @override
  State<ResourceMapAnnotationScope> createState() => _AnnotationScopeState();
}

class _AnnotationScopeState extends State<ResourceMapAnnotationScope> {
  final occlusion = ResourceMapAnnotationOcclusion();

  @override
  void dispose() {
    occlusion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _AnnotationScope(occlusion: occlusion, child: widget.child);
}

class _AnnotationScope extends InheritedWidget {
  const _AnnotationScope({required this.occlusion, required super.child});
  final ResourceMapAnnotationOcclusion occlusion;

  @override
  bool updateShouldNotify(_AnnotationScope oldWidget) =>
      occlusion != oldWidget.occlusion;
}

/// Registers this plane's actual painted rectangle, not a fixed panel estimate.
/// Two or three rectangles are compared during paint; unchanged positions do
/// not notify, rebuild, or scan any other render objects.
class ResourceMapAnnotationPlane extends SingleChildRenderObjectWidget {
  const ResourceMapAnnotationPlane({required super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _AnnotationPlane(ResourceMapAnnotationScope.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _AnnotationPlane).occlusion =
        ResourceMapAnnotationScope.of(context);
  }
}

class _AnnotationPlane extends RenderProxyBox {
  _AnnotationPlane(this._occlusion);
  ResourceMapAnnotationOcclusion? _occlusion;

  set occlusion(ResourceMapAnnotationOcclusion? value) {
    if (value == _occlusion) return;
    _occlusion?.update(this, null);
    _occlusion = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _occlusion?.update(this, localToGlobal(Offset.zero) & size);
    super.paint(context, offset);
  }

  @override
  void detach() {
    _occlusion?.update(this, null);
    super.detach();
  }
}

class ResourceMapAnnotationClip extends SingleChildRenderObjectWidget {
  const ResourceMapAnnotationClip({required super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _AnnotationClip(ResourceMapAnnotationScope.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _AnnotationClip).occlusion = ResourceMapAnnotationScope.of(
      context,
    );
  }
}

class _AnnotationClip extends RenderProxyBox {
  _AnnotationClip(this._occlusion);
  ResourceMapAnnotationOcclusion? _occlusion;

  set occlusion(ResourceMapAnnotationOcclusion? value) {
    if (value == _occlusion) return;
    if (attached) _occlusion?.removeListener(markNeedsPaint);
    _occlusion = value;
    if (attached) _occlusion?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _occlusion?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _occlusion?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final path = _occlusion?.visiblePath(localToGlobal(Offset.zero), size);
    if (path != null && !path.contains(position)) return false;
    return super.hitTest(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final occlusion = _occlusion;
    if (occlusion == null) {
      super.paint(context, offset);
      return;
    }
    context.pushClipPath(
      needsCompositing,
      offset,
      Offset.zero & size,
      occlusion.visiblePath(localToGlobal(Offset.zero), size),
      super.paint,
      clipBehavior: Clip.hardEdge,
    );
  }
}
