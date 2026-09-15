import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/src/domain/matchlock_advice.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('example counts and conditional advice stay separate from DPS', () {
    expect(matchlockCrystalAdvice.map((e) => (e.id, e.count)), [
      ('15672', 2),
      ('15257', 1),
      ('15256', 2),
      ('15690', 2),
      ('15736', 1),
    ]);
    expect(matchlockCrystalAdvice.first.benefit, contains('with two'));
    expect(matchlockCrystalAdvice.first.notes.join(' '), contains('not 22%'));
    expect(matchlockCrystalAdvice[1].notes.join(' '), contains('Skip this'));
    expect(matchlockCrystalAdvice[3].notes.join(' '), contains('separate'));
    final guide = matchlockDamageSections.expand((s) => s.lines).join('\n');
    expect(guide, contains('not a build for every class'));
    expect(guide, contains('We haven’t verified a fix'));
    expect(guide, contains('no longer gives Attack Speed or Critical Hit'));
    expect(guide, isNot(contains('100%')));
    expect(guide, isNot(contains('700')));
    expect(
      matchlockAdviceSources.map((s) => s.url).toSet().length,
      matchlockAdviceSources.length,
    );
    for (final source in [
      ...matchlockAdviceSources,
      ...matchlockCrystalAdvice.expand((e) => e.sources),
    ]) {
      expect(Uri.parse(source.url).scheme, 'https');
      expect(source.label, isNotEmpty);
    }
  });

  test('every crystal uses decoded original game artwork unchanged', () async {
    final rootCatalog =
        jsonDecode(File('../../assets/data/app-data.json').readAsStringSync())
            as Map<String, dynamic>;
    final originals = rootCatalog['processing']['itemIcons'] as Map;
    final manifest =
        jsonDecode(
              await rootBundle.loadString(
                'packages/bdo_gathering_companion/assets/icons/items/matchlock-advice-provenance.json',
              ),
            )
            as Map<String, dynamic>;
    final entries = manifest['entries'] as List;
    expect(entries.length, matchlockCrystalAdvice.length);
    for (final item in matchlockCrystalAdvice) {
      final entry = entries.singleWhere((e) => e['id'].toString() == item.id);
      final data = await rootBundle.load(
        'packages/bdo_gathering_companion/${item.icon}',
      );
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      expect(bytes.length, entry['byteLength']);
      expect(sha256.convert(bytes).toString(), entry['sha256']);
      expect(
        bytes,
        base64Decode((originals[item.name] as String).split(',')[1]),
      );
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThanOrEqualTo(32));
      expect(frame.image.height, greaterThanOrEqualTo(32));
      frame.image.dispose();
      codec.dispose();
    }
  });
}
