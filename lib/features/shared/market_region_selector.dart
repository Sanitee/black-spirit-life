import 'package:flutter/material.dart';

import '../../visual/foundations/theme_spec.dart';

/// Content-sized NA/EU segments sharing one theme-coloured pill.
class MarketRegionSelector extends StatelessWidget {
  const MarketRegionSelector({
    required this.region,
    required this.onChanged,
    super.key,
  });

  final String region;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final palette = spec.palette;
    return Semantics(
      container: true,
      label: 'Marketplace region',
      child: Material(
        color: palette.surfaceInset,
        shape: StadiumBorder(side: BorderSide(color: palette.trim)),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final value in const ['na', 'eu'])
                Semantics(
                  selected: region == value,
                  child: TextButton(
                    key: ValueKey('market-region:$value'),
                    onPressed: onChanged == null
                        ? null
                        : () => onChanged!(value),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(36, 32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: region == value
                          ? palette.text
                          : palette.textMuted,
                      disabledForegroundColor: palette.textMuted,
                      backgroundColor: region == value
                          ? palette.primary.withValues(alpha: .22)
                          : Colors.transparent,
                      shape: const StadiumBorder(),
                      textStyle: spec.typography.button.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(value.toUpperCase()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
