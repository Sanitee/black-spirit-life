import 'package:flutter/material.dart';

import '../foundations/theme_spec.dart';

/// A restrained, accessibility-aware reveal for small pieces of app chrome.
///
/// The outgoing child is retained until the reverse animation completes. This
/// lets callers remove transient state immediately without making previews or
/// inline details disappear abruptly. Hidden content stops receiving pointer,
/// focus, and semantics input as soon as [visible] becomes false.
class AppRevealTransition extends StatefulWidget {
  const AppRevealTransition({
    required this.visible,
    required this.child,
    this.expandVertically = false,
    this.duration,
    this.curve = Curves.easeOutCubic,
    this.reverseCurve = Curves.easeInCubic,
    super.key,
  });

  final bool visible;
  final Widget? child;
  final bool expandVertically;
  final Duration? duration;
  final Curve curve;
  final Curve reverseCurve;

  @override
  State<AppRevealTransition> createState() => _AppRevealTransitionState();
}

class _AppRevealTransitionState extends State<AppRevealTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.visible ? 1 : 0,
  )..addStatusListener(_handleStatus);
  late CurvedAnimation _progress = _buildProgress();
  Widget? _retainedChild;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    if (widget.visible) _retainedChild = widget.child;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncDuration();
    if (_reduceMotion) {
      _controller.value = widget.visible ? 1 : 0;
      _retainedChild = widget.visible ? widget.child : null;
    }
  }

  @override
  void didUpdateWidget(AppRevealTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.curve != widget.curve ||
        oldWidget.reverseCurve != widget.reverseCurve) {
      _progress.dispose();
      _progress = _buildProgress();
    }
    _syncDuration();

    if (widget.visible) {
      _retainedChild = widget.child;
      if (_reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
      return;
    }

    if (_reduceMotion || _controller.value == 0) {
      _controller.value = 0;
      _retainedChild = null;
    } else {
      _controller.reverse();
    }
  }

  CurvedAnimation _buildProgress() => CurvedAnimation(
    parent: _controller,
    curve: widget.curve,
    reverseCurve: widget.reverseCurve,
  );

  void _syncDuration() {
    final duration =
        widget.duration ??
        ThemeSpecScope.maybeOf(context)?.motion.interactionDuration ??
        const Duration(milliseconds: 100);
    _controller
      ..duration = duration
      ..reverseDuration = duration;
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed || widget.visible) return;
    if (_retainedChild == null || !mounted) return;
    setState(() => _retainedChild = null);
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) {
      return widget.visible && widget.child != null
          ? widget.child!
          : const SizedBox.shrink();
    }

    final retainedChild = _retainedChild;
    if (retainedChild == null) return const SizedBox.shrink();

    Widget transition = FadeTransition(
      opacity: _progress,
      child: retainedChild,
    );
    if (widget.expandVertically) {
      transition = SizeTransition(
        sizeFactor: _progress,
        alignment: Alignment.topCenter,
        child: transition,
      );
    }

    return FocusScope(
      canRequestFocus: widget.visible,
      descendantsAreFocusable: widget.visible,
      child: ExcludeSemantics(
        excluding: !widget.visible,
        child: IgnorePointer(ignoring: !widget.visible, child: transition),
      ),
    );
  }
}
