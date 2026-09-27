import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:pomodoist/ui/tasks/view_models/project_tree_data.dart';
import 'package:pomodoist/domain/models/tasks/project_hierarchy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/data/repositories/projects/project_repository_impl.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  late AppDatabase db;
  late DriftTaskRepository tasks;
  late String p, q;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    final queue = DriftOutboxService(db);
    tasks = DriftTaskRepository(db, queue);
    final projects = DriftProjectRepository(db, queue);
    p = (await projects.createProject('P')).getOrThrow();
    q = (await projects.createProject('Q')).getOrThrow();
  });
  tearDown(() => db.close());
  Future<String> add(String title, String project, [String? parent]) async =>
      (await tasks.createTask(
        CreateTaskInput(content: title, projectId: project, parentId: parent),
      )).getOrThrow();
  test(
    'placement moves the entire subtree and orders before a sibling',
    () async {
      final a = await add('A', p), child = await add('child', p);
      (await tasks.moveTask(child, parentId: a)).getOrThrow();
      final b = await add('B', q), c = await add('C', q);
      (await tasks.placeTask(
        a,
        projectId: q,
        parentId: null,
        beforeTaskId: c,
      )).getOrThrow();
      expect((await tasks.watchTask(child).first)!.projectId, q);
      expect((await tasks.watchTask(child).first)!.parentId, a);
      final rows = await tasks
          .watchTasks(TaskQuery(kind: TaskQueryKind.project, projectId: q))
          .first;
      expect(rows.where((t) => t.parentId == null).map((t) => t.id), [b, a, c]);
      (await tasks.placeTask(
        a,
        projectId: q,
        parentId: null,
        beforeTaskId: null,
      )).getOrThrow();
      expect(
        (await tasks
                .watchTasks(
                  TaskQuery(kind: TaskQueryKind.project, projectId: q),
                )
                .first)
            .where((t) => t.parentId == null)
            .map((t) => t.id),
        [b, c, a],
      );
    },
  );
  test(
    'cycles and stale destinations do not change tasks or the outbox',
    () async {
      final a = await add('A', p), b = await add('B', p, a);
      final beforeTasks = await db.select(db.tasks).get();
      final beforeCommands = await db.select(db.syncCommands).get();
      for (final result in [
        await tasks.placeTask(a, projectId: p, parentId: b, beforeTaskId: null),
        await tasks.placeTask(
          a,
          projectId: q,
          parentId: null,
          beforeTaskId: 'missing',
        ),
        await tasks.placeTask(
          a,
          projectId: 'missing',
          parentId: null,
          beforeTaskId: null,
        ),
      ]) {
        expect(result, isA<Failure<void>>());
      }
      expect(await db.select(db.tasks).get(), beforeTasks);
      expect(await db.select(db.syncCommands).get(), beforeCommands);
    },
  );
  test(
    'placement inferred beside an open child of a completed parent succeeds',
    () async {
      final source = await add('Source', p), parent = await add('Parent', p);
      (await tasks.completeTask(parent)).getOrThrow();
      final child = await add('Child', p, parent);
      final projects = await DriftProjectRepository(
        db,
        DriftOutboxService(db),
      ).watchProjects().first;
      final tree = projectTreeData(p, projects, [
        ...await tasks.watchTasks(const TaskQuery.all()).first,
        ...await tasks.watchTasks(const TaskQuery.completed()).first,
      ]);
      final drop = projectDiagramDrop(
        tree,
        't:$source',
        't:$child',
        ProjectDropPosition.before,
      )!;
      (await tasks.placeTask(
        source,
        projectId: drop.projectId,
        parentId: drop.parentId,
        beforeTaskId: drop.beforeId,
      )).getOrThrow();
      expect((await tasks.watchTask(source).first)!.parentId, parent);
    },
  );
  test(
    'scope boundaries and read-only access reject placement without changes',
    () async {
      final source = await add('Private', p), shared = await add('Shared', q);
      await db
          .into(db.sharedScopes)
          .insert(
            SharedScopesCompanion.insert(
              id: 'scope',
              dataJson: jsonEncode({
                'id': 'scope',
                'rootProjectId': q,
                'ownerId': 'owner',
                'role': 'observer',
                'members': [],
              }),
            ),
          );
      await (db.update(db.projects)..where((t) => t.id.equals(q))).write(
        const ProjectsCompanion(scopeId: Value('scope')),
      );
      await (db.update(db.tasks)..where((t) => t.id.equals(shared))).write(
        const TasksCompanion(scopeId: Value('scope')),
      );
      final before = await db.select(db.tasks).get();
      final queue = await db.select(db.syncCommands).get();
      expect(
        await tasks.placeTask(
          source,
          projectId: q,
          parentId: null,
          beforeTaskId: null,
        ),
        isA<Failure<void>>(),
      );
      expect(
        await tasks.placeTask(
          shared,
          projectId: q,
          parentId: null,
          beforeTaskId: null,
        ),
        isA<Failure<void>>(),
      );
      expect(await db.select(db.tasks).get(), before);
      expect(await db.select(db.syncCommands).get(), queue);
    },
  );
  test(
    'an outbox failure rolls back placement and sibling rebalancing',
    () async {
      final a = await add('A', p), b = await add('B', q);
      final beforeTasks = await db.select(db.tasks).get();
      final beforeCommands = await db.select(db.syncCommands).get();
      final failing = DriftTaskRepository(db, _FailingOutbox(db));
      expect(
        await failing.placeTask(
          a,
          projectId: q,
          parentId: null,
          beforeTaskId: b,
        ),
        isA<Failure<void>>(),
      );
      expect(await db.select(db.tasks).get(), beforeTasks);
      expect(await db.select(db.syncCommands).get(), beforeCommands);
    },
  );
}

class _FailingOutbox extends DriftOutboxService {
  _FailingOutbox(super.db);
  @override
  Future<void> enqueueBatch(
    List<SyncQueueCommand> commands, {
    DateTime? occurredAt,
  }) async {
    await super.enqueueBatch(commands, occurredAt: occurredAt);
    throw StateError('disk failure');
  }
}
