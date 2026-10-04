// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/config/task_preferences_dependencies.dart';
import 'package:pomodoist/data/repositories/tasks/task_repository_impl.dart';
import 'package:pomodoist/data/repositories/notifications/local_notification_repository.dart';
import 'package:pomodoist/data/repositories/productivity/productivity_repository_impl.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/notifications/notification_copy.dart';
import 'package:pomodoist/ui/planning/view_models/today_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/task_list_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/task_subtask_progress.dart';
import 'package:pomodoist/ui/tasks/view_models/upcoming_day_groups.dart';
import 'package:pomodoist/ui/tasks/view_models/upcoming_view_model.dart';
import 'package:pomodoist/utils/clock.dart';

final now = DateTime(2026, 10, 3, 12);

final metrics = <String, Object?>{};
void main() {
  tearDownAll(() {
    final path = Platform.environment['PERFORMANCE_OUTPUT'];
    if (path != null)
      File(
        path,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(metrics));
  });
  test('fixed computation benchmark', () {
    for (final n in [40, 1000]) {
      final same = List.generate(n, (i) => CountedTask('$i'));
      final spread = List.generate(
        n,
        (i) => CountedTask('$i', day: now.add(Duration(days: i))),
      );
      final chain = List.generate(
        n,
        (i) => CountedTask('$i', parent: i == 0 ? null : '${i - 1}'),
      );
      final mixed = List.generate(
        n,
        (i) => CountedTask(
          '$i',
          timed: i.isEven,
          day: now.add(Duration(days: i % 7)),
          parent: i % 4 == 0 ? null : '${i - i % 4}',
        ),
      );
      final history = [
        ...List.generate(
          10000,
          (i) => CountedTask('history-$i', completed: true),
        ),
        ...same.take(40),
      ];
      final scenarios = <String, void Function()>{
        'one_day_$n': () {
          buildUpcomingDayGroups(same, allItems: same);
        },
        'different_days_$n': () {
          buildUpcomingDayGroups(spread, allItems: spread);
        },
        'mixed_$n': () {
          buildUpcomingDayGroups(mixed, allItems: mixed);
        },
        'progress_chain_$n': () {
          taskSubtaskProgressById(chain);
        },
        if (n == 40)
          'history_10000': () {
            TaskListState(tasks: AsyncData(same), allTasks: history).rows(same);
          },
      };
      for (final entry in scenarios.entries) {
        for (var i = 0; i < 20; i++) {
          entry.value();
        }
        final samples = <int>[];
        for (var i = 0; i < 100; i++) {
          final stopwatch = Stopwatch()..start();
          entry.value();
          stopwatch.stop();
          samples.add(stopwatch.elapsedMicroseconds);
        }
        final sorted = [...samples]..sort();
        metrics[entry.key] = {
          'samples_us': samples,
          'median_us': (sorted[49] + sorted[50]) / 2,
          'p95_us': sorted[94],
          'min_us': sorted.first,
          'max_us': sorted.last,
        };
      }
    }
  });
  for (final n in [40, 1000]) {
    test('upcoming recomputes unchanged $n tasks on every second', () async {
      final tasks = List.generate(n, (i) => CountedTask('$i'));
      final ticks = StreamController<DateTime>();
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(FixedClock(now)),
          taskTimeTickerProvider.overrideWith((ref) => ticks.stream),
          tasksByQueryProvider(
            const TaskQuery.all(),
          ).overrideWith((ref) => Stream.value(tasks)),
          tasksByQueryProvider(
            const TaskQuery.completed(),
          ).overrideWith((ref) => Stream.value([])),
          tasksByQueryProvider(
            const TaskQuery.inbox(),
          ).overrideWith((ref) => Stream.value(tasks)),
          projectsProvider.overrideWith((ref) => Stream.value([])),
          taskBranchExpansionProvider.overrideWithValue(const {}),
        ],
      );
      var upcomingUpdates = 0;
      var listUpdates = 0;
      var todayUpdates = 0;
      final upcoming = container.listen(
        upcomingViewModelProvider(null),
        (_, _) => upcomingUpdates++,
      );
      final list = container.listen(
        taskListViewModelProvider(const TaskQuery.inbox()),
        (_, _) => listUpdates++,
      );
      final today = container.listen(
        todayViewModelProvider,
        (_, _) => todayUpdates++,
      );
      ticks.add(now);
      await container.read(taskTimeTickerProvider.future);
      await container.read(tasksByQueryProvider(const TaskQuery.all()).future);
      await container.read(
        tasksByQueryProvider(const TaskQuery.completed()).future,
      );
      await container.read(projectsProvider.future);
      await flush(container);
      final before = container.read(upcomingViewModelProvider(null));
      upcomingUpdates = listUpdates = todayUpdates = CountedTask.scheduleReads =
          0;
      for (var second = 1; second <= 10; second++) {
        ticks.add(now.add(Duration(seconds: second)));
        await flush(container);
      }
      final after = container.read(upcomingViewModelProvider(null));
      metrics['idle_$n'] = {
        'upcoming_updates': upcomingUpdates,
        'list_updates': listUpdates,
        'today_updates': todayUpdates,
        'schedule_getters': CountedTask.scheduleReads,
      };
      expect(after.today, before.today);
      expect(after.scheduledCounts, before.scheduledCounts);
      expect(after.groups.single.rows.length, n);

      expect(listUpdates, 0);
      expect(todayUpdates, 0);

      print(
        'UPCOMING n=$n: updates=$upcomingUpdates/10 ticks, '
        'schedule decodes=${CountedTask.scheduleReads}; list updates=$listUpdates; '
        'today updates=$todayUpdates',
      );
      today.close();
      upcoming.close();
      list.close();
      container.dispose();
      await ticks.close();
    });

    test(
      'unrelated change reschedules all $n existing task reminders',
      () async {
        final scheduler = RecordingScheduler();
        final repository = LocalNotificationRepository(
          scheduler,
          NotificationCopy.english,
        );
        final tasks = List.generate(
          n,
          (i) => CountedTask(
            '$i',
            timed: true,
            day: now.add(const Duration(days: 1)),
          ),
        );
        await repository.syncTaskStartNotifications(tasks: tasks, now: now);
        expect(scheduler.scheduled, n);
        await repository.syncTaskStartNotifications(
          tasks: [...tasks, CountedTask('unrelated-all-day')],
          now: now,
        );

        metrics['reminders_$n'] = {
          'rescheduled': scheduler.scheduled - n,
          'permissions': scheduler.permissions,
        };
        print(
          'NOTIFICATIONS n=$n: $n existing reminders rescheduled '
          'after unrelated all-day task change',
        );
      },
    );

    test('day grouping rescans all metadata for each of $n days', () {
      final sameDay = List.generate(n, (i) => CountedTask('$i'));
      final separateDays = List.generate(
        n,
        (i) => CountedTask('$i', day: now.add(Duration(days: i))),
      );
      CountedTask.idReads = 0;
      final same = buildUpcomingDayGroups(sameDay, allItems: sameDay);
      final sameReads = CountedTask.idReads;
      CountedTask.idReads = 0;
      final spread = buildUpcomingDayGroups(
        separateDays,
        allItems: separateDays,
      );
      final spreadReads = CountedTask.idReads;
      metrics['grouping_$n'] = {
        'same_day_ids': sameReads,
        'different_day_ids': spreadReads,
      };
      expect(same.single.rows.length, n);
      expect(spread.length, n);

      expect(sameReads, lessThan(30 * n));
      print(
        'GROUPING n=$n: id accesses one day=$sameReads, '
        '$n days=$spreadReads',
      );
    });

    test(
      'unchanged timed status suppresses notifications for $n rows',
      () async {
        final tasks = List.generate(n, (i) => CountedTask('$i', timed: true));
        final ticks = StreamController<DateTime>();
        final container = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(FixedClock(now)),
            taskTimeTickerProvider.overrideWith((ref) => ticks.stream),
            activeFocusRunProvider.overrideWith((ref) => Stream.value(null)),
          ],
        );
        var updates = 0;
        final subscriptions = [
          for (final task in tasks)
            container.listen(taskTimeStateProvider(task), (_, _) => updates++),
        ];
        ticks.add(now);
        await container.read(taskTimeTickerProvider.future);
        await container.read(activeFocusRunProvider.future);
        await flush(container);
        updates = CountedTask.scheduleReads = 0;
        for (var second = 1; second <= 10; second++) {
          ticks.add(now.add(Duration(seconds: second)));
          await flush(container);
        }
        expect(updates, 0);

        print(
          'TIME SELECT n=$n: notifications=$updates, '
          'schedule decodes=${CountedTask.scheduleReads}/10 ticks',
        );
        for (final subscription in subscriptions) {
          subscription.close();
        }
        container.dispose();
        await ticks.close();
      },
    );

    test('one invisible task update invalidates the $n-task list', () async {
      final recorder = SelectRecorder();
      final db = AppDatabase(NativeDatabase.memory().interceptWith(recorder));
      await db.ensureSeedData();
      await db.batch((batch) {
        batch.insertAll(db.tasks, [
          for (var i = 0; i < n; i++)
            TasksCompanion.insert(
              id: 'task-$i',
              userId: localUserId,
              content: 'Task $i',
              projectId: inboxProjectId,
              orderKey: '$i'.padLeft(8, '0'),
              createdAt: now,
              updatedAt: now,
            ),
        ]);
      });
      final repository = DriftTaskRepository(db, DriftOutboxService(db));
      final container = ProviderContainer(
        overrides: [taskRepositoryProvider.overrideWithValue(repository)],
      );
      var listUpdates = 0;
      var hierarchyUpdates = 0;
      var todayUpdates = 0;
      final list = container.listen(
        taskListViewModelProvider(const TaskQuery.inbox()),
        (_, _) => listUpdates++,
      );
      final hierarchy = container.listen(
        taskHierarchyViewModelProvider,
        (_, _) => hierarchyUpdates++,
      );
      final todayQuery = TaskQuery(kind: TaskQueryKind.today, now: now);
      final today = container.listen(
        tasksByQueryProvider(todayQuery),
        (_, _) => todayUpdates++,
      );
      await container.read(
        tasksByQueryProvider(const TaskQuery.inbox()).future,
      );
      await container.read(tasksByQueryProvider(const TaskQuery.all()).future);
      await container.read(
        tasksByQueryProvider(const TaskQuery.completed()).future,
      );
      await container.read(tasksByQueryProvider(todayQuery).future);
      await flush(container);
      final before = container
          .read(taskListViewModelProvider(const TaskQuery.inbox()))
          .tasks
          .requireValue;
      expect(before.length, n);
      expect(
        container.read(tasksByQueryProvider(todayQuery)).requireValue,
        isEmpty,
      );
      final emitted = Completer<void>();
      final emission = container.listen(
        tasksByQueryProvider(const TaskQuery.inbox()),
        (_, next) {
          if (next.value?.any(
                    (t) => t.id == 'task-${n - 1}' && t.content == 'Changed',
                  ) ==
                  true &&
              !emitted.isCompleted) {
            emitted.complete();
          }
        },
      );
      recorder.reads.clear();
      listUpdates = hierarchyUpdates = todayUpdates = 0;
      await (db.update(db.tasks)..where((t) => t.id.equals('task-${n - 1}')))
          .write(const TasksCompanion(content: Value('Changed')));
      await emitted.future.timeout(const Duration(seconds: 5));
      await flush(container);
      final after = container
          .read(taskListViewModelProvider(const TaskQuery.inbox()))
          .tasks
          .requireValue;
      final identityChanges = [
        for (var i = 0; i < n; i++)
          if (!identical(before[i], after[i])) i,
      ].length;

      metrics['repository_$n'] = {
        'new_identities': identityChanges,
        'list_updates': listUpdates,
        'hierarchy_updates': hierarchyUpdates,
        'today_updates': todayUpdates,
        'sql_rows': recorder.reads.map((r) => r.rows).toList(),
      };
      expect(listUpdates, greaterThan(0));
      expect(hierarchyUpdates, greaterThan(0));

      expect(
        recorder.reads.where((r) => r.rows == n).length,
        greaterThanOrEqualTo(2),
      );
      print(
        'DRIFT n=$n: new task identities=$identityChanges, '
        'list updates=$listUpdates, hierarchy updates=$hierarchyUpdates, '
        'empty today updates=$todayUpdates; '
        'task SELECT row counts=${recorder.reads.map((r) => r.rows).toList()}',
      );
      emission.close();
      list.close();
      hierarchy.close();
      today.close();
      container.dispose();
      await db.close();
    });
  }

  test('descendant progress work is quadratic only for nested chains', () {
    for (final n in [40, 1000]) {
      final flat = List.generate(n, (i) => CountedTask('$i'));
      final chain = List.generate(
        n,
        (i) => CountedTask('$i', parent: i == 0 ? null : '${i - 1}'),
      );
      CountedTask.completionReads = 0;
      expect(taskSubtaskProgressById(flat), isEmpty);
      expect(CountedTask.completionReads, 0);
      final progress = taskSubtaskProgressById(chain);
      expect(progress['0']!.total, n - 1);

      metrics['progress_$n'] = {
        'completion_reads': CountedTask.completionReads,
      };
      print(
        'PROGRESS n=$n: flat visits=0, chain visits=${CountedTask.completionReads}',
      );
    }
  });

  test(
    '40 visible tasks still scan 10000 completed tasks for row projection',
    () {
      final visible = List.generate(40, (i) => CountedTask('$i'));
      final history = List.generate(
        10000,
        (i) => CountedTask('history-$i', completed: true),
      );
      final state = TaskListState(
        tasks: AsyncData(visible),
        allTasks: [...history, ...visible],
      );
      CountedTask.idReads = 0;
      expect(state.rows(visible).length, 40);
      expect(CountedTask.idReads, greaterThanOrEqualTo(10040));
      print(
        'HISTORY: 40 visible + 10000 completed, '
        'row projection id accesses=${CountedTask.idReads}',
      );
    },
  );

  test('productivity subscribes to full rows then reads them again', () async {
    final recorder = SelectRecorder();
    final db = AppDatabase(NativeDatabase.memory().interceptWith(recorder));
    await db.ensureSeedData();
    await db.batch((batch) {
      batch.insertAll(db.tasks, [
        for (var i = 0; i < 40; i++)
          TasksCompanion.insert(
            id: '$i',
            userId: localUserId,
            content: '$i',
            projectId: inboxProjectId,
            orderKey: '$i',
            createdAt: now,
            updatedAt: now,
          ),
      ]);
    });
    recorder.reads.clear();
    final loaded = Completer<void>();
    final repository = DriftProductivityRepository(db);
    final subscription = repository.watchTodaySummary().listen((summary) {
      if (!loaded.isCompleted) loaded.complete();
    });
    await loaded.future.timeout(const Duration(seconds: 5));
    final taskReads = recorder.reads.length;

    metrics['productivity'] = {
      'task_reads': taskReads,
      'task_rows': recorder.reads.fold<int>(0, (sum, r) => sum + r.rows),
    };
    print(
      'PRODUCTIVITY initial: task SELECTs=$taskReads, '
      'total task rows transferred=${recorder.reads.fold<int>(0, (sum, r) => sum + r.rows)}',
    );
    await subscription.cancel();
    await db.close();
  });

  test(
    'closed task details pause database subscriptions despite cached state',
    () async {
      final recorder = SelectRecorder();
      final db = AppDatabase(NativeDatabase.memory().interceptWith(recorder));
      await db.ensureSeedData();
      await db.batch((batch) {
        batch.insertAll(db.tasks, [
          for (var i = 0; i < 40; i++)
            TasksCompanion.insert(
              id: '$i',
              userId: localUserId,
              content: '$i',
              projectId: inboxProjectId,
              orderKey: '$i',
              createdAt: now,
              updatedAt: now,
            ),
        ]);
      });
      final container = ProviderContainer(
        overrides: [
          taskRepositoryProvider.overrideWithValue(
            DriftTaskRepository(db, DriftOutboxService(db)),
          ),
        ],
      );
      for (var i = 0; i < 40; i++) {
        final details = container.listen(taskProvider('$i'), (_, _) {});
        await container.read(taskProvider('$i').future);
        details.close();
      }
      await flush(container);
      for (var i = 0; i < 40; i++) {
        expect(container.exists(taskProvider('$i')), isTrue);
      }
      recorder.reads.clear();
      await (db.update(db.tasks)..where((t) => t.id.equals('0'))).write(
        const TasksCompanion(content: Value('Changed')),
      );
      await flush(container);
      expect(recorder.reads, isEmpty);
      final changed = Completer<void>();
      final resumed = container.listen(taskProvider('0'), (_, next) {
        if (next.value?.content == 'Changed' && !changed.isCompleted)
          changed.complete();
      });
      await changed.future.timeout(const Duration(seconds: 5));
      await flush(container);
      expect(recorder.reads.length, 1);
      print(
        'LIFECYCLE: 40 closed details issue 0 task SELECTs; '
        'reopening one causes 1 SELECT',
      );
      resumed.close();
      container.dispose();
      await db.close();
    },
  );
}

Future<void> flush(ProviderContainer container) async {
  await Future<void>.delayed(Duration.zero);
  await container.pump();
}

class CountedTask extends TaskItem {
  CountedTask(
    String id, {
    DateTime? day,
    bool timed = false,
    String? parent,
    bool completed = false,
  }) : super(
         id: id,
         userId: 'u',
         content: id,
         projectId: inboxProjectId,
         priority: 4,
         status: completed ? 'completed' : 'open',
         completedFocusIntervals: 0,
         totalFocusSeconds: 0,
         orderKey: id.padLeft(8, '0'),
         isDeleted: false,
         createdAt: now,
         updatedAt: now,
         parentId: parent,
         dueJson:
             (timed
                     ? TaskSchedule.timed(
                         start: day ?? now,
                         end: (day ?? now).add(const Duration(hours: 1)),
                       )
                     : TaskSchedule.allDay(day ?? now))
                 .toJsonString(),
       );
  static int scheduleReads = 0;
  static int idReads = 0;
  static int completionReads = 0;
  @override
  TaskSchedule? get schedule {
    scheduleReads++;
    return super.schedule;
  }

  @override
  String get id {
    idReads++;
    return super.id;
  }

  @override
  bool get isCompleted {
    completionReads++;
    return super.isCompleted;
  }
}

class RecordingScheduler extends NotificationScheduler {
  int scheduled = 0;
  int permissions = 0;
  final pending = <String>{};
  @override
  Future<Set<String>> pendingTaskStartTaskIds() async => {...pending};
  @override
  Future<void> requestNotificationPermissions() async {
    permissions++;
  }

  @override
  Future<void> scheduleTaskStart({
    required String taskId,
    required DateTime startAt,
    required String title,
    required String body,
  }) async {
    scheduled++;
    pending.add(taskId);
  }
}

class SelectRecorder extends QueryInterceptor {
  final reads = <({String sql, int rows})>[];
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (statement.contains('FROM "tasks"')) {
      reads.add((sql: statement, rows: rows.length));
    }
    return rows;
  }
}
