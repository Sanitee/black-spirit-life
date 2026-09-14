import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'resource_map_chrome_theme.dart';

/// Game house-recipe IDs and the game's UI use groups are different namespaces.
/// UVs match HouseControlManager:UseTypeIconTexture, not the animated upgrade
/// effects under houseinfo/usetype. See the bundled provenance notice.
int houseUseIconGroup(int type) => switch (type) {
  0 || 1 || 2 || 3 => type,
  11 || 1801 => 4,
  12 => 5,
  13 => 6,
  14 => 7,
  15 || 999 => 8,
  16 || 21 || 2002 || 2004 => 9,
  17 => 10,
  19 || 2009 => 23,
  1051 => 19,
  >= 1101 && <= 1106 || 2011 => 13,
  >= 1201 && <= 1208 => 14,
  1301 || 1304 => 15,
  1302 || 1901 || 2012 => 20,
  1303 => 21,
  >= 1401 && <= 1419 || 1428 || 1432 || 2003 => 16,
  1422 || 1423 || 1424 || 1426 || 1427 => 18,
  1701 || 1702 => 22,
  _ => 17,
};

Rect houseUseIconRect(int type) {
  final group = houseUseIconGroup(type);
  if (group <= 8) return Rect.fromLTWH(170 + group * 19, 265, 18, 18);
  if (group <= 17) return Rect.fromLTWH(170 + (group - 9) * 19, 284, 18, 18);
  return Rect.fromLTWH(
    switch (group) {
      18 => 227,
      19 => 170,
      20 => 208,
      21 => 189,
      22 => 246,
      _ => 265,
    },
    303,
    18,
    18,
  );
}

class HouseUseIcon extends StatefulWidget {
  const HouseUseIcon({super.key, required this.typeId, this.size = 22});
  static const asset = 'assets/images/house_icons/houseicon.png';
  final int typeId;
  final double size;
  @override
  State<HouseUseIcon> createState() => _HouseUseIconState();
}

class _HouseUseIconState extends State<HouseUseIcon> {
  ImageStream? _stream;
  ImageInfo? _info;
  late final _listener = ImageStreamListener((info, _) {
    if (!mounted) {
      info.dispose();
      return;
    }
    setState(() {
      _info?.dispose();
      _info = info;
    });
  });
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stream != null) return;
    _stream = const AssetImage(
      HouseUseIcon.asset,
      package: 'bdo_map_core',
    ).resolve(createLocalImageConfiguration(context));
    _stream!.addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: _info == null
        ? null
        : CustomPaint(
            painter: _HouseIconPainter(
              _info!.image,
              houseUseIconRect(widget.typeId),
              context.mapChrome.ink,
            ),
          ),
  );
}

class _HouseIconPainter extends CustomPainter {
  const _HouseIconPainter(this.image, this.source, this.tint);
  final ui.Image image;
  final Rect source;
  final Color tint;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawImageRect(
    image,
    source,
    Offset.zero & size,
    Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = ColorFilter.mode(tint, BlendMode.srcIn),
  );
  @override
  bool shouldRepaint(_HouseIconPainter old) =>
      old.image != image || old.source != source || old.tint != tint;
}
