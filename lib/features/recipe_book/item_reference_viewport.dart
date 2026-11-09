part of 'recipe_book_item_info_view.dart';

/// Measure the existing laid-out content, without building a hidden second copy.
/// A reading window fits its introduction and longest recipe; the rest scrolls.
class _ReferenceReadingSection extends SingleChildRenderObjectWidget {
  const _ReferenceReadingSection({
    required this.recipe,
    this.heading = false,
    required super.child,
  });
  final bool recipe;
  final bool heading;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReferenceReadingSection(recipe, heading);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReferenceReadingSection renderObject,
  ) {
    if (renderObject.recipe == recipe && renderObject.heading == heading) return;
    renderObject
      ..recipe = recipe
      ..heading = heading
      ..markNeedsLayout();
  }
}

class _RenderReferenceReadingSection extends RenderProxyBox {
  _RenderReferenceReadingSection(this.recipe, this.heading);
  bool recipe, heading;
  double readingHeight = 0;

  @override
  void performLayout() {
    super.performLayout();
    readingHeight = size.height;
  }
}

class _ReferenceReadingViewport extends SingleChildRenderObjectWidget {
  const _ReferenceReadingViewport({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReferenceReadingViewport();
}

class _RenderReferenceReadingViewport extends RenderProxyBox {
  @override
  void performLayout() {
    final content = child;
    if (content == null) {
      size = constraints.smallest;
      return;
    }
    content.layout(constraints, parentUsesSize: true);
    var introduction = 0.0;
    var recipe = 0.0;
    double? firstHeading;
    void measure(RenderObject node) {
      if (node is _RenderReferenceReadingSection) {
        if (node.heading) {
          // Later outputs can have long effect descriptions. They remain in
          // the scroll content instead of making every reading window tall.
          firstHeading ??= node.readingHeight;
        } else if (node.recipe) {
          recipe = math.max(recipe, node.readingHeight);
        } else {
          introduction += node.readingHeight;
        }
        return;
      }
      node.visitChildren(measure);
    }

    content.visitChildren(measure);
    final height = introduction + (firstHeading ?? 0) + recipe;
    if (recipe > 0 && height < content.size.height) {
      content.layout(
        constraints.copyWith(
          minHeight: math.min(constraints.minHeight, height),
          maxHeight: math.min(constraints.maxHeight, height),
        ),
        parentUsesSize: true,
      );
    }
    size = constraints.constrain(content.size);
  }
}
