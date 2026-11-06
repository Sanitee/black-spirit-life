import 'dart:io';

import 'package:flutter/services.dart';

/// Opt-in headless evidence only. Does not launch the app or inspect user data.
Future<void> loadNativePreviewFonts() async {
  if (!Platform.isWindows) {
    throw UnsupportedError('These native previews require Windows fonts.');
  }
  final windows = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var sdk = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${sdk.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    if (sdk.parent.path == sdk.path) {
      throw StateError('Flutter material fonts were not found.');
    }
    sdk = sdk.parent;
  }
  final material = '${sdk.path}/bin/cache/artifacts/material_fonts';
  for (final family in <String, List<String>>{
    'Segoe UI': [
      for (final name in [
        'segoeui.ttf',
        'seguisb.ttf',
        'segoeuib.ttf',
        'segoeuii.ttf',
      ])
        '$windows/Fonts/$name',
    ],
    'Georgia': [
      for (final name in ['georgia.ttf', 'georgiab.ttf', 'georgiai.ttf'])
        '$windows/Fonts/$name',
    ],
    'Roboto': ['$material/roboto-regular.ttf', '$material/roboto-bold.ttf'],
    'MaterialIcons': ['$material/materialicons-regular.otf'],
  }.entries) {
    final loader = FontLoader(family.key);
    for (final path in family.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
