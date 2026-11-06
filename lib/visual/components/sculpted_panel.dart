import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/overlays/anchored_popover.dart';
import '../visual.dart';

/// Approved recessed reading face and sculpted header. Theme identity belongs
/// here, not in individual Planner workflows. No new appearance preference.
class SculptedPanel extends StatelessWidget {
  const SculptedPanel({
    required this.title,
    required this.onClose,
    required this.body,
    this.footer,
    super.key,
  });
  final String title;
  final VoidCallback onClose;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final p = spec.palette;
    final sakura = spec.isSakuraNightGarden;
    final edge = sakura ? const Color(0xFF66545B) : p.trim;
    final radius = BorderRadius.circular(spec.isIlluminatedLedger ? 2 : 7);
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: edge),
          borderRadius: radius,
          boxShadow: spec.materials.highShadow,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: sakura
                ? const [Color(0xFF151317), Color(0xFF20191F)]
                : [p.surfaceInset, p.surface],
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: DefaultTextStyle(
            style: spec.typography.body.copyWith(
              color: p.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  key: const ValueKey('sculpted-panel-header'),
                  constraints: const BoxConstraints(minHeight: 54),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: sakura
                          ? const [
                              Color(0xFF3F323E),
                              Color(0xFF2A232D),
                              Color(0xFF201B22),
                            ]
                          : [p.surfaceRaised, p.surface, p.surfaceInset],
                      stops: const [0, .48, 1],
                    ),
                    border: Border(bottom: BorderSide(color: edge)),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _SculptedHeader(
                              sakura ? const Color(0xFFAA8394) : p.specular,
                              p.shadow,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: AnchoredPopoverDragRegion(
                                child: Text(
                                  title,
                                  style: spec.typography.body.copyWith(
                                    color: p.text,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            AppButton(
                              role: AppButtonRole.optionPill,
                              minimumSize: const Size(42, 40),
                              padding: EdgeInsets.zero,
                              semanticLabel: 'Close $title',
                              onPressed: onClose,
                              child: const AppVectorGlyph('close', size: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('sculpted-panel-scroll'),
                    child: body,
                  ),
                ),
                if (footer != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: footer!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SculptedRail extends StatelessWidget {
  const SculptedRail({
    required this.label,
    required this.child,
    this.width = 94,
    this.centerLabel = false,
    super.key,
  });
  final String label;
  final Widget child;
  final double width;
  final bool centerLabel;
  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final p = spec.palette;
    final rail = Container(
      key: ValueKey('sculpted-rail:$label'),
      alignment: centerLabel ? Alignment.center : null,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: spec.isSakuraNightGarden
              ? const [Color(0xFF161217), Color(0xFF251D25)]
              : [p.surfaceInset, p.surfaceRaised],
        ),
        border: Border(right: BorderSide(color: p.trim.withValues(alpha: .45))),
      ),
      child: Text(
        label,
        textAlign: centerLabel ? TextAlign.center : TextAlign.start,
        style: spec.typography.meta.copyWith(
          color: p.textMuted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(14) > 21) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [rail, child],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: width, child: rail),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}

class _SculptedHeader extends CustomPainter {
  const _SculptedHeader(this.light, this.shadow);
  final Color light;
  final Color shadow;
  @override
  void paint(Canvas canvas, Size size) {
    final top = Rect.fromLTWH(0, 0, size.width, 15);
    final bottom = Rect.fromLTWH(0, size.height - 9, size.width, 9);
    canvas.drawRect(
      top,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [light.withValues(alpha: .15), light.withValues(alpha: 0)],
        ).createShader(top),
    );
    canvas.drawRect(
      bottom,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [shadow.withValues(alpha: 0), shadow.withValues(alpha: .5)],
        ).createShader(bottom),
    );
    canvas.drawLine(
      Offset(0, size.height - 2.5),
      Offset(size.width, size.height - 2.5),
      Paint()
        ..color = light.withValues(alpha: .44)
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      const Offset(7, 1.5),
      Offset(size.width - 7, 1.5),
      Paint()
        ..color = light.withValues(alpha: .4)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SculptedHeader old) =>
      old.light != light || old.shadow != shadow;
}
