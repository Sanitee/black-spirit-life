import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'resource_map_chrome_theme.dart';
import 'worker_activity_style.dart';

enum ResourceMapMenuArtworkKind {
  plan,
  checklist,
  saved,
  materials,
  income,
  findNodes,
  connections,
  invest,
  houses,
  royalWorkshop,
  scan,
}

/// Original game symbols where available, with matching quiet UI glyphs for
/// companion-only actions. These are controls, not illustrated inventory items.
class ResourceMapMenuArtwork extends StatelessWidget {
  const ResourceMapMenuArtwork({super.key, required this.kind, this.size = 36});

  final ResourceMapMenuArtworkKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final Widget artwork;
    final asset = switch (kind) {
      ResourceMapMenuArtworkKind.materials => 'iron_ore',
      ResourceMapMenuArtworkKind.income => 'silver',
      ResourceMapMenuArtworkKind.houses => 'house',
      _ => null,
    };
    if (asset != null) {
      artwork = Image.asset(
        'assets/images/menu_artwork/$asset.webp',
        package: 'bdo_map_core',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      );
    } else if (kind == ResourceMapMenuArtworkKind.findNodes ||
        kind == ResourceMapMenuArtworkKind.invest) {
      artwork = Stack(
        children: [
          // The original node texture has a large transparent margin. Normalize
          // its visible size here only; map-marker artwork stays untouched.
          ClipRect(
            child: Transform.scale(
              scale: 1.7,
              child: BdoNodeTypeImage(sourceIconType: 0, size: size),
            ),
          ),
          if (kind == ResourceMapMenuArtworkKind.invest)
            Positioned.fill(
              child: CustomPaint(
                painter: _MenuSymbolPainter(kind, chrome.ink, chrome.text),
              ),
            ),
        ],
      );
    } else {
      artwork = CustomPaint(
        painter: _MenuSymbolPainter(kind, chrome.ink, chrome.text),
      );
    }
    return ExcludeSemantics(
      child: SizedBox.square(dimension: size, child: artwork),
    );
  }
}

class _MenuSymbolPainter extends CustomPainter {
  const _MenuSymbolPainter(this.kind, this.light, this.shade);

  final ResourceMapMenuArtworkKind kind;
  final Color light;
  final Color shade;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 36, size.height / 36);
    final path = Path();
    switch (kind) {
      case ResourceMapMenuArtworkKind.plan:
        path
          ..addOval(const Rect.fromLTWH(3, 24, 6, 6))
          ..moveTo(9, 27)
          ..lineTo(16, 27)
          ..lineTo(23, 20)
          ..lineTo(23, 5)
          ..lineTo(32, 9)
          ..lineTo(23, 13);
      case ResourceMapMenuArtworkKind.checklist:
        path
          ..moveTo(4, 10)
          ..lineTo(7, 13)
          ..lineTo(12, 7)
          ..moveTo(18, 10)
          ..lineTo(31, 10)
          ..moveTo(4, 24)
          ..lineTo(7, 27)
          ..lineTo(12, 21)
          ..moveTo(18, 24)
          ..lineTo(31, 24);
      case ResourceMapMenuArtworkKind.saved:
        for (var point = 0; point < 10; point++) {
          final angle = -math.pi / 2 + point * math.pi / 5;
          final radius = point.isEven ? 14.0 : 6.5;
          final x = 18 + math.cos(angle) * radius;
          final y = 18 + math.sin(angle) * radius;
          if (point == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        canvas.drawPath(path, Paint()..color = shade.withValues(alpha: .28));
      case ResourceMapMenuArtworkKind.income:
        path
          ..addOval(const Rect.fromLTWH(4, 12, 16, 6))
          ..moveTo(4, 15)
          ..lineTo(4, 27)
          ..cubicTo(4, 32, 20, 32, 20, 27)
          ..lineTo(20, 15)
          ..moveTo(4, 21)
          ..cubicTo(4, 26, 20, 26, 20, 21)
          ..moveTo(27, 22)
          ..lineTo(27, 5)
          ..moveTo(22, 10)
          ..lineTo(27, 5)
          ..lineTo(32, 10);
      case ResourceMapMenuArtworkKind.connections:
        path
          ..addOval(const Rect.fromLTWH(3, 4, 7, 7))
          ..addOval(const Rect.fromLTWH(26, 4, 7, 7))
          ..addOval(const Rect.fromLTWH(14.5, 25, 7, 7))
          ..moveTo(10, 7.5)
          ..lineTo(26, 7.5)
          ..moveTo(8, 11)
          ..lineTo(16, 25)
          ..moveTo(28, 11)
          ..lineTo(20, 25);
      case ResourceMapMenuArtworkKind.invest:
        path
          ..moveTo(28, 23)
          ..lineTo(28, 33)
          ..moveTo(23, 28)
          ..lineTo(33, 28);
      case ResourceMapMenuArtworkKind.houses:
        path
          ..moveTo(3, 17)
          ..lineTo(13, 8)
          ..lineTo(23, 17)
          ..moveTo(6, 15)
          ..lineTo(6, 30)
          ..lineTo(20, 30)
          ..lineTo(20, 15)
          ..moveTo(11, 30)
          ..lineTo(11, 22)
          ..lineTo(15, 22)
          ..lineTo(15, 30)
          ..moveTo(18, 9)
          ..lineTo(24, 4)
          ..lineTo(33, 12)
          ..moveTo(30, 10)
          ..lineTo(30, 27)
          ..lineTo(25, 27)
          ..moveTo(25, 15)
          ..lineTo(25, 18);
      case ResourceMapMenuArtworkKind.royalWorkshop:
        path
          ..moveTo(5, 30)
          ..lineTo(5, 9)
          ..lineTo(10, 9)
          ..lineTo(10, 14)
          ..lineTo(15, 14)
          ..lineTo(15, 4)
          ..lineTo(21, 4)
          ..lineTo(21, 14)
          ..lineTo(26, 14)
          ..lineTo(26, 9)
          ..lineTo(31, 9)
          ..lineTo(31, 30)
          ..close()
          ..addRect(const Rect.fromLTWH(15, 22, 6, 8));
      case ResourceMapMenuArtworkKind.scan:
        for (final (x, y, dx, dy) in [
          (5.0, 5.0, 1.0, 1.0),
          (31.0, 5.0, -1.0, 1.0),
          (5.0, 31.0, 1.0, -1.0),
          (31.0, 31.0, -1.0, -1.0),
        ]) {
          path
            ..moveTo(x, y + dy * 7)
            ..lineTo(x, y)
            ..lineTo(x + dx * 7, y);
        }
        path
          ..moveTo(5, 18)
          ..lineTo(31, 18);
      case ResourceMapMenuArtworkKind.materials:
      case ResourceMapMenuArtworkKind.findNodes:
        break;
    }
    // A small dark under-edge and restrained silver face match game UI symbols
    // without turning them into illustrated objects or tinted button tiles.
    canvas.drawPath(
      path.shift(const Offset(0, .6)),
      Paint()
        ..color = const Color(0xA6000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [light, Color.lerp(light, shade, .4)!],
        ).createShader(const Rect.fromLTWH(0, 0, 36, 36))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MenuSymbolPainter old) =>
      old.kind != kind || old.light != light || old.shade != shade;
}
