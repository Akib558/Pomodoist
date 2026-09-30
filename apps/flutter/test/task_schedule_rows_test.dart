import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/tasks/task_time.dart';
import 'package:pomodoist/ui/core/localization/formatters.dart';

void main() {
  final timed = TaskSchedule.timed(
    start: DateTime(2026, 9, 30, 20, 30),
    end: DateTime(2026, 9, 30, 21, 50),
  );
  List<List<String>> rows(
    TaskSchedule? schedule, {
    bool withinDate = false,
    String? recurrence,
    TaskTimeDisplayMode mode = TaskTimeDisplayMode.smart,
    String Function(DateTime)? timeLabel,
  }) => taskListScheduleRows(
    schedule,
    formatDate: (date) => date.day == 30 ? 'Сегодня' : 'Завтра',
    formatTime:
        timeLabel ??
        (date) =>
            '${date.hour.toString().padLeft(2, '0')}:'
            '${date.minute.toString().padLeft(2, '0')}',
    recurrenceLabel: recurrence,
    withinDate: withinDate,
    displayMode: mode,
  );

  test('date and same-day time range remain separate indivisible blocks', () {
    expect(rows(timed), [
      ['Сегодня', '20:30-21:50'],
    ]);
    expect(rows(timed, withinDate: true), [
      ['20:30-21:50'],
    ]);
    expect(
      rows(timed, timeLabel: (date) => date.hour == 20 ? '8:30 PM' : '9:50 PM'),
      [
        ['Сегодня', '8:30 PM-9:50 PM'],
      ],
    );
  });

  test('time display modes retain start-only and default-duration rules', () {
    expect(rows(timed, mode: TaskTimeDisplayMode.startOnly), [
      ['Сегодня', '20:30'],
    ]);
    final defaultBlock = TaskSchedule.timed(
      start: DateTime(2026, 9, 30, 20, 30),
      end: DateTime(2026, 9, 30, 21),
    );
    expect(rows(defaultBlock), [
      ['Сегодня', '20:30'],
    ]);
    expect(rows(defaultBlock, mode: TaskTimeDisplayMode.range), [
      ['Сегодня', '20:30-21:00'],
    ]);
  });

  test(
    'overnight ranges have distinct dated endpoints even within an agenda day',
    () {
      final overnight = TaskSchedule.timed(
        start: DateTime(2026, 9, 30, 23, 30),
        end: DateTime(2026, 10, 1, 1),
      );
      expect(rows(overnight), [
        ['Сегодня', '23:30'],
        ['Завтра', '01:00'],
      ]);
      expect(rows(overnight, withinDate: true), [
        ['23:30'],
        ['Завтра', '01:00'],
      ]);
      expect(rows(overnight, mode: TaskTimeDisplayMode.startOnly), [
        ['Сегодня', '23:30'],
      ]);
    },
  );

  test(
    'recurrence occupies its own row without empty date or time placeholders',
    () {
      final allDay = TaskSchedule.allDay(DateTime(2026, 9, 30));
      expect(rows(timed, recurrence: 'Каждые 2 недели'), [
        ['Сегодня', '20:30-21:50'],
        ['Каждые 2 недели'],
      ]);
      expect(rows(allDay, recurrence: 'Каждый день'), [
        ['Сегодня'],
        ['Каждый день'],
      ]);
      expect(rows(allDay, withinDate: true, recurrence: 'Каждый день'), [
        ['Каждый день'],
      ]);
      expect(rows(allDay, withinDate: true), isEmpty);
      expect(rows(null), isEmpty);
    },
  );
}
