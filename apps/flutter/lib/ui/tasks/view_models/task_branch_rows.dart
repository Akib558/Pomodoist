import 'package:pomodoist/domain/models/tasks/task_models.dart';

List<VisibleTaskRow> visibleTaskRows(
  List<TaskItem> allItems,
  List<TaskItem> visibleItems, {
  Map<String, bool> expansion = const {},
  int Function(TaskItem, TaskItem)? compare,
  int Function(TaskItem, TaskItem)? compareRoots,
}) {
  final eligible = {for (final task in visibleItems) task.id: task};
  final byId = {for (final task in allItems) task.id: task, ...eligible};
  final parentById = {
    for (final task in eligible.values)
      task.id: eligible.containsKey(task.parentId) && task.parentId != task.id
          ? task.parentId
          : null,
  };
  final order = compare ?? compareTaskOrder;
  final ordered = eligible.values.toList()..sort(compareRoots ?? order);

  // Break invalid cycles before applying expansion, so hidden descendants never
  // reappear as fallback roots.
  final checked = <String>{};
  for (final task in ordered) {
    final path = <String>{};
    String? id = task.id;
    while (id != null && !checked.contains(id)) {
      if (!path.add(id)) {
        parentById[id] = null;
        break;
      }
      id = parentById[id];
    }
    checked.addAll(path);
  }

  final childrenByParent = <String?, List<TaskItem>>{};
  for (final task in eligible.values) {
    childrenByParent.putIfAbsent(parentById[task.id], () => []).add(task);
  }
  for (final entry in childrenByParent.entries) {
    entry.value.sort(entry.key == null ? compareRoots ?? order : order);
  }

  final rows = <VisibleTaskRow>[];
  void walk(List<TaskItem> siblings, List<bool> continuations) {
    for (var index = 0; index < siblings.length; index++) {
      final task = siblings[index];
      final children = childrenByParent[task.id] ?? const <TaskItem>[];
      final expanded = expansion[task.id] ?? continuations.isEmpty;
      final isLast = index == siblings.length - 1;
      rows.add(
        VisibleTaskRow(
          task: task,
          depth: continuations.length,
          visibleParentId: parentById[task.id],
          ancestors: taskAncestorPath(task, byId),
          hasVisibleChildren: children.isNotEmpty,
          expanded: expanded,
          ancestorContinuations: List.unmodifiable(continuations),
          isLastSibling: isLast,
        ),
      );
      if (expanded) {
        walk(children, [...continuations, !isLast]);
      }
    }
  }

  walk(childrenByParent[null] ?? const [], const []);
  return withTaskBranchGroups(rows);
}

/// Annotate the displayed forest without changing its order or membership.
/// Also works when details omit the task that owns the displayed subtree.
List<VisibleTaskRow> withTaskBranchGroups(List<VisibleTaskRow> rows) {
  final roots = <String, VisibleTaskRow>{};
  final rootByTask = <String, String?>{};
  final lastByRoot = <String, String>{};
  for (final row in rows) {
    final parentRoot = rootByTask[row.visibleParentId];
    final isRoot = !rootByTask.containsKey(row.visibleParentId);
    final root = isRoot && row.hasVisibleChildren ? row.task.id : parentRoot;
    if (root == row.task.id) roots[root!] = row;
    rootByTask[row.task.id] = root;
    if (root != null) lastByRoot[root] = row.task.id;
  }
  return List.unmodifiable([
    for (final row in rows)
      VisibleTaskRow(
        task: row.task,
        depth: row.depth,
        visibleParentId: row.visibleParentId,
        ancestors: row.ancestors,
        hasVisibleChildren: row.hasVisibleChildren,
        expanded: row.expanded,
        ancestorContinuations: row.ancestorContinuations,
        isLastSibling: row.isLastSibling,
        groupRootId: rootByTask[row.task.id],
        groupRootDepth: roots[rootByTask[row.task.id]]?.depth ?? 0,
        endsGroup: lastByRoot[rootByTask[row.task.id]] == row.task.id,
      ),
  ]);
}

List<TaskItem> taskAncestorPath(TaskItem task, Map<String, TaskItem> byId) {
  final ancestors = <TaskItem>[];
  final seen = {task.id};
  var parentId = task.parentId;
  while (parentId != null && seen.add(parentId)) {
    final parent = byId[parentId];
    if (parent == null || parent.isDeleted) break;
    ancestors.add(parent);
    parentId = parent.parentId;
  }
  return List.unmodifiable(ancestors.reversed);
}

Set<String> descendantTaskIds(String parentId, Iterable<TaskItem> tasks) {
  final byId = {for (final task in tasks) task.id: task};
  final children = <String, List<String>>{};
  for (final task in byId.values) {
    final parent = task.parentId;
    if (parent != null) {
      children.putIfAbsent(parent, () => []).add(task.id);
    }
  }
  final visited = {parentId};
  final pending = [...?children[parentId]];
  while (pending.isNotEmpty) {
    final id = pending.removeLast();
    if (visited.add(id)) pending.addAll(children[id] ?? const []);
  }
  return visited..remove(parentId);
}

int compareTaskOrder(TaskItem a, TaskItem b) {
  final dayOrderCompare = (a.dayOrder ?? 999999).compareTo(
    b.dayOrder ?? 999999,
  );
  if (dayOrderCompare != 0) return dayOrderCompare;
  return a.orderKey.compareTo(b.orderKey);
}

class VisibleTaskRow {
  const VisibleTaskRow({
    required this.task,
    required this.depth,
    this.visibleParentId,
    this.ancestors = const [],
    this.hasVisibleChildren = false,
    bool? expanded,
    this.ancestorContinuations = const [],
    this.isLastSibling = true,
    this.groupRootId,
    this.groupRootDepth = 0,
    this.endsGroup = false,
  }) : expanded = expanded ?? depth == 0;

  final TaskItem task;
  final int depth;
  int get displayDepth => depth > 2 ? 2 : depth;
  final String? visibleParentId;
  final List<TaskItem> ancestors;
  final bool hasVisibleChildren;
  final bool expanded;
  final List<bool> ancestorContinuations;
  final bool isLastSibling;
  final String? groupRootId;
  final int groupRootDepth;
  final bool endsGroup;
  bool get startsGroup => groupRootId == task.id;
  int get groupDisplayDepth => (depth - groupRootDepth).clamp(0, 2);
  bool get needsAncestorContext =>
      ancestors.isNotEmpty && (visibleParentId == null || depth > 2);
}

TaskItem? taskParentForNavigation(
  TaskItem task,
  Map<String, TaskItem> byId, {
  bool selectionActive = false,
}) {
  if (selectionActive || task.isDeleted || task.parentId == task.id) {
    return null;
  }
  final parent = byId[task.parentId];
  return parent == null || parent.isDeleted ? null : parent;
}
