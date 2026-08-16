import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundations/theme_spec.dart';
import '../illuminated_ledger/ledger_ornament_painters.dart';
import '../sakura_night_garden/sakura_spec.dart';
import '../standard/standard_spec.dart';
import 'app_button.dart';
import 'app_vector_glyph.dart';

enum AppTextFieldEmphasis { normal, subdued }

/// Theme-owned marker for compact independent selection controls.
///
/// Feature widgets own their labels and behavior; this primitive keeps the
/// selected material consistent with the active retained theme and live
/// Standard accent settings.
class AppSelectionMarker extends StatelessWidget {
  const AppSelectionMarker({required this.selected, super.key});

  final bool selected;

  static const Key materialKey = ValueKey<String>('app-selection-marker');

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final Widget marker;
    if (spec.isIlluminatedLedger) {
      marker = selected
          ? CustomPaint(
              painter: const LedgerWaxSealPainter(
                enabled: true,
                hovered: false,
                pressed: false,
                focused: false,
              ),
              child: const Center(child: AppVectorGlyph('check', size: 13)),
            )
          : Padding(
              padding: const EdgeInsets.all(3),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: spec.materials.surfaceRaised,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0x8A7A5B2A),
                    width: 1.2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0x6F8A6A3A)),
                    ),
                  ),
                ),
              ),
            );
    } else if (spec.isSakuraNightGarden) {
      marker = DecoratedBox(
        decoration: BoxDecoration(
          gradient: selected
              ? SakuraNightGardenSpec.mossGradient
              : SakuraNightGardenSpec.raisedSurfaceGradient,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected
                ? const Color(0xFF899783)
                : SakuraNightGardenSpec.barkCopper,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: selected
            ? const Center(
                child: AppVectorGlyph(
                  'check',
                  size: 14,
                  color: SakuraNightGardenSpec.warmIvory,
                ),
              )
            : const SizedBox.expand(),
      );
    } else {
      final standard = context.standardVisual;
      final usesDefaultAccent =
          standard.accentHue == StandardVisualSettings.fallback.accentHue &&
          !standard.neon;
      marker = DecoratedBox(
        decoration: BoxDecoration(
          gradient: selected
              ? usesDefaultAccent
                    ? spec.materials.primary
                    : StandardSpec.accentGlass(
                        standard.accentHue,
                        topAlpha: 255,
                        bottomAlpha: 228,
                        neon: standard.neon,
                      )
              : spec.materials.surfaceRaised,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? usesDefaultAccent
                      ? spec.palette.primaryBright.withAlpha(226)
                      : StandardSpec.accentBrush(
                          standard.accentHue,
                          alpha: .9,
                          neon: standard.neon,
                        )
                : spec.palette.trim.withAlpha(142),
            width: selected ? 1.2 : 1,
          ),
        ),
        child: selected
            ? Center(
                child: AppVectorGlyph(
                  'check',
                  size: 10,
                  color: const Color(0xFF03120E),
                ),
              )
            : const SizedBox.expand(),
      );
    }
    return KeyedSubtree(key: materialKey, child: marker);
  }
}

/// Compact independent Boolean filter with shared theme-owned geometry.
class AppFilterButton extends StatelessWidget {
  const AppFilterButton({
    required this.selected,
    required this.label,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  final bool selected;
  final String label;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final markerSize = ledger ? 18.0 : 17.0;
    return Semantics(
      container: true,
      toggled: selected,
      child: AppButton(
        role: AppButtonRole.optionPill,
        selected: selected,
        minimumSize: const Size(0, 36),
        padding: EdgeInsets.fromLTRB(ledger ? 7 : 8, 5, ledger ? 10 : 11, 5),
        semanticLabel: semanticLabel ?? label,
        onPressed: onChanged == null ? null : () => onChanged!(!selected),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox.square(
              dimension: markerSize,
              child: AppSelectionMarker(selected: selected),
            ),
            const SizedBox(width: 7),
            DefaultTextStyle.merge(
              style: TextStyle(
                fontFamily: ledger ? 'Georgia' : null,
                fontSize: ledger ? 12 : 12.25,
                fontWeight: FontWeight.w600,
                letterSpacing: ledger ? .16 : .08,
                height: 1,
              ),
              child: ExcludeSemantics(
                child: Text(label, maxLines: 1, softWrap: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    this.controller,
    this.focusNode,
    this.label,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.onKeyEvent,
    this.onTap,
    this.keyboardType,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.textStyle,
    this.hintStyle,
    this.enabled = true,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.prefixIcon,
    this.suffixIcon,
    this.semanticLabel,
    this.emphasis = AppTextFieldEmphasis.normal,
    this.minimumHeight,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusOnKeyEventCallback? onKeyEvent;
  final GestureTapCallback? onTap;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;
  final TextStyle? textStyle;
  final TextStyle? hintStyle;
  final bool enabled;
  final bool obscureText;
  final int? maxLines;
  final int? minLines;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? semanticLabel;
  final AppTextFieldEmphasis emphasis;
  final double? minimumHeight;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final standard = context.standardVisual;
    final subduedStandard =
        spec.isStandard && emphasis == AppTextFieldEmphasis.subdued;
    final baseTextStyle = textStyle ?? spec.typography.body;
    final denseSingleLine = spec.usesDenseSplitLayout && maxLines == 1;
    final controlTextStyle = denseSingleLine
        ? baseTextStyle.copyWith(
            height: 1.15,
            leadingDistribution: TextLeadingDistribution.even,
          )
        : baseTextStyle;
    final pinnedSingleLineHeight = minimumHeight != null && maxLines == 1;
    final controlFontSize = controlTextStyle.fontSize ?? 14.0;
    final scaledLineHeight =
        MediaQuery.textScalerOf(context).scale(controlFontSize) *
        (controlTextStyle.height ?? 1.15);
    final singleLineHeight = (scaledLineHeight + 10)
        .clamp(38.0, double.infinity)
        .toDouble();
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(spec.geometry.fieldRadius),
      borderSide: BorderSide(
        color: ledger
            ? spec.palette.trim.withAlpha(138)
            : sakura
            ? spec.palette.trim.withAlpha(
                emphasis == AppTextFieldEmphasis.subdued ? 128 : 190,
              )
            : subduedStandard
            ? const Color(0x395C8B76)
            : StandardSpec.accentBrush(
                standard.accentHue,
                alpha: .32,
                neon: standard.neon,
              ),
      ),
    );
    Widget field = TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textAlign: textAlign,
      textAlignVertical: maxLines == 1
          ? TextAlignVertical.center
          : TextAlignVertical.top,
      enabled: enabled,
      obscureText: obscureText,
      maxLines: maxLines,
      minLines: minLines,
      cursorColor: spec.palette.primaryBright,
      style: controlTextStyle,
      decoration: InputDecoration(
        // Dense InputDecorator layouts shrink to the raw line height and sit
        // at the top of a taller desktop host. Full-workstation single-line
        // controls use the normal template so the centered baseline fills the
        // same authored host height as adjacent controls.
        isDense: !(denseSingleLine || (subduedStandard && maxLines == 1)),
        labelText: label,
        hintText: hintText,
        prefixIcon: prefixIcon,
        // Keep a zero-width suffix slot when a fixed desktop height is
        // requested. InputDecorator uses that slot's vertical constraint when
        // calculating its painted container, even when no visible suffix is
        // currently needed (for example an empty Search field).
        suffixIcon: pinnedSingleLineHeight
            ? suffixIcon ?? const SizedBox.shrink()
            : suffixIcon,
        // A tight outer SizedBox only stretches the Standard glass layer; a
        // dense InputDecorator can still paint a shorter outline at the top of
        // that host. Callers that compose a fixed-height desktop row can pin
        // the decorator itself so its border, fill, suffix, and centered text
        // all consume the same authored height as adjacent controls.
        constraints: minimumHeight == null
            ? null
            : BoxConstraints(minHeight: minimumHeight!),
        prefixIconConstraints: minimumHeight == null
            ? null
            : BoxConstraints(minWidth: 0, minHeight: minimumHeight!),
        suffixIconConstraints: minimumHeight == null
            ? null
            : BoxConstraints(minWidth: 0, minHeight: minimumHeight!),
        filled: ledger,
        fillColor: ledger ? spec.palette.surfaceRaised.withAlpha(212) : null,
        labelStyle: spec.typography.label.copyWith(
          color: spec.palette.textMuted,
        ),
        hintStyle:
            hintStyle ??
            controlTextStyle.copyWith(
              color: spec.palette.textMuted.withAlpha(160),
            ),
        // Dense workstation fields and the subdued Standard source-note
        // variant use zero vertical inset. Generic Standard fields retain the
        // denser template used by the other workspace controls.
        contentPadding: maxLines == 1
            ? denseSingleLine
                  ? const EdgeInsets.symmetric(horizontal: 12)
                  : subduedStandard
                  ? const EdgeInsets.symmetric(horizontal: 9)
                  : const EdgeInsets.symmetric(horizontal: 12, vertical: 9)
            : EdgeInsets.fromLTRB(12, spec.usesDenseSplitLayout ? 9 : 8, 12, 8),
        border: border,
        enabledBorder: border,
        disabledBorder: border.copyWith(
          borderSide: BorderSide(color: spec.palette.trim.withAlpha(62)),
        ),
        focusedBorder: border.copyWith(
          borderSide: BorderSide(
            color: ledger
                ? spec.palette.primaryBright
                : sakura
                ? spec.palette.primaryBright
                : StandardSpec.accentBrush(
                    standard.accentHue,
                    neon: standard.neon,
                  ),
            width: ledger
                ? 1.7
                : sakura
                ? 1.6
                : 1.4,
          ),
        ),
      ),
    );
    if (denseSingleLine) {
      field = SizedBox(height: singleLineHeight, child: field);
    }
    if (onKeyEvent != null) {
      field = Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onKeyEvent: onKeyEvent,
        child: field,
      );
    }
    if (semanticLabel != null) {
      field = Semantics(textField: true, label: semanticLabel, child: field);
    }
    if (sakura) {
      field = DecoratedBox(
        decoration: BoxDecoration(
          gradient: emphasis == AppTextFieldEmphasis.subdued
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    SakuraNightGardenSpec.charcoalPlum,
                    SakuraNightGardenSpec.insetPlum,
                  ],
                )
              : SakuraNightGardenSpec.raisedSurfaceGradient,
          image: const DecorationImage(
            image: AssetImage(
              'assets/sakura/materials/charcoal-plum-lacquer.png',
            ),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            opacity: .17,
          ),
          borderRadius: BorderRadius.circular(spec.geometry.fieldRadius),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: spec.palette.shadow.withAlpha(76),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: field,
      );
    } else if (spec.isStandard) {
      field = DecoratedBox(
        decoration: BoxDecoration(
          gradient: subduedStandard
              ? StandardSpec.glassGradient(topAlpha: 34, bottomAlpha: 12)
              : StandardSpec.accentGlass(
                  standard.accentHue,
                  topAlpha: 54,
                  bottomAlpha: 18,
                  neon: standard.neon,
                ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: field,
      );
    }
    return field;
  }
}

/// An app-authored searchable combo box for choosing an existing domain item.
///
/// Unlike [AppSelect], the anchor stays editable while its lazily built option
/// list is open. The caller owns the controller so an in-progress query can be
/// retained in a feature session across navigation and responsive rebuilds.
class AppSearchSelect<T extends Object> extends StatefulWidget {
  const AppSearchSelect({
    required this.controller,
    required this.items,
    required this.labelFor,
    required this.onSelected,
    this.value,
    this.onQueryChanged,
    this.hintText,
    this.semanticLabel,
    this.focusNode,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final List<T> items;
  final String Function(T value) labelFor;
  final ValueChanged<T>? onSelected;
  final T? value;
  final ValueChanged<String>? onQueryChanged;
  final String? hintText;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool enabled;

  @override
  State<AppSearchSelect<T>> createState() => _AppSearchSelectState<T>();
}

class _AppSearchSelectState<T extends Object>
    extends State<AppSearchSelect<T>> {
  final MenuController _menuController = MenuController();
  late final FocusNode _ownedFocusNode = FocusNode();
  bool _expanded = false;
  int _highlighted = 0;

  bool get _enabled =>
      widget.enabled && widget.onSelected != null && widget.items.isNotEmpty;
  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(AppSearchSelect<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      (oldWidget.focusNode ?? _ownedFocusNode).removeListener(_focusChanged);
      _focusNode.addListener(_focusChanged);
    }
    if (!_enabled) _menuController.close();
  }

  @override
  void dispose() {
    _focusNode.removeListener(_focusChanged);
    _ownedFocusNode.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!_focusNode.hasFocus) _menuController.close();
  }

  List<T> _matchingItems() {
    final query = widget.controller.text.trim().toLowerCase();
    if (query.isEmpty) return widget.items;
    final selected = widget.value;
    if (selected != null &&
        widget.labelFor(selected).trim().toLowerCase() == query) {
      return widget.items;
    }
    return widget.items
        .where((item) => widget.labelFor(item).toLowerCase().contains(query))
        .toList(growable: false);
  }

  void _open() {
    if (_enabled && !_menuController.isOpen) _menuController.open();
  }

  void _queryChanged(String value) {
    widget.onQueryChanged?.call(value);
    if (mounted) setState(() => _highlighted = 0);
    if (!_menuController.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open();
      });
    }
  }

  void _submit(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return;
    for (final item in widget.items) {
      if (widget.labelFor(item).trim().toLowerCase() == normalized) {
        _select(item);
        return;
      }
    }
  }

  void _select(T item) {
    final label = widget.labelFor(item);
    widget.controller.value = TextEditingValue(
      text: label,
      // Reveal the identifying start of a selected value instead of leaving a
      // long searchable label scrolled to an ambiguous suffix.
      selection: const TextSelection.collapsed(offset: 0),
    );
    widget.onQueryChanged?.call(label);
    widget.onSelected?.call(item);
    _highlighted = widget.items.indexOf(item).clamp(0, widget.items.length - 1);
    _menuController.close();
    _focusNode.requestFocus();
  }

  void _moveHighlight(int delta) {
    final matches = _matchingItems();
    if (!_enabled || matches.isEmpty) return;
    final selectedValue = widget.value;
    final selectedIndex = selectedValue == null
        ? -1
        : matches.indexOf(selectedValue);
    final current = _menuController.isOpen
        ? _highlighted.clamp(0, matches.length - 1)
        : selectedIndex >= 0
        ? selectedIndex
        : delta > 0
        ? -1
        : matches.length;
    setState(() {
      _highlighted = (current + delta).clamp(0, matches.length - 1);
    });
    _open();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        _menuController.isOpen) {
      final matches = _matchingItems();
      if (matches.isNotEmpty) {
        _select(matches[_highlighted.clamp(0, matches.length - 1)]);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        _menuController.isOpen) {
      _menuController.close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final standard = context.standardVisual;
    final matches = _matchingItems();
    final highlighted = matches.isEmpty
        ? -1
        : _highlighted.clamp(0, matches.length - 1);
    final bodyFontSize = spec.typography.body.fontSize ?? 14;
    final optionExtent =
        (MediaQuery.textScalerOf(context).scale(bodyFontSize) + 16)
            .clamp(36.0, double.infinity)
            .toDouble();
    final optionHeight = matches.isEmpty
        ? optionExtent
        : (matches.length * optionExtent).clamp(optionExtent, 280.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final preferredControlWidth = AppSelect.readableWidthFor<T>(
          context,
          items: widget.items,
          labelFor: widget.labelFor,
        );
        final controlWidth = constraints.hasBoundedWidth
            ? preferredControlWidth
                  .clamp(constraints.minWidth, constraints.maxWidth)
                  .toDouble()
            : preferredControlWidth;
        final menuWidth = _readableSearchMenuWidth(
          context,
          spec,
          matches,
          minimumWidth: controlWidth,
        );
        return SizedBox(
          width: controlWidth,
          child: MenuAnchor(
            controller: _menuController,
            childFocusNode: _focusNode,
            crossAxisUnconstrained: true,
            consumeOutsideTap: false,
            clipBehavior: Clip.antiAlias,
            onOpen: () {
              if (mounted) setState(() => _expanded = true);
            },
            onClose: () {
              if (mounted) setState(() => _expanded = false);
            },
            style: MenuStyle(
              backgroundColor: WidgetStatePropertyAll<Color>(
                ledger
                    ? const Color(0xFFF0D99F)
                    : sakura
                    ? SakuraNightGardenSpec.raisedPlum
                    : const Color.fromARGB(250, 7, 24, 19),
              ),
              surfaceTintColor: const WidgetStatePropertyAll<Color>(
                Colors.transparent,
              ),
              shadowColor: WidgetStatePropertyAll<Color>(spec.palette.shadow),
              elevation: WidgetStatePropertyAll<double>(
                ledger || sakura ? 12 : 10,
              ),
              shape: WidgetStatePropertyAll<OutlinedBorder>(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    ledger ? 2 : spec.geometry.fieldRadius,
                  ),
                ),
              ),
              side: WidgetStatePropertyAll<BorderSide>(
                BorderSide(
                  color: ledger
                      ? spec.palette.trimBright
                      : sakura
                      ? spec.palette.trim.withAlpha(224)
                      : StandardSpec.accentBrush(
                          standard.accentHue,
                          alpha: .62,
                          neon: standard.neon,
                        ),
                  width: ledger
                      ? 1.2
                      : sakura
                      ? 1.1
                      : 1,
                ),
              ),
              padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                EdgeInsets.symmetric(vertical: 4),
              ),
              minimumSize: WidgetStatePropertyAll<Size>(Size(menuWidth, 0)),
              maximumSize: WidgetStatePropertyAll<Size>(Size(menuWidth, 292)),
            ),
            menuChildren: <Widget>[
              SizedBox(
                width: menuWidth,
                height: optionHeight,
                child: matches.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.builder(
                        primary: false,
                        padding: EdgeInsets.zero,
                        itemCount: matches.length,
                        itemBuilder: (context, index) {
                          final item = matches[index];
                          final selected = item == widget.value;
                          return Semantics(
                            selected: selected,
                            label: widget.labelFor(item),
                            child: MenuItemButton(
                              semanticsLabel: widget.labelFor(item),
                              closeOnActivate: false,
                              requestFocusOnHover: false,
                              style: _searchMenuItemStyle(
                                spec: spec,
                                standard: standard,
                                selected: selected,
                                highlighted: index == highlighted,
                              ),
                              onPressed: _enabled ? () => _select(item) : null,
                              child: Row(
                                children: <Widget>[
                                  SizedBox(
                                    width: 18,
                                    child: selected
                                        ? AppVectorGlyph(
                                            'check',
                                            size: 13,
                                            color: ledger
                                                ? const Color(0xFFFFE7A4)
                                                : sakura
                                                ? spec.palette.primaryBright
                                                : StandardSpec.accentBrush(
                                                    standard.accentHue,
                                                    neon: standard.neon,
                                                  ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      widget.labelFor(item),
                                      softWrap: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
            builder: (context, controller, child) => AppTextField(
              controller: widget.controller,
              focusNode: _focusNode,
              hintText: widget.hintText,
              semanticLabel: widget.semanticLabel,
              enabled: _enabled,
              onTap: _open,
              onChanged: _queryChanged,
              onSubmitted: _submit,
              onKeyEvent: _handleKey,
              suffixIcon: IgnorePointer(
                child: Center(
                  child: AnimatedRotation(
                    turns: _expanded ? .5 : 0,
                    duration: spec.motion.interactionDuration,
                    child: AppVectorGlyph(
                      'chevron-down',
                      size: 15,
                      color: spec.palette.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _readableSearchMenuWidth(
    BuildContext context,
    ThemeSpec spec,
    List<T> items, {
    required double minimumWidth,
  }) {
    final ledger = spec.isIlluminatedLedger;
    final measurementStyle = spec.typography.body.copyWith(
      fontFamily: ledger ? 'Georgia' : spec.typography.body.fontFamily,
      fontWeight: FontWeight.w700,
    );
    var longestLabelWidth = 0.0;
    for (final item in items) {
      final painter = TextPainter(
        text: TextSpan(text: widget.labelFor(item), style: measurementStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      if (painter.width > longestLabelWidth) {
        longestLabelWidth = painter.width;
      }
    }
    final viewportLimit = (MediaQuery.sizeOf(context).width - 24)
        .clamp(0.0, double.infinity)
        .toDouble();
    final floor = minimumWidth.clamp(0.0, viewportLimit).toDouble();
    return (longestLabelWidth + 62).clamp(floor, viewportLimit).toDouble();
  }

  ButtonStyle _searchMenuItemStyle({
    required ThemeSpec spec,
    required StandardVisualSettings standard,
    required bool selected,
    required bool highlighted,
  }) {
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    return ButtonStyle(
      animationDuration: spec.motion.interactionDuration,
      splashFactory: NoSplash.splashFactory,
      elevation: const WidgetStatePropertyAll<double>(0),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      ),
      minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 36)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      alignment: Alignment.centerLeft,
      shape: const WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return spec.palette.textMuted.withAlpha(102);
        }
        if (ledger && selected) return const Color(0xFFFFEBC0);
        if (ledger) return const Color(0xFF412A17);
        if (sakura && selected) return SakuraNightGardenSpec.warmIvory;
        if (sakura) return spec.palette.text;
        return const Color(0xFFFFF1D3);
      }),
      backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        final hovered =
            highlighted ||
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused);
        final pressed = states.contains(WidgetState.pressed);
        if (ledger) {
          if (selected) {
            return pressed
                ? const Color(0xFF082A4A)
                : hovered
                ? const Color(0xFF1C5B8E)
                : const Color(0xFF123F6A);
          }
          if (pressed) return const Color(0xFFD4B16E);
          if (hovered) return const Color(0xFFE5C985);
          return Colors.transparent;
        }
        if (sakura) {
          if (selected) {
            return pressed
                ? SakuraNightGardenSpec.darkCherrywood.withAlpha(238)
                : hovered
                ? SakuraNightGardenSpec.rosewood.withAlpha(224)
                : SakuraNightGardenSpec.rosewood.withAlpha(174);
          }
          if (pressed) {
            return SakuraNightGardenSpec.darkCherrywood.withAlpha(188);
          }
          if (hovered) {
            return SakuraNightGardenSpec.dustySakura.withAlpha(34);
          }
          return Colors.transparent;
        }
        final accent = StandardSpec.accentBrush(
          standard.accentHue,
          neon: standard.neon,
        );
        if (selected) return accent.withAlpha(pressed ? 102 : 72);
        if (pressed) return accent.withAlpha(50);
        if (hovered) return accent.withAlpha(34);
        return Colors.transparent;
      }),
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      textStyle: WidgetStatePropertyAll<TextStyle>(
        spec.typography.body.copyWith(
          fontFamily: ledger ? 'Georgia' : spec.typography.body.fontFamily,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class AppToggle extends StatelessWidget {
  const AppToggle({
    required this.value,
    required this.onChanged,
    required this.label,
    this.description,
    this.leading,
    this.switchAtEnd = false,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;
  final String? description;
  final Widget? leading;
  final bool switchAtEnd;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final enabled = onChanged != null;
    final control = _AppToggleControl(
      value: value,
      spec: spec,
      ledger: ledger,
      sakura: sakura,
    );
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: label,
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        borderRadius: BorderRadius.circular(spec.geometry.fieldRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading!,
                const SizedBox(width: 10),
              ],
              if (!switchAtEnd) ...<Widget>[control, const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sakura
                          ? spec.typography.body.copyWith(
                              fontSize: 13,
                              height: 1.05,
                            )
                          : spec.typography.body,
                    ),
                    if (description != null)
                      Text(
                        description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sakura
                            ? spec.typography.meta.copyWith(
                                fontSize: 10.5,
                                height: 1.05,
                              )
                            : spec.typography.meta,
                      ),
                  ],
                ),
              ),
              if (switchAtEnd) ...<Widget>[const SizedBox(width: 12), control],
            ],
          ),
        ),
      ),
    );
  }
}

class _AppToggleControl extends StatelessWidget {
  const _AppToggleControl({
    required this.value,
    required this.spec,
    required this.ledger,
    required this.sakura,
  });

  final bool value;
  final ThemeSpec spec;
  final bool ledger;
  final bool sakura;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: spec.motion.interactionDuration,
    width: 38,
    height: 22,
    padding: const EdgeInsets.all(3),
    alignment: value ? Alignment.centerRight : Alignment.centerLeft,
    decoration: BoxDecoration(
      color: sakura
          ? null
          : value
          ? spec.palette.primary
          : spec.palette.surfaceInset,
      gradient: sakura
          ? value
                ? SakuraNightGardenSpec.mossGradient
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      SakuraNightGardenSpec.charcoalPlum,
                      SakuraNightGardenSpec.insetPlum,
                    ],
                  )
          : null,
      borderRadius: BorderRadius.circular(
        ledger
            ? 3
            : sakura
            ? spec.geometry.fieldRadius
            : 999,
      ),
      border: Border.all(
        color: sakura
            ? value
                  ? spec.palette.secondary
                  : spec.palette.trim.withAlpha(190)
            : value
            ? spec.palette.primaryBright
            : spec.palette.trim,
      ),
      boxShadow: sakura
          ? <BoxShadow>[
              BoxShadow(
                color: spec.palette.shadow.withAlpha(70),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ]
          : null,
    ),
    child: Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: sakura
            ? value
                  ? SakuraNightGardenSpec.warmIvory
                  : SakuraNightGardenSpec.mutedText
            : value
            ? spec.palette.text
            : spec.palette.textMuted,
        shape: BoxShape.circle,
        border: sakura
            ? Border.all(
                color: value
                    ? spec.palette.primaryBright.withAlpha(104)
                    : spec.palette.trim.withAlpha(96),
                width: .7,
              )
            : null,
      ),
    ),
  );
}

class AppChoiceChip extends StatefulWidget {
  const AppChoiceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;

  static const Key materialKey = ValueKey<String>('app-choice-material');

  @override
  State<AppChoiceChip> createState() => _AppChoiceChipState();
}

class _AppChoiceChipState extends State<AppChoiceChip> {
  late final FocusNode _ownedFocusNode = FocusNode();
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onSelected != null;
  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode;

  @override
  void didUpdateWidget(AppChoiceChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled && (_hovered || _pressed)) {
      _hovered = false;
      _pressed = false;
    }
  }

  @override
  void dispose() {
    _ownedFocusNode.dispose();
    super.dispose();
  }

  void _activate() {
    if (_enabled) widget.onSelected!(!widget.selected);
  }

  Object? _keyboardActivate(ActivateIntent intent) {
    if (!_enabled) return null;
    setState(() => _pressed = true);
    _activate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _pressed = false);
    });
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final visual = _AppChoiceVisual.resolve(
      spec: spec,
      standard: context.standardVisual,
      selected: widget.selected,
      enabled: _enabled,
      hovered: _hovered,
      pressed: _pressed,
      focused: _focused,
    );
    final plate = AnimatedContainer(
      key: AppChoiceChip.materialKey,
      duration: spec.motion.interactionDuration,
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: visual.gradient,
        borderRadius: BorderRadius.circular(visual.radius),
        border: Border.all(
          color: visual.borderColor,
          width: visual.borderWidth,
        ),
        boxShadow: visual.shadows,
      ),
      child: Center(
        child: Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: spec.typography.button.copyWith(
            color: visual.foreground,
            fontFamily: ledger ? 'Georgia' : spec.typography.button.fontFamily,
            fontSize: ledger ? 14 : 13,
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: _enabled,
      label: widget.semanticLabel ?? widget.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: _enabled,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        mouseCursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onShowHoverHighlight: (value) {
          if (_hovered != value && _enabled) {
            setState(() => _hovered = value);
          }
        },
        onShowFocusHighlight: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: _keyboardActivate,
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled
              ? (_) {
                  _focusNode.requestFocus();
                  setState(() => _pressed = true);
                }
              : null,
          onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
          onTap: _enabled ? _activate : null,
          child: plate,
        ),
      ),
    );
  }
}

@immutable
final class _AppChoiceVisual {
  const _AppChoiceVisual({
    required this.gradient,
    required this.foreground,
    required this.borderColor,
    required this.borderWidth,
    required this.radius,
    required this.shadows,
    required this.toolingColor,
  });

  final Gradient gradient;
  final Color foreground;
  final Color borderColor;
  final double borderWidth;
  final double radius;
  final List<BoxShadow> shadows;
  final Color toolingColor;

  static _AppChoiceVisual resolve({
    required ThemeSpec spec,
    required StandardVisualSettings standard,
    required bool selected,
    required bool enabled,
    required bool hovered,
    required bool pressed,
    required bool focused,
  }) {
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    late Gradient gradient;
    late Color foreground;
    late Color border;
    late Color tooling;
    late double radius;
    if (ledger) {
      gradient = selected
          ? LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: pressed
                  ? const <Color>[Color(0xFF0B3B69), Color(0xFF071F38)]
                  : hovered
                  ? const <Color>[Color(0xFF24679D), Color(0xFF0D385F)]
                  : const <Color>[Color(0xFF174F82), Color(0xFF092B4C)],
            )
          : LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: pressed
                  ? const <Color>[Color(0xFFE0BF7D), Color(0xFFC39A53)]
                  : hovered
                  ? const <Color>[Color(0xFFFFEDBF), Color(0xFFE5C47F)]
                  : const <Color>[Color(0xFFF7E5B3), Color(0xFFD8B66F)],
            );
      foreground = selected ? const Color(0xFFFFF2CF) : const Color(0xFF402814);
      border = selected ? spec.palette.trimBright : spec.palette.trim;
      tooling = selected
          ? spec.palette.trimBright.withAlpha(172)
          : spec.palette.trim.withAlpha(142);
      radius = 2;
    } else if (sakura) {
      gradient = selected
          ? LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: pressed
                  ? const <Color>[
                      Color(0xFF4D2938),
                      Color(0xFF341E29),
                      SakuraNightGardenSpec.insetPlum,
                    ]
                  : hovered
                  ? const <Color>[
                      Color(0xFF855068),
                      Color(0xFF663A50),
                      Color(0xFF432534),
                    ]
                  : const <Color>[
                      Color(0xFF743E50),
                      Color(0xFF5A2E40),
                      Color(0xFF3A202D),
                    ],
            )
          : LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: pressed
                  ? const <Color>[
                      SakuraNightGardenSpec.insetPlum,
                      SakuraNightGardenSpec.charcoalPlum,
                    ]
                  : hovered
                  ? const <Color>[
                      Color(0xFF392A34),
                      SakuraNightGardenSpec.raisedPlum,
                      Color(0xFF1D171D),
                    ]
                  : const <Color>[
                      Color(0xFF30252D),
                      SakuraNightGardenSpec.charcoalPlum,
                      SakuraNightGardenSpec.insetPlum,
                    ],
            );
      foreground = selected
          ? SakuraNightGardenSpec.warmIvory
          : spec.palette.text;
      border = selected
          ? spec.palette.primary
          : focused
          ? spec.palette.trimBright
          : spec.palette.trim.withAlpha(198);
      tooling = selected
          ? spec.palette.primaryBright.withAlpha(150)
          : spec.palette.trimBright.withAlpha(118);
      radius = spec.geometry.buttonRadius;
    } else {
      final selectedTop = pressed
          ? 174
          : hovered
          ? 236
          : 214;
      final selectedBottom = pressed
          ? 116
          : hovered
          ? 186
          : 160;
      gradient = StandardSpec.accentGlass(
        standard.accentHue,
        topAlpha: selected
            ? selectedTop
            : pressed
            ? 34
            : hovered
            ? 82
            : 48,
        bottomAlpha: selected
            ? selectedBottom
            : pressed
            ? 12
            : hovered
            ? 32
            : 16,
        neon: standard.neon,
      );
      foreground = selected ? const Color(0xFFF4FFF9) : const Color(0xFFFFF1D1);
      border = StandardSpec.accentBrush(
        standard.accentHue,
        alpha: selected
            ? .86
            : focused
            ? .7
            : hovered
            ? .5
            : .3,
        neon: standard.neon,
      );
      tooling = border;
      radius = 7;
    }
    final shadows = <BoxShadow>[
      if (focused)
        BoxShadow(
          color:
              (ledger
                      ? spec.palette.primary
                      : sakura
                      ? spec.palette.primaryBright
                      : border)
                  .withAlpha(138),
          blurRadius: 5,
          spreadRadius: 1,
        ),
      if (selected && enabled)
        BoxShadow(
          color: (ledger || sakura ? spec.palette.shadow : border).withAlpha(
            ledger
                ? 82
                : sakura
                ? 104
                : 52,
          ),
          blurRadius: ledger
              ? 3
              : sakura
              ? 5
              : 7,
          offset: Offset(0, sakura ? 2 : 1),
        ),
    ];
    if (!enabled) {
      foreground = spec.palette.textMuted.withAlpha(116);
      border = border.withAlpha(76);
      tooling = tooling.withAlpha(62);
      gradient = LinearGradient(
        colors: <Color>[
          spec.palette.surfaceInset.withAlpha(118),
          spec.palette.surfaceInset.withAlpha(74),
        ],
      );
    }
    return _AppChoiceVisual(
      gradient: gradient,
      foreground: foreground,
      borderColor: border,
      borderWidth: focused
          ? 1.6
          : selected
          ? 1.2
          : 1,
      radius: radius,
      shadows: shadows,
      toolingColor: tooling,
    );
  }
}

class AppSlider extends StatefulWidget {
  const AppSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.label,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final int? divisions;
  final String? label;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;

  static const Key paintKey = ValueKey<String>('app-slider-paint');

  @override
  State<AppSlider> createState() => _AppSliderState();
}

class _AppSliderState extends State<AppSlider> {
  late final FocusNode _ownedFocusNode = FocusNode();
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;
  double? _transientValue;

  bool get _enabled => widget.onChanged != null && widget.max > widget.min;
  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode;

  double get _safeValue => _normalize(
    _transientValue ?? widget.value.clamp(widget.min, widget.max).toDouble(),
  );

  @override
  void didUpdateWidget(AppSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value ||
        widget.min != oldWidget.min ||
        widget.max != oldWidget.max ||
        widget.divisions != oldWidget.divisions) {
      _transientValue = null;
    }
    if (!_enabled && (_hovered || _pressed || _transientValue != null)) {
      _hovered = false;
      _pressed = false;
      _transientValue = null;
    }
  }

  @override
  void dispose() {
    _ownedFocusNode.dispose();
    super.dispose();
  }

  double _normalize(double raw) {
    if (widget.max <= widget.min) return widget.min;
    final clamped = raw.clamp(widget.min, widget.max).toDouble();
    final divisions = widget.divisions;
    if (divisions == null || divisions <= 0) return clamped;
    final step = (widget.max - widget.min) / divisions;
    final index = ((clamped - widget.min) / step).round();
    return (widget.min + index * step).clamp(widget.min, widget.max).toDouble();
  }

  void _emit(double raw) {
    if (!_enabled) return;
    final next = _normalize(raw);
    if (_transientValue == next && next == widget.value) return;
    setState(() => _transientValue = next);
    widget.onChanged!(next);
  }

  void _emitAt(Offset localPosition, double width) {
    const horizontalInset = 12.0;
    final trackWidth = (width - horizontalInset * 2).clamp(1, double.infinity);
    final fraction = ((localPosition.dx - horizontalInset) / trackWidth).clamp(
      0,
      1,
    );
    _emit(widget.min + (widget.max - widget.min) * fraction);
  }

  double get _step {
    final divisions = widget.divisions;
    if (divisions != null && divisions > 0) {
      return (widget.max - widget.min) / divisions;
    }
    return (widget.max - widget.min) / 100;
  }

  Object? _adjust(_SliderAdjustmentIntent intent) {
    if (!_enabled) return null;
    _emit(_safeValue + _step * intent.steps);
    return null;
  }

  Object? _jump(_SliderEdgeIntent intent) {
    if (!_enabled) return null;
    _emit(intent.maximum ? widget.max : widget.min);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final value = _safeValue;
    final fraction = widget.max <= widget.min
        ? 0.0
        : ((value - widget.min) / (widget.max - widget.min))
              .clamp(0, 1)
              .toDouble();
    return Semantics(
      slider: true,
      enabled: _enabled,
      focusable: _enabled,
      focused: _focused,
      label: widget.semanticLabel,
      value: widget.label ?? value.toStringAsFixed(2),
      increasedValue: _enabled
          ? _normalize(value + _step).toStringAsFixed(2)
          : null,
      decreasedValue: _enabled
          ? _normalize(value - _step).toStringAsFixed(2)
          : null,
      onIncrease: _enabled
          ? () => _adjust(const _SliderAdjustmentIntent(1))
          : null,
      onDecrease: _enabled
          ? () => _adjust(const _SliderAdjustmentIntent(-1))
          : null,
      child: FocusableActionDetector(
        enabled: _enabled,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        mouseCursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onShowHoverHighlight: (next) {
          if (_hovered != next && _enabled) setState(() => _hovered = next);
        },
        onShowFocusHighlight: (next) {
          if (_focused != next) setState(() => _focused = next);
        },
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowLeft):
              _SliderAdjustmentIntent(-1),
          SingleActivator(LogicalKeyboardKey.arrowDown):
              _SliderAdjustmentIntent(-1),
          SingleActivator(LogicalKeyboardKey.arrowRight):
              _SliderAdjustmentIntent(1),
          SingleActivator(LogicalKeyboardKey.arrowUp): _SliderAdjustmentIntent(
            1,
          ),
          SingleActivator(LogicalKeyboardKey.pageDown): _SliderAdjustmentIntent(
            -10,
          ),
          SingleActivator(LogicalKeyboardKey.pageUp): _SliderAdjustmentIntent(
            10,
          ),
          SingleActivator(LogicalKeyboardKey.home): _SliderEdgeIntent(false),
          SingleActivator(LogicalKeyboardKey.end): _SliderEdgeIntent(true),
        },
        actions: <Type, Action<Intent>>{
          _SliderAdjustmentIntent: CallbackAction<_SliderAdjustmentIntent>(
            onInvoke: _adjust,
          ),
          _SliderEdgeIntent: CallbackAction<_SliderEdgeIntent>(onInvoke: _jump),
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 200.0;
            return SizedBox(
              width: width,
              height: 32,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _enabled
                    ? (details) {
                        _focusNode.requestFocus();
                        setState(() => _pressed = true);
                        _emitAt(details.localPosition, width);
                      }
                    : null,
                onTapUp: _enabled
                    ? (_) => setState(() => _pressed = false)
                    : null,
                onTapCancel: _enabled
                    ? () => setState(() => _pressed = false)
                    : null,
                onHorizontalDragStart: _enabled
                    ? (details) {
                        _focusNode.requestFocus();
                        setState(() => _pressed = true);
                        _emitAt(details.localPosition, width);
                      }
                    : null,
                onHorizontalDragUpdate: _enabled
                    ? (details) => _emitAt(details.localPosition, width)
                    : null,
                onHorizontalDragEnd: _enabled
                    ? (_) => setState(() => _pressed = false)
                    : null,
                onHorizontalDragCancel: _enabled
                    ? () => setState(() => _pressed = false)
                    : null,
                child: CustomPaint(
                  key: AppSlider.paintKey,
                  painter: _AppSliderPainter(
                    spec: spec,
                    fraction: fraction,
                    enabled: _enabled,
                    hovered: _hovered,
                    pressed: _pressed,
                    focused: _focused,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SliderAdjustmentIntent extends Intent {
  const _SliderAdjustmentIntent(this.steps);

  final int steps;
}

class _SliderEdgeIntent extends Intent {
  const _SliderEdgeIntent(this.maximum);

  final bool maximum;
}

class _AppSliderPainter extends CustomPainter {
  const _AppSliderPainter({
    required this.spec,
    required this.fraction,
    required this.enabled,
    required this.hovered,
    required this.pressed,
    required this.focused,
  });

  final ThemeSpec spec;
  final double fraction;
  final bool enabled;
  final bool hovered;
  final bool pressed;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const horizontalInset = 12.0;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final centerY = size.height / 2;
    final endX = (size.width - horizontalInset).clamp(
      horizontalInset,
      double.infinity,
    );
    final thumbX = horizontalInset + (endX - horizontalInset) * fraction;
    final active = enabled
        ? sakura
              ? pressed
                    ? SakuraNightGardenSpec.rosewood
                    : hovered
                    ? SakuraNightGardenSpec.paleBlossom
                    : SakuraNightGardenSpec.dustySakura
              : pressed
              ? const Color(0xFF079AE7)
              : hovered
              ? const Color(0xFF159CE5)
              : const Color(0xFF078DD6)
        : spec.palette.textMuted.withAlpha(72);
    final inactive = enabled
        ? ledger
              ? const Color(0xA0786B4E)
              : sakura
              ? spec.palette.trim.withAlpha(152)
              : const Color(0x9299A69F)
        : spec.palette.trim.withAlpha(58);
    final trackHeight = ledger
        ? 1.5
        : sakura
        ? 2.2
        : 2.0;
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        horizontalInset,
        centerY - trackHeight / 2,
        endX,
        centerY + trackHeight / 2,
      ),
      const Radius.circular(99),
    );
    canvas.drawRRect(trackRect, Paint()..color = inactive);
    if (thumbX > horizontalInset) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            horizontalInset,
            centerY - trackHeight / 2,
            thumbX,
            centerY + trackHeight / 2,
          ),
          const Radius.circular(99),
        ),
        Paint()..color = active,
      );
    }
    final double thumbRadius = pressed
        ? 10.5
        : hovered
        ? 10.0
        : 9.5;
    final thumbCenter = Offset(thumbX, centerY);
    if (focused) {
      canvas.drawCircle(
        thumbCenter,
        thumbRadius + 4,
        Paint()
          ..color = active.withAlpha(42)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        thumbCenter,
        thumbRadius + 3,
        Paint()
          ..color = ledger
              ? spec.palette.trimBright
              : sakura
              ? spec.palette.primaryBright.withAlpha(218)
              : active.withAlpha(214)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    } else if (hovered && enabled) {
      canvas.drawCircle(
        thumbCenter,
        thumbRadius + 3,
        Paint()..color = active.withAlpha(35),
      );
    }
    canvas.drawCircle(
      thumbCenter.translate(0, 1.3),
      thumbRadius + .5,
      Paint()..color = spec.palette.shadow.withAlpha(enabled ? 88 : 42),
    );
    canvas.drawCircle(thumbCenter, thumbRadius, Paint()..color = active);
    canvas.drawCircle(
      thumbCenter,
      thumbRadius,
      Paint()
        ..color = enabled
            ? sakura
                  ? spec.palette.primaryBright.withAlpha(190)
                  : const Color(0x879EE7FF)
            : spec.palette.trim.withAlpha(60)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_AppSliderPainter oldDelegate) =>
      oldDelegate.spec != spec ||
      oldDelegate.fraction != fraction ||
      oldDelegate.enabled != enabled ||
      oldDelegate.hovered != hovered ||
      oldDelegate.pressed != pressed ||
      oldDelegate.focused != focused;
}

class AppSelect<T> extends StatefulWidget {
  const AppSelect({
    required this.value,
    required this.items,
    required this.labelFor,
    required this.onChanged,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  final T value;
  final List<T> items;
  final String Function(T value) labelFor;
  final ValueChanged<T?>? onChanged;
  final String? semanticLabel;

  final FocusNode? focusNode;
  final bool autofocus;

  static const Key anchorMaterialKey = ValueKey<String>(
    'app-select-anchor-material',
  );

  /// Width required to show the longest closed label at the theme's normal
  /// body size, including the selector padding and chevron.
  static double readableWidthFor<T>(
    BuildContext context, {
    required Iterable<T> items,
    required String Function(T value) labelFor,
    double minimumWidth = 88,
    double? maximumWidth,
  }) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final measurementStyle = spec.typography.body.copyWith(
      fontFamily: ledger ? 'Georgia' : spec.typography.body.fontFamily,
      fontWeight: FontWeight.w700,
    );
    var longestLabelWidth = 0.0;
    for (final item in items) {
      final painter = TextPainter(
        text: TextSpan(text: labelFor(item), style: measurementStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      if (painter.width > longestLabelWidth) {
        longestLabelWidth = painter.width;
      }
    }
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final upperBound = (maximumWidth ?? viewportWidth)
        .clamp(0.0, viewportWidth)
        .toDouble();
    final lowerBound = minimumWidth.clamp(0.0, upperBound).toDouble();
    return (longestLabelWidth + 43).clamp(lowerBound, upperBound).toDouble();
  }

  @override
  State<AppSelect<T>> createState() => _AppSelectState<T>();
}

class _AppSelectState<T> extends State<AppSelect<T>> {
  final MenuController _menuController = MenuController();
  late final FocusNode _ownedFocusNode = FocusNode();
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;
  bool _expanded = false;

  bool get _enabled => widget.onChanged != null && widget.items.isNotEmpty;
  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode;

  @override
  void didUpdateWidget(AppSelect<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) {
      _menuController.close();
      _hovered = false;
      _pressed = false;
    }
  }

  @override
  void dispose() {
    _ownedFocusNode.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (!_enabled) return;
    _focusNode.requestFocus();
    if (_menuController.isOpen) {
      _menuController.close();
    } else {
      _menuController.open();
    }
  }

  Object? _keyboardToggle(ActivateIntent intent) {
    _toggleMenu();
    return null;
  }

  Object? _keyboardOpen(_OpenSelectIntent intent) {
    if (_enabled && !_menuController.isOpen) _menuController.open();
    return null;
  }

  Object? _keyboardAdjust(_AdjustSelectIntent intent) {
    if (!_enabled) return null;
    final current = widget.items.indexOf(widget.value);
    final base = current < 0 ? 0 : current;
    final next = (base + intent.delta).clamp(0, widget.items.length - 1);
    if (next != current) widget.onChanged?.call(widget.items[next]);
    return null;
  }

  Object? _keyboardEdge(_SelectEdgeIntent intent) {
    if (!_enabled) return null;
    final next = intent.last ? widget.items.length - 1 : 0;
    if (widget.items[next] != widget.value) {
      widget.onChanged?.call(widget.items[next]);
    }
    return null;
  }

  Object? _keyboardDismiss(DismissIntent intent) {
    if (_menuController.isOpen) _menuController.close();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final standard = context.standardVisual;
    final selectedLabel = widget.labelFor(widget.value);
    final anchorVisual = _AppSelectVisual.resolve(
      spec: spec,
      standard: standard,
      enabled: _enabled,
      hovered: _hovered,
      pressed: _pressed,
      focused: _focused,
      expanded: _expanded,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final preferredControlWidth = _readableControlWidth(context, spec);
        final controlWidth = constraints.hasBoundedWidth
            ? preferredControlWidth
                  .clamp(constraints.minWidth, constraints.maxWidth)
                  .toDouble()
            : preferredControlWidth;
        final menuWidth = _readableMenuWidth(
          context,
          spec,
          minimumWidth: controlWidth,
        );
        return SizedBox(
          width: controlWidth,
          child: MenuAnchor(
            controller: _menuController,
            childFocusNode: _focusNode,
            crossAxisUnconstrained: true,
            consumeOutsideTap: false,
            clipBehavior: Clip.antiAlias,
            onOpen: () {
              if (mounted) setState(() => _expanded = true);
            },
            onClose: () {
              if (mounted) {
                setState(() {
                  _expanded = false;
                  _pressed = false;
                });
              }
            },
            style: MenuStyle(
              backgroundColor: WidgetStatePropertyAll<Color>(
                ledger
                    ? const Color(0xFFF0D99F)
                    : sakura
                    ? SakuraNightGardenSpec.raisedPlum
                    : const Color.fromARGB(250, 7, 24, 19),
              ),
              surfaceTintColor: const WidgetStatePropertyAll<Color>(
                Colors.transparent,
              ),
              shadowColor: WidgetStatePropertyAll<Color>(spec.palette.shadow),
              elevation: WidgetStatePropertyAll<double>(
                ledger || sakura ? 12 : 10,
              ),
              shape: WidgetStatePropertyAll<OutlinedBorder>(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    ledger ? 2 : spec.geometry.fieldRadius,
                  ),
                ),
              ),
              side: WidgetStatePropertyAll<BorderSide>(
                BorderSide(
                  color: ledger
                      ? spec.palette.trimBright
                      : sakura
                      ? spec.palette.trim.withAlpha(224)
                      : StandardSpec.accentBrush(
                          standard.accentHue,
                          alpha: .62,
                          neon: standard.neon,
                        ),
                  width: ledger
                      ? 1.2
                      : sakura
                      ? 1.1
                      : 1,
                ),
              ),
              padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                EdgeInsets.symmetric(vertical: 4),
              ),
              minimumSize: WidgetStatePropertyAll<Size>(Size(menuWidth, 0)),
              maximumSize: WidgetStatePropertyAll<Size>(Size(menuWidth, 420)),
            ),
            menuChildren: <Widget>[
              for (final item in widget.items)
                Semantics(
                  selected: item == widget.value,
                  label: widget.labelFor(item),
                  child: MenuItemButton(
                    semanticsLabel: widget.labelFor(item),
                    closeOnActivate: true,
                    requestFocusOnHover: true,
                    style: _menuItemStyle(
                      spec: spec,
                      standard: standard,
                      selected: item == widget.value,
                    ),
                    onPressed: _enabled
                        ? () => widget.onChanged?.call(item)
                        : null,
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 18,
                          child: item == widget.value
                              ? AppVectorGlyph(
                                  'check',
                                  size: 13,
                                  color: ledger
                                      ? const Color(0xFFFFE7A4)
                                      : sakura
                                      ? spec.palette.primaryBright
                                      : StandardSpec.accentBrush(
                                          standard.accentHue,
                                          neon: standard.neon,
                                        ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(widget.labelFor(item), softWrap: true),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            builder: (context, controller, child) => Semantics(
              button: true,
              enabled: _enabled,
              focusable: _enabled,
              focused: _focused,
              expanded: _expanded,
              label: widget.semanticLabel,
              value: selectedLabel,
              onTap: _enabled ? _toggleMenu : null,
              child: FocusableActionDetector(
                enabled: _enabled,
                focusNode: _focusNode,
                autofocus: widget.autofocus,
                mouseCursor: _enabled
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.forbidden,
                onShowHoverHighlight: (next) {
                  if (_hovered != next && _enabled) {
                    setState(() => _hovered = next);
                  }
                },
                onShowFocusHighlight: (next) {
                  if (_focused != next) setState(() => _focused = next);
                },
                shortcuts: <ShortcutActivator, Intent>{
                  const SingleActivator(LogicalKeyboardKey.enter):
                      const ActivateIntent(),
                  const SingleActivator(LogicalKeyboardKey.space):
                      const ActivateIntent(),
                  const SingleActivator(LogicalKeyboardKey.arrowDown):
                      const _AdjustSelectIntent(1),
                  const SingleActivator(LogicalKeyboardKey.arrowUp):
                      const _AdjustSelectIntent(-1),
                  const SingleActivator(LogicalKeyboardKey.home):
                      const _SelectEdgeIntent(last: false),
                  const SingleActivator(LogicalKeyboardKey.end):
                      const _SelectEdgeIntent(last: true),
                  const SingleActivator(
                    LogicalKeyboardKey.arrowDown,
                    alt: true,
                  ): const _OpenSelectIntent(),
                  if (_expanded)
                    const SingleActivator(LogicalKeyboardKey.escape):
                        const DismissIntent(),
                },
                actions: <Type, Action<Intent>>{
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: _keyboardToggle,
                  ),
                  _OpenSelectIntent: CallbackAction<_OpenSelectIntent>(
                    onInvoke: _keyboardOpen,
                  ),
                  _AdjustSelectIntent: CallbackAction<_AdjustSelectIntent>(
                    onInvoke: _keyboardAdjust,
                  ),
                  _SelectEdgeIntent: CallbackAction<_SelectEdgeIntent>(
                    onInvoke: _keyboardEdge,
                  ),
                  if (_expanded)
                    DismissIntent: CallbackAction<DismissIntent>(
                      onInvoke: _keyboardDismiss,
                    ),
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: _enabled
                      ? (_) {
                          _focusNode.requestFocus();
                          setState(() => _pressed = true);
                        }
                      : null,
                  onTapUp: _enabled
                      ? (_) => setState(() => _pressed = false)
                      : null,
                  onTapCancel: _enabled
                      ? () => setState(() => _pressed = false)
                      : null,
                  onTap: _enabled ? _toggleMenu : null,
                  child: AnimatedContainer(
                    key: AppSelect.anchorMaterialKey,
                    duration: spec.motion.interactionDuration,
                    curve: Curves.easeOutCubic,
                    constraints: const BoxConstraints(minHeight: 28),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      gradient: anchorVisual.gradient,
                      borderRadius: BorderRadius.circular(anchorVisual.radius),
                      border: Border.all(
                        color: anchorVisual.borderColor,
                        width: anchorVisual.borderWidth,
                      ),
                      boxShadow: anchorVisual.shadows,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        Positioned.fill(
                          child: AnimatedContainer(
                            duration: spec.motion.interactionDuration,
                            color: anchorVisual.stateOverlay,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  selectedLabel,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: spec.typography.body.copyWith(
                                    color: anchorVisual.foreground,
                                    fontFamily: ledger
                                        ? 'Georgia'
                                        : spec.typography.body.fontFamily,
                                    fontWeight: ledger
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    height: ledger
                                        ? 1.15
                                        : spec.typography.body.height,
                                    leadingDistribution: ledger
                                        ? TextLeadingDistribution.even
                                        : spec
                                              .typography
                                              .body
                                              .leadingDistribution,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              AnimatedRotation(
                                turns: _expanded ? .5 : 0,
                                duration: spec.motion.interactionDuration,
                                child: AppVectorGlyph(
                                  'chevron-down',
                                  size: 15,
                                  color: anchorVisual.chevron,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _readableControlWidth(BuildContext context, ThemeSpec spec) {
    return AppSelect.readableWidthFor<T>(
      context,
      items: widget.items,
      labelFor: widget.labelFor,
    );
  }

  double _readableMenuWidth(
    BuildContext context,
    ThemeSpec spec, {
    required double minimumWidth,
  }) {
    final viewportLimit = (MediaQuery.sizeOf(context).width - 24)
        .clamp(0.0, double.infinity)
        .toDouble();
    final floor = minimumWidth.clamp(0.0, viewportLimit).toDouble();
    return (_longestLabelWidth(context, spec) + 62)
        .clamp(floor, viewportLimit)
        .toDouble();
  }

  double _longestLabelWidth(BuildContext context, ThemeSpec spec) {
    final ledger = spec.isIlluminatedLedger;
    final measurementStyle = spec.typography.body.copyWith(
      fontFamily: ledger ? 'Georgia' : spec.typography.body.fontFamily,
      fontWeight: FontWeight.w700,
    );
    var longestLabelWidth = 0.0;
    for (final item in widget.items) {
      final painter = TextPainter(
        text: TextSpan(text: widget.labelFor(item), style: measurementStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      if (painter.width > longestLabelWidth) {
        longestLabelWidth = painter.width;
      }
    }
    return longestLabelWidth;
  }

  ButtonStyle _menuItemStyle({
    required ThemeSpec spec,
    required StandardVisualSettings standard,
    required bool selected,
  }) {
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    return ButtonStyle(
      animationDuration: spec.motion.interactionDuration,
      splashFactory: NoSplash.splashFactory,
      elevation: const WidgetStatePropertyAll<double>(0),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      ),
      minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 36)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      alignment: Alignment.centerLeft,
      shape: const WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return spec.palette.textMuted.withAlpha(102);
        }
        if (ledger && selected) return const Color(0xFFFFEBC0);
        if (ledger) return const Color(0xFF412A17);
        if (sakura && selected) return SakuraNightGardenSpec.warmIvory;
        if (sakura) return spec.palette.text;
        return const Color(0xFFFFF1D3);
      }),
      backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused);
        final pressed = states.contains(WidgetState.pressed);
        if (ledger) {
          if (selected) {
            return pressed
                ? const Color(0xFF082A4A)
                : hovered
                ? const Color(0xFF1C5B8E)
                : const Color(0xFF123F6A);
          }
          if (pressed) return const Color(0xFFD4B16E);
          if (hovered) return const Color(0xFFE5C985);
          return Colors.transparent;
        }
        if (sakura) {
          if (selected) {
            return pressed
                ? SakuraNightGardenSpec.darkCherrywood.withAlpha(238)
                : hovered
                ? SakuraNightGardenSpec.rosewood.withAlpha(224)
                : SakuraNightGardenSpec.rosewood.withAlpha(174);
          }
          if (pressed) {
            return SakuraNightGardenSpec.darkCherrywood.withAlpha(188);
          }
          if (hovered) {
            return SakuraNightGardenSpec.dustySakura.withAlpha(34);
          }
          return Colors.transparent;
        }
        final accent = StandardSpec.accentBrush(
          standard.accentHue,
          neon: standard.neon,
        );
        if (selected) return accent.withAlpha(pressed ? 102 : 72);
        if (pressed) return accent.withAlpha(50);
        if (hovered) return accent.withAlpha(34);
        return Colors.transparent;
      }),
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      textStyle: WidgetStatePropertyAll<TextStyle>(
        spec.typography.body.copyWith(
          fontFamily: ledger ? 'Georgia' : spec.typography.body.fontFamily,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _OpenSelectIntent extends Intent {
  const _OpenSelectIntent();
}

class _AdjustSelectIntent extends Intent {
  const _AdjustSelectIntent(this.delta);

  final int delta;
}

class _SelectEdgeIntent extends Intent {
  const _SelectEdgeIntent({required this.last});

  final bool last;
}

@immutable
final class _AppSelectVisual {
  const _AppSelectVisual({
    required this.gradient,
    required this.foreground,
    required this.chevron,
    required this.borderColor,
    required this.borderWidth,
    required this.radius,
    required this.shadows,
    required this.stateOverlay,
  });

  final Gradient gradient;
  final Color foreground;
  final Color chevron;
  final Color borderColor;
  final double borderWidth;
  final double radius;
  final List<BoxShadow> shadows;
  final Color stateOverlay;

  static _AppSelectVisual resolve({
    required ThemeSpec spec,
    required StandardVisualSettings standard,
    required bool enabled,
    required bool hovered,
    required bool pressed,
    required bool focused,
    required bool expanded,
  }) {
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final active = expanded || focused;
    final border = ledger
        ? active
              ? spec.palette.primary
              : hovered
              ? spec.palette.trimBright
              : spec.palette.trim.withAlpha(188)
        : sakura
        ? active
              ? spec.palette.primaryBright
              : hovered
              ? spec.palette.primary
              : spec.palette.trim.withAlpha(198)
        : StandardSpec.accentBrush(
            standard.accentHue,
            alpha: active
                ? .82
                : hovered
                ? .52
                : .32,
            neon: standard.neon,
          );
    final gradient = ledger
        ? spec.materials.surfaceRaised
        : sakura
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: expanded
                ? const <Color>[
                    Color(0xFF3A2834),
                    SakuraNightGardenSpec.raisedPlum,
                    SakuraNightGardenSpec.insetPlum,
                  ]
                : hovered
                ? const <Color>[
                    Color(0xFF382A34),
                    SakuraNightGardenSpec.raisedPlum,
                    Color(0xFF1B151B),
                  ]
                : const <Color>[
                    Color(0xFF30252D),
                    SakuraNightGardenSpec.charcoalPlum,
                    SakuraNightGardenSpec.insetPlum,
                  ],
          )
        : StandardSpec.accentGlass(
            standard.accentHue,
            topAlpha: expanded
                ? 88
                : hovered
                ? 70
                : 54,
            bottomAlpha: expanded
                ? 38
                : hovered
                ? 28
                : 18,
            neon: standard.neon,
          );
    final shadows = <BoxShadow>[
      if (ledger) ...spec.materials.lowShadow,
      if (sakura)
        BoxShadow(
          color: spec.palette.shadow.withAlpha(100),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      if (focused)
        BoxShadow(color: border.withAlpha(110), blurRadius: 5, spreadRadius: 1),
    ];
    return _AppSelectVisual(
      gradient: gradient,
      foreground: enabled
          ? spec.palette.text
          : spec.palette.textMuted.withAlpha(112),
      chevron: enabled
          ? ledger
                ? spec.palette.primary
                : sakura
                ? spec.palette.primaryBright
                : spec.palette.text
          : spec.palette.textMuted.withAlpha(92),
      borderColor: enabled ? border : spec.palette.trim.withAlpha(62),
      borderWidth: active
          ? 1.5
          : ledger
          ? 1.1
          : sakura
          ? 1
          : 1,
      radius: ledger ? 2 : spec.geometry.fieldRadius,
      shadows: shadows,
      stateOverlay: pressed
          ? spec.palette.shadow.withAlpha(38)
          : expanded
          ? spec.palette.primary.withAlpha(
              ledger
                  ? 22
                  : sakura
                  ? 16
                  : 18,
            )
          : Colors.transparent,
    );
  }
}
