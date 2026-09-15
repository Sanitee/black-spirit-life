import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:bdo_fishing_core/src/runtime/fish_companion_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

final bool _isFlutterTest = Platform.environment['FLUTTER_TEST'] == 'true';

const fishyStuffSourceUrl = 'https://fishystuff.fish/map/';
const fishyStuffSourceMessage = 'fishystuff:open-source';

/// Only the user-activated FishyStuff source-credit anchor opts into the host
/// bridge.
/// A standalone browser keeps its ordinary HTTPS anchor behavior.
const fishyStuffSourceLinkScript = r'''
(() => {
  if (window.top !== window || !window.chrome?.webview?.postMessage) return;
  document.addEventListener('click', event => {
    const link = event.target instanceof Element
      ? event.target.closest('a.brand-icon-link') : null;
    if (event.defaultPrevented || !link ||
        link.href !== 'https://fishystuff.fish/map/') return;
    event.preventDefault();
    window.chrome.webview.postMessage('fishystuff:open-source');
  });
})()
''';

/// Fixed-target dispatcher: web content cannot supply a URL or native action.
class FishyStuffSourceLink {
  // This existing Windows channel is host-owned; no Gathering code is imported.
  static const _channel = MethodChannel('bdo_gathering/native');
  bool _opening = false;

  /// Null means an unrelated message or an already-pending explicit request.
  Future<bool?> handleMessage(Object? message) async {
    if (message != fishyStuffSourceMessage || _opening) return null;
    _opening = true;
    try {
      return await _channel.invokeMethod<bool>('openExternal', {
            'url': fishyStuffSourceUrl,
          }) ??
          false;
    } on Object {
      return false;
    } finally {
      _opening = false;
    }
  }
}

/// The terminal readiness state of the accepted standalone Fish page.
enum FishCompanionPageStatus { starting, ready, failed }

/// Test seam for completing the page-readiness handoff without a native
/// WebView2 instance.
typedef FishCompanionPageReadinessOverride =
    Future<FishCompanionPageStatus> Function();

typedef _FishCompanionScriptExecutor = Future<Object?> Function(String script);

/// Whether this Fish surface created the process-wide WebView2 environment or
/// safely joined one already created for another Stable workspace.
@visibleForTesting
enum FishCompanionWebViewEnvironmentOwnership { isolated, shared }

@visibleForTesting
bool canReuseExistingFishCompanionWebViewEnvironment(Object error) =>
    error is PlatformException &&
    error.code == 'environment_already_initialized';

@visibleForTesting
Future<FishCompanionWebViewEnvironmentOwnership>
initializeFishCompanionWebViewEnvironment(
  Future<void> Function() initializeSharedEnvironment,
) async {
  try {
    await initializeSharedEnvironment();
    return FishCompanionWebViewEnvironmentOwnership.isolated;
  } on PlatformException catch (error) {
    if (!canReuseExistingFishCompanionWebViewEnvironment(error)) rethrow;
    return FishCompanionWebViewEnvironmentOwnership.shared;
  }
}

const String _fishCompanionPageStatusScript = r'''
(() => {
  const app = document.getElementById('app');
  const boot = document.getElementById('boot');
  if (
    document.readyState === 'complete' &&
    boot === null &&
    app !== null &&
    !app.classList.contains('is-hidden')
  ) {
    return 'ready';
  }
  const bootText = document.getElementById('bootText');
  if (bootText !== null && bootText.style.color !== '') {
    return 'failed';
  }
  return 'starting';
})()
''';

/// Waits until the standalone page has either removed its own boot overlay or
/// displayed its own terminal bootstrap failure.
Future<FishCompanionPageStatus> waitForFishCompanionPageTerminalStatus(
  Future<Object?> Function(String script) executeScript, {
  Duration pollInterval = const Duration(milliseconds: 80),
  Duration timeout = const Duration(seconds: 60),
}) async {
  assert(!pollInterval.isNegative);
  assert(timeout > Duration.zero);
  final elapsed = Stopwatch()..start();
  while (elapsed.elapsed < timeout) {
    final remaining = timeout - elapsed.elapsed;
    Object? result;
    try {
      result = await executeScript(
        _fishCompanionPageStatusScript,
      ).timeout(remaining);
    } on Object {
      // Script execution can race the first document navigation. Keep polling
      // until the single overall deadline rather than treating that as a page
      // failure.
    }
    switch (result) {
      case 'ready':
        return FishCompanionPageStatus.ready;
      case 'failed':
        return FishCompanionPageStatus.failed;
    }
    final delayRemaining = timeout - elapsed.elapsed;
    if (delayRemaining <= Duration.zero) break;
    await Future<void>.delayed(
      pollInterval.compareTo(delayRemaining) < 0
          ? pollInterval
          : delayRemaining,
    );
  }
  throw TimeoutException('Fish Map did not finish loading.', timeout);
}

/// The accepted standalone Fish Companion, hosted without a replacement UI.
class FishCompanionView extends StatefulWidget {
  const FishCompanionView({
    required this.runtimeHost,
    this.onPageStatusChanged,
    this.pageReadinessOverride,
    super.key,
  });

  final FishCompanionRuntimeHost runtimeHost;
  final ValueChanged<FishCompanionPageStatus>? onPageStatusChanged;
  final FishCompanionPageReadinessOverride? pageReadinessOverride;

  @override
  State<FishCompanionView> createState() => _FishCompanionViewState();
}

class _FishCompanionViewState extends State<FishCompanionView>
    implements FishCompanionSurfaceLifecycle {
  WebviewController? _controller;
  WebviewController? _initializingController;
  StreamSubscription<dynamic>? _sourceLinkMessages;
  final _sourceLink = FishyStuffSourceLink();
  bool _sourceLinkFailureShown = false;
  Object? _error;
  FishCompanionPageStatus _pageStatus = FishCompanionPageStatus.starting;
  int _initializationGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.runtimeHost.attachSurface(this);
    if (_isFlutterTest) {
      unawaited(_initializeTestPageStatus());
    } else {
      unawaited(_initialize());
    }
  }

  @override
  void didUpdateWidget(covariant FishCompanionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.runtimeHost, widget.runtimeHost)) return;
    oldWidget.runtimeHost.detachSurface(this);
    widget.runtimeHost.attachSurface(this);
    unawaited(_restartForRuntimeHostChange());
  }

  Future<void> _restartForRuntimeHostChange() async {
    await _releaseWebViewSurface(updateState: true);
    if (!mounted) return;
    if (_isFlutterTest) {
      await _initializeTestPageStatus();
    } else {
      await _initialize();
    }
  }

  Future<void> _initialize() async {
    final generation = ++_initializationGeneration;
    _updatePageStatus(FishCompanionPageStatus.starting);
    final controller = WebviewController();
    _initializingController = controller;
    try {
      final runtime = await widget.runtimeHost.ready();
      await runtime.webViewDataRoot.create(recursive: true);
      await initializeFishCompanionWebViewEnvironment(
        () => WebviewController.initializeEnvironment(
          userDataPath: runtime.webViewDataRoot.absolute.path,
          additionalArguments:
              '--disk-cache-size=16777216 --media-cache-size=8388608',
        ),
      );
      await controller.initialize();
      await controller.setCacheDisabled(true);
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.allow);
      await controller.setDefaultContextMenusEnabled(true);
      await controller.setBackgroundColor(const Color(0xFF0A0E12));
      await controller.addScriptToExecuteOnDocumentCreated(
        fishyStuffSourceLinkScript,
      );
      await _sourceLinkMessages?.cancel();
      _sourceLinkMessages = controller.webMessage.listen(
        (message) => unawaited(_handleSourceLinkMessage(message)),
      );
      await _primeHeadlessSurfaceSize(controller);
      await controller.loadUrl(runtime.uri.toString());

      if (!mounted ||
          generation != _initializationGeneration ||
          !identical(_initializingController, controller)) {
        await controller.dispose();
        return;
      }
      setState(() {
        _initializingController = null;
        _controller = controller;
        _error = null;
      });
      final pageStatus = await _waitForPageTerminalStatus(controller);
      if (!mounted || generation != _initializationGeneration) return;
      _updatePageStatus(pageStatus);
    } catch (error) {
      await _sourceLinkMessages?.cancel();
      _sourceLinkMessages = null;
      final stillOwned =
          identical(_initializingController, controller) ||
          identical(_controller, controller);
      if (identical(_initializingController, controller)) {
        _initializingController = null;
      }
      if (identical(_controller, controller)) _controller = null;
      if (stillOwned) await controller.dispose();
      if (!mounted || generation != _initializationGeneration) return;
      setState(() {
        _error = error;
      });
      _updatePageStatus(FishCompanionPageStatus.failed);
    }
  }

  Future<void> _handleSourceLinkMessage(Object? message) async {
    final opened = await _sourceLink.handleMessage(message);
    if (opened != false || !mounted || _sourceLinkFailureShown) return;
    _sourceLinkFailureShown = true;
    final bool retry;
    try {
      retry =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Could not open FishyStuff'),
              content: const SelectableText(fishyStuffSourceUrl),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Close'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      _sourceLinkFailureShown = false;
    }
    if (retry && mounted) {
      await _handleSourceLinkMessage(fishyStuffSourceMessage);
    }
  }

  Future<void> _initializeTestPageStatus() async {
    final generation = ++_initializationGeneration;
    await WidgetsBinding.instance.endOfFrame;
    try {
      final pageStatus =
          await widget.pageReadinessOverride?.call() ??
          FishCompanionPageStatus.ready;
      if (!mounted || generation != _initializationGeneration) return;
      _updatePageStatus(pageStatus);
    } catch (error) {
      if (!mounted || generation != _initializationGeneration) return;
      setState(() => _error = error);
      _updatePageStatus(FishCompanionPageStatus.failed);
    }
  }

  Future<void> _primeHeadlessSurfaceSize(WebviewController controller) async {
    if (!mounted) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.hasSize ||
        renderObject.size.isEmpty) {
      return;
    }
    await controller.setSize(
      renderObject.size,
      scaleFactor: MediaQuery.devicePixelRatioOf(context),
    );
  }

  Future<FishCompanionPageStatus> _waitForPageTerminalStatus(
    WebviewController controller,
  ) {
    final override = widget.pageReadinessOverride;
    if (override != null) return override();
    final _FishCompanionScriptExecutor executor = controller.executeScript;
    return waitForFishCompanionPageTerminalStatus(executor);
  }

  void _updatePageStatus(FishCompanionPageStatus status) {
    if (_pageStatus == status) return;
    if (mounted) {
      setState(() => _pageStatus = status);
    } else {
      _pageStatus = status;
    }
    widget.onPageStatusChanged?.call(status);
  }

  Future<void> _retry() async {
    setState(() => _error = null);
    if (_isFlutterTest) {
      await _initializeTestPageStatus();
    } else {
      await _initialize();
    }
  }

  @override
  Future<void> freezeForLifecycle() =>
      _releaseWebViewSurface(updateState: true);

  @override
  Future<void> resumeAfterLifecycleFailure() async {
    if (!mounted || _controller != null || _initializingController != null) {
      return;
    }
    if (_isFlutterTest) {
      await _initializeTestPageStatus();
    } else {
      await _initialize();
    }
  }

  Future<void> _releaseWebViewSurface({required bool updateState}) async {
    _initializationGeneration += 1;
    await _sourceLinkMessages?.cancel();
    _sourceLinkMessages = null;
    final controllers = <WebviewController>{
      ?_initializingController,
      ?_controller,
    };
    _initializingController = null;
    _controller = null;
    if (updateState && mounted) {
      setState(() {
        _error = null;
        _pageStatus = FishCompanionPageStatus.starting;
      });
    }
    for (final controller in controllers) {
      try {
        await controller.stop().timeout(const Duration(seconds: 2));
      } on Object {
        // A controller still initializing or already closing needs no stop.
      }
      await controller.dispose();
    }
    await WebviewController.releaseFocus();
  }

  @override
  void dispose() {
    widget.runtimeHost.detachSurface(this);
    unawaited(_releaseWebViewSurface(updateState: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return FishCompanionPageSurface(
        pageStatus: _pageStatus,
        content: ColoredBox(
          color: const Color(0xFF0A0E12),
          child: Webview(controller, key: const Key('fish-companion-webview')),
        ),
      );
    }
    if (_error != null) {
      return _FishCompanionUnavailable(onRetry: _retry, error: _error!);
    }
    return const _FishCompanionStarting();
  }
}

/// The exact production layering used while the standalone Fish page starts.
///
/// This remains public only so widget tests can exercise the same loaded-page
/// branch without constructing a native WebView2 controller.
@visibleForTesting
class FishCompanionPageSurface extends StatelessWidget {
  const FishCompanionPageSurface({
    required this.pageStatus,
    required this.content,
    super.key,
  });

  final FishCompanionPageStatus pageStatus;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        content,
        if (pageStatus == FishCompanionPageStatus.starting)
          const Positioned.fill(
            child: AbsorbPointer(child: _FishCompanionStarting()),
          ),
      ],
    );
  }
}

class _FishCompanionStarting extends StatefulWidget {
  const _FishCompanionStarting();

  @override
  State<_FishCompanionStarting> createState() => _FishCompanionStartingState();
}

class _FishCompanionStartingState extends State<_FishCompanionStarting>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (!_isFlutterTest) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1500),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = _controller;
    if (controller == null) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      controller
        ..stop()
        ..value = 0.18;
    } else if (!controller.isAnimating) {
      controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation = _controller;
    return ColoredBox(
      color: const Color(0xFF0A0E12),
      child: Center(
        child: Semantics(
          key: const Key('fish-companion-loading-semantics'),
          excludeSemantics: true,
          container: true,
          liveRegion: true,
          label: 'Preparing Fish Map. Loading the current fishing tables.',
          child: RepaintBoundary(
            key: const Key('fish-companion-starting'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox.square(
                  dimension: 112,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      if (animation == null)
                        const CustomPaint(
                          size: Size.square(108),
                          painter: _FishLoadingOrbitPainter(0.18),
                        )
                      else
                        AnimatedBuilder(
                          animation: animation,
                          builder: (context, child) => CustomPaint(
                            size: const Size.square(108),
                            painter: _FishLoadingOrbitPainter(animation.value),
                          ),
                        ),
                      Container(
                        width: 78,
                        height: 78,
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: const Color(
                              0xFF6CB7C8,
                            ).withValues(alpha: 0.7),
                          ),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: <Color>[
                              Color(0xFF17232B),
                              Color(0xFF0B1218),
                            ],
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: const Color(
                                0xFF6CB7C8,
                              ).withValues(alpha: 0.2),
                              blurRadius: 20,
                              spreadRadius: 1,
                            ),
                            const BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 14,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/fish_companion/data/cache/icons-4x/00008479.webp',
                          key: const Key('fish-companion-loading-game-icon'),
                          package: 'bdo_fishing_core',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Preparing Fish Map',
                  style: TextStyle(
                    color: Color(0xFFF2F5F7),
                    fontSize: 18,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Loading the current fishing tables…',
                  style: TextStyle(
                    color: Color(0xFFA7B6BF),
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FishLoadingOrbitPainter extends CustomPainter {
  const _FishLoadingOrbitPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(
      center: center,
      radius: size.shortestSide / 2 - 4,
    );
    final rotation = progress * math.pi * 2;
    final primary = Paint()
      ..color = const Color(0xFF78CAD8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final secondary = Paint()
      ..color = const Color(0xFF8C4860).withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final guide = Paint()
      ..color = const Color(0xFF6CB7C8).withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawArc(rect, 0, math.pi * 2, false, guide);
    canvas.drawArc(rect, rotation - 0.35, math.pi * 0.72, false, primary);
    canvas.drawArc(
      rect.deflate(6),
      -rotation - 0.15,
      math.pi * 0.46,
      false,
      secondary,
    );

    final dotAngle = rotation + math.pi * 0.37;
    final dotRadius = rect.width / 2;
    final dotCenter = Offset(
      center.dx + math.cos(dotAngle) * dotRadius,
      center.dy + math.sin(dotAngle) * dotRadius,
    );
    canvas.drawCircle(dotCenter, 3, Paint()..color = const Color(0xFFB8EDF3));
  }

  @override
  bool shouldRepaint(_FishLoadingOrbitPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _FishCompanionUnavailable extends StatelessWidget {
  const _FishCompanionUnavailable({required this.onRetry, required this.error});

  final Future<void> Function() onRetry;
  final Object error;

  @override
  Widget build(BuildContext context) {
    final isWebViewRuntimeMissing =
        error is PlatformException &&
        (error as PlatformException).code == 'environment_creation_failed';
    return ColoredBox(
      color: const Color(0xFF0A0E12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.phishing_rounded,
                  color: Color(0xFF6CB7C8),
                  size: 38,
                ),
                const SizedBox(height: 14),
                Text(
                  isWebViewRuntimeMissing
                      ? 'Microsoft Edge WebView2 is required to open Fish Map.'
                      : 'Fish Map could not start.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFF2F5F7),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6CB7C8),
                    foregroundColor: const Color(0xFF071116),
                  ),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
