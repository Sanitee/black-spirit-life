import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';
import '../../shared/overlays/anchored_popover.dart';
import '../../visual/visual.dart';
import '../shared/mode_item_icon.dart';
import 'recipe_book_controller.dart';
import 'recipe_book_item_info.dart';
import 'recipe_book_keys.dart';

class RecipeBookItemIcon extends StatefulWidget {
  const RecipeBookItemIcon({
    required this.controller,
    required this.name,
    required this.size,
    required this.anchorId,
    this.mode,
    super.key,
  });

  final RecipeBookController controller;
  final String name;
  final double size;
  final String anchorId;
  final CraftMode? mode;

  @override
  State<RecipeBookItemIcon> createState() => _RecipeBookItemIconState();
}

class _RecipeBookItemIconState extends State<RecipeBookItemIcon> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'RecipeBookItemIcon(${widget.anchorId}:${widget.name})',
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final name = widget.name;
    final anchorId = widget.anchorId;
    final itemMode = widget.mode ?? controller.modeController.mode;
    final itemModeController = controller.modeController.owner.modes[itemMode]!;
    final icon = ModeItemIcon(
      controller: itemModeController,
      catalogRepository: controller.catalogRepository,
      name: name,
      size: widget.size,
    );
    final info = controller.itemInfoFor(name, mode: itemMode);
    if (info == null || !info.hasBody) return icon;
    final spec = context.visualTheme;
    final panelWidth = (MediaQuery.sizeOf(context).width - 40)
        .clamp(340.0, 400.0)
        .toDouble();
    return AnchoredPopover(
      overlayId: 'recipe-book-item-info:$anchorId:$name',
      preferredWidth: panelWidth,
      maximumHeight: 620,
      alignEnd: false,
      placement: AnchoredPopoverPlacement.beside,
      consumeOutsideTap: true,
      anchorBuilder: (context, toggle, isShowing) => Semantics(
        button: true,
        label: isShowing
            ? 'Close pinned information for $name'
            : 'Pin information for $name',
        child: FocusableActionDetector(
          focusNode: _focusNode,
          mouseCursor: SystemMouseCursors.click,
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                toggle();
                return null;
              },
            ),
          },
          child: GestureDetector(
            key: RecipeBookKeys.itemInfoAnchor(name, anchorId),
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _focusNode.requestFocus(),
            onTap: toggle,
            child: TooltipVisibility(
              visible: !isShowing,
              child: Tooltip(
                waitDuration: const Duration(milliseconds: 350),
                showDuration: const Duration(seconds: 12),
                exitDuration: const Duration(milliseconds: 300),
                preferBelow: false,
                ignorePointer: false,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: EdgeInsets.zero,
                richMessage: WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: _RecipeBookItemInfoPanel(
                    key: RecipeBookKeys.itemInfo(name),
                    controller: controller,
                    mode: itemMode,
                    name: name,
                    info: info,
                    maxWidth: panelWidth,
                    spec: spec,
                  ),
                ),
                child: icon,
              ),
            ),
          ),
        ),
      ),
      popoverBuilder: (context, close) => _RecipeBookItemInfoPanel(
        key: RecipeBookKeys.pinnedItemInfo(name, anchorId),
        controller: controller,
        mode: itemMode,
        name: name,
        info: info,
        maxWidth: panelWidth,
        spec: spec,
        onClose: close,
        closeKey: RecipeBookKeys.closePinnedItemInfo(name, anchorId),
      ),
    );
  }
}

class _RecipeBookItemInfoPanel extends StatelessWidget {
  const _RecipeBookItemInfoPanel({
    required this.controller,
    required this.mode,
    required this.name,
    required this.info,
    required this.maxWidth,
    required this.spec,
    this.onClose,
    this.closeKey,
    super.key,
  });

  final RecipeBookController controller;
  final CraftMode mode;
  final String name;
  final RecipeBookItemInfo info;
  final double maxWidth;
  final ThemeSpec spec;
  final VoidCallback? onClose;
  final Key? closeKey;

  @override
  Widget build(BuildContext context) {
    final heading = spec.typography.section.copyWith(
      fontSize: 17,
      color: spec.palette.text,
      height: 1.1,
    );
    final meta = spec.typography.meta.copyWith(
      color: spec.palette.textMuted,
      fontWeight: FontWeight.w700,
      letterSpacing: .2,
    );
    final body = spec.typography.body.copyWith(
      color: spec.palette.text,
      fontSize: 12.5,
      height: 1.3,
    );
    final accent = body.copyWith(
      color: spec.palette.warning,
      fontWeight: FontWeight.w700,
    );
    final maxHeight = (MediaQuery.sizeOf(context).height - 64)
        .clamp(220.0, 620.0)
        .toDouble();
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      child: AppSurface(
        role: AppSurfaceRole.tooltip,
        tone: AppSurfaceTone.info,
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        child: ScrollConfiguration(
          behavior: const _RecipeBookItemInfoScrollBehavior(),
          child: SingleChildScrollView(
            primary: false,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.only(right: 7),
            child: DefaultTextStyle(
              style: body,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      ModeItemIcon(
                        controller:
                            controller.modeController.owner.modes[mode]!,
                        catalogRepository: controller.catalogRepository,
                        name: name,
                        size: 36,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AnchoredPopoverDragRegion(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(info.kind, style: meta, maxLines: 1),
                              const SizedBox(height: 3),
                              Text(info.title, style: heading, maxLines: 2),
                            ],
                          ),
                        ),
                      ),
                      if (onClose != null) ...<Widget>[
                        const SizedBox(width: 8),
                        AppButton(
                          key: closeKey,
                          role: AppButtonRole.optionPill,
                          minimumSize: const Size.square(26),
                          padding: EdgeInsets.zero,
                          semanticLabel: 'Close $name information',
                          tooltip: 'Close information',
                          onPressed: onClose,
                          child: const AppVectorGlyph('close', size: 9),
                        ),
                      ],
                    ],
                  ),
                  if (info.summary.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    _InfoSectionHeading(title: 'Description', spec: spec),
                    const SizedBox(height: 5),
                    Text(info.summary, style: body),
                  ],
                  if (info.effects.isNotEmpty)
                    _InfoSection(
                      title: info.effectsTitle,
                      values: info.effects,
                      style: accent,
                    ),
                  if (info.acquisitionFormulas.isNotEmpty)
                    _FormulaSection(
                      controller: controller,
                      mode: mode,
                      title: 'Recipe & materials',
                      formulas: info.acquisitionFormulas,
                      style: body,
                    ),
                  if (info.acquisitionNotes.isNotEmpty)
                    _InfoSection(
                      title: 'How to Obtain',
                      values: info.acquisitionNotes,
                      style: body,
                    ),
                  if (info.uses.isNotEmpty || info.craftUses.isNotEmpty)
                    _UsedForSection(
                      controller: controller,
                      mode: mode,
                      values: info.uses,
                      craftUses: info.craftUses,
                      style: body,
                    ),
                  if (info.example?.trim().isNotEmpty ?? false)
                    _InfoSection(
                      title: 'Example',
                      values: <String>[info.example!.trim()],
                      style: body,
                    ),
                  if (info.notes.isNotEmpty)
                    _InfoSection(
                      title: 'Notes',
                      values: info.notes,
                      style: body,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecipeBookItemInfoScrollBehavior extends AppScrollBehavior {
  const _RecipeBookItemInfoScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

class _FormulaSection extends StatelessWidget {
  const _FormulaSection({
    required this.controller,
    required this.mode,
    required this.title,
    required this.formulas,
    required this.style,
  });

  final RecipeBookController controller;
  final CraftMode mode;
  final String title;
  final List<RecipeBookFormula> formulas;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final routeIds = formulas
        .map((formula) => (formula.routeId ?? formula.routeLabel ?? '').trim())
        .where((value) => value.isNotEmpty)
        .map((value) => value.toLowerCase())
        .toSet();
    final showRouteLabel = routeIds.length > 1;
    final showBatchLabel = formulas.any(
      (formula) => formula.batchMultiplier != 1,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _InfoSectionHeading(title: title, spec: spec),
          const SizedBox(height: 7),
          for (var index = 0; index < formulas.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(height: 8),
            _FormulaCard(
              controller: controller,
              mode: mode,
              formula: formulas[index],
              style: style,
              showRouteLabel: showRouteLabel,
              showBatchLabel: showBatchLabel,
            ),
          ],
        ],
      ),
    );
  }
}

class _FormulaCard extends StatelessWidget {
  const _FormulaCard({
    required this.controller,
    required this.mode,
    required this.formula,
    required this.style,
    required this.showRouteLabel,
    required this.showBatchLabel,
  });

  final RecipeBookController controller;
  final CraftMode mode;
  final RecipeBookFormula formula;
  final TextStyle style;
  final bool showRouteLabel;
  final bool showBatchLabel;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final routeLabel = formula.routeLabel?.trim() ?? '';
    final tags = <String>[
      if (showRouteLabel && routeLabel.isNotEmpty) routeLabel,
      if (showBatchLabel) '${formula.batchMultiplier}× batch',
    ];
    final meta = spec.typography.meta.copyWith(
      color: spec.palette.textMuted,
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    final output = _formulaOutputLabel(formula);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        key: RecipeBookKeys.itemInfoFormula(
          formula.outputName,
          formula.variantId,
          formula.batchMultiplier,
        ),
        padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
        decoration: BoxDecoration(
          color: spec.palette.surfaceInset.withAlpha(150),
          border: Border.all(color: spec.palette.trim.withAlpha(105)),
          borderRadius: BorderRadius.circular(spec.geometry.cardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              label: <String>[formula.method, ...tags, output].join(', '),
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      formula.method,
                      style: style.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (tags.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(tags.join(' · '), style: meta),
                    ],
                    const SizedBox(height: 3),
                    Text(output, style: meta),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Container(height: 1, color: spec.palette.trim.withAlpha(65)),
            const SizedBox(height: 3),
            for (var index = 0; index < formula.ingredients.length; index++)
              _FormulaMaterialRow(
                controller: controller,
                mode: mode,
                formula: formula,
                ingredient: formula.ingredients[index],
                style: style,
                topSpacing: index == 0 ? 3 : 6,
              ),
          ],
        ),
      ),
    );
  }
}

class _FormulaMaterialRow extends StatelessWidget {
  const _FormulaMaterialRow({
    required this.controller,
    required this.mode,
    required this.formula,
    required this.ingredient,
    required this.style,
    required this.topSpacing,
  });

  final RecipeBookController controller;
  final CraftMode mode;
  final RecipeBookFormula formula;
  final Ingredient ingredient;
  final TextStyle style;
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final alternatives = _formulaAlternatives(ingredient);
    final quantity = _displayQuantity(ingredient.quantity);
    final semanticLabel = <String>[
      '$quantity ${ingredient.name}',
      for (final alternative in alternatives)
        'or ${_displayQuantity(alternative.quantity)} ${alternative.name}',
    ].join(', ');
    final alternateStyle = style.copyWith(
      color: spec.palette.textMuted,
      fontSize: (style.fontSize ?? 12.5) - 1,
      height: 1.2,
    );
    return Padding(
      padding: EdgeInsets.only(top: topSpacing),
      child: Semantics(
        container: true,
        label: semanticLabel,
        child: ExcludeSemantics(
          child: Row(
            key: RecipeBookKeys.itemInfoMaterial(
              formula.outputName,
              formula.variantId,
              ingredient.name,
            ),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ModeItemIcon(
                controller: controller.modeController.owner.modes[mode]!,
                catalogRepository: controller.catalogRepository,
                name: ingredient.name,
                size: 24,
                searchAcrossModes: true,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      ingredient.name,
                      style: style.copyWith(fontWeight: FontWeight.w700),
                    ),
                    for (final alternative in alternatives)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          'or ${_displayQuantity(alternative.quantity)} '
                          '${alternative.name}',
                          style: alternateStyle,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '×$quantity',
                style: style.copyWith(
                  color: spec.palette.warning,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _FormulaAlternative {
  const _FormulaAlternative({required this.name, required this.quantity});

  final String name;
  final double quantity;
}

List<_FormulaAlternative> _formulaAlternatives(Ingredient ingredient) {
  final candidates = <String>[
    ...ingredient.options,
    ...ingredient.substituteRatios.keys,
  ];
  final seen = <String>{ingredient.name.trim().toLowerCase()};
  final result = <_FormulaAlternative>[];
  for (final candidate in candidates) {
    final name = candidate.trim();
    final identity = name.toLowerCase();
    if (name.isEmpty || !seen.add(identity)) continue;
    var ratio = 1.0;
    for (final entry in ingredient.substituteRatios.entries) {
      if (entry.key.trim().toLowerCase() == identity && entry.value > 0) {
        ratio = entry.value;
        break;
      }
    }
    result.add(
      _FormulaAlternative(name: name, quantity: ingredient.quantity * ratio),
    );
  }
  return result;
}

String _formulaOutputLabel(RecipeBookFormula formula) {
  final outputLabel = formula.outputEstimated ? 'Estimated output' : 'Output';
  final minimum = formula.outputMinimum;
  final maximum = formula.outputMaximum;
  if (minimum != null && maximum != null) {
    if (minimum == maximum) {
      return '$outputLabel ×${_displayQuantity(minimum)}';
    }
    return '$outputLabel ×${_displayQuantity(minimum)}–'
        '${_displayQuantity(maximum)}';
  }
  final prefix =
      !formula.outputEstimated && formula.type.trim().toLowerCase() == 'alchemy'
      ? 'Base output'
      : outputLabel;
  return '$prefix ×${_displayQuantity(formula.baseOutput)}';
}

String _displayQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

class _UsedForSection extends StatelessWidget {
  const _UsedForSection({
    required this.controller,
    required this.mode,
    required this.values,
    required this.craftUses,
    required this.style,
  });

  final RecipeBookController controller;
  final CraftMode mode;
  final List<String> values;
  final List<RecipeBookCraftUse> craftUses;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _InfoSectionHeading(title: 'Used For', spec: spec),
          const SizedBox(height: 5),
          for (final value in values) _InfoBullet(value: value, style: style),
          for (var index = 0; index < craftUses.length; index++)
            _CraftUseEntry(
              controller: controller,
              mode: mode,
              craftUse: craftUses[index],
              style: style,
              topSpacing: index == 0 && values.isEmpty ? 0 : 5,
            ),
        ],
      ),
    );
  }
}

class _CraftUseEntry extends StatelessWidget {
  const _CraftUseEntry({
    required this.controller,
    required this.mode,
    required this.craftUse,
    required this.style,
    required this.topSpacing,
  });

  final RecipeBookController controller;
  final CraftMode mode;
  final RecipeBookCraftUse craftUse;
  final TextStyle style;
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final outputInfo = controller.itemInfoFor(craftUse.output, mode: mode);
    final description = outputInfo == null
        ? ''
        : recipeBookUseDescription(outputInfo);
    final example = outputInfo?.example?.trim() ?? '';
    final contextStyle = style.copyWith(
      color: spec.palette.textMuted,
      fontSize: (style.fontSize ?? 12.5) - .5,
    );
    final routeIds = craftUse.formulas
        .map((formula) => (formula.routeId ?? formula.routeLabel ?? '').trim())
        .where((value) => value.isNotEmpty)
        .map((value) => value.toLowerCase())
        .toSet();
    final showRouteLabel = routeIds.length > 1;
    final showBatchLabel = craftUse.formulas.any(
      (formula) => formula.batchMultiplier != 1,
    );
    return Padding(
      padding: EdgeInsets.only(top: topSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              ModeItemIcon(
                controller: controller.modeController.owner.modes[mode]!,
                catalogRepository: controller.catalogRepository,
                name: craftUse.output,
                size: 24,
                searchAcrossModes: true,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  craftUse.output,
                  style: style.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(description, style: contextStyle),
          ],
          if (example.isNotEmpty) ...<Widget>[
            const SizedBox(height: 3),
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: 'Example: ',
                    style: contextStyle.copyWith(
                      color: spec.palette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: example, style: contextStyle),
                ],
              ),
            ),
          ],
          if (craftUse.formulas.isNotEmpty) const SizedBox(height: 7),
          for (
            var index = 0;
            index < craftUse.formulas.length;
            index++
          ) ...<Widget>[
            if (index > 0) const SizedBox(height: 8),
            _FormulaCard(
              controller: controller,
              mode: mode,
              formula: craftUse.formulas[index],
              style: style,
              showRouteLabel: showRouteLabel,
              showBatchLabel: showBatchLabel,
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.title,
    required this.values,
    required this.style,
  });

  final String title;
  final List<String> values;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _InfoSectionHeading(title: title, spec: spec),
          const SizedBox(height: 5),
          for (final value in values) _InfoBullet(value: value, style: style),
        ],
      ),
    );
  }
}

class _InfoSectionHeading extends StatelessWidget {
  const _InfoSectionHeading({required this.title, required this.spec});

  final String title;
  final ThemeSpec spec;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        title,
        style: spec.typography.meta.copyWith(
          color: spec.palette.textMuted,
          fontWeight: FontWeight.w800,
          letterSpacing: .2,
        ),
      ),
    );
  }
}

class _InfoBullet extends StatelessWidget {
  const _InfoBullet({required this.value, required this.style});

  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final lines = value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.length > 1) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Semantics(
          container: true,
          label: lines.join(', '),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('\u2022', style: style),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        lines.first,
                        style: style.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final line in lines.skip(1))
                  Padding(
                    padding: const EdgeInsets.only(left: 18, bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('\u2022', style: style),
                        const SizedBox(width: 6),
                        Expanded(child: Text(line, style: style)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        container: true,
        label: lines.isEmpty ? value : lines.single,
        child: ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('\u2022', style: style),
              const SizedBox(width: 6),
              Expanded(
                child: Text(lines.isEmpty ? value : lines.single, style: style),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
