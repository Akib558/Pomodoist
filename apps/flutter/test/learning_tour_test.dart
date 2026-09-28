import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/ui/onboarding/view_models/learning_tour_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('old completed users are not prompted, but can replay', () async {
    SharedPreferences.setMockInitialValues({'onboarding.completed.v1': true});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    expect(
      await container.read(learningTourProvider.future),
      LearningTourStep.inactive,
    );

    container.read(learningTourProvider.notifier).replay();
    expect(
      container.read(learningTourProvider).value,
      LearningTourStep.addTask,
    );
  });

  test(
    'invitation is cleared and navigation needs no saved task or focus run',
    () async {
      SharedPreferences.setMockInitialValues({
        'onboarding.completed.v1': true,
        'learningTour.invitationPending.v1': true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      expect(
        await container.read(learningTourProvider.future),
        LearningTourStep.invitation,
      );
      final tour = container.read(learningTourProvider.notifier);

      await tour.start();
      expect(
        container.read(learningTourProvider).value,
        LearningTourStep.addTask,
      );
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'learningTour.invitationPending.v1',
        ),
        isFalse,
      );
      tour.quickAddOpened();
      expect(
        container.read(learningTourProvider).value,
        LearningTourStep.addTaskOpen,
      );
      tour.quickAddClosed();
      expect(
        container.read(learningTourProvider).value,
        LearningTourStep.focusNavigation,
      );
      tour.focusOpened();
      expect(
        container.read(learningTourProvider).value,
        LearningTourStep.focusReady,
      );
      tour.next();
      expect(
        container.read(learningTourProvider).value,
        LearningTourStep.projectsNavigation,
      );
      tour.projectsOpened();
      expect(
        container.read(learningTourProvider).value,
        LearningTourStep.projectsReady,
      );
      tour.finish();
      expect(
        container.read(learningTourProvider).value,
        LearningTourStep.inactive,
      );
    },
  );

  test(
    'later removes a pending invitation; closing replay keeps it closed',
    () async {
      SharedPreferences.setMockInitialValues({
        'learningTour.invitationPending.v1': true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      expect(
        await container.read(learningTourProvider.future),
        LearningTourStep.invitation,
      );
      final tour = container.read(learningTourProvider.notifier);
      await tour.later();
      expect(
        container.read(learningTourProvider).value,
        LearningTourStep.inactive,
      );
      tour.replay();
      tour.close();
      expect(
        container.read(learningTourProvider).value,
        LearningTourStep.inactive,
      );
    },
  );
}
