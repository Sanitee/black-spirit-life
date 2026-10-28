import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'retained map and already-open nested dialogs follow Appearance',
    (tester) async {
      final controller = _controller();
      final stateKey = GlobalKey<_RetainedMapState>();
      await tester.pumpWidget(
        MaterialApp(
          home: ResourceMapThemeBinding(
            controller: controller,
            child: _RetainedMap(key: stateKey),
          ),
        ),
      );
      final retained = stateKey.currentState!;
      final initial = retained.builds;
      controller.active.updateState((s) => s.copyWith(inventory: {'Salt': 7}));
      await tester.pump();
      expect(
        retained.builds,
        initial,
        reason: 'Inventory must not repaint map chrome.',
      );
      await tester.tap(find.text('Open map dialog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open nested dialog'));
      await tester.pumpAndSettle();
      final route = ModalRoute.of(
        tester.element(find.byKey(const ValueKey('nested'))),
      );
      controller.active.updateState(
        (s) => s.copyWith(appearance: _appearance('illuminated-ledger')),
      );
      await tester.pumpAndSettle();
      expect(stateKey.currentState, same(retained));
      expect(
        ModalRoute.of(tester.element(find.byKey(const ValueKey('nested')))),
        same(route),
      );
      expect(stateKey.currentContext!.mapChrome.uiOpacity, .6);
      expect(
        stateKey.currentContext!.mapChrome.ink,
        IlluminatedLedgerSpec.theme.palette.text,
      );
      for (final key in ['dialog', 'nested']) {
        final context = tester.element(
          find.byKey(ValueKey(key), skipOffstage: false),
        );
        expect(context.mapChrome.ink, IlluminatedLedgerSpec.theme.palette.text);
        expect(context.mapChrome.uiOpacity, 1);
        expect(context.mapChrome.chromeRaised.a, 1);
      }
      controller.setResourceMapUiOpacity(0);
      await tester.pumpAndSettle();
      expect(stateKey.currentContext!.mapChrome.uiOpacity, 0);
      expect(
        tester
            .element(find.byKey(const ValueKey('nested')))
            .mapChrome
            .uiOpacity,
        1,
      );
      controller.switchMode(CraftMode.cooking);
      await tester.pumpAndSettle();
      expect(
        tester.element(find.byKey(const ValueKey('nested'))).mapChrome.ink,
        SakuraNightGardenSpec.theme.palette.text,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.dispose();
    },
  );
  testWidgets(
    'binding swaps controllers and removes old appearance listeners',
    (tester) async {
      final old = _controller();
      final next = _controller();
      next.active.updateState(
        (s) => s.copyWith(appearance: _appearance('illuminated-ledger')),
      );
      final stateKey = GlobalKey<_RetainedMapState>();
      Widget view(PlannerApplicationController c) => MaterialApp(
        home: ResourceMapThemeBinding(
          controller: c,
          child: _RetainedMap(key: stateKey),
        ),
      );
      await tester.pumpWidget(view(old));
      final retained = stateKey.currentState;
      await tester.pumpWidget(view(next));
      expect(stateKey.currentState, same(retained));
      expect(
        stateKey.currentContext!.mapChrome.ink,
        IlluminatedLedgerSpec.theme.palette.text,
      );
      old.setResourceMapUiOpacity(.25);
      await tester.pump();
      expect(stateKey.currentContext!.mapChrome.uiOpacity, .6);
      await tester.pumpWidget(const SizedBox.shrink());
      await old.dispose();
      await next.dispose();
    },
  );
}

class _RetainedMap extends StatefulWidget {
  const _RetainedMap({super.key});
  @override
  State<_RetainedMap> createState() => _RetainedMapState();
}

class _RetainedMapState extends State<_RetainedMap> {
  int builds = 0;
  @override
  Widget build(BuildContext context) {
    builds++;
    return ColoredBox(
      color: context.mapChrome.paper,
      child: Center(
        child: TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const _Dialog(),
          ),
          child: const Text('Open map dialog'),
        ),
      ),
    );
  }
}

class _Dialog extends StatelessWidget {
  const _Dialog();
  @override
  Widget build(BuildContext context) => ResourceMapChromeTheme(
    data: context.mapChrome.withUiOpacity(1),
    liveData: ResourceMapChromeTheme.liveDataOf(context),
    opacityOverride: 1,
    child: Builder(
      builder: (context) => AlertDialog(
        key: const ValueKey('dialog'),
        content: TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              key: const ValueKey('nested'),
              backgroundColor: context.mapChrome.paper,
              content: const Text('Nested'),
            ),
          ),
          child: const Text('Open nested dialog'),
        ),
      ),
    ),
  );
}

AppearanceSettings _appearance(String background) => AppearanceSettings(
  background: background,
  particleStyle: 'none',
  particleMinSize: 1,
  particleMaxSize: 1,
  particleHue: 0,
  buttonEffect: 'none',
  buttonEffectHue: 0,
  accentHue: 158,
);
PlannerApplicationController _controller() {
  ModeCatalog catalog(CraftMode mode) => ModeCatalog(
    mode: mode,
    items: const {},
    iconDataUris: const {},
    defaults: const {},
    metadata: const {},
    searchAliases: const {},
  );
  ModeState mode() => ModeState(
    target: '',
    bonusTarget: '',
    market: MarketState(),
    appearance: _appearance('sakura-night-garden'),
  );
  return PlannerApplicationController(
    catalog: CatalogSnapshot(
      sourceSha256: 'test',
      sourceByteCount: 1,
      alchemy: catalog(CraftMode.alchemy),
      cooking: catalog(CraftMode.cooking),
      processing: catalog(CraftMode.processing),
      supportingData: const {},
      collisions: const [],
    ),
    initialState: PlannerState(
      applicationVersion: 'test',
      lastSuccessfulWriteUtc: DateTime.utc(2026),
      activeMode: CraftMode.alchemy,
      alchemy: mode(),
      cooking: mode(),
      processing: mode(),
      processingYields: const {},
      marketTax: MarketTax(),
      extensions: const {},
    ),
    saveState: (state) async => state,
    saveDebounce: const Duration(days: 1),
  );
}
