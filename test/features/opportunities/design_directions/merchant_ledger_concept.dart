import 'package:flutter/material.dart';

import 'concept_support.dart';

/// A static visual direction, separate from the application's saved appearance.
class MerchantLedgerConcept extends StatelessWidget {
  const MerchantLedgerConcept({required this.itemIcon, super.key});

  final ConceptItemIcon itemIcon;

  static const _ink = Color(0xFF293730);
  static const _muted = Color(0xFF727265);
  static const _paper = Color(0xFFF3EDD9);
  static const _rule = Color(0xFFD2CAB1);
  static const _leather = Color(0xFF283F36);
  static const _brass = Color(0xFFD2B77D);
  static const _green = Color(0xFF30704C);
  static const _red = Color(0xFFA84036);

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF463F33),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-.55, -.6),
          radius: 1.5,
          colors: [Color(0xFF786C54), Color(0xFF393B31)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        child: Stack(
          children: [
            Positioned.fill(
              top: 12,
              left: 5,
              right: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFAF9E79),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x800D160F),
                      blurRadius: 36,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              top: 6,
              left: 2,
              right: 2,
              bottom: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFD6C8A3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFEFE5C9)),
                ),
              ),
            ),
            Positioned.fill(
              bottom: 12,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _spine(),
                    Expanded(child: _page()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _spine() => Container(
    width: 260,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF172B23), _leather, Color(0xFF314B3E)],
        stops: [0, .09, 1],
      ),
    ),
    child: Stack(
      children: [
        const Positioned(
          top: 0,
          bottom: 0,
          left: 13,
          child: SizedBox(
            width: 1,
            child: ColoredBox(color: Color(0x556E8060)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 31, 20, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Opportunities',
                style: conceptType(28, _paper, weight: FontWeight.w600),
              ),
              const SizedBox(height: 23),
              Container(height: 1, color: _brass.withAlpha(115)),
              const SizedBox(height: 22),
              _nav('Crafting', selected: true),
              const SizedBox(height: 8),
              _nav('Exchanges'),
              const SizedBox(height: 37),
              _mode('Cooking', selected: true),
              _mode('Alchemy'),
              _mode('Processing'),
              const Spacer(),
              Container(height: 1, color: _brass.withAlpha(100)),
              const SizedBox(height: 18),
              Text('Mastery', style: conceptType(14, const Color(0xFFB9C4B2))),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '0',
                    style: conceptType(20, _paper, weight: FontWeight.w600),
                  ),
                  const Spacer(),
                  const Icon(Icons.edit_outlined, size: 18, color: _brass),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _nav(String label, {bool selected = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: selected
        ? BoxDecoration(
            color: _paper,
            borderRadius: BorderRadius.circular(3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 5,
                offset: Offset(0, 3),
              ),
            ],
          )
        : null,
    child: Row(
      children: [
        Text(
          label,
          style: conceptType(
            16,
            selected ? _ink : _paper,
            weight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        const Spacer(),
        if (selected) const Icon(Icons.east, size: 20, color: _ink),
      ],
    ),
  );

  Widget _mode(String label, {bool selected = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    child: Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: selected ? _brass : Colors.transparent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: conceptType(
            16,
            selected ? const Color(0xFFE6CD98) : const Color(0xFFBCC7B6),
            weight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  Widget _page() => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFFD8CEB3), _paper, Color(0xFFF6F1E1)],
        stops: [0, .038, 1],
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(38, 29, 32, 19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Crafting',
                style: conceptType(28, _ink, weight: FontWeight.w600),
              ),
              const Spacer(),
              _tool('Refresh', Icons.refresh),
              const SizedBox(width: 12),
              _tool('Market · EU', Icons.tune),
            ],
          ),
          const SizedBox(height: 26),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 47,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBF8EC),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: _rule),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 22, color: _muted),
                      const SizedBox(width: 10),
                      Text('Search recipes', style: conceptType(16, _muted)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              _sort('Profit', selected: true),
              _sort('Demand'),
              const SizedBox(width: 20),
              _tool('Filters', Icons.filter_list),
            ],
          ),
          const SizedBox(height: 28),
          _tableHeader(),
          Expanded(
            child: Column(
              children: [
                for (final recipe in conceptRecipes)
                  Expanded(child: _recipeRow(recipe)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Design preview · Example prices',
                style: conceptType(14, _muted),
              ),
              const Spacer(),
              Text('Prices from 8.9. 18:00', style: conceptType(14, _muted)),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _tool(String label, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      border: Border.all(color: _rule),
      borderRadius: BorderRadius.circular(3),
      color: const Color(0x50FFFFFF),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: _ink),
        const SizedBox(width: 8),
        Text(label, style: conceptType(16, _ink)),
      ],
    ),
  );

  Widget _sort(String label, {bool selected = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(
          color: selected ? _green : Colors.transparent,
          width: 2,
        ),
      ),
    ),
    child: Text(
      label,
      style: conceptType(
        16,
        selected ? _green : _muted,
        weight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
    ),
  );

  Widget _tableHeader() => Container(
    padding: const EdgeInsets.fromLTRB(14, 13, 16, 13),
    decoration: const BoxDecoration(
      border: Border(
        top: BorderSide(color: _ink, width: 1.5),
        bottom: BorderSide(color: _rule),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          flex: 5,
          child: Text('Recipe', style: conceptType(14, _muted)),
        ),
        _heading('Profit'),
        _heading('Market'),
        _heading('Investment'),
      ],
    ),
  );

  Widget _heading(String text) => Expanded(
    flex: 2,
    child: Text(
      text,
      textAlign: TextAlign.right,
      style: conceptType(14, _muted),
    ),
  );

  Widget _recipeRow(ConceptRecipe recipe) => DecoratedBox(
    decoration: BoxDecoration(
      color: recipe == conceptRecipes.first ? const Color(0x1064834D) : null,
      border: const Border(bottom: BorderSide(color: _rule)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                itemIcon(recipe.name, 64),
                const SizedBox(width: 17),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recipe.name,
                        style: conceptType(20, _ink, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 7),
                      Text(recipe.scope, style: conceptType(14, _muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _figure(recipe.profit, recipe.profitable ? _green : _red, bold: true),
          _figure(recipe.market, recipe.demand ? _red : _ink),
          _figure(recipe.cost, _ink),
        ],
      ),
    ),
  );

  Widget _figure(String text, Color color, {bool bold = false}) => Expanded(
    flex: 2,
    child: Text(
      text,
      textAlign: TextAlign.right,
      style: conceptType(
        20,
        color,
        weight: bold ? FontWeight.w600 : FontWeight.w500,
      ),
    ),
  );
}
