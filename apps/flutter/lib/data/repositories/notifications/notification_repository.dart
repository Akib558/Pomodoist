import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/domain/models/notifications/habit_reminder_status.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

/// Domain-facing notification operations. Scheduling copy is resolved by the
/// implementation from an injected localization source; callers pass domain
/// requests only.
abstract interface class NotificationRepository {
  Future<HabitReminderStatus> syncHabitNotifications({
    required List<Habit> habits,
    required List<HabitCheckIn> checkIns,
    required DateTime now,
  });
  Future<void> initialize();
  Future<void> refreshLanguage();
  Future<void> requestPermission();
  Future<void> scheduleFocusIntervalEnd({
    required DateTime expectedEndAt,
    required String intervalType,
  });
  Future<void> cancelFocusIntervalEnd();
  Future<void> syncTaskStartNotifications({
    required List<TaskItem> tasks,
    required DateTime now,
  });
  Future<void> syncReengagementReminder({
    required bool enabled,
    required DateTime now,
    required bool hasProgressToday,
  });
  Future<void> cancelReengagementReminder();
}
