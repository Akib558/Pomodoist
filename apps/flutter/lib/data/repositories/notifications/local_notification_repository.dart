import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/domain/models/notifications/habit_reminder_status.dart';
import 'package:pomodoist/data/repositories/notifications/habit_reminder_plan.dart';
import 'package:pomodoist/data/repositories/notifications/notification_repository.dart';
import 'package:pomodoist/data/services/notifications/notification_scheduler.dart';
import 'package:pomodoist/domain/models/notifications/notification_copy.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/utils/clock.dart';

const _reengagementReminderHour = 20;
const _reengagementReminderMinute = 30;

/// Wraps the platform scheduler and owns the notification policy that used to
/// live in composition: which task-start notifications are desired, when the
/// reengagement reminder fires, and which localized copy is used.
class LocalNotificationRepository implements NotificationRepository {
  LocalNotificationRepository(
    this._scheduler,
    this._copy, {
    Clock clock = const SystemClock(),
  }) : _clock = clock;

  final Clock _clock;

  final NotificationScheduler _scheduler;
  final NotificationCopy Function() _copy;
  Future<void> _habitUpdate = Future<void>.value();
  int _habitRevision = 0;
  ({List<Habit> habits, List<HabitCheckIn> checkIns})? _habitRequest;

  Future<void> _refreshHabitCapacity() async {
    final request = _habitRequest;
    if (request == null) return;
    await syncHabitNotifications(
      habits: request.habits,
      checkIns: request.checkIns,
      now: _clock.now(),
    );
  }

  Future<void> _reengagementUpdate = Future<void>.value();
  int _reengagementRevision = 0;

  Future<void> _queueReengagementUpdate(Future<void> Function() update) {
    final previous = _reengagementUpdate;
    final revision = ++_reengagementRevision;
    final current = () async {
      try {
        await previous;
      } catch (_) {
        // A failed update must not prevent the next cancellation or refresh.
      }
      if (revision == _reengagementRevision) {
        await update();
      }
    }();
    _reengagementUpdate = current;
    return current.whenComplete(_refreshHabitCapacity);
  }

  @override
  Future<HabitReminderStatus> syncHabitNotifications({
    required List<Habit> habits,
    required List<HabitCheckIn> checkIns,
    required DateTime now,
  }) {
    _habitRequest = (
      habits: List.unmodifiable(habits),
      checkIns: List.unmodifiable(checkIns),
    );
    final previous = _habitUpdate;
    final revision = ++_habitRevision;
    final update = () async {
      try {
        await previous;
      } catch (_) {}
      if (!_scheduler.supportsHabitReminders) {
        return HabitReminderStatus.unsupported;
      }
      if (revision != _habitRevision) return HabitReminderStatus.available;
      try {
        await _scheduler.cancelHabitNotifications();
        if (!habits.any(
          (h) =>
              !h.isDeleted &&
              h.reminderMinutes != null &&
              !h.isFinishedOn(now.toLocal()),
        )) {
          return HabitReminderStatus.available;
        }
        if (!await _scheduler.requestHabitPermission()) {
          return HabitReminderStatus.denied;
        }
        final queue = planHabitReminders(
          habits: habits,
          checkIns: checkIns,
          now: now,
          budget: await _scheduler.habitNotificationBudget(),
        );
        final copy = _copy();
        for (var i = 0; i < queue.length; i++) {
          if (revision != _habitRevision) break;
          final reminder = queue[i];
          await _scheduler.scheduleHabitReminder(
            id: NotificationScheduler.habitNotificationBaseId + i,
            habitId: reminder.habitId,
            scheduledAt: reminder.scheduledAt,
            title: copy.habitReminderTitle,
            body: reminder.title,
          );
        }
        return HabitReminderStatus.available;
      } catch (_) {
        return HabitReminderStatus.failed;
      }
    }();
    _habitUpdate = update.then((_) {});
    return update;
  }

  @override
  Future<void> initialize() => _scheduler.initialize();

  @override
  Future<void> refreshLanguage() => _scheduler.refreshLanguage();

  @override
  Future<void> requestPermission() =>
      _scheduler.requestNotificationPermissions();

  @override
  Future<void> scheduleFocusIntervalEnd({
    required DateTime expectedEndAt,
    required String intervalType,
  }) {
    return _scheduler
        .scheduleFocusIntervalEnd(
          expectedEndAt: expectedEndAt,
          title: 'pomodoist',
          body: _scheduler.focusCompletedBody(intervalType),
        )
        .whenComplete(_refreshHabitCapacity);
  }

  @override
  Future<void> cancelFocusIntervalEnd() =>
      _scheduler.cancelFocusNotification().whenComplete(_refreshHabitCapacity);

  @override
  Future<void> syncTaskStartNotifications({
    required List<TaskItem> tasks,
    required DateTime now,
  }) async {
    try {
      final desired = <String, TaskItem>{};
      for (final task in tasks) {
        final schedule = task.schedule;
        if (task.isCompleted ||
            task.isDeleted ||
            schedule == null ||
            !schedule.isTimed ||
            !schedule.start!.toLocal().isAfter(now.toLocal())) {
          continue;
        }
        desired[task.id] = task;
      }

      final pending = await _scheduler.pendingTaskStartTaskIds();
      for (final taskId in pending.difference(desired.keys.toSet())) {
        await _scheduler.cancelTaskStart(taskId);
      }
      if (desired.isEmpty) {
        return;
      }

      await _scheduler.requestNotificationPermissions();
      final title = _copy().taskStarting;
      for (final task in desired.values) {
        await _scheduler.scheduleTaskStart(
          taskId: task.id,
          startAt: task.schedule!.start!,
          title: title,
          body: task.content,
        );
      }
    } finally {
      await _refreshHabitCapacity();
    }
  }

  @override
  Future<void> syncReengagementReminder({
    required bool enabled,
    required DateTime now,
    required bool hasProgressToday,
  }) => _queueReengagementUpdate(() async {
    if (!enabled) {
      await _scheduler.cancelReengagementReminder();
      return;
    }

    final copy = _copy();
    await _scheduler.requestNotificationPermissions();
    await _scheduler.scheduleReengagementReminder(
      firstAt: nextReengagementReminderAt(
        now: now,
        hasProgressToday: hasProgressToday,
      ),
      copy: copy,
    );
  });

  @override
  Future<void> cancelReengagementReminder() =>
      _queueReengagementUpdate(_scheduler.cancelReengagementReminder);
}

DateTime nextReengagementReminderAt({
  required DateTime now,
  required bool hasProgressToday,
}) {
  final local = now.toLocal();
  final todayReminder = DateTime(
    local.year,
    local.month,
    local.day,
    _reengagementReminderHour,
    _reengagementReminderMinute,
  );
  if (hasProgressToday || !local.isBefore(todayReminder)) {
    return DateTime(
      local.year,
      local.month,
      local.day + 1,
      _reengagementReminderHour,
      _reengagementReminderMinute,
    );
  }
  return todayReminder;
}
