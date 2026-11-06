import 'dart:async';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/market_eligibility.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/shared/source_availability_badges.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/availability_badge_finders.dart';
import '../../support/choice_market_transport.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as projection;

void main() {
  late CatalogSnapshot catalog;
  setUpAll(() {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
  });

  test(
    'bound sea references cannot acquire a market identity in any mode',
    () async {
      final app = projection.controller(
        catalog,
        CraftMode.processing,
        'Red Pepper Powder',
        100,
      );
      try {
        for (final mode in app.modes.values) {
          for (final name in [
            'Origin of Serni',
            'Eltro Crystal',
            'Zulatia Crystal',
            'Eltro Sea Crystal',
            'Serni Sea Crystal',
            'Zulatia Sea Crystal',
            'Margoria Sea Crystal',
          ]) {
            expect(
              choiceMarketIdentity(mode, name, acrossModes: true).marketId,
              isNull,
              reason: '${mode.mode}/$name',
            );
          }
        }
      } finally {
        await app.dispose();
      }
    },
  );

  for (final host in ['pinned', 'hover', 'passive', 'inline']) {
    testWidgets('$host source uses shared stock and preorder pills', (
      tester,
    ) async {
      final app = projection.controller(
        catalog,
        CraftMode.cooking,
        'Beer',
        100,
      );
      final book = _book(app.active, catalog);
      final transport = ChoiceMarketTransport();
      final id = app.active.recipes['Corn']!.marketId!;
      transport.values[id] = (price: 100, stock: 12594, preorders: 84);
      final broker = SharedMarketRepository(
        transport: transport,
        requestSpacing: Duration.zero,
      );
      final before = app.active.state.value.toJson();
      final info = _info('Corn', [
        'Central Market · When in stock',
        'Garden · Grow Corn',
      ]);
      try {
        await tester.pumpWidget(_host(book, info, broker: broker, host: host));
        await settle(tester, broker);
        expect(find.text('Central Market'), findsOneWidget);
        expect(find.textContaining('When in stock'), findsNothing);
        expect(stockBadgeText('12.594'), findsOneWidget);
        expect(find.text('Orders 84'), findsOneWidget);
        expect(find.text('Garden · Grow Corn'), findsOneWidget);
        expect(find.byType(Tooltip), findsNothing);
        expect(transport.requests.expand((r) => r.ids).toSet(), {id});
        final requests = transport.requests.length;
        await tester.pumpWidget(_host(book, info, broker: broker, host: host));
        await tester.pump(const Duration(seconds: 1));
        expect(transport.requests.length, requests);
        expect(info.acquisitionNotes.first, 'Central Market · When in stock');
        expect(app.active.state.value.toJson(), before);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await broker.close();
        book.dispose();
        await app.dispose();
      }
    });
  }

  for (final counts in [(2532, 0), (0, 84), (0, 0)]) {
    testWidgets(
      'source counts $counts distinguish zero and positive preorders',
      (tester) async {
        final app = projection.controller(
          catalog,
          CraftMode.cooking,
          'Beer',
          100,
        );
        final book = _book(app.active, catalog);
        final transport = ChoiceMarketTransport();
        final id = app.active.recipes['Corn']!.marketId!;
        transport.values[id] = (
          price: 100,
          stock: counts.$1,
          preorders: counts.$2,
        );
        final broker = SharedMarketRepository(
          transport: transport,
          requestSpacing: Duration.zero,
        );
        try {
          await tester.pumpWidget(
            _host(book, _info('Corn', ['Central Market']), broker: broker),
          );
          await settle(tester, broker);
          expect(
            stockBadgeText(counts.$1 == 0 ? '0' : '2.532'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Orders'),
            counts.$2 > 0 ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const ValueKey('availability-game-icon:stock')),
            findsOneWidget,
          );
        } finally {
          await tester.pumpWidget(const SizedBox());
          await broker.close();
          book.dispose();
          await app.dispose();
        }
      },
    );
  }

  testWidgets('missing broker or identity is unknown, never zero', (
    tester,
  ) async {
    final app = projection.controller(catalog, CraftMode.cooking, 'Beer', 100);
    final book = _book(app.active, catalog);
    final transport = ChoiceMarketTransport();
    final broker = SharedMarketRepository(
      transport: transport,
      requestSpacing: Duration.zero,
    );
    try {
      await tester.pumpWidget(_host(book, _info('Corn', ['Central Market'])));
      expect(stockBadgeText('—'), findsOneWidget);
      expect(stockBadgeText('0'), findsNothing);
      await tester.pumpWidget(
        _host(
          book,
          _info('Unknown material', ['Central Market']),
          broker: broker,
        ),
      );
      await settle(tester, broker);
      expect(stockBadgeText('—'), findsOneWidget);
      expect(transport.requests, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await broker.close();
      book.dispose();
      await app.dispose();
    }
  });

  testWidgets(
    'compound purchase restrictions remain; prohibitions and archived facts do not fetch',
    (tester) async {
      final app = projection.controller(
        catalog,
        CraftMode.cooking,
        'Beer',
        100,
      );
      final book = _book(app.active, catalog);
      final transport = ChoiceMarketTransport();
      final broker = SharedMarketRepository(
        transport: transport,
        requestSpacing: Duration.zero,
      );
      try {
        for (final info in [
          _info('Corn', ['Cannot be registered on the Central Market.']),
          _info('Corn', ['Central Market'], archived: true),
        ]) {
          await tester.pumpWidget(_host(book, info, broker: broker));
          await settle(tester, broker);
          expect(find.byType(SourceAvailabilityBadges), findsNothing);
          expect(transport.requests, isEmpty);
        }
        const source =
            'Buy Corn on the Central Market, or grow it in a garden.';
        await tester.pumpWidget(
          _host(book, _info('Corn', [source]), broker: broker),
        );
        await settle(tester, broker);
        expect(find.text(source), findsOneWidget);
        expect(stockBadgeText('12.594'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await broker.close();
        book.dispose();
        await app.dispose();
      }
    },
  );

  testWidgets(
    'region and item changes clear old receipts and closing cancels',
    (tester) async {
      final app = projection.controller(
        catalog,
        CraftMode.cooking,
        'Beer',
        100,
      );
      final book = _book(app.active, catalog);
      final transport = ChoiceMarketTransport();
      final broker = SharedMarketRepository(
        transport: transport,
        requestSpacing: Duration.zero,
      );
      try {
        await tester.pumpWidget(
          _host(book, _info('Corn', ['Central Market']), broker: broker),
        );
        await settle(tester, broker);
        expect(stockBadgeText('12.594'), findsOneWidget);
        transport.hold = Completer<void>();
        app.active.setMarketRegion('na');
        await tester.pump(const Duration(milliseconds: 250));
        expect(stockBadgeText('—'), findsOneWidget);
        expect(stockBadgeText('12.594'), findsNothing);
        await tester.pumpWidget(
          _host(book, _info('Wheat', ['Central Market']), broker: broker),
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(stockBadgeText('—'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        expect(transport.aborted, isTrue);
        transport.hold!.complete();
        await settle(tester, broker);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await broker.close();
        book.dispose();
        await app.dispose();
      }
    },
  );

  testWidgets('explicit market source does not replace stock with NPC', (
    tester,
  ) async {
    final app = projection.controller(catalog, CraftMode.cooking, 'Beer', 100);
    final book = _book(app.active, catalog);
    final recipe = app.active.recipes.values.firstWhere(
      (r) =>
          r.marketId != null &&
          isOpportunityMarketRequestEligible(r.marketId!) &&
          app.active.resolveItemSource(r.name, recipe: r).npcPrice > 0,
    );
    final transport = ChoiceMarketTransport();
    final broker = SharedMarketRepository(
      transport: transport,
      requestSpacing: Duration.zero,
    );
    try {
      await tester.pumpWidget(
        _host(book, _info(recipe.name, ['Central Market']), broker: broker),
      );
      await settle(tester, broker);
      expect(stockBadgeText('12.594'), findsOneWidget);
      expect(find.text('NPC'), findsNothing);
      expect(transport.requests.expand((r) => r.ids).toSet(), {
        recipe.marketId,
      });
    } finally {
      await tester.pumpWidget(const SizedBox());
      await broker.close();
      book.dispose();
      await app.dispose();
    }
  });

  for (final staleBook in [false, true, null]) {
    testWidgets(
      'stock and preorder freshness are independent; stale book $staleBook',
      (tester) async {
        final app = projection.controller(
          catalog,
          CraftMode.cooking,
          'Beer',
          100,
        );
        final book = _book(app.active, catalog);
        final id = app.active.recipes['Corn']!.marketId!;
        final key = SharedMarketKey(
          region: app.active.state.value.market.region,
          itemId: id,
        );
        final transport = ChoiceMarketTransport();
        transport.values[id] = (price: 100, stock: 12594, preorders: 84);
        var clock = DateTime.now().subtract(const Duration(minutes: 6));
        final broker = SharedMarketRepository(
          transport: transport,
          requestSpacing: Duration.zero,
          utcNow: () => clock,
        );
        try {
          final old = broker.fetch(quoteKeys: [key], bookKeys: [key]);
          await settle(tester, broker);
          await old;
          clock = DateTime.now();
          if (staleBook != null) {
            transport.values[id] = (price: 100, stock: 5678, preorders: 9);
            final fresh = broker.fetch(
              quoteKeys: staleBook ? [key] : [],
              bookKeys: staleBook ? [] : [key],
              maxAge: sharedMarketFreshness,
            );
            await settle(tester, broker);
            await fresh;
          }
          transport.hold = Completer<void>();
          await tester.pumpWidget(
            _host(book, _info('Corn', ['Central Market']), broker: broker),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            stockBadgeText(staleBook == null ? '—' : '5.678'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Orders'),
            staleBook == false ? findsOneWidget : findsNothing,
          );
          if (staleBook == false) {
            expect(find.text('Orders 9'), findsOneWidget);
          }
          await tester.pumpWidget(const SizedBox());
          transport.hold!.complete();
          await settle(tester, broker);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await broker.close();
          book.dispose();
          await app.dispose();
        }
      },
    );
  }

  for (final spec in RetainedThemeRegistry.themes) {
    for (final host in ['pinned', 'hover', 'passive', 'inline']) {
      for (final size in [(480.0, 1.0), (240.0, 1.0), (300.0, 2.0)]) {
        testWidgets(
          'adjacent source preserves restrictions ${spec.id} $host $size',
          (tester) async {
            final app = projection.controller(
              catalog,
              CraftMode.cooking,
              'Beer',
              100,
            );
            final book = _book(app.active, catalog);
            final before = app.active.state.value.toJson();
            try {
              for (final source in [
                'Central Market',
                'Buy Corn on the Central Market, or grow it in a garden.',
                'Buy Corn on the Central Market.\nOnly registered items can be bought.',
              ]) {
                await tester.pumpWidget(
                  _host(
                    book,
                    _info('Corn', [source]),
                    host: host,
                    spec: spec,
                    width: size.$1,
                    scale: size.$2,
                  ),
                );
                await tester.pumpAndSettle();
                for (final line in source.split('\n')) {
                  expect(find.text(line), findsOneWidget);
                }
                final label = tester.getRect(
                  find
                      .ancestor(
                        of: find.text(source.split('\n').first),
                        matching: find.byType(IntrinsicWidth),
                      )
                      .first,
                );
                final badge = tester.getRect(
                  find.byType(SourceAvailabilityBadges),
                );
                if (source == 'Central Market' && size.$1 == 480) {
                  expect(badge.left - label.right, closeTo(12, .1));
                } else {
                  expect(badge.top - label.bottom, closeTo(6, .1));
                  expect(badge.left, closeTo(label.left, .1));
                }
                expect(badge.width, lessThanOrEqualTo(size.$1));
                expect(stockBadgeText('—'), findsOneWidget);
                expect(stockBadgeText('0'), findsNothing);
                expect(find.byType(Tooltip), findsNothing);
                expect(tester.takeException(), isNull);
              }
              expect(app.active.state.value.toJson(), before);
            } finally {
              await tester.pumpWidget(const SizedBox());
              book.dispose();
              await app.dispose();
            }
          },
        );
      }
    }
    for (final size in [(480.0, 1.0), (300.0, 2.0)]) {
      testWidgets('adjacent source badges reflow ${spec.id} $size', (
        tester,
      ) async {
        final app = projection.controller(
          catalog,
          CraftMode.cooking,
          'Beer',
          100,
        );
        final book = _book(app.active, catalog);
        try {
          await tester.pumpWidget(
            _host(
              book,
              _info('Corn', ['Central Market']),
              spec: spec,
              width: size.$1,
              scale: size.$2,
            ),
          );
          final label = tester.getRect(find.text('Central Market'));
          final badge = tester.getRect(find.byType(SourceAvailabilityBadges));
          if (size.$2 == 1) {
            expect(badge.left - label.right, closeTo(12, .1));
          } else {
            expect(badge.top, greaterThanOrEqualTo(label.bottom));
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          book.dispose();
          await app.dispose();
        }
      });
    }
  }
}

RecipeBookController _book(
  ModeFeatureController mode,
  CatalogSnapshot catalog,
) => RecipeBookController(
  modeController: mode,
  catalogRepository: CatalogRepository(catalog),
  callingContext: RecipeBookCallingContext.planner,
  allowedTargets: mode.craftableNames,
);

RecipeBookItemInfo _info(
  String name,
  List<String> sources, {
  bool archived = false,
}) => RecipeBookItemInfo(
  title: name,
  kind: 'Recipe material',
  summary: '',
  acquisitionNotes: sources,
  isTemporarilyArchived: archived,
);

Widget _host(
  RecipeBookController book,
  RecipeBookItemInfo info, {
  SharedMarketRepository? broker,
  String host = 'pinned',
  ThemeSpec spec = SakuraNightGardenSpec.theme,
  double width = 480,
  double scale = 1,
}) {
  final child = host == 'inline'
      ? ItemReferenceSections(
          controller: book,
          mode: CraftMode.cooking,
          name: info.title,
          info: info,
          spec: spec,
        )
      : ItemReferenceCard(
          controller: book,
          mode: CraftMode.cooking,
          name: info.title,
          info: info,
          spec: spec,
          maxWidth: width,
          interactive: host != 'passive',
          onClose: host == 'pinned' ? () {} : null,
          icon: const SizedBox(width: 44, height: 44),
        );
  // Embedded prose relies on its host's scrolling; it does not own a second
  // window or scroll view. Model that host for long, enlarged restrictions.
  final hosted = host == 'inline'
      ? SingleChildScrollView(primary: false, child: child)
      : child;
  return MaterialApp(
    theme: spec.materialTheme(),
    home: ThemeSpecScope(
      spec: spec,
      child: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: Center(
              child: SizedBox(
                width: width,
                child: broker == null
                    ? hosted
                    : PlannerChoiceMarketScope(
                        repository: broker,
                        child: hosted,
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
