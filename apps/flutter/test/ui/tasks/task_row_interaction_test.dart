import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/tasks/widgets/task_branch_widgets.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('mobile actions use long press and reserve no leading margin', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(usesTouchTaskInteraction, isTrue);
      expect(taskBranchGutterWidth, 0);
    }
  });

  test('desktop keeps pointer actions and the external disclosure margin', () {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(usesTouchTaskInteraction, isFalse);
      expect(taskBranchGutterWidth, 24);
    }
  });
}
