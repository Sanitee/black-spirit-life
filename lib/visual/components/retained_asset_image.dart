import 'package:flutter/material.dart';

/// Asset image with an explicit, named failure surface.
///
/// Retained authored art is part of the product contract. A decode or package
/// failure therefore remains visible instead of silently becoming a gradient
/// or an empty colored rectangle.
class RetainedAssetImage extends StatelessWidget {
  const RetainedAssetImage({
    required this.assetPath,
    required this.assetLabel,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.high,
    this.opacity,
    this.background = const Color(0xF20B1716),
    this.foreground = const Color(0xFFF4E8C9),
    this.imageKey,
    this.failureKey,
    super.key,
  });

  final String assetPath;
  final String assetLabel;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final FilterQuality filterQuality;
  final Animation<double>? opacity;
  final Color background;
  final Color foreground;
  final Key? imageKey;
  final Key? failureKey;

  @override
  Widget build(BuildContext context) => Image.asset(
    assetPath,
    key: imageKey,
    fit: fit,
    alignment: alignment,
    filterQuality: filterQuality,
    gaplessPlayback: true,
    opacity: opacity,
    errorBuilder: (context, error, stackTrace) => RetainedAssetFailure(
      key: failureKey,
      assetLabel: assetLabel,
      background: background,
      foreground: foreground,
    ),
  );
}

class RetainedAssetFailure extends StatelessWidget {
  const RetainedAssetFailure({
    required this.assetLabel,
    required this.background,
    required this.foreground,
    super.key,
  });

  final String assetLabel;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: '$assetLabel asset unavailable',
    child: ColoredBox(
      color: background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.broken_image_outlined, color: foreground, size: 22),
              const SizedBox(height: 5),
              Text(
                'Artwork unavailable',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                assetLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: foreground.withAlpha(190),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
