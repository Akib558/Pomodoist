import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/repositories/focus/focus_repository.dart';
import 'package:pomodoist/domain/models/focus/focus_models.dart';
import 'package:pomodoist/ui/tasks/view_models/task_detail_view_model.dart';
import 'package:pomodoist/utils/result.dart';

void main() {
  final now = DateTime.utc(2026, 9, 28);
  final run = FocusRunItem(
    id: 'run',
    userId: 'user',
    taskId: 'task',
    presetId: 'preset',
    status: 'active',
    startedAt: now,
    targetWorkIntervals: 1,
    completedWorkIntervals: 0,
    createdAt: now,
    updatedAt: now,
  );

  FocusIntervalItem interval(String status, {String runId = 'run'}) =>
      FocusIntervalItem(
        id: 'interval',
        runId: runId,
        type: 'work',
        status: status,
        plannedSeconds: 1500,
        startedAt: now,
        pausedTotalSeconds: 0,
        sequenceNumber: 1,
        createdAt: now,
        updatedAt: now,
      );

  test('task detail action follows its own active interval', () {
    expect(
      taskDetailFocusAction(taskId: 'task', run: null, interval: null),
      TaskDetailFocusAction.startFocus,
    );
    expect(
      taskDetailFocusAction(
        taskId: 'other',
        run: run,
        interval: interval('running'),
      ),
      TaskDetailFocusAction.startFocus,
    );
    expect(
      taskDetailFocusAction(
        taskId: 'task',
        run: run,
        interval: interval('running'),
      ),
      TaskDetailFocusAction.pause,
    );
    expect(
      taskDetailFocusAction(
        taskId: 'task',
        run: run,
        interval: interval('paused'),
      ),
      TaskDetailFocusAction.resume,
    );
    expect(
      taskDetailFocusAction(
        taskId: 'task',
        run: run,
        interval: interval('ready'),
      ),
      TaskDetailFocusAction.startInterval,
    );
  });

  test('pause restriction and mismatched streams never pause another run', () {
    expect(
      taskDetailFocusAction(
        taskId: 'task',
        run: run,
        interval: interval('running'),
        allowPause: false,
      ),
      TaskDetailFocusAction.pauseUnavailable,
    );
    expect(
      taskDetailFocusAction(
        taskId: 'task',
        run: run,
        interval: interval('paused'),
        allowPause: false,
      ),
      TaskDetailFocusAction.resume,
    );
    expect(
      taskDetailFocusAction(
        taskId: 'task',
        run: run,
        interval: interval('running', runId: 'previous'),
      ),
      isNull,
    );
  });

  test('detail actions call only the matching interval operation', () async {
    final repository = _FocusRepository(run, interval('running'));
    expect(
      await performTaskDetailFocusAction(
        repository,
        taskId: 'task',
        runId: 'run',
        action: TaskDetailFocusAction.pause,
      ),
      isTrue,
    );
    expect(repository.pauseCount, 1);

    repository.interval = interval('paused');
    expect(
      await performTaskDetailFocusAction(
        repository,
        taskId: 'task',
        runId: 'run',
        action: TaskDetailFocusAction.resume,
      ),
      isTrue,
    );
    expect(repository.resumeCount, 1);

    repository.interval = interval('ready');
    expect(
      await performTaskDetailFocusAction(
        repository,
        taskId: 'task',
        runId: 'run',
        action: TaskDetailFocusAction.startInterval,
      ),
      isTrue,
    );
    expect(repository.startCount, 1);
  });

  test('stale detail actions do not change the active session', () async {
    final repository = _FocusRepository(run, interval('running'));
    expect(
      await performTaskDetailFocusAction(
        repository,
        taskId: 'task',
        runId: 'old-run',
        action: TaskDetailFocusAction.pause,
      ),
      isFalse,
    );
    expect(
      await performTaskDetailFocusAction(
        repository,
        taskId: 'task',
        runId: 'run',
        action: TaskDetailFocusAction.resume,
      ),
      isFalse,
    );
    expect(repository.pauseCount, 0);
    expect(repository.resumeCount, 0);
  });
}

class _FocusRepository implements FocusRepository {
  _FocusRepository(this.run, this.interval);

  FocusRunItem? run;
  FocusIntervalItem? interval;
  int pauseCount = 0;
  int resumeCount = 0;
  int startCount = 0;

  @override
  Stream<FocusRunItem?> watchActiveRun() => Stream.value(run);

  @override
  Stream<FocusIntervalItem?> watchActiveInterval() => Stream.value(interval);

  @override
  Future<Result<void>> pauseActiveInterval({DateTime? now}) =>
      Result.capture<void>(() async {
        pauseCount++;
      });

  @override
  Future<Result<void>> resumeActiveInterval({DateTime? now}) =>
      Result.capture<void>(() async {
        resumeCount++;
      });

  @override
  Future<Result<void>> startReadyInterval() => Result.capture<void>(() async {
    startCount++;
  });

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
