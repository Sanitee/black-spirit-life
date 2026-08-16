import 'dart:io';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('node icon paths preserve normal, gray, and highlighted states', () {
    expect(
      bdoNodeIconAssetPath(2, active: true),
      'assets/images/node_icons/2.png',
    );
    expect(
      bdoNodeIconAssetPath(2, active: false),
      'assets/images/node_icons/gray/2.png',
    );
    expect(
      bdoNodeIconAssetPath(2, active: true, highlighted: true),
      'assets/images/node_icons/highlighted/2.png',
    );
    expect(
      bdoNodeIconAssetPath(2, active: false, highlighted: true),
      'assets/images/node_icons/highlighted/gray/2.png',
    );
    expect(() => bdoNodeIconAssetPath(16, active: true), throwsRangeError);
  });

  test('private Workerman icon set is complete and pinned', () {
    final root = Directory('assets/images/node_icons');
    final files = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.png'))
        .toList(growable: false);
    expect(files, hasLength(64));
    for (var type = 0; type <= 15; type += 1) {
      for (final active in const <bool>[false, true]) {
        for (final highlighted in const <bool>[false, true]) {
          expect(
            File(
              bdoNodeIconAssetPath(
                type,
                active: active,
                highlighted: highlighted,
              ),
            ).existsSync(),
            isTrue,
          );
        }
      }
    }
    expect(
      _sha256('assets/images/node_icons/0.png'),
      '215517d2f96177950f9980d91c8d34a98c8c974db158e5d985d38a7dc5e6e7a9',
    );
    expect(
      _sha256('assets/images/node_icons/gray/0.png'),
      '01a7835579e9738d3343638be28710f77680c1265803117b142ae47c29c074f7',
    );
    expect(
      _sha256('assets/images/node_icons/highlighted/2.png'),
      '0241ffd86cbd45979ac3fa071bc410c95ed7aa3e642bcfcbf52e136648dcd2f6',
    );
    expect(
      _sha256('assets/images/node_icons/highlighted/gray/2.png'),
      '0042a4a43b42d7268499fa09553a8b396db8ba03573b511f12f46d3d95ab664a',
    );
  });
}

String _sha256(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();
