import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    '100 previews repaint only; one commit saves without rebuilding plans',
    () async {
      final saves = <PlannerState>[];
      final controller = _controller(_document({}), (state) async {
        saves.add(state);
        return state;
      }, saveDebounce: Duration.zero);
      addTearDown(controller.dispose);
      final initial = controller.documentSnapshot;
      final plans = {
        for (final entry in controller.modes.entries)
          entry.key: entry.value.plan.value,
      };
      var modeNotifications = 0;
      var planNotifications = 0;
      var activeModeNotifications = 0;
      var opacityNotifications = 0;
      for (final mode in controller.modes.values) {
        mode.state.addListener(() => modeNotifications++);
        mode.plan.addListener(() => planNotifications++);
      }
      controller.activeMode.addListener(() => activeModeNotifications++);
      controller.resourceMapUiOpacity.addListener(() => opacityNotifications++);

      for (var i = 1; i <= 100; i++) {
        controller.previewResourceMapUiOpacity(i / 100);
      }
      // Let an accidentally scheduled immediate save run. flush() intentionally
      // commits previews and therefore must not be used to inspect drag state.
      await Future<void>.delayed(Duration.zero);
      expect(controller.resourceMapUiOpacity.value, 1);
      expect(opacityNotifications, 100);
      expect(controller.documentSnapshot, same(initial));
      expect(saves, isEmpty);
      expect(modeNotifications, 0);
      expect(planNotifications, 0);
      expect(activeModeNotifications, 0);

      controller.commitResourceMapUiOpacity();
      await controller.flush();
      expect(saves, hasLength(1));
      expect(_storedOpacity(saves.single), 1);
      expect(controller.activeMode.value, initial.activeMode);
      expect(modeNotifications, 0);
      expect(planNotifications, 0);
      expect(activeModeNotifications, 0);
      for (final entry in controller.modes.entries) {
        expect(entry.value.state.value, same(initial.forMode(entry.key)));
        expect(entry.value.plan.value, same(plans[entry.key]));
      }

      final committed = controller.documentSnapshot;
      controller.commitResourceMapUiOpacity();
      controller.commitResourceMapUiOpacity(1);
      await controller.flush();
      expect(controller.documentSnapshot, same(committed));
      expect(opacityNotifications, 100);
      expect(saves, hasLength(1));
    },
  );

  test(
    'unrelated document and map saves retain an active opacity preview',
    () async {
      final saves = <PlannerState>[];
      final controller = _controller(
        _document({
          'resourceMap': {'uiOpacity': .75},
        }),
        (state) async {
          saves.add(state);
          return state;
        },
        saveDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.previewResourceMapUiOpacity(.31);
      controller.updateDocument(
        (state) => state.copyWith(showDeleteTools: true),
      );
      controller.setResourceMapFavoriteIds({'ash'});
      await Future<void>.delayed(Duration.zero);
      expect(controller.resourceMapUiOpacity.value, .31);
      expect(controller.deleteToolsEnabled.value, isTrue);
      expect(controller.resourceMapFavoriteIds.value, {'ash'});
      expect(_storedOpacity(controller.documentSnapshot), .75);
      expect(saves, hasLength(2));
      expect(saves.map(_storedOpacity), everyElement(.75));

      controller.commitResourceMapUiOpacity();
      await controller.flush();
      expect(saves, hasLength(3));
      expect(_storedOpacity(saves.last), .31);
      expect(saves.last.showDeleteTools, isTrue);
      expect(
        (saves.last.extensions['resourceMap'] as Map)['favoriteResourceIds'],
        ['ash'],
      );
    },
  );

  for (final withSibling in [false, true]) {
    test(
      'preview zero and reset preserve extension ownership ($withSibling)',
      () async {
        final saves = <PlannerState>[];
        final controller = _controller(
          _document({
            if (withSibling)
              'resourceMap': {
                'favoriteResourceIds': ['ash'],
              },
            'gathering': {'uiOpacity': .8},
            'future': {'keep': true},
          }),
          (state) async {
            saves.add(state);
            return state;
          },
        );
        addTearDown(controller.dispose);
        final initial = controller.documentSnapshot;
        controller.previewResourceMapUiOpacity(0);
        expect(controller.documentSnapshot, same(initial));
        controller.commitResourceMapUiOpacity();
        await controller.flush();
        expect(_storedOpacity(saves.single), 0);

        controller.previewResourceMapUiOpacity(.6);
        expect(_storedOpacity(controller.documentSnapshot), 0);
        controller.commitResourceMapUiOpacity();
        await controller.flush();
        expect(saves, hasLength(2));
        expect(controller.resourceMapUiOpacity.value, .6);
        final extensions = saves.last.extensions;
        if (withSibling) {
          expect(extensions['resourceMap'], {
            'favoriteResourceIds': ['ash'],
          });
        } else {
          expect(extensions.containsKey('resourceMap'), isFalse);
        }
        expect(extensions['gathering'], initial.extensions['gathering']);
        expect(extensions['future'], initial.extensions['future']);
        controller.commitResourceMapUiOpacity(.6);
        await controller.flush();
        expect(saves, hasLength(2));
        final reloaded = _controller(saves.last, (state) async => state);
        expect(reloaded.resourceMapUiOpacity.value, .6);
        await reloaded.dispose();
      },
    );
  }

  for (final lifecycle in ['flush', 'dispose']) {
    for (final opacity in [0.0, .83]) {
      test(
        '$lifecycle commits the active preview exactly once ($opacity)',
        () async {
          final saves = <PlannerState>[];
          final controller = _controller(
            _document({
              'resourceMap': {'uiOpacity': .75},
            }),
            (state) async {
              saves.add(state);
              return state;
            },
          );
          addTearDown(controller.dispose);
          controller.previewResourceMapUiOpacity(opacity);
          expect(_storedOpacity(controller.documentSnapshot), .75);
          expect(saves, isEmpty);
          if (lifecycle == 'flush') {
            await controller.flush();
          } else {
            await controller.dispose();
          }
          expect(saves, hasLength(1));
          expect(_storedOpacity(saves.single), opacity);
          expect(_storedOpacity(controller.documentSnapshot), opacity);
          await controller.dispose();
          final disposed = controller.documentSnapshot;
          controller.previewResourceMapUiOpacity(.2);
          controller.commitResourceMapUiOpacity(.2);
          controller.commitResourceMapUiOpacity();
          expect(controller.documentSnapshot, same(disposed));
          expect(saves, hasLength(1));
        },
      );
    }
  }

  test(
    'restart freeze commits preview before rejecting all later edits',
    () async {
      final saves = <PlannerState>[];
      final controller = _controller(_document({}), (state) async {
        saves.add(state);
        return state;
      });
      addTearDown(controller.dispose);
      controller.previewResourceMapUiOpacity(0);
      controller.freezeMutationsForRestart();
      expect(controller.mutationsFrozen, isTrue);
      expect(_storedOpacity(controller.documentSnapshot), 0);
      final frozen = controller.documentSnapshot;
      controller.previewResourceMapUiOpacity(.9);
      controller.commitResourceMapUiOpacity(.9);
      controller.setResourceMapUiOpacity(.9);
      controller.updateDocument(
        (state) => state.copyWith(showDeleteTools: true),
      );
      expect(controller.resourceMapUiOpacity.value, 0);
      expect(controller.documentSnapshot, same(frozen));
      await controller.flush();
      expect(saves, hasLength(1));
      expect(_storedOpacity(saves.single), 0);

      controller.resumeMutationsAfterRestartFailure();
      controller.previewResourceMapUiOpacity(.42);
      controller.commitResourceMapUiOpacity();
      await controller.flush();
      expect(controller.mutationsFrozen, isFalse);
      expect(saves, hasLength(2));
      expect(_storedOpacity(saves.last), .42);
    },
  );

  for (final storedOpacity in <double?>[null, 0, .6, .75]) {
    test(
      'durable replacement owns equal stored opacity during preview ($storedOpacity)',
      () async {
        final saves = <PlannerState>[];
        final controller = _controller(
          _document({
            'resourceMap': {
              'uiOpacity': ?storedOpacity,
              'favoriteResourceIds': ['ash'],
            },
          }),
          (state) async {
            saves.add(state);
            return state;
          },
        );
        addTearDown(controller.dispose);
        controller.previewResourceMapUiOpacity(.8);
        await controller.updateDocumentDurably(
          (state) => state.copyWith(
            showDeleteTools: true,
            extensions: {
              'resourceMap': {
                'uiOpacity': ?storedOpacity,
                'favoriteResourceIds': ['birch'],
              },
            },
          ),
        );
        expect(controller.resourceMapUiOpacity.value, storedOpacity ?? .6);
        expect(_storedOpacity(controller.documentSnapshot), storedOpacity);
        expect(controller.resourceMapFavoriteIds.value, {'birch'});
        expect(controller.deleteToolsEnabled.value, isTrue);
        expect(saves, hasLength(1));
        expect(_storedOpacity(saves.single), storedOpacity);
        expect(saves.single, same(controller.documentSnapshot));
        await controller.flush();
        expect(saves, hasLength(1));
      },
    );
  }

  for (final originalOpacity in [0.0, .75]) {
    test(
      'failed replacement restores durable opacity after a preview ($originalOpacity)',
      () async {
        final saves = <PlannerState>[];
        var rejectNextSave = true;
        final controller = _controller(
          _document({
            'resourceMap': {
              'uiOpacity': originalOpacity,
              'favoriteResourceIds': ['ash'],
            },
          }),
          (state) async {
            saves.add(state);
            if (rejectNextSave) {
              rejectNextSave = false;
              throw StateError('offline test save failure');
            }
            return state;
          },
        );
        addTearDown(controller.dispose);
        final original = controller.documentSnapshot;
        controller.previewResourceMapUiOpacity(.31);
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
        expect(controller.documentSnapshot, same(original));
        expect(controller.resourceMapUiOpacity.value, originalOpacity);
        expect(controller.resourceMapFavoriteIds.value, {'ash'});
        expect(saves, hasLength(1));
        expect(_storedOpacity(saves.single), .9);
        await controller.flush();
        expect(saves, hasLength(2));
        expect(saves.last, same(original));
        expect(controller.saveError.value, isNull);
      },
    );
  }

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
      expect(controller.resourceMapUiOpacity.value, .6);
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
      reloaded.setResourceMapUiOpacity(.6);
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
        if (value == .6) {
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
            : input == 2
            ? 1
            : input == .8
            ? .8
            : .6,
      );
    }
    controller.setResourceMapUiOpacity(-2);
    expect(controller.resourceMapUiOpacity.value, 0);
    controller.freezeMutationsForRestart();
    controller.setResourceMapUiOpacity(.9);
    expect(controller.resourceMapUiOpacity.value, 0);
    controller.resumeMutationsAfterRestartFailure();
    controller.setResourceMapUiOpacity(double.nan);
    expect(controller.resourceMapUiOpacity.value, .6);
    await controller.dispose();
  });
}

PlannerApplicationController _controller(
  PlannerState state,
  SavePlannerState save, {
  Duration saveDebounce = const Duration(days: 1),
}) => PlannerApplicationController(
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
  saveDebounce: saveDebounce,
);

Object? _storedOpacity(PlannerState state) {
  final resourceMap = state.extensions['resourceMap'];
  return resourceMap is Map ? resourceMap['uiOpacity'] : null;
}

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
