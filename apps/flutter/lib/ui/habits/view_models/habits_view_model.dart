import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/habit_dependencies.dart';
import 'package:pomodoist/config/habit_notification_dependencies.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/habits/habit_repository.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/notifications/habit_reminder_status.dart';
import 'package:pomodoist/utils/result.dart';

class HabitDayRow {
  const HabitDayRow({
    required this.habit,
    required this.count,
    required this.target,
    required this.canAdd,
    required this.canUndo,
    required this.history,
    this.project,
  });
  final Habit habit;
  final int count, target;
  final bool canAdd, canUndo;
  final ProjectItem? project;
  final List<({DateTime day, int count, int? target})> history;
}

class HabitsViewState {
  const HabitsViewState({
    required this.today,
    required this.selectedDay,
    required this.rows,
    required this.projects,
    required this.reminderStatus,
    required this.planned,
    required this.completed,
    required this.loading,
    required this.finished,
    required this.saving,
    this.loadError = false,
    this.actionError = false,
  });
  final DateTime today, selectedDay;
  final List<HabitDayRow> rows;
  final List<ProjectItem> projects;
  final HabitReminderStatus reminderStatus;
  final int planned, completed;
  final bool loading, finished, saving, loadError, actionError;
  bool get futureDay => selectedDay.isAfter(today);
  DateTime get weekStart => DateTime(
    selectedDay.year,
    selectedDay.month,
    selectedDay.day - selectedDay.weekday + 1,
  );
}

final habitsViewModelProvider =
    NotifierProvider.autoDispose<HabitsViewModel, HabitsViewState>(
      HabitsViewModel.new,
    );

class HabitsViewModel extends Notifier<HabitsViewState> {
  late HabitRepository _repository;
  DateTime? _selected, _lastToday;
  bool _finished = false, _saving = false, _actionError = false;
  @override
  HabitsViewState build() {
    _repository = ref.watch(habitRepositoryProvider);
    ref.listen(habitsProvider, (_, _) => _refresh());
    ref.listen(habitCheckInsProvider, (_, _) => _refresh());
    ref.listen(projectsProvider, (_, _) => _refresh());
    ref.listen(habitReminderStatusProvider, (_, _) => _refresh());
    final timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
    ref.onDispose(timer.cancel);
    return _compute();
  }

  HabitsViewState _compute() {
    final today = habitDate(ref.read(clockProvider).now().toLocal());
    if (_selected == null || _selected == _lastToday) _selected = today;
    _lastToday = today;
    final habits = ref.read(habitsProvider),
        checks = ref.read(habitCheckInsProvider),
        projects = ref.read(projectsProvider);
    final personal = (projects.value ?? const <ProjectItem>[])
        .where((p) => p.scopeId == null && !p.isArchived && !p.isDeleted)
        .toList();
    final byId = {for (final p in personal) p.id: p};
    final scheduled = (habits.value ?? const <Habit>[])
        .where((h) => h.isScheduledOn(_selected!))
        .toList();
    final checkIns = checks.value ?? const <HabitCheckIn>[];
    final counts = <(String, DateTime), int>{};
    for (final check in checkIns) {
      if (!check.isDeleted) {
        final key = (check.habitId, check.day);
        counts.update(key, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final complete = scheduled
        .where(
          (h) =>
              (counts[(h.id, _selected!)] ?? 0) >=
              h.scheduleFor(_selected!)!.targetPerDay,
        )
        .length;
    final visible = (habits.value ?? const <Habit>[]).where(
      (h) =>
          !h.isDeleted &&
          h.isFinishedOn(today) == _finished &&
          (_finished || h.isScheduledOn(_selected!)),
    );
    final rows = visible.map((h) {
      final count = counts[(h.id, _selected!)] ?? 0;
      final target =
          (h.scheduleFor(_selected!) ?? h.scheduleHistory.last).targetPerDay;
      return HabitDayRow(
        habit: h,
        count: math.min(count, target),
        target: target,
        history: List.unmodifiable(
          List.generate(5, (index) {
            final day = DateTime(
              _selected!.year,
              _selected!.month,
              _selected!.day - 4 + index,
            );
            final target = h.isScheduledOn(day)
                ? h.scheduleFor(day)!.targetPerDay
                : null;
            return (
              day: day,
              count: target == null || day.isAfter(today)
                  ? 0
                  : math.min(counts[(h.id, day)] ?? 0, target),
              target: target,
            );
          }),
        ),
        project: byId[h.projectId],
        canAdd:
            !_selected!.isAfter(today) &&
            h.isScheduledOn(_selected!) &&
            count < target,
        canUndo: !_selected!.isAfter(today) && count > 0,
      );
    }).toList();
    return HabitsViewState(
      today: today,
      selectedDay: _selected!,
      rows: List.unmodifiable(rows),
      projects: List.unmodifiable(personal),
      reminderStatus: ref.read(habitReminderStatusProvider),
      planned: scheduled.length,
      completed: complete,
      loading: habits.isLoading || checks.isLoading || projects.isLoading,
      loadError: habits.hasError || checks.hasError || projects.hasError,
      finished: _finished,
      saving: _saving,
      actionError: _actionError,
    );
  }

  void _refresh() {
    if (ref.mounted) state = _compute();
  }

  void selectDay(DateTime day) {
    _selected = habitDate(day);
    _refresh();
  }

  void selectToday() {
    selectDay(ref.read(clockProvider).now().toLocal());
  }

  void moveWeek(int delta) {
    selectDay(
      DateTime(
        state.selectedDay.year,
        state.selectedDay.month,
        state.selectedDay.day + delta * 7,
      ),
    );
  }

  void showFinished(bool value) {
    _finished = value;
    _refresh();
  }

  void retry() {
    ref.invalidate(habitsProvider);
    ref.invalidate(habitCheckInsProvider);
    ref.invalidate(projectsProvider);
  }

  Future<bool> _run(Future<Result<Object?>> Function() operation) async {
    if (_saving) return false;
    _saving = true;
    _actionError = false;
    _refresh();
    try {
      (await operation()).getOrThrow();
      return true;
    } catch (_) {
      _actionError = true;
      return false;
    } finally {
      _saving = false;
      _refresh();
    }
  }

  Future<bool> save({
    String? id,
    required String title,
    required DateTime startDate,
    DateTime? endDate,
    required List<int> weekdays,
    required String target,
    String? projectId,
    int? reminderMinutes,
  }) => _run(() async {
    final draft = HabitDraft(
      title: title,
      startDate: startDate,
      endDate: endDate,
      weekdays: weekdays,
      targetPerDay: int.tryParse(target) ?? 0,
      projectId: projectId,
      reminderMinutes: reminderMinutes,
    );
    final now = ref.read(clockProvider).now();
    if (id == null) return _repository.createHabit(draft, now: now);
    return _repository.updateHabit(id, draft, now: now);
  });
  Future<bool> addCheckIn(String id) {
    final day = state.selectedDay;
    return _run(
      () => _repository.addCheckIn(id, day, now: ref.read(clockProvider).now()),
    );
  }

  Future<bool> undoCheckIn(String id) {
    final day = state.selectedDay;
    return _run(
      () =>
          _repository.undoCheckIn(id, day, now: ref.read(clockProvider).now()),
    );
  }

  Future<bool> deleteHabit(String id) => _run(
    () => _repository.deleteHabit(id, now: ref.read(clockProvider).now()),
  );
  Future<void> retryReminders() =>
      ref.read(habitReminderStatusProvider.notifier).refresh();
}
