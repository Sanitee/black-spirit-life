import 'dart:io';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Regression coverage for the user's approved Gathering-menu density:
/// option names are 16px, utility labels stay compact, and panels fit content.
/// All names, products, connections and result counts come from the bundle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BdoResourceMapDataset dataset;
  late Directory cacheDirectory;
  late MockClient tileClient;
  late BdoWorkerNode thornwood;

  setUpAll(() async {
    dataset = await BdoResourceMapLoader.loadBundled();
    cacheDirectory = await Directory.systemTemp.createTemp(
      'bdo_map_adaptive_panel_test_',
    );
    tileClient = MockClient(
      (_) async => http.Response('', HttpStatus.notFound),
    );
    thornwood = dataset.workerNodes.singleWhere(
      (node) =>
          node.isResourceNode && node.name == 'Thornwood Forest - Lumbering',
    );
    expect(
      thornwood.outputs,
      hasLength(7),
      reason: 'This layout regression must exercise all seven real outputs.',
    );
  });

  tearDownAll(() async {
    tileClient.close();
    await cacheDirectory.delete(recursive: true);
  });

  Future<void> openMap(
    WidgetTester tester,
    ResourceMapInterfaceStyle style, {
    Size viewport = const Size(1200, 752),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: viewport,
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: ResourceMapChromeTheme(
            data: style == ResourceMapInterfaceStyle.ghostLedger
                ? ResourceMapChromeThemeData.ghostLedger
                : ResourceMapChromeThemeData.glassDock,
            child: BdoResourceMap(
              dataset: dataset,
              cacheDirectory: cacheDirectory,
              tileHttpClient: tileClient,
              showSourceNotice: false,
              interfaceStyle: style,
              resourceIconBuilder: _artworkSizeProbe,
              workerOutputIconBuilder: _artworkSizeProbe,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectThornwood(WidgetTester tester) async {
    await tester.enterText(_searchField, thornwood.name);
    await tester.pumpAndSettle();
    final result = find.byKey(
      ValueKey('resource-map-search-result-workerNode-${thornwood.id}'),
    );
    expect(result, findsOneWidget);
    await tester.ensureVisible(result);
    await tester.tap(result);
    await tester.pumpAndSettle();
    expect(_inspector, findsOneWidget);
  }

  for (final style in ResourceMapInterfaceStyle.values) {
    testWidgets(
      '${style.id}: seven-output node uses readable, content-adaptive details',
      (tester) async {
        await openMap(tester, style);
        await selectThornwood(tester);

        final panelRect = tester.getRect(_inspector);
        expect(
          panelRect.height,
          greaterThan(320),
          reason: 'Seven outputs must not be squeezed into the old 320px cap.',
        );
        expect(panelRect.width, inInclusiveRange(310, 480));
        _expectWithinViewport(panelRect, const Size(1200, 752));

        for (final output in thornwood.outputs) {
          final row = find.byKey(
            ValueKey('resource-map-node-output-${output.resourceId}'),
          );
          expect(row, findsOneWidget);
          final label = find.descendant(
            of: row,
            matching: find.text(output.name),
          );
          expect(label, findsOneWidget);
          expect(
            _effectiveFontSize(tester, label),
            16,
            reason:
                '${output.name} must match the approved submenu label size.',
          );
          final artwork = find.descendant(
            of: row,
            matching: find.byKey(ValueKey('artwork-size-${output.resourceId}')),
          );
          expect(tester.getSize(artwork), const Size.square(36));
          expect(tester.getSize(row).height, greaterThanOrEqualTo(40));
          expect(
            _fullyVisibleInside(tester, label, panelRect),
            isTrue,
            reason:
                '${output.name} should be visible without scrolling when '
                'the normal desktop viewport has room for all seven outputs.',
          );
        }
        _expectNoOverflowOrScrollbars(tester);
      },
    );

    testWidgets(
      '${style.id}: short-window 200% node details scroll to the final action',
      (tester) async {
        const viewport = Size(1200, 560);
        await openMap(tester, style, viewport: viewport, textScale: 2);
        await selectThornwood(tester);
        final initialRect = tester.getRect(_inspector);
        _expectWithinViewport(initialRect, viewport);
        _expectNoOverflowOrScrollbars(tester);

        final savePath = find.byKey(
          const ValueKey('resource-map-node-add-route'),
        );
        final pathToggle = find.byKey(
          const ValueKey('resource-map-worker-path-toggle'),
        );
        final finalAction = savePath.evaluate().isNotEmpty
            ? savePath
            : pathToggle;
        expect(finalAction, findsOneWidget);
        expect(
          finalAction.hitTestable(),
          findsNothing,
          reason:
              'The dense large-text case should genuinely require scrolling.',
        );

        await _wheelUntilVisible(tester, finalAction, _inspector);
        expect(finalAction.hitTestable(), findsOneWidget);
        _expectWithinViewport(tester.getRect(_inspector), viewport);

        // After scrolling, the final action remains a normal readable row.
        final labels = find.descendant(
          of: finalAction,
          matching: find.byType(Text),
        );
        expect(_effectiveFontSize(tester, labels.first), 16);
        _expectNoOverflowOrScrollbars(tester);
      },
    );

    testWidgets(
      '${style.id}: a one-product gathering source does not fill the side',
      (tester) async {
        await openMap(tester, style);
        final source = dataset.fieldSources.singleWhere(
          (source) => source.id == 'field-source:everlasting-herb',
        );
        expect(source.products, hasLength(1));
        await tester.enterText(_searchField, source.name);
        await tester.pumpAndSettle();
        final result = find.byKey(
          ValueKey('resource-map-search-result-fieldSource-${source.id}'),
        );
        expect(result, findsOneWidget);
        await tester.tap(result);
        await tester.pumpAndSettle();

        expect(_inspector, findsOneWidget);
        final panelRect = tester.getRect(_inspector);
        _expectWithinViewport(panelRect, const Size(1200, 752));
        expect(
          panelRect.height,
          lessThan(752 - panelRect.top - 100),
          reason:
              'A single-product source should shrink to its actual content, '
              'not reserve the full available side height.',
        );
        expect(panelRect.width, inInclusiveRange(310, 480));
        _expectNoOverflowOrScrollbars(tester);
      },
    );

    testWidgets(
      '${style.id}: search fits result count without replacing the focused field',
      (tester) async {
        await openMap(tester, style);
        await tester.enterText(_searchField, thornwood.name);
        await tester.pumpAndSettle();
        final field = tester.widget<TextField>(_searchField);
        final controller = field.controller!;
        final focusNode = field.focusNode!;
        expect(focusNode.hasFocus, isTrue);
        final singleResult = _searchRows;
        expect(
          singleResult,
          findsOneWidget,
          reason: 'The full production-node name is the sparse-result case.',
        );
        final singleHeight = tester.getSize(_searchSurface).height;

        await tester.enterText(_searchField, 'Thornwood');
        await tester.pumpAndSettle();
        expect(_searchRows.evaluate().length, greaterThan(1));
        final manyHeight = tester.getSize(_searchSurface).height;
        expect(
          manyHeight,
          greaterThan(singleHeight + 40),
          reason: 'Several results should get more room than a single result.',
        );
        expect(
          tester.widget<TextField>(_searchField).controller,
          same(controller),
        );
        expect(
          tester.widget<TextField>(_searchField).focusNode,
          same(focusNode),
        );
        expect(focusNode.hasFocus, isTrue);
        _expectWithinViewport(
          tester.getRect(_searchSurface),
          const Size(1200, 752),
        );
        _expectNoOverflowOrScrollbars(tester);
      },
    );
  }
}

Finder get _searchField =>
    find.byKey(const ValueKey('resource-map-atlas-search-field'));

Finder get _searchSurface =>
    find.byKey(const ValueKey('resource-map-atlas-dock'));

Finder get _inspector =>
    find.byKey(const ValueKey('resource-map-sidebar-details'));

Finder get _searchRows => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      key.value.startsWith('resource-map-search-result-');
});

Widget _artworkSizeProbe(
  BuildContext context,
  BdoResourceDefinition resource,
  double size,
) => SizedBox.square(
  key: ValueKey('artwork-size-${resource.id}'),
  dimension: size,
);

double? _effectiveFontSize(WidgetTester tester, Finder label) {
  final richText = find.descendant(of: label, matching: find.byType(RichText));
  final paragraph = tester.renderObject<RenderParagraph>(richText.first);
  return paragraph.text.style?.fontSize;
}

bool _fullyVisibleInside(WidgetTester tester, Finder content, Rect panel) {
  final rect = tester.getRect(content);
  return rect.left >= panel.left &&
      rect.right <= panel.right &&
      rect.top >= panel.top &&
      rect.bottom <= panel.bottom &&
      content.hitTestable().evaluate().isNotEmpty;
}

void _expectWithinViewport(Rect panel, Size viewport) {
  expect(panel.left, greaterThanOrEqualTo(0));
  expect(panel.top, greaterThanOrEqualTo(0));
  expect(panel.right, lessThanOrEqualTo(viewport.width));
  expect(panel.bottom, lessThanOrEqualTo(viewport.height));
}

void _expectNoOverflowOrScrollbars(WidgetTester tester) {
  expect(
    tester.takeException(),
    isNull,
    reason: 'Map controls must not overflow.',
  );
  expect(find.byType(Scrollbar), findsNothing);
  expect(find.byType(RawScrollbar), findsNothing);
}

Future<void> _wheelUntilVisible(
  WidgetTester tester,
  Finder target,
  Finder panel,
) async {
  for (var attempt = 0; attempt < 18; attempt += 1) {
    if (target.hitTestable().evaluate().isNotEmpty) return;
    final bounds = tester.getRect(panel);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: Offset(bounds.center.dx, bounds.bottom - 24),
        scrollDelta: const Offset(0, 180),
      ),
    );
    await tester.pumpAndSettle();
  }
  fail('The final detail action was not reachable by mouse-wheel scrolling.');
}
