import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/update/beta_update.dart';
import 'package:bdo_craft_planner_flutter/app/update/beta_update_indicator.dart';
import 'package:bdo_craft_planner_flutter/app/window/app_title_bar.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _root = ValueKey('native-update-capture');

void main() {
  setUpAll(_loadFonts);
  for (final entry in <String, ThemeSpec>{
    'sakura': SakuraNightGardenSpec.theme,
    'standard': StandardSpec.theme,
    'ledger': IlluminatedLedgerSpec.theme,
  }.entries) {
    testWidgets('${entry.key} native title-bar motion frames', (tester) async {
      tester.view.physicalSize = const Size(1000, 100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _MotionService();
      final controller = BetaUpdateController(service: service, source: '');
      await tester.pumpWidget(_host(controller, entry.value));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      controller.showTestUpdate(currentVersion: '0.1.13');
      await tester.pump();
      await tester.pump();
      final buttonRect = tester.getRect(
        find.byKey(BetaUpdateIndicator.buttonKey),
      );
      final iconRect = tester.getRect(find.byKey(BetaUpdateIndicator.iconKey));
      final rest = await _capture(tester, '${entry.key}-rest');
      // Exact peak of the approved 5.2s cycle; no geometry may move.
      await tester.pump(const Duration(milliseconds: 2288));
      final peak = await _capture(tester, '${entry.key}-peak');
      expect(
        tester.getRect(find.byKey(BetaUpdateIndicator.buttonKey)),
        buttonRect,
      );
      expect(tester.getRect(find.byKey(BetaUpdateIndicator.iconKey)), iconRect);
      expect(peak, isNot(orderedEquals(rest)));
      // A running timer alone passed the old, barely visible implementation.
      // Verify the actual crest lights up, not only pixels behind its face.
      final crest = iconRect.deflate(3);
      final restLight = _meanLight(rest, crest);
      final peakLight = _meanLight(peak, crest);
      if (entry.value.brightness == Brightness.dark) {
        expect(peakLight, greaterThan(restLight * 1.12));
      }
      await tester.pump(const Duration(milliseconds: 2288));
      final end = await _capture(tester, '${entry.key}-end');
      expect(end, orderedEquals(rest));
      expect(tester.takeException(), isNull);
      if (entry.key == 'sakura' &&
          Platform.environment.containsKey('BSL_UPDATE_CAPTURE_DIR')) {
        await tester.pump(const Duration(milliseconds: 624));
        for (var frame = 0; frame < 40; frame++) {
          await _capture(
            tester,
            'motion-${frame.toString().padLeft(2, '0')}',
            crop: true,
          );
          await tester.pump(const Duration(milliseconds: 130));
        }
      }
      await tester.pumpWidget(
        _host(controller, entry.value, reducedMotion: true),
      );
      await tester.pump();
      final still = await _capture(tester, '${entry.key}-reduced');
      await tester.pump(const Duration(milliseconds: 2288));
      expect(
        await _capture(tester, '${entry.key}-reduced-later'),
        orderedEquals(still),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await service.dispose();
      expect(tester.takeException(), isNull);
    });
  }
}

double _meanLight(Uint8List pixels, Rect region) {
  var total = 0.0;
  var count = 0;
  for (var y = region.top.ceil(); y < region.bottom.floor(); y++) {
    for (var x = region.left.ceil(); x < region.right.floor(); x++) {
      final index = (y * 1000 + x) * 4;
      total +=
          pixels[index] * .2126 +
          pixels[index + 1] * .7152 +
          pixels[index + 2] * .0722;
      count++;
    }
  }
  return total / count;
}

Widget _host(
  BetaUpdateController controller,
  ThemeSpec spec, {
  bool reducedMotion = false,
}) => MaterialApp(
  theme: spec.materialTheme(),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(1000, 100),
      disableAnimations: reducedMotion,
    ),
    child: ThemeSpecScope(
      spec: spec,
      child: RepaintBoundary(
        key: _root,
        child: Scaffold(
          backgroundColor: spec.palette.canvas,
          body: AppTitleBar(
            workspaceNavigation: AppTitleTabStrip(
              tabs: [
                AppTitleTab(
                  tabKey: const ValueKey('planner'),
                  label: 'Planner',
                  selected: true,
                  icon: Icons.menu_book,
                  onPressed: () {},
                ),
                AppTitleTab(
                  tabKey: const ValueKey('opportunities'),
                  label: 'Opportunities',
                  selected: false,
                  icon: Icons.auto_awesome,
                  onPressed: () {},
                ),
                AppTitleTab(
                  tabKey: const ValueKey('settings'),
                  label: 'Settings',
                  selected: false,
                  icon: Icons.settings,
                  onPressed: () {},
                ),
              ],
            ),
            trailing: BetaUpdateIndicator(
              controller: controller,
              onUpdateNow: () async {},
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<Uint8List> _capture(
  WidgetTester tester,
  String name, {
  bool crop = false,
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_root),
  );
  final bounds = crop
      ? tester
            .getRect(find.byKey(BetaUpdateIndicator.buttonKey))
            .inflate(12)
            .intersect(Offset.zero & boundary.size)
      : Offset.zero & boundary.size;
  return (await tester.runAsync(() async {
    final image = await (boundary.debugLayer! as OffsetLayer).toImage(
      bounds,
      pixelRatio: crop ? 3 : 1,
    );
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      final dir = Platform.environment['BSL_UPDATE_CAPTURE_DIR'];
      if (dir != null) {
        await Directory(dir).create(recursive: true);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$dir/$name.png').writeAsBytes(png!.buffer.asUint8List());
      }
      return data;
    } finally {
      image.dispose();
    }
  }))!;
}

Future<void> _loadFonts() async {
  var sdk = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${sdk.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    if (sdk.path == sdk.parent.path) {
      throw StateError('Flutter fonts not found');
    }
    sdk = sdk.parent;
  }
  final win = Platform.environment['WINDIR'] ?? 'C:/Windows';
  for (final family in <String, List<String>>{
    'Segoe UI': [
      '$win/Fonts/segoeui.ttf',
      '$win/Fonts/seguisb.ttf',
      '$win/Fonts/segoeuib.ttf',
    ],
    'Georgia': ['$win/Fonts/georgia.ttf', '$win/Fonts/georgiab.ttf'],
    'Roboto': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      '${sdk.path}/bin/cache/artifacts/material_fonts/roboto-bold.ttf',
    ],
    'MaterialIcons': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
  }.entries) {
    final loader = FontLoader(family.key);
    for (final file in family.value) {
      loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}

class _MotionService implements BetaUpdateService {
  final events = StreamController<BetaUpdateSnapshot>.broadcast(sync: true);
  @override
  Stream<BetaUpdateSnapshot> get snapshots => events.stream;
  @override
  Future<BetaUpdateSnapshot> currentStatus() async =>
      const BetaUpdateSnapshot();
  @override
  Future<BetaUpdateSnapshot> checkForUpdates(String source) async =>
      throw StateError('No real checks in visual tests');
  @override
  Future<BetaUpdateSnapshot> downloadUpdate() async =>
      throw StateError('No real download in visual tests');
  @override
  Future<BetaUpdateSnapshot> restartAndApply() async =>
      throw StateError('No real apply in visual tests');
  @override
  Future<void> dispose() => events.close();
}
