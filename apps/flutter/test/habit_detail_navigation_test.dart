import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/routing/habit_detail_navigation.dart';

void main() {
  test('habit selection preserves the background and closes cleanly', () {
    final background = Uri.parse('/habits?date=2026-10-03&tag=a&tag=b#week');
    final opened = habitDetailUri(background, 'habit / one');
    expect(opened.queryParameters['habit'], 'habit / one');
    expect(opened.queryParametersAll['tag'], ['a', 'b']);
    expect(habitDetailUri(opened, null), background);
    expect(
      habitDetailUri(Uri.parse('/habits?habit=one'), null).toString(),
      '/habits',
    );
  });

  test(
    'new and existing editors replace selection without stacking panels',
    () {
      final taskOpen = Uri.parse('/habits?task=old&date=2026-10-03');
      final create = habitDetailUri(taskOpen, newHabitDetailsId);
      expect(create.queryParameters['habit'], 'new');
      expect(create.queryParameters.containsKey('task'), isFalse);
      final edit = habitDetailUri(create, 'existing');
      expect(edit.queryParametersAll['habit'], ['existing']);
      expect(edit.queryParameters['date'], '2026-10-03');
      expect(habitDetailUri(edit, 'existing'), edit);
    },
  );
}
