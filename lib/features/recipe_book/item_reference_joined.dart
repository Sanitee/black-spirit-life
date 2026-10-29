part of 'recipe_book_item_info_view.dart';

/// Pinned item windows; noninteractive artwork hovers retain their full reference.
class _JoinedItemReference extends StatefulWidget {
  const _JoinedItemReference({required this.card});
  final ItemReferenceCard card;

  @override
  State<_JoinedItemReference> createState() => _JoinedItemReferenceState();
}

/// Static copper detailing: no animation or hit-testing changes.
class _JoinedCopperPainter extends CustomPainter {
  const _JoinedCopperPainter(this.zone);
  final String zone;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || zone == 'inactive') return;
    final bounds = Offset.zero & size;
    const metal = Color(0xFFB67C71);
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    void gradient(
      Rect rect,
      List<Color> colors, {
      Alignment begin = Alignment.centerLeft,
      Alignment end = Alignment.centerRight,
      List<double>? stops,
    }) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: begin,
            end: end,
            colors: colors,
            stops: stops,
          ).createShader(rect),
      );
    }

    if (zone == 'frame') {
      rim.shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xAAAD8279), Color(0x183E2930), Color(0x665C3B42)],
        stops: [0, .46, 1],
      ).createShader(bounds);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds.deflate(1.5), const Radius.circular(7)),
        rim,
      );
      gradient(
        Rect.fromLTWH(.5, 12, 1.8, size.height - 24),
        [
          metal.withValues(alpha: 0),
          metal.withValues(alpha: .8),
          metal.withValues(alpha: .15),
          metal.withValues(alpha: 0),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0, .18, .66, 1],
      );
    } else if (zone == 'header') {
      gradient(
        bounds,
        [
          const Color(0xFFA66C69).withValues(alpha: .12),
          Colors.transparent,
          Colors.transparent,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0, .28, 1],
      );
      canvas.drawLine(
        Offset(0, size.height - 1.5),
        Offset(size.width, size.height - 1.5),
        Paint()
          ..color = const Color(0xAA09070A)
          ..strokeWidth = 1,
      );
      gradient(
        Rect.fromLTWH(79, 8, 1.3, size.height - 8),
        const [Color(0x00B67C71), Color(0x44B67C71), Color(0xAAB67C71)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
    } else if (zone == 'mount') {
      rim.shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xAAAD8279), Color(0x146B3C48), Color(0x555A363F)],
      ).createShader(bounds);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds.deflate(1.5), const Radius.circular(5)),
        rim,
      );
      final corners = Path()
        ..moveTo(.5, 14)
        ..lineTo(.5, 6)
        ..quadraticBezierTo(.5, .5, 6, .5)
        ..lineTo(14, .5)
        ..moveTo(size.width - 14, size.height - .5)
        ..lineTo(size.width - 6, size.height - .5)
        ..quadraticBezierTo(
          size.width - .5,
          size.height - .5,
          size.width - .5,
          size.height - 6,
        )
        ..lineTo(size.width - .5, size.height - 14);
      canvas.drawPath(
        corners,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = metal.withValues(alpha: .82)
          ..strokeWidth = 1.3,
      );
    } else if (zone == 'tab') {
      gradient(Rect.fromLTWH(7, 1, size.width - 14, 1.5), const [
        Color(0x00A66C69),
        Color(0xBBD09A8F),
        Color(0x00A66C69),
      ]);
      gradient(Rect.fromLTWH(1, size.height - 1.5, size.width - 2, 1.2), const [
        Color(0x99B67C71),
        Color(0x77B67C71),
        Color(0x00B67C71),
      ]);
    }
  }

  @override
  bool shouldRepaint(_JoinedCopperPainter oldDelegate) =>
      zone != oldDelegate.zone;
}

class _JoinedItemReferenceState extends State<_JoinedItemReference> {
  final _scroll = ScrollController(keepScrollOffset: false);
  final _offsets = <bool, double>{false: 0, true: 0};
  bool _used = false;
  ItemReferenceCard get card => widget.card;
  ThemeSpec get spec => card.spec;
  RecipeBookController get book => card.controller;
  RecipeBookItemInfo get info => withReadableRecipeBookSections(card.info);
  TextStyle get body => ItemDetailStyle.body(spec);
  TextStyle get meta => ItemDetailStyle.meta(spec);
  // Sakura uses the approved dark copper finish; other themes keep their palette.
  bool get refined => spec.isSakuraNightGarden;
  Color get face =>
      refined ? const Color(0xFF191619) : spec.palette.surfaceRaised;
  Color get copper => refined
      ? const Color(0xFF403035)
      : Color.lerp(spec.palette.trimBright, spec.palette.surfaceRaised, .30)!;
  Color get seam => spec.palette.trimBright.withValues(alpha: .45);
  LinearGradient get bodyGradient => LinearGradient(
    begin: refined ? Alignment.topCenter : Alignment.topLeft,
    end: refined ? Alignment.bottomCenter : Alignment.bottomRight,
    colors: refined
        ? [face, Color.lerp(face, const Color(0xFF100E12), .38)!]
        : [
            Color.lerp(copper, face, .86)!,
            Color.lerp(face, spec.palette.surface, .65)!,
          ],
  );
  LinearGradient get headerGradient => LinearGradient(
    begin: refined ? Alignment.topCenter : Alignment.centerLeft,
    end: refined ? Alignment.bottomCenter : Alignment.centerRight,
    colors: [Color.lerp(copper, face, refined ? .58 : .65)!, face],
  );
  LinearGradient get artworkGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [copper, Color.lerp(copper, face, refined ? .70 : .30)!],
  );
  LinearGradient get selectedGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color.lerp(copper, face, refined ? .38 : .58)!, face],
  );

  Widget _edgeDetail(String zone, Widget child) => !refined
      ? child
      : CustomPaint(
          foregroundPainter: _JoinedCopperPainter(zone),
          child: child,
        );

  Widget _headerArt() {
    final art = card.icon ?? _art(card.name, 44);
    if (!refined) return art;
    return _edgeDetail(
      'mount',
      Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF171316), Color(0xFF231A20), Color(0xFF100D10)],
          ),
          border: Border.all(color: seam),
          boxShadow: [
            BoxShadow(
              color: const Color(0x99000000),
              offset: const Offset(0, 3),
              blurRadius: 5,
            ),
          ],
        ),
        child: Center(child: art),
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_JoinedItemReference oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.name != card.name || oldWidget.card.mode != card.mode) {
      _used = false;
      _offsets.updateAll((_, _) => 0);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  void _select(bool used) {
    if (_used == used) return;
    if (_scroll.hasClients) _offsets[_used] = _scroll.offset;
    setState(() => _used = used);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(
          _offsets[used]!.clamp(0.0, _scroll.position.maxScrollExtent),
        );
      }
    });
  }

  Widget _art(String name, double size, [CraftMode? mode]) => ModeItemIcon(
    controller: book.modeController.owner.modes[mode ?? card.mode]!,
    catalogRepository: book.catalogRepository,
    name: name,
    size: size,
    showFrame: false,
    searchAcrossModes: true,
  );

  Widget _inset(Widget child, {EdgeInsetsGeometry? padding}) => Padding(
    padding: padding ?? const EdgeInsets.fromLTRB(18, 16, 18, 16),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final details = info;
    final hasUsed = details.craftUses.isNotEmpty || details.uses.isNotEmpty;
    final formulas = _distinctReferenceFormulas(details.acquisitionFormulas);
    final activeFormulas = _used
        ? details.craftUses.length == 1
              ? _matchingFormulas(
                  details.craftUses.single,
                  card.name.trim().toLowerCase(),
                )
              : const <RecipeBookFormula>[]
        : formulas;
    final single = activeFormulas.length == 1 ? activeFormulas.single : null;
    final footer = single != null && book.canActivateFormula(single);
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
      1.0,
      1.5,
    );
    return SizedBox(
      width: card.maxWidth,
      height: math.min(itemReferenceCardHeight(context), 548 * scale),
      child: _ItemReferenceCopyScope(
        onCopyItemName: card.onCopyItemName,
        onRecipeActivated: card.onClose,
        onUseFormula: card.onUseFormula,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: refined ? seam : Color.lerp(seam, spec.palette.text, .20)!,
            ),
            boxShadow: [
              BoxShadow(
                color: spec.palette.shadow.withValues(alpha: .45),
                offset: const Offset(0, 5),
                blurRadius: 14,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _edgeDetail(
                'frame',
                Material(
                  color: face,
                  child: DefaultTextStyle(
                    style: body,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(details, hasUsed),
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(gradient: bodyGradient),
                            child: ScrollConfiguration(
                              behavior:
                                  const _RecipeBookItemInfoScrollBehavior(),
                              child: SingleChildScrollView(
                                key: const ValueKey(
                                  'attached-reference-scroll',
                                ),
                                controller: _scroll,
                                primary: false,
                                physics: const ClampingScrollPhysics(),
                                child: _ReferenceSelection(
                                  enabled: card.onClose != null,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: _used && hasUsed
                                        ? _usedContent(details, footer)
                                        : _recipeContent(
                                            details,
                                            formulas,
                                            footer,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (footer) _action(single),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(RecipeBookItemInfo details, bool hasUsed) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(20) / 20;
      if (constraints.maxWidth / scale >= 210) {
        return _wideHeader(details, hasUsed);
      }
      // At narrow/enlarged sizes give the full name the entire panel width.
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: headerGradient,
          border: Border(bottom: BorderSide(color: seam)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _headerArt(),
                  const SizedBox(width: 12),
                  Expanded(child: Text(details.kind, style: meta)),
                  const SizedBox(width: 6),
                  AppButton(
                    key: card.closeKey,
                    role: AppButtonRole.optionPill,
                    minimumSize: const Size.square(30),
                    padding: EdgeInsets.zero,
                    semanticLabel: 'Close ${card.name} information',
                    onPressed: card.onClose,
                    child: const AppVectorGlyph('close', size: 9),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: AnchoredPopoverDragRegion(
                  key: card.headerDragKey,
                  child: _ReferenceItemName(
                    name: card.name,
                    label: details.title,
                    style: ItemDetailStyle.title(spec),
                  ),
                ),
              ),
              if (hasUsed)
                Row(
                  children: [
                    Expanded(
                      child: _tab(
                        details.acquisitionFormulas.isNotEmpty
                            ? 'Recipe'
                            : 'Details',
                        Icons.science_outlined,
                        false,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: _tab('Used for', Icons.layers_outlined, true),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _wideHeader(RecipeBookItemInfo details, bool hasUsed) => _edgeDetail(
    'header',
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: headerGradient,

        border: Border(bottom: BorderSide(color: seam)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 80,
              decoration: BoxDecoration(
                gradient: artworkGradient,
                border: Border(right: BorderSide(color: seam)),
              ),
              child: Center(child: _headerArt()),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AnchoredPopoverDragRegion(
                            key: card.headerDragKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ReferenceItemName(
                                  name: card.name,
                                  label: details.title,
                                  style: ItemDetailStyle.title(spec),
                                ),
                                const SizedBox(height: 6),
                                Text(details.kind, style: meta),
                              ],
                            ),
                          ),
                        ),
                        if (card.onClose != null) ...[
                          const SizedBox(width: 6),
                          AppButton(
                            key: card.closeKey,
                            role: AppButtonRole.optionPill,
                            minimumSize: const Size.square(30),
                            padding: EdgeInsets.zero,
                            semanticLabel: 'Close ${card.name} information',
                            onPressed: card.onClose,
                            child: const AppVectorGlyph('close', size: 9),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (hasUsed)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: _tab(
                              details.acquisitionFormulas.isNotEmpty
                                  ? 'Recipe'
                                  : 'Details',
                              Icons.science_outlined,
                              false,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: _tab(
                              'Used for',
                              Icons.layers_outlined,
                              true,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _tab(String label, IconData icon, bool used) {
    final selected = used == _used;
    final colour = selected ? spec.palette.text : spec.palette.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        key: ValueKey('attached-reference-tab:${used ? 'used' : 'recipe'}'),
        onTap: () => _select(used),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
        child: _edgeDetail(
          selected ? 'tab' : 'inactive',
          Container(
            constraints: const BoxConstraints(minHeight: 37),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(7),
              ),
              border: Border.all(color: selected ? seam : Colors.transparent),
              gradient: selected ? selectedGradient : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: colour),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    style: meta.copyWith(
                      color: colour,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _recipeContent(
    RecipeBookItemInfo details,
    List<RecipeBookFormula> formulas,
    bool footer,
  ) => [
    if (details.summary.trim().isNotEmpty) _inset(Text(details.summary)),
    if (details.effects.isNotEmpty)
      _inset(
        _InfoSection(
          title: details.effectsTitle,
          values: details.effects,
          style: body,
        ),
      ),
    if (details.acquisitionNotes.isNotEmpty)
      _inset(
        _InfoSection(
          title: 'How to Obtain',
          values: details.acquisitionNotes,
          style: body,
        ),
      ),
    for (final formula in formulas) _formula(formula, showAction: !footer),
    if (details.example?.trim().isNotEmpty ?? false)
      _inset(
        _InfoSection(title: 'Example', values: [details.example!], style: body),
      ),
    if (details.notes.isNotEmpty)
      _inset(_InfoSection(title: 'Notes', values: details.notes, style: body)),
    if (!details.hasBody) _inset(const Text('No source details recorded yet.')),
  ];

  List<Widget> _usedContent(RecipeBookItemInfo details, bool footer) {
    final source = card.name.trim().toLowerCase();
    return [
      for (final value in details.uses)
        _inset(_InfoBullet(value: value, style: body)),
      for (final use in details.craftUses) ...[
        _inset(
          Row(
            children: [
              _art(use.output, 38),
              const SizedBox(width: 12),
              Expanded(
                child: _ReferenceItemName(
                  name: use.output,
                  style: ItemDetailStyle.recipe(spec),
                ),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 10),
        ),
        if (book.itemInfoFor(use.output, mode: card.mode)
            case final output?) ...[
          if (recipeBookUseDescription(output).trim().isNotEmpty)
            _inset(
              Text(recipeBookUseDescription(output), style: meta),
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            ),
          for (final effect in output.effects)
            _inset(_InfoBullet(value: effect, style: body)),
          if (output.example?.trim().isNotEmpty ?? false)
            _inset(Text('Example: ${output.example}', style: meta)),
        ],
        for (final formula in _matchingFormulas(use, source))
          _formula(formula, showAction: !footer),
      ],
    ];
  }

  List<RecipeBookFormula> _matchingFormulas(
    RecipeBookCraftUse use,
    String source,
  ) {
    final matching = use.formulas
        .where(
          (f) => f.ingredients.any(
            (i) => [
              i.name,
              ...i.options,
              ...i.substituteRatios.keys,
            ].any((n) => n.trim().toLowerCase() == source),
          ),
        )
        .toList();
    return _distinctReferenceFormulas(
      matching.isEmpty ? use.formulas : matching,
    );
  }

  Widget _formula(RecipeBookFormula formula, {bool showAction = true}) =>
      KeyedSubtree(
        // One item can have same-named routes in multiple workstations.
        key: ValueKey(recipeBookPreviewFormulaIdentity(formula)),
        child: Column(
          key: RecipeBookKeys.itemInfoFormula(
            formula.outputName,
            formula.variantId,
            formula.batchMultiplier,
          ),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: spec.palette.primary.withValues(
                  alpha: refined ? .025 : .045,
                ),
                border: Border(
                  top: BorderSide(color: seam.withValues(alpha: .2)),
                  bottom: BorderSide(color: seam.withValues(alpha: .2)),
                ),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 14,
                runSpacing: 6,
                children: [
                  Text(
                    formula.method,
                    style: meta.copyWith(
                      color: spec.palette.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (formula.routeLabel?.trim().isNotEmpty ?? false)
                    Text(formula.routeLabel!, style: meta),
                  if (formula.batchMultiplier != 1)
                    Text('${formula.batchMultiplier}× batch', style: meta),
                  _ReferenceItemName(
                    name: formula.outputName,
                    label: _formulaOutputLabel(formula),
                    style: meta,
                  ),
                ],
              ),
            ),
            for (var i = 0; i < formula.ingredients.length; i++)
              _ingredient(formula, formula.ingredients[i], i),
            if (showAction && book.canActivateFormula(formula))
              _action(formula),
          ],
        ),
      );

  Widget _ingredient(
    RecipeBookFormula formula,
    Ingredient ingredient,
    int index,
  ) {
    final mode = formula.mode ?? card.mode;
    final alternatives = _formulaAlternatives(
      ingredient,
      recipes: book.modeController.owner.modes[mode]!.recipes,
    );
    return DecoratedBox(
      key: RecipeBookKeys.itemInfoMaterial(
        formula.outputName,
        formula.variantId,
        ingredient.name,
      ),
      decoration: BoxDecoration(
        color: index.isOdd
            ? spec.palette.primary.withValues(alpha: refined ? .025 : .045)
            : Colors.transparent,
        border: Border(bottom: BorderSide(color: seam.withValues(alpha: .16))),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 52,
              padding: const EdgeInsets.only(top: 9, bottom: 9),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    copper.withValues(alpha: .34),
                    copper.withValues(alpha: .16),
                  ],
                ),
                border: Border(
                  right: BorderSide(color: seam.withValues(alpha: .2)),
                ),
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: _art(ingredient.name, 32, mode),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ReferenceItemName(
                      name: ingredient.name,
                      style: ItemDetailStyle.ingredient(spec),
                    ),
                    for (final alternate in alternatives)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _ReferenceItemName(
                          name: alternate.name,
                          label:
                              'or ${_displayQuantity(alternate.quantity)} ${alternate.name}',
                          style: meta.copyWith(
                            height: 1.45,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 18, 12),
              child: Text(
                '×${_displayQuantity(ingredient.quantity)}',
                style: meta,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(RecipeBookFormula formula) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: face,
      border: Border(top: BorderSide(color: seam.withValues(alpha: .25))),
    ),
    child: Stack(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: AppButton(
            key: ValueKey(
              'item-info-use-recipe:${(formula.mode ?? card.mode).key}:'
              '${formula.outputName}:${formula.variantId ?? 'base'}:'
              '${formula.batchMultiplier}',
            ),
            role: AppButtonRole.optionPill,
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            semanticLabel:
                'Use ${formula.outputName}, ${formula.method}'
                '${formula.routeLabel?.trim().isNotEmpty == true ? ', ${formula.routeLabel}' : ''}'
                '${formula.batchMultiplier != 1 ? ', ${formula.batchMultiplier}× batch' : ''}',
            onPressed: () {
              if (!book.canActivateFormula(formula)) return;
              Tooltip.dismissAllToolTips();
              if (card.onUseFormula case final use?) {
                use(formula);
              } else {
                card.onClose?.call();
                book.activateFormula(formula);
              }
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.north_east, size: 14),
                SizedBox(width: 7),
                Flexible(child: Text('Use recipe')),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
