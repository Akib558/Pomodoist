import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/projects/project_repository_impl.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/use_cases/quick_add/quick_add_use_case.dart';
import 'package:pomodoist/ui/tasks/view_models/quick_add_view_model.dart';

class _FailTaskInsert extends QueryInterceptor {
  bool enabled = false;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (enabled && statement.contains('INSERT INTO "tasks"')) {
      throw StateError('Injected task failure');
    }
    return super.runInsert(executor, statement, args);
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late QuickAddViewModel model;
  late _FailTaskInsert interceptor;

  setUp(() async {
    interceptor = _FailTaskInsert();
    db = AppDatabase(NativeDatabase.memory().interceptWith(interceptor));
    await db.ensureSeedData();
    final outbox = DriftOutboxService(db);
    container = ProviderContainer(
      overrides: [
        quickAddUseCaseProvider.overrideWithValue(
          QuickAddUseCase(
            parser: const QuickAddParser(),
            taskRepository: DriftTaskRepository(db, outbox),
            projectRepository: DriftProjectRepository(db, outbox),
          ),
        ),
      ],
    );
    final provider = quickAddViewModelProvider(Object());
    container.listen(provider, (_, _) {});
    model = container.read(provider.notifier);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test(
    'comment is saved literally with the task and its sync command',
    () async {
      model.updateDraft(
        'Prepare documents',
        description: '  Tomorrow #NotAProject\nBring originals  ',
      );
      final id = await model.submit();
      expect(id, isNotNull);
      final task = await (db.select(
        db.tasks,
      )..where((row) => row.id.equals(id!))).getSingle();
      expect(task.content, 'Prepare documents');
      expect(task.description, 'Tomorrow #NotAProject\nBring originals');
      final command = await (db.select(
        db.syncCommands,
      )..where((row) => row.type.equals('task.create'))).getSingle();
      expect(jsonDecode(command.payloadJson)['description'], task.description);
      expect(model.state.description, isEmpty);
      expect(model.state.draft, isEmpty);
    },
  );

  test(
    'failed creation keeps the comment and retry creates only one task',
    () async {
      model.updateDraft('Prepare documents', description: 'Bring originals');
      interceptor.enabled = true;
      expect(await model.submit(), isNull);
      expect(model.state.description, 'Bring originals');
      expect(model.state.draft, 'Prepare documents');
      expect(await db.select(db.tasks).get(), isEmpty);
      expect(await db.select(db.syncCommands).get(), isEmpty);
      interceptor.enabled = false;
      expect(await model.submit(), isNotNull);
      final tasks = await db.select(db.tasks).get();
      expect(tasks, hasLength(1));
      expect(tasks.single.description, 'Bring originals');
    },
  );

  test('comment without a task title remains a draft', () async {
    model.updateDraft('', description: 'Bring originals');
    expect(await model.submit(), isNull);
    expect(model.state.description, 'Bring originals');
    expect(await db.select(db.tasks).get(), isEmpty);
  });

  test('blank comments are omitted and drafts stay independent', () async {
    final secondProvider = quickAddViewModelProvider(Object());
    container.listen(secondProvider, (_, _) {});
    final second = container.read(secondProvider.notifier);
    model.updateDraft('First', description: 'Keep this');
    model.updateDraft('Renamed');
    second.updateDraft('Second', description: ' \n ');
    expect(model.state.description, 'Keep this');
    expect(await second.submit(), isNotNull);
    expect((await db.select(db.tasks).get()).single.description, isNull);
    model.clearDraft();
    expect(model.state.description, isEmpty);
  });
}
