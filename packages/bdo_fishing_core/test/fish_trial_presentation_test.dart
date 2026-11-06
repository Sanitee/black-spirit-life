import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// These are source/interaction contracts, not a browser-rendered visual test.
// The Fish WebView and service must not be launched by this trial's checks.
void main() {
  final css = File('assets/fish_companion/static/app.css').readAsStringSync();
  const marker = '/* Codex all-tabs trial — tide instruments.';
  final trial = css.substring(css.indexOf(marker));
  final withoutComments = trial.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  final rules = RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(withoutComments);

  String hash(String value) => sha256.convert(utf8.encode(value)).toString();

  test('accepted Fish layout includes the approved single-well search', () {
    expect(css.split(marker), hasLength(2));
    final baseline = css
        .split(marker)
        .first
        .replaceAll('\r\n', '\n')
        .trimRight();
    expect(
      hash(baseline),
      // Reviewed correctness changes: contained zoomed dialogs and reachable
      // actions. Browser capture checks cover normal/enlarged geometry.
      'f72382c122416e3361e90e14ca94a659d29e971262c561f4cc8e472469450b9f',
    );

    // Presentation additions cannot move controls, change hit targets, clamp
    // readable text, interfere with scrolling, or restart map layout work.
    const forbiddenProperties = <String>{
      'width',
      'height',
      'min-width',
      'min-height',
      'max-width',
      'max-height',
      'display',
      'visibility',
      'position',
      'inset',
      'top',
      'right',
      'bottom',
      'left',
      'padding',
      'margin',
      'gap',
      'grid-template-columns',
      'grid-template-rows',
      'grid-template-areas',
      'flex',
      'overflow',
      'overflow-x',
      'overflow-y',
      'pointer-events',
      'touch-action',
      'z-index',
      'transform',
      'scale',
      'zoom',
      'font-size',
      'line-height',
      'content',
    };
    for (final rule in rules) {
      for (final declaration in rule.group(2)!.split(';')) {
        if (!declaration.contains(':')) continue;
        final property = declaration.split(':').first.trim();
        expect(
          forbiddenProperties,
          isNot(contains(property)),
          reason: '${rule.group(1)!.trim()}: $property',
        );
      }
    }
  });

  test(
    'HTML and JavaScript retain quiet hover with the approved names-only fish search',
    () {
      final html = File(
        'assets/fish_companion/static/index.html',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final script = File(
        'assets/fish_companion/static/app.js',
      ).readAsStringSync();
      expect(html, contains('/app.css?v=codex-depth-instruments-2'));
      expect(
        hash(
          html.replaceAll('codex-depth-instruments-2', 'codex-field-desk-1'),
        ),
        '53c8df318e9cccde0443cb062177b53d8629972758e88fed6d94df6945958c2f',
      );
      expect(
        hash(script.replaceAll('\r\n', '\n')),
        // Real-JS sale/unknown-value tests independently check the revised
        // arithmetic; this pin prevents later presentation-only drift.
        'b7d11e560c7f5a429c1428bfae8b021586cafe1bf359e924d1a6e6608eae3115',
      );
      expect(html, contains('aria-label="Hide towns and cities"'));
      expect(html, contains('before freshness'));
      expect(html, contains('Imperial delivery is not included'));
      expect(
        html,
        isNot(contains('data-page="map" title="Fishing map"')),
      );
      expect(script, contains('els.profileButton.removeAttribute("title");'));
      expect(
        script,
        contains('els.settlementToggle.setAttribute("aria-label"'),
      );
    },
  );

  test('map translucency, geography and rarity frames are not repainted', () {
    for (final rule in rules) {
      final selector = rule.group(1)!;
      expect(selector, isNot(contains('.map-world')));
      expect(selector, isNot(contains('.map-viewport')));
      expect(selector, isNot(contains('.map-stage')));
      expect(selector, isNot(contains('.map-tools')));
      expect(selector, isNot(contains('.spot-drawer')));
      expect(selector, isNot(contains('.grade-frame')));
      expect(selector, isNot(contains('.map-tile')));
      expect(selector, isNot(contains('.fishing-spot-point')));
      expect(selector, isNot(contains('.map-pin')));
      expect(rule.group(2), isNot(matches(r'(^|;)\s*opacity\s*:')));
      expect(rule.group(2), isNot(matches(r'--ui-[\w-]+\s*:')));
    }
    expect(trial, isNot(contains('url(')));
    expect(trial, isNot(contains('backdrop-filter')));
  });

  test('only short local feedback animates and reduced motion disables it', () {
    expect(trial, isNot(contains('@keyframes')));
    expect(trial, isNot(contains('infinite')));
    expect(trial, isNot(contains('will-change')));
    expect(trial, contains('@media (hover: hover) and (pointer: fine)'));
    final transitions = RegExp(r'transition:\s*([^;]+);').allMatches(trial);
    expect(transitions, hasLength(2));
    expect(
      transitions.first.group(1),
      'border-color 140ms ease,background-color 140ms ease,\n'
      '    box-shadow 140ms ease,color 140ms ease',
    );
    expect(transitions.last.group(1), 'none !important');
    expect(
      trial.trimRight(),
      endsWith(
        '@media (prefers-reduced-motion: reduce) {\n'
        '  *, *::before, *::after { transition: none !important; '
        'animation: none !important; }\n}',
      ),
    );
  });

  test(
    'selected actions and keyboard focus retain visible independent cues',
    () {
      for (final selector in <String>[
        '.nav-button.is-active',
        '#page-map .map-result.is-selected',
        '.profile-list-item.is-selected',
        '.stats-row.is-active',
        '.gear-option.is-active',
        '.profile-equipment-option.is-active',
        '.quiet-button[aria-pressed="true"]',
        '.method-button.is-active',
        '.style-option.is-active',
        '.time-mode-option.is-active',
        '.journal-view-switch button.is-active',
        '.stats-choice.is-active',
        '.profile-method-switch button.is-active',
      ]) {
        expect(trial, contains(selector));
      }
      expect(
        trial,
        contains(
          'button:focus-visible, a:focus-visible, summary:focus-visible',
        ),
      );
      expect(trial, contains('outline-color: var(--gold-soft)'));
      expect(trial, isNot(matches(r'outline\s*:\s*(none|0)')));
      expect(trial, contains(':active:not(:disabled)'));
      expect(trial, contains(':hover:not(:disabled)'));
      expect(trial, contains('var(--instrument-selected)'));
    },
  );

  test('Fish keeps its own warm material without inherited cyan controls', () {
    // Success/error/rarity data colors stay untouched. These selectors are
    // navigation, selection and input chrome, not semantic catch values.
    for (final selector in <String>[
      '.profile-form select:focus',
      '.location-suggestion.is-active',
      '.sale-quote-cell.is-selected',
      '.sale-total-cell.is-selected',
      '.time-picker-hand i',
      '.check-row input:checked + .check-box',
      '.drop-zone.is-over',
    ]) {
      expect(trial, contains(selector));
    }
    expect(trial, isNot(contains('108,183,200')));
    expect(trial, isNot(contains('82,214,202')));
    expect(trial, isNot(contains('prefers-color-scheme')));
    expect(trial, isNot(contains('Appearance')));
  });

  test(
    'opaque reading surfaces and primary actions preserve text contrast',
    () {
      const lightText = 0xf1e8d8;
      const mutedText = 0xb9abb1;
      for (final background in <int>[0x141218, 0x25212a, 0x49333f, 0x62444d]) {
        expect(_contrast(lightText, background), greaterThanOrEqualTo(4.5));
      }
      for (final background in <int>[0x141218, 0x25212a, 0x49333f]) {
        expect(_contrast(mutedText, background), greaterThanOrEqualTo(4.5));
      }
      for (final background in <int>[0xead1aa, 0xc8a16c, 0xb68d58]) {
        expect(_contrast(0x231b23, background), greaterThanOrEqualTo(4.5));
      }
    },
  );
}

double _contrast(int foreground, int background) {
  double luminance(int color) {
    double channel(int shift) {
      final value = ((color >> shift) & 0xff) / 255;
      return value <= .04045
          ? value / 12.92
          : math.pow((value + .055) / 1.055, 2.4).toDouble();
    }

    return .2126 * channel(16) + .7152 * channel(8) + .0722 * channel(0);
  }

  final first = luminance(foreground);
  final second = luminance(background);
  return (math.max(first, second) + .05) / (math.min(first, second) + .05);
}
