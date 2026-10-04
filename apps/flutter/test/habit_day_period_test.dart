import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/domain/models/notifications/habit_reminder_status.dart';
import 'package:pomodoist/ui/habits/view_models/habits_view_model.dart';

void main() {
  test(
    'rhythm keeps one row per habit, hides empty periods and sorts completion',
    () {
      final now = DateTime(2026, 10, 3);
      HabitDayRow row(String id, HabitDayPeriod period, int count, int goal) =>
          HabitDayRow(
            habit: Habit(
              id: id,
              userId: 'local-user',
              title: id,
              scheduleHistory: [
                HabitDraft(
                  title: id,
                  startDate: now,
                  targetPerDay: goal,
                ).schedule(now),
              ],
              createdAt: now,
              updatedAt: now,
            ),
            count: count,
            target: goal,
            dayPeriod: period,
            canAdd: count < goal,
            canUndo: count > 0,
            history: [],
          );
      final state = HabitsViewState(
        today: now,
        selectedDay: now,
        rows: [
          row('evening', HabitDayPeriod.evening, 0, 1),
          row('morning-done', HabitDayPeriod.morning, 1, 1),
          row('water', HabitDayPeriod.anytime, 3, 7),
          row('morning-pending', HabitDayPeriod.morning, 0, 1),
          row('night', HabitDayPeriod.night, 1, 1),
        ],
        projects: [],
        reminderStatus: HabitReminderStatus.available,
        planned: 5,
        completed: 2,
        loading: false,
        finished: false,
        saving: false,
      );
      final groups = state.rhythmGroups;
      expect(groups.map((g) => g.period), [
        HabitDayPeriod.anytime,
        HabitDayPeriod.morning,
        HabitDayPeriod.evening,
        HabitDayPeriod.night,
      ]);
      expect(groups[1].rows.map((r) => r.habit.id), [
        'morning-pending',
        'morning-done',
      ]);
      expect(
        groups.expand((g) => g.rows).map((r) => r.habit.id).toSet(),
        hasLength(5),
      );
      expect(state.remainingRows, hasLength(3));
      expect(state.completedRows, hasLength(2));
    },
  );

  test('automatic periods use reminder boundaries, not check-in time', () {
    for (final (minutes, period) in [
      (0, HabitDayPeriod.night),
      (299, HabitDayPeriod.night),
      (300, HabitDayPeriod.morning),
      (719, HabitDayPeriod.morning),
      (720, HabitDayPeriod.afternoon),
      (1079, HabitDayPeriod.afternoon),
      (1080, HabitDayPeriod.evening),
      (1439, HabitDayPeriod.evening),
    ]) {
      expect(
        resolveHabitDayPeriod(target: 1, reminderMinutes: minutes),
        period,
      );
      expect(
        resolveHabitDayPeriod(target: 7, reminderMinutes: minutes),
        HabitDayPeriod.anytime,
      );
    }
    expect(resolveHabitDayPeriod(target: 1), HabitDayPeriod.anytime);
    for (final period in HabitDayPeriod.values.where(
      (p) => p != HabitDayPeriod.automatic,
    )) {
      expect(
        resolveHabitDayPeriod(
          selection: period,
          target: 7,
          reminderMinutes: 1200,
        ),
        period,
      );
    }
  });

  test('old schedule JSON stays automatic and manual periods round-trip', () {
    final old = HabitDraft(
      title: 'Water',
      startDate: DateTime(2026, 10, 3),
    ).schedule(DateTime(2026, 10, 3)).toJson();
    expect(old.containsKey('dayPeriod'), isFalse);
    expect(HabitSchedule.fromJson(old).dayPeriod, HabitDayPeriod.automatic);
    for (final period in HabitDayPeriod.values) {
      final schedule = HabitDraft(
        title: 'Water',
        startDate: DateTime(2026, 10, 3),
        dayPeriod: period,
      ).schedule(DateTime(2026, 10, 3));
      expect(HabitSchedule.fromJson(schedule.toJson()).dayPeriod, period);
    }
    expect(
      () => HabitSchedule.fromJson({...old, 'dayPeriod': 'invalid'}),
      throwsFormatException,
    );
    expect(
      () => HabitSchedule.fromJson({...old, 'dayPeriod': null}),
      throwsFormatException,
    );
    expect(
      () => HabitSchedule.fromJson({...old, 'dayPeriod': 12}),
      throwsFormatException,
    );
  });
}
