import 'dart:io';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/map_menu_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BdoResourceMapDataset dataset;
  late Directory cacheDirectory;
  late MockClient tileClient;

  setUpAll(() async {
    if ((Platform.environment['MAP_MENU_CAPTURE_DIR'] ?? '').isNotEmpty) {
      await loadMapMenuCaptureFonts();
    }
    dataset = await BdoResourceMapLoader.loadBundled();
    cacheDirectory = await Directory.systemTemp.createTemp(
      'bdo_map_vendor_panel_test_',
    );
    tileClient = MockClient(
      (_) async => http.Response('', HttpStatus.notFound),
    );
  });

  tearDownAll(() async {
    tileClient.close();
    await cacheDirectory.delete(recursive: true);
  });

  for (final viewport in [const Size(1200, 752), const Size(790, 500)]) {
    testWidgets(
      'small NPC inspector stays steady when the map pans at $viewport',
      (tester) async {
        final controller = BdoResourceMapController();
        addTearDown(controller.dispose);
        await tester.binding.setSurfaceSize(viewport);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: const ValueKey('anchored-npc-capture'),
              child: BdoResourceMap(
                dataset: dataset,
                cacheDirectory: cacheDirectory,
                tileHttpClient: tileClient,
                showSourceNotice: false,
                controller: controller,
                vendorPortraitBuilder: (context, vendor, size) {
                  final asset = bdoBundledVendorPortraitAsset(
                    vendor.sourceVendorId,
                  );
                  return asset == null
                      ? Icon(Icons.person, size: size)
                      : Image.asset(
                          asset,
                          width: size,
                          height: size,
                          fit: BoxFit.contain,
                        );
                },
              ),
            ),
          ),
        );
        controller.focus(
          const BdoResourceMapFocusRequest(
            materialName: 'Purified Water',
            source: BdoResourceMapFocusSource.npcVendors,
          ),
        );
        await tester.pumpAndSettle();
        final vendor = dataset
            .vendorNpcsForItem('Purified Water')
            .firstWhere((v) => v.name == 'Waida');
        final camera = tester
            .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
            .cameraController;
        camera.showPoint(vendor.location, viewport: viewport, zoom: 6.4);
        await tester.pumpAndSettle();
        final marker = find.byKey(
          ValueKey('resource-map-vendor-marker-${vendor.id}'),
        );
        expect(tester.getSize(marker), const Size(56, 56));
        final art = tester.widget<Image>(
          find.descendant(of: marker, matching: find.byType(Image)),
        );
        expect(art.width, 44);
        await tester.tap(marker);
        await tester.pumpAndSettle();
        final details = find.byKey(const ValueKey('resource-map-atlas-dock'));
        final before = tester.getRect(details);
        expect(before.height, lessThan(330));
        expect(before.left, isNot(16));
        expect(before.top, 16);
        expect(before.right, closeTo(viewport.width - 88, 1));
        expect(before.bottom, lessThanOrEqualTo(viewport.height - 12));
        expect(
          tester
              .getRect(
                find.byKey(const ValueKey('resource-map-workspace-position')),
              )
              .topLeft,
          before.topLeft,
        );
        await captureMapMenu(
          tester,
          boundary: find.byKey(const ValueKey('anchored-npc-capture')),
          name: 'waida-click-details-${viewport.width.toInt()}',
        );
        camera.panBy(const Offset(0, 20), viewport);
        await tester.pumpAndSettle();
        expect(tester.getRect(details).top, before.top);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('every vendor item lookup returns every unique mapped seller', () {
    final listingsByItemId = <int, List<BdoVendorListing>>{};
    for (final listing in dataset.vendorListings) {
      (listingsByItemId[listing.itemId] ??= <BdoVendorListing>[]).add(listing);
    }

    for (final entry in listingsByItemId.entries) {
      final listings = entry.value;
      final itemName = listings.first.itemName;
      final expectedVendorIds = listings
          .map((listing) => listing.vendorId)
          .toSet();
      final actualVendorIds = dataset
          .vendorNpcsForItem(itemName, itemId: entry.key)
          .map((vendor) => vendor.id)
          .toSet();
      expect(
        actualVendorIds,
        unorderedEquals(expectedVendorIds),
        reason: '$itemName (${entry.key}) must not apply a seller cap.',
      );
    }
  });

  testWidgets(
    'herb seller pins open details and every seller remains reachable',
    (tester) async {
      const viewport = Size(1200, 752);
      const itemName = 'Silver Azalea';
      final vendors = dataset.vendorNpcsForItem(itemName);
      expect(vendors.length, greaterThan(5));
      final controller = BdoResourceMapController();
      addTearDown(controller.dispose);
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              cacheDirectory: cacheDirectory,
              tileHttpClient: tileClient,
              showSourceNotice: false,
              controller: controller,
            ),
          ),
        ),
      );
      const request = BdoResourceMapFocusRequest(
        materialName: itemName,
        source: BdoResourceMapFocusSource.npcVendors,
      );
      controller.focus(request);
      await tester.pumpAndSettle();

      expect(
        find.text(
          '${vendors.length} mapped NPC locations · click a pin for details',
        ),
        findsOneWidget,
      );

      // Vendor markers remain part of the shared geographic gesture surface:
      // dragging one pans the map and must not accidentally choose a seller.
      var clusters = _vendorClusters.hitTestable();
      expect(clusters, findsWidgets);
      final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      final cameraBeforeDrag = canvas.cameraController.camera;
      final drag = await tester.startGesture(
        tester.getCenter(clusters.first),
        kind: PointerDeviceKind.mouse,
      );
      for (var step = 0; step < 8; step += 1) {
        await drag.moveBy(const Offset(9, 6));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await drag.up();
      await tester.pumpAndSettle();
      expect(
        canvas.cameraController.camera.center,
        isNot(cameraBeforeDrag.center),
      );
      expect(_vendorPicker, findsNothing);

      // Refocus and click the visible grouped pin. The first click now opens
      // its seller choices instead of requiring repeated zoom clicks.
      controller.focus(request);
      await tester.pumpAndSettle();
      clusters = _vendorClusters.hitTestable();
      expect(clusters, findsWidgets);
      await tester.tap(
        find.descendant(of: clusters.first, matching: find.byType(InkResponse)),
      );
      await tester.pump();
      expect(_vendorPicker, findsOneWidget);

      await captureMapMenu(
        tester,
        boundary: find.byType(RepaintBoundary).first,
        name: 'npc-sellers-text100',
      );
      final choice = _vendorChoices.first;
      final choiceKey = tester.widget(choice).key! as ValueKey<String>;
      final selectedVendorId = choiceKey.value.replaceFirst(
        'resource-map-vendor-cluster-choice-',
        '',
      );
      _expectReadableVendorChoice(tester, choice);
      await tester.tap(choice);
      await tester.pump();

      final inspector = find.byKey(const ValueKey('resource-map-atlas-dock'));
      expect(inspector, findsOneWidget);
      final panelRect = tester.getRect(inspector);
      expect(panelRect.left, isNot(16));
      expect(panelRect.right, lessThanOrEqualTo(viewport.width - 12));
      expect(panelRect.bottom, lessThanOrEqualTo(viewport.height - 12));
      expect(panelRect.right, closeTo(viewport.width - 88, 1));
      expect(panelRect.height, greaterThan(500));
      expect(panelRect.top, greaterThanOrEqualTo(0));
      expect(panelRect.bottom, lessThanOrEqualTo(viewport.height));
      expect(find.text('Other sellers'), findsOneWidget);
      await captureMapMenu(
        tester,
        boundary: find.byType(RepaintBoundary).first,
        name: 'npc-details-anchored-1200',
      );

      final otherVendorIds = vendors
          .where((vendor) => vendor.id != selectedVendorId)
          .map((vendor) => vendor.id)
          .toList(growable: false);
      for (final vendorId in otherVendorIds) {
        expect(
          find.byKey(ValueKey('resource-map-other-vendor-$vendorId')),
          findsOneWidget,
        );
      }

      final detailsFocus = tester.widget<Focus>(
        find.byKey(
          const ValueKey<String>('resource-map-sidebar-details-focus'),
        ),
      );
      expect(detailsFocus.focusNode!.hasFocus, isTrue);
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey<String>('resource-map-sidebar-details')),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.pixels, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();
      expect(position.pixels, greaterThan(0));

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(position.pixels, position.maxScrollExtent);
      expect(
        find
            .byKey(ValueKey('resource-map-other-vendor-${otherVendorIds.last}'))
            .hitTestable(),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(position.pixels, 0);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: panelRect.center,
          scrollDelta: const Offset(0, 180),
        ),
      );
      await tester.pump();
      expect(position.pixels, greaterThan(0));

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(position.pixels, 0);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.trackpad,
          position: panelRect.center,
          scrollDelta: const Offset(0, 120),
        ),
      );
      await tester.pump();
      expect(position.pixels, greaterThan(0));
      expect(find.byType(Scrollbar), findsNothing);
      expect(find.byType(RawScrollbar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all Silver Azalea sellers remain scrollable at 200 percent text',
    (tester) async {
      const viewport = Size(1200, 752);
      const itemName = 'Silver Azalea';
      final vendors = dataset.vendorNpcsForItem(itemName);
      expect(vendors, hasLength(18));
      final controller = BdoResourceMapController()
        ..focus(
          const BdoResourceMapFocusRequest(
            materialName: itemName,
            source: BdoResourceMapFocusSource.npcVendors,
          ),
        );
      addTearDown(controller.dispose);
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              textScaler: TextScaler.linear(2),
            ),
            child: BdoResourceMap(
              dataset: dataset,
              cacheDirectory: cacheDirectory,
              tileHttpClient: tileClient,
              showSourceNotice: false,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final clusters = _vendorClusters.hitTestable();
      expect(clusters, findsWidgets);
      await tester.tap(
        find.descendant(of: clusters.first, matching: find.byType(InkResponse)),
      );
      await tester.pump();
      expect(_vendorPicker, findsOneWidget);

      await captureMapMenu(
        tester,
        boundary: find.byType(RepaintBoundary).first,
        name: 'npc-sellers-text200',
      );
      final choice = _vendorChoices.first;
      final choiceKey = tester.widget(choice).key! as ValueKey<String>;
      final selectedVendorId = choiceKey.value.replaceFirst(
        'resource-map-vendor-cluster-choice-',
        '',
      );
      _expectReadableVendorChoice(tester, choice);
      await tester.tap(choice);
      await tester.pump();

      final inspector = find.byKey(const ValueKey('resource-map-atlas-dock'));
      expect(inspector, findsOneWidget);
      final panelRect = tester.getRect(inspector);
      expect(panelRect.height, greaterThan(500));
      expect(panelRect.top, greaterThanOrEqualTo(0));
      expect(panelRect.bottom, lessThanOrEqualTo(viewport.height));

      final otherVendorIds = vendors
          .where((vendor) => vendor.id != selectedVendorId)
          .map((vendor) => vendor.id)
          .toList(growable: false);
      expect(otherVendorIds, hasLength(17));
      for (final vendorId in otherVendorIds) {
        expect(
          find.byKey(ValueKey('resource-map-other-vendor-$vendorId')),
          findsOneWidget,
        );
      }

      final lastSeller = find.byKey(
        ValueKey('resource-map-other-vendor-${otherVendorIds.last}'),
      );
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey<String>('resource-map-sidebar-details')),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      expect(lastSeller.hitTestable(), findsNothing);

      for (
        var attempt = 0;
        attempt < 16 && lastSeller.hitTestable().evaluate().isEmpty;
        attempt += 1
      ) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            kind: PointerDeviceKind.mouse,
            position: panelRect.center,
            scrollDelta: const Offset(0, 240),
          ),
        );
        await tester.pump();
      }
      expect(position.pixels, greaterThan(0));
      expect(lastSeller.hitTestable(), findsOneWidget);
      expect(find.byType(Scrollbar), findsNothing);
      expect(find.byType(RawScrollbar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a different high-volume vendor item has no seller cap', (
    tester,
  ) async {
    const viewport = Size(1200, 752);
    const itemName = 'Salt';
    final vendors = dataset.vendorNpcsForItem(itemName, itemId: 9001);
    expect(vendors.length, greaterThan(5));
    final controller = BdoResourceMapController()
      ..focus(
        const BdoResourceMapFocusRequest(
          materialName: itemName,
          source: BdoResourceMapFocusSource.npcVendors,
        ),
      );
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileHttpClient: tileClient,
            showSourceNotice: false,
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final clusters = _vendorClusters.hitTestable();
    expect(clusters, findsWidgets);
    await tester.tap(
      find.descendant(of: clusters.first, matching: find.byType(InkResponse)),
    );
    await tester.pump();
    expect(_vendorPicker, findsOneWidget);

    final choice = _vendorChoices.first;
    final choiceKey = tester.widget(choice).key! as ValueKey<String>;
    final selectedVendorId = choiceKey.value.replaceFirst(
      'resource-map-vendor-cluster-choice-',
      '',
    );
    await tester.tap(choice);
    await tester.pump();

    final otherVendorIds = vendors
        .where((vendor) => vendor.id != selectedVendorId)
        .map((vendor) => vendor.id)
        .toList(growable: false);
    expect(otherVendorIds.length, vendors.length - 1);
    for (final vendorId in otherVendorIds) {
      expect(
        find.byKey(ValueKey('resource-map-other-vendor-$vendorId')),
        findsOneWidget,
      );
    }

    final inspector = find.byKey(const ValueKey('resource-map-atlas-dock'));
    final panelRect = tester.getRect(inspector);
    final scrollable = find.descendant(
      of: find.byKey(const ValueKey<String>('resource-map-sidebar-details')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    final lastSeller = find.byKey(
      ValueKey('resource-map-other-vendor-${otherVendorIds.last}'),
    );
    expect(lastSeller.hitTestable(), findsNothing);

    for (
      var attempt = 0;
      attempt < 20 && lastSeller.hitTestable().evaluate().isEmpty;
      attempt += 1
    ) {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: panelRect.center,
          scrollDelta: const Offset(0, 320),
        ),
      );
      await tester.pump();
    }
    expect(position.pixels, greaterThan(0));
    expect(lastSeller.hitTestable(), findsOneWidget);
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _expectReadableVendorChoice(WidgetTester tester, Finder choice) {
  final labels = tester
      .widgetList<Text>(
        find.descendant(of: choice, matching: find.byType(Text)),
      )
      .toList();
  expect(labels, hasLength(3));
  expect(labels.first.style?.fontSize, 14);
  for (final label in labels) {
    expect(label.style?.fontSize, anyOf(14, 12.5));
    expect(label.maxLines, isNull);
    expect(label.overflow, isNot(TextOverflow.ellipsis));
  }
}

Finder get _vendorClusters => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      key.value.startsWith('resource-map-vendor-cluster-');
});

Finder get _vendorPicker =>
    find.byKey(const ValueKey<String>('resource-map-vendor-cluster-picker'));

Finder get _vendorChoices => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      key.value.startsWith('resource-map-vendor-cluster-choice-');
});
