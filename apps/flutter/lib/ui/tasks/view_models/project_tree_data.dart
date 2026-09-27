import 'package:pomodoist/domain/models/tasks/project_hierarchy.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'task_branch_rows.dart';
import 'task_subtask_progress.dart';

class ProjectTreeNode {
  ProjectTreeNode({
    required this.key,
    this.parentKey,
    this.project,
    this.task,
    this.children = const [],
    this.progress = const TaskSubtaskProgress(completed: 0, total: 0),
  });
  final String key;
  final String? parentKey;
  final ProjectItem? project;
  final TaskItem? task;
  final List<String> children;
  final TaskSubtaskProgress progress;
}

class ProjectTreeData {
  const ProjectTreeData(
    this.rootKey,
    this.nodes,
    this.visibleKeys,
    this.expandedKeys,
    this.tasksById,
  );
  final String rootKey;
  final Map<String, ProjectTreeNode> nodes;
  final List<String> visibleKeys;
  final Set<String> expandedKeys;
  final Map<String, TaskItem> tasksById;
  List<String> visibleChildren(String key) =>
      expandedKeys.contains(key) ? nodes[key]?.children ?? const [] : const [];
}

String projectDiagramScope(String id) => 'project-diagram:$id';

ProjectTreeData projectTreeData(
  String projectId,
  List<ProjectItem> projects,
  List<TaskItem> tasks, {
  bool showCompleted = false,
  Map<String, bool> expansion = const {},
}) {
  final rootKey = 'p:$projectId';
  final active = projects.where((p) => !p.isDeleted).toList();
  final parents = projectParents(active);
  final byProject = {for (final p in active) p.id: p};
  final projectChildren = <String, List<ProjectItem>>{};
  for (final p in active) {
    final parent = parents[p.id];
    if (!p.isArchived && parent != null)
      projectChildren.putIfAbsent(parent, () => []).add(p);
  }
  for (final children in projectChildren.values) {
    children.sort(compareProjects);
  }
  final included = <String>{};
  final pending = [projectId];
  while (pending.isNotEmpty) {
    final id = pending.removeLast();
    if (!byProject.containsKey(id) || !included.add(id)) continue;
    pending.addAll((projectChildren[id] ?? []).map((p) => p.id));
  }
  final allTasks = {
    for (final t in tasks)
      if (!t.isDeleted && included.contains(t.projectId)) t.id: t,
  };
  final progress = taskSubtaskProgressById(allTasks.values);
  final nodes = <String, ProjectTreeNode>{};
  for (final id in included) {
    final projectTasks = allTasks.values
        .where((t) => t.projectId == id)
        .toList();
    final visible = projectTasks
        .where((t) => showCompleted || !t.isCompleted)
        .toList();
    final rows = visibleTaskRows(
      projectTasks,
      visible,
      expansion: {for (final t in visible) t.id: true},
      compare: (a, b) {
        final order = a.orderKey.compareTo(b.orderKey);
        return order == 0 ? a.id.compareTo(b.id) : order;
      },
    );
    final taskChildren = <String?, List<String>>{};
    for (final row in rows) {
      taskChildren
          .putIfAbsent(row.visibleParentId, () => [])
          .add('t:${row.task.id}');
    }
    for (final row in rows) {
      final t = row.task;
      nodes['t:${t.id}'] = ProjectTreeNode(
        key: 't:${t.id}',
        task: t,
        parentKey: row.visibleParentId == null
            ? 'p:$id'
            : 't:${row.visibleParentId}',
        children: taskChildren[t.id] ?? const [],
        progress:
            progress[t.id] ?? const TaskSubtaskProgress(completed: 0, total: 0),
      );
    }
    final subtreeIds = <String>{};
    final descendants = [id];
    while (descendants.isNotEmpty) {
      final current = descendants.removeLast();
      if (subtreeIds.add(current))
        descendants.addAll((projectChildren[current] ?? []).map((p) => p.id));
    }
    // ponytail: aggregate each project subtree; cache bottom-up if huge project forests need it.
    final counted = allTasks.values
        .where((t) => subtreeIds.contains(t.projectId))
        .toList();
    nodes['p:$id'] = ProjectTreeNode(
      key: 'p:$id',
      project: byProject[id],
      parentKey: id == projectId ? null : 'p:${parents[id]}',
      children: [
        ...(projectChildren[id] ?? []).map((p) => 'p:${p.id}'),
        ...?taskChildren[null],
      ],
      progress: TaskSubtaskProgress(
        completed: counted.where((t) => t.isCompleted).length,
        total: counted.length,
      ),
    );
  }
  final visibleKeys = <String>[];
  final expanded = <String>{};
  final stack = [(rootKey, 0)];
  while (stack.isNotEmpty) {
    final (key, depth) = stack.removeLast();
    if (!nodes.containsKey(key)) continue;
    visibleKeys.add(key);
    if (key == rootKey || (expansion[key] ?? depth <= 1)) {
      expanded.add(key);
      for (final child in nodes[key]!.children.reversed) {
        stack.add((child, depth + 1));
      }
    }
  }
  return ProjectTreeData(
    rootKey,
    Map.unmodifiable(nodes),
    List.unmodifiable(visibleKeys),
    Set.unmodifiable(expanded),
    Map.unmodifiable(allTasks),
  );
}

class ProjectDiagramDrop {
  const ProjectDiagramDrop({
    required this.sourceKey,
    required this.projectId,
    required this.parentId,
    required this.beforeId,
  });
  final String sourceKey;
  final String projectId;
  final String? parentId;
  final String? beforeId;
}

bool canMoveProjectDiagramNode(ProjectTreeData tree, String key) {
  final node = tree.nodes[key];
  if (node == null || key == tree.rootKey) return false;
  if (node.task case final task?) return task.canEdit;
  final project = node.project!;
  final personalSharedLink =
      project.scopeId != null &&
      project.scopeId != tree.nodes[node.parentKey]?.project?.scopeId;
  return !project.isArchived && (project.canEdit || personalSharedLink);
}

// Flutter decides acceptance on target entry; pointer zones can change later.
bool canEnterProjectDiagramDrop(
  ProjectTreeData tree,
  String source,
  String target,
) => ProjectDropPosition.values.any(
  (position) => projectDiagramDrop(tree, source, target, position) != null,
);

ProjectDiagramDrop? projectDiagramDrop(
  ProjectTreeData tree,
  String sourceKey,
  String targetKey,
  ProjectDropPosition position,
) {
  if (!canMoveProjectDiagramNode(tree, sourceKey) || sourceKey == targetKey)
    return null;
  final source = tree.nodes[sourceKey]!, target = tree.nodes[targetKey];
  if (target == null) return null;
  if (source.task case final task?) {
    if (target.project != null && position != ProjectDropPosition.inside)
      return null;
    final projectId = target.project?.id ?? target.task!.projectId;
    final destination = tree.nodes['p:$projectId']?.project;
    if (destination == null ||
        !destination.canEdit ||
        destination.isArchived ||
        task.scopeId != destination.scopeId)
      return null;
    final parentId = position == ProjectDropPosition.inside
        ? target.task?.id
        : target.task?.parentId;
    final parent = tree.tasksById[parentId];
    if (parentId != null &&
        (parent == null || !parent.canEdit || parent.projectId != projectId))
      return null;
    var ancestorId = parentId;
    final seen = <String>{};
    while (ancestorId != null && seen.add(ancestorId)) {
      if (ancestorId == task.id) return null;
      ancestorId = tree.tasksById[ancestorId]?.parentId;
    }
    String? before;
    if (position != ProjectDropPosition.inside) {
      // Display can promote children of hidden completed parents. Placement uses
      // persisted parentage, not that display-only promotion.
      final siblings =
          tree.nodes.values
              .map((n) => n.task)
              .whereType<TaskItem>()
              .where(
                (t) =>
                    t.id != task.id &&
                    t.projectId == projectId &&
                    t.parentId == parentId,
              )
              .toList()
            ..sort((a, b) {
              final c = a.orderKey.compareTo(b.orderKey);
              return c == 0 ? a.id.compareTo(b.id) : c;
            });
      final index = siblings.indexWhere((t) => t.id == target.task!.id);
      if (index < 0) return null;
      before = position == ProjectDropPosition.before
          ? siblings[index].id
          : index + 1 < siblings.length
          ? siblings[index + 1].id
          : null;
    }
    return ProjectDiagramDrop(
      sourceKey: sourceKey,
      projectId: projectId,
      parentId: parentId,
      beforeId: before,
    );
  }
  if (target.project == null ||
      targetKey == tree.rootKey && position != ProjectDropPosition.inside)
    return null;
  final projects = tree.nodes.values
      .map((n) => n.project)
      .whereType<ProjectItem>()
      .toList();
  final move = projectDropTarget(
    projects,
    source.project!.id,
    target.project!.id,
    position,
  );
  if (move == null || move.parentId == null) return null;
  final destination = tree.nodes['p:${move.parentId}']?.project;
  if (destination == null) return null;
  final project = source.project!;
  final sharedRoot =
      project.scopeId != null &&
      project.scopeId != tree.nodes[source.parentKey]?.project?.scopeId;
  if (sharedRoot
      ? destination.scopeId != null
      : !destination.canEdit || project.scopeId != destination.scopeId)
    return null;
  return ProjectDiagramDrop(
    sourceKey: sourceKey,
    projectId: destination.id,
    parentId: destination.id,
    beforeId: move.beforeProjectId,
  );
}
