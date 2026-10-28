import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'concept_support.dart';

/// A visual proposal, intentionally separate from the shipping workspace.
class NightMarketConcept extends StatelessWidget {
  const NightMarketConcept({required this.itemIcon, super.key});
  final ConceptItemIcon itemIcon;
  static const ink = Color(0xFF181916);
  static const paper = Color(0xFFF3EAD9);
  static const muted = Color(0xFFBDB6A5);
  static const gold = Color(0xFFD7B878);
  static const green = Color(0xFF8BCAB1);
  static const red = Color(0xFFE59A8C);

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF131410),
    child: Stack(
      children: [
        const Positioned.fill(child: CustomPaint(painter: _MarketAtmosphere())),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 26, 32, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0xFF5A482B), Color(0x00443220)],
                      ),
                    ),
                    child: Image.asset(
                      'assets/opportunities/items/66771.webp',
                      width: 64,
                      height: 64,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Opportunities',
                        style: conceptType(28, paper, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Design preview · Example prices',
                        style: conceptType(14, muted),
                      ),
                    ],
                  ),
                  const SizedBox(width: 48),
                  const _MetalControl('Crafting', selected: true),
                  const SizedBox(width: 8),
                  const _MetalControl('Exchanges'),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Row(
                        children: [
                          _MetalControl('Refresh'),
                          SizedBox(width: 12),
                          _MetalControl('Market · EU'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Prices from 8.9. 18:00',
                        style: conceptType(14, muted),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF343A30), Color(0xFF1E2420)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF68634B)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x65000000),
                      offset: Offset(0, 8),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const _MetalControl('Cooking', selected: true),
                    const SizedBox(width: 8),
                    const _MetalControl('Alchemy'),
                    const SizedBox(width: 8),
                    const _MetalControl('Processing'),
                    const SizedBox(width: 28),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF131B18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF4E574A)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search, color: muted, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              'Find a recipe',
                              style: conceptType(16, muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const _MetalControl('Filters'),
                    const SizedBox(width: 24),
                    const _MetalControl('Profit', selected: true),
                    const SizedBox(width: 8),
                    const _MetalControl('Demand'),
                    const SizedBox(width: 24),
                    Text('Mastery · 0', style: conceptType(16, paper)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF26302B),
                        Color(0xFF18211E),
                        Color(0xFF1C211B),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF928061)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x99000000),
                        offset: Offset(0, 16),
                        blurRadius: 30,
                      ),
                    ],
                  ),
                  child: CustomPaint(
                    foregroundPainter: const _MetalCorners(),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                            child: _columns([
                              for (final label in [
                                'Recipe',
                                'Profit',
                                'Market',
                                'Investment',
                              ])
                                Text(label, style: conceptType(14, gold)),
                            ]),
                          ),
                          const Divider(height: 1, color: Color(0xFF6E694E)),
                          const SizedBox(height: 10),
                          for (var i = 0; i < conceptRecipes.length; i++) ...[
                            _recipe(conceptRecipes[i], selected: i == 0),
                            if (i < conceptRecipes.length - 1)
                              const SizedBox(height: 5),
                          ],
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Row(
                              children: [
                                Text(
                                  '6 recipes',
                                  style: conceptType(14, muted),
                                ),
                                const Spacer(),
                                Text(
                                  'Main item only',
                                  style: conceptType(14, muted),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.info_outline,
                                  color: muted,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _recipe(ConceptRecipe recipe, {required bool selected}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: selected
            ? const [Color(0xFF474530), Color(0xFF303A2F), Color(0xFF263027)]
            : const [Color(0xFF202C27), Color(0xFF1B2520)],
      ),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(
        color: selected ? const Color(0xFFAF975B) : const Color(0xFF3F4D3F),
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x50000000),
          blurRadius: 5,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: _columns([
      Row(
        children: [
          itemIcon(recipe.name, 64),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipe.name,
                  style: conceptType(20, paper, weight: FontWeight.w600),
                ),
                const SizedBox(height: 7),
                Text(recipe.scope, style: conceptType(14, muted)),
              ],
            ),
          ),
        ],
      ),
      Text(
        recipe.profit,
        style: conceptType(
          20,
          recipe.profitable ? green : red,
          weight: FontWeight.w700,
        ),
      ),
      Text(recipe.market, style: conceptType(20, recipe.demand ? red : muted)),
      Row(
        children: [
          Expanded(child: Text(recipe.cost, style: conceptType(20, paper))),
          const Icon(Icons.arrow_forward, color: gold, size: 20),
        ],
      ),
    ]),
  );

  Widget _columns(List<Widget> children) => Row(
    children: [
      Expanded(flex: 46, child: children[0]),
      Expanded(flex: 18, child: children[1]),
      Expanded(flex: 20, child: children[2]),
      Expanded(flex: 16, child: children[3]),
    ],
  );
}

class _MetalControl extends StatelessWidget {
  const _MetalControl(this.text, {this.selected = false});
  final String text;
  final bool selected;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: selected
            ? const [Color(0xFFD1B881), Color(0xFF94784A)]
            : const [Color(0xFF414A3D), Color(0xFF222B23)],
      ),
      border: Border.all(
        color: selected ? const Color(0xFFE5C992) : const Color(0xFF646E56),
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x80000000),
          offset: Offset(0, 3),
          blurRadius: 4,
        ),
      ],
    ),
    child: Text(
      text,
      style: conceptType(
        16,
        selected ? const Color(0xFF211F16) : NightMarketConcept.paper,
        weight: FontWeight.w600,
      ),
    ),
  );
}

class _MarketAtmosphere extends CustomPainter {
  const _MarketAtmosphere();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.85, -.8),
          radius: 1.5,
          colors: [Color(0xFF4C4730), Color(0xFF1C271F), Color(0xFF101713)],
        ).createShader(Offset.zero & size),
    );
    final random = math.Random(41);
    final grain = Paint()..color = const Color(0x0AF8EDCD);
    for (var i = 0; i < 13000; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        .65,
        grain,
      );
    }
    canvas.drawLine(
      const Offset(0, 142),
      Offset(size.width, 142),
      Paint()..color = const Color(0x305D6D49),
    );
  }

  @override
  bool shouldRepaint(covariant _MarketAtmosphere oldDelegate) => false;
}

class _MetalCorners extends CustomPainter {
  const _MetalCorners();
  @override
  void paint(Canvas canvas, Size size) {
    final metal = Paint()
      ..color = const Color(0xFFE1C58B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final point in [
      const Offset(10, 10),
      Offset(size.width - 10, 10),
      Offset(10, size.height - 10),
      Offset(size.width - 10, size.height - 10),
    ]) {
      final dx = point.dx < size.width / 2 ? 1.0 : -1.0;
      final dy = point.dy < size.height / 2 ? 1.0 : -1.0;
      canvas.drawPath(
        Path()
          ..moveTo(point.dx, point.dy + 20 * dy)
          ..lineTo(point.dx, point.dy)
          ..lineTo(point.dx + 20 * dx, point.dy),
        metal,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MetalCorners oldDelegate) => false;
}
