import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/task_preferences_repository_impl.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/task_detail_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/task_selection_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_rows.dart';
import 'package:pomodoist/ui/tasks/view_models/upcoming_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/upcoming_day_groups.dart';
import '../../../testing/fakes/fake_task_repository.dart';

void main() {
  test(
    'parent navigation resolves accessible completed or read-only parents',
    () {
      final parent = task('parent', status: 'completed', canEdit: false);
      final child = task('child', parentId: parent.id);
      expect(taskParentForNavigation(child, {parent.id: parent}), same(parent));
      expect(
        taskParentForNavigation(child, {
          parent.id: parent,
        }, selectionActive: true),
        isNull,
      );
    },
  );

  test(
    'parent navigation omits missing parents, roots, and self references',
    () {
      final root = task('root');
      final orphan = task('orphan', parentId: 'missing');
      final self = task('self', parentId: 'self');
      expect(taskParentForNavigation(root, {root.id: root}), isNull);
      expect(taskParentForNavigation(orphan, {}), isNull);
      expect(taskParentForNavigation(self, {self.id: self}), isNull);
      final parent = task('parent');
      expect(
        taskParentForNavigation(
          task('deleted-child', parentId: parent.id, isDeleted: true),
          {parent.id: parent},
        ),
        isNull,
      );
      final deleted = task('deleted', isDeleted: true);
      expect(
        taskParentForNavigation(task('child', parentId: deleted.id), {
          deleted.id: deleted,
        }),
        isNull,
      );
    },
  );

  test(
    'collapsing a branch removes hidden descendants from bulk selection',
    () {
      final parent = task('parent');
      final child = task('child', parentId: parent.id);
      final tasks = [parent, child];
      final container = ProviderContainer(
        overrides: [
          taskRepositoryProvider.overrideWithValue(_Tasks(tasks)),
          projectsProvider.overrideWith((ref) => Stream.value([])),
          labelsProvider.overrideWith((ref) => Stream.value([])),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        taskSelectionViewModelProvider('branches'),
        (_, _) {},
      );
      addTearDown(subscription.close);
      final selection = container.read(
        taskSelectionViewModelProvider('branches').notifier,
      );
      selection.updateVisible(visibleTaskRows(tasks, tasks).map((r) => r.task));
      selection.begin(child.id);
      selection.toggle(parent.id);
      selection.updateVisible(
        visibleTaskRows(
          tasks,
          tasks,
          expansion: {parent.id: false},
        ).map((r) => r.task),
      );
      expect(selection.selectedIds, {parent.id});
      selection.toggleAll();
      selection.toggleAll();
      expect(selection.selectedIds, {parent.id});
    },
  );

  test(
    'day expansion preserves date partitions, metadata, and calendar counts',
    () {
      final parent = task('parent', date: DateTime(2026, 9, 30));
      final child = task(
        'child',
        parentId: parent.id,
        date: DateTime(2026, 9, 29),
      );
      final all = [parent, child];
      final groups = buildUpcomingDayGroups(
        all,
        allItems: all,
        expansion: {'parent': false},
      );
      expect(groups, hasLength(2));
      expect(groups.first.rows.single.task.id, 'child');
      expect(groups.first.rows.single.depth, 0);
      expect(groups.first.rows.single.ancestors.single.id, 'parent');
      expect(scheduledTaskCounts(all), {
        DateTime(2026, 9, 29): 1,
        DateTime(2026, 9, 30): 1,
      });
      final stale = task(child.id, parentId: parent.id, status: 'completed');
      expect(mergeTasks([child], [stale]).single.status, 'open');
    },
  );

  test(
    'details expose all descendants including completed and other dates',
    () async {
      final root = task('root');
      final child = task('child', parentId: root.id);
      final leaf = task('leaf', parentId: child.id, status: 'completed');
      final container = ProviderContainer(
        overrides: [
          tasksByQueryProvider(
            const TaskQuery.all(),
          ).overrideWith((ref) => Stream.value([root, child])),
          tasksByQueryProvider(
            const TaskQuery.completed(),
          ).overrideWith((ref) => Stream.value([leaf])),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        subtasksViewModelProvider(root.id),
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.read(tasksByQueryProvider(const TaskQuery.all()).future);
      await container.read(
        tasksByQueryProvider(const TaskQuery.completed()).future,
      );
      await container.pump();
      expect(
        container
            .read(subtasksViewModelProvider(root.id))
            .tasks
            .requireValue
            .map((t) => t.id),
        ['child', 'leaf'],
      );
    },
  );

  test('branch scopes survive date changes and separate named lists', () {
    expect(
      taskBranchScopeKey(
        TaskQuery(kind: TaskQueryKind.today, now: DateTime(2026)),
      ),
      'today',
    );
    expect(
      taskBranchScopeKey(
        TaskQuery(kind: TaskQueryKind.today, now: DateTime(2027)),
      ),
      'today',
    );
    expect(taskBranchScopeKey(const TaskQuery.upcoming()), 'upcoming');
    expect(
      taskBranchScopeKey(
        const TaskQuery(kind: TaskQueryKind.project, projectId: 'p'),
      ),
      'project:p',
    );
    expect(
      taskBranchScopeKey(
        const TaskQuery(kind: TaskQueryKind.label, labelId: 'l'),
      ),
      'label:l',
    );
  });

  test('creation reveals only ancestor chain in current scope', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = LocalTaskPreferencesRepository(
      PreferencesService(() async => SharedPreferences.getInstance()),
    );
    addTearDown(preferences.dispose);
    final root = task('root');
    final child = task('child', parentId: root.id);
    final leaf = task('leaf', parentId: child.id);
    final repository = _Tasks([root, child, leaf]);
    final container = ProviderContainer(
      overrides: [
        taskRepositoryProvider.overrideWithValue(repository),
        taskPreferencesRepositoryProvider.overrideWithValue(preferences),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      taskBranchViewModelProvider('today'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    await container
        .read(taskBranchViewModelProvider('today').notifier)
        .revealCreatedTasks([leaf.id]);
    expect(preferences.state.branchExpansion['today'], {
      'root': true,
      'child': true,
    });
    expect(preferences.state.branchExpansion['upcoming'], isNull);
    expect(
      preferences.state.branchExpansion['today']!.containsKey('leaf'),
      isFalse,
    );
  });
}

class _Tasks extends FakeTaskRepository {
  _Tasks(this.items);
  final List<TaskItem> items;
  @override
  Stream<TaskItem?> watchTask(String id) =>
      Stream.value(items.where((t) => t.id == id).firstOrNull);
}

TaskItem task(
  String id, {
  String? parentId,
  DateTime? date,
  String status = 'open',
  bool canEdit = true,
  bool isDeleted = false,
}) => TaskItem(
  id: id,
  userId: 'u',
  content: id,
  projectId: 'p',
  parentId: parentId,
  priority: 4,
  status: status,
  dueJson: date == null ? null : TaskSchedule.allDay(date).toJsonString(),
  completedFocusIntervals: 0,
  totalFocusSeconds: 0,
  orderKey: id,
  isDeleted: isDeleted,
  canEdit: canEdit,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
