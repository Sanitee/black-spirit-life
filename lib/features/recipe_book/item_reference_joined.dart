part of 'recipe_book_item_info_view.dart';

/// One finish and recipe layout for opened windows and artwork previews.
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
              ? _matchingReferenceFormulas(
                  details.craftUses.single,
                  card.name.trim().toLowerCase(),
                )
              : const <RecipeBookFormula>[]
        : formulas;
    final single = activeFormulas.length == 1 ? activeFormulas.single : null;
    final footer =
        card.interactive && single != null && book.canActivateFormula(single);
    final shownFormulas = [
      if (!_used || !card.interactive) ...formulas,
      if (_used || !card.interactive)
        for (final use in details.craftUses)
          ..._matchingReferenceFormulas(use, card.name.trim().toLowerCase()),
    ];
    return PlannerChoiceMarket(
      controller: book.modeController.owner.modes[card.mode]!,
      resolveAcrossModes: true,
      names: {
        for (final formula in shownFormulas)
          ..._referenceFormulaNames(book, formula, formula.mode ?? card.mode),
      }.toList(),
      builder: (context, marketFor, now) => Container(
        width: math.min(
          card.maxWidth,
          itemReferenceCardWidth(
            context,
            controller: book,
            info: details,
            mode: card.mode,
            usedFor: _used,
            includeAllSections: !card.interactive,
            marketFor: marketFor,
            now: now,
          ),
        ),
        // Keep the introduction and one complete recipe in view. The reading
        // viewport below measures their actual height, capped to the screen.
        constraints: BoxConstraints(
          maxHeight: itemReferenceCardHeight(context),
        ),
        child: _ItemReferenceCopyScope(
          onCopyItemName: card.onCopyItemName,
          onRecipeActivated: card.onClose,
          onUseFormula: card.onUseFormula,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: refined
                    ? seam
                    : Color.lerp(seam, spec.palette.text, .20)!,
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
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(details, hasUsed && card.interactive),
                          Flexible(
                            child: DecoratedBox(
                              decoration: BoxDecoration(gradient: bodyGradient),
                              child: ScrollConfiguration(
                                behavior:
                                    const _RecipeBookItemInfoScrollBehavior(),
                                child: _ReferenceReadingViewport(
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
                                        children: !card.interactive
                                            ? [
                                                ..._recipeContent(
                                                  details,
                                                  formulas,
                                                  false,
                                                ),
                                                if (hasUsed) ...[
                                                  _inset(
                                                    _InfoSectionHeading(
                                                      title: 'Used for',
                                                      spec: spec,
                                                    ),
                                                  ),
                                                  ..._usedContent(
                                                    details,
                                                    false,
                                                  ),
                                                ],
                                              ]
                                            : _used && hasUsed
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
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
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
    _ReferenceReadingSection(
      recipe: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (details.summary.trim().isNotEmpty)
            _inset(
              Text(details.summary),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            ),
          if (details.effects.isNotEmpty)
            _inset(
              _InfoSection(
                title: details.effectsTitle,
                values: details.effects,
                style: body,
                leadingSpacing: 0,
              ),
            ),
          if (details.acquisitionNotes.isNotEmpty)
            _inset(
              _AcquisitionSection(
                controller: book,
                mode: card.mode,
                name: card.name,
                info: details,
                style: body,
                leadingSpacing: 0,
              ),
            ),
        ],
      ),
    ),
    for (final formula in formulas)
      _ReferenceReadingSection(
        recipe: true,
        child: _formula(formula, showAction: !footer),
      ),
    if (details.example?.trim().isNotEmpty ?? false)
      _inset(
        _InfoSection(
          title: 'Example',
          values: [details.example!],
          style: body,
          leadingSpacing: 0,
        ),
      ),
    if (details.notes.isNotEmpty)
      _inset(
        _InfoSection(
          title: 'Notes',
          values: details.notes,
          style: body,
          leadingSpacing: 0,
        ),
      ),
    if (details.summary.trim().isEmpty &&
        details.effects.isEmpty &&
        details.acquisitionFormulas.isEmpty &&
        details.acquisitionNotes.isEmpty &&
        details.uses.isEmpty &&
        details.craftUses.isEmpty &&
        details.notes.isEmpty &&
        (details.example?.trim().isEmpty ?? true))
      _inset(const Text('No source details recorded yet.')),
  ];

  List<Widget> _usedContent(RecipeBookItemInfo details, bool footer) {
    final source = card.name.trim().toLowerCase();
    return [
      _ReferenceReadingSection(
        recipe: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final value in details.uses)
              _inset(_InfoBullet(value: value, style: body)),
          ],
        ),
      ),
      for (final use in details.craftUses)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReferenceReadingSection(
              recipe: false,
              heading: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                  ),
                  if (book.itemInfoFor(use.output, mode: card.mode)
                      case final output?) ...[
                    if (recipeBookUseDescription(output).trim().isNotEmpty &&
                        !(output.effects.isNotEmpty &&
                            recipeBookUseDescription(output).trim() ==
                                'A temporary draught buff.'))
                      _inset(
                        Text(recipeBookUseDescription(output), style: meta),
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                      ),
                    if (output.effects.isNotEmpty)
                      _inset(
                        _InfoSection(
                          title: output.effectsTitle,
                          values: output.effects,
                          style: body,
                          leadingSpacing: 0,
                        ),
                        padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
                      ),
                    if (output.example?.trim().isNotEmpty ?? false)
                      _inset(Text('Example: ${output.example}', style: meta)),
                  ],
                ],
              ),
            ),
            for (final formula in _matchingReferenceFormulas(use, source))
              _ReferenceReadingSection(
                recipe: true,
                child: _formula(formula, showAction: !footer),
              ),
          ],
        ),
    ];
  }

  Widget _formula(RecipeBookFormula formula, {bool showAction = true}) =>
      PlannerChoiceMarket(
        key: ValueKey(
          'reference-market:${recipeBookPreviewFormulaIdentity(formula)}',
        ),
        controller: book.modeController.owner.modes[formula.mode ?? card.mode]!,
        resolveAcrossModes: true,
        names: _referenceFormulaNames(book, formula, card.mode),
        builder: (context, marketFor, now) => KeyedSubtree(
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: spec.palette.primary.withValues(
                    alpha: refined ? .025 : .045,
                  ),
                  border: Border(
                    top: BorderSide(color: seam.withValues(alpha: .2)),
                    bottom: BorderSide(color: seam.withValues(alpha: .2)),
                  ),
                ),
                child: _formulaHeading(formula),
              ),
              _ReferenceIngredientsTable(
                book: book,
                formula: formula,
                mode: formula.mode ?? card.mode,
                marketFor: marketFor,
                now: now,
              ),
              if (card.interactive &&
                  showAction &&
                  book.canActivateFormula(formula))
                _action(formula),
            ],
          ),
        ),
      );

  Widget _formulaHeading(RecipeBookFormula formula) {
    final route = formula.routeLabel?.trim();
    final label = _formulaOutputLabel(formula);
    return Row(
      key: ValueKey(
        'formula-heading:${formula.outputName}:${formula.batchMultiplier}',
      ),
      children: [
        _art(formula.outputName, 24, formula.mode),
        const SizedBox(width: 8),
        Text(
          label.startsWith('Output ') ? label.substring(7) : label,
          style: meta.copyWith(
            color: spec.palette.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(
                formula.method,
                style: meta.copyWith(
                  color: spec.palette.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (formula.batchMultiplier != 1 &&
                  !(formula.outputMinimum == formula.batchMultiplier &&
                      formula.outputMaximum == formula.batchMultiplier &&
                      !formula.outputEstimated))
                Text('${formula.batchMultiplier}× batch', style: meta),
              if (route != null &&
                  route.isNotEmpty &&
                  route.toLowerCase() != formula.method.trim().toLowerCase())
                Text(route, style: meta),
            ],
          ),
        ),
      ],
    );
  }

  Widget _action(RecipeBookFormula formula) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                use(book.referenceFormulaForActivation(formula));
              } else {
                card.onClose?.call();
                book.activateFormula(
                  book.referenceFormulaForActivation(formula),
                );
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
