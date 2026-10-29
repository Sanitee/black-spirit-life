import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/native_bridge.dart';
import 'theme.dart';

class PasteReferenceIntent extends Intent {
  const PasteReferenceIntent();
}

class ReferenceWindow extends StatefulWidget {
  const ReferenceWindow({super.key});
  @override
  State<ReferenceWindow> createState() => _ReferenceWindowState();
}

class _ReferenceWindowState extends State<ReferenceWindow> {
  Uint8List? _bytes;
  bool _pinned = true, _busy = false;
  String? _error;
  bool _pinError = false;
  final _transform = TransformationController();
  @override
  void initState() {
    super.initState();
    _setPinned(true, initial: true);
  }

  @override
  void dispose() {
    if (_bytes != null) MemoryImage(_bytes!).evict();
    _transform.dispose();
    super.dispose();
  }

  String _failureDetails(Object error) => switch (error) {
    PlatformException(:final message?) => message,
    FormatException(:final message) => message,
    _ => error.toString(),
  };

  void _showError(String message, {bool pin = false}) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _pinError = pin;
    });
  }

  Future<void> _setPinned(bool next, {bool initial = false}) async {
    try {
      final changed = await NativeBridge.setAlwaysOnTop(next);
      if (!mounted) return;
      if (!changed) {
        if (initial) setState(() => _pinned = false);
        _showError('Could not change always on top. Try again.', pin: true);
        return;
      }
      setState(() {
        _pinned = next;
        if (_pinError) _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      if (initial) setState(() => _pinned = false);
      _showError(
        'Could not change always on top: ${_failureDetails(error)}',
        pin: true,
      );
    }
  }

  Future<void> _paste() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await NativeBridge.readClipboardImage();
      if (!mounted) return;
      if (bytes == null) {
        _showError('Copy a screenshot first, then press Ctrl+V here.');
        return;
      }
      if (bytes.length > 16 * 1024 * 1024) {
        throw const FormatException('Choose an image smaller than 16 MB.');
      }
      if (_bytes != null) await MemoryImage(_bytes!).evict();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _transform.value = Matrix4.identity();
        if (!_pinError) _error = null;
      });
    } catch (e) {
      _showError('Could not open image: ${_failureDetails(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.keyV, control: true):
          PasteReferenceIntent(),
    },
    child: Actions(
      actions: {
        PasteReferenceIntent: CallbackAction<PasteReferenceIntent>(
          onInvoke: (_) {
            _paste();
            return null;
          },
        ),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GatheringQuietIconButton(
                      onPressed: () => _setPinned(!_pinned),
                      tooltip: _pinned
                          ? 'Turn always on top off'
                          : 'Keep on top',
                      icon: Icon(
                        _pinned ? Icons.push_pin : Icons.push_pin_outlined,
                        color: _pinned
                            ? context.gatheringColors.accent
                            : context.gatheringColors.muted,
                        size: 18,
                      ),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(40, 40),
                        maximumSize: const Size(40, 40),
                        padding: const EdgeInsets.all(10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    GatheringQuietIconButton(
                      onPressed: _bytes == null
                          ? null
                          : () => setState(
                              () => _transform.value = Matrix4.identity(),
                            ),
                      tooltip: 'Fit picture',
                      icon: const Icon(Icons.fit_screen, size: 18),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(40, 40),
                        maximumSize: const Size(40, 40),
                        padding: const EdgeInsets.all(10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
              if (_error case final message?)
                Semantics(
                  liveRegion: true,
                  child: Container(
                    key: const ValueKey('reference-error'),
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha: .08),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.error.withValues(alpha: .45),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Icon(
                            Icons.error_outline,
                            size: 18,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Tooltip(
                            message: message,
                            child: Text(
                              message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, height: 1.3),
                            ),
                          ),
                        ),
                        GatheringQuietIconButton(
                          key: const ValueKey('dismiss-reference-error'),
                          onPressed: () => setState(() => _error = null),
                          tooltip: 'Dismiss error',
                          icon: const Icon(Icons.close, size: 17),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(30, 30),
                            maximumSize: const Size(30, 30),
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                key: const ValueKey('reference-image-area'),
                child: _bytes == null
                    ? const SizedBox.expand()
                    : ColoredBox(
                        color: context.gatheringColors.inset,
                        child: InteractiveViewer(
                          transformationController: _transform,
                          minScale: .3,
                          maxScale: 8,
                          boundaryMargin: const EdgeInsets.all(100),
                          child: Center(
                            child: Image.memory(
                              _bytes!,
                              fit: BoxFit.contain,
                              gaplessPlayback: false,
                              errorBuilder: (_, e, s) => const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'This image could not be decoded. Try PNG or JPEG.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: TextButton.icon(
                  key: const ValueKey('reference-paste'),
                  onPressed: _busy ? null : _paste,
                  icon: const Icon(Icons.content_paste, size: 16),
                  label: Text(
                    _busy ? 'Opening…' : 'Paste screenshot · Ctrl+V',
                    style: const TextStyle(fontSize: 14),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: context.gatheringColors.muted,
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
