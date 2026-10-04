import 'package:pomodoist/domain/models/tasks/task_models.dart';

class TaskSubtaskProgress {
  const TaskSubtaskProgress({required this.completed, required this.total});

  final int completed;
  final int total;

  String get label => '$completed/$total';

  @override
  bool operator ==(Object other) =>
      other is TaskSubtaskProgress &&
      completed == other.completed &&
      total == other.total;
  @override
  int get hashCode => Object.hash(completed, total);
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
  final result = <String, TaskSubtaskProgress>{};
  final remaining = {for (final id in byId.keys) id: children[id]?.length ?? 0};
  final totals = <String, int>{};
  final completedTotals = <String, int>{};
  final leaves = [
    for (final entry in remaining.entries)
      if (entry.value == 0) entry.key,
  ];
  final resolved = <String>{};
  while (leaves.isNotEmpty) {
    final id = leaves.removeLast();
    resolved.add(id);
    final total = totals[id] ?? 0;
    final completed = completedTotals[id] ?? 0;
    if (total > 0) {
      result[id] = TaskSubtaskProgress(completed: completed, total: total);
    }
    final parent = byId[id]!.parentId;
    if (parent == null || !byId.containsKey(parent)) continue;
    totals.update(
      parent,
      (value) => value + total + 1,
      ifAbsent: () => total + 1,
    );
    final count = completed + (byId[id]!.isCompleted ? 1 : 0);
    completedTotals.update(
      parent,
      (value) => value + count,
      ifAbsent: () => count,
    );
    remaining[parent] = remaining[parent]! - 1;
    if (remaining[parent] == 0) leaves.add(parent);
  }
  // ponytail: corrupt cyclic remnants retain the safe quadratic traversal;
  // acyclic trees use the linear bottom-up pass above.
  for (final id in children.keys) {
    if (resolved.contains(id)) continue;
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
