import 'package:flutter/material.dart';

import '../engine/map_camera.dart';
import 'resource_map_chrome_theme.dart';
import 'resource_map_field_desk.dart';
import 'resource_map_pill.dart';

/// A compact continuous zoom rail with a separate full-world reset.
class ResourceMapZoomDock extends StatelessWidget {
  const ResourceMapZoomDock({
    required this.cameraController,
    required this.onZoomChanged,
    required this.onShowFullWorld,
    super.key,
  });

  final BdoMapCameraController cameraController;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onShowFullWorld;

  static const double controlExtent = 44;
  static const double sliderExtent = 126;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final ghost = chrome.variant == ResourceMapChromeThemeVariant.ghostLedger;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Map zoom controls',
      child: Material(
        key: const ValueKey<String>('resource-map-zoom-dock-surface'),
        color: Colors.transparent,
        elevation: ghost ? 2 : 6,
        shadowColor: const Color(0x59000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ghost ? 8 : 12),
          side: BorderSide(color: chrome.softOutline.withValues(alpha: .82)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: resourceMapRaisedSurfaceGradient(
              chrome,
              LinearGradient(
                colors: [
                  chrome.fillAlpha(chrome.chromeBase, ghost ? .68 : .9),
                  chrome.fillAlpha(chrome.chromeBase, ghost ? .68 : .9),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          child: CustomPaint(
            foregroundPainter: ResourceMapInstrumentEdge(
              light: chrome.primary,
              opacity: chrome.materialOpacity,
              radius: ghost ? 8 : 12,
            ),
            child: SizedBox(
              width: controlExtent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AnimatedBuilder(
                    animation: cameraController,
                    builder: (context, _) {
                      final zoom = cameraController.camera.zoom
                          .clamp(
                            cameraController.minimumZoom,
                            cameraController.maximumZoom,
                          )
                          .toDouble();
                      return Semantics(
                        label: 'Map zoom level',
                        value: zoom.toStringAsFixed(1),
                        increasedValue: (zoom + .5)
                            .clamp(
                              cameraController.minimumZoom,
                              cameraController.maximumZoom,
                            )
                            .toStringAsFixed(1),
                        decreasedValue: (zoom - .5)
                            .clamp(
                              cameraController.minimumZoom,
                              cameraController.maximumZoom,
                            )
                            .toStringAsFixed(1),
                        child: SizedBox(
                          width: controlExtent,
                          height: sliderExtent,
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                activeTrackColor: chrome.primary,
                                inactiveTrackColor: chrome.softOutline
                                    .withValues(alpha: .72),
                                thumbColor: chrome.ink,
                                overlayColor: chrome.primary.withValues(
                                  alpha: .14,
                                ),
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                  elevation: 0,
                                  pressedElevation: 0,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 15,
                                ),
                                showValueIndicator: ShowValueIndicator.onDrag,
                                valueIndicatorColor: chrome.chromeRaised,
                                valueIndicatorTextStyle: TextStyle(
                                  color: chrome.ink,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: Slider(
                                key: const ValueKey<String>(
                                  'resource-map-zoom-slider',
                                ),
                                min: cameraController.minimumZoom,
                                max: cameraController.maximumZoom,
                                value: zoom,
                                label: zoom.toStringAsFixed(1),
                                onChanged: onZoomChanged,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const _ZoomDockDivider(),
                  _ZoomDockControl(
                    key: const ValueKey<String>('resource-map-full-world'),
                    icon: Icons.public_rounded,
                    tooltip: 'Show the full world',
                    semanticLabel: 'Show full world',
                    onPressed: onShowFullWorld,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomDockControl extends StatefulWidget {
  const _ZoomDockControl({
    required this.icon,
    required this.tooltip,
    required this.semanticLabel,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  State<_ZoomDockControl> createState() => _ZoomDockControlState();
}

class _ZoomDockControlState extends State<_ZoomDockControl> {
  var _hovered = false;
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return MapQuietTooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        child: ExcludeSemantics(
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: InkWell(
              onTap: widget.onPressed,
              onFocusChange: (focused) => setState(() => _focused = focused),
              focusColor: chrome.accent.withValues(alpha: .12),
              hoverColor: chrome.accent.withValues(alpha: .08),
              highlightColor: chrome.accent.withValues(alpha: .15),
              child: SizedBox.square(
                dimension: ResourceMapZoomDock.controlExtent,
                child: Center(
                  child: AnimatedContainer(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _hovered || _focused
                          ? chrome.primary.withValues(alpha: .14)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      widget.icon,
                      size: 18,
                      color: _hovered || _focused ? chrome.accent : chrome.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomDockDivider extends StatelessWidget {
  const _ZoomDockDivider();

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return SizedBox(
      key: const ValueKey<String>('resource-map-zoom-divider'),
      width: 18,
      height: 1,
      child: ColoredBox(color: chrome.softOutline.withValues(alpha: .55)),
    );
  }
}
