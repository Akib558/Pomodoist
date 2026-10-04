import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/ui/tasks/view_models/task_list_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/tasks/view_models/upcoming_day_groups.dart';
import 'package:pomodoist/ui/tasks/view_models/task_subtask_progress.dart';
import 'task_performance_test.dart' show CountedTask, now;

void main() {
  test('1000 separate days use at most 30000 ID accesses', () {
    final tasks = List.generate(
      1000,
      (i) => CountedTask('$i', day: now.add(Duration(days: i))),
    );
    CountedTask.idReads = 0;
    expect(buildUpcomingDayGroups(tasks, allItems: tasks).length, 1000);
    expect(CountedTask.idReads, lessThanOrEqualTo(30000));
  });
  test('nested progress is linear and preserves totals', () {
    final tasks = List.generate(
      1000,
      (i) => CountedTask('$i', parent: i == 0 ? null : '${i - 1}'),
    );
    CountedTask.completionReads = 0;
    final result = taskSubtaskProgressById(tasks);
    expect(result['0']!.total, 999);
    expect(result['998']!.total, 1);
    expect(CountedTask.completionReads, lessThanOrEqualTo(1000));
  });
  test(
    'row projection reuses the index of a snapshot with 10000 completed tasks',
    () {
      final visible = List.generate(40, (i) => CountedTask('$i'));
      final history = List.generate(
        10000,
        (i) => CountedTask('history-$i', completed: true),
      );
      final state = TaskListState(
        tasks: AsyncData(visible),
        allTasks: [...history, ...visible],
      );
      state.rows(visible);
      CountedTask.idReads = 0;
      expect(state.rows(visible).length, 40);
      expect(CountedTask.idReads, lessThan(1000));
    },
  );
  test('missing and invalid schedule parsing is also memoized', () {
    for (final raw in [null, 'invalid JSON']) {
      final task = _NoScheduleTask(raw);
      for (var i = 0; i < 3; i++) {
        expect(task.schedule, isNull);
      }
      expect(task.dueReads, 1);
    }
  });
  test('schedule is decoded only once per immutable instance', () {
    final task = CountedTask('one');
    expect(identical(task.schedule, task.schedule), isTrue);
  });
}

class _NoScheduleTask extends CountedTask {
  _NoScheduleTask(this.raw) : super('none');
  final String? raw;
  var dueReads = 0;
  @override
  String? get dueJson {
    dueReads++;
    return raw;
  }
}
