import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/shop_lodging_setup_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shop lodging edits purchased Pearl Loyalty and Other separately',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(700, 650));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final saved = <WorkerLodgingShopSetup>[];
      final calpheon = WorkerLodgingShopCatalog.findTown('Calpheon City')!;

      await tester.pumpWidget(
        _DialogHarness(
          dialog: WorkerLodgingShopSetupDialog(
            townName: 'Calpheon City',
            catalogTown: calpheon,
            initialValue: const WorkerLodgingShopSetup(),
            onSave: saved.add,
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Shop lodging · Calpheon City'), findsOneWidget);
      expect(find.text('0 of 5 purchased'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('resource-map-shop-lodging-loyalty')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Enter purchased, not remaining'),
        findsOneWidget,
      );

      final pearlPlus = find.byKey(
        const ValueKey<String>('resource-map-shop-lodging-pearl-plus'),
      );
      for (var count = 0; count < calpheon.pearlCouponLimit; count += 1) {
        await tester.tap(pearlPlus);
        await tester.pump();
      }
      expect(find.text('5 of 5 purchased'), findsOneWidget);
      expect(tester.widget<IconButton>(pearlPlus).onPressed, isNull);
      await tester.tap(pearlPlus, warnIfMissed: false);
      await tester.pump();
      expect(find.text('5 of 5 purchased'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-shop-lodging-loyalty')),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey<String>('resource-map-shop-lodging-other')),
        '3',
      );
      await tester.pump();
      expect(find.text('Adds 9 bonus beds'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-shop-lodging-save')),
      );
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      expect(saved.single.pearlPurchased, 5);
      expect(saved.single.loyaltyPurchased, 1);
      expect(saved.single.otherBonus, 3);
      expect(saved.single.totalBonus, 9);
      expect(
        find.byKey(const ValueKey<String>('resource-map-shop-lodging-dialog')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('uncataloged town keeps Other bonus available', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final saved = <WorkerLodgingShopSetup>[];

    await tester.pumpWidget(
      _DialogHarness(
        dialog: WorkerLodgingShopSetupDialog(
          townName: 'Future Town',
          initialValue: const WorkerLodgingShopSetup(otherBonus: 2),
          onSave: saved.add,
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('resource-map-shop-lodging-pearl')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-shop-lodging-loyalty')),
      findsNothing,
    );
    expect(
      find.textContaining('No verified town-specific shop coupon'),
      findsOneWidget,
    );
    expect(find.text('Adds 2 bonus beds'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-shop-lodging-save')),
    );
    await tester.pumpAndSettle();
    expect(saved.single.totalBonus, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('older unsplit bonus is explained instead of guessed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _DialogHarness(
        dialog: WorkerLodgingShopSetupDialog(
          townName: 'Calpheon City',
          catalogTown: WorkerLodgingShopCatalog.findTown('Calpheon City'),
          initialValue: const WorkerLodgingShopSetup(),
          legacyUnsplitBonus: 8,
          onSave: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('8 older bonus beds are saved without'),
      findsOneWidget,
    );
    expect(find.text('0 of 5 purchased'), findsOneWidget);
    expect(find.text('Adds 0 bonus beds'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses Illuminated Atlas colors and heading typography', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const chrome = ResourceMapChromeThemeData.illuminatedAtlas;

    await tester.pumpWidget(
      _DialogHarness(
        chrome: chrome,
        dialog: WorkerLodgingShopSetupDialog(
          townName: 'Calpheon City',
          catalogTown: WorkerLodgingShopCatalog.findTown('Calpheon City'),
          initialValue: const WorkerLodgingShopSetup(),
          onSave: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<AlertDialog>(
      find.byKey(const ValueKey<String>('resource-map-shop-lodging-dialog')),
    );
    expect(dialog.backgroundColor, chrome.paperRaised);
    final title = tester.widget<Text>(find.textContaining('Shop lodging'));
    expect(title.style?.color, chrome.ink);
    expect(title.style?.fontFamily, chrome.headingFontFamily);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'title area drags while the close button remains a plain action',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(760, 650));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _DialogHarness(
          dialog: WorkerLodgingShopSetupDialog(
            townName: 'Heidel',
            initialValue: const WorkerLodgingShopSetup(),
            catalogTown: WorkerLodgingShopCatalog.findTown('Heidel'),
            onSave: (_) {},
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final title = find.textContaining('Shop lodging');
      final before = tester.getCenter(title);
      await tester.drag(
        find.byKey(
          const ValueKey<String>('resource-map-shop-lodging-drag-handle'),
        ),
        const Offset(70, 32),
      );
      await tester.pump();
      expect(tester.getCenter(title), isNot(before));

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-shop-lodging-close')),
      );
      await tester.pumpAndSettle();
      expect(title, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _DialogHarness extends StatelessWidget {
  const _DialogHarness({
    required this.dialog,
    this.chrome = ResourceMapChromeThemeData.sakuraCartographer,
  });

  final Widget dialog;
  final ResourceMapChromeThemeData chrome;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: ResourceMapChromeTheme(
        data: chrome,
        child: Scaffold(
          body: Builder(
            builder: (context) {
              return Center(
                child: FilledButton(
                  onPressed: () {
                    showDialog<void>(context: context, builder: (_) => dialog);
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
