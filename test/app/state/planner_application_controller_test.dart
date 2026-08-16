import 'dart:async';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/first_run_setup.dart';
import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state_json_codec.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_map_core/bdo_map_core.dart'
    show
        BdoGatherChecklist,
        BdoGatherChecklistEntry,
        BdoGatherChecklistSourceKind,
        BdoMapVisualStyle,
        BdoNodeNetworkPreferences,
        BdoTownWorkerCapacity;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'planner actions update only the selected mode and flush once',
    () async {
      final saves = <PlannerState>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async {
          saves.add(state);
          return state;
        },
        saveDebounce: const Duration(days: 1),
      );
      final alchemy = controller.modes[CraftMode.alchemy]!;

      expect(alchemy.selectTarget('Potion'), isTrue);
      expect(alchemy.commitAmount('-3.8'), isTrue);
      expect(alchemy.state.value.want, 1);
      alchemy.setFullTargetAmount(false);
      alchemy.setIgnoreOwnedIngredients(false);
      alchemy.toggleCompleted('Potion');
      alchemy.toggleIngredients('Potion');
      alchemy.addMissingAmount('Base', 4);

      expect(alchemy.state.value.ignoreTargetInventory, isFalse);
      expect(alchemy.state.value.ignoreIngredientInventory, isFalse);
      expect(alchemy.state.value.completedSteps, contains('Potion'));
      expect(alchemy.expandedSteps.value, contains('Potion'));
      expect(alchemy.state.value.inventory['Base'], 4);
      expect(
        controller.modes[CraftMode.cooking]!.state.value.inventory,
        isEmpty,
      );

      await controller.flush();
      expect(saves, isNotEmpty);
      expect(saves.last.alchemy.inventory['Base'], 4);
      await controller.dispose();
    },
  );

  test('invalid amount and inventory input leave state unchanged', () async {
    final controller = _controller();
    final mode = controller.active;

    expect(mode.commitAmount(''), isFalse);
    expect(mode.commitInventory('Base', '-1'), isFalse);
    expect(mode.state.value.want, 100);
    expect(mode.state.value.inventory, isEmpty);

    await controller.dispose();
  });

  test(
    'advanced navigation stays hidden until Editor Settings enables it',
    () async {
      final controller = _controller();
      final mode = controller.active;

      mode.navigate('inventory');
      expect(mode.state.value.view, 'plan');
      mode.navigate('editor');
      expect(mode.state.value.view, 'plan');

      controller.updateDocument(
        (document) => document.copyWith(showDeleteTools: true),
        immediate: true,
      );
      mode.navigate('inventory');
      expect(mode.state.value.view, 'inventory');
      mode.navigate('editor');
      expect(mode.state.value.view, 'editor');

      controller.updateDocument(
        (document) => document.copyWith(showDeleteTools: false),
        immediate: true,
      );
      mode.navigate('inventory');
      expect(mode.state.value.view, 'plan');
      await controller.dispose();
    },
  );

  test(
    'owned amounts and completed steps survive save and Restart queue',
    () async {
      PlannerState? saved;
      final first = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async {
          saved = state;
          return state;
        },
        saveDebounce: Duration.zero,
      );
      final firstMode = first.active;
      firstMode.commitInventory('Base', '12.500');
      firstMode.toggleCompleted('Potion');
      await first.flush();
      expect(saved!.alchemy.inventory['Base'], 12500);
      expect(saved!.alchemy.completedSteps, contains('Potion'));
      await first.dispose();

      final restored = PlannerApplicationController(
        catalog: _catalog(),
        initialState: saved!,
        saveState: (state) async => state,
        saveDebounce: Duration.zero,
      );
      expect(restored.active.state.value.inventory['Base'], 12500);
      expect(restored.active.state.value.completedSteps, contains('Potion'));

      restored.active.resetCompleted();
      expect(restored.active.state.value.completedSteps, isEmpty);
      expect(restored.active.state.value.inventory['Base'], 12500);
      expect(restored.active.state.value.target, 'Potion');
      expect(restored.active.state.value.want, 100);
      await restored.dispose();
    },
  );

  test(
    'document market tax notifier tracks edits without replacing mode state',
    () async {
      final saves = <PlannerState>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async {
          saves.add(state);
          return state;
        },
        saveDebounce: const Duration(days: 1),
      );
      final initialModeState = controller.active.state.value;
      final notifications = <MarketTax>[];
      controller.marketTax.addListener(
        () => notifications.add(controller.marketTax.value),
      );

      controller.updateDocument(
        (document) => document.copyWith(
          marketTax: document.marketTax.copyWith(
            valuePack: true,
            merchantRing: true,
            familyFameBonus: .015,
          ),
        ),
      );
      controller.updateDocument(
        (document) => document.copyWith(
          marketTax: document.marketTax.copyWith(enabled: false),
        ),
      );
      controller.updateDocument(
        (document) => document.copyWith(showDeleteTools: true),
      );

      expect(
        identical(controller.active.state.value, initialModeState),
        isTrue,
      );
      expect(notifications, hasLength(2));
      expect(controller.marketTax.value.enabled, isFalse);
      expect(controller.marketTax.value.valuePack, isTrue);
      expect(controller.marketTax.value.merchantRing, isTrue);
      expect(controller.marketTax.value.familyFameBonus, .015);
      expect(
        identical(
          controller.marketTax.value,
          controller.documentSnapshot.marketTax,
        ),
        isTrue,
      );

      await controller.flush();
      expect(saves.last.marketTax.enabled, isFalse);
      expect(saves.last.marketTax.valuePack, isTrue);
      expect(saves.last.marketTax.merchantRing, isTrue);
      expect(saves.last.marketTax.familyFameBonus, .015);
      await controller.dispose();
    },
  );

  test(
    'AFK weight profile notifier tracks global settings and persisted state',
    () async {
      final saves = <PlannerState>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async {
          saves.add(state);
          return state;
        },
        saveDebounce: const Duration(days: 1),
      );
      final initialModeState = controller.active.state.value;
      final notifications = <AfkWeightProfile>[];
      controller.afkWeightProfile.addListener(
        () => notifications.add(controller.afkWeightProfile.value),
      );

      controller.updateDocument(
        (document) => document.copyWith(
          afkWeightProfile: document.afkWeightProfile.copyWith(
            maximumWeightLt: 1750,
            currentCarriedWeightLt: 120,
            safetyBufferLt: 25,
            featheryStepsLevel: 4,
          ),
        ),
      );

      expect(
        identical(controller.active.state.value, initialModeState),
        isTrue,
      );
      expect(notifications, hasLength(1));
      expect(controller.afkWeightProfile.value.maximumWeightLt, 1750);
      expect(controller.afkWeightProfile.value.safeLimitLt, 1955);
      expect(
        identical(
          controller.afkWeightProfile.value,
          controller.documentSnapshot.afkWeightProfile,
        ),
        isTrue,
      );

      await controller.flush();
      expect(saves.last.afkWeightProfile.maximumWeightLt, 1750);
      expect(saves.last.afkWeightProfile.featheryStepsLevel, 4);
      await controller.dispose();
    },
  );

  test(
    'resource map favorites load, persist deterministically, and preserve extensions',
    () async {
      final saves = <PlannerState>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document().copyWith(
          extensions: const <String, Object?>{
            'futureRoot': <String, Object?>{'revision': 7},
            'resourceMap': <String, Object?>{
              'futureMapPreference': 'compact',
              'favoriteResourceIds': <Object?>[
                ' snake-meat ',
                '',
                'worker-node:12',
                42,
                'snake-meat',
              ],
            },
          },
        ),
        saveState: (state) async {
          saves.add(state);
          return state;
        },
        saveDebounce: const Duration(days: 1),
      );

      expect(controller.resourceMapFavoriteIds.value, const <String>{
        'snake-meat',
        'worker-node:12',
      });

      controller.setResourceMapFavoriteIds(const <String>{
        'worker:lead',
        ' gathering:coral ',
        '',
      });

      expect(controller.resourceMapFavoriteIds.value, const <String>{
        'gathering:coral',
        'worker:lead',
      });
      expect(
        controller.documentSnapshot.extensions['futureRoot'],
        const <String, Object?>{'revision': 7},
      );
      final resourceMap =
          controller.documentSnapshot.extensions['resourceMap'] as Map;
      expect(resourceMap['futureMapPreference'], 'compact');
      expect(resourceMap['favoriteResourceIds'], const <String>[
        'gathering:coral',
        'worker:lead',
      ]);

      await controller.flush();
      expect(saves, hasLength(1));
      expect(
        (saves.single.extensions['resourceMap'] as Map)['favoriteResourceIds'],
        const <String>['gathering:coral', 'worker:lead'],
      );
      await controller.dispose();
    },
  );

  test(
    'resource map favorites notifier follows external document replacements',
    () async {
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async => state,
        saveDebounce: const Duration(days: 1),
      );
      final notifications = <Set<String>>[];
      controller.resourceMapFavoriteIds.addListener(
        () => notifications.add(controller.resourceMapFavoriteIds.value),
      );

      controller.updateDocument(
        (document) => document.copyWith(
          extensions: const <String, Object?>{
            'resourceMap': <String, Object?>{
              'favoriteResourceIds': <String>['second', 'first'],
            },
          },
        ),
      );
      controller.updateDocument(
        (document) => document.copyWith(showDeleteTools: true),
      );
      controller.updateDocument(
        (document) => document.copyWith(
          extensions: const <String, Object?>{'futureRoot': true},
        ),
      );

      expect(notifications, const <Set<String>>[
        <String>{'first', 'second'},
        <String>{},
      ]);
      await controller.dispose();
    },
  );

  test(
    'resource map node network loads, persists, and preserves sibling settings',
    () async {
      final saves = <PlannerState>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document().copyWith(
          extensions: const <String, Object?>{
            'resourceMap': <String, Object?>{
              'favoriteResourceIds': <String>['ash'],
              'nodeNetwork': <String, Object?>{
                'contributionPointBudget': 325,
                'desiredResourceNodeCounts': <String, int>{'ash': 2},
                'currentNodeIds': <String>['12', '8'],
                'currentOwnedHouseIds': <String>['2202', '2201'],
                'currentHouseUsageTypeIds': <String, int>{'2201': 2},
              },
            },
          },
        ),
        saveState: (state) async {
          saves.add(state);
          return state;
        },
        saveDebounce: const Duration(days: 1),
      );

      expect(
        controller
            .resourceMapNodeNetworkPreferences
            .value
            .contributionPointBudget,
        325,
      );
      expect(
        controller
            .resourceMapNodeNetworkPreferences
            .value
            .desiredResourceNodeCounts,
        const <String, int>{'ash': 2},
      );
      expect(
        controller.resourceMapNodeNetworkPreferences.value.onlineHoursPerDay,
        BdoNodeNetworkPreferences.defaultOnlineHoursPerDay,
      );
      expect(
        controller
            .resourceMapNodeNetworkPreferences
            .value
            .resourceAvailabilityPercent,
        BdoNodeNetworkPreferences.defaultResourceAvailabilityPercent,
      );
      expect(
        controller
            .resourceMapNodeNetworkPreferences
            .value
            .townWorkerCapacitiesByNodeId,
        isEmpty,
      );
      expect(
        controller.resourceMapNodeNetworkPreferences.value.mapVisualStyle,
        BdoMapVisualStyle.vivid,
      );
      expect(
        controller.resourceMapNodeNetworkPreferences.value.showCitiesAndTowns,
        isTrue,
      );
      expect(
        controller.resourceMapNodeNetworkPreferences.value.showGatewayHubs,
        isTrue,
      );
      expect(
        controller.resourceMapNodeNetworkPreferences.value.showAllMapNodes,
        isTrue,
      );
      expect(
        controller
            .resourceMapNodeNetworkPreferences
            .value
            .showAllNodeConnections,
        isTrue,
      );
      expect(
        controller
            .resourceMapNodeNetworkPreferences
            .value
            .showWorkerOutputIcons,
        isTrue,
      );
      expect(
        controller.resourceMapNodeNetworkPreferences.value.currentOwnedHouseIds,
        const <String>{'2201', '2202'},
      );
      expect(
        controller
            .resourceMapNodeNetworkPreferences
            .value
            .currentHouseUsageTypeIds,
        const <String, int>{'2201': 2},
      );

      controller.setResourceMapNodeNetworkPreferences(
        BdoNodeNetworkPreferences(
          contributionPointBudget: 280,
          desiredResourceNodeCounts: const <String, int>{'fish': 3},
          currentNodeIds: const <String>{'24', '5'},
          currentOwnedHouseIds: const <String>{'2202', '2156'},
          currentHouseUsageTypeIds: const <String, int>{'2156': 1, '2202': 3},
          rootNodeIds: const <String>{'1'},
          onlineHoursPerDay: 10,
          resourceAvailabilityPercent: 65,
          useObservedTradeVolume: true,
          mapVisualStyle: BdoMapVisualStyle.vivid,
          showCitiesAndTowns: false,
          showGatewayHubs: false,
          showAllMapNodes: false,
          showAllNodeConnections: false,
          showWorkerOutputIcons: false,
          townWorkerCapacitiesByNodeId: const <String, BdoTownWorkerCapacity>{
            '100': BdoTownWorkerCapacity(
              availableWorkerCount: 4,
              freeLodgingSlotCount: 2,
              hiredWorkerCount: 4,
              bonusLodgingSlotCount: 8,
            ),
            '2': BdoTownWorkerCapacity(
              availableWorkerCount: 1,
              freeLodgingSlotCount: 0,
            ),
          },
        ),
      );

      expect(controller.resourceMapFavoriteIds.value, const <String>{'ash'});
      final resourceMap =
          controller.documentSnapshot.extensions['resourceMap'] as Map;
      final nodeNetwork = resourceMap['nodeNetwork'] as Map;
      expect(nodeNetwork['contributionPointBudget'], 280);
      expect(nodeNetwork['desiredResourceNodeCounts'], const <String, int>{
        'fish': 3,
      });
      expect(nodeNetwork['currentNodeIds'], const <String>['5', '24']);
      expect(nodeNetwork['currentOwnedHouseIds'], const <String>[
        '2156',
        '2202',
      ]);
      expect(nodeNetwork['currentHouseUsageTypeIds'], const <String, int>{
        '2156': 1,
        '2202': 3,
      });
      expect(nodeNetwork['rootNodeIds'], const <String>['1']);
      expect(
        nodeNetwork['schemaVersion'],
        BdoNodeNetworkPreferences.schemaVersion,
      );
      expect(nodeNetwork['onlineHoursPerDay'], 10);
      expect(nodeNetwork['resourceAvailabilityPercent'], 65);
      expect(nodeNetwork['useObservedTradeVolume'], isTrue);
      expect(nodeNetwork.containsKey('mapVisualStyle'), isFalse);
      expect(nodeNetwork['showCitiesAndTowns'], isFalse);
      expect(nodeNetwork['showGatewayHubs'], isFalse);
      expect(nodeNetwork['showAllMapNodes'], isFalse);
      expect(nodeNetwork['showAllNodeConnections'], isFalse);
      expect(nodeNetwork['showWorkerOutputIcons'], isFalse);
      expect(nodeNetwork['townWorkerCapacitiesByNodeId'], {
        '2': {'availableWorkerCount': 1, 'freeLodgingSlotCount': 0},
        '100': {
          'availableWorkerCount': 4,
          'freeLodgingSlotCount': 2,
          'hiredWorkerCount': 4,
          'bonusLodgingSlotCount': 8,
        },
      });

      await controller.flush();
      expect(saves, hasLength(1));
      const codec = PlannerStateJsonCodec();
      final restored = PlannerApplicationController(
        catalog: _catalog(),
        initialState: codec.decode(codec.encode(saves.single)),
        saveState: (state) async => state,
        saveDebounce: Duration.zero,
      );
      expect(
        restored.resourceMapNodeNetworkPreferences.value.sameValuesAs(
          controller.resourceMapNodeNetworkPreferences.value,
        ),
        isTrue,
      );
      expect(
        restored.resourceMapNodeNetworkPreferences.value.mapVisualStyle,
        BdoMapVisualStyle.vivid,
      );
      await restored.dispose();
      await controller.dispose();
    },
  );

  test(
    'gather checklist restores tolerant data, persists order, and preserves siblings',
    () async {
      final saves = <PlannerState>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document().copyWith(
          extensions: const <String, Object?>{
            'futureRoot': <String, Object?>{'revision': 9},
            'resourceMap': <String, Object?>{
              'favoriteResourceIds': <String>['ash'],
              'futureMapPreference': 'compact',
              'gatherChecklist': <String, Object?>{
                'schemaVersion': 99,
                'entries': <Object?>[
                  <String, Object?>{
                    'resourceId': ' thuja ',
                    'displayName': ' Thuja Tree ',
                    'sourceKind': 'worker',
                  },
                  null,
                  <String, Object?>{
                    'resourceId': 'snake',
                    'displayName': 'Snake',
                    'completed': 'yes',
                  },
                  <String, Object?>{'resourceId': 'thuja', 'completed': true},
                  <String, Object?>{'resourceId': ' '},
                ],
                'selectedResourceId': 'snake',
              },
            },
          },
        ),
        saveState: (state) async {
          saves.add(state);
          return state;
        },
        saveDebounce: const Duration(days: 1),
      );

      expect(
        controller.resourceMapGatherChecklist.value,
        BdoGatherChecklist(
          entries: <BdoGatherChecklistEntry>[
            BdoGatherChecklistEntry(
              resourceId: 'thuja',
              displayName: 'Thuja Tree',
              sourceKind: BdoGatherChecklistSourceKind.workerNode,
              isCompleted: true,
            ),
            BdoGatherChecklistEntry(
              resourceId: 'snake',
              displayName: 'Snake',
              isCompleted: true,
            ),
          ],
          selectedResourceId: 'snake',
        ),
      );

      final replacement = BdoGatherChecklist(
        entries: <BdoGatherChecklistEntry>[
          BdoGatherChecklistEntry(
            resourceId: 'rusalkas-coral',
            displayName: "Rusalka's Coral",
            sourceKind: BdoGatherChecklistSourceKind.manualGathering,
          ),
          BdoGatherChecklistEntry(
            resourceId: 'snake',
            displayName: 'Snake',
            sourceKind: BdoGatherChecklistSourceKind.manualGathering,
            isCompleted: true,
          ),
        ],
        selectedResourceId: 'rusalkas-coral',
      );
      controller.setResourceMapGatherChecklist(replacement);

      expect(controller.resourceMapGatherChecklist.value, replacement);
      expect(
        controller.documentSnapshot.extensions['futureRoot'],
        const <String, Object?>{'revision': 9},
      );
      final resourceMap =
          controller.documentSnapshot.extensions['resourceMap'] as Map;
      expect(resourceMap['favoriteResourceIds'], const <String>['ash']);
      expect(resourceMap['futureMapPreference'], 'compact');
      expect(resourceMap['gatherChecklist'], <String, Object?>{
        'schemaVersion': 1,
        'entries': <Object?>[
          <String, Object?>{
            'resourceId': 'rusalkas-coral',
            'displayName': "Rusalka's Coral",
            'sourceKind': 'manualGathering',
          },
          <String, Object?>{
            'resourceId': 'snake',
            'displayName': 'Snake',
            'sourceKind': 'manualGathering',
            'completed': true,
          },
        ],
        'selectedResourceId': 'rusalkas-coral',
      });

      await controller.flush();
      expect(saves, hasLength(1));
      expect(
        (saves.single.extensions['resourceMap'] as Map)['gatherChecklist'],
        replacement.toJson(),
      );
      await controller.dispose();
    },
  );

  test(
    'gather checklist follows document replacements and removes only its key when empty',
    () async {
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async => state,
        saveDebounce: const Duration(days: 1),
      );
      final notifications = <BdoGatherChecklist>[];
      controller.resourceMapGatherChecklist.addListener(
        () => notifications.add(controller.resourceMapGatherChecklist.value),
      );

      controller.updateDocument(
        (document) => document.copyWith(
          extensions: const <String, Object?>{
            'resourceMap': <String, Object?>{
              'favoriteResourceIds': <String>['ash'],
              'gatherChecklist': <String, Object?>{
                'items': <Object?>[
                  <String, Object?>{
                    'materialId': 'snake',
                    'name': 'Snake',
                    'route': 'gather',
                  },
                  17,
                  false,
                ],
                'currentItemId': 'snake',
              },
            },
          },
        ),
      );
      controller.updateDocument(
        (document) => document.copyWith(showDeleteTools: true),
      );
      controller.setResourceMapGatherChecklist(BdoGatherChecklist());

      expect(notifications, hasLength(2));
      expect(
        notifications.first.entries.map((entry) => entry.resourceId),
        const <String>['snake', '17'],
      );
      expect(notifications.first.selectedResourceId, 'snake');
      expect(notifications.last, BdoGatherChecklist());
      final resourceMap =
          controller.documentSnapshot.extensions['resourceMap'] as Map;
      expect(resourceMap.containsKey('gatherChecklist'), isFalse);
      expect(resourceMap['favoriteResourceIds'], const <String>['ash']);
      await controller.dispose();
    },
  );

  test(
    'failed durable replacement restores gather checklist notifier',
    () async {
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document().copyWith(
          extensions: const <String, Object?>{
            'resourceMap': <String, Object?>{
              'gatherChecklist': <String, Object?>{
                'entries': <Object?>[
                  <String, Object?>{'resourceId': 'original'},
                ],
              },
            },
          },
        ),
        saveState: (_) async {
          throw const FileSystemException('write failed');
        },
        saveDebounce: Duration.zero,
      );
      final notifications = <BdoGatherChecklist>[];
      controller.resourceMapGatherChecklist.addListener(
        () => notifications.add(controller.resourceMapGatherChecklist.value),
      );

      await expectLater(
        controller.updateDocumentDurably(
          (document) => document.copyWith(
            extensions: const <String, Object?>{
              'resourceMap': <String, Object?>{
                'gatherChecklist': <String, Object?>{
                  'entries': <Object?>[
                    <String, Object?>{'resourceId': 'replacement'},
                  ],
                },
              },
            },
          ),
        ),
        throwsStateError,
      );

      expect(
        notifications
            .map((checklist) => checklist.entries.single.resourceId)
            .toList(),
        const <String>['replacement', 'original'],
      );
      expect(
        controller.resourceMapGatherChecklist.value.entries.single.resourceId,
        'original',
      );
      await controller.dispose();
    },
  );

  test(
    'failed durable replacement restores resource map favorites notifier',
    () async {
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document().copyWith(
          extensions: const <String, Object?>{
            'resourceMap': <String, Object?>{
              'favoriteResourceIds': <String>['original'],
            },
          },
        ),
        saveState: (_) async {
          throw const FileSystemException('write failed');
        },
        saveDebounce: Duration.zero,
      );
      final notifications = <Set<String>>[];
      controller.resourceMapFavoriteIds.addListener(
        () => notifications.add(controller.resourceMapFavoriteIds.value),
      );

      await expectLater(
        controller.updateDocumentDurably(
          (document) => document.copyWith(
            extensions: const <String, Object?>{
              'resourceMap': <String, Object?>{
                'favoriteResourceIds': <String>['replacement'],
              },
            },
          ),
        ),
        throwsStateError,
      );

      expect(notifications, const <Set<String>>[
        <String>{'replacement'},
        <String>{'original'},
      ]);
      expect(controller.resourceMapFavoriteIds.value, const <String>{
        'original',
      });
      await controller.dispose();
    },
  );

  test('quantity commands accept de-DE decimal input', () async {
    final controller = _controller();
    final mode = controller.active;

    expect(mode.commitAmount('12,8'), isTrue);
    expect(mode.state.value.want, 12);
    expect(mode.commitInventory('Base', '1.234,5'), isTrue);
    expect(mode.state.value.inventory['Base'], 1234.5);

    await controller.dispose();
  });

  test(
    'market classification and trade evidence persist across mode switches',
    () async {
      final controller = _controller();
      final alchemy = controller.active;

      alchemy.replaceMarketValues(
        prices: const <String, double>{},
        stock: const <String, double>{},
        tradeMarketIds: const <String, String>{'Ore': '9'},
        totalTrades: const <String, int>{'Ore': 100},
        tradeObservedAt: const <String, int>{'Ore': 1000},
        observedDailyTrades: const <String, double>{'Ore': 24},
        tradeObservationHours: const <String, double>{'Ore': 6},
        lastSoldAtEpochSeconds: const <String, int>{'Ore': 900},
        unlistedItemNames: const <String>{'  BASE  '},
        fetchedAt: 42,
      );

      expect(alchemy.state.value.market.isItemUnlisted('Base'), isTrue);
      expect(
        controller.documentSnapshot.alchemy.market.unlistedItemNames,
        const <String>{'base'},
      );
      controller.switchMode(CraftMode.cooking);
      expect(controller.active.state.value.market.unlistedItemNames, isEmpty);
      controller.switchMode(CraftMode.alchemy);
      expect(
        controller.active.state.value.market.isItemUnlisted('BASE'),
        isTrue,
      );
      expect(
        controller.active.state.value.market.observedDailyTrades,
        const <String, double>{'Ore': 24},
      );
      expect(
        controller.active.state.value.market.tradeObservationHours,
        const <String, double>{'Ore': 6},
      );

      await controller.flush();
      await controller.dispose();
    },
  );

  test(
    'assembled recipes stay cached for unrelated state and invalidate safely',
    () async {
      final controller = _controller();
      final mode = controller.active;
      final initialRecipes = mode.recipes;

      mode.navigate('inventory');
      expect(identical(mode.recipes, initialRecipes), isTrue);
      mode.commitInventory('Base', '12');
      expect(identical(mode.recipes, initialRecipes), isTrue);

      mode.updateState(
        (state) => state.copyWith(hiddenItems: const <String>['Base']),
        immediate: true,
      );
      expect(identical(mode.recipes, initialRecipes), isFalse);
      expect(mode.recipes, isNot(contains('Base')));

      await controller.dispose();
    },
  );

  test(
    'legacy processing yield values persist without affecting plans',
    () async {
      final lowYield = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document().copyWith(
          activeMode: CraftMode.processing,
          processingYields: const <String, double>{
            'defaultYield': 1,
            'Grinding': .5,
          },
        ),
        saveState: (state) async => state,
        saveDebounce: Duration.zero,
      );
      final highYield = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document().copyWith(
          activeMode: CraftMode.processing,
          processingYields: const <String, double>{
            'defaultYield': 99,
            'Grinding': 77,
          },
        ),
        saveState: (state) async => state,
        saveDebounce: Duration.zero,
      );

      expect(
        lowYield.active.plan.value.toJson(),
        highYield.active.plan.value.toJson(),
      );
      expect(lowYield.documentSnapshot.processingYields['defaultYield'], 1);
      expect(highYield.documentSnapshot.processingYields['defaultYield'], 99);
      await lowYield.dispose();
      await highYield.dispose();
    },
  );

  test(
    'substitute, grade, reset, bonus target, and mode restore work',
    () async {
      final controller = _controller();
      final alchemy = controller.active;
      final ingredient = alchemy.recipes['Potion']!.ingredients.single;

      alchemy.selectSubstitute(
        parentName: 'Potion',
        ingredient: ingredient,
        selection: 'Other Base',
      );
      alchemy.selectIngredientGrade(
        parentName: 'Potion',
        ingredientName: 'Base',
        grade: 'high',
      );
      alchemy.toggleCompleted('Potion');
      alchemy.resetCompleted();
      alchemy.updateState(
        (state) =>
            state.copyWith(bonusTarget: 'Potion', bonusWant: 7, view: 'bonus'),
      );
      alchemy.useBonusAsTarget();

      expect(
        alchemy.state.value.substituteChoices.values,
        contains('Other Base'),
      );
      expect(alchemy.state.value.ingredientGrades.values, contains('high'));
      expect(alchemy.state.value.completedSteps, isEmpty);
      expect(alchemy.state.value.want, 7);
      expect(alchemy.state.value.view, 'plan');

      controller.switchMode(CraftMode.processing);
      controller.modes[CraftMode.processing]!.navigate('bonus');
      expect(controller.activeMode.value, CraftMode.processing);
      expect(controller.active.state.value.view, 'plan');
      await controller.dispose();
    },
  );

  test(
    'recipe variant choice is saved, recalculates, and survives market refresh',
    () async {
      final saves = <PlannerState>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async {
          saves.add(state);
          return state;
        },
        saveDebounce: Duration.zero,
      );
      final mode = controller.active;
      mode.toggleCompleted('Potion');

      expect(mode.selectedRecipeVariantId('Potion'), 'base-route');
      expect(
        mode.selectRecipeVariant(
          recipeName: 'potion',
          variantId: 'ALTERNATE-ROUTE',
        ),
        isTrue,
      );
      expect(mode.state.value.recipeVariantChoices, {
        'Potion': 'alternate-route',
      });
      expect(mode.state.value.completedSteps, isNot(contains('Potion')));
      expect(
        mode.plan.value.steps.single.ingredients.single.name,
        'Variant Base',
      );
      expect(
        mode.availableIngredientGrades(
          parentName: 'Potion',
          selectedName: 'Variant Base',
        ),
        isEmpty,
        reason: 'the selected processing formula suppresses quality grades',
      );

      mode.replaceMarketValues(
        prices: const <String, double>{'Base': 1, 'Variant Base': 999},
        stock: const <String, double>{'Base': 999, 'Variant Base': 0},
        unlistedItemNames: const <String>{},
        fetchedAt: 12,
      );
      expect(mode.selectedRecipeVariantId('Potion'), 'alternate-route');
      expect(
        mode.plan.value.steps.single.ingredients.single.name,
        'Variant Base',
      );

      await controller.flush();
      expect(saves.last.alchemy.recipeVariantChoices, {
        'Potion': 'alternate-route',
      });
      await controller.dispose();
    },
  );

  test(
    'durable document update restores memory after a write failure',
    () async {
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (_) async => throw const FileSystemException('disk full'),
        saveDebounce: Duration.zero,
      );

      await expectLater(
        controller.updateDocumentDurably(
          (document) => document.copyWith(
            alchemy: document.alchemy.copyWith(target: 'Other Base'),
          ),
        ),
        throwsStateError,
      );

      expect(controller.documentSnapshot.alchemy.target, 'Potion');
      expect(controller.modes[CraftMode.alchemy]!.state.value.target, 'Potion');
      expect(controller.saveError.value, contains('disk full'));
      await controller.dispose();
    },
  );

  test(
    'failed durable update restores the document market tax notifier',
    () async {
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (_) async => throw const FileSystemException('disk full'),
        saveDebounce: Duration.zero,
      );
      final notifications = <MarketTax>[];
      controller.marketTax.addListener(
        () => notifications.add(controller.marketTax.value),
      );

      await expectLater(
        controller.updateDocumentDurably(
          (document) => document.copyWith(
            marketTax: document.marketTax.copyWith(
              enabled: false,
              valuePack: true,
              merchantRing: true,
              familyFameBonus: .015,
            ),
          ),
        ),
        throwsStateError,
      );

      expect(notifications.map((tax) => tax.enabled), const <bool>[
        false,
        true,
      ]);
      expect(controller.marketTax.value.enabled, isTrue);
      expect(controller.marketTax.value.valuePack, isFalse);
      expect(controller.marketTax.value.merchantRing, isFalse);
      expect(controller.marketTax.value.familyFameBonus, 0);
      expect(
        identical(
          controller.marketTax.value,
          controller.documentSnapshot.marketTax,
        ),
        isTrue,
      );
      await controller.dispose();
    },
  );

  test(
    'failed durable update restores the AFK weight profile notifier',
    () async {
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (_) async => throw const FileSystemException('disk full'),
        saveDebounce: Duration.zero,
      );
      final notifications = <double>[];
      controller.afkWeightProfile.addListener(
        () => notifications.add(
          controller.afkWeightProfile.value.maximumWeightLt,
        ),
      );

      await expectLater(
        controller.updateDocumentDurably(
          (document) => document.copyWith(
            afkWeightProfile: document.afkWeightProfile.copyWith(
              maximumWeightLt: 1900,
            ),
          ),
        ),
        throwsStateError,
      );

      expect(notifications, const <double>[1900, 0]);
      expect(controller.afkWeightProfile.value.maximumWeightLt, 0);
      expect(
        identical(
          controller.afkWeightProfile.value,
          controller.documentSnapshot.afkWeightProfile,
        ),
        isTrue,
      );
      await controller.dispose();
    },
  );

  test(
    'an older failed save cannot overwrite a newer durable update',
    () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final savedTargets = <String>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async {
          savedTargets.add(state.alchemy.target);
          if (savedTargets.length == 1) {
            firstStarted.complete();
            await releaseFirst.future;
            throw const FileSystemException('first write failed');
          }
          return state;
        },
        saveDebounce: Duration.zero,
      );

      controller.updateDocument(
        (document) => document.copyWith(
          alchemy: document.alchemy.copyWith(target: 'Base'),
        ),
        immediate: true,
      );
      await firstStarted.future;
      final durable = controller.updateDocumentDurably(
        (document) => document.copyWith(
          alchemy: document.alchemy.copyWith(target: 'Other Base'),
        ),
      );
      releaseFirst.complete();
      await durable;
      await controller.flush();

      expect(savedTargets, const <String>['Base', 'Other Base']);
      expect(controller.documentSnapshot.alchemy.target, 'Other Base');
      expect(controller.saveError.value, isNull);
      await controller.dispose();
    },
  );

  test('first-run setup completes in one durable save', () async {
    final saves = <PlannerState>[];
    final controller = PlannerApplicationController(
      catalog: _catalog(),
      initialState: _document(),
      saveState: (state) async {
        saves.add(state);
        return state;
      },
      saveDebounce: Duration.zero,
    );

    await controller.finishFirstRunSetup(
      const FirstRunSetupAnswers(
        alchemyMastery: 1200,
        cookingMastery: 900,
        processingMastery: 1500,
        useMassProcessing: true,
        maximumWeightLt: 1900,
        currentCarriedWeightLt: 125,
        safetyBufferLt: 25,
        featheryStepsLevel: 3,
        valuePack: true,
        merchantRing: true,
        familyFameBonus: .015,
      ),
      groups: FirstRunSetupSchema.groups,
    );

    expect(saves, hasLength(1));
    expect(controller.documentSnapshot.alchemy.alchemyMastery, 1200);
    expect(controller.documentSnapshot.cooking.cookingMastery, 900);
    expect(controller.documentSnapshot.processing.processingMastery, 1500);
    expect(controller.documentSnapshot.processing.useMassProcessing, isTrue);
    expect(controller.documentSnapshot.afkWeightProfile.maximumWeightLt, 1900);
    expect(
      controller.documentSnapshot.afkWeightProfile.currentCarriedWeightLt,
      125,
    );
    expect(controller.documentSnapshot.afkWeightProfile.safetyBufferLt, 25);
    expect(controller.documentSnapshot.afkWeightProfile.featheryStepsLevel, 3);
    expect(controller.marketTax.value.valuePack, isTrue);
    expect(controller.marketTax.value.merchantRing, isTrue);
    expect(
      FirstRunSetupProgress.fromDocument(
        controller.documentSnapshot,
      ).shouldShow,
      isFalse,
    );
    await controller.dispose();
  });

  test('failed first-run setup save restores every prior value', () async {
    final initial = _document();
    final controller = PlannerApplicationController(
      catalog: _catalog(),
      initialState: initial,
      saveState: (_) async => throw const FileSystemException('disk full'),
      saveDebounce: Duration.zero,
    );

    await expectLater(
      controller.finishFirstRunSetup(
        const FirstRunSetupAnswers(
          alchemyMastery: 1200,
          cookingMastery: 900,
          processingMastery: 1500,
          useMassProcessing: true,
          maximumWeightLt: 1900,
          currentCarriedWeightLt: 125,
          safetyBufferLt: 25,
          featheryStepsLevel: 3,
          valuePack: true,
          merchantRing: true,
          familyFameBonus: .015,
        ),
        groups: FirstRunSetupSchema.groups,
      ),
      throwsStateError,
    );

    expect(identical(controller.documentSnapshot, initial), isTrue);
    expect(controller.active.state.value.alchemyMastery, 0);
    expect(controller.marketTax.value.valuePack, isFalse);
    expect(
      controller.documentSnapshot.extensions,
      isNot(contains(firstRunSetupExtensionKey)),
    );
    await controller.dispose();
  });
}

PlannerApplicationController _controller() => PlannerApplicationController(
  catalog: _catalog(),
  initialState: _document(),
  saveState: (state) async => state,
  saveDebounce: Duration.zero,
);

PlannerState _document() => PlannerState(
  applicationVersion: 'test',
  lastSuccessfulWriteUtc: DateTime.utc(2026),
  activeMode: CraftMode.alchemy,
  alchemy: _mode(CraftMode.alchemy, 'Potion'),
  cooking: _mode(CraftMode.cooking, 'Meal'),
  processing: _mode(CraftMode.processing, 'Flour'),
  processingYields: const {'defaultYield': 2.5},
  marketTax: MarketTax(),
);

ModeState _mode(CraftMode mode, String target) => ModeState(
  target: target,
  bonusTarget: target,
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);

CatalogSnapshot _catalog() => CatalogSnapshot(
  sourceSha256: 'fixture',
  sourceByteCount: 1,
  alchemy: _modeCatalog(CraftMode.alchemy, 'Potion'),
  cooking: _modeCatalog(CraftMode.cooking, 'Meal'),
  processing: _modeCatalog(CraftMode.processing, 'Flour'),
  supportingData: const {
    'qualityIngredients': <String>['Variant Base'],
  },
  collisions: const [],
);

ModeCatalog _modeCatalog(CraftMode mode, String target) => ModeCatalog(
  mode: mode,
  items: {
    target: _recipe(
      target,
      mode.key,
      [
        Ingredient(
          name: 'Base',
          quantity: 2,
          options: const ['Base', 'Other Base'],
          substituteGroup: 'bases',
          substituteRatios: const {'Other Base': 2},
        ),
      ],
      variants: <RecipeVariant>[
        RecipeVariant(
          id: 'base-route',
          label: 'Base Route',
          type: mode.key,
          baseOutput: 1,
          method: null,
          ingredients: <Ingredient>[
            Ingredient(
              name: 'Base',
              quantity: 2,
              options: const <String>['Base', 'Other Base'],
              substituteGroup: 'bases',
              substituteRatios: const <String, double>{'Other Base': 2},
            ),
          ],
          outputMinimum: 1,
          outputMaximum: 1,
        ),
        RecipeVariant(
          id: 'alternate-route',
          label: 'Alternate Route',
          type: 'processing',
          baseOutput: 1,
          method: null,
          ingredients: <Ingredient>[
            Ingredient(
              name: 'Variant Base',
              quantity: 3,
              options: const <String>[],
              substituteGroup: null,
              substituteRatios: const <String, double>{},
            ),
          ],
          outputMinimum: 1,
          outputMaximum: 1,
        ),
      ],
      defaultVariantId: 'base-route',
    ),
    'Base': _recipe('Base', 'gathered', const []),
    'Other Base': _recipe('Other Base', 'gathered', const []),
    'Variant Base': _recipe('Variant Base', 'gathered', const []),
  },
  iconDataUris: const {},
  defaults: const {},
  metadata: const {},
  searchAliases: const {},
);

Recipe _recipe(
  String name,
  String type,
  List<Ingredient> ingredients, {
  List<RecipeVariant> variants = const <RecipeVariant>[],
  String? defaultVariantId,
}) => Recipe(
  name: name,
  type: type,
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: ingredients,
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 1,
  outputMaximum: 1,
  variants: variants,
  defaultVariantId: defaultVariantId,
);
