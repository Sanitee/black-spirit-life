import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/domain/gathering_preparation.dart';
import 'package:bdo_gathering_companion/src/ui/buff_picker.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  late Map<String, dynamic> raw;
  Buff item(int id) => catalog.buffs.singleWhere((b) => b.id == 'buff-$id');
  Map<String, dynamic> rawItem(int id) =>
      objectList(raw['buffs']).singleWhere((b) => b['itemId'] == id);

  setUpAll(() async {
    catalog = await Catalog.load();
    raw = objectMap(
      jsonDecode(
        await rootBundle.loadString(
          'packages/bdo_gathering_companion/assets/data/buffs.json',
        ),
      ),
    );
  });

  test(
    'Lethal Destruction retains the audited separate two-percent effect',
    () {
      final buff = item(1181);
      expect(buff.name, 'Elixir of Lethal Destruction');
      expect(buff.category, 'elixirs');
      expect(buff.grade, 2);
      expect(buff.duration, 15);
      expect(buff.effects, {'specialAttackDamagePct': 2});
      expect(buff.recommendedFor, ['hunting']);
      expect(buff.referenceOnly, isFalse);
      expect(
        catalog.statLabel('specialAttackDamagePct'),
        'All special attack extra damage',
      );
      expect(catalog.statUnit('specialAttackDamagePct'), '%');
      expect(effectText(catalog, 'specialAttackDamagePct', 2), '+2%');
      final evidence = objectList(rawItem(1181)['clientEffectEvidence']).single;
      expect(evidence['buff'], 55971);
      expect(evidence['buffGroup'], 6943);
      expect(evidence['buffCategory'], 2);
      expect(evidence['durationMs'], 900000);
      expect(evidence['cooldownMs'], 1000);
      expect(
        buff.sourceUrls,
        contains('https://www.youtube.com/watch?v=KnfbewYBxhE&t=858s'),
      );
    },
  );

  test('ordinary elixir stacking remains symmetric and family-specific', () {
    final buff = item(1181);
    for (final draught in catalog.buffs.where(
      (b) => b.category == 'draughts',
    )) {
      expect(buff.conflictsWith(draught), isTrue, reason: draught.name);
      expect(draught.conflictsWith(buff), isTrue, reason: draught.name);
    }
    for (final id in [689, 697, 699, 763, 750, 1159]) {
      expect(buff.conflictsWith(item(id)), isFalse, reason: item(id).name);
      expect(item(id).conflictsWith(buff), isFalse, reason: item(id).name);
    }
    // Both client1180 and client1183 share1181's audited buffGroup6943.
    for (final id in [1180, 1183]) {
      final sameFamily = Buff({...rawItem(1181), 'id': 'buff-$id'});
      expect(buff.conflictsWith(sameFamily), isTrue);
      expect(sameFamily.conflictsWith(buff), isTrue);
    }
    expect(
      catalog.sumBuffs(['buff-1181', 'buff-1181', 'buff-697', 'buff-699']),
      {
        'specialAttackDamagePct': 2,
        'backAttackDamagePct': 15,
        'criticalHitDamagePct': 15,
      },
    );
  });

  test('special attack bonus does not become a gathering efficiency input', () {
    final before = GatheringPreparation();
    final after = before.withBuffIds({'buff-1181'}, catalog);
    expect(after.activeBuffIds(catalog), {'buff-1181'});
    expect(after.buffTotals(catalog), {'specialAttackDamagePct': 2});
    expect(
      after.effectiveSettings(catalog).toJson(),
      before.effectiveSettings(catalog).toJson(),
    );
    expect(after.baseSettings.toJson(), before.baseSettings.toJson());
  });

  test(
    'Rough Labor gains matchlock recommendation without changing values',
    () {
      final labor = item(1159);
      expect(labor.recommendedFor, ['gathering', 'hunting', 'sniper']);
      expect(labor.effects, {'gatheringItemDropPct': 5});
      expect(labor.duration, 15);
      expect(labor.grade, 2);
      expect(labor.exclusiveGroup, 'elixir-labor');
      expect(labor.conflictsWithGroups, ['draught']);
      expect(labor.notes, contains('Constantly consumes MP/WP/SP.'));
      expect(labor.conflictsWith(item(1156)), isTrue);
      expect(
        labor.sourceUrls,
        contains('https://www.youtube.com/watch?v=KnfbewYBxhE&t=858s'),
      );
    },
  );

  test('existing starter presets do not become an unsolicited full setup', () {
    final matchlock = catalog.presets.singleWhere(
      (p) => p['id'] == 'hunting-simple',
    );
    expect(strings(matchlock['buffIds']), [
      'buff-9691',
      'buff-750',
      'buff-689',
      'buff-763',
      'buff-721092',
    ]);
    final sniper = catalog.presets.singleWhere(
      (p) => p['id'] == 'sniper-simple',
    );
    expect(strings(sniper['buffIds']), [
      'buff-9301',
      'buff-1159',
      'buff-750',
      'buff-689',
      'buff-691',
      'buff-721092',
    ]);
    for (final preset in catalog.presets) {
      expect(strings(preset['buffIds']), isNot(contains('buff-1181')));
    }
    expect(GatheringPreparation().buffIds, isEmpty);
    expect(
      objectMap(raw['itemGradeProvenance'])['verifiedCount'],
      catalog.buffs.length,
    );
  });

  test(
    'Lethal Destruction uses unchanged original44-pixel game artwork',
    () async {
      final buff = item(1181);
      final provenance = objectMap(rawItem(1181)['provenance']);
      expect(provenance['clientDate'], '2026-09-10');
      expect(
        provenance['originalIcon'],
        'New_Icon/03_ETC/08_Potion/00001183.dds',
      );
      expect(buff.icon, 'assets/icons/buffs/1181.webp');
      final data = await rootBundle.load(
        'packages/bdo_gathering_companion/${buff.icon}',
      );
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      expect(bytes.length, 932);
      expect(
        sha256.convert(bytes).toString(),
        'ae8f9357df71ee7c40390f5ba668c30d31ac903de6938ed22940b0b0da5482fa',
      );
      expect(provenance['iconByteLength'], bytes.length);
      expect(provenance['iconSha256'], sha256.convert(bytes).toString());
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 44);
      expect(frame.image.height, 44);
      frame.image.dispose();
      codec.dispose();
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'real picker selects and pins the percent effect at ${scale}x',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? selected;
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: BuffPicker(
                  catalog: catalog,
                  activity: 'hunting',
                  selected: const {},
                  onToggle: (buff) => selected = buff.id,
                  onPreset: (_) => fail('No preset should be selected.'),
                  onClear: () => fail('No selection should be cleared.'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final icon = find.byKey(const ValueKey('buff-icon-buff-1181'));
        await tester.ensureVisible(icon);
        await tester.pumpAndSettle();
        await tester.tap(icon);
        await tester.pumpAndSettle();
        expect(selected, 'buff-1181');
        await tester.tap(
          icon,
          buttons: kSecondaryMouseButton,
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        final pinned = find.byKey(const ValueKey('buff-pinned-card-buff-1181'));
        expect(pinned, findsOneWidget);
        expect(
          find.descendant(
            of: pinned,
            matching: find.text('All special attack extra damage'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: pinned, matching: find.text('+2%')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: pinned, matching: find.text('Duration  15 min')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.descendant(of: pinned, matching: find.text('Close')),
        );
        await tester.pumpAndSettle();
        expect(pinned, findsNothing);
      },
    );
  }
}
