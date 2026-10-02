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
  test(
    'row history respects past schedules, partial goals and future days',
    () async {
      final now = DateTime(2026, 10, 2, 12);
      final habit = Habit(
        id: 'h',
        userId: 'local-user',
        title: 'Water',
        scheduleHistory: [
          HabitDraft(
            title: 'Water',
            startDate: DateTime(2026, 9, 28),
            weekdays: [1, 3, 5],
            targetPerDay: 2,
          ).schedule(DateTime(2026, 9, 28)),
          HabitDraft(
            title: 'Water',
            startDate: DateTime(2026, 9, 28),
            targetPerDay: 4,
          ).schedule(DateTime(2026, 10, 2)),
        ],
        createdAt: now,
        updatedAt: now,
      );
      HabitCheckIn check(
        String id,
        DateTime day, {
        bool deleted = false,
        String habitId = 'h',
      }) => HabitCheckIn(
        id: id,
        userId: 'local-user',
        habitId: habitId,
        day: day,
        createdAt: now,
        updatedAt: now,
        isDeleted: deleted,
      );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(FixedClock(now)),
          habitsProvider.overrideWith((_) => Stream.value([habit])),
          habitCheckInsProvider.overrideWith(
            (_) => Stream.value([
              check('past-1', DateTime(2026, 9, 30)),
              check('past-2', DateTime(2026, 9, 30)),
              check('past-excess', DateTime(2026, 9, 30)),
              check('today', now),
              check('deleted', now, deleted: true),
              check('other', now, habitId: 'other'),
            ]),
          ),
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
      final row = container.read(habitsViewModelProvider).rows.single;
      final history = row.history;
      expect(history.map((day) => (day.day, day.count, day.target)), [
        (DateTime(2026, 9, 28), 0, 2),
        (DateTime(2026, 9, 29), 0, null),
        (DateTime(2026, 9, 30), 2, 2),
        (DateTime(2026, 10, 1), 0, null),
        (DateTime(2026, 10, 2), 1, 4),
      ]);
      expect(row.count, 1);
      container
          .read(habitsViewModelProvider.notifier)
          .selectDay(DateTime(2026, 10, 3));
      final future = container.read(habitsViewModelProvider).rows.single;
      final futureHistory = future.history;
      expect(futureHistory.last.day, DateTime(2026, 10, 3));
      expect(futureHistory.last.count, 0);
      expect(futureHistory.last.target, 4);
      expect(future.canAdd, isFalse);
      container
          .read(habitsViewModelProvider.notifier)
          .selectDay(DateTime(2026, 9, 30));
      final past = container.read(habitsViewModelProvider).rows.single;
      expect(past.history.first.day, DateTime(2026, 9, 26));
      expect(past.history.first.target, isNull);
      expect(past.history.last.target, 2);
      expect(past.count, 2);
    },
  );
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
      expect(row.history.last.target, 1);
      vm.selectToday();
      expect(
        container.read(habitsViewModelProvider).rows.single.history.last.target,
        isNull,
      );
    },
  );
}

class _Status extends HabitNotificationCoordinator {
  @override
  HabitReminderStatus build() => HabitReminderStatus.available;
}
