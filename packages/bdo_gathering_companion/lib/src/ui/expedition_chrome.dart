import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../widgets/spot_map.dart';
import 'theme.dart';

/// Reveals a changed stage without replacing its stateful editor or map.
class GatheringStageReveal extends StatefulWidget {
  const GatheringStageReveal({
    super.key,
    required this.stage,
    required this.child,
  });
  final int stage;
  final Widget child;

  @override
  State<GatheringStageReveal> createState() => _GatheringStageRevealState();
}

class _GatheringStageRevealState extends State<GatheringStageReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );
  late final CurvedAnimation _reveal = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _controller.value = 1;
  }

  @override
  void didUpdateWidget(GatheringStageReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stage != oldWidget.stage) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: .55, end: 1).animate(_reveal),
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, .012),
        end: Offset.zero,
      ).animate(_reveal),
      child: widget.child,
    ),
  );
}

/// A compact location masthead. The tile crop is decorative; the explicit map
/// button opens the actual navigable map with its area marker and attribution.
class GatheringSpotBanner extends StatelessWidget {
  const GatheringSpotBanner({
    super.key,
    required this.spot,
    required this.customName,
    required this.method,
    required this.methods,
    required this.onChange,
    required this.onMap,
    required this.active,
  });
  final Spot? spot;
  final String customName;
  final Method method;
  final List<Method> methods;
  final VoidCallback onChange, onMap;
  final bool active;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 640;
      final location = spot;
      final region = location?.region.trim() ?? '';
      final artwork = location?.icon.isNotEmpty == true
          ? location!.icon
          : method.icon;
      final identity = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: gold.withValues(alpha: .4)),
              color: const Color(0xCC101C25),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 12),
              ],
            ),
            child: GameIcon(
              artwork,
              size: compact ? 44 : 56,
              backgroundColor: Colors.transparent,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (region.isNotEmpty) ...[
                  Text(
                    region.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.8,
                      color: gold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  location?.displayName ?? customName,
                  style: TextStyle(
                    fontSize: compact ? 24 : 30,
                    height: 1.15,
                    letterSpacing: -.7,
                    color: ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    GlassArtworkWell(
                      tool: true,
                      child: GameIcon(
                        method.icon,
                        size: 28,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        location?.nodeName.isNotEmpty == true
                            ? '${method.label} · ${location!.nodeName}'
                            : method.label,
                        style: const TextStyle(fontSize: 13, color: ink),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
      final actions = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          GlassControl(
            child: IconButton(
              key: const ValueKey('change-spot'),
              onPressed: onChange,
              tooltip: 'Change spot',
              icon: const Icon(Icons.edit_location_alt_outlined, size: 21),
            ),
          ),
          if (location != null)
            GlassControl(
              child: IconButton(
                key: const ValueKey('show-chosen-spot-map'),
                onPressed: onMap,
                tooltip: 'Show on map',
                icon: const Icon(Icons.map_outlined, size: 21),
              ),
            ),
        ],
      );
      return DecoratedBox(
        key: const ValueKey('chosen-spot-banner'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: context.glass.panelShadows,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: const Color(0xFF1B3943)),
              ),
              if (location?.mapped == true && active)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: compact ? constraints.maxWidth : 460,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Colors.transparent, Colors.white],
                      stops: [0, .3],
                    ).createShader(bounds),
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: SpotMap(
                          key: const ValueKey('chosen-spot-atmosphere'),
                          spots: [location!],
                          selected: location,
                          methods: methods,
                          onSelect: (_) => onMap(),
                          preview: true,
                        ),
                      ),
                    ),
                  ),
                ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFA142631),
                        Color(0xE3142731),
                        Color(0x70304A50),
                      ],
                      stops: [0, .52, 1],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: gold.withValues(alpha: .24)),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(compact ? 18 : 24),
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          identity,
                          const SizedBox(height: 16),
                          actions,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: identity),
                          const SizedBox(width: 24),
                          actions,
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
