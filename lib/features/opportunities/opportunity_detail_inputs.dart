part of 'opportunities_workspace.dart';

/// A stationary label and one full-height input, shared by detail quantities
/// and custom prices. No floating label or shadowed outer container.
class _OpportunityNumberInput extends StatelessWidget {
  const _OpportunityNumberInput({
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.inputFormatters,
    this.focusNode,
    this.hintText,
    this.textStyle,
    this.tooltip,
    super.key,
  });
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final List<TextInputFormatter> inputFormatters;
  final FocusNode? focusNode;
  final String? hintText, tooltip;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final field = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 5),
          child: Text(label, style: spec.typography.meta),
        ),
        OpportunityTextField(
          controller: controller,
          focusNode: focusNode,
          semanticLabel: label,
          hintText: hintText,
          textStyle: textStyle ?? spec.typography.body.copyWith(fontSize: 16),
          keyboardType: TextInputType.number,
          inputFormatters: inputFormatters,
          minimumHeight: 42,
          flat: true,
          onChanged: onChanged,
        ),
      ],
    );
    return tooltip == null ? field : Tooltip(message: tooltip!, child: field);
  }
}

class _OpportunityCustomSalePrice extends StatefulWidget {
  const _OpportunityCustomSalePrice({
    required this.value,
    required this.onChanged,
  });
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  State<_OpportunityCustomSalePrice> createState() =>
      _OpportunityCustomSalePriceState();
}

class _OpportunityCustomSalePriceState
    extends State<_OpportunityCustomSalePrice> {
  late final text = TextEditingController(text: _formatted(widget.value));
  final focus = FocusNode();

  static String _formatted(int? value) => value == null
      ? ''
      : value <= 0
      ? '0'
      : formatSilverPrice(value);
  int? get entered =>
      text.text.isEmpty ? null : parseSilverPrice(text.text) ?? 0;

  @override
  void didUpdateWidget(_OpportunityCustomSalePrice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && entered != widget.value) {
      text.text = _formatted(widget.value);
    }
  }

  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 230 * (MediaQuery.textScalerOf(context).scale(14) / 14),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OpportunityNumberInput(
          key: const ValueKey('opportunity-custom-sale-price'),
          label: 'Custom sale price',
          hintText: 'Market price',
          tooltip:
              'Silver per item, before tax. Clear to use the market price.',
          controller: text,
          focusNode: focus,
          inputFormatters: const [SilverPriceInputFormatter()],
          onChanged: (_) {
            setState(() {});
            widget.onChanged(entered);
          },
        ),
        if (entered == 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Enter a whole price above 0',
              style: context.visualTheme.typography.meta.copyWith(
                color: context.visualTheme.palette.danger,
              ),
            ),
          ),
      ],
    ),
  );
}
