import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/view_models/upcoming_view_model.dart';
import 'package:pomodoist/utils/clock.dart';
import 'task_performance_test.dart' show CountedTask, now, flush;

void main() {
  test(
    'repository reuses rows but refreshes changed editing rights and evicts departed rows',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureSeedData();
      String scope(String role) => jsonEncode({
        'id': 'scope',
        'rootProjectId': inboxProjectId,
        'ownerId': 'owner',
        'role': role,
      });
      await db
          .into(db.sharedScopes)
          .insert(
            SharedScopesCompanion.insert(
              id: 'scope',
              dataJson: scope('observer'),
            ),
          );
      await db.batch(
        (batch) => batch.insertAll(db.tasks, [
          for (final id in ['local', 'shared'])
            TasksCompanion.insert(
              id: id,
              userId: localUserId,
              scopeId: Value(id == 'shared' ? 'scope' : null),
              content: id,
              projectId: inboxProjectId,
              orderKey: id,
              createdAt: now,
              updatedAt: now,
            ),
        ]),
      );
      final repository = DriftTaskRepository(db, DriftOutboxService(db));
      final all = StreamIterator(repository.watchTasks(const TaskQuery.all()));
      final one = StreamIterator(repository.watchTask('shared'));
      addTearDown(all.cancel);
      addTearDown(one.cancel);
      await all.moveNext();
      await one.moveNext();
      final oldLocal = all.current.firstWhere((t) => t.id == 'local');
      final oldShared = all.current.firstWhere((t) => t.id == 'shared');
      expect(oldShared.canEdit, isFalse);
      final oldSingle = one.current;
      await (db.update(db.sharedScopes)..where((s) => s.id.equals('scope')))
          .write(SharedScopesCompanion(dataJson: Value(scope('member'))));
      await all.moveNext();
      await one.moveNext();
      expect(all.current.firstWhere((t) => t.id == 'local'), same(oldLocal));
      final newShared = all.current.firstWhere((t) => t.id == 'shared');
      expect(newShared, isNot(same(oldShared)));
      expect(newShared.canEdit, isTrue);
      expect(one.current, isNot(same(oldSingle)));
      expect(one.current!.canEdit, isTrue);
      await (db.update(db.tasks)..where((t) => t.id.equals('local'))).write(
        const TasksCompanion(status: Value('completed')),
      );
      await all.moveNext();
      expect(all.current.map((t) => t.id), ['shared']);
      await (db.update(db.tasks)..where((t) => t.id.equals('local'))).write(
        const TasksCompanion(status: Value('open')),
      );
      await all.moveNext();
      expect(
        all.current.firstWhere((t) => t.id == 'local'),
        isNot(same(oldLocal)),
      );
      expect(all.current.firstWhere((t) => t.id == 'shared'), same(newShared));
    },
  );
  test('Upcoming ignores seconds but recomputes at local midnight', () async {
    final ticks = StreamController<DateTime>();
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(FixedClock(now)),
        taskTimeTickerProvider.overrideWith((ref) => ticks.stream),
        tasksByQueryProvider(const TaskQuery.all()).overrideWith(
          (ref) => Stream.value([
            CountedTask('today'),
            CountedTask('tomorrow', day: now.add(const Duration(days: 1))),
          ]),
        ),
        tasksByQueryProvider(
          const TaskQuery.completed(),
        ).overrideWith((ref) => Stream.value([])),
        projectsProvider.overrideWith((ref) => Stream.value([])),
        taskBranchExpansionProvider.overrideWithValue(const {}),
      ],
    );
    var updates = 0;
    final listener = container.listen(
      upcomingViewModelProvider(null),
      (_, _) => updates++,
    );
    ticks.add(now);
    await container.read(taskTimeTickerProvider.future);
    await container.read(tasksByQueryProvider(const TaskQuery.all()).future);
    await container.read(
      tasksByQueryProvider(const TaskQuery.completed()).future,
    );
    await flush(container);
    updates = 0;
    ticks.add(now.add(const Duration(seconds: 1)));
    await flush(container);
    expect(updates, 0);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    ticks.add(tomorrow);
    await flush(container);
    expect(updates, 1);
    expect(container.read(upcomingViewModelProvider(null)).today, tomorrow);
    expect(
      container
          .read(upcomingViewModelProvider(null))
          .groups
          .single
          .rows
          .single
          .task
          .id,
      'tomorrow',
    );
    listener.close();
    container.dispose();
    await ticks.close();
  });
}
