import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bdo_gathering_companion/domain/bairog_calculator.dart';
import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/services/session_store.dart';
import 'package:bdo_gathering_companion/src/domain/gathering_preparation.dart';
import 'package:bdo_gathering_companion/src/gathering_companion_home.dart';
import 'package:bdo_gathering_companion/src/services/host_services.dart';
import 'package:bdo_gathering_companion/src/ui/field_guide.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore extends SessionStore {
  _MemoryStore(Directory directory) : super(directory: directory);

  int saves = 0;

  @override
  Future<void> save() async {
    saves++;
  }
}

// Exercise the host's real market loader, without external requests or changes
// to production injection points. These are deterministic test prices only.
class _MarketFixture implements HttpClient {
  final prices = <int, double>{};
  int preorderRequests = 0;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async => _MarketRequest(this, url);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      throw const HttpException('Offline map tiles in the workflow fixture.');

  @override
  set connectionTimeout(Duration? value) {}

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixtureHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MarketRequest implements HttpClientRequest {
  _MarketRequest(this.fixture, this.uri);
  final _MarketFixture fixture;
  @override
  final Uri uri;
  final _body = <int>[];
  @override
  final HttpHeaders headers = _FixtureHeaders();

  @override
  void add(List<int> data) => _body.addAll(data);

  @override
  Future<HttpClientResponse> close() async {
    final id = (jsonDecode(utf8.decode(_body)) as Map)['mainKey'] as int;
    final price = switch (id) {
      4998 => 5000000,
      4999 => 2000000,
      821348 || 821349 || 821350 || 821351 || 821352 || 821353 => 100000000,
      _ => 100000,
    };
    final orderBook = uri.path.endsWith('GetBiddingInfoList');
    if (orderBook) {
      fixture.preorderRequests++;
    } else {
      fixture.prices[id] = price.toDouble();
    }
    return _MarketResponse(
      utf8.encode(
        jsonEncode({
          'resultCode': 0,
          'resultMsg': orderBook ? '$price-0-500|' : '$id-0-0-$price-0|',
        }),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MarketResponse extends Stream<List<int>> implements HttpClientResponse {
  _MarketResponse(this.bytes);
  final List<int> bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _silver(double value) {
  if (value >= 1000000000) {
    return '${(value / 1000000000).toStringAsFixed(2)}B';
  }
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(value >= 100000000 ? 0 : 1)}M';
  }
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}K';
  return value.toStringAsFixed(0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  late Directory temporaryRoot;

  setUpAll(() async {
    catalog = await Catalog.load();
    temporaryRoot = await Directory.systemTemp.createTemp('bdo-guided-market-');
  });

  tearDownAll(() async {
    if (temporaryRoot.parent.absolute.path !=
            Directory.systemTemp.absolute.path ||
        !temporaryRoot.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('bdo-guided-market-')) {
      throw StateError(
        'Unexpected test directory; refusing recursive removal.',
      );
    }
    await temporaryRoot.delete(recursive: true);
  });

  Finder keyed(String key, {bool skipOffstage = true}) =>
      find.byKey(ValueKey(key), skipOffstage: skipOffstage);

  FieldGuide guide(WidgetTester tester) =>
      tester.widget<FieldGuide>(find.byType(FieldGuide, skipOffstage: false));

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(keyed(key));
    await tester.tap(keyed(key));
    await tester.pumpAndSettle();
  }

  for (final ranking in ['value', 'demand']) {
    testWidgets(
      '$ranking keeps search, tool and sort through stats, Cancel and buffs',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1563, 950);
        addTearDown(tester.view.reset);
        final profile = GatheringPreparation(
          statsConfirmed: true,
          baseSettings: const BairogCalculatorSettings(
            mastery: 1500,
            gatheringDropRatePercent: 20,
            enabledExpenseItemIds: {},
          ),
        );
        final store = _MemoryStore(temporaryRoot)
          ..preferences = {
            'methodId': 'butcher',
            'spotId': 'ancado-lions',
            gatheringPreparationPreferenceKey: profile.toJson(),
          };
        final fixture = _MarketFixture();
        final rankingKey = ranking == 'value' ? 'profit' : ranking;
        await HttpOverrides.runZoned(() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: companionTheme(),
              builder: companionBackdropBuilder,
              home: GatheringHostServicesScope(
                services: GatheringHostServices(
                  openExternal: (_) async => true,
                ),
                child: CompanionHome(
                  catalog: catalog,
                  store: store,
                  glassOpacityPercent: defaultGlassOpacityPercent,
                  onGlassOpacityChanged: (_) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final guideState = tester.state(find.byType(FieldGuide));
          await tester.enterText(keyed('spot-search'), 'Lions');
          await tester.pumpAndSettle();
          await tester.tap(keyed('spot-ranking-$rankingKey'));
          for (var attempt = 0; attempt < 500; attempt++) {
            await tester.pump(const Duration(milliseconds: 200));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
              break;
            }
          }
          expect(
            find.byType(CircularProgressIndicator),
            findsNothing,
            reason:
                'Fixture prices=${fixture.prices.length}, '
                'preorders=${fixture.preorderRequests}',
          );
          await tap(tester, 'spot-method-filter');
          final toolMenu = find.widgetWithText(MenuItemButton, 'Butchering');
          expect(toolMenu, findsOneWidget);
          await tester.tap(toolMenu);
          await tester.pumpAndSettle();
          if (ranking == 'demand') {
            await tap(tester, 'spot-demand-sort-value');
          }
          expect(fixture.prices, isNotEmpty);
          expect(fixture.preorderRequests, greaterThan(0));

          void expectFilterPreserved() {
            expect(tester.state(find.byType(FieldGuide)), same(guideState));
            expect(
              tester.widget<TextField>(keyed('spot-search')).controller!.text,
              'Lions',
            );
            expect(
              tester
                  .widget<GlassControl>(keyed('spot-ranking-$rankingKey'))
                  .selected,
              isTrue,
            );
            if (ranking == 'demand') {
              expect(
                tester
                    .widget<GlassControl>(keyed('spot-demand-sort-value'))
                    .selected,
                isTrue,
              );
            }
            final methodSemantics = find.ancestor(
              of: keyed('spot-method-filter'),
              matching: find.byType(Semantics),
            );
            expect(
              tester
                  .widgetList<Semantics>(methodSemantics)
                  .any((widget) => widget.properties.label == 'Butchering'),
              isTrue,
            );
          }

          String expectProjection(BairogCalculatorSettings settings) {
            expect(
              guide(tester).bairogSettings.hasSameValuesAs(settings),
              isTrue,
            );
            final expected = BairogCalculator(catalog.bairogCalculatorData!)
                .projectRoute(
                  routeId: 51,
                  settings: settings,
                  marketPricesByBdoItemId: fixture.prices,
                );
            final total = find.descendant(
              of: keyed('spot-route-51', skipOffstage: false),
              matching: keyed('$ranking-card-total', skipOffstage: false),
              skipOffstage: false,
            );
            final expectedText = '${_silver(expected.netSilverPerHour)}/h';
            final texts = tester.widgetList<Text>(
              find.descendant(
                of: total,
                matching: find.byType(Text, skipOffstage: false),
                skipOffstage: false,
              ),
            );
            expect(
              texts.any((text) => text.data?.endsWith(expectedText) ?? false),
              isTrue,
              reason: 'The host must render its current projection.',
            );
            return expectedText;
          }

          expectFilterPreserved();
          final initialValue = expectProjection(
            profile.effectiveSettings(catalog),
          );
          final originalPreferences = jsonEncode(store.preferences);
          await tap(tester, 'open-gathering-setup');
          await tester.enterText(keyed('gathering-setup-mastery'), '1800');
          await tester.enterText(keyed('gathering-setup-gdr'), '40');
          await tester.pumpAndSettle();
          final editedBase = profile.baseSettings.copyWith(
            mastery: 1800,
            gatheringDropRatePercent: 40,
          );
          expect(expectProjection(editedBase), isNot(initialValue));
          expect(
            jsonEncode(store.preferences),
            originalPreferences,
            reason: 'Draft previews must not persist.',
          );
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expectProjection(profile.effectiveSettings(catalog));
          expectFilterPreserved();
          expect(jsonEncode(store.preferences), originalPreferences);
          expect(store.saves, 0);

          await tap(tester, 'open-gathering-setup');
          await tester.enterText(keyed('gathering-setup-mastery'), '1800');
          await tester.enterText(keyed('gathering-setup-gdr'), '40');
          await tap(tester, 'apply-gathering-setup');
          final saved = GatheringPreparation.fromPreferences(
            store.preferences,
            catalog: catalog,
          );
          expect(saved.baseSettings.hasSameValuesAs(editedBase), isTrue);
          expect(saved.statsConfirmed, isTrue);
          final savedValue = expectProjection(saved.effectiveSettings(catalog));
          expectFilterPreserved();

          await tap(tester, 'workflow-prepare');
          await tap(tester, 'preparation-lightstones-buff-yawning-hedgehog');
          final buffed = GatheringPreparation.fromPreferences(
            store.preferences,
            catalog: catalog,
          );
          expect(buffed.buffIds, contains('buff-yawning-hedgehog'));
          expect(buffed.baseSettings.hasSameValuesAs(editedBase), isTrue);
          expect(
            guide(
              tester,
            ).bairogSettings.hasSameValuesAs(buffed.effectiveSettings(catalog)),
            isTrue,
            reason: 'Offstage spot estimates update immediately too.',
          );
          await tap(tester, 'workflow-spots');
          expectFilterPreserved();
          expect(
            expectProjection(buffed.effectiveSettings(catalog)),
            isNot(savedValue),
          );

          final beforeCancel = jsonEncode(store.preferences);
          final savesBeforeCancel = store.saves;
          await tap(tester, 'open-gathering-setup');
          await tester.enterText(keyed('gathering-setup-mastery'), '1000');
          await tester.pumpAndSettle();
          expect(
            guide(tester).bairogSettings.mastery,
            lessThan(buffed.effectiveSettings(catalog).mastery),
          );
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expectProjection(buffed.effectiveSettings(catalog));
          expectFilterPreserved();
          expect(jsonEncode(store.preferences), beforeCancel);
          expect(store.saves, savesBeforeCancel);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }, createHttpClient: (_) => fixture);
      },
    );
  }
}
