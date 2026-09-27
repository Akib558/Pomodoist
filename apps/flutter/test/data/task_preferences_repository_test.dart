import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'package:pomodoist/utils/result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/data/repositories/settings/task_preferences_repository_impl.dart';

void main() {
  test(
    'rapid project mode changes serialize writes and retain the final choice',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = _ControlledPreferences();
      final repository = LocalTaskPreferencesRepository(preferences);
      addTearDown(repository.dispose);
      final first = repository.setProjectViewMode(ProjectViewMode.map);
      await preferences.started.future;
      final second = repository.setProjectViewMode(ProjectViewMode.branches);
      await Future<void>.delayed(Duration.zero);
      expect(preferences.writeCount, 1);
      preferences.release.complete();
      for (final result in await Future.wait([first, second])) {
        result.getOrThrow();
      }
      final restored = LocalTaskPreferencesRepository(preferences);
      addTearDown(restored.dispose);
      (await restored.load()).getOrThrow();
      expect(restored.state.projectViewMode, ProjectViewMode.branches);
    },
  );

  test(
    'project view is global, survives reload, and wins against delayed hydration',
    () async {
      SharedPreferences.setMockInitialValues({
        projectViewModePreferenceKey: 'map',
      });
      final ready = Completer<SharedPreferences?>();
      final preferences = PreferencesService(() => ready.future);
      final repository = LocalTaskPreferencesRepository(preferences);
      addTearDown(repository.dispose);
      expect(repository.state.projectViewMode, ProjectViewMode.list);
      final loading = repository.load();
      final saving = repository.setProjectViewMode(ProjectViewMode.branches);
      ready.complete(await SharedPreferences.getInstance());
      (await loading).getOrThrow();
      (await saving).getOrThrow();
      expect(repository.state.projectViewMode, ProjectViewMode.branches);
      final restored = LocalTaskPreferencesRepository(preferences);
      addTearDown(restored.dispose);
      (await restored.load()).getOrThrow();
      expect(restored.state.projectViewMode, ProjectViewMode.branches);
    },
  );

  test(
    'a late load preserves local edits and loads unrelated saved values',
    () async {
      SharedPreferences.setMockInitialValues({
        taskListStylePreferenceKey: 'classic',
        timelineHourWidthPreferenceKey: 288,
      });
      final ready = Completer<SharedPreferences?>();
      final repository = LocalTaskPreferencesRepository(
        PreferencesService(() => ready.future),
      );
      addTearDown(repository.dispose);
      final loading = repository.load();
      final saving = repository.setListStyle(TaskListStyle.modern);
      ready.complete(await SharedPreferences.getInstance());
      (await loading).getOrThrow();
      (await saving).getOrThrow();
      expect(repository.state.listStyle, TaskListStyle.modern);
      expect(repository.state.hourWidth, 288);
      (await repository.setVisibleHours(60, 120)).getOrThrow();
      (await repository.setVisibleHours(120, 60)).getOrThrow();
      expect(
        repository.state.visibleHours,
        const TimelineVisibleHours(startMinutes: 60, endMinutes: 120),
      );
      (await repository.toggleCollapsedProject('work')).getOrThrow();
      expect(
        () => repository.state.collapsedProjectIds.add('other'),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'branch choices round-trip independently per scope and are immutable',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = PreferencesService(SharedPreferences.getInstance);
      final repository = LocalTaskPreferencesRepository(preferences);
      addTearDown(repository.dispose);
      (await repository.setBranchExpanded(
        'today',
        'parent',
        false,
      )).getOrThrow();
      (await repository.setBranchExpanded(
        'project:work',
        'parent',
        true,
      )).getOrThrow();
      final restored = LocalTaskPreferencesRepository(preferences);
      addTearDown(restored.dispose);
      (await restored.load()).getOrThrow();
      expect(restored.state.branchExpansion, {
        'today': {'parent': false},
        'project:work': {'parent': true},
      });
      expect(
        () => restored.state.branchExpansion['inbox'] = {},
        throwsUnsupportedError,
      );
      expect(
        () => restored.state.branchExpansion['today']!['parent'] = true,
        throwsUnsupportedError,
      );
      expect(
        restored.state.copyWith(hourWidth: 288).branchExpansion,
        restored.state.branchExpansion,
      );
    },
  );

  test(
    'rapid branch writes are ordered and the last toggle survives reload',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = _ControlledPreferences();
      final repository = LocalTaskPreferencesRepository(preferences);
      addTearDown(repository.dispose);
      final first = repository.setBranchExpanded('today', 'parent', false);
      await preferences.started.future;
      final second = repository.setBranchExpanded('today', 'parent', true);
      final third = repository.setBranchExpanded('today', 'parent', false);
      expect(repository.state.branchExpansion['today']!['parent'], false);
      await Future<void>.delayed(Duration.zero);
      expect(preferences.writeCount, 1);
      preferences.release.complete();
      for (final result in await Future.wait([first, second, third])) {
        result.getOrThrow();
      }
      final restored = LocalTaskPreferencesRepository(preferences);
      addTearDown(restored.dispose);
      (await restored.load()).getOrThrow();
      expect(restored.state.branchExpansion['today']!['parent'], false);
      expect(preferences.writeCount, 3);
    },
  );

  test(
    'late load merges individual local branch edits with all saved scopes',
    () async {
      SharedPreferences.setMockInitialValues({
        taskBranchExpansionPreferenceKey: jsonEncode({
          'version': 1,
          'scopes': {
            'today': {'parent': true, 'sibling': false},
            'upcoming': {'parent': true},
          },
        }),
      });
      final ready = Completer<SharedPreferences?>();
      final preferences = PreferencesService(() => ready.future);
      final repository = LocalTaskPreferencesRepository(preferences);
      addTearDown(repository.dispose);
      final loading = repository.load();
      final local = repository.setBranchExpanded('today', 'parent', false);
      final other = repository.setBranchExpanded(
        'details:parent',
        'child',
        true,
      );
      ready.complete(await SharedPreferences.getInstance());
      for (final result in await Future.wait([loading, local, other])) {
        result.getOrThrow();
      }
      final expected = {
        'today': {'parent': false, 'sibling': false},
        'upcoming': {'parent': true},
        'details:parent': {'child': true},
      };
      expect(repository.state.branchExpansion, expected);
      final restored = LocalTaskPreferencesRepository(preferences);
      addTearDown(restored.dispose);
      (await restored.load()).getOrThrow();
      expect(restored.state.branchExpansion, expected);
    },
  );

  test(
    'invalid branch storage safely defaults and invalid entries are skipped',
    () async {
      for (final value in [
        true,
        '{',
        '[]',
        '{"version":2,"scopes":{}}',
        '{"version":1,"scopes":[]}',
      ]) {
        SharedPreferences.setMockInitialValues({
          taskBranchExpansionPreferenceKey: value,
        });
        final repository = LocalTaskPreferencesRepository(
          PreferencesService(SharedPreferences.getInstance),
        );
        addTearDown(repository.dispose);
        (await repository.load()).getOrThrow();
        expect(repository.state.branchExpansion, isEmpty);
      }
      SharedPreferences.setMockInitialValues({
        taskBranchExpansionPreferenceKey: jsonEncode({
          'version': 1,
          'scopes': {
            'today': {'good': false, 'invalid': 'true', '': true},
            'upcoming': 123,
            '': {'parent': true},
          },
        }),
      });
      final repository = LocalTaskPreferencesRepository(
        PreferencesService(SharedPreferences.getInstance),
      );
      addTearDown(repository.dispose);
      (await repository.load()).getOrThrow();
      expect(repository.state.branchExpansion, {
        'today': {'good': false},
      });
    },
  );

  test(
    'failed branch reads retain choices and retry before overwriting storage',
    () async {
      SharedPreferences.setMockInitialValues({
        taskBranchExpansionPreferenceKey: jsonEncode({
          'version': 1,
          'scopes': {
            'upcoming': {'saved': true},
          },
        }),
      });
      var failRead = true;
      final preferences = PreferencesService(() async {
        if (failRead) throw StateError('read failure');
        return SharedPreferences.getInstance();
      });
      final repository = LocalTaskPreferencesRepository(preferences);
      addTearDown(repository.dispose);
      expect(
        await repository.setBranchExpanded('today', 'parent', false),
        isA<Failure<void>>(),
      );
      expect(repository.state.branchExpansion['today']!['parent'], false);
      failRead = false;
      (await repository.setBranchExpanded('inbox', 'other', true)).getOrThrow();
      final restored = LocalTaskPreferencesRepository(preferences);
      addTearDown(restored.dispose);
      (await restored.load()).getOrThrow();
      expect(restored.state.branchExpansion, {
        'upcoming': {'saved': true},
        'today': {'parent': false},
        'inbox': {'other': true},
      });
    },
  );

  test(
    'disposal during hydration cannot overwrite saved branch scopes',
    () async {
      final saved = jsonEncode({
        'version': 1,
        'scopes': {
          'upcoming': {'saved': true},
        },
      });
      SharedPreferences.setMockInitialValues({
        taskBranchExpansionPreferenceKey: saved,
      });
      final ready = Completer<SharedPreferences?>();
      final repository = LocalTaskPreferencesRepository(
        PreferencesService(() => ready.future),
      );
      final saving = repository.setBranchExpanded('today', 'parent', false);
      repository.dispose();
      final preferences = await SharedPreferences.getInstance();
      ready.complete(preferences);
      (await saving).getOrThrow();
      expect(preferences.getString(taskBranchExpansionPreferenceKey), saved);
    },
  );

  test(
    'write failure retains branch choices and does not poison the next save',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = _ControlledPreferences()..failNextWrite = true;
      preferences.release.complete();
      final repository = LocalTaskPreferencesRepository(preferences);
      addTearDown(repository.dispose);
      expect(
        await repository.setBranchExpanded('today', 'parent', false),
        isA<Failure<void>>(),
      );
      expect(repository.state.branchExpansion['today']!['parent'], false);
      (await repository.setBranchExpanded('inbox', 'other', true)).getOrThrow();
      final restored = LocalTaskPreferencesRepository(preferences);
      addTearDown(restored.dispose);
      (await restored.load()).getOrThrow();
      expect(restored.state.branchExpansion, repository.state.branchExpansion);
    },
  );
}

class _ControlledPreferences extends PreferencesService {
  _ControlledPreferences() : super(SharedPreferences.getInstance);
  final started = Completer<void>();
  final release = Completer<void>();
  int writeCount = 0;
  bool failNextWrite = false;

  @override
  Future<Result<void>> write(Map<String, Object?> values) async {
    writeCount++;
    if (!started.isCompleted) started.complete();
    await release.future;
    if (failNextWrite) {
      failNextWrite = false;
      return Result.error(StateError('disk failure'), StackTrace.current);
    }
    return super.write(values);
  }
}
