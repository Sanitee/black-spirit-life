import 'package:flutter/material.dart';

/// Original game artwork, selected from unchanged bundled reference images.
enum AvailabilityArtwork { stock, preorders, npc, inventory }

class AvailabilityGameIcon extends StatelessWidget {
  const AvailabilityGameIcon({
    required this.artwork,
    required this.color,
    this.size = 16,
    super.key,
  });

  final AvailabilityArtwork artwork;
  final Color color;
  final double size;

  static const marketplaceAsset = 'assets/app/availability_marketplace.png';
  static const buyAsset = 'assets/app/availability_buy_sell.png';
  static const inventoryAsset = 'assets/app/availability_inventory.png';
  static const npcAsset =
      'packages/bdo_map_core/assets/images/gathering_tools/interaction_00.png';

  @override
  Widget build(BuildContext context) {
    final (asset, dimensions, crop, threshold) = switch (artwork) {
      AvailabilityArtwork.stock => (
        marketplaceAsset,
        const Size(56, 51),
        const Rect.fromLTWH(14, 11, 32, 32),
        112.0,
      ),
      AvailabilityArtwork.preorders => (
        buyAsset,
        const Size(62, 188),
        const Rect.fromLTWH(13, 26, 28, 28),
        110.0,
      ),
      AvailabilityArtwork.inventory => (
        inventoryAsset,
        const Size(185, 49),
        const Rect.fromLTWH(11, 9, 24, 24),
        112.0,
      ),
      AvailabilityArtwork.npc => (
        npcAsset,
        const Size(512, 256),
        const Rect.fromLTWH(147, 7, 22, 22),
        150.0,
      ),
    };
    final scale = size / crop.width;
    // Convert the screenshot's light silhouette into theme-coloured alpha.
    // The source bitmap stays byte-exact; its UI background is not displayed.
    final filter = ColorFilter.matrix([
      0,
      0,
      0,
      0,
      color.r * 255,
      0,
      0,
      0,
      0,
      color.g * 255,
      0,
      0,
      0,
      0,
      color.b * 255,
      5 * .2126,
      5 * .7152,
      5 * .0722,
      0,
      -5 * threshold,
    ]);
    Widget image = ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: dimensions.width * scale,
        maxWidth: dimensions.width * scale,
        minHeight: dimensions.height * scale,
        maxHeight: dimensions.height * scale,
        child: Transform.translate(
          offset: Offset(-crop.left * scale, -crop.top * scale),
          child: ColorFiltered(
            colorFilter: filter,
            child: Image.asset(
              asset,
              width: dimensions.width * scale,
              height: dimensions.height * scale,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    );
    if (artwork == AvailabilityArtwork.npc) image = ClipOval(child: image);
    return ExcludeSemantics(
      child: SizedBox.square(
        key: ValueKey('availability-game-icon:${artwork.name}'),
        dimension: size,
        child: image,
      ),
    );
  }
}
