import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_map_core/src/widgets/house_use_icon.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

bool _fontsLoaded = false;

/// Optional evidence only. Tests still run without capture settings or Windows.
Future<void> loadMapMenuCaptureFonts() async {
  if (_fontsLoaded ||
      !Platform.isWindows ||
      Platform.environment['MAP_MENU_CAPTURE_DIR'] == null) {
    return;
  }
  final windowsRoot = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var flutterRoot = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${flutterRoot.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    final parent = flutterRoot.parent;
    if (parent.path == flutterRoot.path) {
      throw StateError('Flutter fonts not found.');
    }
    flutterRoot = parent;
  }
  final fontGroups = <String, List<String>>{
    'Segoe UI': [
      for (final file in ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf'])
        '$windowsRoot/Fonts/$file',
    ],
    'Georgia': [
      for (final file in ['georgia.ttf', 'georgiab.ttf'])
        '$windowsRoot/Fonts/$file',
    ],
    'Roboto': [
      for (final file in ['roboto-regular.ttf', 'roboto-bold.ttf'])
        '${flutterRoot.path}/bin/cache/artifacts/material_fonts/$file',
    ],
    'MaterialIcons': [
      '${flutterRoot.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
  };
  for (final entry in fontGroups.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
  _fontsLoaded = true;
}

/// Capture a caller-provided RepaintBoundary, after local artwork is decoded.
Future<void> captureMapMenu(
  WidgetTester tester, {
  required Finder boundary,
  required String name,
}) async {
  final root = Platform.environment['MAP_MENU_CAPTURE_DIR'];
  if (root == null) return;
  for (final element in find.byType(HouseUseIcon).evaluate()) {
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(HouseUseIcon.asset, package: 'bdo_map_core'),
        element,
      ),
    );
  }
  for (final element in find.byType(Image).evaluate()) {
    final provider = (element.widget as Image).image;
    if (provider is AssetImage) {
      await tester.runAsync(() => precacheImage(provider, element));
    }
  }
  await tester.pumpAndSettle();
  final render = tester.renderObject<RenderRepaintBoundary>(boundary);
  await tester.runAsync(() async {
    final capture = await render.toImage(pixelRatio: 1);
    try {
      final bytes = (await capture.toByteData(format: ui.ImageByteFormat.png))!;
      await File('$root${Platform.pathSeparator}$name.png').writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      capture.dispose();
    }
  });
}
