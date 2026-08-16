import 'package:flutter/material.dart';

import 'resource_map_chrome_theme.dart';

/// A single connected rail for the map's three viewport controls.
///
/// The parent decides where the rail is positioned and may provide the
/// surrounding `resource-map-zoom-controls` key during integration.
class ResourceMapZoomDock extends StatelessWidget {
  const ResourceMapZoomDock({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onShowFullWorld,
    super.key,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onShowFullWorld;

  static const double controlExtent = 44;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final isSakura =
        chrome.variant == ResourceMapChromeThemeVariant.sakuraCartographer;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Map zoom controls',
      child: Material(
        key: const ValueKey<String>('resource-map-zoom-dock-surface'),
        color: chrome.paperRaised,
        elevation: 2,
        shadowColor: isSakura
            ? const Color(0x330A1512)
            : chrome.idleShadow.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            isSakura ? 10 : chrome.toolRadius,
          ),
          side: BorderSide(color: chrome.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[chrome.graphiteHighlight, chrome.graphite],
            ),
          ),
          child: SizedBox(
            width: controlExtent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _ZoomDockControl(
                  key: const ValueKey<String>('resource-map-zoom-in'),
                  icon: Icons.add_rounded,
                  tooltip: 'Zoom in',
                  semanticLabel: 'Zoom in',
                  onPressed: onZoomIn,
                ),
                const _ZoomDockDivider(),
                _ZoomDockControl(
                  key: const ValueKey<String>('resource-map-zoom-out'),
                  icon: Icons.remove_rounded,
                  tooltip: 'Zoom out',
                  semanticLabel: 'Zoom out',
                  onPressed: onZoomOut,
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
    final isSakura =
        chrome.variant == ResourceMapChromeThemeVariant.sakuraCartographer;
    return Tooltip(
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
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _hovered || _focused
                          ? chrome.brassWash
                          : chrome.graphiteRaised,
                      borderRadius: BorderRadius.circular(
                        isSakura ? 6 : chrome.compactRadius,
                      ),
                      border: Border.all(
                        color: _hovered || _focused
                            ? chrome.brassLine
                            : chrome.softOutline,
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      size: 20,
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
      width: ResourceMapZoomDock.controlExtent,
      height: 1,
      child: ColoredBox(color: chrome.brassDeep),
    );
  }
}
