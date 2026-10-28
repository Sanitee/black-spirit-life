import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'bold_concept_support.dart';
import 'concept_support.dart';

/// Native overview-only exploration. No production theme or data is changed.
class PorcelainCounterConcept extends StatelessWidget {
  const PorcelainCounterConcept({super.key, required this.itemIcon});

  final ConceptItemIcon itemIcon;

  static const _ink = Color(0xFF242D39);
  static const _muted = Color(0xFF727575);
  static const _ivory = Color(0xFFF5F0E4);
  static const _cobalt = Color(0xFF244977);
  static const _blueDark = Color(0xFF173554);
  static const _blueLight = Color(0xFF527AA4);
  static const _green = Color(0xFF2B7352);
  static const _red = Color(0xFFB2423A);

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFD1D0C9),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE9E5DB), Color(0xFFD0D1CC), Color(0xFFC1C6C6)],
        ),
      ),
      child: CustomPaint(
        painter: const _CounterFinish(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(34, 31, 34, 32),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Row(
                        children: [
                          Text(
                            'Opportunities',
                            style: conceptType(
                              28,
                              _ink,
                              weight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Design preview · Example prices',
                            style: conceptType(14, _muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 29),
                    for (var row = 0; row < 3; row++) ...[
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _recipeTile(
                                context,
                                boldConceptRecipes[row * 2],
                              ),
                            ),
                            const SizedBox(width: 23),
                            Expanded(
                              child: _recipeTile(
                                context,
                                boldConceptRecipes[row * 2 + 1],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (row < 2) const SizedBox(height: 23),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 30),
              SizedBox(width: 306, child: _console()),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _recipeTile(BuildContext context, ConceptRecipe recipe) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(23),
      boxShadow: const [
        BoxShadow(
          color: Color(0x49434845),
          blurRadius: 24,
          offset: Offset(0, 13),
        ),
        BoxShadow(
          color: Color(0x45404943),
          blurRadius: 3,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFE6DDC9), Color(0xFFB1AFA1)],
          stops: [0, .64, 1],
        ),
        border: Border.all(color: const Color(0xFFF9F5E9), width: 1.1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Material(
          color: _ivory,
          borderRadius: BorderRadius.circular(19),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _showSummary(context, recipe),
            hoverColor: const Color(0x094275A4),
            splashColor: const Color(0x144275A4),
            child: CustomPaint(
              foregroundPainter: const _CeramicRim(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        itemIcon(recipe.name, 64),
                        const SizedBox(width: 17),
                        Expanded(
                          child: Text(
                            recipe.name,
                            style: conceptType(
                              20,
                              _ink,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.north_east,
                          color: Color(0xFF8E969B),
                          size: 19,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(height: 1, color: const Color(0xFFD6D2C6)),
                    Container(height: 1, color: const Color(0xFFFDFBF5)),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _metric(
                            'Profit',
                            recipe.profit,
                            recipe.profitable ? _green : _red,
                            strong: true,
                          ),
                        ),
                        Expanded(
                          child: _metric(
                            'Market',
                            recipe.market,
                            recipe.demand ? _red : _ink,
                          ),
                        ),
                        Expanded(
                          child: _metric('Investment', recipe.cost, _ink),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _metric(
    String label,
    String value,
    Color color, {
    bool strong = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: conceptType(16, _muted)),
      const SizedBox(height: 8),
      Text(
        value,
        style: conceptType(
          20,
          color,
          weight: strong ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ],
  );

  Widget _console() => Container(
    padding: const EdgeInsets.fromLTRB(5, 5, 5, 9),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(29),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFC9D5DE), Color(0xFF6885A1), Color(0xFF142F4C)],
        stops: [0, .24, 1],
      ),
      border: Border.all(color: const Color(0xFFCAD7DE)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x42404A4D),
          blurRadius: 28,
          offset: Offset(0, 16),
        ),
        BoxShadow(
          color: Color(0x4E253B4F),
          blurRadius: 4,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_blueLight, _cobalt, _blueDark],
          stops: [0, .22, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 23),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _rocker(['Crafting', 'Exchanges']),
            const SizedBox(height: 24),
            _mode('Cooking'),
            const SizedBox(height: 8),
            _mode('Alchemy', selected: true),
            const SizedBox(height: 8),
            _mode('Processing'),
            const SizedBox(height: 25),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF102A46),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF7590AA)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x71000000),
                    blurRadius: 3,
                    offset: Offset(0, -1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Color(0xFFC3D3DE), size: 20),
                  const SizedBox(width: 9),
                  Text(
                    'Search recipes',
                    style: conceptType(16, const Color(0xFFC3D3DE)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _smallControl('Filters', Icons.filter_list)),
                const SizedBox(width: 10),
                Expanded(child: _smallControl('Mastery · 0', null)),
              ],
            ),
            const SizedBox(height: 25),
            _rocker(['Profit', 'Demand']),
            const SizedBox(height: 26),
            Container(height: 1, color: const Color(0xFF122F4B)),
            Container(height: 1, color: const Color(0xFF557492)),
            const SizedBox(height: 22),
            _smallControl('Market · EU', Icons.tune),
            const SizedBox(height: 11),
            _smallControl('Refresh', Icons.refresh),
            const SizedBox(height: 19),
            Text(
              'Prices from 8.9. 18:00',
              textAlign: TextAlign.center,
              style: conceptType(14, const Color(0xFFC1D0DC)),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _rocker(List<String> labels) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFF142F4A),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF537391)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x540B1C2A),
          blurRadius: 3,
          offset: Offset(0, -1),
        ),
      ],
    ),
    child: Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: i == 0
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFEFBF2), Color(0xFFD4D3C7)],
                      ),
                      border: Border.all(color: const Color(0xFFFAFBF6)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x8C071929),
                          blurRadius: 4,
                          offset: Offset(0, 3),
                        ),
                      ],
                    )
                  : null,
              child: Text(
                labels[i],
                textAlign: TextAlign.center,
                style: conceptType(
                  16,
                  i == 0 ? _ink : const Color(0xFFC5D4E0),
                  weight: i == 0 ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _mode(String name, {bool selected = false}) => Container(
    padding: const EdgeInsets.fromLTRB(15, 14, 14, 14),
    decoration: BoxDecoration(
      color: selected ? const Color(0xFFDCE6EE) : const Color(0x4F142E48),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(
        color: selected ? const Color(0xFFF0F6F7) : const Color(0xFF63809C),
      ),
      boxShadow: selected
          ? const [
              BoxShadow(
                color: Color(0x60091929),
                blurRadius: 5,
                offset: Offset(0, 3),
              ),
            ]
          : null,
    ),
    child: Row(
      children: [
        Text(
          name,
          style: conceptType(
            16,
            selected ? _cobalt : const Color(0xFFE1E9EE),
            weight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        const Spacer(),
        if (selected) const Icon(Icons.check, size: 19, color: _cobalt),
      ],
    ),
  );

  Widget _smallControl(String label, IconData? icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 13),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF517493), Color(0xFF284B6D)],
      ),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFF7F9AAD)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x4C0A2138),
          blurRadius: 4,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 19, color: const Color(0xFFE0E9EE)),
          const SizedBox(width: 7),
        ],
        Text(label, style: conceptType(16, const Color(0xFFF1F2ED))),
      ],
    ),
  );

  Future<void> _showSummary(BuildContext context, ConceptRecipe recipe) =>
      showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: _ivory,
          child: SizedBox(
            width: 470,
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.name,
                    style: conceptType(20, _ink, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 25),
                  Row(
                    children: [
                      Expanded(
                        child: _metric(
                          'Profit',
                          recipe.profit,
                          recipe.profitable ? _green : _red,
                        ),
                      ),
                      Expanded(
                        child: _metric(
                          'Market',
                          recipe.market,
                          recipe.demand ? _red : _ink,
                        ),
                      ),
                      Expanded(child: _metric('Investment', recipe.cost, _ink)),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Design preview · Example prices',
                    style: conceptType(14, _muted),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Close', style: conceptType(16, _cobalt)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _CeramicRim extends CustomPainter {
  const _CeramicRim();

  @override
  void paint(Canvas canvas, Size size) {
    final edge = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(1.3),
      const Radius.circular(18),
    );
    canvas.drawRRect(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xADFFFFFF),
    );
    final sheen = Rect.fromLTWH(23, 1, math.max(0, size.width - 46), 1);
    canvas.drawLine(
      sheen.topLeft,
      sheen.topRight,
      Paint()
        ..strokeWidth = 2
        ..shader = const LinearGradient(
          colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        ).createShader(sheen),
    );
  }

  @override
  bool shouldRepaint(_CeramicRim oldDelegate) => false;

  @override
  bool? hitTest(Offset position) => false;
}

class _CounterFinish extends CustomPainter {
  const _CounterFinish();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = .5;
    for (var i = 0; i < 100; i++) {
      final y = (i + .3) / 100 * size.height;
      paint.color = i.isEven
          ? const Color(0x05FFFFFF)
          : const Color(0x04000000);
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 2), paint);
    }
  }

  @override
  bool shouldRepaint(_CounterFinish oldDelegate) => false;
}
