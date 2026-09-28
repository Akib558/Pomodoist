import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';

const learningTourInvitationPendingPreferenceKey =
    'learningTour.invitationPending.v1';

enum LearningTourStep {
  inactive,
  invitation,
  addTask,
  addTaskOpen,
  focusNavigation,
  focusReady,
  projectsNavigation,
  projectsReady;

  bool get active => this != inactive && this != invitation;
}

final learningTourProvider =
    AsyncNotifierProvider<LearningTourController, LearningTourStep>(
      LearningTourController.new,
    );

class LearningTourController extends AsyncNotifier<LearningTourStep> {
  @override
  Future<LearningTourStep> build() async {
    final values = (await ref.read(preferencesRepositoryProvider).read(const [
      learningTourInvitationPendingPreferenceKey,
    ])).getOrThrow();
    return values[learningTourInvitationPendingPreferenceKey] == true
        ? LearningTourStep.invitation
        : LearningTourStep.inactive;
  }

  Future<void> start() async {
    await _resolveInvitation();
    if (ref.mounted) state = const AsyncData(LearningTourStep.addTask);
  }

  Future<void> later() async {
    await _resolveInvitation();
    if (ref.mounted) state = const AsyncData(LearningTourStep.inactive);
  }

  Future<void> _resolveInvitation() async {
    await future;
    (await ref.read(preferencesRepositoryProvider).write(const {
      learningTourInvitationPendingPreferenceKey: false,
    })).getOrThrow();
  }

  void replay() => state = const AsyncData(LearningTourStep.addTask);

  void quickAddOpened() {
    if (state.value == LearningTourStep.addTask) {
      state = const AsyncData(LearningTourStep.addTaskOpen);
    }
  }

  void quickAddClosed() {
    if (state.value == LearningTourStep.addTaskOpen) {
      state = const AsyncData(LearningTourStep.focusNavigation);
    }
  }

  void focusOpened() {
    if (state.value == LearningTourStep.focusNavigation) {
      state = const AsyncData(LearningTourStep.focusReady);
    }
  }

  void projectsOpened() {
    if (state.value == LearningTourStep.projectsNavigation) {
      state = const AsyncData(LearningTourStep.projectsReady);
    }
  }

  void next() {
    if (state.value == LearningTourStep.focusReady) {
      state = const AsyncData(LearningTourStep.projectsNavigation);
    }
  }

  void skipStep() {
    state = AsyncData(switch (state.value) {
      LearningTourStep.addTask ||
      LearningTourStep.addTaskOpen => LearningTourStep.focusNavigation,
      LearningTourStep.focusNavigation ||
      LearningTourStep.focusReady => LearningTourStep.projectsNavigation,
      LearningTourStep.projectsNavigation ||
      LearningTourStep.projectsReady => LearningTourStep.inactive,
      _ => state.value ?? LearningTourStep.inactive,
    });
  }

  void finish() => state = const AsyncData(LearningTourStep.inactive);

  void close() => state = const AsyncData(LearningTourStep.inactive);
}
