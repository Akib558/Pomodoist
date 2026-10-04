import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';

void main() {
  final day = DateTime(2026, 10, 3);
  final targets = {
    HabitDayPeriod.morning: 2,
    HabitDayPeriod.afternoon: 2,
    HabitDayPeriod.evening: 2,
    HabitDayPeriod.night: 1,
  };
  Habit habit() => Habit(
    id: 'habit',
    userId: 'user',
    title: 'Water',
    scheduleHistory: [
      HabitDraft(
        title: 'Water',
        startDate: day,
        periodTargets: targets,
      ).schedule(day),
    ],
    createdAt: day,
    updatedAt: day,
  );
  HabitCheckIn mark(
    String id, {
    HabitDayPeriod? period,
    bool deleted = false,
  }) => HabitCheckIn(
    id: id,
    userId: 'user',
    habitId: 'habit',
    day: day,
    createdAt: day,
    updatedAt: day,
    dayPeriod: period,
    isDeleted: deleted,
  );

  test('four goals including night derive the total and round-trip JSON', () {
    final schedule = habit().scheduleHistory.single;
    expect(schedule.targetPerDay, 7);
    expect(HabitSchedule.fromJson(schedule.toJson()).periodTargets, targets);
    expect(
      mark('night', period: HabitDayPeriod.night).toJson()['dayPeriod'],
      'night',
    );
    expect(
      HabitCheckIn.fromJson(
        mark('night', period: HabitDayPeriod.night).toJson(),
      ).dayPeriod,
      HabitDayPeriod.night,
    );
    expect(HabitCheckIn.fromJson(mark('old').toJson()).dayPeriod, isNull);
  });

  test('goals reject automatic, anytime, zero and daily totals over 99', () {
    for (final invalid in [
      {HabitDayPeriod.automatic: 1},
      {HabitDayPeriod.anytime: 1},
      {HabitDayPeriod.night: 0},
      {HabitDayPeriod.night: -1},
      {HabitDayPeriod.morning: 99, HabitDayPeriod.night: 1},
    ]) {
      expect(
        () =>
            HabitDraft(title: 'Water', startDate: day, periodTargets: invalid),
        throwsArgumentError,
      );
    }
    for (final invalid in [
      null,
      [],
      {},
      {'night': '2'},
      {'night': 1.5},
      {'dawn': 1},
      {'night': 0},
    ]) {
      expect(() => habitPeriodTargetsFromJson(invalid), throwsFormatException);
    }
    expect(
      () => HabitSchedule(
        effectiveFrom: day,
        startDate: day,
        weekdays: [6],
        targetPerDay: 2,
        periodTargets: {HabitDayPeriod.night: 1},
      ),
      throwsArgumentError,
    );
    expect(
      () => HabitCheckIn.fromJson({
        ...mark('old').toJson(),
        'dayPeriod': 'automatic',
      }),
      throwsArgumentError,
    );
  });

  test(
    'legacy marks use stable quota order, explicit night marks retain night',
    () {
      final checks = [
        mark('a'),
        mark('b'),
        mark('c'),
        mark('n', period: HabitDayPeriod.night),
        mark('deleted', period: HabitDayPeriod.morning, deleted: true),
      ];
      final assigned = habitCheckInPeriods(habit(), day, checks);
      expect(assigned, {
        'n': HabitDayPeriod.night,
        'a': HabitDayPeriod.morning,
        'b': HabitDayPeriod.morning,
        'c': HabitDayPeriod.afternoon,
      });
      expect(habitCheckInPeriods(habit(), day, checks.reversed), assigned);
      expect(habitPeriodCounts(habit(), day, checks), {
        HabitDayPeriod.morning: 2,
        HabitDayPeriod.afternoon: 1,
        HabitDayPeriod.evening: 0,
        HabitDayPeriod.night: 1,
      });
    },
  );

  test('extra marks in one period cannot complete another period', () {
    final counts = habitPeriodCounts(habit(), day, [
      for (var i = 0; i < 7; i++) mark('$i', period: HabitDayPeriod.morning),
    ]);
    expect(counts[HabitDayPeriod.morning], 2);
    expect(counts[HabitDayPeriod.night], 0);
    expect(counts.values.fold(0, (a, b) => a + b), 2);
  });
}
