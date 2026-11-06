import 'dart:async';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_card_reading.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
import 'package:bdo_craft_planner_flutter/features/shared/availability_game_icon.dart';
import 'package:bdo_craft_planner_flutter/features/shared/market_count_badges.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/choice_market_transport.dart';
import 'planner_review_projection_test.dart' as projection;

void main() {
  late CatalogSnapshot catalog;
  setUpAll(() {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
  });
  testWidgets(
    'chooser reuses shared receipts, omits NPCs, preserves identity and cancels on close',
    (tester) async {
      final app = projection.controller(
        catalog,
        CraftMode.cooking,
        'Beer',
        100,
      );
      final transport = ChoiceMarketTransport();
      final broker = SharedMarketRepository(
        transport: transport,
        requestSpacing: Duration.zero,
      );
      final corn = app.active.recipes['Corn']!.marketId!;
      OpportunityMarketItem? shown;
      Widget host() => MaterialApp(
        home: PlannerChoiceMarketScope(
          repository: broker,
          child: PlannerChoiceMarket(
            controller: app.active,
            names: const ['Corn', 'Sugar', 'Not a real item'],
            builder: (context, marketFor, now) {
              shown = marketFor('Corn');
              expect(marketFor('Sugar'), isNull);
              expect(marketFor('Not a real item'), isNull);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(host());
      await settle(tester, broker);
      expect(shown?.basePrice, 480);
      expect(shown?.stockFor(DateTime.now(), sharedMarketFreshness), 12594);
      expect(shown?.preorderCount, 0);
      expect(transport.requests.expand((r) => r.ids).toSet(), {corn});
      expect(transport.requests.where((r) => r.book), hasLength(1));
      final count = transport.requests.length;
      await tester.pumpWidget(host());
      await tester.pump(const Duration(seconds: 1));
      expect(transport.requests, hasLength(count));

      // A region change cannot temporarily paint the previous region's receipt.
      transport.hold = Completer<void>();
      app.active.setMarketRegion('na');
      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 200));
      expect(shown, isNull);
      expect(transport.requests.last.region, 'na');
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(transport.aborted, isTrue);
      transport.hold!.complete();
      await broker.close();
      await app.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'badges retain exact counts, game market/cart symbols and NPC source',
    (tester) async {
      for (final entry in [
        (12594, 84, false, AvailabilityArtwork.stock, '12.594'),
        (0, 84, false, AvailabilityArtwork.stock, '0'),
        (null, null, false, AvailabilityArtwork.stock, '—'),
        (12594, 84, true, AvailabilityArtwork.npc, 'NPC'),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: ThemeSpecScope(
              spec: RetainedThemeRegistry.themes.first,
              child: Scaffold(
                body: MarketCountBadges(
                  stock: entry.$1,
                  preorders: entry.$2,
                  npc: entry.$3,
                ),
              ),
            ),
          ),
        );
        expect(find.text(entry.$5), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w is AvailabilityGameIcon && w.artwork == entry.$4,
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('availability-game-icon:preorders')),
          entry.$2 != null && !entry.$3 ? findsOneWidget : findsNothing,
        );
        expect(find.byType(Tooltip), findsNothing);
        if (entry.$3) expect(find.textContaining('Stock'), findsNothing);
      }
    },
  );

  test(
    'cross-mode lookup tolerates case only, is opt-in, and respects exclusions',
    () async {
      final app = projection.controller(
        catalog,
        CraftMode.processing,
        'Essence of Liquor',
        1,
      );
      addTearDown(app.dispose);
      final processing = app.active;
      expect(
        choiceMarketIdentity(processing, 'Essence of Liquor').marketId,
        isNull,
      );
      expect(
        choiceMarketIdentity(
          processing,
          'Essence of Liquor',
          acrossModes: true,
        ).marketId,
        '9057',
      );
      expect(
        choiceMarketIdentity(
          processing,
          'essence of liquor',
          acrossModes: true,
        ).marketId,
        '9057',
      );
      expect(
        choiceMarketIdentity(
          processing,
          'Unverified Liquor',
          acrossModes: true,
        ).marketId,
        isNull,
      );
      for (final mode in [processing, app.modes[CraftMode.cooking]!]) {
        mode.replaceMarketValues(
          prices: const {},
          stock: const {},
          unlistedItemNames: const {'Essence of Liquor'},
          fetchedAt: 1,
        );
        expect(
          choiceMarketIdentity(
            processing,
            'Essence of Liquor',
            acrossModes: true,
          ).marketId,
          isNull,
        );
        mode.replaceMarketValues(
          prices: const {},
          stock: const {},
          unlistedItemNames: const {},
          fetchedAt: 2,
        );
      }
    },
  );

  test(
    'Insectivore alternatives resolve exact stock identities in every mode and retain exclusions',
    () async {
      final app = projection.controller(
        catalog,
        CraftMode.alchemy,
        'Insectivore Plant Powder',
        1,
      );
      addTearDown(app.dispose);
      for (final mode in app.modes.values) {
        for (final entry in const {
          'Insectivore Plant Leaf': '5441',
          'Insectivore Plant Root': '5443',
        }.entries) {
          final identity = choiceMarketIdentity(
            mode,
            entry.key,
            acrossModes: true,
          );
          expect(identity.marketId, entry.value);
          expect(identity.npc, isFalse);
          mode.replaceMarketValues(
            prices: const {},
            stock: const {},
            unlistedItemNames: {entry.key},
            fetchedAt: 1,
          );
          expect(
            choiceMarketIdentity(mode, entry.key, acrossModes: true).marketId,
            isNull,
          );
          mode.replaceMarketValues(
            prices: const {},
            stock: const {},
            unlistedItemNames: const {},
            fetchedAt: 2,
          );
        }
      }
    },
  );

  test('cross-mode conflicting exact identities stay unknown', () async {
    final base = catalog.alchemy;
    final conflict = CatalogSnapshot(
      sourceSha256: 'synthetic-conflict',
      sourceByteCount: 0,
      cooking: catalog.cooking,
      processing: catalog.processing,
      supportingData: catalog.supportingData,
      collisions: const [],
      alchemy: ModeCatalog(
        mode: CraftMode.alchemy,
        items: {
          ...base.items,
          'Essence of Liquor': Recipe(
            name: 'Essence of Liquor',
            type: 'material',
            baseOutput: 1,
            group: null,
            method: null,
            ingredients: const [],
            marketId: '123456',
            sourceNote: null,
            vendor: null,
            location: null,
            npcPrice: 0,
            qualityBase: null,
            qualityGrade: null,
            outputMinimum: null,
            outputMaximum: null,
          ),
        },
        iconDataUris: base.iconDataUris,
        defaults: base.defaults,
        metadata: base.metadata,
        searchAliases: base.searchAliases,
      ),
    );
    final app = projection.controller(
      conflict,
      CraftMode.processing,
      'Essence of Liquor',
      1,
    );
    addTearDown(app.dispose);
    expect(
      choiceMarketIdentity(
        app.active,
        'Essence of Liquor',
        acrossModes: true,
      ).marketId,
      isNull,
    );
  });

  test('expired quote and incomplete book stay unknown, not zero or mixed', () {
    final now = DateTime.now();
    final stale = OpportunityMarketItem(
      itemId: '1',
      basePrice: 480,
      stock: 100,
      quoteFetchedAt: now.subtract(const Duration(minutes: 6)),
      asks: const [],
      bids: const [OpportunityMarketLevel(price: 480, quantity: 84)],
      bookFetchedAt: now.subtract(const Duration(minutes: 6)),
    );
    expect(stale.quoteIsFresh(now, sharedMarketFreshness), isFalse);
    final reading = OpportunityCardStock(stale, now, sharedMarketFreshness);
    expect(reading.stock, isNull);
    expect(reading.preorders, isNull);
    expect(reading.tone, OpportunityStockTone.unknown);
    final partial = OpportunityMarketItem(
      itemId: '1',
      basePrice: 480,
      stock: 100,
      quoteFetchedAt: now,
      bids: const [OpportunityMarketLevel(price: 480, quantity: 84)],
      bookFetchedAt: now,
    );
    expect(
      OpportunityCardStock(partial, now, sharedMarketFreshness).tone,
      OpportunityStockTone.available,
    );
    expect(
      OpportunityCardStock(partial, now, sharedMarketFreshness).preorders,
      isNull,
    );
  });
}

Future<void> settle(WidgetTester tester, SharedMarketRepository broker) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (broker.diagnostics.activeRequests == 0 &&
        broker.diagnostics.queuedParts == 0) {
      break;
    }
  }
  await tester.pump(const Duration(milliseconds: 200));
}
