import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../services/native_bridge.dart';

/// The app's own Win32 manifest/process identity, also used by the local page.
/// This is not a claimed public website or a replacement YouTube identity.
const spotVideoAppHost = 'blackspiritlife.bdogatheringcompanion';

Directory? _spotVideoCacheRoot;
final Set<_SpotVideoPlayerState> _spotVideoPlayers = <_SpotVideoPlayerState>{};

/// Keeps every Gathering WebView2 profile beneath the user-selected data root.
void configureSpotVideoCacheRoot(Directory root) {
  _spotVideoCacheRoot = root.absolute;
}

/// Optional startup housekeeping. No browser, network, or profile is created.
/// Only stale video folders under this app's own identity are considered.
Future<void> cleanupSpotVideoCache() async {
  if (!Platform.isWindows) return;
  final root = _spotVideoCacheRoot;
  if (root == null) return;
  try {
    if (await FileSystemEntity.type(root.path, followLinks: false) ==
        FileSystemEntityType.directory) {
      await _WindowsVideoSession._serialize(
        () => _WindowsVideoSession._cleanStaleProfiles(root),
      );
    }
  } catch (_) {
    // Locked remnants are retried at the next opening. Never touch sessions.
  }
}

/// Releases every active Gathering video before an update, close, or data move.
Future<void> pauseSpotVideoResources() async {
  await Future.wait(<Future<void>>[
    for (final player in _spotVideoPlayers.toList())
      player.pauseForMaintenance(),
  ]);
}

/// Restores paused inline previews when a guarded outer operation is cancelled.
void resumeSpotVideoResources() {
  for (final player in _spotVideoPlayers.toList()) {
    player.resumeAfterMaintenance();
  }
}

class YouTubeVideo {
  final String id;
  final int startSeconds;

  const YouTubeVideo(this.id, {this.startSeconds = 0});

  static YouTubeVideo? parse(String input) {
    final uri = Uri.tryParse(input);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return null;
    }
    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments;
    String? id;
    if (host == 'youtu.be' && segments.length == 1) {
      id = segments.first;
    } else if (const {
      'youtube.com',
      'www.youtube.com',
      'm.youtube.com',
      'www.youtube-nocookie.com',
      'youtube-nocookie.com',
    }.contains(host)) {
      if (uri.path == '/watch') {
        id = uri.queryParameters['v'];
      } else if (segments.length == 2 &&
          const {'embed', 'shorts', 'live'}.contains(segments.first)) {
        id = segments.last;
      }
    }
    if (id == null || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
      return null;
    }
    final time = uri.queryParameters['t'] ?? uri.queryParameters['start'] ?? '';
    var seconds = int.tryParse(time.replaceFirst(RegExp(r's$'), '')) ?? 0;
    final units = RegExp(
      r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$',
    ).firstMatch(time);
    if (units != null && time.isNotEmpty) {
      seconds =
          (int.tryParse(units.group(1) ?? '') ?? 0) * 3600 +
          (int.tryParse(units.group(2) ?? '') ?? 0) * 60 +
          (int.tryParse(units.group(3) ?? '') ?? 0);
    }
    return YouTubeVideo(id, startSeconds: seconds.clamp(0, 86400));
  }

  String get watchUrl => Uri.https('www.youtube.com', '/watch', {
    'v': id,
    if (startSeconds > 0) 't': '${startSeconds}s',
  }).toString();
}

enum SpotVideoEventKind { ready, failure, autoplayBlocked }

class SpotVideoEvent {
  final SpotVideoEventKind kind;
  final String? message;
  const SpotVideoEvent(this.kind, [this.message]);
}

/// A narrow seam for testing lifecycle without launching a real browser.
abstract class SpotVideoSession {
  Stream<SpotVideoEvent> get events;
  Future<void> open(YouTubeVideo video);
  Future<void> play();
  Widget buildView();
  Future<void> dispose();
}

/// By default no browser/network/profile is created until Play. [loadOnOpen]
/// opts into loading a visible, paused inline player; it never starts playback.
/// [startOnOpen] is reserved for an explicit Watch-video action. Dispose on close.
class SpotVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String title;
  final bool startOnOpen;
  final bool loadOnOpen;
  final bool showTitle;
  @visibleForTesting
  final SpotVideoSession Function()? sessionFactory;

  const SpotVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.title,
    this.startOnOpen = false,
    this.loadOnOpen = false,
    this.showTitle = true,
    this.sessionFactory,
  });

  @override
  State<SpotVideoPlayer> createState() => _SpotVideoPlayerState();
}

class _SpotVideoPlayerState extends State<SpotVideoPlayer>
    with WidgetsBindingObserver {
  final _viewportKey = GlobalKey();
  SpotVideoSession? _session;
  StreamSubscription<SpotVideoEvent>? _events;
  Timer? _readyTimeout;
  Timer? _visibilityTimer;
  Timer? _loadWhenVisibleTimer;
  bool _opening = false;
  bool _ready = false;
  bool _playRequested = false;
  bool _allowScriptedPlayback = false;
  bool _appVisible = true;
  String? _message;
  int _generation = 0;
  int _loadScheduleGeneration = 0;

  YouTubeVideo? get _video => YouTubeVideo.parse(widget.videoUrl);

  @override
  void initState() {
    super.initState();
    _spotVideoPlayers.add(this);
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appVisible =
        lifecycle != AppLifecycleState.hidden &&
        lifecycle != AppLifecycleState.paused &&
        lifecycle != AppLifecycleState.detached;
    if (widget.startOnOpen || widget.loadOnOpen) {
      _scheduleInitialLoad(startPlayback: widget.startOnOpen);
    }
  }

  @override
  void didUpdateWidget(covariant SpotVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _stop();
      _message = null;
      if (widget.loadOnOpen) _scheduleInitialLoad(startPlayback: false);
    } else if (widget.loadOnOpen != oldWidget.loadOnOpen && _session == null) {
      _cancelScheduledLoad();
      if (widget.loadOnOpen) _scheduleInitialLoad(startPlayback: false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled && _session != null) {
      _stop(
        message: 'Playback stopped while the video was hidden.',
        reloadWhenVisible: true,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible =
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached;
    if (!_appVisible && _session != null) {
      _stop(
        message: 'Playback stopped while the video was hidden.',
        reloadWhenVisible: true,
      );
    }
  }

  bool _viewportVisible() {
    if (!mounted || !_appVisible || !TickerMode.valuesOf(context).enabled) {
      return false;
    }
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final render = _viewportKey.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.attached || !render.hasSize) {
      return false;
    }
    if (render.size.width < 200 || render.size.height < 200) return false;
    final rect = render.localToGlobal(Offset.zero) & render.size;
    var visible = rect.intersect(Offset.zero & MediaQuery.sizeOf(context));
    final scrollViewport = _viewportKey.currentContext
        ?.findAncestorRenderObjectOfType<RenderAbstractViewport>();
    final viewportBox = scrollViewport is RenderBox
        ? scrollViewport as RenderBox
        : null;
    if (viewportBox != null && viewportBox.hasSize) {
      visible = visible.intersect(
        viewportBox.localToGlobal(Offset.zero) & viewportBox.size,
      );
    }
    return !visible.isEmpty &&
        visible.width * visible.height >= rect.width * rect.height / 2;
  }

  void _scheduleInitialLoad({required bool startPlayback}) {
    _cancelScheduledLoad();
    final schedule = _loadScheduleGeneration;
    void tryLoad() {
      if (!mounted ||
          schedule != _loadScheduleGeneration ||
          !_viewportVisible()) {
        return;
      }
      _loadWhenVisibleTimer?.cancel();
      unawaited(_load(startPlayback: startPlayback));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tryLoad());
    // A newly built inline player may initially be outside the scroll viewport.
    // Wait without allocating a browser; loading only happens once it is visible.
    _loadWhenVisibleTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => tryLoad(),
    );
  }

  void _cancelScheduledLoad() {
    _loadScheduleGeneration++;
    _loadWhenVisibleTimer?.cancel();
  }

  Future<void> _play() => _load(startPlayback: true);

  Future<void> _load({required bool startPlayback}) async {
    final video = _video;
    if (_opening || _session != null || video == null || !_viewportVisible()) {
      return;
    }
    _cancelScheduledLoad();
    final generation = ++_generation;
    final session = widget.sessionFactory?.call() ?? _WindowsVideoSession();
    setState(() {
      _session = session;
      _opening = true;
      _ready = false;
      _playRequested = false;
      _allowScriptedPlayback = startPlayback;
      _message = null;
    });
    _events = session.events.listen((event) {
      if (!mounted || generation != _generation) return;
      switch (event.kind) {
        case SpotVideoEventKind.ready:
          _readyTimeout?.cancel();
          setState(() {
            _ready = true;
            _message = null;
          });
          _playWhenVisible(generation);
        case SpotVideoEventKind.failure:
          _stop(
            message: event.message ?? 'This video could not be played here.',
          );
        case SpotVideoEventKind.autoplayBlocked:
          setState(() => _message = 'Press Play in the YouTube player.');
      }
    });
    _readyTimeout = Timer(const Duration(seconds: 35), () {
      if (mounted && generation == _generation && !_ready) {
        _stop(
          message:
              'YouTube did not respond. Check your connection or open it on YouTube.',
        );
      }
    });
    _visibilityTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_viewportVisible()) {
        _stop(
          message: 'Playback stopped while the video was hidden.',
          reloadWhenVisible: true,
        );
      }
    });
    try {
      await session.open(video);
      if (mounted && generation == _generation) {
        setState(() => _opening = false);
        _playWhenVisible(generation);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        _stop(
          message: error is _VideoFailure
              ? error.message
              : 'The video player could not start. You can still open this video on YouTube.',
        );
      }
    }
  }

  void _playWhenVisible(int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          generation != _generation ||
          _opening ||
          !_ready ||
          !_allowScriptedPlayback ||
          _playRequested ||
          !_viewportVisible()) {
        return;
      }
      _playRequested = true;
      try {
        await _session?.play();
      } catch (_) {
        if (mounted && generation == _generation) {
          _stop(
            message: 'Playback could not start. Open this video on YouTube.',
          );
        }
      }
    });
  }

  void _stop({
    String? message,
    bool notify = true,
    bool reloadWhenVisible = false,
  }) {
    _generation++;
    _readyTimeout?.cancel();
    _visibilityTimer?.cancel();
    _cancelScheduledLoad();
    unawaited(_events?.cancel());
    final session = _session;
    _session = null;
    _events = null;
    _opening = false;
    _ready = false;
    _message = message;
    if (session != null) {
      unawaited(
        session.dispose().catchError((Object _) {
          // Closing playback must not crash the app if Windows is still holding
          // a browser file. Startup/next-open housekeeping retries stale folders.
        }),
      );
    }
    if (reloadWhenVisible && mounted && widget.loadOnOpen) {
      // A hidden inline preview returns paused without adding a status row that
      // could shrink a compact 200px viewport below its minimum loading size.
      _message = null;
      _scheduleInitialLoad(startPlayback: false);
    }
    if (notify && mounted) setState(() {});
  }

  Future<void> pauseForMaintenance() async {
    _generation++;
    _readyTimeout?.cancel();
    _visibilityTimer?.cancel();
    _cancelScheduledLoad();
    final events = _events;
    _events = null;
    await events?.cancel();
    final session = _session;
    _session = null;
    _opening = false;
    _ready = false;
    _message = 'Playback paused while personal data is synchronized.';
    if (session != null) await session.dispose();
    if (mounted) setState(() {});
  }

  void resumeAfterMaintenance() {
    if (!mounted || _session != null) return;
    _message = null;
    if (widget.loadOnOpen) _scheduleInitialLoad(startPlayback: false);
    setState(() {});
  }

  Future<void> _openOnYouTube() async {
    final video = _video;
    if (video == null) return;
    try {
      if (await NativeBridge.openExternal(video.watchUrl)) return;
    } catch (_) {
      // Keep failures visible; never execute arbitrary schemes or commands.
    }
    if (mounted) {
      setState(
        () => _message = 'Your browser could not open this YouTube link.',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _spotVideoPlayers.remove(this);
    _stop(notify: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    final compact = !widget.showTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTitle)
          Text(
            widget.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        if (widget.showTitle) const SizedBox(height: 10),
        Expanded(
          child: KeyedSubtree(
            key: const ValueKey('spot-video-viewport'),
            child: ColoredBox(
              key: _viewportKey,
              color: Colors.black,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 200 ||
                      constraints.maxHeight < 200) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Enlarge the window to play this video.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  if (video == null) {
                    return const Center(
                      child: Text(
                        'This is not a supported YouTube video link.',
                      ),
                    );
                  }
                  if (_session != null && !_opening) {
                    return _session!.buildView();
                  }
                  if (_opening) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (compact && _message != null) ...[
                            Flexible(
                              child: SingleChildScrollView(
                                primary: false,
                                child: Text(
                                  _message!,
                                  key: const ValueKey('spot-video-message'),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          FilledButton.icon(
                            key: const ValueKey('play-spot-video'),
                            onPressed: _play,
                            icon: const Icon(Icons.play_arrow),
                            label: Text(
                              compact && _message != null
                                  ? 'Try again'
                                  : 'Play video',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (!compact && _message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_message!, key: const ValueKey('spot-video-message')),
          ),
        const SizedBox(height: 6),
        if (compact)
          SizedBox(
            key: const ValueKey('spot-video-footer'),
            height: 40,
            child: Row(
              children: [
                if (_session != null)
                  IconButton(
                    key: const ValueKey('stop-spot-video'),
                    tooltip: 'Stop video',
                    onPressed: _stop,
                    icon: const Icon(Icons.stop, size: 20),
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                  ),
                if (_session != null && _message != null) ...[
                  Expanded(
                    child: Text(
                      _message!,
                      key: const ValueKey('spot-video-message'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('open-spot-video-youtube'),
                    tooltip: 'Open on YouTube',
                    onPressed: video == null ? null : _openOnYouTube,
                    icon: const Icon(Icons.open_in_new, size: 18),
                  ),
                ] else
                  Expanded(
                    child: TextButton.icon(
                      key: const ValueKey('open-spot-video-youtube'),
                      onPressed: video == null ? null : _openOnYouTube,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text(
                        'Open on YouTube',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          )
        else
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_session != null)
                TextButton.icon(
                  onPressed: _stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              TextButton.icon(
                key: const ValueKey('open-spot-video-youtube'),
                onPressed: video == null ? null : _openOnYouTube,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open on YouTube'),
              ),
            ],
          ),
      ],
    );
  }
}

class _VideoFailure implements Exception {
  final String message;
  const _VideoFailure(this.message);
}

@visibleForTesting
enum SpotVideoEnvironmentOwnership {
  isolated,
  shared;

  bool get clearsBrowserDataOnClose => this == isolated;
}

@visibleForTesting
bool canReuseExistingSpotVideoEnvironment(Object error) =>
    error is PlatformException &&
    error.code == 'environment_already_initialized';

@visibleForTesting
Future<SpotVideoEnvironmentOwnership> initializeSpotVideoEnvironment(
  Future<void> Function() initializeIsolatedEnvironment,
) async {
  try {
    await initializeIsolatedEnvironment();
    return SpotVideoEnvironmentOwnership.isolated;
  } on PlatformException catch (error) {
    if (!canReuseExistingSpotVideoEnvironment(error)) rethrow;
    return SpotVideoEnvironmentOwnership.shared;
  }
}

/// The browser can cache its own streamed media temporarily. This directory
/// never contains imported images, session JSON, paths, or a user's browser data.
class _WindowsVideoSession implements SpotVideoSession {
  static Future<void> _queue = Future.value();
  static _WindowsVideoSession? _active;
  static const _profileLimit = 128 * 1024 * 1024;
  final _events = StreamController<SpotVideoEvent>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  WebviewController? _controller;
  Directory? _directory;
  RandomAccessFile? _profileLock;
  Timer? _cacheMonitor;
  SpotVideoEnvironmentOwnership _environmentOwnership =
      SpotVideoEnvironmentOwnership.isolated;
  bool _disposed = false;
  bool _measuring = false;
  Future<void>? _closing;

  @override
  Stream<SpotVideoEvent> get events => _events.stream;

  static Future<void> _serialize(Future<void> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.catchError((Object _) {});
    return result;
  }

  @override
  Future<void> open(YouTubeVideo video) => _serialize(() async {
    if (_disposed) return;
    if (!Platform.isWindows) {
      throw const _VideoFailure(
        'Embedded playback is available on Windows. Open this video on YouTube.',
      );
    }
    if (await WebviewController.getWebViewVersion() == null) {
      throw const _VideoFailure(
        'The shared Microsoft Edge WebView2 Runtime is missing. Open this video on YouTube instead.',
      );
    }
    if (_active != null && _active != this) {
      _active!._emit(
        const SpotVideoEvent(
          SpotVideoEventKind.failure,
          'Playback stopped because another video was opened.',
        ),
      );
      await _active!._closeNative();
    }
    _active = this;
    try {
      final root = _spotVideoCacheRoot;
      if (root == null) {
        throw const _VideoFailure(
          'The selected personal-data folder is unavailable for video playback.',
        );
      }
      await root.create(recursive: true);
      if (await FileSystemEntity.type(root.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const _VideoFailure('The temporary video folder is unavailable.');
      }
      await _cleanStaleProfiles(root);
      if (_disposed) return;
      _directory = await root.createTemp('profile-');
      _profileLock = await File(
        '${_directory!.path}/active.lock',
      ).open(mode: FileMode.write);
      await _profileLock!.lock(FileLock.exclusive);
      final page = await Directory('${_directory!.path}/page').create();
      await File(
        '${page.path}/player.html',
      ).writeAsString(spotVideoHtml(video));
      _environmentOwnership = await initializeSpotVideoEnvironment(
        () => WebviewController.initializeEnvironment(
          userDataPath: '${_directory!.path}/browser',
          additionalArguments:
              '--disk-cache-size=16777216 --media-cache-size=8388608',
        ),
      );
      if (_disposed) return;
      final controller = _controller = WebviewController();
      await controller.initialize();
      if (_disposed) return;
      _subscriptions.add(controller.webMessage.listen(_onWebMessage));
      _subscriptions.add(
        controller.onLoadError.listen(
          (_) => _emit(
            const SpotVideoEvent(
              SpotVideoEventKind.failure,
              'YouTube could not load. Check your connection or open it on YouTube.',
            ),
          ),
        ),
      );
      _subscriptions.add(
        controller.url.listen((url) {
          if (url != 'https://$spotVideoAppHost/player.html' &&
              url != 'about:blank') {
            _emit(
              const SpotVideoEvent(
                SpotVideoEventKind.failure,
                'Continue this video on YouTube using the link below.',
              ),
            );
          }
        }),
      );
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await controller.setDefaultContextMenusEnabled(false);
      await controller.setCacheDisabled(true);
      await controller.addVirtualHostNameMapping(
        spotVideoAppHost,
        page.path,
        WebviewHostResourceAccessKind.deny,
      );
      await controller.loadUrl('https://$spotVideoAppHost/player.html');
      _cacheMonitor = Timer.periodic(
        const Duration(seconds: 10),
        (_) => unawaited(_checkCache()),
      );
    } catch (_) {
      await _closeNative();
      rethrow;
    } finally {
      if (_disposed) await _closeNative();
    }
  });

  void _emit(SpotVideoEvent event) {
    if (!_disposed && !_events.isClosed) _events.add(event);
  }

  void _onWebMessage(dynamic message) {
    if (message is! Map || message['source'] != 'bdo-video') return;
    switch (message['kind']) {
      case 'ready':
        _emit(const SpotVideoEvent(SpotVideoEventKind.ready));
      case 'blocked':
        _emit(const SpotVideoEvent(SpotVideoEventKind.autoplayBlocked));
      case 'error':
        _emit(
          SpotVideoEvent(
            SpotVideoEventKind.failure,
            spotVideoErrorMessage(
              message['code'] is int ? message['code'] as int : null,
            ),
          ),
        );
    }
  }

  Future<void> _checkCache() async {
    final directory = _directory;
    if (_disposed || _measuring || directory == null) return;
    _measuring = true;
    try {
      var bytes = 0;
      await for (final entry in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is File) bytes += await entry.length();
        if (bytes > _profileLimit) {
          _emit(
            const SpotVideoEvent(
              SpotVideoEventKind.failure,
              'Playback stopped to clear temporary video storage. You can play it again.',
            ),
          );
          return;
        }
      }
    } on FileSystemException {
      // Browser cache files can disappear during this approximate guard.
    } finally {
      _measuring = false;
    }
  }

  @override
  Widget buildView() => Webview(
    _controller!,
    key: const ValueKey('spot-video-webview'),
    permissionRequested: (_, _, _) => WebviewPermissionDecision.deny,
  );

  @override
  Future<void> play() async {
    if (!_disposed) {
      await _controller?.executeScript(
        'if(window.player && player.playVideo) player.playVideo();',
      );
    }
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    return _closing ??= _serialize(() async {
      await _closeNative();
      await _events.close();
    });
  }

  Future<void> _closeNative() async {
    _cacheMonitor?.cancel();
    final environmentOwnership = _environmentOwnership;
    _environmentOwnership = SpotVideoEnvironmentOwnership.isolated;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      for (final operation in <Future<void> Function()>[
        controller.stop,
        () => controller.loadUrl('about:blank'),
        if (environmentOwnership.clearsBrowserDataOnClose) ...[
          controller.clearCache,
          controller.clearCookies,
        ],
      ]) {
        try {
          await operation().timeout(const Duration(seconds: 2));
        } catch (_) {
          /* best effort */
        }
      }
      await controller.dispose();
      await WebviewController.releaseFocus();
    }
    if (_active == this) _active = null;
    await _profileLock?.close();
    _profileLock = null;
    final directory = _directory;
    _directory = null;
    if (directory != null) {
      for (var attempt = 0; attempt < 4; attempt++) {
        try {
          if (await directory.exists()) await directory.delete(recursive: true);
          break;
        } on FileSystemException {
          // WebView2 processes release their files asynchronously. Any locked
          // remnants are retried on the next explicit video opening.
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (attempt + 1)),
          );
        }
      }
    }
  }

  static Future<void> _cleanStaleProfiles(Directory root) async {
    final rootPath = root.absolute.path;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory ||
          !entity.absolute.path.startsWith(
            '$rootPath${Platform.pathSeparator}profile-',
          )) {
        continue;
      }
      RandomAccessFile? lock;
      try {
        final lockFile = File('${entity.path}/active.lock');
        if (await lockFile.exists()) {
          lock = await lockFile.open(mode: FileMode.append);
          await lock.lock(FileLock.exclusive);
          await lock.close();
          lock = null;
        }
        await entity.delete(recursive: true);
      } on FileSystemException {
        // An active player in another independent process is never removed.
      } finally {
        await lock?.close();
      }
    }
  }
}

@visibleForTesting
String spotVideoErrorMessage(int? code) => switch (code) {
  101 || 150 =>
    'The creator does not allow this video to play inside other apps. Open it on YouTube.',
  100 =>
    'This video is private, removed, or unavailable. Try opening it on YouTube.',
  153 =>
    'YouTube could not verify this app for embedded playback. Open the video on YouTube.',
  5 => 'This video could not play in the Windows player. Open it on YouTube.',
  _ => 'This video could not be played here. Try opening it on YouTube.',
};

/// Only an app-authored HTML wrapper is written. The virtual HTTPS origin gives
/// YouTube a real browser-generated Referer instead of about:blank/null origin.
/// No controls, branding, ads, or creator restrictions are modified or covered.
@visibleForTesting
String spotVideoHtml(YouTubeVideo video) =>
    '''<!doctype html>
<html><head><meta charset="utf-8">
<meta name="referrer" content="strict-origin-when-cross-origin">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' https://www.youtube.com https://s.ytimg.com; frame-src https://www.youtube.com https://www.youtube-nocookie.com; style-src 'unsafe-inline'; connect-src https://www.youtube.com">
<style>html,body,#player{width:100%;height:100%;margin:0;background:#000;overflow:hidden}</style>
</head><body><div id="player"></div><script>
function send(kind,code){window.chrome.webview.postMessage({source:'bdo-video',kind:kind,code:code});}
var player;
function onYouTubeIframeAPIReady(){
  player=new YT.Player('player',{
    host:'https://www.youtube-nocookie.com',
    videoId:${jsonEncode(video.id)},width:'100%',height:'100%',
    playerVars:{autoplay:0,controls:1,playsinline:1,origin:'https://$spotVideoAppHost',start:${video.startSeconds}},
    events:{onReady:function(){send('ready');},onError:function(e){send('error',e.data);},onAutoplayBlocked:function(){send('blocked');}}
  });
}
document.addEventListener('visibilitychange',function(){if(document.hidden&&player&&player.pauseVideo)player.pauseVideo();});
</script><script src="https://www.youtube.com/iframe_api" onerror="send('error')"></script></body></html>''';
