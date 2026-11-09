import 'package:flutter/material.dart';

import '../../visual/visual.dart';

/// One layout contract for recipe and batch switches in every host.
class RecipeSwitchAxes extends StatelessWidget {
  const RecipeSwitchAxes({required this.children, super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 24,
    runSpacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: children,
  );
}

class RecipeSwitchAxis extends StatelessWidget {
  const RecipeSwitchAxis({required this.label, required this.child, super.key});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: spec.typography.meta.copyWith(
            color: spec.palette.textMuted,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(child: child),
      ],
    );
  }
}

/// The inset switch track used by recipe and batch choices.
class RecipeSwitchGroup extends StatelessWidget {
  const RecipeSwitchGroup({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.visualTheme.palette.surfaceInset,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: Wrap(spacing: 3, runSpacing: 3, children: children),
    ),
  );
}

/// Quiet, content-sized segments: the selected formula stays visibly inset.
class RecipeSwitchChoice extends StatelessWidget {
  const RecipeSwitchChoice({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final p = spec.palette;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onPressed != null,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onPressed,
      child: TextButton(
        onPressed: onPressed,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 37)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.standard,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          animationDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : spec.motion.interactionDuration,
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? p.textMuted.withAlpha(112)
                : p.text,
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (selected) {
              return Color.alphaBlend(p.primary.withAlpha(32), p.surfaceInset);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return p.surfaceRaised;
            }
            return Colors.transparent;
          }),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.focused)
                  ? p.primaryBright
                  : selected
                  ? p.primaryBright.withAlpha(190)
                  : states.contains(WidgetState.hovered)
                  ? p.trimBright.withAlpha(175)
                  : Colors.transparent,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(spec.geometry.buttonRadius),
            ),
          ),
          textStyle: WidgetStatePropertyAll(
            spec.typography.button.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
