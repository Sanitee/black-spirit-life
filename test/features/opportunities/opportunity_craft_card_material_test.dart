import 'dart:math' as math;

import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_card_reading.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_visuals.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_craft_card_material.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) =>
    (math.max(a.computeLuminance(), b.computeLuminance()) + .05) /
    (math.min(a.computeLuminance(), b.computeLuminance()) + .05);

void main() {
  for (final theme in RetainedThemeRegistry.themes) {
    for (final tone in OpportunityStockTone.values) {
      test('Broad edge coverage and readable ${theme.id} ${tone.name}', () {
        final spec = OpportunitiesVisualSpec.forAppearance(theme);
        final material = OpportunityCraftCardMaterial.forSpec(spec, tone);
        expect(
          OpportunityCraftCardMaterial.forSpec(spec, tone),
          same(material),
        );
        expect(material.bay.a, 1);
        expect(material.headerWash.begin, Alignment.bottomCenter);
        expect(material.headerWash.end, Alignment.topCenter);
        expect(material.headerWash.stops, [0, .48, .96]);
        expect(
          material.headerWash.colors.first.a,
          closeTo(material.light ? .12 : .24, .005),
        );
        expect(material.headerWash.colors.last.a, 0);
        for (final surface in material.readingSurfaces) {
          expect(
            contrast(
              material.badgeInk,
              Color.alphaBlend(material.badgeFill, surface),
            ),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(material.mutedInk, surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(material.lossInk, surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(spec.palette.text, surface),
            greaterThanOrEqualTo(4.5),
          );
        }
        if (tone == OpportunityStockTone.available) {
          expect(material.bay.g, greaterThan(material.bay.r));
          expect(material.bay.g, greaterThan(material.bay.b));
        } else if (tone == OpportunityStockTone.outOfStock) {
          expect(material.bay.r, greaterThan(material.bay.g));
          expect(material.bay.r, greaterThan(material.bay.b));
        } else if (tone == OpportunityStockTone.mixed) {
          expect(material.bay.r, greaterThan(material.bay.g));
          expect(material.bay.g, greaterThan(material.bay.b));
        }
      });
    }
  }
}
