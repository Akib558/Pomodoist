import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/onboarding/widgets/learning_tour_overlay.dart';
import 'package:pomodoist/ui/onboarding/view_models/learning_tour_view_model.dart';
import 'package:pomodoist/domain/models/settings/bottom_navigation_preferences.dart';
import 'package:pomodoist/ui/core/widgets/app_bottom_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/test_app.dart';

void main() {
  setUpAll(loadTestAppResources);
  testWidgets('invitation offers a choice once and later dismisses it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'learningTour.invitationPending.v1': true,
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: testAppBuilder,
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [Text('App'), LearningTourOverlay()],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Take a quick look around Pomodoist?'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Take a quick look around Pomodoist?'), findsNothing);
    expect(find.text('App'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'learningTour.invitationPending.v1',
      ),
      isFalse,
    );
  });

  testWidgets(
    'custom mobile navigation gives a way to open missing destinations',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            builder: testAppBuilder,
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: AppBottomNavigation(
                      preferences: BottomNavigationPreferences(
                        destinations: const [BottomNavigationDestination.today],
                      ),
                      selected: BottomNavigationDestination.today,
                      onSelected: (_) {},
                    ),
                  ),
                  const LearningTourOverlay(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppBottomNavigation)),
      );
      final tour = container.read(learningTourProvider.notifier);
      tour.replay();
      tour.skipStep();
      await tester.pumpAndSettle();
      expect(find.text('Open Focus'), findsOneWidget);
      await tester.tap(find.text('Skip step'));
      await tester.pumpAndSettle();
      expect(find.text('Open Projects'), findsOneWidget);
      await tester.tap(find.text('Skip step'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('learning-tour-card')), findsNothing);
    },
  );

  testWidgets('task hint stays visible beside the mobile add button', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: testAppBuilder,
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: Alignment.bottomRight,
                  child: LearningTourAnchor(
                    id: LearningTourAnchorId.addMobile,
                    child: FilledButton(
                      onPressed: () {},
                      child: const Text('Add target'),
                    ),
                  ),
                ),
                const LearningTourOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.text('Add target')),
    );
    container.read(learningTourProvider.notifier).replay();
    await tester.pumpAndSettle();

    final target = tester.getRect(find.text('Add target'));
    final card = tester.getRect(find.byKey(const Key('learning-tour-card')));
    expect(find.text('Close tour'), findsOneWidget);
    expect(card.width, lessThanOrEqualTo(320));
    expect(card.bottom, lessThan(target.top));
    expect(card.left, greaterThanOrEqualTo(0));
    expect(card.right, lessThanOrEqualTo(320));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('learning-tour-card')), findsNothing);
  });
}
