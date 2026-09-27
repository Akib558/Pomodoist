import 'package:pomodoist/domain/models/tasks/task_models.dart';

class TaskSubtaskProgress {
  const TaskSubtaskProgress({required this.completed, required this.total});

  final int completed;
  final int total;

  String get label => '$completed/$total';
}

Map<String, TaskSubtaskProgress> taskSubtaskProgressById(
  Iterable<TaskItem> tasks,
) {
  final byId = <String, TaskItem>{for (final task in tasks) task.id: task};
  final children = <String, List<String>>{};
  for (final task in byId.values) {
    if (task.parentId != null && byId.containsKey(task.parentId)) {
      children.putIfAbsent(task.parentId!, () => []).add(task.id);
    }
  }
  // ponytail: repeated traversal is quadratic for deep chains; cache acyclic
  // subtree totals if large nested collections make this measurable.
  final result = <String, TaskSubtaskProgress>{};
  for (final id in children.keys) {
    final visited = {id};
    final pending = [...children[id]!];
    var completed = 0;
    while (pending.isNotEmpty) {
      final child = pending.removeLast();
      if (!visited.add(child)) continue;
      if (byId[child]!.isCompleted) completed++;
      pending.addAll(children[child] ?? const []);
    }
    if (visited.length > 1) {
      result[id] = TaskSubtaskProgress(
        completed: completed,
        total: visited.length - 1,
      );
    }
  }
  return result;
}
