import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/notifications/local_notification_repository.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/domain/models/notifications/notification_copy.dart';
import 'task_performance_test.dart' show CountedTask, now;

void main() {
  test(
    'same signature requires native pending ID; restart schedules again',
    () async {
      final scheduler = _Scheduler();
      final task = CountedTask(
        'one',
        timed: true,
        day: now.add(const Duration(days: 1)),
      );
      final repository = LocalNotificationRepository(
        scheduler,
        NotificationCopy.english,
      );
      await repository.syncTaskStartNotifications(tasks: [task], now: now);
      await repository.syncTaskStartNotifications(
        tasks: [task, CountedTask('all-day')],
        now: now,
      );
      expect(scheduler.calls, 1);
      scheduler.pending.clear();
      await repository.syncTaskStartNotifications(tasks: [task], now: now);
      expect(scheduler.calls, 2);
      await LocalNotificationRepository(
        scheduler,
        NotificationCopy.english,
      ).syncTaskStartNotifications(tasks: [task], now: now);
      expect(scheduler.calls, 3);
    },
  );
  test('title, localized notification copy and start changes replan', () async {
    final scheduler = _Scheduler();
    var copy = const NotificationCopy.english();
    final repository = LocalNotificationRepository(scheduler, () => copy);
    final task = CountedTask(
      'one',
      timed: true,
      day: now.add(const Duration(days: 1)),
    );
    await repository.syncTaskStartNotifications(tasks: [task], now: now);
    final renamed = TaskItem(
      id: task.id,
      userId: task.userId,
      content: 'Renamed',
      projectId: task.projectId,
      priority: 4,
      dueJson: task.dueJson,
      status: 'open',
      completedFocusIntervals: 0,
      totalFocusSeconds: 0,
      orderKey: task.orderKey,
      isDeleted: false,
      createdAt: now,
      updatedAt: now,
    );
    await repository.syncTaskStartNotifications(tasks: [renamed], now: now);
    expect(scheduler.calls, 2);
    copy = NotificationCopy(
      focusCompleted: copy.focusCompleted,
      longBreakCompleted: copy.longBreakCompleted,
      breakCompleted: copy.breakCompleted,
      focusChannel: copy.focusChannel,
      focusDescription: copy.focusDescription,
      taskChannel: copy.taskChannel,
      taskDescription: copy.taskDescription,
      returnChannel: copy.returnChannel,
      returnDescription: copy.returnDescription,
      openApp: copy.openApp,
      taskStarting: 'Задача начинается',
      returnMessages: copy.returnMessages,
    );
    await repository.syncTaskStartNotifications(tasks: [renamed], now: now);
    expect(scheduler.calls, 3);
    await repository.syncTaskStartNotifications(tasks: [renamed], now: now);
    expect(scheduler.calls, 3);
  });
  test(
    'failed scheduling is retried and queued updates never overlap',
    () async {
      final scheduler = _Scheduler()..failure = true;
      final repository = LocalNotificationRepository(
        scheduler,
        NotificationCopy.english,
      );
      final task = CountedTask(
        'one',
        timed: true,
        day: now.add(const Duration(days: 1)),
      );
      final failed = repository.syncTaskStartNotifications(
        tasks: [task],
        now: now,
      );
      final retry = repository.syncTaskStartNotifications(
        tasks: [task],
        now: now,
      );
      await expectLater(failed, throwsStateError);
      await retry;
      expect(scheduler.calls, 2);
      expect(scheduler.maxActive, 1);
      final moved = CountedTask(
        'one',
        timed: true,
        day: now.add(const Duration(days: 2)),
      );
      await repository.syncTaskStartNotifications(tasks: [moved], now: now);
      expect(scheduler.calls, 3);
      await repository.syncTaskStartNotifications(tasks: [], now: now);
      expect(scheduler.pending, isEmpty);
    },
  );
}

class _Scheduler extends NotificationScheduler {
  final pending = <String>{};
  var calls = 0, active = 0, maxActive = 0;
  var failure = false;
  @override
  Future<Set<String>> pendingTaskStartTaskIds() async => {...pending};
  @override
  Future<void> requestNotificationPermissions() async {}
  @override
  Future<void> cancelTaskStart(String id) async {
    pending.remove(id);
  }

  @override
  Future<void> scheduleTaskStart({
    required String taskId,
    required DateTime startAt,
    required String title,
    required String body,
  }) async {
    calls++;
    active++;
    if (active > maxActive) maxActive = active;
    await Future<void>.delayed(Duration.zero);
    active--;
    if (failure) {
      failure = false;
      throw StateError('native failure');
    }
    pending.add(taskId);
  }
}
