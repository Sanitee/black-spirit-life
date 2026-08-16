import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/features/planner/need_material_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual substitute keeps its existing Need First row position', () {
    final order = NeedMaterialOrder();

    expect(
      order
          .apply(<MissingMaterial>[
            _material('Wolf Blood', 778, choice: _bloodChoice('Wolf Blood')),
            _material('Powder of Flame', 795),
            _material('Powder of Darkness', 730),
          ])
          .map((row) => row.name),
      <String>['Wolf Blood', 'Powder of Flame', 'Powder of Darkness'],
    );

    // The engine ranks by missing quantity, so the changed ratio would put the
    // replacement last without the presentation-order reconciliation.
    expect(
      order
          .apply(<MissingMaterial>[
            _material('Sheep Blood', 700, choice: _bloodChoice('Sheep Blood')),
            _material('Powder of Flame', 795),
            _material('Powder of Darkness', 730),
          ])
          .map((row) => row.name),
      <String>['Sheep Blood', 'Powder of Flame', 'Powder of Darkness'],
    );
  });

  test('explicit market refresh can adopt the fresh planner ranking', () {
    final order = NeedMaterialOrder();
    order.apply(<MissingMaterial>[
      _material('Wolf Blood', 778, choice: _bloodChoice('Wolf Blood')),
      _material('Powder of Flame', 795),
      _material('Powder of Darkness', 730),
    ]);
    order.apply(<MissingMaterial>[
      _material('Sheep Blood', 700, choice: _bloodChoice('Sheep Blood')),
      _material('Powder of Flame', 795),
      _material('Powder of Darkness', 730),
    ]);

    final refreshed = order.apply(<MissingMaterial>[
      _material('Powder of Flame', 795),
      _material('Powder of Darkness', 730),
      _material('Sheep Blood', 700, choice: _bloodChoice('Sheep Blood')),
    ], useDefaultOrder: true);
    expect(refreshed.map((row) => row.name), <String>[
      'Powder of Flame',
      'Powder of Darkness',
      'Sheep Blood',
    ]);

    expect(
      order
          .apply(<MissingMaterial>[
            _material('Powder of Flame', 790),
            _material('Powder of Darkness', 720),
            _material('Sheep Blood', 690, choice: _bloodChoice('Sheep Blood')),
          ])
          .map((row) => row.name),
      <String>['Powder of Flame', 'Powder of Darkness', 'Sheep Blood'],
    );
  });

  test('repeated blood substitutions retain the same visible slot', () {
    final order = NeedMaterialOrder();
    var visible = order.apply(<MissingMaterial>[
      _material(
        'Wolf Blood',
        900,
        choice: _bloodChoiceFor(parent: 'Clown Blood', selected: 'Wolf Blood'),
      ),
      _material('Powder of Flame', 800),
      _material('Powder of Darkness', 700),
    ]);

    order.stageSubstitute(source: visible.first, selection: 'Flamingo Blood');
    visible = order.apply(<MissingMaterial>[
      _material('Powder of Flame', 800),
      _material('Powder of Darkness', 700),
      _material(
        'Flamingo Blood',
        600,
        choice: _bloodChoiceFor(
          parent: 'Clown Blood',
          selected: 'Flamingo Blood',
        ),
      ),
    ]);
    expect(visible.map((row) => row.name), <String>[
      'Flamingo Blood',
      'Powder of Flame',
      'Powder of Darkness',
    ]);

    order.stageSubstitute(source: visible.first, selection: 'Rhino Blood');
    visible = order.apply(<MissingMaterial>[
      _material('Powder of Flame', 800),
      _material('Powder of Darkness', 700),
      _material(
        'Rhino Blood',
        500,
        choice: _bloodChoiceFor(parent: 'Clown Blood', selected: 'Rhino Blood'),
      ),
    ]);
    expect(visible.map((row) => row.name), <String>[
      'Rhino Blood',
      'Powder of Flame',
      'Powder of Darkness',
    ]);
  });

  test('converging blood choices swap merged rows and can split back', () {
    final order = NeedMaterialOrder();
    var visible = order.apply(<MissingMaterial>[
      _material('Trace of Nature', 1000),
      _material(
        'Flamingo Blood',
        900,
        choice: _bloodChoiceFor(
          parent: 'Clown Blood',
          selected: 'Flamingo Blood',
        ),
      ),
      _material('Powder of Flame', 800),
      _material(
        'Wolf Blood',
        700,
        choice: _bloodChoiceFor(parent: 'Sinner Blood', selected: 'Wolf Blood'),
      ),
      _material('Powder of Darkness', 600),
    ]);

    order.stageSubstitute(source: visible[1], selection: 'Wolf Blood');
    visible = order.apply(<MissingMaterial>[
      _material('Trace of Nature', 1000),
      _material('Powder of Flame', 800),
      _material(
        'Wolf Blood',
        750,
        // The edited Clown Blood identity was overwritten when both requests
        // converged on the same material.
        choice: _bloodChoiceFor(parent: 'Sinner Blood', selected: 'Wolf Blood'),
      ),
      _material(
        'Flamingo Blood',
        650,
        choice: _bloodChoiceFor(
          parent: 'Other Blood',
          selected: 'Flamingo Blood',
        ),
      ),
      _material('Powder of Darkness', 600),
    ]);
    expect(visible.map((row) => row.name), <String>[
      'Trace of Nature',
      'Wolf Blood',
      'Powder of Flame',
      'Flamingo Blood',
      'Powder of Darkness',
    ]);

    // Queue rows still know the hidden Clown Blood identity, allowing the
    // merged choice to split back without losing the interacted slot.
    order.stageSubstituteChoice(
      parentName: 'Clown Blood',
      original: 'Wolf Blood',
      substituteGroup: 'Blood Group 1',
      sourceName: 'Wolf Blood',
      sourceBaseName: 'Wolf Blood',
      selection: 'Flamingo Blood',
    );
    visible = order.apply(<MissingMaterial>[
      _material('Trace of Nature', 1000),
      _material('Powder of Flame', 800),
      _material(
        'Flamingo Blood',
        760,
        choice: _bloodChoiceFor(
          parent: 'Other Blood',
          selected: 'Flamingo Blood',
        ),
      ),
      _material(
        'Wolf Blood',
        700,
        choice: _bloodChoiceFor(parent: 'Sinner Blood', selected: 'Wolf Blood'),
      ),
      _material('Powder of Darkness', 600),
    ]);
    expect(visible.map((row) => row.name), <String>[
      'Trace of Nature',
      'Flamingo Blood',
      'Powder of Flame',
      'Wolf Blood',
      'Powder of Darkness',
    ]);
  });

  test('pending substitution survives an unchanged transient rebuild', () {
    final order = NeedMaterialOrder();
    final initial = <MissingMaterial>[
      _material(
        'Wolf Blood',
        900,
        choice: _bloodChoiceFor(parent: 'Clown Blood', selected: 'Wolf Blood'),
      ),
      _material('Powder of Flame', 800),
    ];
    var visible = order.apply(initial);
    order.stageSubstitute(source: visible.first, selection: 'Flamingo Blood');

    expect(order.apply(initial).map((row) => row.name), <String>[
      'Wolf Blood',
      'Powder of Flame',
    ]);
    visible = order.apply(<MissingMaterial>[
      _material('Powder of Flame', 800),
      _material(
        'Flamingo Blood',
        600,
        choice: _bloodChoiceFor(
          parent: 'Clown Blood',
          selected: 'Flamingo Blood',
        ),
      ),
    ]);
    expect(visible.map((row) => row.name), <String>[
      'Flamingo Blood',
      'Powder of Flame',
    ]);
  });

  test('duplicate choice identities are disambiguated by material name', () {
    final order = NeedMaterialOrder();
    order.apply(<MissingMaterial>[
      _material(
        'Wolf Blood',
        900,
        choice: _bloodChoiceFor(parent: 'Clown Blood', selected: 'Wolf Blood'),
      ),
      _material(
        'Flamingo Blood',
        800,
        choice: _bloodChoiceFor(
          parent: 'Clown Blood',
          selected: 'Flamingo Blood',
        ),
      ),
    ]);

    expect(
      order
          .apply(<MissingMaterial>[
            _material(
              'Flamingo Blood',
              950,
              choice: _bloodChoiceFor(
                parent: 'Clown Blood',
                selected: 'Flamingo Blood',
              ),
            ),
            _material(
              'Wolf Blood',
              700,
              choice: _bloodChoiceFor(
                parent: 'Clown Blood',
                selected: 'Wolf Blood',
              ),
            ),
          ])
          .map((row) => row.name),
      <String>['Wolf Blood', 'Flamingo Blood'],
    );
  });
}

ChoiceMeta _bloodChoice(String selected) => ChoiceMeta(
  parentName: 'Clear Liquid Reagent',
  original: 'Wolf Blood',
  substituteGroup: 'Blood Group 1',
  options: const <String>['Wolf Blood', 'Sheep Blood'],
  baseName: selected,
);

ChoiceMeta _bloodChoiceFor({
  required String parent,
  required String selected,
}) => ChoiceMeta(
  parentName: parent,
  original: 'Wolf Blood',
  substituteGroup: 'Blood Group 1',
  options: const <String>['Wolf Blood', 'Flamingo Blood', 'Rhino Blood'],
  baseName: selected,
);

MissingMaterial _material(String name, double missing, {ChoiceMeta? choice}) =>
    MissingMaterial(
      name: name,
      key: name,
      category: 'Alchemy Materials',
      need: missing,
      have: 0,
      missing: missing,
      choice: choice,
      market: const MarketMaterialState(
        marketable: true,
        stock: 0,
        price: 0,
        buyable: 0,
        unavailable: 0,
        total: 0,
        status: 'missing',
        hasSourceInfo: false,
      ),
    );
