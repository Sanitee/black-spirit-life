import 'package:bdo_map_core/src/widgets/resource_map_atlas_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'details sit next to the clicked point, flip and clamp by actual size',
    () {
      for (final viewport in [const Size(1200, 752), const Size(790, 500)]) {
        for (final panel in [
          const Size(320, 220),
          Size(320, viewport.height - 24),
        ]) {
          for (final anchor in [
            const Offset(100, 170),
            Offset(viewport.width / 2, viewport.height / 2),
            Offset(viewport.width - 40, viewport.height - 30),
            Offset(viewport.width - 10, 10),
          ]) {
            final placement = ResourceMapDetailsPlacement(
              anchor: anchor,
              width: panel.width,
            );
            final position = placement.getPositionForChild(viewport, panel);
            final rect = position & panel;
            expect(rect.left, greaterThanOrEqualTo(12));
            expect(rect.top, greaterThanOrEqualTo(12));
            expect(rect.right, lessThanOrEqualTo(viewport.width - 12));
            expect(rect.bottom, lessThanOrEqualTo(viewport.height - 12));
            final rightFits =
                anchor.dx + 32 + panel.width <= viewport.width - 12;
            if (rightFits) {
              expect(rect.left, anchor.dx + 32);
            } else if (anchor.dx - 32 - panel.width >= 12) {
              expect(rect.right, anchor.dx - 32);
            }
          }
        }
      }
    },
  );

  test('panel constraints shrink to small viewports without fixing height', () {
    const placement = ResourceMapDetailsPlacement(
      anchor: Offset(150, 200),
      width: 380,
    );
    final limits = placement.getConstraintsForChild(
      const BoxConstraints.tightFor(width: 300, height: 400),
    );
    expect(limits.minWidth, 276);
    expect(limits.maxWidth, 276);
    expect(limits.minHeight, 0);
    expect(limits.maxHeight, 376);
    expect(
      placement.shouldRelayout(
        const ResourceMapDetailsPlacement(anchor: Offset(160, 200), width: 380),
      ),
      isTrue,
    );
  });
}
