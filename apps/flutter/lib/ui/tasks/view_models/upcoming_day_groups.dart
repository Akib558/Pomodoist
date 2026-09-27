import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_rows.dart';

class UpcomingDayGroup {
  const UpcomingDayGroup({
    required this.date,
    required this.rows,
    this.isSynthetic = false,
  });

  final DateTime date;
  final List<UpcomingTaskRow> rows;
  final bool isSynthetic;
}

typedef UpcomingTaskRow = VisibleTaskRow;

List<UpcomingDayGroup> buildUpcomingDayGroups(
  Iterable<TaskItem> tasks, {
  Iterable<TaskItem>? allItems,
  Map<String, bool> expansion = const {},
  DateTime? selectedDate,
  DateTime? visibleFromDate,
}) {
  final currentTasks = {
    for (final task in tasks) task.id: task,
  }.values.toList();
  final metadata = [...?allItems, ...currentTasks];
  final tasksByDate = <DateTime, List<TaskItem>>{};
  final firstVisibleDay = visibleFromDate == null
      ? null
      : _localDateOnly(visibleFromDate);
  for (final task in currentTasks) {
    final schedule = task.schedule;
    if (schedule == null) {
      continue;
    }
    final date = _localDateOnly(schedule.displayDate);
    if (firstVisibleDay != null && date.isBefore(firstVisibleDay)) {
      continue;
    }
    tasksByDate.putIfAbsent(date, () => []).add(task);
  }

  final selectedDay = selectedDate == null
      ? null
      : _localDateOnly(selectedDate);
  if (selectedDay != null) {
    tasksByDate.putIfAbsent(selectedDay, () => []);
  }

  final dates = tasksByDate.keys.toList()..sort();
  return List.unmodifiable(
    dates.map((date) {
      final dayTasks = tasksByDate[date]!;
      return UpcomingDayGroup(
        date: date,
        rows: visibleTaskRows(
          metadata,
          dayTasks,
          expansion: expansion,
          compare: _compareTaskOrder,
          compareRoots: _compareRootOrder,
        ),
        isSynthetic: dayTasks.isEmpty && date == selectedDay,
      );
    }),
  );
}

int _compareTaskOrder(TaskItem a, TaskItem b) {
  final aDayOrder = a.dayOrder;
  final bDayOrder = b.dayOrder;
  if (aDayOrder == null && bDayOrder != null) {
    return 1;
  }
  if (aDayOrder != null && bDayOrder == null) {
    return -1;
  }
  if (aDayOrder != null && bDayOrder != null) {
    final dayOrder = aDayOrder.compareTo(bDayOrder);
    if (dayOrder != 0) {
      return dayOrder;
    }
  }

  final orderKey = a.orderKey.compareTo(b.orderKey);
  if (orderKey != 0) {
    return orderKey;
  }
  return a.id.compareTo(b.id);
}

int _compareRootOrder(TaskItem a, TaskItem b) {
  if (a.isCompleted != b.isCompleted) {
    return a.isCompleted ? -1 : 1;
  }
  return _compareTaskOrder(a, b);
}

DateTime _localDateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}
