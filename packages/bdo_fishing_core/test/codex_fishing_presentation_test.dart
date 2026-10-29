import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final html = File(
    'assets/fish_companion/static/index.html',
  ).readAsStringSync();
  final css = File('assets/fish_companion/static/app.css').readAsStringSync();

  String contractHash(RegExp pattern, String Function(RegExpMatch) value) {
    final values = pattern.allMatches(html).map(value).toList()..sort();
    return sha256.convert(utf8.encode(values.join('\n'))).toString();
  }

  test('all 185 accepted DOM identities survive the presentation rewrite', () {
    final ids = RegExp(r'\bid="([^"]+)"');
    expect(ids.allMatches(html), hasLength(185));
    expect(
      contractHash(ids, (match) => match.group(1)!),
      '7255957b731843f0ad96ee970c531eab2f079affddf95b38b2dd62f0745e680d',
    );
  });

  test('every navigation, gear and workflow action binding is retained', () {
    final actions = RegExp(
      r'\b(data-(?:go|page|method|method-switch|equipment|style|time-mode|journal-mode|stats-style|profile-method))="([^"]+)"',
    );
    expect(actions.allMatches(html), hasLength(31));
    expect(
      contractHash(actions, (match) => '${match.group(1)}=${match.group(2)}'),
      '7263007a963d4016bab1ce1068ebf116e8ab3f7a98c652372f8e5f318fbb58bd',
    );
  });

  test(
    'all panels hide scrollbar chrome while retaining overflow scrolling',
    () {
      final desk = css.substring(css.indexOf('/* Beta by Codex — field desk.'));
      // Class selectors such as .content-page previously beat the universal
      // rule, and standard scrollbar-width takes precedence over WebKit styling.
      expect(desk, contains('* { scrollbar-width: none !important; }'));
      expect(
        desk,
        contains('*::-webkit-scrollbar { display: none !important; }'),
      );
      final importantWidths = RegExp(
        r'scrollbar-width\s*:\s*([^;{}]+)!important',
      ).allMatches(css);
      expect(importantWidths, isNotEmpty);
      for (final declaration in importantWidths) {
        expect(declaration.group(1)!.trim(), 'none');
      }
      expect(css, contains('.content-page { overflow: auto;'));
      expect(css, contains('.sale-offers { overflow-x: auto;'));
    },
  );

  test(
    'desk material has no ongoing blur or fog and retains reduced motion',
    () {
      final desk = css.substring(css.indexOf('/* Beta by Codex — field desk.'));
      expect(desk, contains('backdrop-filter: none !important'));
      expect(desk, contains('animation: none; will-change: auto'));
      expect(desk, contains('.fishing-spot-point::before { animation: none;'));
      expect(
        desk,
        contains('.map-pin::before, .map-pin::after { animation: none;'),
      );
      expect(desk, contains('prefers-reduced-motion: reduce'));
      expect(desk, isNot(contains('infinite')));
      expect(desk, contains('zoom: 1'));
      expect(desk, contains('"filters entries"'));
      expect(html, contains('<details class="atlas-filter-details">'));
      expect(html, contains('https://fishystuff.fish/map/'));
    },
  );
}
