import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../components/retained_asset_image.dart';
import 'ledger_spec.dart';

/// A retained, noninteractive leather-and-vellum book background.
class LedgerBackdrop extends StatelessWidget {
  const LedgerBackdrop({
    this.child,
    this.showSidebarFold = true,
    this.showCenterFold = true,
    this.showMarginalia = true,
    this.centerFoldX,
    this.centerFoldRatio = IlluminatedLedgerSpec.defaultCenterFoldRatio,
    this.centerFoldWidth = 30,
    super.key,
  });

  final Widget? child;
  final bool showSidebarFold;
  final bool showCenterFold;
  final bool showMarginalia;
  final double? centerFoldX;
  final double centerFoldRatio;
  final double centerFoldWidth;

  static const Key leatherKey = ValueKey<String>('ledger-leather-texture');
  static const Key vellumKey = ValueKey<String>('ledger-vellum-texture');
  static const Key marginaliaKey = ValueKey<String>('ledger-marginalia');
  static const Key coverGradientKey = ValueKey<String>('ledger-cover-gradient');
  static const Key leatherFailureKey = ValueKey<String>(
    'ledger-leather-asset-failure',
  );
  static const Key vellumFailureKey = ValueKey<String>(
    'ledger-vellum-asset-failure',
  );
  static const Key marginaliaFailureKey = ValueKey<String>(
    'ledger-marginalia-asset-failure',
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final size = constraints.biggest;
      final page = ledgerPageRect(size);
      final hasPage = page.width > 0 && page.height > 0;
      final marginaliaWidth = math.min(198.0, page.width * 0.22);
      final marginaliaHeight = math.min(292.0, page.height * 0.42);

      return Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    const DecoratedBox(
                      key: coverGradientKey,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            Color(0xFF06182C),
                            Color(0xFF123E68),
                            Color(0xFF071A2E),
                          ],
                          stops: <double>[0, 0.43, 1],
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: 0.54,
                      child: RetainedAssetImage(
                        assetPath: IlluminatedLedgerSpec.leatherAssetPath,
                        assetLabel: 'Illuminated Ledger navy leather',
                        imageKey: leatherKey,
                        failureKey: leatherFailureKey,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        background: const Color(0xFF071A2E),
                      ),
                    ),
                    CustomPaint(painter: LedgerPageBasePainter()),
                    if (hasPage)
                      Positioned.fromRect(
                        rect: page,
                        child: ClipRect(
                          child: Opacity(
                            opacity: 0.34,
                            child: RetainedAssetImage(
                              assetPath: IlluminatedLedgerSpec.vellumAssetPath,
                              assetLabel: 'Illuminated Ledger vellum',
                              imageKey: vellumKey,
                              failureKey: vellumFailureKey,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.high,
                              background: const Color(0xFFE8D2A3),
                              foreground: const Color(0xFF352516),
                            ),
                          ),
                        ),
                      ),
                    CustomPaint(
                      painter: LedgerBookDetailPainter(
                        showSidebarFold: showSidebarFold,
                        showCenterFold: showCenterFold,
                        centerFoldX: centerFoldX,
                        centerFoldRatio: centerFoldRatio,
                        centerFoldWidth: centerFoldWidth,
                      ),
                    ),
                    if (showMarginalia &&
                        marginaliaWidth >= 40 &&
                        marginaliaHeight >= 60)
                      Positioned(
                        key: marginaliaKey,
                        left: page.left + 22,
                        bottom: size.height - page.bottom + 18,
                        width: marginaliaWidth,
                        height: marginaliaHeight,
                        child: Opacity(
                          opacity: 0.68,
                          child: RetainedAssetImage(
                            assetPath:
                                IlluminatedLedgerSpec.marginaliaAssetPath,
                            assetLabel: 'Illuminated Ledger marginalia',
                            failureKey: marginaliaFailureKey,
                            fit: BoxFit.contain,
                            alignment: Alignment.bottomLeft,
                            filterQuality: FilterQuality.high,
                            background: const Color(0xFFE8D2A3),
                            foreground: const Color(0xFF352516),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (child case final content?) Positioned.fill(child: content),
        ],
      );
    },
  );
}

Rect ledgerPageRect(Size size) {
  if (!size.width.isFinite || !size.height.isFinite) return Rect.zero;
  final insets = IlluminatedLedgerSpec.pageInsets;
  return Rect.fromLTWH(
    insets.left,
    insets.top,
    math.max(0, size.width - insets.horizontal),
    math.max(0, size.height - insets.vertical),
  );
}

/// Paints the cover rules, page shadow, and base vellum sheet.
class LedgerPageBasePainter extends CustomPainter {
  const LedgerPageBasePainter();

  static const List<Color> pageGradientColors = <Color>[
    Color(0xFFCFAF73),
    Color(0xFFE6CE98),
    Color(0xFFF1E0B7),
    Color(0xFFE9D3A2),
    Color(0xFFC9A96F),
  ];
  static const List<double> pageGradientStops = <double>[
    0,
    0.08,
    0.32,
    0.73,
    1,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final page = ledgerPageRect(size);
    if (page.isEmpty) return;

    canvas.drawRect(
      Rect.fromLTWH(
        4,
        4,
        math.max(0, size.width - 8),
        math.max(0, size.height - 8),
      ),
      Paint()
        ..color = const Color(0xFF030F1E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        9.5,
        9.5,
        math.max(0, size.width - 19),
        math.max(0, size.height - 19),
      ),
      Paint()
        ..color = const Color(0xFFC49B42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        13.5,
        13.5,
        math.max(0, size.width - 27),
        math.max(0, size.height - 27),
      ),
      Paint()
        ..color = const Color(0x9E7E6A2E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    final shadow = Paint()
      ..color = const Color(0x66352516)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawRect(page.shift(const Offset(0, 5)), shadow);

    final pagePaint = Paint()
      ..shader = ui.Gradient.linear(
        page.topLeft,
        page.bottomRight,
        pageGradientColors,
        pageGradientStops,
      );
    canvas.drawRect(page, pagePaint);
  }

  @override
  bool shouldRepaint(covariant LedgerPageBasePainter oldDelegate) => false;
}

/// Deterministic page patina, fibres, folds, and book tooling.
class LedgerBookDetailPainter extends CustomPainter {
  const LedgerBookDetailPainter({
    required this.showSidebarFold,
    required this.showCenterFold,
    required this.centerFoldX,
    required this.centerFoldRatio,
    required this.centerFoldWidth,
  });

  final bool showSidebarFold;
  final bool showCenterFold;
  final double? centerFoldX;
  final double centerFoldRatio;
  final double centerFoldWidth;

  static const Offset pageGlowRelativeCenter = Offset(0.48, 0.36);
  static const double pageGlowRadiusX = 0.82;
  static const double pageGlowRadiusY = 0.82;
  static const double sidebarFoldWidth = 13;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final page = ledgerPageRect(size);
    if (page.isEmpty) return;

    canvas.save();
    canvas.clipRect(page);
    _drawPageGlow(canvas, page);
    _drawStains(canvas, page);
    _drawFibres(canvas, page);
    if (showSidebarFold) {
      _drawFold(
        canvas,
        page,
        IlluminatedLedgerSpec.referenceSidebarFoldX
            .clamp(page.left + 18, page.right - 18)
            .toDouble(),
        sidebarFoldWidth,
      );
    }
    if (showCenterFold) {
      final desired =
          centerFoldX ?? size.width * centerFoldRatio.clamp(0.2, 0.8);
      _drawFold(
        canvas,
        page,
        desired.clamp(page.left + 24, page.right - 24).toDouble(),
        centerFoldWidth.clamp(8, 48).toDouble(),
      );
    }
    canvas.restore();

    _drawPageEdges(canvas, page);
    _drawCornerTooling(canvas, size);
  }

  void _drawPageGlow(Canvas canvas, Rect page) {
    final center = Offset(
      page.left + page.width * pageGlowRelativeCenter.dx,
      page.top + page.height * pageGlowRelativeCenter.dy,
    );
    final radiusX = page.width * pageGlowRadiusX;
    final radiusY = page.height * pageGlowRadiusY;
    if (radiusX <= 0 || radiusY <= 0) return;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(radiusX, radiusY);
    final paint = Paint()
      ..shader = ui.Gradient.radial(Offset.zero, 1, const <Color>[
        Color(0x35FFF9E6),
        Color(0x00FFF9E6),
      ]);
    canvas.drawRect(
      Rect.fromLTRB(
        -pageGlowRelativeCenter.dx / pageGlowRadiusX,
        -pageGlowRelativeCenter.dy / pageGlowRadiusY,
        (1 - pageGlowRelativeCenter.dx) / pageGlowRadiusX,
        (1 - pageGlowRelativeCenter.dy) / pageGlowRadiusY,
      ),
      paint,
    );
    canvas.restore();
  }

  void _drawStains(Canvas canvas, Rect page) {
    const stains = <(double, double, double, double, int)>[
      (0.035, 0.12, 58, 104, 18),
      (0.18, 0.94, 128, 34, 14),
      (0.47, 0.035, 150, 28, 11),
      (0.76, 0.965, 170, 35, 13),
      (0.975, 0.18, 46, 126, 17),
      (0.985, 0.82, 64, 116, 12),
    ];
    for (final stain in stains) {
      final center = Offset(
        page.left + page.width * stain.$1,
        page.top + page.height * stain.$2,
      );
      final rect = Rect.fromCenter(
        center: center,
        width: stain.$3 * 2,
        height: stain.$4 * 2,
      );
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          center,
          math.max(stain.$3, stain.$4),
          <Color>[
            Color.fromARGB(stain.$5, 120, 75, 28),
            const Color(0x001E1208),
          ],
        );
      canvas.drawOval(rect, paint);
    }
  }

  void _drawFibres(Canvas canvas, Rect page) {
    final usableWidth = math.max(1, page.width.floor() - 20);
    final usableHeight = math.max(1, page.height.floor() - 20);
    final paint = Paint()
      ..color = const Color(0x16856A35)
      ..strokeWidth = 0.65
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 250; i++) {
      final x = page.left + 10 + ((i * 83 + i * i * 7) % usableWidth);
      final y = page.top + 10 + ((i * 47 + i * i * 13) % usableHeight);
      final length = 1.2 + (i % 7) * 0.62;
      final rise = (i % 5 - 2) * 0.22;
      canvas.drawLine(Offset(x, y), Offset(x + length, y + rise), paint);
    }
  }

  void _drawFold(Canvas canvas, Rect page, double x, double width) {
    final rect = Rect.fromLTWH(x - width / 2, page.top, width, page.height);
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        rect.centerLeft,
        rect.centerRight,
        const <Color>[
          Color(0x00B29154),
          Color(0x32573C1F),
          Color(0x4CFFF0C9),
          Color(0x28573C1F),
          Color(0x00B29154),
        ],
        const <double>[0, 0.34, 0.53, 0.7, 1],
      );
    canvas.drawRect(rect, paint);
    canvas.drawLine(
      Offset(x, page.top + 8),
      Offset(x, page.bottom - 8),
      Paint()
        ..color = const Color(0x269A742F)
        ..strokeWidth = 0.7,
    );
  }

  void _drawPageEdges(Canvas canvas, Rect page) {
    canvas.drawRect(
      page.deflate(0.75),
      Paint()
        ..color = const Color(0x8A765F3B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawRect(
      page.deflate(4),
      Paint()
        ..color = const Color(0x459A742F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7,
    );
  }

  void _drawCornerTooling(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xB8D6B45A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const inset = 18.0;
    const arm = 22.0;
    final corners = <(Offset, double, double)>[
      (const Offset(inset, inset), 1, 1),
      (Offset(size.width - inset, inset), -1, 1),
      (Offset(inset, size.height - inset), 1, -1),
      (Offset(size.width - inset, size.height - inset), -1, -1),
    ];
    for (final corner in corners) {
      final origin = corner.$1;
      final sx = corner.$2;
      final sy = corner.$3;
      final path = Path()
        ..moveTo(origin.dx, origin.dy + sy * arm)
        ..quadraticBezierTo(
          origin.dx,
          origin.dy,
          origin.dx + sx * arm,
          origin.dy,
        );
      canvas.drawPath(path, paint);
      canvas.drawCircle(origin.translate(sx * 7, sy * 7), 2.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant LedgerBookDetailPainter oldDelegate) =>
      oldDelegate.showSidebarFold != showSidebarFold ||
      oldDelegate.showCenterFold != showCenterFold ||
      oldDelegate.centerFoldX != centerFoldX ||
      oldDelegate.centerFoldRatio != centerFoldRatio ||
      oldDelegate.centerFoldWidth != centerFoldWidth;
}
