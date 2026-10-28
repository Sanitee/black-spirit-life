import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Temporary manual experiment; absent from the ordinary workspace tree.
const resourceRedrawDiagnosticEnabled = bool.fromEnvironment(
  'BSL_DIAGNOSTIC_RESOURCE_REDRAW',
);

/// F8 requests one bounded native redraw burst, without changing the scene.
/// No render-object wrapper, Dart ticker, capture, file IO or saved preference.
class ResourceMapRedrawDiagnostic extends StatefulWidget {
  const ResourceMapRedrawDiagnostic({
    required this.active,
    required this.child,
    super.key,
  });

  final bool active;
  final Widget child;

  @override
  State<ResourceMapRedrawDiagnostic> createState() =>
      _ResourceMapRedrawDiagnosticState();
}

class _ResourceMapRedrawDiagnosticState
    extends State<ResourceMapRedrawDiagnostic>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.bdocraftplanner.flutter/window');
  bool _used = false;
  bool _pending = false;
  bool _tickerEnabled = true;
  bool _routeCurrent = true;
  AppLifecycleState? _lifecycle;

  bool get _eligible =>
      mounted &&
      widget.active &&
      _tickerEnabled &&
      _routeCurrent &&
      (_lifecycle == null || _lifecycle == AppLifecycleState.resumed);

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointer);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (!_eligible) _cancel();
  }

  @override
  void didUpdateWidget(ResourceMapRedrawDiagnostic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) _cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (!_eligible) _cancel();
  }

  @override
  void didChangeMetrics() => _cancel();

  bool _handleKey(KeyEvent event) {
    if (const SingleActivator(
      LogicalKeyboardKey.f8,
      includeRepeats: false,
    ).accepts(event, HardwareKeyboard.instance)) {
      if (!_eligible || _used) return false;
      _used = true;
      _pending = true;
      unawaited(_start());
      return true;
    }
    // Preserve the view during the experiment; ordinary input still propagates.
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        event.logicalKey != LogicalKeyboardKey.f8) {
      _cancel();
    }
    return false;
  }

  // Also catch gestures/presses begun before F8. No input details are retained.
  void _handlePointer(PointerEvent _) => _cancel();

  Future<void> _start() async {
    try {
      // The native reply arrives when the capped burst ends or is cancelled.
      // Its count is redraw REQUESTS, never proof of successful presentation.
      await _channel.invokeMethod<Object?>('diagnosticResourceRedrawStart');
    } on MissingPluginException {
      // Unsupported host is not success; do not retry or mutate the UI.
    } on PlatformException {
      // Keep failure local and consume the attempt rather than start a loop.
    } finally {
      _pending = false;
    }
  }

  void _cancel() {
    if (!_pending) return;
    _pending = false;
    unawaited(_sendCancel());
  }

  Future<void> _sendCancel() async {
    try {
      await _channel.invokeMethod<void>('diagnosticResourceRedrawCancel');
    } on MissingPluginException {
      // No timer exists in an ordinary native runner.
    } on PlatformException {
      // Native deadline and request cap remain independent of this reply.
    }
  }

  @override
  void dispose() {
    _cancel();
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_handlePointer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
