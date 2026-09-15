import 'dart:async';

import 'package:flutter/services.dart';

class WindowHostService {
  const WindowHostService({this.closeFlushTimeout = defaultCloseFlushTimeout});

  static const _channel = MethodChannel('com.bdocraftplanner.flutter/window');
  static const defaultCloseFlushTimeout = Duration(seconds: 12);

  final Duration closeFlushTimeout;

  Future<void> beginDrag() => _invoke('beginDrag');
  Future<void> minimize() => _invoke('minimize');

  /// Asks the native runner to begin its Dart-approved close handshake.
  ///
  /// Startup surfaces use this path because they have no local durability
  /// callback of their own. The runner posts WM_CLOSE without pre-authorizing
  /// destruction, so the currently installed close-request handler can first
  /// finish Fish native-surface teardown.
  Future<void> requestClose() => _invoke('requestClose');

  /// Closes after the caller has already completed its durability barrier.
  Future<void> close() => _invoke('close');

  /// Adds or removes a logical-pixel strip below the fixed-ratio workspace.
  /// The native host grows the outer window instead of shrinking planner UI.
  Future<void> setBottomInset(double logicalPixels) => _invoke(
    'setBottomInset',
    <String, Object?>{'logicalPixels': logicalPixels.clamp(0, 96)},
  );

  Future<bool> toggleMaximize() async {
    try {
      return await _channel.invokeMethod<bool>('toggleMaximize') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Installs the save-before-close handshake used for Alt+F4, the taskbar,
  /// and other native close requests. The native runner destroys the window
  /// only after this callback completes successfully.
  void installCloseRequestHandler(Future<void> Function()? handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'closeRequested') {
        throw MissingPluginException('Unknown window callback ${call.method}.');
      }
      if (handler == null) return false;
      await handler().timeout(
        closeFlushTimeout,
        onTimeout: () => throw TimeoutException(
          'Close was canceled because saving did not finish within '
          '${closeFlushTimeout.inSeconds} seconds.',
        ),
      );
      return true;
    });
    // The native window can exist briefly before Dart reaches this point. Let
    // it replay one close request that arrived during that startup gap only
    // after the callback above is able to guard application teardown.
    unawaited(_invoke('closeHandlerReady'));
  }

  void removeCloseRequestHandler() => _channel.setMethodCallHandler(null);

  Future<bool> isMaximized() async {
    try {
      return await _channel.invokeMethod<bool>('isMaximized') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      return;
    }
  }
}
