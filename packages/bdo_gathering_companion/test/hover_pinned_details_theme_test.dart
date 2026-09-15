import 'dart:ui' show PointerDeviceKind;

import 'package:bdo_gathering_companion/src/ui/hover_pinned_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'root hover keeps local theme and normal text at scale $scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(900, 700);
        addTearDown(tester.view.reset);
        const foreground = Color(0xffe4eeeb);
        final localTheme = ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.copyWith(
            bodyMedium: const TextStyle(fontSize: 14, color: foreground),
          ),
        );
        TextStyle? observedStyle;
        ThemeData? observedTheme;
        var pinned = 0;
        var primary = 0;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Theme(
              data: localTheme,
              child: Scaffold(
                body: Center(
                  child: HoverPinnedDetails(
                    hoverKey: const ValueKey('artifact-hover'),
                    onPin: () => pinned++,
                    cardBuilder: (context) {
                      observedStyle = DefaultTextStyle.of(context).style;
                      observedTheme = Theme.of(context);
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('2× Gathering Item Drop Rate'),
                            SizedBox(height: 12),
                            Text('+4% Gathering Item Drop Rate'),
                            SizedBox(height: 12),
                            Text('Choose one pair; these are alternatives.'),
                          ],
                        ),
                      );
                    },
                    child: TextButton(
                      key: const ValueKey('artifact-target'),
                      onPressed: () => primary++,
                      child: const Text('Artifact pair'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await pointer.addPointer(location: Offset.zero);
        await pointer.moveTo(
          tester.getCenter(find.byKey(const ValueKey('artifact-target'))),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();
        expect(find.byKey(const ValueKey('artifact-hover')), findsOneWidget);
        expect(observedTheme?.brightness, Brightness.dark);
        expect(observedTheme?.textTheme.bodyMedium?.fontSize, 14);
        expect(observedTheme?.textTheme.bodyMedium?.color, foreground);
        expect(observedStyle?.fontSize, 14);
        expect(observedStyle?.color, foreground);
        expect(observedStyle?.decoration, isNot(TextDecoration.underline));
        final card = tester.getRect(
          find.byKey(const ValueKey('artifact-hover')),
        );
        // The test font has wide square glyphs; even then the detail remains
        // bounded at both accessibility scales instead of the 48px fallback.
        expect(card.height, lessThan(scale == 1 ? 200 : 500));
        expect(card.left, greaterThanOrEqualTo(12));
        expect(card.right, lessThanOrEqualTo(888));
        expect(tester.takeException(), isNull);
        expect(pinned, 0);
        expect(primary, 0);
        await pointer.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
