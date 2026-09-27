import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/settings/task_preferences_repository_impl.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/project_diagram_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/project_tree_data.dart';
import 'package:pomodoist/ui/tasks/view_models/projects_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/project_view_model.dart';
import '../../../testing/models/task_fixtures.dart';

void main() {
  test(
    'catalog filters and disclosure never change another project scope',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = LocalTaskPreferencesRepository(
        PreferencesService(SharedPreferences.getInstance),
      );
      addTearDown(preferences.dispose);
      final projects = [
        buildProject(id: 'root'),
        buildProject(id: 'child', parentId: 'root'),
        buildProject(id: 'arch', isArchived: true),
      ];
      final open = [
        buildTask(id: 'needle', projectId: 'child', content: 'Needle'),
        buildTask(id: 'archtask', projectId: 'arch'),
      ];
      final done = [
        buildTask(
          id: 'done',
          projectId: 'child',
          content: 'Done',
          status: 'completed',
        ),
      ];
      final container = ProviderContainer(
        overrides: [
          taskPreferencesRepositoryProvider.overrideWithValue(preferences),
          projectsProvider.overrideWith((ref) => Stream.value(projects)),
          tasksByQueryProvider(
            const TaskQuery.all(),
          ).overrideWith((ref) => Stream.value(open)),
          tasksByQueryProvider(
            const TaskQuery.completed(),
          ).overrideWith((ref) => Stream.value(done)),
        ],
      );
      addTearDown(container.dispose);
      final catalogProvider = projectDiagramViewModelProvider(null);
      final projectProvider = projectDiagramViewModelProvider('root');
      final catalogSubscription = container.listen(catalogProvider, (_, _) {});
      final projectSubscription = container.listen(projectProvider, (_, _) {});
      addTearDown(catalogSubscription.close);
      addTearDown(projectSubscription.close);
      await container.read(projectsProvider.future);
      await container.read(tasksByQueryProvider(const TaskQuery.all()).future);
      await container.read(
        tasksByQueryProvider(const TaskQuery.completed()).future,
      );
      await container.pump();
      final catalog = container.read(catalogProvider.notifier);
      final project = container.read(projectProvider.notifier);
      await catalog.setMode(ProjectViewMode.branches);
      await project.setMode(ProjectViewMode.map);
      await catalog.expand('p:root', false);
      await container.pump();
      expect(
        container.read(projectCatalogViewModeProvider),
        ProjectViewMode.branches,
      );
      expect(container.read(projectViewModeProvider), ProjectViewMode.map);
      expect(
        container.read(catalogProvider).tree.visibleKeys,
        isNot(contains('p:child')),
      );
      expect(
        container.read(projectProvider).tree.visibleKeys,
        contains('p:child'),
      );
      final before = preferences.state.branchExpansion;
      catalog.setCatalogFilter(search: 'NEEDLE');
      await container.pump();
      expect(
        container.read(catalogProvider).tree.visibleKeys,
        contains('t:needle'),
      );
      expect(preferences.state.branchExpansion, before);
      await expectLater(
        catalog.place(
          const ProjectDiagramDrop(
            sourceKey: 'p:child',
            projectId: null,
            parentId: null,
            beforeId: null,
          ),
        ),
        throwsStateError,
      );
      catalog.setCatalogFilter(search: '');
      await container.pump();
      expect(
        container.read(catalogProvider).tree.visibleKeys,
        isNot(contains('p:child')),
      );
      catalog.showCompleted(true);
      await container.pump();
      expect(container.read(catalogProvider).tree.nodes, contains('t:done'));
      expect(
        container.read(projectProvider).tree.nodes,
        isNot(contains('t:done')),
      );
      catalog.setCatalogFilter(archivedOnly: true);
      await container.pump();
      expect(container.read(catalogProvider).tree.nodes.keys.toSet(), {
        projectCatalogRootKey,
        'p:arch',
        't:archtask',
      });
      expect(container.read(catalogProvider).tree.movesEnabled, false);
    },
  );
}
