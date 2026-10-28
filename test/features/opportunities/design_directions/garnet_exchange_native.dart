import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'bold_concept_support.dart';
import 'concept_support.dart';

/// Native visual exploration only; the example amounts are not market quotes.
class GarnetExchangeConcept extends StatefulWidget {
  const GarnetExchangeConcept({super.key, required this.itemIcon});

  final ConceptItemIcon itemIcon;

  @override
  State<GarnetExchangeConcept> createState() => _GarnetExchangeConceptState();
}

class _GarnetExchangeConceptState extends State<GarnetExchangeConcept> {
  static const _ink = Color(0xFFF4EAE3);
  static const _muted = Color(0xFFBCADA7);
  static const _copper = Color(0xFFCB9A82);
  static const _green = Color(0xFFB7D9BB);
  static const _red = Color(0xFFF59B99);

  String _section = 'Crafting';
  String _category = 'Alchemy';
  String _search = '';
  String? _selected;
  bool _profitFirst = true;

  @override
  Widget build(BuildContext context) {
    final recipes = boldConceptRecipes
        .where((recipe) => recipe.name.toLowerCase().contains(_search))
        .toList();
    return Material(
      color: const Color(0xFF171314),
      child: DefaultTextStyle(
        style: conceptType(16, _ink),
        child: Stack(
          children: [
            const Positioned.fill(
              child: CustomPaint(painter: _GarnetSurround()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(34, 30, 34, 34),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: 22),
                  _toolbar(),
                  const SizedBox(height: 26),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _comparisonTable(recipes),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => SizedBox(
    height: 104,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Row(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Opportunities',
                  style: conceptType(28, _ink, weight: FontWeight.w700),
                ),
                const SizedBox(height: 9),
                Text(
                  'Design preview · Example prices',
                  style: conceptType(14, _muted),
                ),
              ],
            ),
            const Spacer(),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Market · EU', style: conceptType(16, _copper)),
                    const SizedBox(width: 18),
                    _GarnetControl(
                      'Refresh',
                      icon: Icons.refresh_rounded,
                      onTap: () => setState(() => _selected = null),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Prices from 9.9. 16:00', style: conceptType(14, _muted)),
              ],
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xFF171214),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF584039)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final section in ['Crafting', 'Exchanges'])
                _GarnetControl(
                  section,
                  selected: _section == section,
                  navigation: true,
                  onTap: () => setState(() => _section = section),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _toolbar() => Row(
    children: [
      for (final category in ['Cooking', 'Alchemy', 'Processing']) ...[
        _GarnetControl(
          category,
          selected: _category == category,
          onTap: () => setState(() => _category = category),
        ),
        const SizedBox(width: 9),
      ],
      const SizedBox(width: 18),
      SizedBox(
        width: 340,
        height: 48,
        child: TextField(
          key: const ValueKey('garnet-concept-search'),
          onChanged: (value) => setState(() => _search = value.toLowerCase()),
          style: conceptType(16, _ink),
          cursorColor: _copper,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: const Color(0xFF171214),
            hintText: 'Find a recipe',
            hintStyle: conceptType(16, _muted),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: _muted,
              size: 22,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 15,
            ),
            border: _searchBorder(const Color(0xFF60453F)),
            enabledBorder: _searchBorder(const Color(0xFF60453F)),
            focusedBorder: _searchBorder(_copper),
          ),
        ),
      ),
      const Spacer(),
      Text('Sort by', style: conceptType(16, _muted)),
      const SizedBox(width: 12),
      _GarnetControl(
        _profitFirst ? 'Profit' : 'Market',
        icon: Icons.south_rounded,
        onTap: () => setState(() => _profitFirst = !_profitFirst),
      ),
    ],
  );

  OutlineInputBorder _searchBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(7),
    borderSide: BorderSide(color: color),
  );

  Widget _comparisonTable(List<ConceptRecipe> recipes) => Container(
    key: const ValueKey('garnet-comparison-table'),
    padding: const EdgeInsets.all(7),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(15),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFAF7964),
          Color(0xFF5A3534),
          Color(0xFF2B171C),
          Color(0xFF805448),
        ],
        stops: [0, .12, .68, 1],
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x8A000000),
          blurRadius: 32,
          offset: Offset(0, 19),
        ),
        BoxShadow(
          color: Color(0x2217090E),
          blurRadius: 3,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF42232A), Color(0xFF251A1F)],
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _tableHead(),
              for (var index = 0; index < recipes.length; index++)
                _recipeRow(recipes[index], index),
              if (recipes.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No matching recipes',
                    style: conceptType(20, _ink),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _tableHead() => Container(
    height: 64,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF653540), Color(0xFF3C2029)],
      ),
      border: Border(
        top: BorderSide(color: Color(0x77F0B59C)),
        bottom: BorderSide(color: Color(0xFFB07865)),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          flex: 46,
          child: Padding(
            padding: const EdgeInsets.only(left: 25),
            child: Text(
              'Recipe',
              style: conceptType(16, _ink, weight: FontWeight.w600),
            ),
          ),
        ),
        for (final title in ['Profit', 'Market', 'Investment'])
          Expanded(
            flex: 18,
            child: Padding(
              padding: const EdgeInsets.only(right: 28),
              child: Text(
                title,
                textAlign: TextAlign.right,
                style: conceptType(16, _ink, weight: FontWeight.w600),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _recipeRow(ConceptRecipe recipe, int index) {
    final selected = _selected == recipe.name;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${recipe.name}, Profit ${recipe.profit}, '
          'Market ${recipe.market}, Investment ${recipe.cost}',
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: selected
                  ? const [Color(0xFF663743), Color(0xFF38222B)]
                  : index.isEven
                  ? const [Color(0xFF412A30), Color(0xFF2A1E24)]
                  : const [Color(0xFF38262B), Color(0xFF251B21)],
            ),
            border: Border(
              top: const BorderSide(color: Color(0x23EBC5AA)),
              bottom: BorderSide(
                color: selected
                    ? const Color(0xFFBB8770)
                    : const Color(0xFF62433D),
              ),
            ),
          ),
          child: InkWell(
            key: ValueKey('garnet-row-${recipe.name}'),
            onTap: () => setState(() => _selected = recipe.name),
            hoverColor: const Color(0x14E7AF95),
            focusColor: const Color(0x21E7AF95),
            splashColor: const Color(0x25E7AF95),
            child: SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 46,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 72,
                            child: Center(
                              child: widget.itemIcon(recipe.name, 64),
                            ),
                          ),
                          const SizedBox(width: 21),
                          Expanded(
                            child: Text(
                              recipe.name,
                              style: conceptType(
                                20,
                                _ink,
                                weight: FontWeight.w600,
                              ),
                              maxLines: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _numberCell(
                    recipe.profit,
                    recipe.profitable ? _green : _red,
                    first: true,
                  ),
                  _numberCell(recipe.market, recipe.demand ? _red : _ink),
                  _numberCell(recipe.cost, _ink),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _numberCell(String value, Color color, {bool first = false}) =>
      Expanded(
        flex: 18,
        child: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                first ? const Color(0x44120910) : const Color(0x2810080D),
                const Color(0x08000000),
              ],
            ),
            border: const Border(left: BorderSide(color: Color(0x365F3935))),
          ),
          child: Text(
            value,
            style: conceptType(20, color, weight: FontWeight.w600),
          ),
        ),
      );
}

class _GarnetControl extends StatelessWidget {
  const _GarnetControl(
    this.label, {
    required this.onTap,
    this.selected = false,
    this.navigation = false,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool navigation;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Ink(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: selected
              ? const [Color(0xFF874857), Color(0xFF4F2635), Color(0xFF42202C)]
              : const [Color(0xFF3C3031), Color(0xFF292123), Color(0xFF221B1D)],
        ),
        border: Border.all(
          color: selected ? const Color(0xFFCA9580) : const Color(0xFF69504A),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: const Color(0x20DCA18C),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: navigation ? 25 : 17,
            vertical: navigation ? 15 : 13,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: conceptType(
                  16,
                  selected ? const Color(0xFFFFEEE6) : const Color(0xFFD9C7BD),
                  weight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 9),
                Icon(icon, size: 18, color: const Color(0xFFCDA18C)),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _GarnetSurround extends CustomPainter {
  const _GarnetSurround();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF392126), Color(0xFF231C20), Color(0xFF151316)],
          stops: [0, .43, 1],
        ).createShader(bounds),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment(-1, -.7),
          end: Alignment(.5, 1),
          colors: [Color(0x0873A0A4), Color(0x006E8E94), Color(0x006E8E94)],
          stops: [0, .26, 1],
        ).createShader(bounds),
    );
    final random = math.Random(4419);
    final grain = Paint()..color = const Color(0x0CE9CDBA);
    for (var i = 0; i < 8500; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        .38,
        grain,
      );
    }
    canvas.drawLine(
      const Offset(34, 155),
      Offset(size.width - 34, 155),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x001C1517), Color(0xFF885F4E), Color(0x001C1517)],
        ).createShader(Rect.fromLTWH(34, 154, size.width - 68, 2))
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_GarnetSurround oldDelegate) => false;
}
