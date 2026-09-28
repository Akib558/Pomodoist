import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'project_tree_data.dart';

typedef ProjectDiagramState = ({
  ProjectTreeData tree,
  bool loading,
  bool hasError,
  bool showCompleted,
});
final projectDiagramViewModelProvider = NotifierProvider.autoDispose
    .family<ProjectDiagramViewModel, ProjectDiagramState, String?>(
      ProjectDiagramViewModel.new,
    );

class ProjectDiagramViewModel extends Notifier<ProjectDiagramState> {
  ProjectDiagramViewModel(this.projectId);
  final String? projectId;
  String _search = '';
  bool _archivedOnly = false;
  bool _showCompleted = false;
  @override
  ProjectDiagramState build() {
    final projects = ref.watch(projectsProvider);
    final open = ref.watch(tasksByQueryProvider(const TaskQuery.all()));
    final completed = ref.watch(
      tasksByQueryProvider(const TaskQuery.completed()),
    );
    final expansion =
        ref.watch(taskBranchExpansionProvider)[projectDiagramScope(
          projectId,
        )] ??
        const <String, bool>{};
    return (
      tree: projectTreeData(
        projectId,
        projects.value ?? [],
        [...?open.value, ...?completed.value],
        expansion: expansion,
        showCompleted: _showCompleted,
        search: _search,
        archivedOnly: _archivedOnly,
      ),
      loading: projects.isLoading || open.isLoading || completed.isLoading,
      hasError: projects.hasError || open.hasError || completed.hasError,
      showCompleted: _showCompleted,
    );
  }

  void setCatalogFilter({String? search, bool? archivedOnly}) {
    if (projectId != null) return;
    _search = search ?? _search;
    _archivedOnly = archivedOnly ?? _archivedOnly;
    ref.invalidateSelf();
  }

  void showCompleted(bool value) {
    _showCompleted = value;
    ref.invalidateSelf();
  }

  void retry() {
    ref.invalidate(projectsProvider);
    ref.invalidate(tasksByQueryProvider(const TaskQuery.all()));
    ref.invalidate(tasksByQueryProvider(const TaskQuery.completed()));
  }

  Future<void> setMode(ProjectViewMode mode) async {
    final repository = ref.read(taskPreferencesRepositoryProvider);
    (await (projectId == null
            ? repository.setProjectCatalogViewMode(mode)
            : repository.setProjectViewMode(mode)))
        .getOrThrow();
  }

  Future<void> expand(String key, bool expanded) async =>
      (await ref
              .read(taskPreferencesRepositoryProvider)
              .setBranchExpanded(projectDiagramScope(projectId), key, expanded))
          .getOrThrow();
  Future<void> reveal(String key) async {
    final preferences = ref.read(taskPreferencesRepositoryProvider);
    final tree = state.tree;
    String? current = key;
    while (current != null) {
      (await preferences.setBranchExpanded(
        projectDiagramScope(projectId),
        current,
        true,
      )).getOrThrow();
      current = tree.nodes[current]?.parentKey;
    }
  }

  Future<void> place(ProjectDiagramDrop target) async {
    if (!state.tree.movesEnabled) {
      throw StateError('Structural moves are disabled');
    }
    // Repositories revalidate permissions and destinations against current storage.
    if (target.sourceKey.startsWith('p:')) {
      (await ref
              .read(projectRepositoryProvider)
              .moveProject(
                target.sourceKey.substring(2),
                parentId: target.parentId,
                beforeProjectId: target.beforeId,
              ))
          .getOrThrow();
    } else {
      (await ref
              .read(taskRepositoryProvider)
              .placeTask(
                target.sourceKey.substring(2),
                projectId: target.projectId!,
                parentId: target.parentId,
                beforeTaskId: target.beforeId,
              ))
          .getOrThrow();
    }
    if (!ref.mounted) return;
    await reveal(
      target.projectId == null
          ? projectCatalogRootKey
          : target.sourceKey.startsWith('p:') || target.parentId == null
          ? 'p:${target.projectId}'
          : 't:${target.parentId}',
    );
  }
}
