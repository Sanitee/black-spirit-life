import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/market/shared_market_repository.dart';
import '../../visual/visual.dart';
import 'opportunities_controller.dart';
import 'opportunities_visuals.dart';

/// Only this control ticks; the recipe workspace does not rebuild each second.
class OpportunityRefreshControl extends StatefulWidget {
  const OpportunityRefreshControl({required this.controller, super.key});

  final OpportunitiesController controller;

  @override
  State<OpportunityRefreshControl> createState() =>
      _OpportunityRefreshControlState();
}

class _OpportunityRefreshControlState extends State<OpportunityRefreshControl>
    with WidgetsBindingObserver {
  StreamSubscription<void>? _activity;
  Timer? _tick;
  Timer? _activityUpdate;
  late SharedMarketRefreshReadiness _readiness;
  Duration _dispatchWait = Duration.zero;
  bool _visible = false;
  bool _foreground = true;

  bool get _active => _visible && _foreground;
  // Normal request pacing is not a visible pause. Avoid flashing “0:01” for
  // each forty-millisecond dispatch gap; the broker still reports exact time.
  bool get _showDispatchWait => _dispatchWait >= const Duration(seconds: 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _attach();
  }

  void _attach() {
    _readiness = widget.controller.refreshReadiness;
    _dispatchWait = widget.controller.activeDispatchWait;
    widget.controller.addListener(_update);
    _activity = widget.controller.sharedMarket?.activityChanges.listen((_) {
      if (!_active || _activityUpdate != null) return;
      // Coalesce without indefinitely postponing updates on a busy scan.
      _activityUpdate = Timer(const Duration(milliseconds: 200), () {
        _activityUpdate = null;
        _update();
      });
    });
  }

  void _detach(OpportunitiesController controller) {
    controller.removeListener(_update);
    unawaited(_activity?.cancel());
    _activity = null;
    _stopTimers();
  }

  @override
  void didUpdateWidget(covariant OpportunityRefreshControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detach(oldWidget.controller);
      _attach();
      _scheduleTick();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    if (_active) {
      _readiness = widget.controller.refreshReadiness;
      _dispatchWait = widget.controller.activeDispatchWait;
      _scheduleTick();
    } else {
      _stopTimers();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_active) {
      _update();
    } else {
      _stopTimers();
    }
  }

  void _update() {
    if (!mounted || !_active) return;
    setState(() {
      _readiness = widget.controller.refreshReadiness;
      _dispatchWait = widget.controller.activeDispatchWait;
    });
    _scheduleTick();
  }

  void _scheduleTick() {
    final waiting = widget.controller.scanning
        ? _showDispatchWait
        : !_readiness.canRefresh;
    if (!_active || !waiting) {
      _tick?.cancel();
      _tick = null;
      return;
    }
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _stopTimers() {
    _tick?.cancel();
    _tick = null;
    _activityUpdate?.cancel();
    _activityUpdate = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detach(widget.controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanning = widget.controller.scanning;
    final waiting = !scanning && _readiness.wait > Duration.zero;
    final scanWaiting = scanning && _showDispatchWait;
    final enabled = scanning || _readiness.canRefresh;
    final label = scanning
        ? 'Stop check'
        : enabled
        ? 'Refresh'
        : 'Please wait';
    final spec = context.visualTheme;
    final countdown = _formatWait(scanning ? _dispatchWait : _readiness.wait);
    return OpportunityButton(
      key: const ValueKey('opportunities-refresh'),
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      semanticLabel: scanWaiting
          ? 'Stop check. Waiting $countdown before queued market requests.'
          : waiting
          ? 'Refresh in $countdown'
          : label,
      tooltip: scanWaiting
          ? 'Queued requests resume automatically when allowed. '
                'Stop cancels the check.'
          : scanning
          ? 'Stop checking market data.'
          : waiting
          ? _readiness.providerPaused
                ? 'The market asked us to wait before checking again.'
                : 'You can refresh again when the timer ends.'
          : !enabled
          ? 'Finishing the current market check.'
          : 'Load the latest market prices and stock.',
      onPressed: scanning
          ? widget.controller.cancel
          : enabled
          ? () => unawaited(widget.controller.refresh())
          : null,
      child: scanWaiting || waiting
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(scanning ? label : 'Refresh in'),
                const SizedBox(width: 8),
                Text(
                  countdown,
                  key: ValueKey(
                    scanning
                        ? 'opportunities-dispatch-countdown'
                        : 'opportunities-refresh-countdown',
                  ),
                  style: spec.typography.meta.copyWith(
                    fontSize: 12,
                    height: 1.1,
                    color: spec.palette.textMuted,
                  ),
                ),
              ],
            )
          : Text(label),
    );
  }
}

String _formatWait(Duration wait) {
  final seconds =
      (wait.inMicroseconds + Duration.microsecondsPerSecond - 1) ~/
      Duration.microsecondsPerSecond;
  if (seconds >= 3600) {
    return '${seconds ~/ 3600}:'
        '${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
