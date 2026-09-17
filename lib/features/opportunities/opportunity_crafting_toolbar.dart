part of 'opportunities_workspace.dart';

class _CraftMasteryControl extends StatefulWidget {
  const _CraftMasteryControl({required this.controller});
  final OpportunitiesController controller;

  @override
  State<_CraftMasteryControl> createState() => _CraftMasteryControlState();
}

class _CraftMasteryControlState extends State<_CraftMasteryControl> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;
  bool _invalid = false;
  CraftMode? _editingMode;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(_CraftMasteryControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_editing &&
        (oldWidget.controller != widget.controller ||
            _editingMode != widget.controller.preferences.mode)) {
      // Never apply a draft from one craft type to another.
      _editing = false;
      _invalid = false;
      _editingMode = null;
    }
  }

  void _start() {
    _editingMode = widget.controller.preferences.mode;
    _text.value = TextEditingValue(
      text: '${_mastery(widget.controller)}',
      selection: TextSelection(
        baseOffset: 0,
        extentOffset: '${_mastery(widget.controller)}'.length,
      ),
    );
    setState(() {
      _editing = true;
      _invalid = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _focus.requestFocus();
    });
  }

  int? get _value {
    if (!RegExp(r'^[0-9]+$').hasMatch(_text.text)) return null;
    final value = int.tryParse(_text.text);
    return value != null && value >= 0 && value <= 3000 ? value : null;
  }

  void _focusChanged() {
    if (mounted && _editing && !_focus.hasFocus) _finish(fromBlur: true);
  }

  void _cancel() {
    if (!_editing) return;
    setState(() {
      _editing = false;
      _invalid = false;
      _editingMode = null;
    });
    _focus.unfocus();
  }

  void _finish({bool fromBlur = false}) {
    if (!_editing) return;
    if (_editingMode != widget.controller.preferences.mode) {
      _cancel();
      return;
    }
    final value = _value;
    if (value == null) {
      if (fromBlur) {
        _cancel();
      } else {
        setState(() => _invalid = true);
        _focus.requestFocus();
      }
      return;
    }
    final mode = _editingMode!;
    final modeController = widget.controller.modeController;
    final changed = value != _mastery(widget.controller);
    _cancel();
    if (changed) {
      modeController.updateState(
        (state) => switch (mode) {
          CraftMode.cooking => state.copyWith(cookingMastery: value),
          CraftMode.alchemy => state.copyWith(alchemyMastery: value),
          CraftMode.processing => state.copyWith(processingMastery: value),
        },
      );
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final controlHeight = math.max(
      40.0,
      MediaQuery.textScalerOf(
                context,
              ).scale(spec.typography.button.fontSize ?? 14) *
              (spec.typography.button.height ?? 1.3) +
          16,
    );
    // Reserve the editor's text-aware height before it opens, so the status
    // area stays in place at enlarged desktop text sizes too.
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: controlHeight),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Mastery ·', style: spec.typography.button),
          const SizedBox(width: 8),
          SizedBox(
            width: 64 * scale,
            child: _editing
                ? Tooltip(
                    message: '0–3000',
                    child: OpportunityTextField(
                      key: const ValueKey('craft-mastery-input'),
                      flat: true,
                      controller: _text,
                      focusNode: _focus,
                      semanticLabel:
                          '${widget.controller.preferences.mode.label} mastery, 0 to 3000',
                      textAlign: TextAlign.start,
                      textStyle: spec.typography.button.copyWith(
                        color: _invalid
                            ? spec.palette.danger
                            : spec.palette.text,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) =>
                          setState(() => _invalid = _value == null),
                      onSubmitted: (_) => _finish(),
                      onKeyEvent: (_, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.escape) {
                          _cancel();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey ==
                                LogicalKeyboardKey.numpadEnter) {
                          _finish();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                    ),
                  )
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: spec.palette.surfaceInset,
                      borderRadius: BorderRadius.circular(
                        spec.geometry.fieldRadius,
                      ),
                      border: Border.all(
                        color: spec.palette.trim.withAlpha(190),
                      ),
                    ),
                    child: OpportunityButton(
                      key: const ValueKey('craft-mastery'),
                      role: AppButtonRole.infoChip,
                      minimumSize: Size(0, controlHeight),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      semanticLabel:
                          'Edit ${widget.controller.preferences.mode.label} mastery, ${_mastery(widget.controller)}',
                      onPressed: _start,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${_mastery(widget.controller)}',
                          style: spec.typography.button,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CraftingToolbar extends StatefulWidget {
  const _CraftingToolbar({required this.controller});
  final OpportunitiesController controller;

  @override
  State<_CraftingToolbar> createState() => _CraftingToolbarState();
}

class _CraftingToolbarState extends State<_CraftingToolbar> {
  // Keep editing state when the two rows wrap at narrower widths.
  final _searchSlot = GlobalKey();
  OpportunitiesController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final p = controller.preferences;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return LayoutBuilder(
      key: const ValueKey('craft-toolbar'),
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              SizedBox(
                width: math.min(326 * scale, constraints.maxWidth),
                child: KeyedSubtree(
                  key: _searchSlot,
                  child: _TextInput(
                    key: const ValueKey('craft-search'),
                    label: 'Find a recipe',
                    value: p.craftSearch,
                    onChanged: (value) =>
                        controller.change((p) => p.craftSearch = value),
                    prefix: const Icon(Icons.search, size: 20),
                  ),
                ),
              ),
              _CraftSortControl(controller: controller),
            ],
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: spec.palette.trim.withAlpha(70)),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  _CraftModeTabs(controller: controller),
                  Wrap(
                    key: const ValueKey('craft-filters'),
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CraftFilterPill(
                        controlKey: const ValueKey('craft-has-demand'),
                        label: 'Out of stock',
                        selected: p.demandOnly,
                        tooltip:
                            'Zero listed stock, with or without preorders.',
                        onSelected: (value) =>
                            controller.change((p) => p.demandOnly = value),
                      ),
                      _CraftFilterPill(
                        controlKey: const ValueKey(
                          'craft-ingredients-available',
                        ),
                        label: 'Ingredients available',
                        selected: p.readyOnly,
                        tooltip:
                            'Enough market stock or NPC supply for one craft.',
                        onSelected: (value) =>
                            controller.change((p) => p.readyOnly = value),
                      ),
                      _CraftFilterPill(
                        controlKey: const ValueKey('craft-profitable'),
                        label: 'Profitable',
                        selected: p.profitableOnly,
                        tooltip:
                            'Name searches also include recipes with a loss.',
                        onSelected: (value) =>
                            controller.change((p) => p.profitableOnly = value),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CraftSortControl extends StatelessWidget {
  const _CraftSortControl({required this.controller});
  final OpportunitiesController controller;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final p = controller.preferences;
    final activeSort = controller.activeCraftSort;
    final ascending = p.craftSortAscending[activeSort] ?? false;
    double textWidth(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: spec.typography.button),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final expWidth =
        textWidth('EXP') +
        24 +
        (activeSort == 'exp' ? math.max(32, textWidth('↓') + 16) : 0);
    ButtonStyle style(bool selected) => ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: WidgetStatePropertyAll(spec.typography.button),
      foregroundColor: WidgetStatePropertyAll(
        selected ? spec.palette.text : spec.palette.textMuted,
      ),
      backgroundColor: WidgetStatePropertyAll(
        selected
            ? Color.alphaBlend(
                spec.palette.primary.withAlpha(32),
                spec.palette.surfaceInset,
              )
            : spec.palette.surfaceInset,
      ),
      overlayColor: WidgetStatePropertyAll(spec.palette.primary.withAlpha(25)),
      side: WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.focused)
              ? spec.palette.primaryBright
              : selected
              ? spec.palette.primary.withAlpha(150)
              : spec.palette.trim.withAlpha(190),
        ),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Sort recipes',
      child: Material(
        key: const ValueKey('craft-sort-options'),
        color: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in const [
              ('preorders', 'Demand'),
              ('profit', 'Profit'),
            ]) ...[
              Flexible(
                child: MergeSemantics(
                  child: Semantics(
                    selected: activeSort == option.$1,
                    inMutuallyExclusiveGroup: true,
                    child: TextButton(
                      key: ValueKey('craft-sort-${option.$1}'),
                      onPressed: () => controller.selectCraftSort(
                        option.$1,
                        toggleDirection: true,
                      ),
                      style: style(activeSort == option.$1),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(child: Text(option.$2)),
                          if (activeSort == option.$1) ...[
                            const SizedBox(width: 5),
                            Text(ascending ? '↑' : '↓'),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            if (p.section != 'best-use')
              Flexible(
                child: AnchoredPopover(
                  overlayId: 'craft-exp-filter',
                  placement: AnchoredPopoverPlacement.beside,
                  // Beside placement uses the anchor centre; include half its
                  // measured width so the menu never covers either activation.
                  gap: expWidth / 2 + 6,
                  preferredWidth:
                      224 * (MediaQuery.textScalerOf(context).scale(16) / 16),
                  maximumHeight: 360,
                  popoverBuilder: (context, close) => OpportunitySurface(
                    role: AppSurfaceRole.panel,
                    padding: const EdgeInsets.all(6),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (index, option) in const [
                            ('include', 'Include unknown'),
                            ('hide', 'Hide unknown'),
                            ('only', 'Only unknown'),
                          ].indexed) ...[
                            if (index > 0) const SizedBox(height: 6),
                            Semantics(
                              selected: p.unknownExpFilter == option.$1,
                              inMutuallyExclusiveGroup: true,
                              child: OpportunityButton(
                                key: ValueKey('craft-exp-filter-${option.$1}'),
                                role: AppButtonRole.optionPill,
                                selected: p.unknownExpFilter == option.$1,
                                onPressed: () {
                                  controller.setUnknownExpFilter(option.$1);
                                  close();
                                },
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(option.$2),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  anchorBuilder: (context, toggle, showing) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: MergeSemantics(
                          child: Semantics(
                            selected: activeSort == 'exp',
                            inMutuallyExclusiveGroup: true,
                            child: TextButton(
                              key: const ValueKey('craft-sort-exp'),
                              style: style(activeSort == 'exp'),
                              onPressed: () {
                                controller.selectCraftSort('exp');
                                toggle();
                              },
                              child: const Text('EXP'),
                            ),
                          ),
                        ),
                      ),
                      if (activeSort == 'exp')
                        TextButton(
                          key: const ValueKey('craft-sort-exp-direction'),
                          style: style(true).copyWith(
                            minimumSize: const WidgetStatePropertyAll(
                              Size(32, 40),
                            ),
                            padding: const WidgetStatePropertyAll(
                              EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                          ),
                          onPressed: () => controller.reverseCraftSort('exp'),
                          child: Semantics(
                            label:
                                'Reverse EXP sort, ${ascending ? 'ascending' : 'descending'}',
                            child: Text(ascending ? '↑' : '↓'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CraftFilterPill extends StatelessWidget {
  const _CraftFilterPill({
    required this.label,
    required this.selected,
    this.tooltip,
    required this.onSelected,
    required this.controlKey,
  });
  final Key controlKey;
  final String label;
  final String? tooltip;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return FilterChip(
      key: controlKey,
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      tooltip: tooltip,
      showCheckmark: false,
      avatar: Icon(
        selected ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 16,
        color: selected ? spec.palette.primary : spec.palette.textMuted,
      ),
      labelStyle: spec.typography.button.copyWith(
        color: selected ? spec.palette.primaryBright : spec.palette.textMuted,
      ),
      labelPadding: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      side: BorderSide(
        color: selected
            ? spec.palette.primary.withAlpha(150)
            : spec.palette.trim.withAlpha(190),
      ),
      backgroundColor: spec.palette.surfaceInset,
      selectedColor: Color.alphaBlend(
        spec.palette.primary.withAlpha(24),
        spec.palette.surfaceInset,
      ),
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      pressElevation: 0,
    );
  }
}

class _CraftModeTabs extends StatelessWidget {
  const _CraftModeTabs({required this.controller});
  final OpportunitiesController controller;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Wrap(
      key: const ValueKey('craft-mode-tabs'),
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final mode in [
          CraftMode.cooking,
          CraftMode.alchemy,
          CraftMode.processing,
        ])
          MergeSemantics(
            child: Semantics(
              selected: controller.preferences.mode == mode,
              inMutuallyExclusiveGroup: true,
              child: TextButton(
                key: ValueKey('craft-mode-${mode.name}'),
                onPressed: () =>
                    controller.change((p) => p.mode = mode, assemble: true),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: controller.preferences.mode == mode
                      ? spec.palette.text
                      : spec.palette.textMuted,
                  textStyle: spec.typography.button,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color: controller.preferences.mode == mode
                            ? spec.palette.primary
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(mode.label),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
