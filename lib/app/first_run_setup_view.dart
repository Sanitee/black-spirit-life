import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/market/market_calculations.dart';
import '../domain/state/planner_state.dart';
import '../features/data/market_bonus_icon.dart';
import '../visual/components/app_button.dart';
import '../visual/components/app_form_controls.dart';
import '../visual/components/app_surface.dart';
import '../visual/components/section_header.dart';
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
  late final TextEditingController _alchemyMastery;
  late final TextEditingController _cookingMastery;
  late final TextEditingController _processingMastery;
  late final TextEditingController _maximumWeightLt;
  late final TextEditingController _currentCarriedWeightLt;
  late final TextEditingController _safetyBufferLt;
  late bool _useMassProcessing;
  late int _featheryStepsLevel;
  late bool _valuePack;
  late bool _merchantRing;
  late double _familyFameBonus;
  int _pageIndex = 0;
  String? _validationError;

  FirstRunSetupAnswers get _initialAnswers =>
      FirstRunSetupAnswers.forInitialDisplay(widget.document);

  @override
  void initState() {
    super.initState();
    final answers = _initialAnswers.normalized();
    _alchemyMastery = TextEditingController(text: '${answers.alchemyMastery}');
    _cookingMastery = TextEditingController(text: '${answers.cookingMastery}');
    _processingMastery = TextEditingController(
      text: '${answers.processingMastery}',
    );
    _maximumWeightLt = TextEditingController(
      text: _formatSetupQuantity(answers.maximumWeightLt),
    );
    _currentCarriedWeightLt = TextEditingController(
      text: _formatSetupQuantity(answers.currentCarriedWeightLt),
    );
    _safetyBufferLt = TextEditingController(
      text: _formatSetupQuantity(answers.safetyBufferLt),
    );
    _useMassProcessing = answers.useMassProcessing;
    _featheryStepsLevel = answers.featheryStepsLevel;
    _valuePack = answers.valuePack;
    _merchantRing = answers.merchantRing;
    _familyFameBonus = answers.familyFameBonus;
  }

  @override
  void dispose() {
    _alchemyMastery.dispose();
    _cookingMastery.dispose();
    _processingMastery.dispose();
    _maximumWeightLt.dispose();
    _currentCarriedWeightLt.dispose();
    _safetyBufferLt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups.isEmpty
        ? FirstRunSetupSchema.groups
        : widget.groups;
    final safeIndex = _pageIndex.clamp(0, groups.length - 1);
    final group = groups[safeIndex];
    return AppStartupFrame(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Black Spirit Life first run setup',
              child: AppSurface(
                role: AppSurfaceRole.modal,
                padding: const EdgeInsets.all(24),
                semanticLabel: 'First run setup',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SectionHeader(
                      key: const ValueKey<String>('first-run-setup-title'),
                      title: 'Set up your planner',
                      meta: 'Step ${safeIndex + 1} of ${groups.length}',
                    ),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: KeyedSubtree(
                        key: ValueKey<FirstRunSetupGroup>(group),
                        child: switch (group) {
                          FirstRunSetupGroup.masteryAndOutput => _masteryPage(
                            context,
                          ),
                          FirstRunSetupGroup.afkLoad => _afkLoadPage(context),
                          FirstRunSetupGroup.marketSales => _marketPage(
                            context,
                          ),
                        },
                      ),
                    ),
                    if (_validationError != null || widget.error != null) ...[
                      const SizedBox(height: 16),
                      AppSurface(
                        role: AppSurfaceRole.row,
                        tone: AppSurfaceTone.danger,
                        padding: const EdgeInsets.all(12),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _validationError ??
                                'The setup was not saved. Your previous planner values are still active. ${widget.error}',
                            key: const ValueKey<String>(
                              'first-run-setup-error',
                            ),
                            style: TextStyle(
                              color: context.visualTheme.palette.danger,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    _actions(groups, safeIndex),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _masteryPage(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Semantics(
        header: true,
        child: Text('Mastery', style: _groupHeadingStyle(context)),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final fields = <Widget>[
            _masteryField(
              key: const ValueKey<String>('setup-alchemy-mastery'),
              controller: _alchemyMastery,
              label: 'Alchemy mastery',
            ),
            _masteryField(
              key: const ValueKey<String>('setup-cooking-mastery'),
              controller: _cookingMastery,
              label: 'Cooking mastery',
            ),
            _masteryField(
              key: const ValueKey<String>('setup-processing-mastery'),
              controller: _processingMastery,
              label: 'Processing mastery',
            ),
          ];
          if (constraints.maxWidth < 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _spacedVertically(fields, 12),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _expandedHorizontally(fields, 12),
          );
        },
      ),
      const SizedBox(height: 14),
      AppSurface(
        role: AppSurfaceRole.row,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: AppToggle(
          key: const ValueKey<String>('setup-mass-processing'),
          value: _useMassProcessing,
          onChanged: widget.busy
              ? null
              : (value) => setState(() => _useMassProcessing = value),
          label: 'Use Mass Processing',
          description: 'Use mass-process batches in processing plans.',
          switchAtEnd: true,
        ),
      ),
    ],
  );

  Widget _afkLoadPage(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Semantics(
        header: true,
        child: Text('AFK Load', style: _groupHeadingStyle(context)),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final fieldWidth = constraints.maxWidth >= 640
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              SizedBox(
                width: fieldWidth,
                child: _weightField(
                  key: const ValueKey<String>('setup-maximum-weight-lt'),
                  controller: _maximumWeightLt,
                  label: 'Character Max LT',
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: _weightField(
                  key: const ValueKey<String>(
                    'setup-current-carried-weight-lt',
                  ),
                  controller: _currentCarriedWeightLt,
                  label: 'Weight already carried',
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: _weightField(
                  key: const ValueKey<String>('setup-safety-buffer-lt'),
                  controller: _safetyBufferLt,
                  label: 'LT to keep free',
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'Fairy · Feathery Steps',
                      style: context.visualTheme.typography.label,
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 44,
                      child: AppSelect<int>(
                        key: const ValueKey<String>('setup-feathery-steps'),
                        value: _featheryStepsLevel,
                        items: _featheryLevels,
                        labelFor: _featheryLabel,
                        semanticLabel: 'Feathery Steps weight threshold',
                        onChanged: widget.busy
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _featheryStepsLevel = value);
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ],
  );

  Widget _marketPage(BuildContext context) {
    final tax = MarketTax(
      enabled: true,
      valuePack: _valuePack,
      merchantRing: _merchantRing,
      familyFameBonus: _familyFameBonus,
    );
    final familyFameOptions = <double>[
      ..._familyFameTiers,
      if (!_familyFameTiers.any(
        (value) => (value - _familyFameBonus).abs() < .0000001,
      ))
        _familyFameBonus,
    ]..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text('Market sales', style: _groupHeadingStyle(context)),
        ),
        const SizedBox(height: 12),
        AppSurface(
          role: AppSurfaceRole.row,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: AppToggle(
            key: const ValueKey<String>('setup-value-pack'),
            leading: const MarketBonusIcon(
              artwork: MarketBonusArtwork.valuePack,
            ),
            value: _valuePack,
            onChanged: widget.busy
                ? null
                : (value) => setState(() => _valuePack = value),
            label: 'Value Pack',
            description: '+30% collection bonus',
            switchAtEnd: true,
          ),
        ),
        const SizedBox(height: 8),
        AppSurface(
          role: AppSurfaceRole.row,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: AppToggle(
            key: const ValueKey<String>('setup-merchant-ring'),
            leading: const MarketBonusIcon(
              artwork: MarketBonusArtwork.richMerchantsRing,
            ),
            value: _merchantRing,
            onChanged: widget.busy
                ? null
                : (value) => setState(() => _merchantRing = value),
            label: "Rich Merchant's Ring",
            description: '+5% collection bonus',
            switchAtEnd: true,
          ),
        ),
        const SizedBox(height: 12),
        Text('Family Fame bonus', style: context.visualTheme.typography.label),
        const SizedBox(height: 6),
        SizedBox(
          height: 44,
          child: AppSelect<double>(
            key: const ValueKey<String>('setup-family-fame'),
            value: _familyFameBonus,
            items: familyFameOptions,
            labelFor: _familyFameLabel,
            semanticLabel: 'Family Fame market bonus tier',
            onChanged: widget.busy
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _familyFameBonus = value);
                    }
                  },
          ),
        ),
        const SizedBox(height: 14),
        AppSurface(
          role: AppSurfaceRole.row,
          padding: const EdgeInsets.all(12),
          child: Text(
            'Estimated silver received: ${_formatPercent(marketNetRate(tax))} of the sale price.',
            key: const ValueKey<String>('setup-market-return-summary'),
          ),
        ),
      ],
    );
  }

  Widget _masteryField({
    required Key key,
    required TextEditingController controller,
    required String label,
  }) => AppTextField(
    key: key,
    controller: controller,
    label: label,
    semanticLabel: label,
    enabled: !widget.busy,
    keyboardType: TextInputType.number,
    inputFormatters: const <TextInputFormatter>[_MasteryInputFormatter()],
    onChanged: (_) {
      if (_validationError != null) {
        setState(() => _validationError = null);
      }
    },
  );

  Widget _weightField({
    required Key key,
    required TextEditingController controller,
    required String label,
  }) => AppTextField(
    key: key,
    controller: controller,
    label: label,
    semanticLabel: label,
    enabled: !widget.busy,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: const <TextInputFormatter>[
      _NonNegativeNumberInputFormatter(),
    ],
    onChanged: (_) {
      if (_validationError != null) {
        setState(() => _validationError = null);
      }
    },
  );

  Widget _actions(List<FirstRunSetupGroup> groups, int safeIndex) => Wrap(
    alignment: WrapAlignment.end,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 10,
    runSpacing: 10,
    children: <Widget>[
      AppButton.label(
        'Skip for now',
        key: const ValueKey<String>('first-run-setup-skip'),
        onPressed: widget.busy ? null : widget.onSkip,
      ),
      if (safeIndex > 0)
        AppButton.label(
          'Back',
          key: const ValueKey<String>('first-run-setup-back'),
          onPressed: widget.busy
              ? null
              : () => setState(() {
                  _validationError = null;
                  _pageIndex = safeIndex - 1;
                }),
        ),
      AppButton.label(
        safeIndex == groups.length - 1
            ? widget.busy
                  ? 'Saving...'
                  : 'Save and continue'
            : 'Continue',
        key: ValueKey<String>(
          safeIndex == groups.length - 1
              ? 'first-run-setup-finish'
              : 'first-run-setup-next',
        ),
        role: AppButtonRole.primary,
        onPressed: widget.busy
            ? null
            : () {
                if (safeIndex < groups.length - 1) {
                  if (!_validateGroup(groups[safeIndex])) return;
                  setState(() {
                    _validationError = null;
                    _pageIndex = safeIndex + 1;
                  });
                  return;
                }
                _finish();
              },
      ),
    ],
  );

  void _finish() {
    final alchemy = int.tryParse(_alchemyMastery.text);
    final cooking = int.tryParse(_cookingMastery.text);
    final processing = int.tryParse(_processingMastery.text);
    if (alchemy == null || cooking == null || processing == null) {
      setState(() {
        _validationError = 'Enter a mastery value for all three Life Skills.';
      });
      return;
    }
    final maximumWeightLt = _parseSetupQuantity(_maximumWeightLt.text);
    final currentCarriedWeightLt = _parseSetupQuantity(
      _currentCarriedWeightLt.text,
    );
    final safetyBufferLt = _parseSetupQuantity(_safetyBufferLt.text);
    if (maximumWeightLt == null ||
        maximumWeightLt < 0 ||
        currentCarriedWeightLt == null ||
        currentCarriedWeightLt < 0 ||
        safetyBufferLt == null ||
        safetyBufferLt < 0) {
      setState(() {
        _validationError =
            'Enter a valid non-negative LT value in all three weight fields.';
      });
      return;
    }
    setState(() => _validationError = null);
    widget.onFinish(
      FirstRunSetupAnswers(
        alchemyMastery: alchemy,
        cookingMastery: cooking,
        processingMastery: processing,
        useMassProcessing: _useMassProcessing,
        maximumWeightLt: maximumWeightLt,
        currentCarriedWeightLt: currentCarriedWeightLt,
        safetyBufferLt: safetyBufferLt,
        featheryStepsLevel: _featheryStepsLevel,
        valuePack: _valuePack,
        merchantRing: _merchantRing,
        familyFameBonus: _familyFameBonus,
      ),
    );
  }

  bool _validateGroup(FirstRunSetupGroup group) {
    switch (group) {
      case FirstRunSetupGroup.masteryAndOutput:
        if (int.tryParse(_alchemyMastery.text) != null &&
            int.tryParse(_cookingMastery.text) != null &&
            int.tryParse(_processingMastery.text) != null) {
          return true;
        }
        setState(() {
          _validationError = 'Enter a mastery value for all three Life Skills.';
        });
        return false;
      case FirstRunSetupGroup.afkLoad:
        final values = <double?>[
          _parseSetupQuantity(_maximumWeightLt.text),
          _parseSetupQuantity(_currentCarriedWeightLt.text),
          _parseSetupQuantity(_safetyBufferLt.text),
        ];
        if (values.every((value) => value != null && value >= 0)) return true;
        setState(() {
          _validationError =
              'Enter a valid non-negative LT value in all three weight fields.';
        });
        return false;
      case FirstRunSetupGroup.marketSales:
        return true;
    }
  }
}

TextStyle _groupHeadingStyle(BuildContext context) =>
    context.visualTheme.typography.section.copyWith(fontSize: 20);

String _formatSetupQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  // Dart's shortest representation round-trips to the exact saved double.
  // That prevents an untouched repeated-Beta setup from rounding LT values.
  return value.toString();
}

double? _parseSetupQuantity(String text) {
  final trimmed = text.trim();
  if (!_NonNegativeNumberInputFormatter._allowed.hasMatch(trimmed)) return null;
  final value = double.tryParse(trimmed.replaceAll(',', '.'));
  return value != null && value.isFinite ? value : null;
}

final class _MasteryInputFormatter extends TextInputFormatter {
  const _MasteryInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final value = BigInt.tryParse(newValue.text);
    if (value == null) return oldValue;
    final maximum = BigInt.from(3000);
    final bounded = value < BigInt.zero
        ? BigInt.zero
        : value > maximum
        ? maximum
        : value;
    if (bounded == value) return newValue;
    final text = '$bounded';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

final class _NonNegativeNumberInputFormatter extends TextInputFormatter {
  const _NonNegativeNumberInputFormatter();

  static final RegExp _allowed = RegExp(r'^\d*(?:[.,]\d*)?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => _allowed.hasMatch(newValue.text) ? newValue : oldValue;
}

const List<int> _featheryLevels = <int>[0, 1, 2, 3, 4, 5];

String _featheryLabel(int level) => switch (level) {
  1 => 'I · 105%',
  2 => 'II · 110%',
  3 => 'III · 115%',
  4 => 'IV · 120%',
  5 => 'V · 125%',
  _ => 'None · 100%',
};

const List<double> _familyFameTiers = <double>[0, .005, .01, .015];

String _familyFameLabel(double value) {
  if ((value - 0).abs() < .0000001) return 'Below 1,000 - +0%';
  if ((value - .005).abs() < .0000001) return '1,000-3,999 - +0.5%';
  if ((value - .01).abs() < .0000001) return '4,000-6,999 - +1.0%';
  if ((value - .015).abs() < .0000001) return '7,000+ - +1.5%';
  return 'Imported - ${_formatPercent(value)}';
}

String _formatPercent(double fraction) {
  final percent = fraction * 100;
  final text = percent.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  return '$text%';
}

List<Widget> _spacedVertically(List<Widget> widgets, double spacing) => [
  for (var index = 0; index < widgets.length; index++) ...<Widget>[
    if (index > 0) SizedBox(height: spacing),
    widgets[index],
  ],
];

List<Widget> _expandedHorizontally(List<Widget> widgets, double spacing) => [
  for (var index = 0; index < widgets.length; index++) ...<Widget>[
    if (index > 0) SizedBox(width: spacing),
    Expanded(child: widgets[index]),
  ],
];
