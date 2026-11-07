import 'package:flutter/material.dart';

import '../foundations/theme_spec.dart';

/// Brief feedback for an externally changed amount, confined to its text paint.
/// Mounting, editing, selection and list scrolling never start this animation.
class AppNumberFade extends StatefulWidget {
  const AppNumberFade({
    required this.controller,
    required this.builder,
    this.focusNode,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final Widget Function(FocusNode focusNode, double opacity) builder;

  @override
  State<AppNumberFade> createState() => _AppNumberFadeState();
}

class _AppNumberFadeState extends State<AppNumberFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1,
  );
  FocusNode? _ownedFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownedFocus ??= FocusNode());
  ScrollPosition? _listPosition;
  late String _lastText;
  bool _motionEnabled = false;

  @override
  void initState() {
    super.initState();
    _lastText = widget.controller.text;
    widget.controller.addListener(_textChanged);
    _focus.addListener(_focusChanged);
  }

  void _finish() {
    if (_fade.value != 1) _fade.value = 1;
  }

  void _textChanged() {
    final next = widget.controller.text;
    if (next == _lastText) return;
    _lastText = next;
    if (!_motionEnabled ||
        _focus.hasFocus ||
        next.trim().isEmpty ||
        (_listPosition?.isScrollingNotifier.value ?? false)) {
      _finish();
    } else {
      // Restart locally on the latest value; never queue old values or tween
      // through amounts the user did not enter.
      _fade.forward(from: 0);
    }
  }

  void _focusChanged() {
    if (_focus.hasFocus) _finish();
  }

  void _scrollChanged() {
    if (_listPosition?.isScrollingNotifier.value ?? false) _finish();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionEnabled =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context) &&
        context.visualTheme.motion.interactionDuration != Duration.zero;
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _listPosition) {
      _listPosition?.isScrollingNotifier.removeListener(_scrollChanged);
      _listPosition = position;
      _listPosition?.isScrollingNotifier.addListener(_scrollChanged);
    }
    if (!_motionEnabled) _finish();
  }

  @override
  void didUpdateWidget(AppNumberFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_textChanged);
      _lastText = widget.controller.text;
      widget.controller.addListener(_textChanged);
      _finish();
    }
    if (widget.focusNode != oldWidget.focusNode) {
      (oldWidget.focusNode ?? _ownedFocus)?.removeListener(_focusChanged);
      _focus.addListener(_focusChanged);
      _finish();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_textChanged);
    _focus.removeListener(_focusChanged);
    _ownedFocus?.dispose();
    _listPosition?.isScrollingNotifier.removeListener(_scrollChanged);
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _fade,
    builder: (context, _) => widget.builder(
      _focus,
      .65 + .35 * Curves.easeOut.transform(_fade.value),
    ),
  );
}
