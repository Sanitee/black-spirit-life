import 'dart:ui' as ui;

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveBdoGatheringTools', () {
    const currentToolValues =
        <
          String,
          ({
            List<BdoGatheringToolKind> tools,
            BdoGatheringToolRelation relation,
          })
        >{
          'Bare hands / Hoe': (
            tools: <BdoGatheringToolKind>[
              BdoGatheringToolKind.bareHands,
              BdoGatheringToolKind.hoe,
            ],
            relation: BdoGatheringToolRelation.alternative,
          ),
          'Bare Hands or Hoe': (
            tools: <BdoGatheringToolKind>[
              BdoGatheringToolKind.bareHands,
              BdoGatheringToolKind.hoe,
            ],
            relation: BdoGatheringToolRelation.alternative,
          ),
          'Butcher Knife': (
            tools: <BdoGatheringToolKind>[BdoGatheringToolKind.butcherKnife],
            relation: BdoGatheringToolRelation.single,
          ),
          'Combat': (
            tools: <BdoGatheringToolKind>[BdoGatheringToolKind.combat],
            relation: BdoGatheringToolRelation.single,
          ),
          'Fluid Collector': (
            tools: <BdoGatheringToolKind>[BdoGatheringToolKind.fluidCollector],
            relation: BdoGatheringToolRelation.single,
          ),
          'Hoe': (
            tools: <BdoGatheringToolKind>[BdoGatheringToolKind.hoe],
            relation: BdoGatheringToolRelation.single,
          ),
          'Hunting Matchlock and Butcher Knife': (
            tools: <BdoGatheringToolKind>[
              BdoGatheringToolKind.huntingMatchlock,
              BdoGatheringToolKind.butcherKnife,
            ],
            relation: BdoGatheringToolRelation.requiredTogether,
          ),
          'Lumbering Axe': (
            tools: <BdoGatheringToolKind>[BdoGatheringToolKind.lumberingAxe],
            relation: BdoGatheringToolRelation.single,
          ),
          'Pickaxe': (
            tools: <BdoGatheringToolKind>[BdoGatheringToolKind.pickaxe],
            relation: BdoGatheringToolRelation.single,
          ),
          'Sniper Rifle + Butcher Knife': (
            tools: <BdoGatheringToolKind>[
              BdoGatheringToolKind.sniperRifle,
              BdoGatheringToolKind.butcherKnife,
            ],
            relation: BdoGatheringToolRelation.requiredTogether,
          ),
          'Tanning Knife': (
            tools: <BdoGatheringToolKind>[BdoGatheringToolKind.tanningKnife],
            relation: BdoGatheringToolRelation.single,
          ),
        };

    test('covers every current serialized field-product tool value', () {
      for (final entry in currentToolValues.entries) {
        final resolved = resolveBdoGatheringTools(entry.key);
        expect(resolved.tools, entry.value.tools, reason: entry.key);
        expect(resolved.relation, entry.value.relation, reason: entry.key);
        expect(
          resolved.tools,
          isNot(contains(BdoGatheringToolKind.unknown)),
          reason: entry.key,
        );
      }
    });

    test('normalizes case and repeated whitespace', () {
      final resolved = resolveBdoGatheringTools(
        '  HUNTING   matchlock AND butcher KNIFE  ',
      );

      expect(resolved.tools, <BdoGatheringToolKind>[
        BdoGatheringToolKind.huntingMatchlock,
        BdoGatheringToolKind.butcherKnife,
      ]);
      expect(resolved.relation, BdoGatheringToolRelation.requiredTogether);
      expect(resolved.displayLabel, 'Hunting Matchlock and Butcher Knife');
    });

    test('keeps alternatives distinct from tools required together', () {
      final alternative = resolveBdoGatheringTools('Bare hands / Hoe');
      final together = resolveBdoGatheringTools('Sniper Rifle + Butcher Knife');

      expect(alternative.relation, BdoGatheringToolRelation.alternative);
      expect(alternative.displayLabel, 'Bare hands or Hoe');
      expect(together.relation, BdoGatheringToolRelation.requiredTogether);
      expect(together.displayLabel, 'Sniper Rifle and Butcher Knife');
    });

    test('uses a visible fallback for an unknown value', () {
      final resolved = resolveBdoGatheringTools('Future gathering gadget');

      expect(resolved.tools, <BdoGatheringToolKind>[
        BdoGatheringToolKind.unknown,
      ]);
      expect(resolved.relation, BdoGatheringToolRelation.single);
      expect(resolved.displayLabel, 'Unknown tool');
    });

    test('maps real tools to stable catalog item names', () {
      expect(
        <BdoGatheringToolKind, String?>{
          for (final tool in BdoGatheringToolKind.values)
            tool: bdoGatheringToolCatalogItemName(tool),
        },
        const <BdoGatheringToolKind, String?>{
          BdoGatheringToolKind.bareHands: null,
          BdoGatheringToolKind.hoe: 'Hoe',
          BdoGatheringToolKind.fluidCollector: 'Fluid Collector',
          BdoGatheringToolKind.lumberingAxe: 'Lumbering Axe',
          BdoGatheringToolKind.pickaxe: 'Pickaxe',
          BdoGatheringToolKind.butcherKnife: 'Butcher Knife',
          BdoGatheringToolKind.tanningKnife: 'Tanning Knife',
          BdoGatheringToolKind.combat: null,
          BdoGatheringToolKind.huntingMatchlock: 'Hunting Matchlock',
          BdoGatheringToolKind.sniperRifle: '[Hunting] Sniper Rifle',
          BdoGatheringToolKind.unknown: null,
        },
      );
    });

    test('maps real tools to reviewed local artwork', () {
      expect(
        <BdoGatheringToolKind, String?>{
          for (final tool in BdoGatheringToolKind.values)
            tool: bdoGatheringToolAssetPath(tool),
        },
        const <BdoGatheringToolKind, String?>{
          BdoGatheringToolKind.bareHands: null,
          BdoGatheringToolKind.hoe: 'assets/images/gathering_tools/hoe.webp',
          BdoGatheringToolKind.fluidCollector:
              'assets/images/gathering_tools/fluid_collector.webp',
          BdoGatheringToolKind.lumberingAxe:
              'assets/images/gathering_tools/lumbering_axe.webp',
          BdoGatheringToolKind.pickaxe:
              'assets/images/gathering_tools/pickaxe.webp',
          BdoGatheringToolKind.butcherKnife:
              'assets/images/gathering_tools/butcher_knife.webp',
          BdoGatheringToolKind.tanningKnife:
              'assets/images/gathering_tools/tanning_knife.webp',
          BdoGatheringToolKind.combat: null,
          BdoGatheringToolKind.huntingMatchlock:
              'assets/images/gathering_tools/hunting_matchlock.webp',
          BdoGatheringToolKind.sniperRifle:
              'assets/images/gathering_tools/sniper_rifle.webp',
          BdoGatheringToolKind.unknown: null,
        },
      );
    });
  });

  group('BdoGatheringToolIcon', () {
    const bundledArtwork = <String, ({String asset, String sha256})>{
      'Lumbering Axe': (
        asset: 'assets/images/gathering_tools/lumbering_axe.webp',
        sha256:
            '134279e4e49281729ad9ace3bc5bb65a0f65b494afa107fe27cf1ba7961c723f',
      ),
      'Fluid Collector': (
        asset: 'assets/images/gathering_tools/fluid_collector.webp',
        sha256:
            '5bc4c1df3dc784c02242ef21d74519d10512f8e13f93c4e59d743f2ceefd14fb',
      ),
      'Hoe': (
        asset: 'assets/images/gathering_tools/hoe.webp',
        sha256:
            '5599ade25df6c7a41b61577f8140684fe23505347819c3e2344bd5925d16a120',
      ),
      'Butcher Knife': (
        asset: 'assets/images/gathering_tools/butcher_knife.webp',
        sha256:
            '3c76e91d768833fe0d738b555cf617d3e1956807da54962994b7f6a39e12418e',
      ),
      'Tanning Knife': (
        asset: 'assets/images/gathering_tools/tanning_knife.webp',
        sha256:
            'bcef0bef7bdd02aa8f7c858b592eb243cef1e6a38c4b2893f3a04fd070a7bfd2',
      ),
      'Pickaxe': (
        asset: 'assets/images/gathering_tools/pickaxe.webp',
        sha256:
            '8896c0ebeeb608073453e504c10927cf8a7d6083dec4c6a9137116461933b27f',
      ),
      'Hunting Matchlock': (
        asset: 'assets/images/gathering_tools/hunting_matchlock.webp',
        sha256:
            '92951cb230c9f317d89eeea7a65a98a1847c1bb4eca4e5562a469555b332f2ce',
      ),
      'Sniper Rifle': (
        asset: 'assets/images/gathering_tools/sniper_rifle.webp',
        sha256:
            '0655dd10df497f9d0e37d91ce1abc2bad9c88a34a4b761dd1d9e8ef23dd5ecfc',
      ),
    };

    testWidgets(
      'uses every reviewed bundled artwork instead of a generic icon fallback',
      (tester) async {
        for (final entry in bundledArtwork.entries) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: BdoGatheringToolIcon(tool: entry.key, size: 24),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final icon = find.byType(BdoGatheringToolIcon);
          final imageFinder = find.descendant(
            of: icon,
            matching: find.byType(Image),
          );
          expect(imageFinder, findsOneWidget, reason: entry.key);
          final image = tester.widget<Image>(imageFinder);
          expect(image.image, isA<AssetImage>(), reason: entry.key);
          final provider = image.image as AssetImage;
          expect(provider.assetName, entry.value.asset, reason: entry.key);
          expect(
            provider.package,
            bdoGatheringToolAssetPackage,
            reason: entry.key,
          );
          expect(
            find.descendant(of: icon, matching: find.byType(Icon)),
            findsNothing,
            reason: entry.key,
          );
          expect(
            find.descendant(of: icon, matching: find.byType(CustomPaint)),
            findsNothing,
            reason: entry.key,
          );
          expect(tester.takeException(), isNull, reason: entry.key);
        }
      },
    );

    testWidgets('checksum-locks decoded 44px source artwork', (tester) async {
      await tester.runAsync(() async {
        for (final entry in bundledArtwork.entries) {
          final provider = AssetImage(
            entry.value.asset,
            package: bdoGatheringToolAssetPackage,
          );
          final key = await provider.obtainKey(ImageConfiguration.empty);
          final data = await rootBundle.load(key.name);
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );

          expect(
            sha256.convert(bytes).toString(),
            entry.value.sha256,
            reason: entry.key,
          );

          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          expect(frame.image.width, 44, reason: entry.key);
          expect(frame.image.height, 44, reason: entry.key);
          frame.image.dispose();
          codec.dispose();
        }
      });
    });

    testWidgets('is compact and exposes tooltip and semantics', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: BdoGatheringToolIcon(tool: 'Fluid Collector', size: 20),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(BdoGatheringToolIcon)),
        const Size(20, 20),
      );
      expect(find.byTooltip('Fluid Collector'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Required tool: Fluid Collector'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders two full-size tools with an explicit separator', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: BdoGatheringToolIcon(
                tool: 'Sniper Rifle + Butcher Knife',
                size: 20,
              ),
            ),
          ),
        ),
      );

      final renderedSize = tester.getSize(find.byType(BdoGatheringToolIcon));
      expect(renderedSize, const Size(50, 20));
      expect(
        find.byKey(
          const ValueKey<String>(
            'bdo-gathering-tool-separator-requiredTogether',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('+'), findsOneWidget);
      expect(find.byTooltip('Sniper Rifle and Butcher Knife'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Required tools: Sniper Rifle and Butcher Knife'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses scoped canonical item artwork without adding a frame', (
      tester,
    ) async {
      final requests =
          <({BdoGatheringToolKind tool, String name, double size})>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BdoGatheringToolArtworkScope(
                builder: (context, tool, canonicalItemName, size) {
                  requests.add((
                    tool: tool,
                    name: canonicalItemName,
                    size: size,
                  ));
                  return ColoredBox(
                    key: ValueKey<String>('catalog-art:$canonicalItemName'),
                    color: Colors.teal,
                  );
                },
                child: const BdoGatheringToolIcon(
                  tool: 'Fluid Collector',
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        requests,
        <({BdoGatheringToolKind tool, String name, double size})>[
          (
            tool: BdoGatheringToolKind.fluidCollector,
            name: 'Fluid Collector',
            size: 24,
          ),
        ],
      );
      expect(
        find.byKey(const ValueKey<String>('catalog-art:Fluid Collector')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(BdoGatheringToolIcon),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel('Required tool: Fluid Collector'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps full-size catalog art on both sides of a plus', (
      tester,
    ) async {
      final requests =
          <({BdoGatheringToolKind tool, String name, double size})>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BdoGatheringToolArtworkScope(
                builder: (context, tool, canonicalItemName, size) {
                  requests.add((
                    tool: tool,
                    name: canonicalItemName,
                    size: size,
                  ));
                  return ColoredBox(
                    key: ValueKey<String>('catalog-art:$canonicalItemName'),
                    color: Colors.teal,
                  );
                },
                child: const BdoGatheringToolIcon(
                  tool: 'Sniper Rifle + Butcher Knife',
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(BdoGatheringToolIcon)),
        const Size(55, 22),
      );
      expect(
        requests,
        <({BdoGatheringToolKind tool, String name, double size})>[
          (
            tool: BdoGatheringToolKind.sniperRifle,
            name: '[Hunting] Sniper Rifle',
            size: 22,
          ),
          (
            tool: BdoGatheringToolKind.butcherKnife,
            name: 'Butcher Knife',
            size: 22,
          ),
        ],
      );
      expect(find.text('+'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps a readable vector fallback for non-item methods', (
      tester,
    ) async {
      var catalogRequests = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BdoGatheringToolArtworkScope(
                builder: (context, tool, canonicalItemName, size) {
                  catalogRequests += 1;
                  return const SizedBox.shrink();
                },
                child: const BdoGatheringToolIcon(tool: 'Combat', size: 24),
              ),
            ),
          ),
        ),
      );

      expect(catalogRequests, 0);
      expect(
        find.descendant(
          of: find.byType(BdoGatheringToolIcon),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Combat'), findsOneWidget);
      expect(find.bySemanticsLabel('Required tool: Combat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
