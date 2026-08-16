import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../components/retained_asset_image.dart';
import 'sakura_spec.dart';

/// Authored, transparent botanical artwork retained by the Sakura theme.
///
/// Every source bitmap is an integer multiple of its logical display size.
/// Keeping those authored measures stable preserves the petal, stamen, bark,
/// and leaf detail instead of stretching the artwork with its surrounding UI.
abstract final class SakuraBotanicalAssets {
  static const String sidebarBranch =
      'assets/sakura/botanicals/sidebar-branch.png';
  static const String titleSprig = 'assets/sakura/botanicals/title-sprig.png';
  static const String sectionBloom =
      'assets/sakura/botanicals/section-bloom.png';
  static const String queueRisingBloom =
      'assets/sakura/botanicals/queue-rising-bloom.png';
  static const String queueLowBuds =
      'assets/sakura/botanicals/queue-low-buds.png';
  static const String queueSplitBloom =
      'assets/sakura/botanicals/queue-split-bloom.png';
}

/// The fixed 198 x 290 authored branch for the flexible sidebar instrument bay.
class SakuraSidebarBotanicalAsset extends StatelessWidget {
  const SakuraSidebarBotanicalAsset({super.key});

  static const Size authoredSize = Size(198, 290);
  static const Key imageKey = ValueKey<String>(
    'sakura-sidebar-botanical-image',
  );
  static const Key failureKey = ValueKey<String>(
    'sakura-sidebar-botanical-failure',
  );

  @override
  Widget build(BuildContext context) => const _FixedBotanicalAsset(
    size: authoredSize,
    assetPath: SakuraBotanicalAssets.sidebarBranch,
    assetLabel: 'Sakura sidebar branch',
    imageKey: imageKey,
    failureKey: failureKey,
    alignment: Alignment.bottomCenter,
  );
}

/// The fixed 168 x 32 botanical inlay at the safe end of the title strip.
class SakuraTitleSprigAsset extends StatelessWidget {
  const SakuraTitleSprigAsset({super.key});

  static const Size authoredSize = Size(168, 32);
  static const Key imageKey = ValueKey<String>('sakura-title-sprig-image');
  static const Key failureKey = ValueKey<String>('sakura-title-sprig-failure');

  @override
  Widget build(BuildContext context) => const _FixedBotanicalAsset(
    size: authoredSize,
    assetPath: SakuraBotanicalAssets.titleSprig,
    assetLabel: 'Sakura title sprig',
    imageKey: imageKey,
    failureKey: failureKey,
    alignment: Alignment.centerRight,
  );
}

/// The fixed 80 x 18 blossom cluster used at the end of responsive rules.
class SakuraSectionBloomAsset extends StatelessWidget {
  const SakuraSectionBloomAsset({super.key});

  static const Size authoredSize = Size(80, 18);
  static const Key imageKey = ValueKey<String>('sakura-section-bloom-image');
  static const Key failureKey = ValueKey<String>(
    'sakura-section-bloom-failure',
  );

  @override
  Widget build(BuildContext context) => const _FixedBotanicalAsset(
    size: authoredSize,
    assetPath: SakuraBotanicalAssets.sectionBloom,
    assetLabel: 'Sakura section blossom',
    imageKey: imageKey,
    failureKey: failureKey,
    alignment: Alignment.centerRight,
  );
}

/// A responsive fine branch which terminates in a fixed-size authored bloom.
///
/// Only the quiet stem follows the available heading width. The detailed
/// blossom cluster remains at 80 x 18 logical pixels at every supported
/// viewport, avoiding the pinprick effect caused by scaling an entire rule.
class SakuraSectionRuleAsset extends StatelessWidget {
  const SakuraSectionRuleAsset({super.key});

  static const Key stemKey = ValueKey<String>('sakura-section-rule-stem');

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: const <Widget>[
            Positioned.fill(
              child: CustomPaint(
                key: stemKey,
                painter: _SakuraSectionStemPainter(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: SakuraSectionBloomAsset(),
            ),
          ],
        ),
      ),
    ),
  );
}

enum SakuraQueueCornerAssetVariant { risingBloom, lowBuds, splitBloom }

/// One of three fixed 54 x 30 authored flourishes for Queue-card corners.
class SakuraQueueCornerAsset extends StatelessWidget {
  const SakuraQueueCornerAsset({required this.variant, super.key});

  factory SakuraQueueCornerAsset.fromIndex(int index, {Key? key}) =>
      SakuraQueueCornerAsset(variant: variantForIndex(index), key: key);

  static const Size authoredSize = Size(54, 30);

  final SakuraQueueCornerAssetVariant variant;

  /// Stable modulo mapping for lists which recycle or insert Queue cards.
  static SakuraQueueCornerAssetVariant variantForIndex(int index) {
    final count = SakuraQueueCornerAssetVariant.values.length;
    final remainder = index % count;
    final normalized = remainder < 0 ? remainder + count : remainder;
    return SakuraQueueCornerAssetVariant.values[normalized];
  }

  String get _assetPath => switch (variant) {
    SakuraQueueCornerAssetVariant.risingBloom =>
      SakuraBotanicalAssets.queueRisingBloom,
    SakuraQueueCornerAssetVariant.lowBuds => SakuraBotanicalAssets.queueLowBuds,
    SakuraQueueCornerAssetVariant.splitBloom =>
      SakuraBotanicalAssets.queueSplitBloom,
  };

  String get _assetLabel => switch (variant) {
    SakuraQueueCornerAssetVariant.risingBloom => 'Sakura rising Queue blossom',
    SakuraQueueCornerAssetVariant.lowBuds => 'Sakura low Queue buds',
    SakuraQueueCornerAssetVariant.splitBloom => 'Sakura split Queue blossom',
  };

  @override
  Widget build(BuildContext context) => _FixedBotanicalAsset(
    size: authoredSize,
    assetPath: _assetPath,
    assetLabel: _assetLabel,
    imageKey: ValueKey<String>('sakura-queue-${variant.name}-image'),
    failureKey: ValueKey<String>('sakura-queue-${variant.name}-failure'),
    alignment: Alignment.bottomRight,
  );
}

class _FixedBotanicalAsset extends StatelessWidget {
  const _FixedBotanicalAsset({
    required this.size,
    required this.assetPath,
    required this.assetLabel,
    required this.imageKey,
    required this.failureKey,
    required this.alignment,
  });

  final Size size;
  final String assetPath;
  final String assetLabel;
  final Key imageKey;
  final Key failureKey;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size.width,
    height: size.height,
    child: IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: RetainedAssetImage(
            assetPath: assetPath,
            assetLabel: assetLabel,
            imageKey: imageKey,
            failureKey: failureKey,
            fit: BoxFit.contain,
            alignment: alignment,
            filterQuality: FilterQuality.high,
            background: SakuraNightGardenSpec.canvasDeep,
            foreground: SakuraNightGardenSpec.warmIvory,
          ),
        ),
      ),
    ),
  );
}

/// Multi-pass bark stem without flowers; detailed blooms are retained assets.
class _SakuraSectionStemPainter extends CustomPainter {
  const _SakuraSectionStemPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height < 4) return;
    final endX = math.max(6.0, size.width - 74);
    final startY = size.height * .79;
    final endY = size.height * .69;
    final branch = Path()
      ..moveTo(1, startY)
      ..cubicTo(
        endX * .28,
        size.height * .92,
        endX * .68,
        size.height * .47,
        endX,
        endY,
      );

    canvas
      ..drawPath(
        branch,
        Paint()
          ..color = const Color(0xA6000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round,
      )
      ..drawPath(
        branch,
        Paint()
          ..shader = const LinearGradient(
            colors: <Color>[
              Color(0xFF3A2423),
              Color(0xFF8D5C50),
              Color(0xFF4A2A2A),
            ],
          ).createShader(Rect.fromLTWH(0, 0, endX, size.height))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.45
          ..strokeCap = StrokeCap.round,
      )
      ..drawPath(
        branch,
        Paint()
          ..color = const Color(0xB8C18470)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .42
          ..strokeCap = StrokeCap.round,
      );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant _SakuraSectionStemPainter oldDelegate) => false;
}
