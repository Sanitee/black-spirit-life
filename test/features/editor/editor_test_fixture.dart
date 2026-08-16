import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/app/window/native_file_dialog_service.dart';
import 'package:bdo_craft_planner_flutter/data/icons/custom_icon_store.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/editor/editor.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../inventory/inventory_test_fixture.dart';

final class EditorTestHarness {
  EditorTestHarness({
    PlannerState? initialState,
    SavePlannerState? saveState,
    CatalogSnapshot? catalog,
  }) : applicationDirectory = Directory.systemTemp.createTempSync(
         'bdo-editor-test-',
       ),
       session = RecipeEditorSessionController(),
       controller = PlannerApplicationController(
         catalog: catalog ?? inventoryCatalog(additionalHerbs: 18),
         initialState: initialState ?? inventoryDocument(showDeleteTools: true),
         saveState: saveState ?? (state) async => state,
         saveDebounce: Duration.zero,
       ) {
    actions = EditorExternalActions(
      confirmDelete: (request) async {
        deleteRequests.add(request);
        return deleteApprovals.isEmpty ? true : deleteApprovals.removeAt(0);
      },
      reportTransaction: transactionNotices.add,
      offerUndo: undoOffers.add,
      reportUndo: undoResults.add,
    );
    iconStore = CustomIconStore(applicationDirectory: applicationDirectory);
  }

  final Directory applicationDirectory;
  final RecipeEditorSessionController session;
  final PlannerApplicationController controller;
  late final CustomIconStore iconStore;
  late final EditorExternalActions actions;
  final NativeFileDialogService fileDialogs = const NativeFileDialogService();
  final List<bool> deleteApprovals = <bool>[];
  final List<EditorDeleteRequest> deleteRequests = <EditorDeleteRequest>[];
  final List<EditorTransactionNotice> transactionNotices =
      <EditorTransactionNotice>[];
  final List<EditorUndoOffer> undoOffers = <EditorUndoOffer>[];
  final List<EditorUndoResult> undoResults = <EditorUndoResult>[];

  Widget host({
    TextScaler textScaler = TextScaler.noScaling,
    ThemeSpec spec = StandardSpec.theme,
  }) => MaterialApp(
    theme: spec.materialTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: ThemeSpecScope(
      spec: spec,
      child: Scaffold(
        body: ColoredBox(
          color: spec.palette.canvas,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: RecipeEditorView(
              controller: controller.active,
              externalActions: actions,
              fileDialogs: fileDialogs,
              iconStore: iconStore,
              sessionController: session,
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> dispose() async {
    session.dispose();
    await controller.dispose();
    if (applicationDirectory.existsSync()) {
      applicationDirectory.deleteSync(recursive: true);
    }
  }
}

Future<void> pumpEditor(
  WidgetTester tester,
  EditorTestHarness harness, {
  Size size = const Size(1200, 752),
  TextScaler textScaler = TextScaler.noScaling,
  ThemeSpec spec = StandardSpec.theme,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(harness.host(textScaler: textScaler, spec: spec));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 140));
}

Future<void> finishEditor(
  WidgetTester tester,
  EditorTestHarness harness,
) async {
  await tester.runAsync(harness.dispose);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Finder editorForKey(Key key) =>
    find.descendant(of: find.byKey(key), matching: find.byType(EditableText));

Finder editorForSemantics(String label) => find.descendant(
  of: find.bySemanticsLabel(label),
  matching: find.byType(EditableText),
);

PlannerState editorDeepDocument() {
  final base = inventoryDocument(showDeleteTools: true);
  final deepRecipe = RecipeState(
    type: 'alchemy',
    baseOutput: 1.75,
    group: 'Alchemy Reagents',
    ingredients: <IngredientState>[
      IngredientState(
        name: 'Sunrise Herb',
        quantity: 2.5,
        options: const <String>[
          'Sunrise Herb',
          'Silver Azalea',
          'Clear Liquid Reagent',
        ],
        substituteGroup: 'wild-herb',
        substituteRatios: const <String, double>{
          'Sunrise Herb': 1,
          'Silver Azalea': 1.5,
          'Clear Liquid Reagent': 2,
        },
        extensions: const <String, Object?>{
          'futureIngredientRule': <String, Object?>{'rank': 7},
        },
      ),
    ],
    marketId: '999999999999999999999999999',
    sourceNote: 'Bundled source override',
    outputMinimum: 1,
    outputMaximum: 4,
    extensions: const <String, Object?>{
      'futureRecipeRule': <String, Object?>{'enabled': true},
    },
  );
  final dependent = RecipeState(
    type: 'alchemy',
    ingredients: <IngredientState>[
      IngredientState(
        name: 'Clear Liquid Reagent',
        quantity: 3,
        options: const <String>['Clear Liquid Reagent'],
        substituteRatios: const <String, double>{'Clear Liquid Reagent': 1},
      ),
    ],
  );
  final alchemy = ModeState(
    target: 'Clear Liquid Reagent',
    want: base.alchemy.want,
    bonusTarget: 'Clear Liquid Reagent',
    inventory: const <String, double>{'Clear Liquid Reagent': 9},
    view: 'editor',
    recipeEdits: <String, RecipeState?>{
      'Clear Liquid Reagent': deepRecipe,
      'Custom Elixir': dependent,
    },
    iconAliases: const <String, String>{
      'Clear Liquid Reagent': 'Clear Liquid Reagent',
    },
    ingredientMeta: <String, IngredientMetadata>{
      'Clear Liquid Reagent': IngredientMetadata(
        category: 'Alchemy Reagents',
        vendor: 'Lara',
        location: 'Heidel',
        searchKeywords: 'liquid reagent catalyst',
        marketId: '999999999999999999999999999',
        qualityBase: 'Catalyst',
        qualityTier: 'normal',
        extensions: const <String, Object?>{
          'futureMetaRule': <String, Object?>{'color': 'verdant'},
        },
      ),
    },
    substituteChoices: const <String, String>{
      'recipe:Clear Liquid Reagent:wild-herb': 'Clear Liquid Reagent',
    },
    ingredientGrades: const <String, String>{
      'recipe:Clear Liquid Reagent:Clear Liquid Reagent': 'high',
    },
    favoriteRecipes: const <String>['Clear Liquid Reagent'],
    market: MarketState(
      prices: const <String, double>{'Clear Liquid Reagent': 12500},
      stock: const <String, double>{'Clear Liquid Reagent': 44},
      selected: 'Clear Liquid Reagent',
    ),
    completedSteps: const <String>['Clear Liquid Reagent'],
    appearance: AppearanceSettings.defaultsFor(CraftMode.alchemy),
    extensions: const <String, Object?>{
      'futureModeRule': <String, Object?>{'kept': true},
    },
  );
  return base.copyWith(alchemy: alchemy);
}

const List<int> onePixelPngBytes = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  4,
  0,
  0,
  0,
  181,
  28,
  12,
  2,
  0,
  0,
  0,
  11,
  73,
  68,
  65,
  84,
  120,
  218,
  99,
  100,
  248,
  15,
  0,
  1,
  5,
  1,
  1,
  39,
  24,
  227,
  102,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];
