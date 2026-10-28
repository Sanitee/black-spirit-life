import 'package:flutter/material.dart';

import '../bold_concept_support.dart';
import '../concept_support.dart';
import 'tonal_onyx.dart';

/// Isolated design samples, never imported into the live application.
final boardRecipes = <ConceptRecipe>[
  ...boldConceptRecipes.take(5),
  const ConceptRecipe('Elixir of Fury', '', '325K', '19.500', '625K'),
  const ConceptRecipe(
    'Elixir of Shock',
    '',
    '120K',
    '−42.100',
    '880K',
    demand: true,
  ),
  boldConceptRecipes.last,
];

class TonalOnyxBoardConcept extends StatefulWidget {
  const TonalOnyxBoardConcept({super.key, required this.itemIcon});
  final ConceptItemIcon itemIcon;

  @override
  State<TonalOnyxBoardConcept> createState() => _TonalOnyxBoardConceptState();
}

class _TonalOnyxBoardConceptState extends State<TonalOnyxBoardConcept> {
  String _query = '';
  bool _demandFirst = false;

  Color get _text => const Color(0xFFEEEDE5);
  Color get _faceText => const Color(0xFFEEEDE5);
  Color get _faceMuted => const Color(0xFFC7C7BE);
  Color get _muted => const Color(0xFFC7C7BE);
  Color get _accent => const Color(0xFFCCB991);
  Color get _profit => const Color(0xFF9CDEB7);
  Color get _red => const Color(0xFFF2A39A);

  CustomPainter _paint(String part, {bool selected = false}) =>
      TonalOnyxPaint(part: part, selected: selected);

  @override
  Widget build(BuildContext context) {
    final recipes = boardRecipes
        .where((r) => r.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    if (_demandFirst) {
      recipes.sort((a, b) => (b.demand ? 1 : 0).compareTo(a.demand ? 1 : 0));
    }
    return Material(
      color: Colors.transparent,
      child: CustomPaint(
        painter: _paint('background'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 188, child: _navigation()),
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 76, child: _header()),
                    const SizedBox(height: 14),
                    _toolbar(),
                    const SizedBox(height: 18),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final cardWidth = (constraints.maxWidth - 18) / 2;
                          return SingleChildScrollView(
                            clipBehavior: Clip.none,
                            child: Wrap(
                              spacing: 18,
                              runSpacing: 16,
                              children: [
                                for (final recipe in recipes)
                                  SizedBox(
                                    width: cardWidth,
                                    height: 170,
                                    child: _tile(recipe),
                                  ),
                              ],
                            ),
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
  }

  Widget _navigation() => CustomPaint(
    painter: _paint('rail'),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(15, 20, 15, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 9),
              child: Image.asset(
                'assets/opportunities/items/66771.webp',
                width: 48,
                height: 48,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          const SizedBox(height: 22),
          _button('Crafting', selected: true),
          const SizedBox(height: 10),
          _button('Exchanges', quiet: true),
          const SizedBox(height: 25),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Divider(color: _accent.withAlpha(70)),
          ),
          const SizedBox(height: 16),
          _category('Cooking'),
          const SizedBox(height: 7),
          _category('Alchemy', selected: true),
          const SizedBox(height: 7),
          _category('Processing'),
        ],
      ),
    ),
  );

  Widget _category(String name, {bool selected = false}) => Container(
    height: 46,
    decoration: selected
        ? BoxDecoration(
            color: _accent.withAlpha(22),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: _accent.withAlpha(82)),
          )
        : null,
    padding: const EdgeInsets.symmetric(horizontal: 13),
    child: Row(
      children: [
        Container(
          width: 3,
          height: 16,
          color: selected ? _accent : const Color(0xFF69756F),
        ),
        const SizedBox(width: 12),
        Text(
          name,
          style: conceptType(
            16,
            const Color(0xFFEEEDE5),
            weight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            'Opportunities',
            style: conceptType(28, _text, weight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Design preview · Example prices',
            style: conceptType(14, _muted),
          ),
        ],
      ),
      const Spacer(),
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              _button('Market · EU'),
              const SizedBox(width: 10),
              _button('Refresh', icon: Icons.refresh),
            ],
          ),
          const SizedBox(height: 10),
          Text('Prices from 9.9. 18:00', style: conceptType(14, _muted)),
        ],
      ),
    ],
  );

  Widget _toolbar() => Row(
    children: [
      Container(
        width: 320,
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFF252D2D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _muted.withAlpha(90)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(30),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: TextField(
          onChanged: (value) => setState(() => _query = value),
          style: conceptType(16, _text),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search, color: _muted, size: 20),
            hintText: 'Find a recipe',
            hintStyle: conceptType(16, _muted),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            isDense: true,
          ),
        ),
      ),
      const SizedBox(width: 12),
      _button('Filters', icon: Icons.tune),
      const Spacer(),
      _button(
        'Profit',
        selected: !_demandFirst,
        action: () => setState(() => _demandFirst = false),
      ),
      const SizedBox(width: 8),
      _button(
        'Demand',
        selected: _demandFirst,
        action: () => setState(() => _demandFirst = true),
      ),
    ],
  );

  Widget _button(
    String label, {
    bool selected = false,
    bool quiet = false,
    IconData? icon,
    VoidCallback? action,
  }) => CustomPaint(
    painter: quiet ? null : _paint('button', selected: selected),
    child: SizedBox(
      height: 46,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: action ?? () => _previewNote(label),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 19,
                    color: selected
                        ? const Color(0xFFEEEDE5)
                        : const Color(0xFFEEEDE5),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: conceptType(
                    16,
                    selected
                        ? const Color(0xFFEEEDE5)
                        : const Color(0xFFEEEDE5),
                    weight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _tile(ConceptRecipe recipe) => CustomPaint(
    painter: _paint('card'),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('tonal-recipe-${recipe.name}'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openRecipe(recipe),
        hoverColor: _accent.withAlpha(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(19, 15, 19, 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  widget.itemIcon(recipe.name, 64),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Text(
                      recipe.name,
                      style: conceptType(
                        20,
                        _faceText,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (recipe.scope.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text('100×', style: conceptType(14, _faceMuted)),
                  ],
                  const SizedBox(width: 13),
                  Icon(
                    Icons.arrow_forward,
                    color: const Color(0xFFC7C7BE),
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 11),
              const SizedBox(height: 1),
              const SizedBox(height: 11),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: _metric(
                        'Profit',
                        recipe.profit,
                        recipe.profitable ? _profit : _red,
                      ),
                    ),
                    Expanded(
                      child: _metric(
                        'Market',
                        recipe.market,
                        recipe.demand ? _red : _text,
                      ),
                    ),
                    Expanded(child: _metric('Investment', recipe.cost, _text)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _metric(String label, String value, Color valueColor) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: conceptType(16, _muted)),
      const SizedBox(height: 3),
      Text(value, style: conceptType(20, valueColor, weight: FontWeight.w600)),
    ],
  );

  Future<void> _previewNote(String label) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(label),
      content: const Text('Design preview only.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> _openRecipe(ConceptRecipe recipe) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(recipe.name),
      content: const Text(
        'The recipe opens here. This preview only shows the new look.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
      ],
    ),
  );
}
