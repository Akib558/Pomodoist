import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'task_branch_rows.dart';
import 'task_subtask_progress.dart';

final taskBranchStyleViewModelProvider = Provider(
  (ref) => ref.watch(taskBranchStyleProvider),
);

String taskBranchScopeKey(TaskQuery query) => switch (query.kind) {
  TaskQueryKind.project => 'project:${query.projectId}',
  TaskQueryKind.label => 'label:${query.labelId}',
  _ => query.kind.name,
};

typedef TaskHierarchyData = ({
  Map<String, TaskItem> byId,
  Map<String, TaskSubtaskProgress> progress,
});

final taskHierarchyViewModelProvider = Provider.autoDispose<TaskHierarchyData>((
  ref,
) {
  final open = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
  final completed = ref.watch(
    tasksByQueryProvider(const TaskQuery.completed()),
  );
  final byId = <String, TaskItem>{};
  for (final task in [...?open.value, ...?completed.value]) {
    if (!task.isDeleted) byId.putIfAbsent(task.id, () => task);
  }
  return (
    byId: Map.unmodifiable(byId),
    progress: open.hasValue && completed.hasValue
        ? taskSubtaskProgressById(byId.values)
        : const {},
  );
});

final taskProgressProvider = Provider.autoDispose
    .family<({bool live, TaskSubtaskProgress? progress}), String>(
      (ref, id) => ref.watch(
        taskHierarchyViewModelProvider.select(
          (data) =>
              (live: data.byId.containsKey(id), progress: data.progress[id]),
        ),
      ),
    );

final taskAncestorsProvider = Provider.autoDispose
    .family<TaskAncestorSnapshot, TaskItem>(
      (ref, task) => TaskAncestorSnapshot(
        taskAncestorPath(task, ref.watch(taskHierarchyViewModelProvider).byId),
      ),
    );

class TaskAncestorSnapshot {
  const TaskAncestorSnapshot(this.items);
  final List<TaskItem> items;
  @override
  bool operator ==(Object other) =>
      other is TaskAncestorSnapshot &&
      const ListEquality<TaskItem>().equals(items, other.items);
  @override
  int get hashCode => const ListEquality<TaskItem>().hash(items);
}

final taskBranchViewModelProvider = NotifierProvider.autoDispose
    .family<TaskBranchViewModel, Map<String, bool>, String>(
      TaskBranchViewModel.new,
    );

class TaskBranchViewModel extends Notifier<Map<String, bool>> {
  TaskBranchViewModel(this.scopeKey);
  final String scopeKey;

  @override
  Map<String, bool> build() =>
      ref.watch(taskBranchExpansionProvider)[scopeKey] ?? const {};

  Future<void> setExpanded(String taskId, bool expanded) async {
    (await ref
            .read(taskPreferencesRepositoryProvider)
            .setBranchExpanded(scopeKey, taskId, expanded))
        .getOrThrow();
  }

  /// Read freshly created tasks before the list stream necessarily catches up.
  Future<void> revealCreatedTasks(Iterable<String> taskIds) async {
    final tasks = ref.read(taskRepositoryProvider);
    final preferences = ref.read(taskPreferencesRepositoryProvider);
    final revealed = <String>{};
    for (final id in taskIds) {
      final visited = <String>{id};
      var parentId = (await tasks.watchTask(id).first)?.parentId;
      while (parentId != null && visited.add(parentId)) {
        final parent = await tasks.watchTask(parentId).first;
        if (parent == null || parent.isDeleted) break;
        if (revealed.add(parent.id)) {
          (await preferences.setBranchExpanded(
            scopeKey,
            parent.id,
            true,
          )).getOrThrow();
        }
        parentId = parent.parentId;
      }
    }
  }
}

List<TaskItem> hierarchyAncestors(TaskItem task, TaskHierarchyData data) =>
    taskAncestorPath(task, data.byId);
