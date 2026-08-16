import 'dart:ui' show Tristate;

import 'package:bdo_map_core/src/widgets/bdo_map_symbols.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BDO map symbol metadata', () {
    test('covers every symbol kind with a named vector icon', () {
      for (final kind in BdoMapSymbolKind.values) {
        final spec = bdoMapSymbolSpec(kind);

        expect(spec.label, isNotEmpty, reason: '$kind needs a readable label');
        expect(spec.icon.fontFamily, 'MaterialIcons');
        expect(spec.shellScale, inInclusiveRange(0.5, 1));
        expect(spec.iconScale, inInclusiveRange(0.3, 0.7));
      }
    });

    test('house usages remain visually distinct', () {
      const houseKinds = {
        BdoMapSymbolKind.residence,
        BdoMapSymbolKind.lodging,
        BdoMapSymbolKind.storage,
        BdoMapSymbolKind.stable,
        BdoMapSymbolKind.shipyard,
        BdoMapSymbolKind.refinery,
        BdoMapSymbolKind.workshop,
      };

      final codePoints = houseKinds
          .map((kind) => bdoMapSymbolSpec(kind).icon.codePoint)
          .toSet();

      expect(codePoints, hasLength(houseKinds.length));
      expect(
        houseKinds.every(bdoMapSymbolUsesHouseSilhouette),
        isTrue,
        reason: 'Every property service must use the gabled house language.',
      );
      expect(bdoMapSymbolUsesHouseSilhouette(BdoMapSymbolKind.city), isFalse);
    });
  });

  group('BDO map symbol states', () {
    test('normalizes common planning flags', () {
      expect(
        bdoMapSymbolStates(
          owned: true,
          recommendedPrerequisite: true,
          selected: true,
        ),
        {
          BdoMapSymbolState.owned,
          BdoMapSymbolState.recommendedPrerequisite,
          BdoMapSymbolState.selected,
        },
      );
      expect(bdoMapSymbolStates(), {BdoMapSymbolState.unowned});
    });

    test('selection accents without erasing the owned treatment', () {
      final owned = bdoMapSymbolStyle({BdoMapSymbolState.owned});
      final selectedOwned = bdoMapSymbolStyle({
        BdoMapSymbolState.owned,
        BdoMapSymbolState.selected,
      });

      expect(selectedOwned.foreground, owned.foreground);
      expect(selectedOwned.background, owned.background);
      expect(
        selectedOwned.border,
        ResourceMapChromeThemeData.sakuraCartographer.accent,
      );
      expect(selectedOwned.borderWidth, greaterThan(owned.borderWidth));
      expect(selectedOwned.semanticStateLabel, 'Owned, selected');
    });

    test('paired map skin changes only the selected chrome modifier', () {
      final states = {
        BdoMapSymbolState.recommendedLodging,
        BdoMapSymbolState.selected,
      };
      final sakura = bdoMapSymbolStyle(
        states,
        chromeTheme: ResourceMapChromeThemeData.sakuraCartographer,
      );
      final ledger = bdoMapSymbolStyle(
        states,
        chromeTheme: ResourceMapChromeThemeData.illuminatedAtlas,
      );

      expect(ledger.foreground, sakura.foreground);
      expect(ledger.background, sakura.background);
      expect(ledger.opacity, sakura.opacity);
      expect(ledger.border, ResourceMapChromeThemeData.illuminatedAtlas.accent);
      expect(ledger.halo, ledger.border.withAlpha(102));
      expect(ledger.border, isNot(sakura.border));
    });

    test(
      'recommendations and unavailable state have deterministic priority',
      () {
        expect(
          bdoMapSymbolStyle({
            BdoMapSymbolState.owned,
            BdoMapSymbolState.recommendedPrerequisite,
          }).semanticStateLabel,
          'Recommended prerequisite',
        );
        expect(
          bdoMapSymbolStyle({
            BdoMapSymbolState.recommendedLodging,
            BdoMapSymbolState.unavailable,
          }).semanticStateLabel,
          'Unavailable',
        );
      },
    );
  });

  testWidgets('renders a house silhouette and exposes its state accessibly', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: BdoMapSymbol(
            key: Key('lodging-symbol'),
            kind: BdoMapSymbolKind.lodging,
            states: {
              BdoMapSymbolState.recommendedLodging,
              BdoMapSymbolState.selected,
            },
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('bdo-house-silhouette-lodging')),
      findsOneWidget,
    );
    expect(
      find.byIcon(bdoMapSymbolSpec(BdoMapSymbolKind.lodging).icon),
      findsNothing,
      reason: 'The map house is not a generic glyph in a square frame.',
    );
    expect(
      find.bySemanticsLabel('Lodging; Recommended lodging, selected'),
      findsOneWidget,
    );

    final node = tester.getSemantics(find.byKey(const Key('lodging-symbol')));
    expect(node.flagsCollection.isImage, isTrue);
    expect(node.flagsCollection.isSelected, Tristate.isTrue);
    expect(node.flagsCollection.isEnabled, Tristate.isTrue);
    semantics.dispose();
  });

  testWidgets('house services use distinct app-authored vector crests', (
    tester,
  ) async {
    const houseKinds = <BdoMapSymbolKind>[
      BdoMapSymbolKind.residence,
      BdoMapSymbolKind.lodging,
      BdoMapSymbolKind.storage,
      BdoMapSymbolKind.stable,
      BdoMapSymbolKind.shipyard,
      BdoMapSymbolKind.refinery,
      BdoMapSymbolKind.workshop,
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Wrap(
          children: <Widget>[
            for (final kind in houseKinds) BdoMapSymbol(kind: kind),
          ],
        ),
      ),
    );

    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<BdoHouseMapSymbolPainter>()
        .toList(growable: false);
    expect(painters, hasLength(houseKinds.length));
    expect(painters.map((painter) => painter.kind).toSet(), houseKinds.toSet());
    expect(
      painters.map((painter) => painter.serviceAccent).toSet(),
      hasLength(houseKinds.length),
      reason: 'Tiny dense-map symbols need a second service cue beyond shape.',
    );
  });

  testWidgets('house silhouettes remain legible across planning states', (
    tester,
  ) async {
    const previewKey = ValueKey<String>('house-symbol-state-preview');
    const houseKinds = <BdoMapSymbolKind>[
      BdoMapSymbolKind.residence,
      BdoMapSymbolKind.lodging,
      BdoMapSymbolKind.storage,
      BdoMapSymbolKind.stable,
      BdoMapSymbolKind.shipyard,
      BdoMapSymbolKind.refinery,
      BdoMapSymbolKind.workshop,
    ];
    const stateRows = <Set<BdoMapSymbolState>>[
      {BdoMapSymbolState.unowned},
      {BdoMapSymbolState.owned},
      {BdoMapSymbolState.recommendedPrerequisite, BdoMapSymbolState.selected},
    ];
    await tester.binding.setSurfaceSize(const Size(470, 210));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0B1210),
          body: Center(
            child: RepaintBoundary(
              key: previewKey,
              child: ColoredBox(
                color: const Color(0xFF14201D),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final states in stateRows)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              for (final kind in houseKinds)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                  ),
                                  child: BdoMapSymbol(
                                    kind: kind,
                                    states: states,
                                    size: 32,
                                  ),
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
        ),
      ),
    );

    await expectLater(
      find.byKey(previewKey),
      matchesGoldenFile('goldens/bdo_house_symbols.png'),
    );
  });

  testWidgets('marks unavailable symbols as disabled', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: BdoMapSymbol(
          key: Key('unavailable-house'),
          kind: BdoMapSymbolKind.workshop,
          states: {BdoMapSymbolState.unavailable},
        ),
      ),
    );

    final node = tester.getSemantics(
      find.byKey(const Key('unavailable-house')),
    );
    expect(node.label, 'Workshop; Unavailable');
    expect(node.flagsCollection.isEnabled, Tristate.isFalse);
    semantics.dispose();
  });

  testWidgets('symbol selection border and shadow follow the map skin', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ResourceMapChromeTheme(
          data: ResourceMapChromeThemeData.illuminatedAtlas,
          child: BdoMapSymbol(
            kind: BdoMapSymbolKind.city,
            states: {BdoMapSymbolState.owned, BdoMapSymbolState.selected},
          ),
        ),
      ),
    );

    final decorations = tester
        .widgetList<Container>(find.byType(Container))
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .toList();
    expect(
      decorations.any(
        (decoration) =>
            decoration.border?.top.color ==
            ResourceMapChromeThemeData.illuminatedAtlas.accent,
      ),
      isTrue,
    );
    expect(
      decorations.any(
        (decoration) =>
            decoration.boxShadow?.any(
              (shadow) =>
                  shadow.color ==
                  ResourceMapChromeThemeData
                      .illuminatedAtlas
                      .selectedShadow
                      .color,
            ) ??
            false,
      ),
      isTrue,
    );
  });
}
