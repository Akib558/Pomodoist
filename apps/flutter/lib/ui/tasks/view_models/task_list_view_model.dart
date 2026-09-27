import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_rows.dart';

export 'package:pomodoist/ui/tasks/view_models/task_branch_rows.dart';

final taskListViewModelProvider = NotifierProvider.autoDispose
    .family<TaskListViewModel, TaskListState, TaskQuery>(TaskListViewModel.new);

class TaskListState {
  const TaskListState({required this.tasks, required this.allTasks});
  final AsyncValue<List<TaskItem>> tasks;
  final List<TaskItem> allTasks;

  List<TaskItem> visibleTasks(
    Iterable<TaskItem> retained,
    bool Function(TaskItem)? filter,
  ) {
    final result = <String, TaskItem>{
      for (final task in retained) task.id: task,
      for (final task in tasks.value ?? const <TaskItem>[])
        if (filter == null || filter(task)) task.id: task,
    }.values.toList()..sort(compareTaskOrder);
    return List.unmodifiable(result);
  }

  List<VisibleTaskRow> rows(
    List<TaskItem> visible, {
    Map<String, bool> expansion = const {},
  }) => visibleTaskRows(allTasks, visible, expansion: expansion);
}

class TaskListViewModel extends Notifier<TaskListState> {
  TaskListViewModel(this.query);
  final TaskQuery query;
  @override
  TaskListState build() => TaskListState(
    tasks: ref.watch(tasksByQueryProvider(query)),
    allTasks: List.unmodifiable(
      {
        for (final task
            in ref
                    .watch(tasksByQueryProvider(const TaskQuery.completed()))
                    .value ??
                const <TaskItem>[])
          task.id: task,
        for (final task
            in ref.watch(tasksByQueryProvider(const TaskQuery.all())).value ??
                const <TaskItem>[])
          task.id: task,
      }.values,
    ),
  );

  void retry() => ref.invalidate(tasksByQueryProvider(query));
  Future<void> makeRoot(String taskId) async {
    (await ref
            .read(taskRepositoryProvider)
            .moveTask(
              taskId,
              clearParentId: true,
              orderKey: ref
                  .read(clockProvider)
                  .now()
                  .toUtc()
                  .microsecondsSinceEpoch
                  .toString()
                  .padLeft(20, '0'),
            ))
        .getOrThrow();
  }
}
