import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../assets.dart';
import '../domain/models.dart';
import '../services/native_bridge.dart';
import '../ui/theme.dart';
import 'spot_video_player.dart';

String _mediaIdentity(SpotMedia media) {
  final video = media.type == 'video' ? YouTubeVideo.parse(media.url) : null;
  if (video != null) return 'video:${video.id}:${video.startSeconds}';
  return '${media.type}:${media.asset.isEmpty ? media.url : media.asset}';
}

String _referenceIdentity(SpotMedia media) {
  final video = media.type == 'video' ? YouTubeVideo.parse(media.url) : null;
  return video == null ? _mediaIdentity(media) : 'video:${video.id}';
}

List<List<SpotMedia>> _referenceGroups(List<SpotMedia> media) {
  final groups = <String, List<SpotMedia>>{};
  for (final entry in media) {
    groups.putIfAbsent(_referenceIdentity(entry), () => []).add(entry);
  }
  return groups.values.toList();
}

SpotMedia _preferredReference(
  List<SpotMedia> group,
  Map<String, SpotMedia> remembered,
) {
  final previous = remembered[_referenceIdentity(group.first)];
  return group
          .where(
            (entry) =>
                _mediaIdentity(entry) ==
                (previous == null ? null : _mediaIdentity(previous)),
          )
          .firstOrNull ??
      group.first;
}

bool _isBairogVideoReference(SpotMedia media) =>
    media.type == 'video' &&
    const {'bairog', 'bairog haan'}.contains(media.author.trim().toLowerCase());

/// Keeps creator-backed Bairog videos at the front of every reference picker.
/// All remaining references retain their established newest-first ordering.
@visibleForTesting
List<SpotMedia> orderSpotMediaForDisplay(List<SpotMedia> media) {
  final seen = <String>{};
  final entries = media.indexed.where((entry) {
    final item = entry.$2;
    return ((item.type == 'image' && item.asset.isNotEmpty) ||
            (item.type == 'video' && item.url.isNotEmpty)) &&
        seen.add(_mediaIdentity(item));
  }).toList();
  entries.sort((a, b) {
    final firstIsBairog = _isBairogVideoReference(a.$2);
    final secondIsBairog = _isBairogVideoReference(b.$2);
    if (firstIsBairog != secondIsBairog) return firstIsBairog ? -1 : 1;
    final first = a.$2.publishedDate;
    final second = b.$2.publishedDate;
    if (first == null && second != null) return 1;
    if (first != null && second == null) return -1;
    final byDate = first != null && second != null
        ? second.compareTo(first)
        : 0;
    return byDate == 0 ? a.$1.compareTo(b.$1) : byDate;
  });
  return entries.map((entry) => entry.$2).toList();
}

String _publishedLabel(SpotMedia media) {
  final date = media.publishedDate;
  if (date == null) return '';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

/// Catalog illustrations are bundled guide assets, never imported inventory images.
class SpotMediaGallery extends StatefulWidget {
  const SpotMediaGallery({
    super.key,
    required this.media,
    this.height,
    this.videoSessionFactory,
  });
  final List<SpotMedia> media;

  /// Total panel height, including header. Videos need about 300 px or more.
  final double? height;
  @visibleForTesting
  final SpotVideoSession Function()? videoSessionFactory;

  @override
  State<SpotMediaGallery> createState() => _SpotMediaGalleryState();
}

class _SpotMediaGalleryState extends State<SpotMediaGallery> {
  String? _selectedId;
  bool _expanded = false;
  final _remembered = <String, SpotMedia>{};

  List<SpotMedia> get _media => orderSpotMediaForDisplay(widget.media);

  @override
  void initState() {
    super.initState();
    _reconcile();
  }

  @override
  void didUpdateWidget(covariant SpotMediaGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reconcile();
  }

  void _reconcile() {
    final media = _media;
    if (!media.any((entry) => _mediaIdentity(entry) == _selectedId)) {
      // Keep location/rotation artwork as the first preview when adding newer
      // setup references. The pager still exposes every image and video.
      final images = media.where((entry) => entry.type == 'image');
      final first =
          images.where((entry) {
            final title = entry.title.toLowerCase();
            return !title.contains('setup') && !title.contains('buff');
          }).firstOrNull ??
          images.firstOrNull ??
          media.firstOrNull;
      _selectedId = first == null ? null : _mediaIdentity(first);
    }
  }

  void _select(SpotMedia media) => setState(() {
    _selectedId = _mediaIdentity(media);
    _remembered[_referenceIdentity(media)] = media;
  });

  Future<void> _expand(SpotMedia media) async {
    if (_expanded) return;
    setState(() => _expanded = true);
    // Remove the inline native player before opening the second one. Its
    // asynchronous native disposal is serialized by SpotVideoPlayer's backend.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      await showSpotMedia(
        context,
        media,
        alternatives: _media,
        preferredSelections: _remembered.values.toList(),
        onChanged: (selected) {
          if (mounted) _select(selected);
        },
        videoSessionFactory: widget.videoSessionFactory,
      );
    } finally {
      if (mounted) setState(() => _expanded = false);
    }
  }

  String _label(SpotMedia media) => media.type == 'video'
      ? 'Video'
      : media.title.toLowerCase().contains('area')
      ? 'Hunting area'
      : media.title.toLowerCase().contains('rotation')
      ? 'Rotation'
      : media.title.toLowerCase().contains('setup')
      ? 'Setup'
      : media.title.toLowerCase().contains('buff')
      ? 'Buffs'
      : 'Map';

  @override
  Widget build(BuildContext context) {
    final media = _media;
    if (media.isEmpty) return const SizedBox.shrink();
    final index = media.indexWhere(
      (entry) => _mediaIdentity(entry) == _selectedId,
    );
    final selected = media[index < 0 ? 0 : index];
    final groups = _referenceGroups(media);
    final groupIndex = groups.indexWhere(
      (group) =>
          _referenceIdentity(group.first) == _referenceIdentity(selected),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 480.0;
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final compact = width < 380 * scale;
        final videoCapable = media.any((entry) => entry.type == 'video');
        final height =
            widget.height ??
            math.max(videoCapable ? 300.0 : 230.0, width * 9 / 16 + 64 * scale);
        final heading = _MediaReferencePicker(
          buttonKey: const ValueKey('spot-media-reference'),
          media: media,
          selected: selected,
          onSelected: _select,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                if (compact) ...[
                  Tooltip(
                    message: _label(selected),
                    child: Icon(
                      selected.type == 'video'
                          ? Icons.play_circle_outline
                          : Icons.image_outlined,
                      key: const ValueKey('spot-media-type'),
                      semanticLabel: _label(selected),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!compact && selected.title.trim() != _label(selected))
                        Text(
                          _label(selected),
                          key: const ValueKey('spot-media-type'),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: context.gatheringColors.muted,
                          ),
                        ),
                      Text(
                        selected.title.isEmpty ? 'Reference' : selected.title,
                        key: const ValueKey('spot-media-title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (media.length > 1) const Icon(Icons.expand_more, size: 18),
              ],
            ),
          ),
        );
        final controls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (groups.length > 1)
              _MediaPager(
                index: groupIndex,
                count: groups.length,
                inline: true,
                onSelected: (position) =>
                    _select(_preferredReference(groups[position], _remembered)),
              ),
            GatheringQuietIconButton(
              key: const ValueKey('expand-spot-media'),
              tooltip: 'Expand ${selected.type == 'video' ? 'video' : 'image'}',
              onPressed: () => _expand(selected),
              icon: const Icon(Icons.open_in_full, size: 18),
              style: IconButton.styleFrom(
                minimumSize: const Size(36, 40),
                maximumSize: const Size(36, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        );
        return SizedBox(
          key: const ValueKey('spot-media-gallery'),
          height: height,
          width: width,
          child: Material(
            color: context.glass.panel,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: context.glass.line),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: heading),
                    controls,
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: selected.type == 'image'
                      ? InkWell(
                          key: ValueKey('spot-media-image-${selected.asset}'),
                          onTap: () => _expand(selected),
                          child: SizedBox.expand(
                            child: Image.asset(
                              selected.asset,
                              package: gatheringAssetPackage,
                              key: const ValueKey('inline-rotation-image'),
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Center(
                                child: Text(
                                  'This rotation image is unavailable.',
                                ),
                              ),
                            ),
                          ),
                        )
                      : _expanded
                      ? const SizedBox.expand()
                      : SpotVideoPlayer(
                          key: ValueKey('inline-spot-video-${selected.url}'),
                          videoUrl: selected.url,
                          title: selected.title,
                          loadOnOpen: true,
                          showTitle: false,
                          sessionFactory: widget.videoSessionFactory,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MediaPager extends StatelessWidget {
  const _MediaPager({
    required this.index,
    required this.count,
    required this.onSelected,
    this.inline = false,
  });
  final int index, count;
  final ValueChanged<int> onSelected;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final prefix = inline ? 'inline-' : '';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GatheringQuietIconButton(
          key: ValueKey('${prefix}previous-spot-reference'),
          tooltip: 'Previous reference',
          onPressed: index > 0 ? () => onSelected(index - 1) : null,
          icon: const Icon(Icons.chevron_left, size: 22),
          style: IconButton.styleFrom(
            minimumSize: const Size(32, 40),
            maximumSize: const Size(32, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        Text(
          '${index + 1}/$count',
          key: ValueKey('${prefix}spot-reference-position'),
          semanticsLabel: 'Reference ${index + 1} of $count',
          style: TextStyle(
            fontSize: 12.5,
            color: context.gatheringColors.muted,
          ),
        ),
        GatheringQuietIconButton(
          key: ValueKey('${prefix}next-spot-reference'),
          tooltip: 'Next reference',
          onPressed: index + 1 < count ? () => onSelected(index + 1) : null,
          icon: const Icon(Icons.chevron_right, size: 22),
          style: IconButton.styleFrom(
            minimumSize: const Size(32, 40),
            maximumSize: const Size(32, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}

Future<void> showSpotMedia(
  BuildContext context,
  SpotMedia media, {
  List<SpotMedia> alternatives = const [],
  List<SpotMedia> preferredSelections = const [],
  ValueChanged<SpotMedia>? onChanged,
  @visibleForTesting SpotVideoSession Function()? videoSessionFactory,
}) => showDialog<void>(
  context: context,
  builder: (context) => _ExpandedSpotMedia(
    initial: media,
    choices: orderSpotMediaForDisplay([...alternatives, media]),
    preferredSelections: preferredSelections,
    onChanged: onChanged,
    videoSessionFactory: videoSessionFactory,
  ),
);

class _ExpandedSpotMedia extends StatefulWidget {
  const _ExpandedSpotMedia({
    required this.initial,
    required this.choices,
    required this.preferredSelections,
    this.onChanged,
    this.videoSessionFactory,
  });
  final SpotMedia initial;
  final List<SpotMedia> choices;
  final List<SpotMedia> preferredSelections;
  final ValueChanged<SpotMedia>? onChanged;
  final SpotVideoSession Function()? videoSessionFactory;

  @override
  State<_ExpandedSpotMedia> createState() => _ExpandedSpotMediaState();
}

class _ExpandedSpotMediaState extends State<_ExpandedSpotMedia> {
  late SpotMedia _selected = widget.initial;
  late final _remembered = <String, SpotMedia>{
    for (final entry in widget.preferredSelections)
      _referenceIdentity(entry): entry,
    _referenceIdentity(widget.initial): widget.initial,
  };

  void _select(SpotMedia media) {
    setState(() {
      _selected = media;
      _remembered[_referenceIdentity(media)] = media;
    });
    widget.onChanged?.call(media);
  }

  @override
  Widget build(BuildContext context) {
    final media = _selected;
    final groups = _referenceGroups(widget.choices);
    final index = groups.indexWhere(
      (group) => _referenceIdentity(group.first) == _referenceIdentity(media),
    );
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      key: ValueKey(
        media.type == 'video' ? 'spot-video-dialog' : 'spot-rotation-dialog',
      ),
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.min(screen.width - 32, 1120),
        height: math.min(screen.height - 32, 780),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _MediaReferencePicker(
                      buttonKey: const ValueKey(
                        'expanded-spot-media-reference',
                      ),
                      media: widget.choices,
                      selected: media,
                      onSelected: _select,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  media.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                _MediaPublishedDate(media: media),
                              ],
                            ),
                          ),
                          if (widget.choices.length > 1)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.expand_more, size: 18),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (groups.length > 1)
                    _MediaPager(
                      index: index,
                      count: groups.length,
                      onSelected: (position) => _select(
                        _preferredReference(groups[position], _remembered),
                      ),
                    ),
                  GatheringQuietIconButton(
                    key: const ValueKey('close-spot-media'),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: media.type == 'video'
                  ? SpotVideoPlayer(
                      key: ValueKey('expanded-spot-video-${media.url}'),
                      videoUrl: media.url,
                      title: media.title,
                      startOnOpen: true,
                      showTitle: false,
                      sessionFactory: widget.videoSessionFactory,
                    )
                  : _RotationImage(key: ValueKey(media.asset), media: media),
            ),
            if (media.type == 'video')
              _MediaCredits(key: ValueKey(media.url), media: media),
          ],
        ),
      ),
    );
  }
}

class _MediaReferencePicker extends StatelessWidget {
  const _MediaReferencePicker({
    required this.buttonKey,
    required this.media,
    required this.selected,
    required this.onSelected,
    required this.child,
  });
  final Key buttonKey;
  final List<SpotMedia> media;
  final SpotMedia selected;
  final ValueChanged<SpotMedia> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = math.min(420.0, MediaQuery.sizeOf(context).width - 32);
    final groups = _referenceGroups(media);
    return PopupMenuButton<String>(
      key: buttonKey,
      enabled: media.length > 1,
      tooltip: selected.title.isEmpty ? 'Choose reference' : selected.title,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      constraints: BoxConstraints(
        minWidth: math.min(300, width),
        maxWidth: width,
      ),
      // No initialValue: selection must not recenter the popup over its trigger.
      itemBuilder: (context) => [
        for (final group in groups) ...[
          if (group.length > 1)
            PopupMenuItem<String>(
              key: ValueKey(
                'spot-reference-group-${_referenceIdentity(group.first)}',
              ),
              enabled: false,
              height: 0,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.play_circle_outline,
                    size: 18,
                    color: context.gatheringColors.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      [
                        group.first.author.trim().isEmpty
                            ? 'Video'
                            : group.first.author,
                        if (_publishedLabel(group.first).isNotEmpty)
                          _publishedLabel(group.first),
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.gatheringColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          for (final entry in group)
            PopupMenuItem<String>(
              key: ValueKey('spot-reference-option-${media.indexOf(entry)}'),
              value: _mediaIdentity(entry),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: group.length > 1
                  ? _ChapterOption(
                      media: entry,
                      selected:
                          _mediaIdentity(entry) == _mediaIdentity(selected),
                    )
                  : _ReferenceOption(
                      media: entry,
                      fallback: 'Reference ${groups.indexOf(group) + 1}',
                      selected:
                          _mediaIdentity(entry) == _mediaIdentity(selected),
                    ),
            ),
        ],
      ],
      onSelected: (id) =>
          onSelected(media.firstWhere((entry) => _mediaIdentity(entry) == id)),
      child: child,
    );
  }
}

String _chapterTime(int seconds) {
  final minutes = seconds ~/ 60;
  final tail = (seconds % 60).toString().padLeft(2, '0');
  return minutes < 60
      ? '$minutes:$tail'
      : '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}:$tail';
}

String _chapterTitle(SpotMedia media, int seconds) {
  final parts = media.title.split(' · ');
  final timestamp = _chapterTime(seconds);
  // Remove only exact repeated metadata from the established title convention.
  // Arbitrary creator titles are never parsed as new chapter or video metadata.
  while (parts.length > 1 &&
      (parts.last.trim() == timestamp ||
          (media.author.trim().isNotEmpty &&
              parts.last.trim().toLowerCase() ==
                  media.author.trim().toLowerCase()))) {
    parts.removeLast();
  }
  return parts.join(' · ').trim();
}

class _ChapterOption extends StatelessWidget {
  const _ChapterOption({required this.media, required this.selected});
  final SpotMedia media;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final seconds = YouTubeVideo.parse(media.url)!.startSeconds;
    final title = _chapterTitle(media, seconds);
    return Semantics(
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.only(left: 28),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _chapterTime(seconds),
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: context.gatheringColors.accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title.isEmpty ? 'Video' : title,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                  color: context.gatheringColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 18,
              child: selected
                  ? Icon(
                      Icons.check,
                      size: 18,
                      color: context.gatheringColors.accent,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceOption extends StatelessWidget {
  const _ReferenceOption({
    required this.media,
    required this.fallback,
    required this.selected,
  });
  final SpotMedia media;
  final String fallback;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (media.type == 'video' && media.author.isNotEmpty) media.author,
      if (_publishedLabel(media).isNotEmpty) _publishedLabel(media),
    ].join(' · ');
    return Semantics(
      selected: selected,
      child: Row(
        children: [
          Icon(
            media.type == 'video'
                ? Icons.play_circle_outline
                : Icons.image_outlined,
            size: 18,
            color: selected
                ? context.gatheringColors.accent
                : context.gatheringColors.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  media.title.isEmpty ? fallback : media.title,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: context.gatheringColors.ink,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    details,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.gatheringColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 18,
            child: selected
                ? Icon(
                    Icons.check,
                    size: 18,
                    color: context.gatheringColors.accent,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _MediaPublishedDate extends StatelessWidget {
  const _MediaPublishedDate({required this.media});
  final SpotMedia media;

  @override
  Widget build(BuildContext context) {
    final label = _publishedLabel(media);
    if (label.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: 'Published $label',
      child: Text(
        label,
        key: ValueKey('spot-${media.type}-published-date'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: context.gatheringColors.muted),
      ),
    );
  }
}

class _MediaCredits extends StatefulWidget {
  const _MediaCredits({super.key, required this.media});
  final SpotMedia media;
  @override
  State<_MediaCredits> createState() => _MediaCreditsState();
}

class _MediaCreditsState extends State<_MediaCredits> {
  String? _error;
  Future<void> _openSource() async {
    var opened = false;
    try {
      opened = await NativeBridge.openExternal(widget.media.sourceUrl);
    } catch (_) {
      /* Keep video available. */
    }
    if (!opened && mounted) {
      setState(() => _error = 'Could not open the source.');
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 8, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _error ?? widget.media.author,
            style: TextStyle(
              fontSize: 12,
              color: context.gatheringColors.muted,
            ),
          ),
        ),
        if (widget.media.sourceUrl.isNotEmpty)
          GatheringQuietIconButton(
            tooltip: 'Open source',
            onPressed: _openSource,
            icon: const Icon(Icons.open_in_new, size: 18),
          ),
      ],
    ),
  );
}

class _RotationImage extends StatefulWidget {
  const _RotationImage({super.key, required this.media});
  final SpotMedia media;
  @override
  State<_RotationImage> createState() => _RotationImageState();
}

class _RotationImageState extends State<_RotationImage> {
  final _transform = TransformationController();
  String? _error;
  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _source() async {
    var opened = false;
    try {
      opened = await NativeBridge.openExternal(widget.media.sourceUrl);
    } catch (_) {
      /* Keep the illustration available. */
    }
    if (!opened && mounted) {
      setState(() => _error = 'Could not open the source.');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                key: const ValueKey('rotation-viewer'),
                transformationController: _transform,
                minScale: 1,
                maxScale: 8,
                child: SizedBox.expand(
                  child: Image.asset(
                    widget.media.asset,
                    package: gatheringAssetPackage,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Center(
                      child: Text('This rotation image is unavailable.'),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                tooltip: 'Fit image',
                onPressed: () => _transform.value = Matrix4.identity(),
                icon: const Icon(Icons.fit_screen),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _error ?? widget.media.author,
                style: TextStyle(
                  fontSize: 12,
                  color: context.gatheringColors.muted,
                ),
              ),
            ),
            if (widget.media.sourceUrl.isNotEmpty)
              GatheringQuietIconButton(
                tooltip: 'Open source',
                onPressed: _source,
                icon: const Icon(Icons.open_in_new, size: 18),
              ),
          ],
        ),
      ),
    ],
  );
}
