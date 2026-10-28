import 'package:flutter/material.dart';

import 'resource_map_chrome_theme.dart';
import 'resource_map_menu_artwork.dart';

/// A persistent, content-sized instrument rail. The map and its controllers
/// remain mounted while the adjacent task changes.
class ResourceMapFieldDesk extends StatelessWidget {
  const ResourceMapFieldDesk({
    required this.search,
    required this.navigation,
    required this.onHome,
    this.controls,
    super.key,
  });

  final Widget search;
  final Widget navigation;
  final Widget? controls;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return ResourceMapReadingPlane(
      child: RepaintBoundary(
        child: CustomPaint(
          foregroundPainter: ResourceMapInstrumentEdge(
            light: chrome.accent,
            opacity: chrome.materialOpacity,
            radius: 8,
            quiet: true,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: _railBackplate(chrome),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: .20 * chrome.materialOpacity,
                  ),
                  offset: const Offset(0, 2),
                  blurRadius: 2,
                ),
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: .12 * chrome.materialOpacity,
                  ),
                  offset: const Offset(0, 5),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      key: const ValueKey('resource-map-field-desk-home'),
                      onTap: onHome,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                        child: Row(
                          children: [
                            const ResourceMapMenuArtwork(
                              kind: ResourceMapMenuArtworkKind.plan,
                              size: 32,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Resource Map',
                                style: TextStyle(
                                  fontFamily: 'Georgia',
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: chrome.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    CustomPaint(
                      foregroundPainter: ResourceMapInstrumentEdge(
                        light: chrome.accent,
                        opacity: chrome.materialOpacity,
                        radius: 9,
                        inset: true,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: chrome.controlInset,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: search,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: ClipRect(
                        clipper: const ResourceMapRailShadowClipper(),
                        child: SingleChildScrollView(
                          key: const ValueKey('resource-map-field-desk-scroll'),
                          clipBehavior: Clip.none,
                          child: navigation,
                        ),
                      ),
                    ),
                    if (controls != null) ...[
                      const SizedBox(height: 8),
                      Divider(height: 1, color: chrome.softOutline),
                      const SizedBox(height: 6),
                      controls!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

LinearGradient _railBackplate(ResourceMapChromeThemeData chrome) {
  final source = chrome.surfaceGradient;
  final base = chrome.chromeBase.withValues(alpha: 1);
  final inset = chrome.controlInset.withValues(alpha: 1);
  return LinearGradient(
    begin: source.begin,
    end: source.end,
    stops: source.stops,
    tileMode: source.tileMode,
    transform: source.transform,
    colors: [
      for (var i = 0; i < source.colors.length; i++)
        Color.lerp(
          base,
          inset,
          .22 + .30 * i / (source.colors.length - 1),
        )!.withValues(alpha: source.colors[i].a),
    ],
  );
}

/// Cards may cast into the rail's existing 8px gutters, never over its header
/// or footer. This alters only the paint clip, not the viewport or scrolling.
class ResourceMapRailShadowClipper extends CustomClipper<Rect> {
  const ResourceMapRailShadowClipper();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-8, 0, size.width + 8, size.height);

  @override
  bool shouldReclip(covariant ResourceMapRailShadowClipper oldClipper) => false;
}

/// A stationary reflection gives the instrument a thin glass edge without
/// adding a blur pass or a continuously repainted effect above the map.
class ResourceMapInstrumentEdge extends CustomPainter {
  const ResourceMapInstrumentEdge({
    required this.light,
    required this.opacity,
    this.radius = 12,
    this.inset = false,
    this.quiet = false,
  });

  final Color light;
  final double opacity;
  final double radius;
  final bool inset;
  final bool quiet;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(.5);
    if (quiet) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius - .5)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              light.withValues(alpha: .20 * opacity),
              light.withValues(alpha: .05 * opacity),
              Colors.black.withValues(alpha: .30 * opacity),
            ],
            stops: const [0, .35, 1],
          ).createShader(rect),
      );
      return;
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius - .5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: inset ? Alignment.bottomRight : Alignment.topLeft,
          end: inset ? Alignment.topLeft : Alignment.bottomRight,
          colors: [
            light.withValues(alpha: .85 * opacity),
            light.withValues(alpha: .17 * opacity),
            Colors.black.withValues(alpha: .70 * opacity),
          ],
          stops: const [0, .4, 1],
        ).createShader(rect),
    );
    final inner = rect.deflate(1.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        inner,
        Radius.circular((radius - 2).clamp(0, 30)),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: inset ? Alignment.bottomCenter : Alignment.topCenter,
          end: inset ? Alignment.topCenter : Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: .16 * opacity),
            Colors.transparent,
            Colors.black.withValues(alpha: .32 * opacity),
          ],
          stops: const [0, .35, 1],
        ).createShader(inner),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant ResourceMapInstrumentEdge oldDelegate) =>
      light != oldDelegate.light ||
      opacity != oldDelegate.opacity ||
      radius != oldDelegate.radius ||
      inset != oldDelegate.inset ||
      quiet != oldDelegate.quiet;
}

/// The original item artwork sits inside a small inset, never a recolored icon.
class ResourceMapArtworkMount extends StatelessWidget {
  const ResourceMapArtworkMount({
    required this.child,
    required this.size,
    super.key,
  });

  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final top = chrome.chromeRaised.withValues(alpha: 1);
    final bottom = chrome.controlInset.withValues(alpha: 1);
    final light = chrome.brightness == Brightness.light;
    return CustomPaint(
      foregroundPainter: ResourceMapArtworkMountEdge(
        light: chrome.accent,
        edge: chrome.readingOutline,
        accent: chrome.finishAccent,
        opacity: chrome.materialOpacity,
        lightSurface: light,
      ),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: .22 * chrome.materialOpacity,
              ),
              offset: const Offset(0, 1),
              blurRadius: 2,
            ),
          ],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(
                bottom,
                Colors.black,
                light ? .04 : .22,
              )!.withValues(alpha: .86 * chrome.materialOpacity),
              Color.lerp(
                bottom,
                top,
                .25,
              )!.withValues(alpha: .761 * chrome.materialOpacity),
              Color.lerp(
                bottom,
                top,
                .58,
              )!.withValues(alpha: .68 * chrome.materialOpacity),
            ],
            stops: const [0, .55, 1],
          ),
        ),
        child: child,
      ),
    );
  }
}

/// The same coloured rim and recessed contact cut as the item mounts in
/// Opportunities. All paint stays inside the existing artwork square.
class ResourceMapArtworkMountEdge extends CustomPainter {
  const ResourceMapArtworkMountEdge({
    required this.light,
    required this.edge,
    required this.accent,
    required this.opacity,
    required this.lightSurface,
  });

  final Color light, edge, accent;
  final double opacity;
  final bool lightSurface;

  Color fade(Color color, int alpha) =>
      color.withValues(alpha: alpha / 255 * opacity);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide < 8) return;
    final rect = (Offset.zero & size).deflate(.5);
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(3.5));
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            fade(Colors.black, lightSurface ? 110 : 180),
            fade(edge, 45),
            fade(light, 165),
          ],
          stops: const [0, .5, 1],
        ).createShader(rect),
    );
    canvas.drawRRect(
      shape.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            fade(Colors.black, lightSurface ? 65 : 120),
            fade(Colors.black, 0),
            fade(light, 40),
          ],
          stops: const [0, .5, 1],
        ).createShader(rect),
    );
    final underline = Rect.fromLTWH(
      size.width * .25,
      size.height - 2,
      size.width * .5,
      1,
    );
    canvas.drawRect(
      underline,
      Paint()
        ..shader = LinearGradient(
          colors: [fade(accent, 0), fade(accent, 115), fade(accent, 0)],
        ).createShader(underline),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant ResourceMapArtworkMountEdge oldDelegate) =>
      light != oldDelegate.light ||
      edge != oldDelegate.edge ||
      accent != oldDelegate.accent ||
      opacity != oldDelegate.opacity ||
      lightSurface != oldDelegate.lightSurface;
}
