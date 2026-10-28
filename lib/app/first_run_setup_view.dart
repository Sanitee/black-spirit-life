import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/market/market_calculations.dart';
import '../domain/state/planner_state.dart';
import '../features/data/market_bonus_icon.dart';
import '../features/data/profile_presentation.dart';
import '../features/shared/profile_game_icon.dart';
import '../visual/components/app_button.dart';
import '../visual/components/app_form_controls.dart';
import '../visual/components/app_surface.dart';
import '../visual/foundations/theme_spec.dart';
import 'first_run_setup.dart';
import 'window/app_startup_frame.dart';

class FirstRunSetupView extends StatefulWidget {
  const FirstRunSetupView({
    required this.document,
    required this.groups,
    required this.busy,
    required this.error,
    required this.onSkip,
    required this.onFinish,
    super.key,
  });
  final PlannerState document;
  final List<FirstRunSetupGroup> groups;
  final bool busy;
  final Object? error;
  final VoidCallback onSkip;
  final ValueChanged<FirstRunSetupAnswers> onFinish;
  @override
  State<FirstRunSetupView> createState() => _FirstRunSetupViewState();
}

class _FirstRunSetupViewState extends State<FirstRunSetupView> {
  late final TextEditingController _alchemy,
      _cooking,
      _processing,
      _maximum,
      _current,
      _free;
  late bool _mass, _pack, _ring;
  late int _feathery;
  late double _fame;
  FirstRunSetupGroup? _open;
  bool _editing = false;
  List<FirstRunSetupGroup> get _groups =>
      widget.groups.isEmpty ? FirstRunSetupSchema.groups : widget.groups;

  @override
  void initState() {
    super.initState();
    final a = FirstRunSetupAnswers.forInitialDisplay(
      widget.document,
    ).normalized();
    _alchemy = TextEditingController(text: '${a.alchemyMastery}');
    _cooking = TextEditingController(text: '${a.cookingMastery}');
    _processing = TextEditingController(text: '${a.processingMastery}');
    _maximum = TextEditingController(text: _quantity(a.maximumWeightLt));
    _current = TextEditingController(text: _quantity(a.currentCarriedWeightLt));
    _free = TextEditingController(text: _quantity(a.safetyBufferLt));
    _mass = a.useMassProcessing;
    _pack = a.valuePack;
    _ring = a.merchantRing;
    _feathery = a.featheryStepsLevel;
    _fame = a.familyFameBonus;
    _open = _groups.first;
  }

  @override
  void dispose() {
    for (final c in [
      _alchemy,
      _cooking,
      _processing,
      _maximum,
      _current,
      _free,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  FirstRunSetupAnswers? get _answers {
    final a = _mastery(_alchemy.text),
        c = _mastery(_cooking.text),
        p = _mastery(_processing.text);
    final m = _parseQuantity(_maximum.text),
        w = _parseQuantity(_current.text),
        f = _parseQuantity(_free.text);
    if (a == null ||
        c == null ||
        p == null ||
        m == null ||
        w == null ||
        f == null) {
      return null;
    }
    return FirstRunSetupAnswers(
      alchemyMastery: a,
      cookingMastery: c,
      processingMastery: p,
      useMassProcessing: _mass,
      maximumWeightLt: m,
      currentCarriedWeightLt: w,
      safetyBufferLt: f,
      featheryStepsLevel: _feathery,
      valuePack: _pack,
      merchantRing: _ring,
      familyFameBonus: _fame,
    );
  }

  // Hidden, previously completed groups must not enable an empty pending section.
  bool get _canSave {
    final a = _answers;
    if (a == null) return false;
    return _groups.any(
      (g) => switch (g) {
        FirstRunSetupGroup.masteryAndOutput =>
          a.alchemyMastery > 0 ||
              a.cookingMastery > 0 ||
              a.processingMastery > 0 ||
              a.useMassProcessing,
        FirstRunSetupGroup.afkLoad =>
          a.maximumWeightLt > 0 ||
              a.currentCarriedWeightLt > 0 ||
              a.safetyBufferLt > 0 ||
              a.featheryStepsLevel > 0,
        FirstRunSetupGroup.marketSales =>
          a.valuePack || a.merchantRing || a.familyFameBonus != 0,
      },
    );
  }

  double get _net => marketNetRate(
    MarketTax(
      enabled: true,
      valuePack: _pack,
      merchantRing: _ring,
      familyFameBonus: _fame,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.visualTheme.palette;
    return AppStartupFrame(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Black Spirit Life first run setup',
              child: AppSurface(
                key: const ValueKey('first-run-setup-panel'),
                role: AppSurfaceRole.modal,
                padding: EdgeInsets.zero,
                semanticLabel: 'First run setup',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Set up your planner',
                          key: const ValueKey('first-run-setup-title'),
                          style: ProfileTypography.section(context),
                        ),
                      ),
                    ),
                    Divider(height: 1, color: p.trim.withValues(alpha: .45)),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < _groups.length; i++) ...[
                              if (i > 0) const SizedBox(height: 10),
                              _section(context, _groups[i]),
                            ],
                            if ((_editing && _answers == null) ||
                                widget.error != null) ...[
                              const SizedBox(height: 12),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _answers == null
                                      ? 'Use zero or a positive number.'
                                      : 'The setup was not saved. Your previous planner values are still active. ${widget.error}',
                                  key: const ValueKey('first-run-setup-error'),
                                  style: ProfileTypography.label(
                                    context,
                                  ).copyWith(color: p.danger),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Divider(height: 1, color: p.trim.withValues(alpha: .45)),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: _actions(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, FirstRunSetupGroup g) {
    final p = context.visualTheme.palette, open = _open == g;
    final summary = switch (g) {
      FirstRunSetupGroup.masteryAndOutput =>
        [
              _alchemy,
              _cooking,
              _processing,
            ].any((c) => (_mastery(c.text) ?? 0) > 0)
            ? '3 skills'
            : '0 mastery',
      FirstRunSetupGroup.afkLoad =>
        '${_maximum.text.isEmpty ? '0' : _maximum.text} LT',
      FirstRunSetupGroup.marketSales => _percent(_net),
    };
    final icon = switch (g) {
      FirstRunSetupGroup.masteryAndOutput => const ProfileIcon(
        artwork: ProfileArtwork.alchemy,
        size: 24,
      ),
      FirstRunSetupGroup.afkLoad => const ProfileIcon(
        artwork: ProfileArtwork.weight,
        size: 24,
      ),
      FirstRunSetupGroup.marketSales => const MarketBonusIcon(
        artwork: MarketBonusArtwork.valuePack,
        size: 25,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surfaceInset,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: open ? p.primaryBright : p.trim),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            expanded: open,
            child: AppButton(
              key: ValueKey('setup-section-${g.name}'),
              role: AppButtonRole.optionPill,
              selected: open,
              minimumSize: const Size(0, 54),
              padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
              semanticLabel: g.title,
              onPressed: widget.busy
                  ? null
                  : () => setState(() {
                      _open = open ? null : g;
                    }),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [p.trimBright, p.trim, p.surfaceInset],
                      ),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: p.trimBright.withValues(alpha: .6),
                      ),
                    ),
                    child: ExcludeSemantics(child: icon),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      g.title,
                      style: ProfileTypography.group(context),
                    ),
                  ),
                  if (!open) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        summary,
                        textAlign: TextAlign.end,
                        style: ProfileTypography.label(context),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Icon(
                    open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18,
                    color: p.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.all(14),
              child: switch (g) {
                FirstRunSetupGroup.masteryAndOutput => _masteryPage(context),
                FirstRunSetupGroup.afkLoad => _weightPage(context),
                FirstRunSetupGroup.marketSales => _marketPage(context),
              },
            ),
        ],
      ),
    );
  }

  Widget _masteryPage(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, c) {
          final stacked = c.maxWidth < 420 * _scale(context, 14);
          final fields = [
            _masteryCard(
              context,
              'Alchemy',
              ProfileArtwork.alchemy,
              'setup-alchemy-mastery',
              _alchemy,
              stacked,
            ),
            _masteryCard(
              context,
              'Cooking',
              ProfileArtwork.cooking,
              'setup-cooking-mastery',
              _cooking,
              stacked,
            ),
            _masteryCard(
              context,
              'Processing',
              ProfileArtwork.processing,
              'setup-processing-mastery',
              _processing,
              stacked,
            ),
          ];
          return stacked
              ? Column(children: _vertical(fields, 10))
              : Row(children: _horizontal(fields, 10));
        },
      ),
      const SizedBox(height: 12),
      _toggle(
        context,
        key: 'setup-mass-processing',
        label: 'Mass processing stone',
        leading: const ProfileIcon(
          artwork: ProfileArtwork.processing,
          size: 22,
        ),
        value: _mass,
        onChanged: (v) => setState(() => _mass = v),
      ),
    ],
  );
  Widget _masteryCard(
    BuildContext context,
    String label,
    ProfileArtwork art,
    String key,
    TextEditingController controller,
    bool horizontal,
  ) {
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ProfileIcon(artwork: art, size: 27),
        const SizedBox(width: 8),
        Flexible(
          child: Text(label, style: ProfileTypography.supporting(context)),
        ),
      ],
    );
    final field = SizedBox(
      width: 112,
      child: _numberField(
        context,
        key: key,
        controller: controller,
        label: '$label mastery',
        mastery: true,
      ),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: context.visualTheme.materials.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: context.visualTheme.palette.trim.withValues(alpha: .65),
        ),
      ),
      child: horizontal
          ? LayoutBuilder(
              builder: (context, c) {
                if (c.maxWidth < 225 * _scale(context, 14)) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 8), field],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 10),
                    field,
                  ],
                );
              },
            )
          : Column(children: [title, const SizedBox(height: 10), field]),
    );
  }

  Widget _weightPage(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, c) {
          final fields = [
            _weightField(
              context,
              'setup-maximum-weight-lt',
              _maximum,
              'Maximum weight',
            ),
            _weightField(
              context,
              'setup-current-carried-weight-lt',
              _current,
              'Current weight',
            ),
            _weightField(context, 'setup-safety-buffer-lt', _free, 'Keep free'),
          ];
          return c.maxWidth < 420 * _scale(context, 12)
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _vertical(fields, 12),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _horizontal(fields, 12),
                );
        },
      ),
      const SizedBox(height: 16),
      Divider(
        height: 1,
        color: context.visualTheme.palette.trim.withValues(alpha: .45),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ProfileIcon(
                artwork: ProfileArtwork.featherySteps,
                size: 27,
              ),
              const SizedBox(width: 8),
              Text(
                'Feathery Steps',
                style: ProfileTypography.supporting(context),
              ),
            ],
          ),
          Wrap(
            spacing: 4,
            runSpacing: 6,
            children: [
              for (var level = 0; level <= 5; level++)
                AppButton(
                  key: ValueKey('setup-feathery-steps-$level'),
                  role: AppButtonRole.optionPill,
                  selected: _feathery == level,
                  minimumSize: const Size(30, 34),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 6,
                  ),
                  semanticLabel: 'Feathery Steps ${_featheryLabel(level)}',
                  tooltip: _featheryLabel(level),
                  onPressed: widget.busy
                      ? null
                      : () => setState(() => _feathery = level),
                  child: Text(
                    _featheryShort(level),
                    style: ProfileTypography.label(
                      context,
                    ).copyWith(color: context.visualTheme.palette.text),
                  ),
                ),
            ],
          ),
        ],
      ),
    ],
  );
  Widget _weightField(
    BuildContext context,
    String key,
    TextEditingController controller,
    String label,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: ProfileTypography.label(context)),
      const SizedBox(height: 6),
      SizedBox(
        width: 140,
        child: _numberField(
          context,
          key: key,
          controller: controller,
          label: '$label in LT',
        ),
      ),
    ],
  );
  Widget _numberField(
    BuildContext context, {
    required String key,
    required TextEditingController controller,
    required String label,
    bool mastery = false,
  }) => AppTextField(
    key: ValueKey(key),
    controller: controller,
    semanticLabel: label,
    enabled: !widget.busy,
    minimumHeight: 40,
    textStyle: ProfileTypography.input(context),
    textAlign: mastery ? TextAlign.center : TextAlign.end,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    suffixIcon: mastery
        ? null
        : Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Text('LT', style: ProfileTypography.label(context))],
            ),
          ),
    keyboardType: TextInputType.numberWithOptions(decimal: !mastery),
    inputFormatters: mastery
        ? const [_MasteryInputFormatter()]
        : const [_NonNegativeNumberInputFormatter()],
    onChanged: (_) => setState(() => _editing = true),
  );

  // The text wraps independently of the shared switch at enlarged text sizes.
  Widget _toggle(
    BuildContext context, {
    required String key,
    required String label,
    required Widget leading,
    String? description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Row(
    children: [
      leading,
      const SizedBox(width: 10),
      Expanded(
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: widget.busy ? null : () => onChanged(!value),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: ProfileTypography.supporting(context)),
                if (description != null)
                  Text(description, style: ProfileTypography.label(context)),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 58,
        child: AppToggle(
          key: ValueKey(key),
          value: value,
          onChanged: widget.busy ? null : onChanged,
          label: label,
          switchAtEnd: true,
        ),
      ),
    ],
  );
  Widget _marketPage(BuildContext context) {
    final options = <double>[
      ..._fameTiers,
      if (!_fameTiers.any((v) => (v - _fame).abs() < .0000001)) _fame,
    ]..sort();
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toggle(
          context,
          key: 'setup-value-pack',
          label: 'Value Pack',
          leading: const MarketBonusIcon(
            artwork: MarketBonusArtwork.valuePack,
            size: 38,
          ),
          description: '+30% collection bonus',
          value: _pack,
          onChanged: (v) => setState(() => _pack = v),
        ),
        const SizedBox(height: 10),
        _toggle(
          context,
          key: 'setup-merchant-ring',
          label: "Rich Merchant's Ring",
          leading: const MarketBonusIcon(
            artwork: MarketBonusArtwork.richMerchantsRing,
            size: 38,
          ),
          description: '+5% collection bonus',
          value: _ring,
          onChanged: (v) => setState(() => _ring = v),
        ),
        const SizedBox(height: 14),
        Text('Family Fame bonus', style: ProfileTypography.label(context)),
        const SizedBox(height: 6),
        AppSelect<double>(
          key: const ValueKey('setup-family-fame'),
          value: _fame,
          items: options,
          labelFor: _fameLabel,
          semanticLabel: 'Family Fame market bonus tier',
          onChanged: widget.busy
              ? null
              : (v) {
                  if (v != null) setState(() => _fame = v);
                },
        ),
      ],
    );
    final result = ProfileResultFrame(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 15,
                color: context.visualTheme.palette.primaryBright,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  'You receive',
                  style: ProfileTypography.label(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Semantics(
            liveRegion: true,
            child: Text(
              _percent(_net),
              key: const ValueKey('setup-market-return-summary'),
              style: ProfileTypography.result(context),
            ),
          ),
          Text('of the listed price', style: ProfileTypography.label(context)),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 470 * _scale(context, 14)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [controls, const SizedBox(height: 14), result],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: controls),
            const SizedBox(width: 14),
            SizedBox(width: 162, child: result),
          ],
        );
      },
    );
  }

  Widget _actions(BuildContext context) {
    final style = ProfileTypography.supporting(context);
    final painter = TextPainter(
      text: TextSpan(text: 'Save & continue', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = (painter.width + 30).clamp(132.0, double.infinity).toDouble();
    painter.dispose();
    Widget action(String label, String key, VoidCallback? callback) => SizedBox(
      width: width,
      child: AppButton(
        key: ValueKey(key),
        role: AppButtonRole.primary,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        onPressed: callback,
        semanticLabel: label,
        child: Text(
          label,
          style: style.copyWith(
            color: callback == null
                ? context.visualTheme.palette.textMuted
                : null,
          ),
        ),
      ),
    );
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 10,
      runSpacing: 10,
      children: [
        action(
          'Skip',
          'first-run-setup-skip',
          widget.busy ? null : widget.onSkip,
        ),
        action(
          widget.busy ? 'Saving...' : 'Save & continue',
          'first-run-setup-finish',
          widget.busy || !_canSave ? null : _finish,
        ),
      ],
    );
  }

  void _finish() {
    if (widget.busy || !_canSave) return;
    widget.onFinish(_answers!);
  }
}

double _scale(BuildContext context, double size) =>
    MediaQuery.textScalerOf(context).scale(size) / size;
int? _mastery(String text) {
  if (text.trim().isEmpty) return 0;
  final v = int.tryParse(text);
  return v != null && v >= 0 && v <= 3000 ? v : null;
}

String _quantity(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

double? _parseQuantity(String text) {
  final t = text.trim();
  if (t.isEmpty) return 0;
  if (!_NonNegativeNumberInputFormatter.allowed.hasMatch(t)) return null;
  final v = double.tryParse(t.replaceAll(',', '.'));
  return v != null && v.isFinite && v >= 0 ? v : null;
}

final class _MasteryInputFormatter extends TextInputFormatter {
  const _MasteryInputFormatter();
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final v = BigInt.tryParse(newValue.text);
    if (v == null) return oldValue;
    final max = BigInt.from(3000),
        bounded = v < BigInt.zero
            ? BigInt.zero
            : v > BigInt.from(3000)
            ? BigInt.from(3000)
            : v;
    if (v >= BigInt.zero && v <= max) return newValue;
    final text = '$bounded';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

final class _NonNegativeNumberInputFormatter extends TextInputFormatter {
  const _NonNegativeNumberInputFormatter();
  static final allowed = RegExp(r'^\d*(?:[.,]\d*)?$');
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => allowed.hasMatch(newValue.text) ? newValue : oldValue;
}

String _featheryShort(int v) => switch (v) {
  1 => 'I',
  2 => 'II',
  3 => 'III',
  4 => 'IV',
  5 => 'V',
  _ => 'None',
};
String _featheryLabel(int v) => '${_featheryShort(v)} · ${100 + v * 5}%';
const _fameTiers = <double>[0, .005, .01, .015];
String _fameLabel(double v) {
  if (v.abs() < .0000001) return 'Below 1,000 · None';
  if ((v - .005).abs() < .0000001) return '1,000+ · +0.5%';
  if ((v - .01).abs() < .0000001) return '4,000+ · +1%';
  if ((v - .015).abs() < .0000001) return '7,000+ · +1.5%';
  return 'Imported · ${_percent(v)}';
}

String _percent(double v) =>
    '${(v * 100).toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '')}%';
List<Widget> _vertical(List<Widget> items, double space) => [
  for (var i = 0; i < items.length; i++) ...[
    if (i > 0) SizedBox(height: space),
    items[i],
  ],
];
List<Widget> _horizontal(List<Widget> items, double space) => [
  for (var i = 0; i < items.length; i++) ...[
    if (i > 0) SizedBox(width: space),
    Expanded(child: items[i]),
  ],
];
