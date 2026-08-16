import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../import/active_node_list_import.dart';
import '../model/resource_map_data.dart';
import 'draggable_dialog_surface.dart';
import 'resource_map_chrome_theme.dart';

typedef BdoActiveNodeRecordingLauncher = Future<bool> Function();
typedef BdoActiveNodeRecordingFinder =
    Future<String?> Function(DateTime? modifiedAfter);
typedef BdoActiveNodeRecordingPicker = Future<String?> Function();

@immutable
class BdoActiveNodeScanProgress {
  const BdoActiveNodeScanProgress({
    required this.fraction,
    required this.completedFrames,
    required this.estimatedFrames,
  });

  final double fraction;
  final int completedFrames;
  final int estimatedFrames;
}

typedef BdoActiveNodeRecordingScanner =
    Future<BdoActiveNodeVideoOcrResult> Function(
      String path, {
      ValueChanged<BdoActiveNodeScanProgress>? onProgress,
    });

/// Reads BDO's narrow Production Node Status > Activated list from one or
/// more scrolling MP4 clips. The result is additive and is not applied until
/// the player confirms this review.
class BdoActiveNodeRecordingImportDialog extends StatefulWidget {
  const BdoActiveNodeRecordingImportDialog({
    required this.dataset,
    required this.existingNodeIds,
    required this.pickRecording,
    required this.scanRecording,
    this.launchRecording,
    this.findLatestRecording,
    super.key,
  });

  final BdoResourceMapDataset dataset;
  final Set<String> existingNodeIds;
  final BdoActiveNodeRecordingPicker pickRecording;
  final BdoActiveNodeRecordingScanner scanRecording;
  final BdoActiveNodeRecordingLauncher? launchRecording;
  final BdoActiveNodeRecordingFinder? findLatestRecording;

  @override
  State<BdoActiveNodeRecordingImportDialog> createState() =>
      _BdoActiveNodeRecordingImportDialogState();
}

class _BdoActiveNodeRecordingImportDialogState
    extends State<BdoActiveNodeRecordingImportDialog> {
  final List<BdoActiveNodeVideoOcrResult> _scans =
      <BdoActiveNodeVideoOcrResult>[];
  final Map<String, Set<String>> _selectedNodeIdsByMatch =
      <String, Set<String>>{};
  final Set<String> _explicitlyUnchecked = <String>{};
  BdoActiveNodeListImportResult? _result;
  DateTime? _recordingStartedAt;
  bool _busy = false;
  bool _showDiagnostics = false;
  BdoActiveNodeScanProgress? _analysisProgress;
  String? _status;
  String? _error;

  Iterable<BdoWorkerNode> get _productionNodes => widget.dataset.workerNodes
      .where((node) => node.isResourceNode && node.isProductionNode);

  Set<String> get _selectedNodeIds => Set<String>.unmodifiable(
    _selectedNodeIdsByMatch.values.expand((nodeIds) => nodeIds),
  );

  int get _newSelectionCount =>
      _selectedNodeIds.difference(widget.existingNodeIds).length;

  String _keyFor(BdoActiveNodeImportMatch match) =>
      '${match.canonicalName ?? match.observedText}\u0000'
      '${match.canonicalActivity ?? ''}';

  Future<void> _startRectangleRecording() async {
    final launcher = widget.launchRecording;
    if (launcher == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final started = await launcher();
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (started) {
          _recordingStartedAt = DateTime.now().subtract(
            const Duration(seconds: 2),
          );
          _status =
              'Record only the narrow Activated list, scroll steadily to the '
              'bottom, then stop the recording and return here.';
        } else {
          _error =
              'Snipping Tool could not be opened. Use Choose MP4 after '
              'recording with Win + Shift + R.';
        }
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _readableError(error);
      });
    }
  }

  Future<void> _findLatest() async {
    final finder = widget.findLatestRecording;
    if (finder == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = await finder(_recordingStartedAt);
      if (!mounted) return;
      if (path == null) {
        setState(() {
          _busy = false;
          _error =
              'No new Snipping Tool MP4 was found. Stop the recording first, '
              'or choose the saved MP4 yourself.';
        });
        return;
      }
      await _scanPath(path, busyAlreadySet: true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _readableError(error);
      });
    }
  }

  Future<void> _chooseRecording() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = await widget.pickRecording();
      if (!mounted) return;
      if (path == null) {
        setState(() => _busy = false);
        return;
      }
      await _scanPath(path, busyAlreadySet: true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _readableError(error);
      });
    }
  }

  Future<void> _scanPath(String path, {required bool busyAlreadySet}) async {
    if (mounted) {
      setState(() {
        if (!busyAlreadySet) _busy = true;
        _analysisProgress = const BdoActiveNodeScanProgress(
          fraction: .01,
          completedFrames: 0,
          estimatedFrames: 0,
        );
      });
    }
    try {
      final scan = await widget.scanRecording(
        path,
        onProgress: _handleAnalysisProgress,
      );
      if (!mounted) return;
      _scans.add(scan);
      _rebuildMatches();
      setState(() {
        _busy = false;
        _analysisProgress = null;
        _recordingStartedAt = null;
        final result = _result;
        if (result == null || result.matches.isEmpty) {
          _error =
              'No production-node rows were recognized. Crop the recording '
              'to the Activated list, keep the names visible, and scroll more '
              'slowly.';
          _status = null;
        } else {
          _error = null;
          _status =
              '${_scans.length} ${_scans.length == 1 ? 'recording' : 'recordings'} '
              'combined. Nothing changes until you confirm.';
        }
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _analysisProgress = null;
        _error = _readableError(error);
      });
    }
  }

  void _handleAnalysisProgress(BdoActiveNodeScanProgress progress) {
    if (!mounted || !_busy) return;
    final normalized = BdoActiveNodeScanProgress(
      fraction: progress.fraction.clamp(0.0, 1.0),
      completedFrames: math.max(0, progress.completedFrames),
      estimatedFrames: math.max(0, progress.estimatedFrames),
    );
    setState(() => _analysisProgress = normalized);
  }

  void _rebuildMatches() {
    final result = BdoActiveNodeListMatcher.match(
      frames: _scans.expand((scan) => scan.frames),
      productionNodes: _productionNodes,
    );
    final validKeys = <String>{
      for (final match in result.matches) _keyFor(match),
    };
    _selectedNodeIdsByMatch.removeWhere((key, _) => !validKeys.contains(key));
    _explicitlyUnchecked.removeWhere((key) => !validKeys.contains(key));
    for (final match in result.matches) {
      final key = _keyFor(match);
      if (match.canApplyWithoutChoice && !_explicitlyUnchecked.contains(key)) {
        _selectedNodeIdsByMatch.putIfAbsent(
          key,
          () => <String>{match.candidateNodeIds.single},
        );
      } else if (!_explicitlyUnchecked.contains(key)) {
        final savedCandidates = match.candidateNodeIds
            .where(widget.existingNodeIds.contains)
            .toSet();
        if (savedCandidates.isNotEmpty) {
          _selectedNodeIdsByMatch.putIfAbsent(key, () => savedCandidates);
        }
      }
    }
    _result = result;
  }

  void _toggleUniqueMatch(BdoActiveNodeImportMatch match, bool selected) {
    final key = _keyFor(match);
    setState(() {
      if (selected) {
        _selectedNodeIdsByMatch[key] = <String>{match.candidateNodeIds.single};
        _explicitlyUnchecked.remove(key);
      } else {
        _selectedNodeIdsByMatch.remove(key);
        _explicitlyUnchecked.add(key);
      }
    });
  }

  void _toggleAmbiguousMatch(
    BdoActiveNodeImportMatch match,
    String nodeId,
    bool selected,
  ) {
    final key = _keyFor(match);
    setState(() {
      final selectedNodeIds = <String>{...?_selectedNodeIdsByMatch[key]};
      if (selected) {
        selectedNodeIds.add(nodeId);
      } else {
        selectedNodeIds.remove(nodeId);
      }
      if (selectedNodeIds.isEmpty) {
        _selectedNodeIdsByMatch.remove(key);
        _explicitlyUnchecked.add(key);
      } else {
        _selectedNodeIdsByMatch[key] = selectedNodeIds;
        _explicitlyUnchecked.remove(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final media = MediaQuery.sizeOf(context);
    final estimated = Size(
      math.min(700, math.max(520, media.width - 36)).toDouble(),
      math.min(690, math.max(450, media.height - 36)).toDouble(),
    );
    return DraggableAlertDialog(
      identity: 'active-node-recording',
      dialogKey: const ValueKey<String>('active-node-recording-dialog'),
      estimatedSize: estimated,
      insetPadding: const EdgeInsets.all(18),
      backgroundColor: chrome.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: chrome.divider),
      ),
      titlePadding: const EdgeInsets.fromLTRB(22, 18, 12, 0),
      title: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: chrome.primary.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.video_file_outlined, color: chrome.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Read Activated nodes',
                  style: TextStyle(
                    color: chrome.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Scan a short scrolling recording; review before saving',
                  style: TextStyle(
                    color: chrome.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
      content: SizedBox(
        width: estimated.width - 44,
        height: math.max(300, estimated.height - 132),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildWorkflow(context),
            if (_error case final error?) ...<Widget>[
              const SizedBox(height: 10),
              _RecordingMessage(message: error, error: true),
            ] else if (_status case final status?) ...<Widget>[
              const SizedBox(height: 10),
              _RecordingMessage(message: status),
            ],
            if (_analysisProgress case final progress?) ...<Widget>[
              const SizedBox(height: 12),
              _RecordingAnalysisStatus(progress: progress),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                key: const ValueKey<String>('active-node-recording-progress'),
                value: progress.fraction,
                color: chrome.primary,
                backgroundColor: chrome.primary.withValues(alpha: .12),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(child: _buildResults(context)),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey<String>('active-node-recording-confirm'),
          onPressed: _busy || _selectedNodeIds.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selectedNodeIds),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(
            _newSelectionCount == 0
                ? 'Keep saved nodes'
                : 'Add $_newSelectionCount ${_newSelectionCount == 1 ? 'node' : 'nodes'}',
          ),
        ),
      ],
    );
  }

  Widget _buildWorkflow(BuildContext context) {
    final chrome = context.mapChrome;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: chrome.paperRaised.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: chrome.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'BDO map  >  Production Node Status  >  Activated',
              style: TextStyle(
                color: chrome.ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Record only that narrow list and scroll once from top to '
              'bottom. The map itself does not need to be visible.',
              style: TextStyle(color: chrome.muted, fontSize: 11, height: 1.3),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (widget.launchRecording != null)
                  FilledButton.tonalIcon(
                    key: const ValueKey<String>('active-node-recording-start'),
                    onPressed: _busy ? null : _startRectangleRecording,
                    icon: const Icon(Icons.crop_free_rounded, size: 18),
                    label: const Text('Start rectangle recording'),
                  ),
                if (widget.findLatestRecording != null &&
                    _recordingStartedAt != null)
                  FilledButton.tonalIcon(
                    key: const ValueKey<String>(
                      'active-node-recording-find-latest',
                    ),
                    onPressed: _busy ? null : _findLatest,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Find my recording'),
                  ),
                OutlinedButton.icon(
                  key: const ValueKey<String>('active-node-recording-choose'),
                  onPressed: _busy ? null : _chooseRecording,
                  icon: const Icon(Icons.video_file_outlined, size: 18),
                  label: Text(
                    _scans.isEmpty ? 'Choose MP4' : 'Add another MP4',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    final chrome = context.mapChrome;
    final result = _result;
    if (result == null || result.matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'The readable node names will appear here. Clear unique matches '
            'are selected automatically; uncertain ones wait for you.',
            textAlign: TextAlign.center,
            style: TextStyle(color: chrome.muted, fontSize: 12, height: 1.4),
          ),
        ),
      );
    }
    final accepted = result.accepted.length;
    final review = result.requiringReview.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '$accepted clear  /  $review to review  /  '
                '${_selectedNodeIds.length} selected',
                style: TextStyle(
                  color: chrome.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(
              onPressed: () =>
                  setState(() => _showDiagnostics = !_showDiagnostics),
              child: Text(_showDiagnostics ? 'Hide details' : 'Scan details'),
            ),
          ],
        ),
        if (_showDiagnostics)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${result.rejected.length} unread OCR '
              '${result.rejected.length == 1 ? 'line' : 'lines'} ignored. '
              '${_scans.expand((scan) => scan.frames).length} sharp frames '
              'sampled. Missing rows are never treated as disconnected.',
              style: TextStyle(
                color: chrome.muted,
                fontSize: 10.5,
                height: 1.35,
              ),
            ),
          ),
        Expanded(
          child: ListView.separated(
            key: const ValueKey<String>('active-node-recording-results'),
            itemCount: result.matches.length,
            separatorBuilder: (_, _) => const SizedBox(height: 7),
            itemBuilder: (context, index) =>
                _buildMatch(context, result.matches[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildMatch(BuildContext context, BdoActiveNodeImportMatch match) {
    final chrome = context.mapChrome;
    final key = _keyFor(match);
    final selectedNodeIds = _selectedNodeIdsByMatch[key] ?? const <String>{};
    final ambiguous = match.candidateNodeIds.length > 1;
    final alreadySaved = match.candidateNodeIds.any(
      widget.existingNodeIds.contains,
    );
    final confidence = (match.confidence * 100).round().clamp(0, 100);
    final warning = match.disposition == BdoActiveNodeMatchDisposition.review;
    return Material(
      color: warning
          ? chrome.warning.withValues(alpha: .075)
          : chrome.paperRaised.withValues(alpha: .62),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: warning
              ? chrome.warning.withValues(alpha: .44)
              : chrome.divider,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (!ambiguous)
                  Checkbox(
                    key: ValueKey<String>('active-node-match-$key'),
                    value: selectedNodeIds.isNotEmpty,
                    onChanged: alreadySaved
                        ? null
                        : (value) => _toggleUniqueMatch(match, value == true),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      Icons.rule_rounded,
                      color: chrome.warning,
                      size: 20,
                    ),
                  ),
                const SizedBox(width: 3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${match.canonicalName ?? match.observedText} - '
                        '${match.canonicalActivity ?? 'Unknown activity'}',
                        style: TextStyle(
                          color: chrome.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        alreadySaved
                            ? 'Already in your setup'
                            : ambiguous
                            ? 'Same in-game label: select each matching output below'
                            : warning
                            ? 'OCR match needs your confirmation / $confidence%'
                            : 'Clear match / read ${match.sightingCount} '
                                  '${match.sightingCount == 1 ? 'time' : 'times'}',
                        style: TextStyle(
                          color: warning ? chrome.warning : chrome.muted,
                          fontSize: 10.5,
                          fontWeight: warning
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (ambiguous) ...<Widget>[
              const SizedBox(height: 5),
              for (final nodeId in match.candidateNodeIds)
                _buildCandidateChoice(
                  context,
                  match,
                  nodeId,
                  selectedNodeIds.contains(nodeId),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCandidateChoice(
    BuildContext context,
    BdoActiveNodeImportMatch match,
    String nodeId,
    bool selected,
  ) {
    final chrome = context.mapChrome;
    final node = widget.dataset.workerNodesById[nodeId];
    final outputs =
        node?.outputs
            .map((output) => output.name.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .join(', ') ??
        '';
    final saved = widget.existingNodeIds.contains(nodeId);
    return CheckboxListTile(
      key: ValueKey<String>('active-node-candidate-$nodeId'),
      value: selected,
      onChanged: saved
          ? null
          : (value) => _toggleAmbiguousMatch(match, nodeId, value == true),
      dense: true,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
      contentPadding: const EdgeInsets.only(left: 6, right: 4),
      title: Text(
        outputs.isEmpty ? (node?.name ?? nodeId) : outputs,
        style: TextStyle(
          color: chrome.ink,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: saved
          ? Text(
              'Already in your setup',
              style: TextStyle(color: chrome.muted, fontSize: 10),
            )
          : null,
    );
  }
}

String _readableError(Object error) {
  if (error is PlatformException) {
    return error.message?.trim().isNotEmpty == true
        ? error.message!.trim()
        : 'Windows could not read that recording (${error.code}).';
  }
  if (error is FormatException) return error.message.toString();
  if (error is TimeoutException) {
    return error.message ?? 'Windows did not return the OCR result in time.';
  }
  return 'That recording could not be read. ${error.toString()}';
}

class _RecordingAnalysisStatus extends StatelessWidget {
  const _RecordingAnalysisStatus({required this.progress});

  final BdoActiveNodeScanProgress progress;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final percent = (progress.fraction * 100).round().clamp(0, 100);
    final label = progress.fraction < .10
        ? 'Opening recording'
        : progress.fraction < .30
        ? 'Sampling video frames'
        : progress.fraction >= .95
        ? 'Collecting OCR result'
        : 'Reading node names';
    final count = progress.estimatedFrames > 0
        ? '${progress.completedFrames} of ${progress.estimatedFrames}'
        : null;
    return Row(
      key: const ValueKey<String>('active-node-recording-progress-status'),
      children: <Widget>[
        Expanded(
          child: Text(
            count == null ? label : '$label  $count',
            style: TextStyle(
              color: chrome.text,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          '$percent%',
          style: TextStyle(
            color: chrome.primary,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _RecordingMessage extends StatelessWidget {
  const _RecordingMessage({required this.message, this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final color = error ? chrome.error : chrome.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: .42)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
              color: color,
              size: 17,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: chrome.text,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
