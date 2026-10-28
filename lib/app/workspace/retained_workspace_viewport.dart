import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Keeps a hidden workspace mounted without relaying every window resize to it.
///
/// Offstage alone still lays out its child at the new size. Retain both layout
/// constraints and MediaQuery while hidden, then deliver current metrics before
/// the first visible frame. Data listeners and state remain alive throughout.
class RetainedWorkspaceViewport extends StatefulWidget {
  const RetainedWorkspaceViewport({
    required this.offstage,
    required this.child,
    super.key,
  });

  final bool offstage;
  final Widget child;

  @override
  State<RetainedWorkspaceViewport> createState() =>
      _RetainedWorkspaceViewportState();
}

class _RetainedWorkspaceViewportState extends State<RetainedWorkspaceViewport> {
  MediaQueryData? _visibleMedia;

  @override
  Widget build(BuildContext context) {
    final currentMedia = MediaQuery.maybeOf(context);
    if (!widget.offstage || _visibleMedia == null) {
      _visibleMedia = currentMedia;
    }
    return _RetainedOffstage(
      offstage: widget.offstage,
      child: _visibleMedia == null
          ? widget.child
          : MediaQuery(data: _visibleMedia!, child: widget.child),
    );
  }
}

// Extending Offstage also retains its hit-testing, semantics and onstage-child
// traversal behavior. Only the hidden child's layout constraints differ.
class _RetainedOffstage extends Offstage {
  const _RetainedOffstage({required super.offstage, required super.child});

  @override
  RenderOffstage createRenderObject(BuildContext context) =>
      _RenderRetainedOffstage(offstage: offstage);
}

class _RenderRetainedOffstage extends RenderOffstage {
  _RenderRetainedOffstage({required super.offstage});

  BoxConstraints? _visibleConstraints;

  @override
  void performLayout() {
    if (!offstage) {
      _visibleConstraints = constraints;
      super.performLayout();
    } else {
      // Initial hidden workspaces still receive one valid layout for prewarm.
      // Subsequent viewport changes do not invalidate their child layouts.
      _visibleConstraints ??= constraints;
      child?.layout(_visibleConstraints!);
    }
  }
}
