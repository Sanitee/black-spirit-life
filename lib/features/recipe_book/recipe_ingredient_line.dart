import 'package:flutter/material.dart';

import '../../domain/formatting/planner_formatters.dart';
import '../../visual/visual.dart';

/// Shared open ingredient layout for recipe previews and related formulas.
class RecipeIngredientLine extends StatelessWidget {
  const RecipeIngredientLine({
    required this.icon,
    required this.name,
    required this.quantity,
    this.nameControl,
    this.controls = const [],
    this.quantityKey,
    this.semanticLabel,
    super.key,
  });

  final Widget icon;
  final String name;
  final double quantity;
  final Widget? nameControl;
  final List<Widget> controls;
  final Key? quantityKey;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel ?? '$name, ${formatQuantity(quantity)} needed',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child:
                            nameControl ??
                            Text(name, style: ItemDetailStyle.ingredient(spec)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '×${formatQuantity(quantity)}',
                        key: quantityKey,
                        style: ItemDetailStyle.meta(spec),
                      ),
                    ],
                  ),
                  if (controls.isNotEmpty)
                    Row(mainAxisSize: MainAxisSize.min, children: controls),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
