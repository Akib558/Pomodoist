import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_rows.dart';

export 'package:pomodoist/ui/tasks/view_models/task_branch_rows.dart';

final taskListViewModelProvider = NotifierProvider.autoDispose
    .family<TaskListViewModel, TaskListState, TaskQuery>(TaskListViewModel.new);

class TaskListState {
  TaskListState({required this.tasks, required this.allTasks});
  final AsyncValue<List<TaskItem>> tasks;
  final List<TaskItem> allTasks;
  late final Map<String, TaskItem> allById = {
    for (final task in allTasks) task.id: task,
  };
  late final Map<String, TaskItem> byId = {
    for (final task in tasks.value ?? const <TaskItem>[]) task.id: task,
  };

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
  }) => visibleTaskRows(
    const [],
    visible,
    allById: allById,
    expansion: expansion,
  );
}

class TaskListLayout {
  TaskListLayout(this.state)
    : visible = [
        for (final task in state.tasks.value ?? const <TaskItem>[])
          taskStructureKey(task),
      ],
      metadata = [for (final task in state.allTasks) taskStructureKey(task)];
  final TaskListState state;
  final List<Object> visible, metadata;
  @override
  bool operator ==(Object other) =>
      other is TaskListLayout &&
      (state.tasks.isLoading, state.tasks.hasValue, state.tasks.error) ==
          (
            other.state.tasks.isLoading,
            other.state.tasks.hasValue,
            other.state.tasks.error,
          ) &&
      const ListEquality<Object>().equals(visible, other.visible) &&
      const ListEquality<Object>().equals(metadata, other.metadata);
  @override
  int get hashCode => Object.hash(
    state.tasks.isLoading,
    state.tasks.hasValue,
    state.tasks.error,
    const ListEquality<Object>().hash(visible),
    const ListEquality<Object>().hash(metadata),
  );
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
