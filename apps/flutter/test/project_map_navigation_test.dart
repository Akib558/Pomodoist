import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/routing/project_map_navigation.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';

void main() {
  test('map fullscreen preserves route context and task detail navigation', () {
    for (final path in ['/project/root', '/projects']) {
      final original = Uri.parse('$path?filter=a&filter=b#branch');
      final expanded = projectMapFullscreenUri(original, true);
      expect(isProjectMapFullscreen(expanded), isTrue);
      expect(expanded.path, original.path);
      expect(expanded.queryParametersAll['filter'], ['a', 'b']);
      expect(expanded.fragment, 'branch');

      final details = taskDetailUri(expanded, 'task-1');
      expect(isProjectMapFullscreen(details), isTrue);
      expect(selectedTaskDetailsId(details), 'task-1');
      expect(taskDetailUri(details, null), expanded);
      expect(projectMapFullscreenUri(expanded, false), original);
      expect(isProjectMapFullscreen(original), isFalse);
    }
    for (final location in [
      '/today?mapFullscreen=1',
      '/project?mapFullscreen=1',
      '/projects?tab=labels&mapFullscreen=1',
      '/project/root?mapFullscreen=0',
    ]) {
      expect(isProjectMapFullscreen(Uri.parse(location)), isFalse);
    }
    final plain = Uri.parse('/project/root');
    expect(
      projectMapFullscreenUri(projectMapFullscreenUri(plain, true), false),
      plain,
    );
  });
}
