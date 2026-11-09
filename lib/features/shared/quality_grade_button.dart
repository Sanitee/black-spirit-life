import 'package:flutter/material.dart';

import '../../visual/components/app_tooltip.dart';
import '../../visual/visual.dart';

/// Shared quality selector. The same grade keeps the same colour in every host.
class QualityGradeButton extends StatelessWidget {
  const QualityGradeButton({
    required this.label,
    required this.grade,
    required this.normalIsBlueFamily,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  static double sizeFor(BuildContext context) =>
      context.visualTheme.usesDenseSplitLayout ? 26 : 24;

  final String label;
  final String grade;
  final bool normalIsBlueFamily;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final (fill, restingBorder) = _gradeColors(
      grade,
      normalIsBlueFamily: normalIsBlueFamily,
    );
    final ring = ledger ? const Color(0xFF7C5B24) : spec.palette.text;
    final size = sizeFor(context);

    return AppTooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label quality',
        child: InkWell(
          onTap: onPressed,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(3),
          ),
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: selected ? Border.all(color: ring, width: 2) : null,
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: restingBorder),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

(Color, Color) _gradeColors(String grade, {required bool normalIsBlueFamily}) =>
    switch (grade) {
      'high' => (const Color(0xAA6FC17A), const Color(0xB9A9E890)),
      'special' => (const Color(0xAA558FD5), const Color(0xB9A8C8FF)),
      'blue' => (const Color(0xAA4D73D2), const Color(0xB9BBCDFF)),
      _ when normalIsBlueFamily => (
        const Color(0xAA4FAF72),
        const Color(0xB9A9E890),
      ),
      _ => (const Color(0xAA909090), const Color(0xB9CBCBCB)),
    };
