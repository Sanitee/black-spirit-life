import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/shell/shell.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_button.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_backdrop.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_ornament_painters.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_botanical_assets.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkspaceShell navigation', () {
    testWidgets('Processing hides advanced destinations and Bonus Recipes', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _setWindowSize(tester, const Size(1500, 940));
      await tester.pumpWidget(
        _host(
          mode: CraftMode.processing,
          destination: ShellDestination.planner,
        ),
      );

      expect(find.byKey(const ValueKey<String>('S07')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('S08')), findsNothing);
      expect(find.byKey(const ValueKey<String>('S09')), findsNothing);
      expect(find.byKey(const ValueKey<String>('S10')), findsNothing);
      expect(find.byKey(const ValueKey<String>('S11')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('S12')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('S16')), findsNothing);
      expect(find.bySemanticsLabel('Open Bonus Recipes'), findsNothing);
      expect(
        find.bySemanticsLabel('Open About Black Spirit Life'),
        findsNothing,
      );
      expect(find.bySemanticsLabel('Open Planner'), findsOneWidget);
      expect(find.byKey(ShellActionKeys.modeSelector), findsOneWidget);
      expect(
        find.byKey(ShellActionKeys.mode(CraftMode.alchemy)),
        findsOneWidget,
      );
      expect(
        find.byKey(ShellActionKeys.mode(CraftMode.cooking)),
        findsOneWidget,
      );
      expect(
        find.byKey(ShellActionKeys.mode(CraftMode.processing)),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('About remains gated until a later product update', (
      tester,
    ) async {
      await _setWindowSize(tester, const Size(1500, 940));
      await tester.pumpWidget(
        _host(
          mode: CraftMode.alchemy,
          destination: ShellDestination.planner,
          showAdvancedDestinations: true,
        ),
      );

      expect(AppIdentity.showAboutDestination, isFalse);
      expect(
        ShellDestination.about.isVisibleFor(
          CraftMode.alchemy,
          showAdvanced: true,
        ),
        isFalse,
      );
      expect(find.byKey(ShellDestination.about.actionKey), findsNothing);
      expect(
        find.bySemanticsLabel('Open About Black Spirit Life'),
        findsNothing,
      );
    });

    testWidgets(
      'Alchemy and Cooking expose every enabled navigation callback',
      (tester) async {
        await _setWindowSize(tester, const Size(1500, 940));
        final destinations = <ShellDestination>[];
        final modes = <CraftMode>[];
        await tester.pumpWidget(
          _host(
            mode: CraftMode.cooking,
            destination: ShellDestination.planner,
            showAdvancedDestinations: true,
            onDestinationChanged: destinations.add,
            onModeChanged: modes.add,
          ),
        );

        final visibleDestinations = _visibleDestinations(
          CraftMode.cooking,
          showAdvanced: true,
        );
        for (final destination in visibleDestinations) {
          expect(find.byKey(destination.actionKey), findsOneWidget);
          await tester.tap(find.byKey(destination.actionKey));
          await tester.pump();
        }
        expect(find.byKey(ShellDestination.about.actionKey), findsNothing);
        expect(destinations, visibleDestinations);

        for (final mode in CraftMode.values) {
          await tester.tap(find.byKey(ShellActionKeys.mode(mode)));
          await tester.pump();
        }
        expect(modes, CraftMode.values);
      },
    );
  });

  group('WorkspaceShell transitions', () {
    testWidgets(
      'Off replaces only content immediately and keeps shell regions',
      (tester) async {
        await _setWindowSize(tester, const Size(1500, 940));
        await tester.pumpWidget(
          const _InteractiveHost(transition: ShellContentTransition.off),
        );

        final sidebarElement = tester.element(
          find.byKey(WorkspaceShellKeys.sidebar),
        );
        final contentHostElement = tester.element(
          find.byKey(WorkspaceShellKeys.contentHost),
        );
        expect(find.byKey(ShellActionKeys.immediateTransition), findsOneWidget);
        expect(find.byKey(ShellActionKeys.animatedTransition), findsNothing);
        expect(find.byType(AnimatedSwitcher), findsNothing);
        expect(find.text('Planner workspace contents'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey<String>('S09')));
        await tester.pump();

        expect(find.text('Planner workspace contents'), findsNothing);
        expect(find.text('Inventory workspace contents'), findsOneWidget);
        expect(
          tester.element(find.byKey(WorkspaceShellKeys.sidebar)),
          same(sidebarElement),
        );
        expect(
          tester.element(find.byKey(WorkspaceShellKeys.contentHost)),
          same(contentHostElement),
        );
      },
    );

    testWidgets('reduced motion overrides a configured animated transition', (
      tester,
    ) async {
      await _setWindowSize(tester, const Size(1500, 940));
      await tester.pumpWidget(
        const _InteractiveHost(
          transition: ShellContentTransition.lift,
          reduceMotion: true,
        ),
      );

      expect(find.byKey(ShellActionKeys.immediateTransition), findsOneWidget);
      expect(find.byKey(ShellActionKeys.animatedTransition), findsNothing);
      expect(find.byType(AnimatedSwitcher), findsNothing);
    });

    testWidgets('Fade, Slide, and Lift use the content-only S14 host', (
      tester,
    ) async {
      await _setWindowSize(tester, const Size(1500, 940));
      for (final transition in <ShellContentTransition>[
        ShellContentTransition.fade,
        ShellContentTransition.slide,
        ShellContentTransition.lift,
      ]) {
        await tester.pumpWidget(_InteractiveHost(transition: transition));
        await tester.pumpAndSettle();

        expect(find.byKey(ShellActionKeys.animatedTransition), findsOneWidget);
        expect(find.byKey(ShellActionKeys.immediateTransition), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(WorkspaceShellKeys.contentHost),
            matching: find.byType(AnimatedSwitcher),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('speed presets use distinct visible transition durations', (
      tester,
    ) async {
      await _setWindowSize(tester, const Size(1500, 940));
      for (final speed in ShellContentTransitionSpeed.values) {
        await tester.pumpWidget(
          _InteractiveHost(
            key: ValueKey<ShellContentTransitionSpeed>(speed),
            transition: ShellContentTransition.fade,
            transitionSpeed: speed,
          ),
        );
        await tester.pumpAndSettle();
        final switcher = find.descendant(
          of: find.byKey(ShellActionKeys.animatedTransition),
          matching: find.byType(AnimatedSwitcher),
        );
        expect(
          tester.widget<AnimatedSwitcher>(switcher).duration,
          speed.duration,
        );
      }

      await tester.pumpWidget(
        const _InteractiveHost(
          key: ValueKey<String>('normal-transition-sample'),
          transition: ShellContentTransition.fade,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('S09')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 181));
      final fade = find
          .descendant(
            of: find.byKey(WorkspaceShellKeys.contentHost),
            matching: find.byType(FadeTransition),
          )
          .first;
      final inProgress = tester.widget<FadeTransition>(fade).opacity.value;
      expect(inProgress, greaterThan(0));
      expect(inProgress, lessThan(1));
      await tester.pump(const Duration(milliseconds: 119));
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    });
  });

  testWidgets('reference and minimum sizes preserve exact retained shell', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _setWindowSize(tester, const Size(1500, 940));
    await tester.pumpWidget(
      _host(mode: CraftMode.alchemy, destination: ShellDestination.planner),
    );

    expect(find.byKey(WorkspaceShellKeys.referenceLayout), findsOneWidget);
    expect(find.byKey(WorkspaceShellKeys.compactLayout), findsNothing);
    expect(
      tester.getSize(find.byKey(WorkspaceShellKeys.sidebar)).width,
      StandardSpec.geometry.sidebarWidth,
    );
    final referenceContent = tester.getSize(
      find.byKey(WorkspaceShellKeys.contentHost),
    );
    expect(referenceContent.width, greaterThan(1200));
    expect(referenceContent.height, greaterThan(890));

    await _setWindowSize(tester, const Size(1200, 752));
    await tester.pumpWidget(
      _host(mode: CraftMode.alchemy, destination: ShellDestination.planner),
    );

    expect(find.byKey(WorkspaceShellKeys.referenceLayout), findsOneWidget);
    expect(find.byKey(WorkspaceShellKeys.compactLayout), findsNothing);
    expect(
      tester.getSize(find.byKey(WorkspaceShellKeys.sidebar)).width,
      StandardSpec.geometry.sidebarWidth,
    );
    final minimumContent = tester.getSize(
      find.byKey(WorkspaceShellKeys.contentHost),
    );
    expect(minimumContent, const Size(916, 714));
    expect(
      tester.getTopLeft(find.byKey(WorkspaceShellKeys.sidebar)),
      const Offset(20, 20),
    );
    expect(
      tester.getTopLeft(find.byKey(WorkspaceShellKeys.contentHost)),
      const Offset(260, 20),
    );
    expect(find.bySemanticsLabel('Open Bonus Recipes'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('200% text keeps Standard navigation labels unclipped', (
    tester,
  ) async {
    await _setWindowSize(tester, const Size(1200, 752));
    await tester.pumpWidget(
      _host(
        mode: CraftMode.alchemy,
        destination: ShellDestination.planner,
        textScaler: TextScaler.linear(2),
      ),
    );

    final button = tester.getRect(find.byKey(const ValueKey<String>('S07')));
    final label = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('S07')),
        matching: find.text('Planner'),
      ),
    );
    expect(button.height, 52);
    expect(button.top, lessThanOrEqualTo(label.top));
    expect(button.bottom, greaterThanOrEqualTo(label.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'all enabled destinations remain visible and unclipped at 1200x752 and 200%',
    (tester) async {
      // WorkspaceShell is hosted below the app-owned 40 px title strip.
      await _setWindowSize(tester, const Size(1200, 712));
      for (final spec in <ThemeSpec>[
        StandardSpec.theme,
        IlluminatedLedgerSpec.theme,
        SakuraNightGardenSpec.theme,
      ]) {
        await tester.pumpWidget(
          _host(
            mode: CraftMode.alchemy,
            destination: ShellDestination.planner,
            spec: spec,
            showAdvancedDestinations: true,
            textScaler: TextScaler.linear(2),
          ),
        );
        await tester.pump();

        final sidebar = tester.getRect(find.byKey(WorkspaceShellKeys.sidebar));
        final navigation = tester.getRect(
          find.byKey(WorkspaceShellKeys.navigation),
        );
        final modeSelector = tester.getRect(
          find.byKey(ShellActionKeys.modeSelector),
        );
        expect(navigation.top, greaterThanOrEqualTo(sidebar.top));
        expect(navigation.bottom, lessThanOrEqualTo(modeSelector.top));

        for (final entry in _visibleDestinations(
          CraftMode.alchemy,
          showAdvanced: true,
        )) {
          final buttonFinder = find.byKey(entry.actionKey);
          final labelFinder = find.descendant(
            of: buttonFinder,
            matching: find.text(entry.label),
          );
          expect(
            buttonFinder,
            findsOneWidget,
            reason: '${spec.id}: ${entry.label}',
          );
          expect(
            labelFinder,
            findsOneWidget,
            reason: '${spec.id}: ${entry.label}',
          );
          final button = tester.getRect(buttonFinder);
          final label = tester.getRect(labelFinder);
          expect(button.top, greaterThanOrEqualTo(sidebar.top));
          expect(button.bottom, lessThanOrEqualTo(modeSelector.top));
          expect(button.left, lessThanOrEqualTo(label.left));
          expect(button.right, greaterThanOrEqualTo(label.right));
          expect(button.top, lessThanOrEqualTo(label.top));
          expect(button.bottom, greaterThanOrEqualTo(label.bottom));
        }
        expect(tester.takeException(), isNull, reason: spec.id);
      }
    },
  );

  testWidgets(
    'hidden editor tabs keep the visible Sakura navigation group balanced',
    (tester) async {
      await _setWindowSize(tester, const Size(1500, 940));

      Future<({Rect navigation, Rect botanical, Rect mode})> capture(
        bool showAdvanced,
      ) async {
        await tester.pumpWidget(
          _host(
            mode: CraftMode.processing,
            destination: ShellDestination.planner,
            spec: SakuraNightGardenSpec.theme,
            showAdvancedDestinations: showAdvanced,
          ),
        );
        await tester.pump();
        return (
          navigation: tester.getRect(find.byKey(WorkspaceShellKeys.navigation)),
          botanical: tester.getRect(
            find.byKey(SakuraSidebarBotanicalAsset.imageKey),
          ),
          mode: tester.getRect(find.byKey(ShellActionKeys.modeSelector)),
        );
      }

      final hidden = await capture(false);
      final advanced = await capture(true);

      expect(hidden.navigation.height, lessThan(advanced.navigation.height));
      expect(
        (hidden.navigation.center.dy - advanced.navigation.center.dy).abs(),
        lessThanOrEqualTo(11),
        reason: 'The visible destination group should remain visually balanced',
      );
      expect(hidden.botanical, advanced.botanical);
      expect(hidden.mode, advanced.mode);
      expect(hidden.navigation.bottom, lessThan(hidden.botanical.top));
      expect(advanced.navigation.bottom, lessThan(advanced.botanical.top));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Standard selected and inactive navigation keep one aligned surface',
    (tester) async {
      for (final viewport in <Size>[
        const Size(1500, 940),
        const Size(1200, 752),
      ]) {
        await _setWindowSize(tester, viewport);
        await tester.pumpWidget(
          _host(mode: CraftMode.alchemy, destination: ShellDestination.planner),
        );

        final selectedAction = find.byKey(ShellDestination.planner.actionKey);
        final inactiveAction = find.byKey(
          ShellDestination.bonusRecipes.actionKey,
        );
        final selectedMaterial = find.descendant(
          of: selectedAction,
          matching: find.byKey(AppButton.materialKey),
        );
        final inactiveMaterial = find.descendant(
          of: inactiveAction,
          matching: find.byKey(AppButton.materialKey),
        );
        final selectedLabel = find.descendant(
          of: selectedAction,
          matching: find.text(ShellDestination.planner.label),
        );
        final inactiveLabel = find.descendant(
          of: inactiveAction,
          matching: find.text(ShellDestination.bonusRecipes.label),
        );

        final selectedActionRect = tester.getRect(selectedAction);
        final inactiveActionRect = tester.getRect(inactiveAction);
        expect(
          tester.getRect(selectedMaterial),
          selectedActionRect,
          reason: '$viewport selected navigation must use its full row',
        );
        expect(
          tester.getRect(inactiveMaterial),
          inactiveActionRect,
          reason: '$viewport inactive navigation must use its full row',
        );
        expect(
          tester.getRect(selectedLabel).left,
          closeTo(tester.getRect(inactiveLabel).left, .001),
          reason: '$viewport selection must not shift the label',
        );
        expect(
          tester.getRect(selectedLabel).center.dy,
          closeTo(selectedActionRect.center.dy, .001),
          reason: '$viewport selected label must be vertically centered',
        );
        expect(
          tester.getRect(inactiveLabel).center.dy,
          closeTo(inactiveActionRect.center.dy, .001),
          reason: '$viewport inactive label must be vertically centered',
        );
        expect(
          tester.widget<Text>(selectedLabel).style!.fontSize,
          standardNavigationLabelFontSize,
          reason: '$viewport selected navigation label size',
        );
        expect(
          tester.widget<Text>(inactiveLabel).style!.fontSize,
          standardNavigationLabelFontSize,
          reason: '$viewport inactive navigation label size',
        );
      }
    },
  );

  testWidgets('content transition preserves mounted feature session state', (
    tester,
  ) async {
    await _setWindowSize(tester, const Size(1500, 940));
    await tester.pumpWidget(const _PersistentContentHost());
    await tester.enterText(find.byKey(const ValueKey('session-field')), 'kept');

    await tester.tap(find.bySemanticsLabel('Open Bonus Recipes'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('session-field')))
          .controller!
          .text,
      'kept',
    );
  });

  testWidgets('Ledger active navigation keeps selection without inset arrows', (
    tester,
  ) async {
    await _setWindowSize(tester, const Size(1500, 940));
    await tester.pumpWidget(
      _host(
        mode: CraftMode.alchemy,
        destination: ShellDestination.planner,
        spec: IlluminatedLedgerSpec.theme,
      ),
    );

    final activeAction = find.byKey(const ValueKey<String>('S07'));
    final active = tester.getRect(activeAction);
    final ribbon = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          (widget.painter is LedgerNavigationRibbonPainter ||
              widget.foregroundPainter is LedgerNavigationRibbonPainter),
    );
    expect(ribbon, findsNothing);
    expect(
      tester.getRect(
        find.descendant(
          of: activeAction,
          matching: find.byKey(AppButton.materialKey),
        ),
      ),
      active,
    );
    expect(tester.widget<AppButton>(activeAction).selected, isTrue);
    final label = tester.widget<Text>(find.text('Planner'));
    expect(label.style!.fontSize, 16);
    expect(label.style!.fontFamily, 'Georgia');
  });

  testWidgets(
    'Ledger navigation rules span each row on a 59 px baseline cadence',
    (tester) async {
      for (final viewport in <Size>[
        const Size(1500, 940),
        // The real 1200x752 window hosts WorkspaceShell below its 40 px title.
        const Size(1200, 712),
      ]) {
        await _setWindowSize(tester, viewport);
        await tester.pumpWidget(
          _host(
            mode: CraftMode.alchemy,
            destination: ShellDestination.planner,
            spec: IlluminatedLedgerSpec.theme,
            showAdvancedDestinations: true,
          ),
        );

        final visibleDestinations = _visibleDestinations(
          CraftMode.alchemy,
          showAdvanced: true,
        );
        final rowRects = <Rect>[
          for (final destination in visibleDestinations)
            tester.getRect(find.byKey(destination.actionKey)),
        ];
        // Every label uses the same 16 px Georgia metrics, so equal label-top
        // advances are equivalent to equal alphabetic-baseline advances.
        final labelTops = <double>[
          for (final destination in visibleDestinations)
            tester.getTopLeft(find.text(destination.label)).dy,
        ];
        for (var index = 1; index < rowRects.length; index++) {
          expect(
            rowRects[index].top - rowRects[index - 1].top,
            59,
            reason: '$viewport row ${visibleDestinations[index].label}',
          );
          expect(
            labelTops[index] - labelTops[index - 1],
            closeTo(59, .51),
            reason: '$viewport baseline ${visibleDestinations[index].label}',
          );
        }

        for (final destination in visibleDestinations.skip(1)) {
          final action = find.byKey(destination.actionKey);
          final material = find.descendant(
            of: action,
            matching: find.byKey(AppButton.materialKey),
          );
          final decoration =
              tester.widget<AnimatedContainer>(material).decoration!
                  as BoxDecoration;
          final border = decoration.border! as Border;
          final actionRect = tester.getRect(action);
          final materialRect = tester.getRect(material);

          expect(border.top, BorderSide.none);
          expect(border.left, BorderSide.none);
          expect(border.right, BorderSide.none);
          expect(
            border.bottom,
            const BorderSide(color: Color(0x687A5B2A), width: 1),
          );
          expect(decoration.borderRadius, BorderRadius.zero);
          expect(materialRect.left, actionRect.left);
          expect(materialRect.right, actionRect.right);
          expect(
            find.descendant(
              of: action,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is CustomPaint &&
                    widget.foregroundPainter is LedgerButtonToolingPainter,
              ),
            ),
            findsNothing,
          );
        }
      }
    },
  );

  testWidgets('Ledger sidebar uses Avalonia translucent vellum material', (
    tester,
  ) async {
    await _setWindowSize(tester, const Size(1500, 940));
    await tester.pumpWidget(
      _host(
        mode: CraftMode.alchemy,
        destination: ShellDestination.planner,
        spec: IlluminatedLedgerSpec.theme,
      ),
    );

    final material = tester.widget<DecoratedBox>(
      find.byKey(WorkspaceShellKeys.sidebarMaterial),
    );
    final decoration = material.decoration as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.begin, Alignment.centerLeft);
    expect(gradient.end, Alignment.centerRight);
    expect(gradient.colors, const <Color>[
      Color(0xB3FBE8BF),
      Color(0x8CF6E1B1),
    ]);
    expect(gradient.colors.every((color) => color.a < 1), isTrue);
    expect(
      decoration.border,
      const Border(right: BorderSide(color: Color(0x9A9A702C), width: 1)),
    );
    expect(decoration.boxShadow, const <BoxShadow>[
      BoxShadow(color: Color(0x28352516), blurRadius: 14, offset: Offset(5, 0)),
    ]);
  });

  testWidgets('Ledger marginalia uses its authored cap in the 1500 rail', (
    tester,
  ) async {
    await _setWindowSize(tester, const Size(1500, 940));
    await tester.pumpWidget(
      _host(
        mode: CraftMode.alchemy,
        destination: ShellDestination.planner,
        spec: IlluminatedLedgerSpec.theme,
      ),
    );

    final imageFinder = find.byKey(LedgerBackdrop.marginaliaKey);
    final hostRect = tester.getRect(
      find.byKey(WorkspaceShellKeys.ledgerMarginaliaHost),
    );
    final imageRect = tester.getRect(imageFinder);
    final navigationRect = tester.getRect(
      find.byKey(WorkspaceShellKeys.navigation),
    );
    final modeRect = tester.getRect(find.byKey(ShellActionKeys.modeSelector));

    expect(
      tester
          .widget<ClipRect>(find.byKey(WorkspaceShellKeys.ledgerMarginaliaHost))
          .clipBehavior,
      Clip.hardEdge,
    );
    expect(imageRect.size, const Size(193.33333333333331, 290));
    expect(imageRect.center.dx, closeTo(hostRect.center.dx, .001));
    expect(imageRect.bottom, closeTo(hostRect.bottom, .001));
    expect(hostRect.top, closeTo(navigationRect.bottom + 7, .001));
    expect(hostRect.bottom, closeTo(modeRect.top - 2, .001));
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(of: imageFinder, matching: find.byType(Opacity)),
          )
          .opacity,
      .78,
    );
    expect(
      (tester.widget<Image>(imageFinder).image as AssetImage).assetName,
      IlluminatedLedgerSpec.marginaliaAssetPath,
    );
  });

  testWidgets('Ledger marginalia uses the freed 1200x752 sidebar space', (
    tester,
  ) async {
    // WorkspaceShell is hosted below the app-owned 40 px title strip.
    await _setWindowSize(tester, const Size(1200, 712));
    await tester.pumpWidget(
      _host(
        mode: CraftMode.alchemy,
        destination: ShellDestination.planner,
        spec: IlluminatedLedgerSpec.theme,
      ),
    );

    final imageRect = tester.getRect(find.byKey(LedgerBackdrop.marginaliaKey));
    final hostRect = tester.getRect(
      find.byKey(WorkspaceShellKeys.ledgerMarginaliaHost),
    );
    final modeRect = tester.getRect(find.byKey(ShellActionKeys.modeSelector));

    // Hiding About leaves one additional 59 px navigation cadence for the
    // retained marginalia at the minimum application height.
    expect(hostRect.height, closeTo(190, .001));
    expect(imageRect.height, closeTo(hostRect.height, .001));
    expect(imageRect.width / imageRect.height, closeTo(2 / 3, .001));
    expect(imageRect.center.dx, closeTo(hostRect.center.dx, .001));
    expect(imageRect.bottom, closeTo(hostRect.bottom, .001));
    expect(hostRect.bottom, closeTo(modeRect.top - 2, .001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Standard sidebar does not acquire Ledger marginalia', (
    tester,
  ) async {
    await _setWindowSize(tester, const Size(1200, 752));
    await tester.pumpWidget(
      _host(mode: CraftMode.alchemy, destination: ShellDestination.planner),
    );

    expect(find.byKey(WorkspaceShellKeys.ledgerMarginaliaHost), findsNothing);
    expect(find.byKey(LedgerBackdrop.marginaliaKey), findsNothing);

    final material = find.descendant(
      of: find.byKey(ShellDestination.bonusRecipes.actionKey),
      matching: find.byKey(AppButton.materialKey),
    );
    final border =
        (tester.widget<AnimatedContainer>(material).decoration!
                    as BoxDecoration)
                .border!
            as Border;
    expect(border.top.style, BorderStyle.solid);
    expect(border.left, border.top);
    expect(border.right, border.top);
    expect(border.bottom, border.top);
  });
}

Widget _host({
  required CraftMode mode,
  required ShellDestination destination,
  ValueChanged<CraftMode>? onModeChanged,
  ValueChanged<ShellDestination>? onDestinationChanged,
  TextScaler textScaler = TextScaler.noScaling,
  ThemeSpec spec = StandardSpec.theme,
  bool showAdvancedDestinations = false,
}) => MaterialApp(
  theme: spec.materialTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: child!,
  ),
  home: ThemeSpecScope(
    spec: spec,
    child: WorkspaceShell(
      mode: mode,
      destination: destination,
      showAdvancedDestinations: showAdvancedDestinations,
      onModeChanged: onModeChanged ?? (_) {},
      onDestinationChanged: onDestinationChanged ?? (_) {},
      child: const ColoredBox(
        color: Color(0x2200FF88),
        child: Center(child: Text('Planner workspace contents')),
      ),
    ),
  ),
);

class _InteractiveHost extends StatefulWidget {
  const _InteractiveHost({
    required this.transition,
    this.transitionSpeed = ShellContentTransitionSpeed.normal,
    this.reduceMotion = false,
    super.key,
  });

  final ShellContentTransition transition;
  final ShellContentTransitionSpeed transitionSpeed;
  final bool reduceMotion;

  @override
  State<_InteractiveHost> createState() => _InteractiveHostState();
}

class _InteractiveHostState extends State<_InteractiveHost> {
  ShellDestination destination = ShellDestination.planner;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: StandardSpec.theme.materialTheme(),
    home: ThemeSpecScope(
      spec: StandardSpec.theme,
      child: WorkspaceShell(
        mode: CraftMode.alchemy,
        destination: destination,
        showAdvancedDestinations: true,
        transition: widget.transition,
        transitionSpeed: widget.transitionSpeed,
        reduceMotion: widget.reduceMotion,
        onModeChanged: (_) {},
        onDestinationChanged: (value) => setState(() => destination = value),
        child: ColoredBox(
          color: const Color(0x2200FF88),
          child: Center(child: Text('${destination.label} workspace contents')),
        ),
      ),
    ),
  );
}

class _PersistentContentHost extends StatefulWidget {
  const _PersistentContentHost();

  @override
  State<_PersistentContentHost> createState() => _PersistentContentHostState();
}

class _PersistentContentHostState extends State<_PersistentContentHost> {
  ShellDestination destination = ShellDestination.planner;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: StandardSpec.theme.materialTheme(),
    home: ThemeSpecScope(
      spec: StandardSpec.theme,
      child: WorkspaceShell(
        mode: CraftMode.alchemy,
        destination: destination,
        onModeChanged: (_) {},
        onDestinationChanged: (value) => setState(() => destination = value),
        child: const Material(
          color: Colors.transparent,
          child: Center(child: _PersistentField()),
        ),
      ),
    ),
  );
}

class _PersistentField extends StatefulWidget {
  const _PersistentField();

  @override
  State<_PersistentField> createState() => _PersistentFieldState();
}

class _PersistentFieldState extends State<_PersistentField> {
  final TextEditingController controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: TextField(
      key: const ValueKey('session-field'),
      controller: controller,
    ),
  );
}

List<ShellDestination> _visibleDestinations(
  CraftMode mode, {
  required bool showAdvanced,
}) => <ShellDestination>[
  for (final destination in ShellDestination.values)
    if (destination.isVisibleFor(mode, showAdvanced: showAdvanced)) destination,
];

Future<void> _setWindowSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
