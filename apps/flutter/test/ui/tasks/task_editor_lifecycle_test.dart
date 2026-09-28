import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/data/repositories/projects/project_repository.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/use_cases/tasks/edit_task_title_use_case.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';
import 'package:pomodoist/ui/tasks/view_models/task_detail_view_model.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'map title editor retains a failed draft and retries without changing other fields',
    () async {
      final repository = _FakeTaskRepository();
      final container = _container(repository: repository);
      addTearDown(container.dispose);
      final identity = Object();
      final subscription = container.listen(
        taskEditorViewModelProvider(identity),
        (_, _) {},
      );
      addTearDown(subscription.close);
      final editor = container.read(
        taskEditorViewModelProvider(identity).notifier,
      );
      final task = _task('original');
      editor.updateDraft('Renamed research');
      repository.failNextUpdate = true;
      expect(await editor.saveTitle(task, editor.state.draft), isFalse);
      expect(editor.state.failed, isTrue);
      expect(editor.state.dirty, isTrue);
      expect(editor.state.draft, 'Renamed research');
      expect(repository.titles, isEmpty);

      repository.failNextUpdate = false;
      expect(await editor.saveTitle(task, editor.state.draft), isTrue);
      expect(editor.state.failed, isFalse);
      expect(editor.state.dirty, isFalse);
      expect(repository.titles, ['Renamed research']);
      expect(repository.descriptions, isEmpty);
    },
  );

  test(
    'a failed draft keeps the editor registered until a retry succeeds',
    () async {
      final repository = _FakeTaskRepository();
      final container = _container(repository: repository);
      addTearDown(container.dispose);
      final task = _task('detail', description: 'Original');
      final identity = Object();
      final guard = container.read(taskDetailSaveGuardProvider);
      final editor = container.read(
        taskEditorViewModelProvider(identity).notifier,
      );
      guard.register(
        identity,
        () => editor.saveDescription(task, editor.state.draft),
      );
      addTearDown(() => guard.unregister(identity));

      editor.updateDraft('Edited description');
      repository.failNextUpdate = true;
      expect(await guard.saveAll(), isFalse);
      expect(editor.state.draft, 'Edited description');
      expect(editor.state.failed, isTrue);
      expect(guard.hasRegisteredEditors, isTrue);

      repository.failNextUpdate = false;
      expect(await guard.saveAll(), isTrue);
      expect(editor.state.failed, isFalse);
      expect(editor.state.draft, 'Edited description');
      expect(repository.descriptions, ['Edited description']);
    },
  );

  test('the guard resolves the editor again after provider disposal', () async {
    final repository = _FakeTaskRepository();
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    final task = _task('detail');
    final identity = Object();
    final guard = container.read(taskDetailSaveGuardProvider);
    final listener = container.listen(
      taskEditorViewModelProvider(identity),
      (_, _) {},
      fireImmediately: true,
    );
    guard.register(
      identity,
      () => container
          .read(taskEditorViewModelProvider(identity).notifier)
          .saveDescription(task, 'Retained draft'),
    );

    listener.close();
    await pumpEventQueue();

    expect(await guard.saveAll(), isTrue);
    expect(repository.descriptions, ['Retained draft']);
    guard.unregister(identity);
    expect(guard.hasRegisteredEditors, isFalse);
    expect(await guard.saveAll(), isTrue);
  });

  test(
    'one failing editor blocks navigation for all retained editors',
    () async {
      final guard = TaskDetailSaveGuard();
      var secondSaved = false;
      guard.register('first', () async => false);
      guard.register('second', () async {
        secondSaved = true;
        return true;
      });
      expect(await guard.saveAll(), isFalse);
      expect(secondSaved, isTrue);

      guard.unregister('first');
      expect(await guard.saveAll(), isTrue);
    },
  );
}

ProviderContainer _container({required _FakeTaskRepository repository}) =>
    ProviderContainer(
      overrides: [
        taskRepositoryProvider.overrideWithValue(repository),
        focusPresetsProvider.overrideWith((ref) => Stream.value([])),
        sharedPreferencesProvider.overrideWith((ref) async => null),
        editTaskTitleUseCaseProvider.overrideWithValue(
          EditTaskTitleUseCase(
            parser: const QuickAddParser(),
            taskRepository: repository,
            projectRepository: _UnusedProjectRepository(),
          ),
        ),
        accountSessionProvider.overrideWith(
          (ref) => Stream.value((userId: null, generation: 0)),
        ),
      ],
    );

TaskItem _task(String id, {String? description}) => TaskItem(
  id: id,
  userId: 'user',
  content: id,
  description: description,
  projectId: 'inbox',
  priority: 4,
  status: 'open',
  completedFocusIntervals: 0,
  totalFocusSeconds: 0,
  orderKey: id,
  isDeleted: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _FakeTaskRepository implements TaskRepository {
  bool failNextUpdate = false;
  final List<String> descriptions = [];
  final List<String> titles = [];

  @override
  Future<Result<void>> updateTask(String id, UpdateTaskPatch patch) =>
      Result.capture(() async {
        if (failNextUpdate) {
          throw StateError('offline');
        }
        if (patch.updateDescription) {
          descriptions.add(patch.description ?? '');
        }
        if (patch.content != null) titles.add(patch.content!);
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedProjectRepository extends Fake implements ProjectRepository {}
