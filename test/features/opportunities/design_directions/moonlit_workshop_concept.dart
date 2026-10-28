import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'concept_support.dart';

/// A static native-Flutter design study. No app state or live prices are used.
class MoonlitWorkshopConcept extends StatelessWidget {
  const MoonlitWorkshopConcept({required this.itemIcon, super.key});

  final ConceptItemIcon itemIcon;

  static const _ink = Color(0xFFF0F3FF);
  static const _muted = Color(0xFFAAB8D2);
  static const _silver = Color(0xFFC8D7F9);

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF080E20),
    child: CustomPaint(
      painter: const _MoonlightBackdrop(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const SizedBox(height: 24),
            _toolbar(),
            const SizedBox(height: 24),
            Row(
              children: [
                Text('Listing prices', style: conceptType(14, _muted)),
                const SizedBox(width: 12),
                Container(width: 3, height: 3, color: _muted),
                const SizedBox(width: 12),
                Text('Main item only', style: conceptType(14, _muted)),
                const SizedBox(width: 6),
                const Icon(Icons.info_outline, size: 16, color: _muted),
                const Spacer(),
                Text('Prices from 8.9. 18:00', style: conceptType(14, _muted)),
                const SizedBox(width: 24),
                Text(
                  'Design preview · Example prices',
                  style: conceptType(14, _silver),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = (constraints.maxWidth - 20) / 2;
                  final height = (constraints.maxHeight - 36) / 3;
                  return Wrap(
                    spacing: 20,
                    runSpacing: 18,
                    children: [
                      for (
                        var index = 0;
                        index < conceptRecipes.length;
                        index++
                      )
                        SizedBox(
                          width: width,
                          height: height,
                          child: _RecipeTicket(
                            recipe: conceptRecipes[index],
                            itemIcon: itemIcon,
                            brighter: index == 0,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _header() => SizedBox(
    height: 60,
    child: Row(
      children: [
        Container(
          width: 4,
          height: 30,
          decoration: BoxDecoration(
            color: _silver,
            borderRadius: BorderRadius.circular(2),
            boxShadow: const [
              BoxShadow(color: Color(0x807B9AFF), blurRadius: 16),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Text(
          'Opportunities',
          style: conceptType(28, _ink, weight: FontWeight.w700),
        ),
        const SizedBox(width: 38),
        _tab('Crafting', selected: true),
        const SizedBox(width: 8),
        _tab('Exchanges'),
        const Spacer(),
        _control('Refresh', icon: Icons.refresh_rounded, bright: true),
        const SizedBox(width: 16),
        _control('Market · EU', icon: Icons.tune_rounded),
      ],
    ),
  );

  Widget _tab(String text, {bool selected = false}) => Container(
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      gradient: selected
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xB52C426B), Color(0x50232B4C)],
            )
          : null,
      border: selected
          ? const Border(bottom: BorderSide(color: _silver, width: 2))
          : null,
    ),
    child: Text(
      text,
      style: conceptType(
        16,
        selected ? _ink : _muted,
        weight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    ),
  );

  Widget _toolbar() => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: const Color(0xB3081127),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF293954)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x60010209),
          blurRadius: 22,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Row(
      children: [
        _control('Cooking', selected: true),
        const SizedBox(width: 4),
        _control('Alchemy'),
        const SizedBox(width: 4),
        _control('Processing'),
        const SizedBox(width: 18),
        Container(width: 1, height: 26, color: const Color(0xFF354461)),
        const SizedBox(width: 18),
        Container(
          width: 242,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF080F21),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xFF34415C)),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, size: 20, color: _muted),
              const SizedBox(width: 10),
              Text('Find a recipe', style: conceptType(16, _muted)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _control('Filters', icon: Icons.tune_rounded),
        const Spacer(),
        _control('Profit', selected: true),
        const SizedBox(width: 4),
        _control('Demand'),
        const SizedBox(width: 14),
        _control('Mastery · 0'),
      ],
    ),
  );

  Widget _control(
    String label, {
    IconData? icon,
    bool selected = false,
    bool bright = false,
  }) => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 15),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(7),
      gradient: bright
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE5EBFE), Color(0xFFA1B6E8)],
            )
          : selected
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF3D517F), Color(0xFF293757)],
            )
          : null,
      border: Border.all(
        color: bright
            ? const Color(0xFFF0F4FF)
            : selected
            ? const Color(0xFF7D96CA)
            : Colors.transparent,
      ),
      boxShadow: bright
          ? const [
              BoxShadow(color: Color(0x30566FBC), blurRadius: 20),
              BoxShadow(
                color: Color(0x60000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ]
          : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 19,
            color: bright ? const Color(0xFF152540) : _silver,
          ),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: conceptType(
            16,
            bright ? const Color(0xFF152540) : _ink,
            weight: selected || bright ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _RecipeTicket extends StatelessWidget {
  const _RecipeTicket({
    required this.recipe,
    required this.itemIcon,
    required this.brighter,
  });

  final ConceptRecipe recipe;
  final ConceptItemIcon itemIcon;
  final bool brighter;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _TicketMetal(brighter: brighter),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 23, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // The item keeps its own original artwork and frame.
              itemIcon(recipe.name, 64),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      style: conceptType(
                        20,
                        const Color(0xFFF2F5FF),
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      recipe.scope,
                      style: conceptType(14, const Color(0xFFADBDD9)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0x502E426E),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF53698C)),
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: Color(0xFFD7E4FF),
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0x806779A4),
                  Color(0x304D5F88),
                  Color(0x106779A4),
                ],
              ),
            ),
          ),
          const SizedBox(height: 17),
          Row(
            children: [
              Expanded(
                child: _metric(
                  'Profit',
                  recipe.profit,
                  recipe.profitable
                      ? const Color(0xFF87E2B5)
                      : const Color(0xFFFF9D9D),
                ),
              ),
              Expanded(
                child: _metric(
                  'Market',
                  recipe.market,
                  recipe.demand
                      ? const Color(0xFFFF9D9D)
                      : const Color(0xFFD3DDED),
                ),
              ),
              Expanded(
                child: _metric(
                  'Investment',
                  recipe.cost,
                  const Color(0xFFD3DDED),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _metric(String label, String value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: conceptType(14, const Color(0xFFAEBBD3))),
      const SizedBox(height: 6),
      Text(value, style: conceptType(20, color, weight: FontWeight.w700)),
    ],
  );
}

class _TicketMetal extends CustomPainter {
  const _TicketMetal({required this.brighter});
  final bool brighter;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = Path()
      ..moveTo(10, 0)
      ..lineTo(size.width - 22, 0)
      ..lineTo(size.width, 22)
      ..lineTo(size.width, size.height - 10)
      ..quadraticBezierTo(size.width, size.height, size.width - 10, size.height)
      ..lineTo(22, size.height)
      ..lineTo(0, size.height - 22)
      ..lineTo(0, 10)
      ..quadraticBezierTo(0, 0, 10, 0)
      ..close();
    canvas.drawShadow(shape, const Color(0xFF00030E), 12, false);
    canvas.drawPath(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: brighter
              ? const [Color(0xFF283F6A), Color(0xFF1B294B), Color(0xFF121D37)]
              : const [Color(0xFF223453), Color(0xFF172440), Color(0xFF111B31)],
          stops: const [0, .45, 1],
        ).createShader(rect),
    );
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF91A9D6), Color(0xFF394F76), Color(0xFF233654)],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawRect(
      Rect.fromLTWH(1, 1, size.width - 23, 2),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x70D5E3FF), Color(0x125D78B0), Color(0x005D78B0)],
        ).createShader(rect),
    );
    final sheen = Path()
      ..moveTo(size.width * .64, 0)
      ..lineTo(size.width * .81, 0)
      ..lineTo(size.width * .54, size.height)
      ..lineTo(size.width * .40, size.height)
      ..close();
    canvas.drawPath(sheen, Paint()..color = const Color(0x052D5FF4));
    canvas.drawCircle(
      const Offset(54, 46),
      78,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x285E83D2), Color(0x005E83D2)],
        ).createShader(const Rect.fromLTWH(-24, -32, 156, 156)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TicketMetal oldDelegate) =>
      brighter != oldDelegate.brighter;
}

class _MoonlightBackdrop extends CustomPainter {
  const _MoonlightBackdrop();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF182A46), Color(0xFF101B33), Color(0xFF090D20)],
          stops: [0, .4, 1],
        ).createShader(bounds),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.8, -.95),
          radius: .75,
          colors: const [Color(0x604C487A), Color(0x005B518F)],
        ).createShader(bounds),
    );
    final line = Paint()
      ..color = const Color(0x163A609A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final center = Offset(size.width * 1.01, -size.height * .09);
    for (final radius in [240.0, 340.0, 480.0]) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        0,
        math.pi * 2,
        false,
        line,
      );
    }
    canvas.drawLine(
      const Offset(32, 0),
      Offset(size.width - 32, 0),
      Paint()
        ..strokeWidth = 2
        ..shader = const LinearGradient(
          colors: [Color(0x00C0D4FF), Color(0x908AAEEB), Color(0x00C0D4FF)],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(covariant _MoonlightBackdrop oldDelegate) => false;
}
