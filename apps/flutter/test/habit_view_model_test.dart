import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/config/habit_dependencies.dart';
import 'package:pomodoist/config/habit_notification_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/domain/models/notifications/habit_reminder_status.dart';
import 'package:pomodoist/ui/habits/view_models/habits_view_model.dart';
import 'package:pomodoist/utils/clock.dart';

void main() {
  test('UTC clock selects the device calendar day around midnight', () async {
    final utc = DateTime.utc(2026, 9, 30, 22, 30);
    final local = utc.toLocal();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(FixedClock(utc)),
        habitsProvider.overrideWith((_) => Stream.value([])),
        habitCheckInsProvider.overrideWith((_) => Stream.value([])),
        projectsProvider.overrideWith((_) => Stream.value([])),
        habitReminderStatusProvider.overrideWith(_Status.new),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(habitsViewModelProvider, (_, _) {});
    addTearDown(subscription.close);
    expect(
      container.read(habitsViewModelProvider).today,
      DateTime(local.year, local.month, local.day),
    );
  });
  final now = DateTime(2026, 9, 30, 12);
  test(
    'daily summary counts fully reached goals and future days stay readonly',
    () async {
      final habit = Habit(
        id: 'h',
        userId: 'local-user',
        title: 'Read',
        scheduleHistory: [
          HabitDraft(
            title: 'Read',
            startDate: DateTime(2026, 9, 28),
            targetPerDay: 2,
          ).schedule(DateTime(2026, 9, 28)),
        ],
        createdAt: now,
        updatedAt: now,
      );
      final check = HabitCheckIn(
        id: 'c',
        userId: 'local-user',
        habitId: 'h',
        day: now,
        createdAt: now,
        updatedAt: now,
      );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FixedClock(now)),
          habitsProvider.overrideWith((_) => Stream.value([habit])),
          habitCheckInsProvider.overrideWith((_) => Stream.value([check])),
          projectsProvider.overrideWith((_) => Stream.value([])),
          habitReminderStatusProvider.overrideWith(_Status.new),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(habitsViewModelProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(habitsProvider.future);
      await container.read(habitCheckInsProvider.future);
      await container.read(projectsProvider.future);
      var state = container.read(habitsViewModelProvider);
      expect(state.planned, 1);
      expect(state.completed, 0);
      expect(state.rows.single.count, 1);
      expect(state.rows.single.canAdd, isTrue);
      container
          .read(habitsViewModelProvider.notifier)
          .selectDay(DateTime(2026, 10, 1));
      state = container.read(habitsViewModelProvider);
      expect(state.rows.single.canAdd, isFalse);
      expect(state.futureDay, isTrue);
      container.read(habitsViewModelProvider.notifier).moveWeek(-1);
      expect(
        container.read(habitsViewModelProvider).selectedDay,
        DateTime(2026, 9, 24),
      );
      container.read(habitsViewModelProvider.notifier).selectToday();
      expect(
        container.read(habitsViewModelProvider).selectedDay,
        DateTime(2026, 9, 30),
      );
    },
  );
  test(
    'ended habits retain historic editing and removed project has no label',
    () async {
      final habit = Habit(
        id: 'h',
        userId: 'local-user',
        title: 'Read',
        projectId: 'missing',
        scheduleHistory: [
          HabitDraft(
            title: 'Read',
            startDate: DateTime(2026, 9, 28),
            endDate: DateTime(2026, 9, 29),
          ).schedule(DateTime(2026, 9, 28)),
        ],
        createdAt: now,
        updatedAt: now,
      );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FixedClock(now)),
          habitsProvider.overrideWith((_) => Stream.value([habit])),
          habitCheckInsProvider.overrideWith((_) => Stream.value([])),
          projectsProvider.overrideWith((_) => Stream.value([])),
          habitReminderStatusProvider.overrideWith(_Status.new),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(habitsViewModelProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(habitsProvider.future);
      await container.read(habitCheckInsProvider.future);
      await container.read(projectsProvider.future);
      final vm = container.read(habitsViewModelProvider.notifier);
      vm.showFinished(true);
      expect(
        container.read(habitsViewModelProvider).rows.single.canAdd,
        isFalse,
      );
      vm.selectDay(DateTime(2026, 9, 29));
      final row = container.read(habitsViewModelProvider).rows.single;
      expect(row.canAdd, isTrue);
      expect(row.project, isNull);
    },
  );
}

class _Status extends HabitNotificationCoordinator {
  @override
  HabitReminderStatus build() => HabitReminderStatus.available;
}
