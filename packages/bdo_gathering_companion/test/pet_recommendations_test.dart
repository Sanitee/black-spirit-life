import 'dart:ui' show PointerDeviceKind;

import 'package:bdo_gathering_companion/src/domain/pets.dart';
import 'package:bdo_gathering_companion/src/ui/pet_recommendations.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<PetRecommendation> pets;

  setUpAll(() async => pets = await PetCatalog.load());

  testWidgets('pet icon keeps click action and offers hover plus pin details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final toggled = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: PetRecommendations(
              methodId: 'hoe',
              pets: pets,
              onToggle: (pet) => toggled.add(pet.id),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final icon = find.byKey(const ValueKey('pet-icon-hedgehog'));
    await tester.tap(icon);
    await tester.pump();
    expect(toggled, ['hedgehog']);
    expect(find.byType(AlertDialog), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(icon));
    await tester.pump(const Duration(milliseconds: 500));
    final hover = find.byKey(const ValueKey('pet-hover-card-hedgehog'));
    expect(hover, findsOneWidget);
    for (final heading in const ['Why it helps', 'Details']) {
      expect(
        find.descendant(of: hover, matching: find.text(heading)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: hover,
        matching: find.textContaining('Right-click for details'),
      ),
      findsNothing,
    );
    await mouse.removePointer();
    await tester.pump(const Duration(milliseconds: 200));
    expect(hover, findsNothing);

    await tester.tap(
      icon,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    final pinned = find.byKey(const ValueKey('pet-details-hedgehog'));
    expect(pinned, findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(pinned, findsOneWidget);
    expect(toggled, ['hedgehog']);
    expect(tester.takeException(), isNull);
  });
}
