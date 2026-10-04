import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/tasks/widgets/task_list_item.dart';
import '../upcoming_screen_test.dart' show pumpUpcomingForTest;
import '../support/test_app.dart';
import 'task_performance_test.dart' show CountedTask, now;

void main() {
  setUpAll(loadTestAppResources);
  final metrics = <String, Object?>{};
  tearDownAll(() {
    final path = Platform.environment['PERFORMANCE_WIDGET_OUTPUT'];
    if (path != null) {
      File(
        path,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(metrics));
    }
  });
  for (final n in [40, 1000]) {
    for (final spread in [false, true]) {
      testWidgets('agenda $n spread=$spread automated mount and scroll', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final tasks = List.generate(
          n,
          (i) =>
              CountedTask('$i', day: now.add(Duration(days: spread ? i : 0))),
        );
        var builds = 0;
        final previous = debugOnRebuildDirtyWidget;
        debugOnRebuildDirtyWidget = (element, built) {
          previous?.call(element, built);
          if (element.widget is TaskListItem) builds++;
        };
        addTearDown(() => debugOnRebuildDirtyWidget = previous);
        await pumpUpcomingForTest(tester, today: now, tasks: tasks);
        final mounted = find.byType(TaskListItem).evaluate().length;
        final initialBuilds = builds;
        final scrollable = find
            .descendant(
              of: find.byKey(const ValueKey('upcoming-scroll-view')),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('${n - 1}')),
          600,
          scrollable: scrollable,
          maxScrolls: 400,
        );
        await tester.pumpAndSettle();
        expect(find.text('${n - 1}'), findsOneWidget);
        metrics['agenda_${n}_$spread'] = {
          'initial_mounted': mounted,
          'initial_builds': initialBuilds,
          'scroll_builds': builds - initialBuilds,
          'final_mounted': find.byType(TaskListItem).evaluate().length,
        };
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('one title changes only its card', (tester) async {
    final stream = StreamController<List<TaskItem>>();
    addTearDown(stream.close);
    final tasks = List.generate(40, (i) => CountedTask('$i'));
    await pumpUpcomingForTest(
      tester,
      today: now,
      tasks: tasks,
      allStream: stream.stream,
      settle: false,
    );
    stream.add(tasks);
    await tester.pumpAndSettle();
    final rebuilt = <String>[];
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, built) {
      previous?.call(element, built);
      if (element.widget case TaskListItem(:final task)) rebuilt.add(task.id);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    final first = tasks.first;
    stream.add([
      TaskItem(
        id: first.id,
        userId: first.userId,
        content: 'Changed title',
        projectId: first.projectId,
        priority: first.priority,
        dueJson: first.dueJson,
        status: first.status,
        completedFocusIntervals: 0,
        totalFocusSeconds: 0,
        orderKey: first.orderKey,
        isDeleted: false,
        createdAt: first.createdAt,
        updatedAt: first.updatedAt,
      ),
      ...tasks.skip(1),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Changed title'), findsOneWidget);
    metrics['one_title'] = {
      'rebuilt_ids': rebuilt,
      'other_builds': rebuilt.where((id) => id != '0').length,
    };
  });
}
