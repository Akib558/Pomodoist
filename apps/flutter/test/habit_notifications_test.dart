import 'dart:async';
import 'package:pomodoist/utils/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/domain/models/notifications/habit_reminder_status.dart';
import 'package:pomodoist/domain/models/notifications/notification_copy.dart';
import 'package:pomodoist/data/repositories/notifications/habit_reminder_plan.dart';
import 'package:pomodoist/data/repositories/notifications/local_notification_repository.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';

void main() {
  setUpAll(tz_data.initializeTimeZones);
  test('calendar notifications keep wall time across both DST transitions', () {
    tz.setLocalLocation(tz.getLocation('Europe/Berlin'));
    final before = NotificationScheduler.habitReminderDate(
      DateTime(2026, 3, 28, 20),
    );
    final after = NotificationScheduler.habitReminderDate(
      DateTime(2026, 3, 29, 20),
    );
    expect(after.hour, 20);
    expect(after.difference(before).inHours, 23);
    final autumnBefore = NotificationScheduler.habitReminderDate(
      DateTime(2026, 10, 24, 20),
    );
    final autumnAfter = NotificationScheduler.habitReminderDate(
      DateTime(2026, 10, 25, 20),
    );
    expect(autumnAfter.hour, 20);
    expect(autumnAfter.difference(autumnBefore).inHours, 25);
    expect(habitDayKey(after), '2026-03-29');
    tz.setLocalLocation(tz.getLocation('America/Los_Angeles'));
    expect(habitDayKey(habitDateFromKey('2026-03-29')), '2026-03-29');
  });
  test('iOS capacity excludes habit slots and reserves Focus', () {
    final pending = List.generate(
      60,
      (i) => PendingNotificationRequest(100000 + i, 'Task', 'Body', 'task'),
    );
    expect(NotificationScheduler.habitNotificationCapacity(pending), 3);
    pending.add(
      PendingNotificationRequest(
        NotificationScheduler.focusNotificationId,
        'Focus',
        'Body',
        'focus',
      ),
    );
    expect(NotificationScheduler.habitNotificationCapacity(pending), 3);
    pending.add(
      const PendingNotificationRequest(
        44000,
        'Habit',
        'Body',
        'habit.reminder:h',
      ),
    );
    expect(NotificationScheduler.habitNotificationCapacity(pending), 3);
    expect(
      NotificationScheduler.habitNotificationCapacity(
        List.generate(
          70,
          (i) => PendingNotificationRequest(i, 'Other', 'Body', 'other'),
        ),
      ),
      0,
    );
  });
  test(
    'native Linux reports unavailable without calling platform channels',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        expect(NotificationScheduler().supportsHabitReminders, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
  final now = DateTime(2026, 9, 30, 12);
  Habit habit({String id = 'h', int target = 2, DateTime? end}) => Habit(
    id: id,
    userId: 'local-user',
    title: 'Read',
    reminderMinutes: 1200,
    scheduleHistory: [
      HabitSchedule(
        effectiveFrom: now,
        startDate: now,
        endDate: end,
        weekdays: const [1, 2, 3, 4, 5, 6, 7],
        targetPerDay: target,
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );
  HabitCheckIn check(String id) => HabitCheckIn(
    id: id,
    userId: 'local-user',
    habitId: 'h',
    day: now,
    createdAt: now,
    updatedAt: now,
  );
  test('partial goal reminds today but complete goal starts tomorrow', () {
    final partial = planHabitReminders(
      habits: [habit()],
      checkIns: [check('1')],
      now: now,
    );
    expect(partial.first.scheduledAt, DateTime(2026, 9, 30, 20));
    final complete = planHabitReminders(
      habits: [habit()],
      checkIns: [check('1'), check('2')],
      now: now,
    );
    expect(complete.first.scheduledAt, DateTime(2026, 10, 1, 20));
    expect(complete, hasLength(29));
  });
  test(
    'queue obeys inclusive end, passed time, global limit and platform budget',
    () {
      expect(
        planHabitReminders(
          habits: [habit(end: now)],
          checkIns: [],
          now: now,
        ),
        hasLength(1),
      );
      expect(
        planHabitReminders(
          habits: [habit(end: now)],
          checkIns: [],
          now: DateTime(2026, 9, 30, 21),
        ),
        isEmpty,
      );
      final queue = planHabitReminders(
        habits: [
          habit(),
          habit(id: 'other'),
        ],
        checkIns: [],
        now: now,
        budget: 4,
      );
      expect(queue, hasLength(4));
      expect(queue.last.scheduledAt, DateTime(2026, 10, 1, 20));
      expect(
        planHabitReminders(
          habits: [
            habit(),
            habit(id: 'other'),
          ],
          checkIns: [],
          now: now,
        ),
        hasLength(30),
      );
      expect(
        planHabitReminders(
          habits: [habit()],
          checkIns: [],
          now: now,
          budget: 0,
        ),
        isEmpty,
      );
    },
  );
  test(
    'replacement cancels completed reminders and reports denied/unsupported',
    () async {
      final scheduler = _Scheduler();
      final repo = LocalNotificationRepository(
        scheduler,
        () => const NotificationCopy.english(),
      );
      expect(
        await repo.syncHabitNotifications(
          habits: [habit(end: now)],
          checkIns: [],
          now: now,
        ),
        HabitReminderStatus.available,
      );
      expect(scheduler.scheduled, hasLength(1));
      await repo.syncHabitNotifications(
        habits: [habit(end: now)],
        checkIns: [check('1'), check('2')],
        now: now,
      );
      expect(scheduler.scheduled, isEmpty);
      scheduler.permission = false;
      expect(
        await repo.syncHabitNotifications(
          habits: [habit()],
          checkIns: [],
          now: now,
        ),
        HabitReminderStatus.denied,
      );
      scheduler.supported = false;
      expect(
        await repo.syncHabitNotifications(
          habits: [habit()],
          checkIns: [],
          now: now,
        ),
        HabitReminderStatus.unsupported,
      );
    },
  );
  test(
    'an in-flight old schedule cannot restore reminders after completion',
    () async {
      final scheduler = _Scheduler()..gate = Completer<void>();
      final repo = LocalNotificationRepository(
        scheduler,
        () => const NotificationCopy.english(),
      );
      final first = repo.syncHabitNotifications(
        habits: [habit(end: now)],
        checkIns: [],
        now: now,
      );
      await scheduler.started.future;
      final latest = repo.syncHabitNotifications(
        habits: [habit(end: now)],
        checkIns: [check('1'), check('2')],
        now: now,
      );
      scheduler.gate!.complete();
      await first;
      await latest;
      expect(scheduler.scheduled, isEmpty);
    },
  );
  test('other notification changes recompute the shared capacity', () async {
    final scheduler = _Scheduler();
    final repository = LocalNotificationRepository(
      scheduler,
      () => const NotificationCopy.english(),
      clock: FixedClock(now),
    );
    await repository.syncHabitNotifications(
      habits: [habit()],
      checkIns: [],
      now: now,
    );
    expect(scheduler.scheduled, hasLength(30));
    scheduler.budget = 3;
    await repository.syncTaskStartNotifications(tasks: [], now: now);
    expect(scheduler.scheduled, hasLength(3));
  });
  test(
    'platform error becomes a retryable status rather than throwing',
    () async {
      final scheduler = _Scheduler()..fail = true;
      final repo = LocalNotificationRepository(
        scheduler,
        () => const NotificationCopy.english(),
      );
      expect(
        await repo.syncHabitNotifications(
          habits: [habit()],
          checkIns: [],
          now: now,
        ),
        HabitReminderStatus.failed,
      );
      scheduler.fail = false;
      expect(
        await repo.syncHabitNotifications(
          habits: [habit(end: now)],
          checkIns: [],
          now: now,
        ),
        HabitReminderStatus.available,
      );
    },
  );
}

class _Scheduler extends NotificationScheduler {
  bool permission = true, supported = true, fail = false;
  int budget = 30;
  @override
  Future<Set<String>> pendingTaskStartTaskIds() async => {};
  final scheduled = <int, DateTime>{};
  Completer<void>? gate;
  final started = Completer<void>();
  @override
  bool get supportsHabitReminders => supported;
  @override
  Future<bool> requestHabitPermission() async => permission;
  @override
  Future<int> habitNotificationBudget() async => budget;
  @override
  Future<void> cancelHabitNotifications() async {
    scheduled.clear();
  }

  @override
  Future<void> scheduleHabitReminder({
    required int id,
    required String habitId,
    required DateTime scheduledAt,
    required String title,
    required String body,
  }) async {
    if (!started.isCompleted) started.complete();
    await gate?.future;
    if (fail) throw StateError('scheduler unavailable');
    scheduled[id] = scheduledAt;
  }
}
