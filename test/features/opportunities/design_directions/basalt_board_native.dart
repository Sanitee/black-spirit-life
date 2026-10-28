import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'bold_concept_support.dart';
import 'concept_support.dart';

/// Static native preview only; all displayed amounts are example figures.
class BasaltBoardConcept extends StatelessWidget {
  const BasaltBoardConcept({super.key, required this.itemIcon});

  final ConceptItemIcon itemIcon;

  static const _text = Color(0xFFF0ECE5);
  static const _muted = Color(0xFFB0B0B1);
  static const _copper = Color(0xFFC79577);

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF0B0D10),
    child: CustomPaint(
      painter: const _BasaltGround(),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _rail(),
            const SizedBox(width: 30),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: 24),
                  _tools(),
                  const SizedBox(height: 22),
                  Text('Recipe', style: conceptType(16, _muted)),
                  const SizedBox(height: 14),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = (constraints.maxWidth - 22) / 2;
                        final height = (constraints.maxHeight - 40) / 3;
                        return Wrap(
                          spacing: 22,
                          runSpacing: 20,
                          children: [
                            for (final recipe in boldConceptRecipes)
                              SizedBox(
                                width: width,
                                height: height,
                                child: _BasaltTile(
                                  recipe: recipe,
                                  itemIcon: itemIcon,
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
          ],
        ),
      ),
    ),
  );

  Widget _rail() => SizedBox(
    width: 188,
    child: CustomPaint(
      painter: const _BasaltRail(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 22, 14, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 22),
              child: Row(
                children: [
                  Container(width: 25, height: 3, color: _copper),
                  const SizedBox(width: 5),
                  Container(width: 5, height: 3, color: _copper.withAlpha(90)),
                ],
              ),
            ),
            _railButton('Crafting', selected: true),
            const SizedBox(height: 10),
            _railButton('Exchanges'),
            const SizedBox(height: 28),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              height: 1,
              color: const Color(0xFF363637),
            ),
            const SizedBox(height: 24),
            _railButton('Cooking', category: true),
            const SizedBox(height: 8),
            _railButton('Alchemy', category: true, selected: true),
            const SizedBox(height: 8),
            _railButton('Processing', category: true),
          ],
        ),
      ),
    ),
  );

  Widget _railButton(
    String label, {
    bool selected = false,
    bool category = false,
  }) => Container(
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      gradient: selected && !category
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFD1A085), Color(0xFFA66D52)],
            )
          : selected
          ? const LinearGradient(colors: [Color(0xFF332B28), Color(0xFF232426)])
          : null,
      borderRadius: BorderRadius.circular(5),
      border: selected
          ? Border.all(
              color: category
                  ? const Color(0xFF775845)
                  : const Color(0xFFDFBAA0),
            )
          : null,
      boxShadow: selected && !category
          ? const [
              BoxShadow(
                color: Color(0xA0000000),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ]
          : null,
    ),
    child: Row(
      children: [
        if (category) ...[
          Container(
            width: 3,
            height: 16,
            color: selected ? _copper : const Color(0xFF53545A),
          ),
          const SizedBox(width: 12),
        ],
        Text(
          label,
          style: conceptType(
            16,
            selected && !category ? const Color(0xFF241713) : _text,
            weight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        if (selected && !category) ...[
          const Spacer(),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: Color(0xFF40271C),
          ),
        ],
      ],
    ),
  );

  Widget _header() => SizedBox(
    height: 86,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Opportunities',
                style: conceptType(28, _text, weight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                'Design preview · Example prices',
                style: conceptType(14, _muted),
              ),
            ],
          ),
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                _button('Market · EU'),
                const SizedBox(width: 10),
                _button('Refresh', icon: Icons.refresh_rounded),
              ],
            ),
            const SizedBox(height: 10),
            Text('Prices from 8.9. 18:00', style: conceptType(14, _muted)),
          ],
        ),
      ],
    ),
  );

  Widget _tools() => Row(
    children: [
      Container(
        width: 330,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1013),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF454447)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x407E8084),
              offset: Offset(0, 1),
              blurRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, size: 20, color: _muted),
            const SizedBox(width: 11),
            Text('Find a recipe', style: conceptType(16, _muted)),
          ],
        ),
      ),
      const SizedBox(width: 12),
      _button('Filters', icon: Icons.tune_rounded),
      const Spacer(),
      _button('Profit', selected: true),
      const SizedBox(width: 8),
      _button('Demand'),
    ],
  );

  Widget _button(String label, {IconData? icon, bool selected = false}) =>
      Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: selected
                ? const [Color(0xFFBD8E73), Color(0xFF91634E)]
                : const [Color(0xFF37383C), Color(0xFF23252A)],
          ),
          border: Border.all(
            color: selected ? const Color(0xFFD6B298) : const Color(0xFF545559),
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(color: Color(0xFF07080A), offset: Offset(0, 3)),
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 9,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 19, color: _text),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: conceptType(
                16,
                selected ? const Color(0xFF211610) : _text,
                weight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class _BasaltTile extends StatelessWidget {
  const _BasaltTile({required this.recipe, required this.itemIcon});

  final ConceptRecipe recipe;
  final ConceptItemIcon itemIcon;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: const _CutBasaltSlab(),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              itemIcon(recipe.name, 64),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  recipe.name,
                  style: conceptType(
                    20,
                    const Color(0xFFF0ECE5),
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 21,
                color: Color(0xFFC79577),
              ),
            ],
          ),
          const Spacer(),
          Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF5E5048),
                  Color(0xFF3E4043),
                  Color(0xFF292C30),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _metric(
                  'Profit',
                  recipe.profit,
                  recipe.profitable
                      ? const Color(0xFF8ED3AD)
                      : const Color(0xFFF09A91),
                ),
              ),
              Expanded(
                child: _metric(
                  'Market',
                  recipe.market,
                  recipe.demand
                      ? const Color(0xFFF09A91)
                      : const Color(0xFFD1D0CD),
                ),
              ),
              Expanded(
                child: _metric(
                  'Investment',
                  recipe.cost,
                  const Color(0xFFD1D0CD),
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
      Text(label, style: conceptType(16, const Color(0xFFB5B2AE))),
      const SizedBox(height: 8),
      Text(value, style: conceptType(20, color, weight: FontWeight.w700)),
    ],
  );
}

class _CutBasaltSlab extends CustomPainter {
  const _CutBasaltSlab();

  Path _edge(Size size, double inset) => Path()
    ..moveTo(14 + inset, inset)
    ..lineTo(size.width - 7 - inset, inset)
    ..lineTo(size.width - inset, 7 + inset)
    ..lineTo(size.width - inset, size.height - 14 - inset)
    ..lineTo(size.width - 14 - inset, size.height - inset)
    ..lineTo(7 + inset, size.height - inset)
    ..lineTo(inset, size.height - 7 - inset)
    ..lineTo(inset, 14 + inset)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final edge = _edge(size, 0);
    canvas.drawShadow(
      edge.shift(const Offset(0, 5)),
      const Color(0xFF000000),
      12,
      false,
    );
    canvas.drawPath(
      edge.shift(const Offset(0, 6)),
      Paint()..color = const Color(0xFF06080A),
    );
    canvas.drawPath(
      edge,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5A5754), Color(0xFF292D31), Color(0xFF12161A)],
        ).createShader(rect),
    );
    final face = _edge(size, 4);
    canvas.drawPath(
      face,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF30343A), Color(0xFF23272C), Color(0xFF1B2025)],
          stops: [0, .46, 1],
        ).createShader(rect),
    );
    canvas.drawPath(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x8097938C), Color(0x304F545A), Color(0x8051565C)],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipPath(face);
    final grain = math.Random(719);
    for (var index = 0; index < 150; index++) {
      final x = grain.nextDouble() * size.width;
      final y = grain.nextDouble() * size.height;
      if (x > 16 && x < size.width - 16 && y > 14 && y < size.height - 14) {
        continue;
      }
      canvas.drawLine(
        Offset(x, y),
        Offset(x + 1 + grain.nextDouble() * 7, y),
        Paint()..color = const Color(0x147D838A),
      );
    }
    canvas.drawLine(
      const Offset(22, 5),
      Offset(size.width * .44, 5),
      Paint()
        ..color = const Color(0xA4C79878)
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CutBasaltSlab oldDelegate) => false;
}

class _BasaltRail extends CustomPainter {
  const _BasaltRail();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final edge = RRect.fromRectAndRadius(rect, const Radius.circular(9));
    canvas.drawShadow(
      Path()..addRRect(edge),
      const Color(0xFF000000),
      14,
      false,
    );
    canvas.drawRRect(
      edge,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF282A2D), Color(0xFF191D21), Color(0xFF111519)],
        ).createShader(rect),
    );
    canvas.drawRRect(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF535354), Color(0xFF24292D)],
        ).createShader(rect),
    );
    canvas.drawLine(
      Offset(size.width - 4, 14),
      Offset(size.width - 4, size.height - 14),
      Paint()
        ..color = const Color(0x60080A0D)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _BasaltRail oldDelegate) => false;
}

class _BasaltGround extends CustomPainter {
  const _BasaltGround();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF232629), Color(0xFF15191E), Color(0xFF101316)],
          stops: [0, .5, 1],
        ).createShader(bounds),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(.85, -.95),
          radius: .85,
          colors: [Color(0x254E3329), Color(0x004E3329)],
        ).createShader(bounds),
    );
    final grain = math.Random(1804);
    for (var index = 0; index < 8000; index++) {
      canvas.drawCircle(
        Offset(
          grain.nextDouble() * size.width,
          grain.nextDouble() * size.height,
        ),
        grain.nextDouble() * .55 + .15,
        Paint()
          ..color = index.isEven
              ? const Color(0x0CDAE0E7)
              : const Color(0x18000000),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BasaltGround oldDelegate) => false;
}
