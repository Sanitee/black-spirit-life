import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/appearance/appearance_actions.dart';
import '../../app/state/planner_application_controller.dart';
import '../../domain/state/planner_state.dart';
import '../../domain/state/state_copy.dart';
import '../../shared/overlays/anchored_popover.dart';
import '../../visual/illuminated_ledger/ledger_ornament_painters.dart';
import '../../visual/visual.dart';

class AppearanceView extends StatefulWidget {
  const AppearanceView({
    required this.controller,
    this.modeController,
    super.key,
  });

  final PlannerApplicationController controller;
  final ModeFeatureController? modeController;

  @override
  State<AppearanceView> createState() => _AppearanceViewState();
}

class _AppearanceViewState extends State<AppearanceView> {
  static const double _themeGridBreakpoint = 720;
  static const double _headerStackBreakpoint = 620;

  final ScrollController _leftScroll = ScrollController();

  ModeFeatureController get _mode =>
      widget.modeController ?? widget.controller.active;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _leftScroll.dispose();
    super.dispose();
  }

  void _update(
    AppearanceSettings Function(AppearanceSettings source) update, {
    bool immediate = false,
  }) {
    _mode.updateState(
      (state) => state.copyWith(appearance: update(state.appearance)),
      immediate: immediate,
    );
  }

  void _selectShared(String id) {
    widget.controller.updateDocument(
      (document) => AppearanceActions.selectSharedBackground(document, id),
      immediate: true,
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ModeState>(
    valueListenable: _mode.state,
    builder: (context, state, _) {
      final appearance = state.appearance;

      return Semantics(
        container: true,
        label: 'Appearance settings',
        child: _columnScroll(
          key: const ValueKey<String>('appearance-scroll'),
          controller: _leftScroll,
          children: <Widget>[
            _appearanceHeader(appearance),
            const SizedBox(height: 14),
            _themeChoices(appearance),
          ],
        ),
      );
    },
  );

  Widget _appearanceHeader(AppearanceSettings appearance) => LayoutBuilder(
    builder: (context, constraints) {
      final themes = Text(
        'Themes',
        key: const ValueKey<String>('appearance-themes-title'),
        style: context.visualTheme.typography.section.copyWith(fontSize: 24),
      );
      final motion = Column(
        key: const ValueKey<String>('appearance-motion-controls'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Motion',
            style: context.visualTheme.typography.section.copyWith(
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          _transitionChoices(appearance),
        ],
      );
      if (constraints.maxWidth < _headerStackBreakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[themes, const SizedBox(height: 14), motion],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(child: themes),
          motion,
        ],
      );
    },
  );

  Widget _columnScroll({
    required Key key,
    required ScrollController controller,
    required List<Widget> children,
  }) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: ListView(
      key: key,
      controller: controller,
      primary: false,
      padding: const EdgeInsets.only(right: 4, bottom: 12),
      children: children,
    ),
  );

  Widget _themeChoices(AppearanceSettings appearance) {
    final ledgerSelected =
        appearance.background == IlluminatedLedgerSpec.backgroundId;
    final sakuraSelected =
        appearance.background == SakuraNightGardenSpec.backgroundId;
    final choices = <Widget>[
      _themePreviewCard(
        id: 'A02:${SakuraNightGardenSpec.backgroundId}',
        title: 'Sakura Night Garden',
        selected: sakuraSelected,
        onPressed: () => _selectShared(SakuraNightGardenSpec.backgroundId),
        selectedBorder: SakuraNightGardenSpec.paleBlossom,
        restingBorder: SakuraNightGardenSpec.rosewood.withAlpha(190),
        child: _sakuraThemePreview(),
      ),
      _themePreviewCard(
        id: 'A02',
        title: 'Illuminated Ledger',
        selected: ledgerSelected,
        onPressed: () => _selectShared(IlluminatedLedgerSpec.backgroundId),
        selectedBorder: IlluminatedLedgerSpec.palette.primary,
        restingBorder: IlluminatedLedgerSpec.palette.trim.withAlpha(150),
        child: _ledgerThemePreview(),
      ),
      _themePreviewCard(
        id: 'A02:standard',
        title: 'Classic Atelier',
        selected: !ledgerSelected && !sakuraSelected,
        onPressed: () => _selectShared(StandardSpec.defaultBackgroundId),
        selectedBorder: StandardSpec.palette.primaryBright,
        restingBorder: StandardSpec.palette.trim.withAlpha(170),
        child: _standardThemePreview(),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 14.0;
        final columns = constraints.maxWidth >= 1080
            ? 3
            : constraints.maxWidth >= _themeGridBreakpoint
            ? 2
            : 1;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          key: const ValueKey<String>('appearance-theme-grid'),
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final choice in choices) SizedBox(width: width, child: choice),
          ],
        );
      },
    );
  }

  Widget _themePreviewCard({
    required String id,
    required String title,
    required bool selected,
    required VoidCallback onPressed,
    required Widget child,
    required Color selectedBorder,
    required Color restingBorder,
  }) => Semantics(
    button: true,
    selected: selected,
    label: '$id Select $title',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey<String>(id),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(3),
        child: Ink(
          child: AspectRatio(
            aspectRatio: 75 / 47,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.noScaling),
                    child: IgnorePointer(child: child),
                  ),
                ),
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: selected ? selectedBorder : restingBorder,
                        width: selected ? 3 : 1,
                      ),
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    top: 9,
                    right: 9,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: selectedBorder,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withAlpha(120),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(5),
                        child: AppVectorGlyph(
                          'check',
                          size: 14,
                          color: Color(0xfffff4d8),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _standardThemePreview() => Stack(
    key: const ValueKey<String>('standard-theme-preview'),
    fit: StackFit.expand,
    children: <Widget>[
      const RetainedAssetImage(
        assetPath: 'assets/scenes/backdrop-alchemy-greenhouse.png',
        assetLabel: 'Classic Atelier greenhouse',
        fit: BoxFit.cover,
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0x42030706), Color(0xB8030706)],
          ),
        ),
      ),
      Column(
        children: <Widget>[
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[Color(0xff152c24), Color(0xff07130f)],
              ),
              border: Border(bottom: BorderSide(color: Color(0xff2f9e7a))),
            ),
            child: const Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'CLASSIC ATELIER',
                    style: TextStyle(
                      color: Color(0xfffff4d8),
                      fontFamily: 'Georgia',
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'LIVE THEME PREVIEW',
                  style: TextStyle(
                    color: Color(0xffb9c9c1),
                    fontSize: 6.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    width: 72,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: StandardSpec.palette.surfaceInset.withAlpha(226),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: StandardSpec.palette.trim.withAlpha(180),
                      ),
                    ),
                    child: Column(
                      children: <Widget>[
                        _standardPreviewNav('spark', 'Planner', active: true),
                        const SizedBox(height: 4),
                        _standardPreviewNav('vault', 'Inventory'),
                        const SizedBox(height: 4),
                        _standardPreviewNav('quill', 'Editor'),
                        const Spacer(),
                        Container(
                          height: 18,
                          decoration: BoxDecoration(
                            color: StandardSpec.palette.surfaceRaised,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: StandardSpec.palette.trim.withAlpha(150),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'ALCHEMY',
                            style: TextStyle(
                              color: Color(0xfffff4d8),
                              fontSize: 6.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Container(
                          height: 30,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: StandardSpec.palette.surface.withAlpha(235),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: StandardSpec.palette.primary.withAlpha(
                                170,
                              ),
                            ),
                          ),
                          child: const Row(
                            children: <Widget>[
                              AppVectorGlyph(
                                'spark',
                                size: 12,
                                color: Color(0xff69d6ac),
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Elixir of Destruction',
                                  style: TextStyle(
                                    color: Color(0xfffff4d8),
                                    fontSize: 7.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                '30,000',
                                style: TextStyle(
                                  color: Color(0xff69d6ac),
                                  fontSize: 7,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: _standardPreviewPane(
                                  title: 'CRAFT QUEUE',
                                  items: const <String>[
                                    'Oil of Storms',
                                    'Trace of Nature',
                                    'Clear Liquid Reagent',
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _standardPreviewPane(
                                  title: 'NEED FIRST',
                                  items: const <String>[
                                    'Powder of Flame',
                                    'Snowfield Cedar Sap',
                                    'Purified Water',
                                  ],
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
        ],
      ),
    ],
  );

  Widget _standardPreviewNav(
    String glyph,
    String label, {
    bool active = false,
  }) => Container(
    height: 22,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: active
          ? StandardSpec.palette.primary.withAlpha(120)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      border: active
          ? Border.all(color: StandardSpec.palette.primaryBright)
          : null,
    ),
    child: Row(
      children: <Widget>[
        AppVectorGlyph(
          glyph,
          size: 10,
          color: active
              ? StandardSpec.palette.primaryBright
              : StandardSpec.palette.textMuted,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active
                  ? StandardSpec.palette.text
                  : StandardSpec.palette.textMuted,
              fontSize: 6.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _standardPreviewPane({
    required String title,
    required List<String> items,
  }) => Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: StandardSpec.palette.surface.withAlpha(230),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: StandardSpec.palette.trim.withAlpha(175)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            color: Color(0xff69d6ac),
            fontSize: 7,
            fontWeight: FontWeight.w800,
            letterSpacing: .3,
          ),
        ),
        const SizedBox(height: 4),
        for (final item in items)
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 3),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: StandardSpec.palette.surfaceInset.withAlpha(215),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: StandardSpec.palette.trim.withAlpha(115),
                ),
              ),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: _sakuraPreviewItemIcon(item, size: 15),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      item,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xfffff4d8),
                        fontSize: 6.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _ledgerThemePreview() => Stack(
    key: const ValueKey<String>('ledger-theme-preview'),
    fit: StackFit.expand,
    children: <Widget>[
      DecoratedBox(
        decoration: const BoxDecoration(
          gradient: IlluminatedLedgerSpec.raisedVellumGradient,
        ),
        child: Column(
          children: <Widget>[
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: const BoxDecoration(
                gradient: IlluminatedLedgerSpec.lapisGradient,
                border: Border(bottom: BorderSide(color: Color(0xffb9903e))),
              ),
              child: const Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'THE ILLUMINATED LEDGER',
                      style: TextStyle(
                        color: Color(0xfff0dca5),
                        fontFamily: 'Georgia',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'LIVE THEME PREVIEW',
                    style: TextStyle(
                      color: Color(0xffd9be78),
                      fontFamily: 'Georgia',
                      fontSize: 7.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: <Widget>[
                  Container(
                    width: 86,
                    padding: const EdgeInsets.fromLTRB(5, 6, 5, 5),
                    decoration: const BoxDecoration(
                      color: Color(0x55d8c294),
                      border: Border(
                        right: BorderSide(color: Color(0x8eb9903e)),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const SizedBox(
                          height: 31,
                          child: Row(
                            children: <Widget>[
                              SizedBox(
                                width: 23,
                                height: 31,
                                child: RetainedAssetImage(
                                  assetPath:
                                      IlluminatedLedgerSpec.dropCapAssetPath,
                                  assetLabel: 'Illuminated Ledger drop cap',
                                  fit: BoxFit.contain,
                                ),
                              ),
                              SizedBox(width: 4),
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        'BDO CRAFT',
                                        style: TextStyle(
                                          color: Color(0xff352516),
                                          fontFamily: 'Georgia',
                                          fontSize: 7.2,
                                          fontWeight: FontWeight.w700,
                                          height: 1,
                                        ),
                                      ),
                                      Text(
                                        'PLANNER',
                                        style: TextStyle(
                                          color: Color(0xff352516),
                                          fontFamily: 'Georgia',
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w700,
                                          height: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: OverflowBox(
                            alignment: Alignment.topCenter,
                            minHeight: 0,
                            maxHeight: double.infinity,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 7, bottom: 2),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  _ledgerPreviewNav(
                                    'compass',
                                    'PLANNER',
                                    active: true,
                                  ),
                                  const SizedBox(height: 1.5),
                                  _ledgerPreviewNav('spark', 'BONUS'),
                                  const SizedBox(height: 1.5),
                                  _ledgerPreviewNav('vault', 'INVENTORY'),
                                  const SizedBox(height: 1.5),
                                  _ledgerPreviewNav('quill', 'EDITOR'),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Opacity(
                          opacity: .76,
                          child: SizedBox(
                            height: 61,
                            child: RetainedAssetImage(
                              assetPath:
                                  IlluminatedLedgerSpec.marginaliaAssetPath,
                              assetLabel: 'Ledger botanical marginalia',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(9, 7, 8, 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(
                            flex: 108,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: _ledgerPreviewPane(
                                title: 'CRAFT QUEUE',
                                meta: '42 LEFT',
                                rows: const <({String meta, String name})>[
                                  (name: 'Purified Water', meta: 'CRAFT 1,221'),
                                  (
                                    name: 'Clear Liquid Reagent',
                                    meta: 'RESIDENCE ALCHEMY',
                                  ),
                                  (
                                    name: 'Pure Powder Reagent',
                                    meta: 'CRAFT 941',
                                  ),
                                  (name: "Clown's Blood", meta: 'CRAFT 107'),
                                ],
                                missing: false,
                              ),
                            ),
                          ),
                          Container(
                            key: const ValueKey<String>(
                              'ledger-preview-center-fold',
                            ),
                            width: 10,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: <Color>[
                                  Color(0x00ffffff),
                                  Color(0x5a5a4028),
                                  Color(0x70fff1cf),
                                  Color(0x00ffffff),
                                ],
                                stops: <double>[0, .44, .62, 1],
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 92,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 5),
                              child: _ledgerPreviewPane(
                                title: 'NEED FIRST',
                                meta: '47 MISSING',
                                rows: const <({String meta, String name})>[
                                  (
                                    name: 'Trace of Nature',
                                    meta: 'MISSING 3,152',
                                  ),
                                  (name: 'Weeds', meta: 'MISSING 2,676'),
                                  (name: 'Sunrise Herb', meta: 'MISSING 1,359'),
                                  (name: 'Birch Sap', meta: 'MISSING 1,316'),
                                ],
                                missing: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const IgnorePointer(
        child: CustomPaint(
          key: ValueKey<String>('ledger-theme-preview-ornament-frame'),
          painter: LedgerOrnamentFramePainter(),
        ),
      ),
    ],
  );

  Widget _ledgerPreviewNav(
    String glyph,
    String label, {
    bool active = false,
  }) => Container(
    key: ValueKey<String>('ledger-preview-nav:${label.toLowerCase()}'),
    height: 19,
    color: active ? IlluminatedLedgerSpec.palette.primary : Colors.transparent,
    child: Row(
      children: <Widget>[
        SizedBox(
          width: 15,
          child: Center(
            child: AppVectorGlyph(
              glyph,
              size: 9,
              color: active ? const Color(0xffe7c76c) : const Color(0xff725b2e),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: active ? const Color(0xfff5e5b9) : const Color(0xff4a3823),
              fontFamily: 'Georgia',
              fontSize: 6.7,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _ledgerPreviewPane({
    required String title,
    required String meta,
    required List<({String meta, String name})> rows,
    required bool missing,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Container(
        height: 20,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x8bb9903e))),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Color(0xff123d69),
                  fontFamily: 'Georgia',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              meta,
              style: const TextStyle(
                color: Color(0xff6b5430),
                fontFamily: 'Georgia',
                fontSize: 5.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      for (var index = 0; index < rows.length; index++) ...<Widget>[
        _ledgerPreviewRow(rows[index], missing: missing),
        if (index != rows.length - 1) const SizedBox(height: 4),
      ],
    ],
  );

  Widget _ledgerPreviewRow(
    ({String meta, String name}) row, {
    required bool missing,
  }) => Container(
    key: ValueKey<String>('ledger-preview-row:${row.name}'),
    height: 33,
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    decoration: BoxDecoration(
      color: missing ? const Color(0x4ca45648) : const Color(0x6ffff6dd),
      border: Border.all(
        color: missing ? const Color(0x82a45648) : const Color(0x78b9903e),
      ),
    ),
    child: Row(
      children: <Widget>[
        SizedBox(
          width: 24,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _ledgerPreviewItemIcon(row.name),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                row.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xff6b2e29),
                  fontFamily: 'Georgia',
                  fontSize: 7.2,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              Text(
                row.meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xff594731),
                  fontFamily: 'Georgia',
                  fontSize: 5.7,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 5),
        if (missing)
          Container(
            key: ValueKey<String>('ledger-preview-add:${row.name}'),
            width: 27,
            height: 17,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: IlluminatedLedgerSpec.lapisGradient,
              border: Border.all(color: const Color(0xffb9903e)),
            ),
            child: const Text(
              '+ ADD',
              style: TextStyle(
                color: Color(0xfff7eac7),
                fontFamily: 'Georgia',
                fontSize: 5.7,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          )
        else
          SizedBox(
            key: ValueKey<String>('ledger-preview-seal:${row.name}'),
            width: 17,
            height: 17,
            child: CustomPaint(
              painter: const LedgerWaxSealPainter(
                enabled: true,
                hovered: false,
                pressed: false,
                focused: false,
              ),
              child: const Center(
                child: AppVectorGlyph(
                  'check',
                  size: 7,
                  color: Color(0xfffff1bd),
                  tightBounds: true,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _ledgerPreviewItemIcon(String name) {
    final bytes = _ledgerPreviewIconBytes(_mode, name);
    return Container(
      key: ValueKey<String>('ledger-preview-icon:$name'),
      width: 20,
      height: 20,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: IlluminatedLedgerSpec.lapisGradient,
        border: Border.all(color: const Color(0xffc3a04b)),
        borderRadius: BorderRadius.circular(1),
      ),
      child: bytes == null
          ? _ledgerPreviewInitials(name)
          : Image.memory(
              bytes,
              key: ValueKey<String>('ledger-preview-art:$name'),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _ledgerPreviewInitials(name),
            ),
    );
  }

  Widget _ledgerPreviewInitials(String name) => Center(
    child: Text(
      _previewInitials(name),
      key: ValueKey<String>('ledger-preview-initials:$name'),
      style: const TextStyle(
        color: Color(0xfff7eac7),
        fontFamily: 'Georgia',
        fontSize: 6,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    ),
  );

  Widget _sakuraThemePreview() => Stack(
    key: const ValueKey<String>('sakura-theme-preview'),
    fit: StackFit.expand,
    children: <Widget>[
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: SakuraNightGardenSpec.canvasGradient,
        ),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
              'assets/sakura/materials/charcoal-plum-lacquer.png',
            ),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            opacity: .2,
          ),
        ),
      ),
      const IgnorePointer(
        child: CustomPaint(
          key: ValueKey<String>('sakura-theme-preview-cedar-grain'),
          painter: SakuraCedarGrainPainter(density: .68),
        ),
      ),
      Column(
        children: <Widget>[
          Container(
            height: 28,
            decoration: const BoxDecoration(
              color: Color(0xE6151414),
              image: DecorationImage(
                image: AssetImage(
                  'assets/sakura/materials/blackened-cedar.png',
                ),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                opacity: .48,
              ),
              border: Border(
                bottom: BorderSide(color: SakuraNightGardenSpec.darkCherrywood),
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const IgnorePointer(
                  child: CustomPaint(
                    painter: SakuraCedarGrainPainter(density: .46),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: <Widget>[
                      const Text(
                        'SAKURA NIGHT GARDEN',
                        style: TextStyle(
                          color: SakuraNightGardenSpec.warmIvory,
                          fontFamily: 'Georgia',
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: FittedBox(
                          key: ValueKey<String>(
                            'sakura-theme-preview-title-sprig',
                          ),
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: SakuraTitleSprigAsset(),
                        ),
                      ),
                      Text(
                        'LIVE THEME PREVIEW',
                        style: TextStyle(
                          color: SakuraNightGardenSpec.mutedText.withAlpha(210),
                          fontSize: 6,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  width: 82,
                  decoration: const BoxDecoration(
                    color: Color(0xED171315),
                    image: DecorationImage(
                      image: AssetImage(
                        'assets/sakura/materials/blackened-cedar.png',
                      ),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      opacity: .52,
                    ),
                    border: Border(
                      right: BorderSide(
                        color: SakuraNightGardenSpec.darkCherrywood,
                      ),
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      const IgnorePointer(
                        child: CustomPaint(
                          painter: SakuraCedarGrainPainter(
                            sidebar: true,
                            density: .58,
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 4,
                        right: 4,
                        bottom: 2,
                        height: 88,
                        child: FittedBox(
                          key: ValueKey<String>(
                            'sakura-theme-preview-sidebar-branch',
                          ),
                          fit: BoxFit.contain,
                          alignment: Alignment.bottomLeft,
                          child: SakuraSidebarBotanicalAsset(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 7, 6, 5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            const Text(
                              'BLACK DESERT',
                              style: TextStyle(
                                color: Color(0xFFD8B7AD),
                                fontFamily: 'Georgia',
                                fontSize: 5.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Text(
                              'Black Spirit\nLife',
                              style: TextStyle(
                                color: SakuraNightGardenSpec.warmIvory,
                                fontFamily: 'Georgia',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                height: .92,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _sakuraPreviewNav(
                              'compass',
                              'PLANNER',
                              active: true,
                            ),
                            _sakuraPreviewNav('spark', 'BONUS'),
                            _sakuraPreviewNav('vault', 'INVENTORY'),
                            _sakuraPreviewNav('quill', 'EDITOR'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
                    child: Column(
                      children: <Widget>[
                        SizedBox(
                          height: 32,
                          child: Row(
                            children: <Widget>[
                              _sakuraPreviewItemIcon(
                                'Harmony Draught - Edania',
                                size: 27,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Container(
                                  height: 27,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                  ),
                                  alignment: Alignment.centerLeft,
                                  decoration: BoxDecoration(
                                    gradient: SakuraNightGardenSpec
                                        .raisedSurfaceGradient,
                                    image: const DecorationImage(
                                      image: AssetImage(
                                        'assets/sakura/materials/'
                                        'charcoal-plum-lacquer.png',
                                      ),
                                      fit: BoxFit.cover,
                                      filterQuality: FilterQuality.high,
                                      opacity: .18,
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(
                                      color: SakuraNightGardenSpec.rosewood,
                                    ),
                                  ),
                                  child: const Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          'Harmony Draught - Edania',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color:
                                                SakuraNightGardenSpec.warmIvory,
                                            fontFamily: 'Georgia',
                                            fontSize: 7.2,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      AppVectorGlyph(
                                        'chevron-down',
                                        size: 8,
                                        color: SakuraNightGardenSpec.mutedText,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              _sakuraPreviewControl('Recipes', width: 48),
                              const SizedBox(width: 5),
                              _sakuraPreviewControl('100', width: 34),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Expanded(
                                flex: 96,
                                child: _sakuraPreviewPane(
                                  title: 'CRAFT QUEUE',
                                  meta: '42 LEFT',
                                  missing: false,
                                  rows: const <({String meta, String name})>[
                                    (
                                      name: 'Purified Water',
                                      meta: 'CRAFT 1,221',
                                    ),
                                    (
                                      name: 'Clear Liquid Reagent',
                                      meta: 'RESIDENCE ALCHEMY',
                                    ),
                                    (
                                      name: 'Pure Powder Reagent',
                                      meta: 'CRAFT 941',
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 104,
                                child: _sakuraPreviewPane(
                                  title: 'NEED FIRST',
                                  meta: '49 MISSING',
                                  missing: true,
                                  rows: const <({String meta, String name})>[
                                    (
                                      name: 'Trace of Nature',
                                      meta: 'MISSING 3,152',
                                    ),
                                    (name: 'Weeds', meta: 'MISSING 2,676'),
                                    (
                                      name: 'Sunrise Herb',
                                      meta: 'MISSING 1,359',
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
              ],
            ),
          ),
        ],
      ),
    ],
  );

  Widget _sakuraPreviewNav(String glyph, String label, {bool active = false}) =>
      Container(
        key: ValueKey<String>('sakura-preview-nav:${label.toLowerCase()}'),
        height: 20,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          gradient: active
              ? SakuraNightGardenSpec.sakuraLacquerGradient
              : SakuraNightGardenSpec.surfaceGradient,
          image: const DecorationImage(
            image: AssetImage(
              'assets/sakura/materials/charcoal-plum-lacquer.png',
            ),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            opacity: .2,
          ),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: active
                ? SakuraNightGardenSpec.dustySakura
                : SakuraNightGardenSpec.darkCherrywood,
          ),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 13,
              child: AppVectorGlyph(
                glyph,
                size: 9,
                color: active
                    ? SakuraNightGardenSpec.paleBlossom
                    : SakuraNightGardenSpec.mutedText,
              ),
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: active
                      ? SakuraNightGardenSpec.warmIvory
                      : SakuraNightGardenSpec.mutedText,
                  fontSize: 5.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _sakuraPreviewControl(String label, {required double width}) =>
      Container(
        width: width,
        height: 27,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: SakuraNightGardenSpec.raisedSurfaceGradient,
          image: const DecorationImage(
            image: AssetImage(
              'assets/sakura/materials/charcoal-plum-lacquer.png',
            ),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            opacity: .18,
          ),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: SakuraNightGardenSpec.rosewood),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(
            color: SakuraNightGardenSpec.warmIvory,
            fontSize: 6.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _sakuraPreviewPane({
    required String title,
    required String meta,
    required List<({String meta, String name})> rows,
    required bool missing,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      SizedBox(
        height: 20,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const Positioned.fill(child: SakuraSectionRuleAsset()),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: SakuraNightGardenSpec.warmIvory,
                      fontFamily: 'Georgia',
                      fontSize: 9.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  meta,
                  style: const TextStyle(
                    color: SakuraNightGardenSpec.mutedText,
                    fontSize: 5.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 3),
      for (var index = 0; index < rows.length; index++) ...<Widget>[
        Expanded(
          child: _sakuraPreviewRow(rows[index], index: index, missing: missing),
        ),
        if (index != rows.length - 1) const SizedBox(height: 3),
      ],
    ],
  );

  Widget _sakuraPreviewRow(
    ({String meta, String name}) row, {
    required int index,
    required bool missing,
  }) => Container(
    key: ValueKey<String>('sakura-preview-row:${row.name}'),
    constraints: const BoxConstraints(minHeight: 30),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      gradient: SakuraNightGardenSpec.surfaceGradient,
      image: const DecorationImage(
        image: AssetImage('assets/sakura/materials/charcoal-plum-lacquer.png'),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        opacity: .2,
      ),
      borderRadius: BorderRadius.circular(3),
      border: Border.all(
        color: missing
            ? SakuraNightGardenSpec.emberBerry.withAlpha(178)
            : SakuraNightGardenSpec.rosewood.withAlpha(188),
      ),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 3,
              color: missing
                  ? SakuraNightGardenSpec.emberBerry
                  : SakuraNightGardenSpec.dustySakura,
            ),
            const SizedBox(width: 3),
            _sakuraPreviewItemIcon(row.name),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SakuraNightGardenSpec.warmIvory,
                      fontFamily: 'Georgia',
                      fontSize: 6.6,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  Text(
                    row.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SakuraNightGardenSpec.mutedText,
                      fontSize: 5.1,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            if (missing)
              Container(
                key: ValueKey<String>('sakura-preview-add:${row.name}'),
                width: 25,
                height: 17,
                margin: const EdgeInsets.only(right: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: SakuraNightGardenSpec.sakuraLacquerGradient,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: SakuraNightGardenSpec.dustySakura),
                ),
                child: const Text(
                  '+ ADD',
                  style: TextStyle(
                    color: SakuraNightGardenSpec.warmIvory,
                    fontSize: 5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              Container(
                key: ValueKey<String>('sakura-preview-check:${row.name}'),
                width: 16,
                height: 16,
                margin: const EdgeInsets.only(left: 1, right: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: SakuraNightGardenSpec.mossGradient,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: SakuraNightGardenSpec.mutedMoss),
                ),
                child: const AppVectorGlyph(
                  'check',
                  size: 7,
                  color: SakuraNightGardenSpec.warmIvory,
                ),
              ),
          ],
        ),
        if (!missing)
          Positioned(
            right: 1,
            bottom: 1,
            width: 27,
            height: 15,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.bottomRight,
              child: SakuraQueueCornerAsset.fromIndex(index),
            ),
          ),
      ],
    ),
  );

  Widget _sakuraPreviewItemIcon(String name, {double size = 20}) {
    final bytes = _ledgerPreviewIconBytes(_mode, name);
    return Container(
      key: ValueKey<String>('sakura-preview-icon:$name'),
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SakuraNightGardenSpec.canvasDeep,
        border: Border.all(color: SakuraNightGardenSpec.barkCopper),
        borderRadius: BorderRadius.circular(2),
      ),
      child: bytes == null
          ? Center(
              child: Text(
                _previewInitials(name),
                key: ValueKey<String>('sakura-preview-initials:$name'),
                style: const TextStyle(
                  color: SakuraNightGardenSpec.warmIvory,
                  fontFamily: 'Georgia',
                  fontSize: 5.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : Image.memory(
              bytes,
              key: ValueKey<String>('sakura-preview-art:$name'),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Center(
                child: Text(
                  _previewInitials(name),
                  style: const TextStyle(
                    color: SakuraNightGardenSpec.warmIvory,
                    fontSize: 5.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
    );
  }

  // Retained for a possible future advanced-appearance mode. It is
  // deliberately not exposed in the streamlined Themes + Motion screen.
  // ignore: unused_element
  Widget _sceneChoices(AppearanceSettings appearance) => _choiceGrid(
    columns: 2,
    children: <Widget>[
      for (final scene in StandardSpec.scenes.values)
        _sceneCard(
          id: 'A04:${scene.id}',
          blurId: scene.id == StandardSpec.scenes.keys.first
              ? 'A07'
              : 'A07:${scene.id}',
          title: scene.displayName,
          selected: appearance.background == scene.id,
          height: 188,
          onPressed: () => _selectShared(scene.id),
          preview: RetainedAssetImage(
            assetPath: scene.assetPath,
            assetLabel: '${scene.displayName} preview',
            failureKey: ValueKey<String>(
              'appearance-scene-asset-failure:${scene.id}',
            ),
            fit: BoxFit.cover,
          ),
        ),
    ],
  );

  // ignore: unused_element
  Widget _plainChoices(AppearanceSettings appearance) => _choiceGrid(
    columns: 3,
    children: <Widget>[
      for (final plain in StandardSpec.plainBackgrounds.values)
        _sceneCard(
          id: 'A06:${plain.id}',
          blurId: 'A07:${plain.id}',
          title: plain.displayName,
          selected: appearance.background == plain.id,
          height: 142,
          onPressed: () => _selectShared(plain.id),
          plain: true,
          preview: DecoratedBox(
            decoration: BoxDecoration(gradient: plain.gradient),
          ),
        ),
    ],
  );

  Widget _choiceGrid({required int columns, required List<Widget> children}) =>
      LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: <Widget>[
              for (final child in children)
                SizedBox(width: width, child: child),
            ],
          );
        },
      );

  Widget _sceneCard({
    required String id,
    required String blurId,
    required String title,
    required bool selected,
    required double height,
    required VoidCallback onPressed,
    required Widget preview,
    bool plain = false,
  }) {
    final spec = context.visualTheme;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Semantics(
            button: true,
            selected: selected,
            label: '$id Select $title',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey<String>(id),
                onTap: onPressed,
                borderRadius: BorderRadius.circular(8),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? spec.palette.primaryBright
                          : spec.palette.trim.withAlpha(150),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        preview,
                        if (plain)
                          Container(
                            margin: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: const Color(0x45fff1b9),
                              ),
                            ),
                          ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Color(0x18000000),
                                Color(0x4e000000),
                                Color(0xc6000000),
                              ],
                              stops: <double>[0, .62, 1],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 10,
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xfffff0d0),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(top: 8, right: 8, child: _blurControl(blurId)),
        ],
      ),
    );
  }

  Widget _transitionChoices(AppearanceSettings appearance) {
    final selected = !appearance.tabFade ? 'off' : appearance.tabTransition;
    final spec = context.visualTheme;
    final baseFontSize = spec.typography.body.fontSize ?? 14;
    final textScale =
        MediaQuery.textScalerOf(context).scale(baseFontSize) / baseFontSize;
    final widthScale = textScale.clamp(1.0, 1.55).toDouble();
    final fieldHeight = textScale > 1.25 ? 52.0 : 40.0;
    final labelStyle = spec.typography.label.copyWith(
      color: spec.palette.textMuted,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: <Widget>[
        SizedBox(
          key: const ValueKey<String>('A09:transition-field'),
          width: 128 * widthScale,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('TAB TRANSITION', style: labelStyle),
              const SizedBox(height: 4),
              SizedBox(
                height: fieldHeight,
                child: AppSelect<String>(
                  key: const ValueKey<String>('A09'),
                  value: selected,
                  items: const <String>['off', 'fade', 'slide', 'lift'],
                  labelFor: _title,
                  semanticLabel: 'A09 Tab transition selector',
                  onChanged: (value) {
                    if (value == null) return;
                    _update(
                      (source) => AppearanceActions.transition(source, value),
                      immediate: true,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          key: const ValueKey<String>('A09:speed-field'),
          width: 144 * widthScale,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('TRANSITION SPEED', style: labelStyle),
              const SizedBox(height: 4),
              SizedBox(
                height: fieldHeight,
                child: AppSelect<String>(
                  key: const ValueKey<String>('A09:speed'),
                  value: appearance.tabTransitionSpeed,
                  items: const <String>['slow', 'normal', 'fast'],
                  labelFor: _title,
                  semanticLabel: 'A09 Transition speed selector',
                  onChanged: selected == 'off'
                      ? null
                      : (value) {
                          if (value == null) return;
                          _update(
                            (source) => AppearanceActions.transitionSpeed(
                              source,
                              value,
                            ),
                            immediate: true,
                          );
                        },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _particleControls(AppearanceSettings appearance) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text('Style', style: context.visualTheme.typography.label),
      const SizedBox(height: 6),
      _choiceGrid(
        columns: 2,
        children: <Widget>[
          for (final style in AppearanceActions.visibleParticleStyles)
            AppChoiceChip(
              key: ValueKey<String>('A11:$style'),
              label: _particleStyleLabel(style),
              selected: appearance.particleStyle == style,
              onSelected: (_) => _update(
                (source) => AppearanceActions.particleStyle(source, style),
                immediate: true,
              ),
            ),
        ],
      ),
      const SizedBox(height: 14),
      _colorControls(
        actionPrefix: 'particle',
        label: 'Particle color',
        wheelId: 'A12',
        swatchId: 'A13',
        sliderId: 'A14',
        modeId: 'A15',
        hue: appearance.particleHue,
        defaultActive:
            !appearance.particleCustomColor &&
            !appearance.particleRainbow &&
            !appearance.particleNeon,
        rainbow: appearance.particleRainbow,
        neon: appearance.particleNeon,
        onHue: (value) =>
            _update((source) => AppearanceActions.particleHue(source, value)),
        onDefault: () =>
            _update(AppearanceActions.particleDefault, immediate: true),
        onRainbow: (value) => _update(
          (source) => AppearanceActions.particleRainbow(source, value),
          immediate: true,
        ),
        onNeon: (value) => _update(
          (source) =>
              AppearanceActions.copyAppearance(source, particleNeon: value),
          immediate: true,
        ),
      ),
      const SizedBox(height: 14),
      _slider(
        id: 'A18:speed',
        label: 'Animation speed',
        value: appearance.motionSpeed,
        onChanged: (value) => _update(
          (source) =>
              AppearanceActions.copyAppearance(source, motionSpeed: value),
        ),
      ),
      _slider(
        id: 'A18:strength',
        label: 'Motion strength',
        value: appearance.motionIntensity,
        onChanged: (value) => _update(
          (source) =>
              AppearanceActions.copyAppearance(source, motionIntensity: value),
        ),
      ),
      _slider(
        id: 'A18:density',
        label: 'Density',
        value: appearance.particleDensity,
        onChanged: (value) => _update(
          (source) =>
              AppearanceActions.copyAppearance(source, particleDensity: value),
        ),
      ),
      _slider(
        id: 'A18:opacity',
        label: 'Opacity',
        value: appearance.particleOpacity,
        onChanged: (value) => _update(
          (source) =>
              AppearanceActions.copyAppearance(source, particleOpacity: value),
        ),
      ),
      _slider(
        id: 'A18:blur',
        label: 'Particle blur',
        value: appearance.particleBlur,
        valueText: (value) => '${(value * 12).toStringAsFixed(1)}px',
        onChanged: (value) => _update(
          (source) =>
              AppearanceActions.copyAppearance(source, particleBlur: value),
        ),
      ),
      _slider(
        id: 'A19',
        label: 'Minimum size',
        value: appearance.particleMinSize,
        min: .45,
        max: 2.2,
        valueText: (value) => '${value.toStringAsFixed(2)}x',
        onChanged: (value) => _update(
          (source) => AppearanceActions.particleMinimum(source, value),
        ),
      ),
      _slider(
        id: 'A20',
        label: 'Maximum size',
        value: appearance.particleMaxSize,
        min: .45,
        max: 2.2,
        valueText: (value) => '${value.toStringAsFixed(2)}x',
        onChanged: (value) => _update(
          (source) => AppearanceActions.particleMaximum(source, value),
        ),
      ),
    ],
  );

  // ignore: unused_element
  Widget _buttonControls(AppearanceSettings appearance) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _choiceGrid(
        columns: 2,
        children: <Widget>[
          for (final effect in AppearanceActions.buttonEffects)
            AppChoiceChip(
              key: ValueKey<String>('A22:$effect'),
              label: _buttonEffectLabel(effect),
              selected: appearance.buttonEffect == effect,
              onSelected: (_) => _update(
                (source) => AppearanceActions.buttonEffect(source, effect),
                immediate: true,
              ),
            ),
        ],
      ),
      const SizedBox(height: 14),
      _colorControls(
        actionPrefix: 'button',
        label: 'Button effect color',
        wheelId: 'A23',
        swatchId: 'A23:swatch',
        sliderId: 'A23:slider',
        modeId: 'A24',
        hue: appearance.buttonEffectHue,
        defaultActive:
            !appearance.buttonEffectCustomColor &&
            !appearance.buttonEffectRainbow &&
            !appearance.buttonEffectNeon,
        rainbow: appearance.buttonEffectRainbow,
        neon: appearance.buttonEffectNeon,
        onHue: (value) =>
            _update((source) => AppearanceActions.buttonHue(source, value)),
        onDefault: () =>
            _update(AppearanceActions.buttonDefault, immediate: true),
        onRainbow: (value) => _update(
          (source) => AppearanceActions.buttonRainbow(source, value),
          immediate: true,
        ),
        onNeon: (value) => _update(
          (source) =>
              AppearanceActions.copyAppearance(source, buttonEffectNeon: value),
          immediate: true,
        ),
      ),
      const SizedBox(height: 14),
      _slider(
        id: 'A25:speed',
        label: 'Effect speed',
        value: appearance.buttonEffectSpeed,
        onChanged: (value) => _update(
          (source) => AppearanceActions.copyAppearance(
            source,
            buttonEffectSpeed: value,
          ),
        ),
      ),
      _slider(
        id: 'A25:strength',
        label: 'Effect strength',
        value: appearance.buttonEffectIntensity,
        onChanged: (value) => _update(
          (source) => AppearanceActions.copyAppearance(
            source,
            buttonEffectIntensity: value,
          ),
        ),
      ),
      _slider(
        id: 'A25:blur',
        label: 'Effect blur',
        value: appearance.buttonEffectBlur,
        valueText: (value) => '${(value * 8).toStringAsFixed(1)}px',
        onChanged: (value) => _update(
          (source) =>
              AppearanceActions.copyAppearance(source, buttonEffectBlur: value),
        ),
      ),
      AppToggle(
        key: const ValueKey<String>('A26'),
        value: appearance.buttonEffectActiveOnly,
        label: 'ACTIVE TABS ONLY',
        onChanged: (value) => _update(
          (source) => AppearanceActions.copyAppearance(
            source,
            buttonEffectActiveOnly: value,
          ),
          immediate: true,
        ),
      ),
    ],
  );

  Widget _colorControls({
    required String actionPrefix,
    required String label,
    required String wheelId,
    required String swatchId,
    required String sliderId,
    required String modeId,
    required double hue,
    required bool defaultActive,
    required bool rainbow,
    required bool neon,
    required ValueChanged<double> onHue,
    required VoidCallback onDefault,
    required ValueChanged<bool> onRainbow,
    required ValueChanged<bool> onNeon,
  }) => _AppearanceColorControls(
    key: ValueKey<String>('appearance-color:$actionPrefix'),
    actionPrefix: actionPrefix,
    label: label,
    wheelId: wheelId,
    swatchId: swatchId,
    sliderId: sliderId,
    modeId: modeId,
    hue: hue,
    defaultActive: defaultActive,
    rainbow: rainbow,
    neon: neon,
    onHue: onHue,
    onDefault: onDefault,
    onRainbow: onRainbow,
    onNeon: onNeon,
  );

  Widget _slider({
    required String id,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    double min = 0,
    double max = 1,
    String Function(double value)? valueText,
  }) {
    final formatted = valueText?.call(value) ?? '${(value * 100).round()}%';
    return Row(
      children: <Widget>[
        SizedBox(
          width: 142,
          child: Text(label, style: context.visualTheme.typography.meta),
        ),
        Expanded(
          child: AppSlider(
            key: ValueKey<String>(id),
            value: value,
            min: min,
            max: max,
            label: formatted,
            semanticLabel: '$id $label',
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 54,
          child: Text(
            formatted,
            key: ValueKey<String>('$id:readout'),
            textAlign: TextAlign.right,
            style: context.visualTheme.typography.meta.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _blurControl(String id) => AnchoredPopover(
    overlayId: 'appearance:scene-blur',
    preferredWidth: 360,
    maximumHeight: 260,
    popoverBuilder: (context, close) => AppSurface(
      role: AppSurfaceRole.popup,
      semanticLabel: 'A07 Scene blur control',
      child: ValueListenableBuilder<ModeState>(
        valueListenable: _mode.state,
        builder: (context, state, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const AnchoredPopoverDragRegion(
              child: SectionHeader(title: 'Backdrop Blur'),
            ),
            const SizedBox(height: 12),
            AppSlider(
              key: const ValueKey<String>('A08'),
              value: state.appearance.backdropBlur,
              min: 0,
              max: 1,
              divisions: 100,
              label: '${(state.appearance.backdropBlur * 12).round()} px',
              semanticLabel: 'A08 Shared backdrop blur',
              onChanged: (value) => _update(
                (source) => AppearanceActions.copyAppearance(
                  source,
                  backdropBlur: value,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton.label(
                'Done',
                semanticLabel: 'Close scene blur control',
                onPressed: close,
              ),
            ),
          ],
        ),
      ),
    ),
    anchorBuilder: (context, toggle, isShowing) => Tooltip(
      message: 'Backdrop blur',
      child: Semantics(
        button: true,
        label: '$id Scene blur control, ${isShowing ? 'open' : 'closed'}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey<String>(id),
            onTap: toggle,
            borderRadius: BorderRadius.circular(99),
            child: Ink(
              width: 34,
              height: 28,
              decoration: BoxDecoration(
                color: context.visualTheme.palette.surfaceInset.withAlpha(190),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: context.visualTheme.palette.trimBright.withAlpha(190),
                ),
              ),
              child: AppVectorGlyph(
                'blur',
                size: 17,
                color: context.visualTheme.palette.text,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _AppearanceColorControls extends StatefulWidget {
  const _AppearanceColorControls({
    required this.actionPrefix,
    required this.label,
    required this.wheelId,
    required this.swatchId,
    required this.sliderId,
    required this.modeId,
    required this.hue,
    required this.defaultActive,
    required this.rainbow,
    required this.neon,
    required this.onHue,
    required this.onDefault,
    required this.onRainbow,
    required this.onNeon,
    super.key,
  });

  final String actionPrefix;
  final String label;
  final String wheelId;
  final String swatchId;
  final String sliderId;
  final String modeId;
  final double hue;
  final bool defaultActive;
  final bool rainbow;
  final bool neon;
  final ValueChanged<double> onHue;
  final VoidCallback onDefault;
  final ValueChanged<bool> onRainbow;
  final ValueChanged<bool> onNeon;

  @override
  State<_AppearanceColorControls> createState() =>
      _AppearanceColorControlsState();
}

class _AppearanceColorControlsState extends State<_AppearanceColorControls> {
  late double _wheelHue = _normalizeHue(widget.hue);
  late double _sliderHue = _wheelHue;
  double? _pendingLocalHue;

  @override
  void didUpdateWidget(_AppearanceColorControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = _normalizeHue(widget.hue);
    final pending = _pendingLocalHue;
    if (pending != null && _huesMatch(incoming, pending)) {
      _pendingLocalHue = null;
      return;
    }
    if (!_huesMatch(incoming, _wheelHue) ||
        !_huesMatch(widget.hue, oldWidget.hue)) {
      _wheelHue = incoming;
      _sliderHue = incoming;
    }
  }

  double _normalizeHue(double value) => (value % 360 + 360) % 360;

  bool _huesMatch(double first, double second) {
    final delta = (_normalizeHue(first) - _normalizeHue(second)).abs();
    return math.min(delta, 360 - delta) < .001;
  }

  void _selectFromWheel(double value) {
    final next = _normalizeHue(value);
    setState(() {
      _wheelHue = next;
      _pendingLocalHue = next;
    });
    widget.onHue(next);
  }

  void _selectFromSlider(double value) {
    final next = _normalizeHue(value);
    setState(() {
      _wheelHue = next;
      _sliderHue = next;
      _pendingLocalHue = next;
    });
    widget.onHue(next);
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final colorModes = Wrap(
      spacing: 7,
      runSpacing: 7,
      children: <Widget>[
        AppButton.label(
          'Default',
          key: ValueKey<String>(widget.modeId),
          semanticLabel:
              '${widget.modeId} ${widget.actionPrefix} color default',
          selected: widget.defaultActive,
          onPressed: widget.onDefault,
          minimumSize: const Size(82, 34),
        ),
        AppChoiceChip(
          key: ValueKey<String>(
            widget.modeId == 'A15' ? 'A16' : '${widget.modeId}:rainbow',
          ),
          label: 'Rainbow',
          selected: widget.rainbow,
          onSelected: widget.onRainbow,
        ),
        AppChoiceChip(
          key: ValueKey<String>(
            widget.modeId == 'A15' ? 'A17' : '${widget.modeId}:neon',
          ),
          label: 'Neon',
          selected: widget.neon,
          onSelected: widget.onNeon,
        ),
      ],
    );
    final palettes = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 115,
          child: Wrap(
            spacing: 5,
            runSpacing: 5,
            children: <Widget>[
              for (final value in AppearanceActions.particleSwatches)
                InkWell(
                  key: ValueKey<String>('${widget.swatchId}:${value.round()}'),
                  onTap: () => _selectFromWheel(value),
                  borderRadius: BorderRadius.circular(99),
                  child: Semantics(
                    button: true,
                    label: '${widget.swatchId} Select hue ${value.round()}',
                    child: Container(
                      width: 25,
                      height: 25,
                      decoration: BoxDecoration(
                        color: HSVColor.fromAHSV(1, value, .72, .9).toColor(),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _huesMatch(_wheelHue, value)
                              ? spec.palette.text
                              : spec.palette.trim,
                          width: _huesMatch(_wheelHue, value) ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        colorModes,
      ],
    );
    final wheel = HueWheel(
      key: ValueKey<String>(widget.wheelId),
      hue: _wheelHue,
      onChanged: _selectFromWheel,
      semanticLabel: '${widget.wheelId} ${widget.actionPrefix} hue wheel',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                widget.label.toUpperCase(),
                style: spec.typography.label.copyWith(
                  color: spec.palette.trimBright,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${_wheelHue.round()} deg',
              key: ValueKey<String>('${widget.wheelId}:readout'),
              style: spec.typography.meta.copyWith(
                color: spec.palette.trimBright,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 360) {
              return Column(
                children: <Widget>[
                  wheel,
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerLeft, child: palettes),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                wheel,
                const SizedBox(width: 12),
                Expanded(child: palettes),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            SizedBox(
              width: 44,
              child: Text('Hue', style: spec.typography.meta),
            ),
            Expanded(
              child: AppSlider(
                key: ValueKey<String>(widget.sliderId),
                value: _sliderHue,
                min: 0,
                max: 360,
                divisions: 360,
                label: '${_sliderHue.round()} deg',
                semanticLabel: '${widget.sliderId} ${widget.actionPrefix} hue',
                onChanged: _selectFromSlider,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 58,
              child: Text(
                '${_sliderHue.round()} deg',
                key: ValueKey<String>('${widget.sliderId}:readout'),
                textAlign: TextAlign.right,
                style: spec.typography.meta.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class HueWheel extends StatefulWidget {
  const HueWheel({
    required this.hue,
    required this.onChanged,
    required this.semanticLabel,
    super.key,
  });

  final double hue;
  final ValueChanged<double> onChanged;
  final String semanticLabel;

  static const int segmentCount = 120;
  static const double minimumDimension = 128;
  static const double preferredDimension = 148;
  static const double keyboardStep = 3;

  @override
  State<HueWheel> createState() => _HueWheelState();
}

class _HueWheelState extends State<HueWheel> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Hue wheel');
  bool _focused = false;

  double _normalized(double value) => (value % 360 + 360) % 360;

  void _adjust(double delta) =>
      widget.onChanged(_normalized(widget.hue + delta));

  void _update(Offset localPosition, Size size) {
    final center = size.center(Offset.zero);
    final delta = localPosition - center;
    final degrees = math.atan2(delta.dy, delta.dx) * 180 / math.pi + 90;
    widget.onChanged(_normalized(degrees));
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowRight) {
      _adjust(HueWheel.keyboardStep);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft) {
      _adjust(-HueWheel.keyboardStep);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      slider: true,
      focusable: true,
      focused: _focused,
      label: widget.semanticLabel,
      value: '${widget.hue.round()} degrees',
      increasedValue:
          '${_normalized(widget.hue + HueWheel.keyboardStep).round()} degrees',
      decreasedValue:
          '${_normalized(widget.hue - HueWheel.keyboardStep).round()} degrees',
      onIncrease: () => _adjust(HueWheel.keyboardStep),
      onDecrease: () => _adjust(-HueWheel.keyboardStep),
      child: Focus(
        focusNode: _focusNode,
        onFocusChange: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        onKeyEvent: _onKeyEvent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final boundedWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : HueWheel.preferredDimension;
            final boundedHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : HueWheel.preferredDimension;
            final available = math.min(boundedWidth, boundedHeight);
            final dimension = available
                .clamp(HueWheel.minimumDimension, HueWheel.preferredDimension)
                .toDouble();
            final size = Size.square(dimension);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (event) {
                _focusNode.requestFocus();
                _update(event.localPosition, size);
              },
              onPanStart: (event) {
                _focusNode.requestFocus();
                _update(event.localPosition, size);
              },
              onPanUpdate: (event) => _update(event.localPosition, size),
              child: SizedBox.fromSize(
                size: size,
                child: CustomPaint(
                  painter: _HueWheelPainter(widget.hue, focused: _focused),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HueWheelPainter extends CustomPainter {
  const _HueWheelPainter(this.hue, {required this.focused});

  final double hue;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius + 4,
      Paint()
        ..color = focused ? const Color(0xfff0bc70) : const Color(0xff121014)
        ..style = PaintingStyle.stroke
        ..strokeWidth = focused ? 4 : 3,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xff17141a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 24,
    );
    final segmentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18;
    const segmentDegrees = 360 / HueWheel.segmentCount;
    for (var index = 0; index < HueWheel.segmentCount; index++) {
      segmentPaint.color = HSVColor.fromAHSV(
        1,
        index * segmentDegrees,
        .88,
        .96,
      ).toColor();
      canvas.drawArc(
        rect,
        (index * segmentDegrees - 90) * math.pi / 180,
        segmentDegrees * 1.08 * math.pi / 180,
        false,
        segmentPaint,
      );
    }
    canvas.drawCircle(
      center,
      radius - 10,
      Paint()
        ..color = const Color(0xffd7a15e)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawCircle(
      center,
      radius - 12,
      Paint()
        ..shader = const RadialGradient(
          colors: <Color>[Color(0xff25202a), Color(0xff0c0a0e)],
        ).createShader(Rect.fromCircle(center: center, radius: radius - 12)),
    );
    final angle = (hue - 90) * math.pi / 180;
    final marker = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    canvas.drawCircle(marker, 10, Paint()..color = const Color(0xff151117));
    canvas.drawCircle(marker, 7.5, Paint()..color = const Color(0xffe6ad62));
    canvas.drawCircle(
      marker,
      5.2,
      Paint()
        ..color = HSVColor.fromAHSV(
          1,
          (hue % 360 + 360) % 360,
          .9,
          1,
        ).toColor(),
    );
  }

  @override
  bool shouldRepaint(covariant _HueWheelPainter oldDelegate) =>
      oldDelegate.hue != hue || oldDelegate.focused != focused;
}

String _title(String value) => value
    .split(RegExp(r'[_\s]+'))
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

final Map<String, Uint8List?> _ledgerPreviewDecodedIconCache =
    <String, Uint8List?>{};

Uint8List? _ledgerPreviewIconBytes(
  ModeFeatureController controller,
  String name,
) {
  final stateAlias = _previewMapValue(controller.state.value.iconAliases, name);
  final bundledAlias = _previewLooseMapValue(
    controller.owner.catalog.supportingData['iconAliases'],
    name,
  );
  final names = <String>[
    name,
    if (stateAlias != null && stateAlias.trim().isNotEmpty) stateAlias.trim(),
    if (bundledAlias != null && bundledAlias.trim().isNotEmpty)
      bundledAlias.trim(),
  ];
  final modes = <ModeFeatureController>[
    controller,
    for (final candidate in controller.owner.modes.values)
      if (!identical(candidate, controller)) candidate,
  ];
  String? uri;
  for (final mode in modes) {
    final icons = controller.owner.catalog.forMode(mode.mode).iconDataUris;
    for (final candidate in names) {
      uri = _previewMapValue(icons, candidate);
      if (uri != null && uri.trim().isNotEmpty) break;
    }
    if (uri != null && uri.trim().isNotEmpty) break;
  }
  if (uri == null || uri.trim().isEmpty) return null;
  final data = uri.trim();
  if (_ledgerPreviewDecodedIconCache.containsKey(data)) {
    return _ledgerPreviewDecodedIconCache[data];
  }
  Uint8List? result;
  try {
    final comma = data.indexOf(',');
    final encoded = comma < 0 ? data : data.substring(comma + 1);
    final decoded = base64Decode(encoded);
    if (decoded.isNotEmpty) result = decoded;
  } on FormatException {
    result = null;
  }
  _ledgerPreviewDecodedIconCache[data] = result;
  return result;
}

String? _previewMapValue(Map<String, String> source, String key) {
  final exact = source[key];
  if (exact != null) return exact;
  final folded = key.toLowerCase();
  for (final entry in source.entries) {
    if (entry.key.toLowerCase() == folded) return entry.value;
  }
  return null;
}

String? _previewLooseMapValue(Object? source, String key) {
  if (source is! Map) return null;
  final exact = source[key];
  if (exact != null) return exact.toString();
  final folded = key.toLowerCase();
  for (final entry in source.entries) {
    if (entry.key.toString().toLowerCase() == folded) {
      return entry.value?.toString();
    }
  }
  return null;
}

String _previewInitials(String name) {
  final parts = name
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2);
  final initials = parts.map((part) => part[0]).join().toUpperCase();
  return initials.isEmpty ? '?' : initials;
}

String _particleStyleLabel(String style) => switch (style) {
  'embers' => 'Embers',
  'snow' => 'Falling snow',
  'bubbles' => 'Rising bubbles',
  'fireflies' => 'Fireflies',
  'petals' => 'Falling leaves',
  _ => _title(style),
};

String _buttonEffectLabel(String effect) => switch (effect) {
  'quiet' => 'Still glass',
  'glow' => 'Breathing glow',
  'orbit' => 'Animated border',
  'sweep' => 'Light sweep',
  'embers' => 'Ember trace',
  'frost' => 'Frost trace',
  'fireflies' => 'Firefly glints',
  _ => _title(effect),
};
