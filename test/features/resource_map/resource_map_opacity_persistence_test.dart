import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('failed durable replacement restores the opacity notifier', () async {
    final controller = _controller(
      _document({
        'resourceMap': {'uiOpacity': .75},
      }),
      (_) async => throw StateError('offline test save failure'),
    );
    await expectLater(
      controller.updateDocumentDurably(
        (state) => state.copyWith(
          extensions: {
            'resourceMap': {'uiOpacity': .9},
          },
        ),
      ),
      throwsStateError,
    );
    expect(controller.resourceMapUiOpacity.value, .75);
    expect(
      (controller.documentSnapshot.extensions['resourceMap']
          as Map)['uiOpacity'],
      .75,
    );
    await controller.dispose();
  });

  test(
    'map opacity persists independently and preserves every sibling setting',
    () async {
      final saves = <PlannerState>[];
      final initial = _document({
        'resourceMap': {
          'favoriteResourceIds': ['ash'],
          'interfaceStyle': 'ghostLedger',
          'nodeNetwork': {'contributionPointBudget': 325},
          'futureSetting': {'keep': true},
        },
        'gathering': {'uiOpacity': .8},
      });
      final controller = _controller(initial, (state) async {
        saves.add(state);
        return state;
      });
      expect(controller.resourceMapUiOpacity.value, 1);
      controller.setResourceMapUiOpacity(.7);
      expect(controller.resourceMapUiOpacity.value, .7);
      await controller.flush();
      final reloaded = _controller(saves.last, (state) async => state);
      expect(reloaded.resourceMapUiOpacity.value, .7);
      expect(reloaded.resourceMapFavoriteIds.value, {'ash'});
      expect(
        reloaded
            .resourceMapNodeNetworkPreferences
            .value
            .contributionPointBudget,
        325,
      );
      expect(reloaded.documentSnapshot.extensions['gathering'], {
        'uiOpacity': .8,
      });
      final map = reloaded.documentSnapshot.extensions['resourceMap'] as Map;
      expect(map['futureSetting'], {'keep': true});
      expect(map['interfaceStyle'], 'ghostLedger');
      reloaded.setResourceMapUiOpacity(1);
      expect(
        (reloaded.documentSnapshot.extensions['resourceMap'] as Map)
            .containsKey('uiOpacity'),
        false,
      );
      expect(
        reloaded.documentSnapshot.alchemy.inventory,
        initial.alchemy.inventory,
      );
      await controller.dispose();
      await reloaded.dispose();
    },
  );

  test(
    'zero and low map opacity round-trip without changing Gathering',
    () async {
      final saves = <PlannerState>[];
      final initial = _document({
        'resourceMap': {
          'favoriteResourceIds': ['ash'],
        },
        'gathering': {'uiOpacity': .8, 'glassOpacityPercent': 60},
        'future': {'keep': true},
      });
      final controller = _controller(initial, (state) async {
        saves.add(state);
        return state;
      });
      for (final value in [0.0, .01, .25, .6, 1.0]) {
        controller.setResourceMapUiOpacity(value);
        await controller.flush();
        final document = saves.last;
        final stored = document.extensions['resourceMap'] as Map;
        if (value == 1) {
          expect(stored.containsKey('uiOpacity'), isFalse);
        } else {
          expect(stored['uiOpacity'], value);
        }
        final reloaded = _controller(document, (state) async => state);
        expect(reloaded.resourceMapUiOpacity.value, value);
        expect(reloaded.resourceMapFavoriteIds.value, {'ash'});
        expect(
          document.extensions['gathering'],
          initial.extensions['gathering'],
        );
        expect(document.extensions['future'], initial.extensions['future']);
        await reloaded.dispose();
      }
      await controller.dispose();
    },
  );

  test('failed durable replacement can restore exactly zero opacity', () async {
    final controller = _controller(
      _document({
        'resourceMap': {'uiOpacity': 0.0},
      }),
      (_) async => throw StateError('offline test save failure'),
    );
    await expectLater(
      controller.updateDocumentDurably(
        (state) => state.copyWith(
          extensions: {
            'resourceMap': {'uiOpacity': .8},
          },
        ),
      ),
      throwsStateError,
    );
    expect(controller.resourceMapUiOpacity.value, 0);
    expect(
      (controller.documentSnapshot.extensions['resourceMap']
          as Map)['uiOpacity'],
      0,
    );
    await controller.dispose();
  });

  test('imports and edits clamp safely and respect restart freeze', () async {
    final controller = _controller(_document({}), (state) async => state);
    for (final input in [null, 'bad', double.nan, double.infinity, -4, 2, .8]) {
      controller.updateDocument(
        (state) => state.copyWith(
          extensions: {
            'resourceMap': {'uiOpacity': input},
          },
        ),
      );
      expect(
        controller.resourceMapUiOpacity.value,
        input == -4
            ? 0
            : input == .8
            ? .8
            : 1,
      );
    }
    controller.setResourceMapUiOpacity(-2);
    expect(controller.resourceMapUiOpacity.value, 0);
    controller.freezeMutationsForRestart();
    controller.setResourceMapUiOpacity(.9);
    expect(controller.resourceMapUiOpacity.value, 0);
    controller.resumeMutationsAfterRestartFailure();
    controller.setResourceMapUiOpacity(double.nan);
    expect(controller.resourceMapUiOpacity.value, 1);
    await controller.dispose();
  });
}

PlannerApplicationController _controller(
  PlannerState state,
  SavePlannerState save,
) => PlannerApplicationController(
  catalog: CatalogSnapshot(
    sourceSha256: 'test',
    sourceByteCount: 1,
    alchemy: _catalog(CraftMode.alchemy),
    cooking: _catalog(CraftMode.cooking),
    processing: _catalog(CraftMode.processing),
    supportingData: const {},
    collisions: const [],
  ),
  initialState: state,
  saveState: save,
  saveDebounce: const Duration(days: 1),
);
ModeCatalog _catalog(CraftMode mode) => ModeCatalog(
  mode: mode,
  items: const {},
  iconDataUris: const {},
  defaults: const {},
  metadata: const {},
  searchAliases: const {},
);
PlannerState _document(Map<String, Object?> extensions) => PlannerState(
  applicationVersion: 'test',
  lastSuccessfulWriteUtc: DateTime.utc(2026),
  activeMode: CraftMode.alchemy,
  alchemy: _mode(CraftMode.alchemy),
  cooking: _mode(CraftMode.cooking),
  processing: _mode(CraftMode.processing),
  processingYields: const {},
  marketTax: MarketTax(),
  extensions: extensions,
);
ModeState _mode(CraftMode mode) => ModeState(
  target: '',
  bonusTarget: '',
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);
