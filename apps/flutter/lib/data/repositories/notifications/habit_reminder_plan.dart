import 'dart:math' as math;
import 'package:pomodoist/domain/models/habits/habit_models.dart';

typedef PlannedHabitReminder = ({
  String habitId,
  String title,
  DateTime scheduledAt,
});

List<PlannedHabitReminder> planHabitReminders({
  required List<Habit> habits,
  required List<HabitCheckIn> checkIns,
  required DateTime now,
  int budget = 30,
}) {
  now = now.toLocal();
  final reminders = <PlannedHabitReminder>[];
  final checksByDay = <(String, String), List<HabitCheckIn>>{};
  for (final check in checkIns.where((c) => !c.isDeleted)) {
    final key = (check.habitId, habitDayKey(check.day));
    (checksByDay[key] ??= []).add(check);
  }
  // ponytail: queue at most 30 days; app activity refills instead of background jobs.
  for (var offset = 0; offset < 30; offset++) {
    final day = DateTime(now.year, now.month, now.day + offset);
    for (final habit in habits) {
      final minutes = habit.reminderMinutes;
      if (minutes == null || !habit.isScheduledOn(day)) continue;
      final completed = habitPeriodCounts(
        habit,
        day,
        checksByDay[(habit.id, habitDayKey(day))] ?? const [],
      ).values.fold(0, (a, b) => a + b);
      if (completed >= habit.scheduleFor(day)!.targetPerDay) {
        continue;
      }
      final at = DateTime(
        day.year,
        day.month,
        day.day,
        minutes ~/ 60,
        minutes % 60,
      );
      if (at.isAfter(now)) {
        reminders.add((habitId: habit.id, title: habit.title, scheduledAt: at));
      }
    }
  }
  reminders.sort((a, b) {
    final time = a.scheduledAt.compareTo(b.scheduledAt);
    return time == 0 ? a.habitId.compareTo(b.habitId) : time;
  });
  return List.unmodifiable(reminders.take(math.max(0, math.min(30, budget))));
}
