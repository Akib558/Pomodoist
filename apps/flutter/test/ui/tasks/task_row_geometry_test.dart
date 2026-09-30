import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/ui/tasks/widgets/task_row_geometry.dart';

void main() {
  test('row densities use distinct vertical padding', () {
    expect(TaskRowGeometry.verticalPadding(TaskRowSpacing.compact), 0);
    expect(TaskRowGeometry.verticalPadding(TaskRowSpacing.comfortable), 8);
    expect(TaskRowGeometry.verticalPadding(TaskRowSpacing.spacious), 20);
  });

  test('only compact caps existing text block gaps without adding space', () {
    for (final gap in [0.0, 1.0, 2.0, 4.0, 6.0]) {
      expect(
        TaskRowGeometry.blockGap(TaskRowSpacing.compact, gap),
        gap > 2 ? 2 : gap,
      );
      for (final spacing in [
        TaskRowSpacing.comfortable,
        TaskRowSpacing.spacious,
      ]) {
        expect(TaskRowGeometry.blockGap(spacing, gap), gap);
      }
    }
  });

  test(
    'mobile spacing changes blocks without moving controls off their anchor',
    () {
      for (final spacing in TaskRowSpacing.values) {
        final padding = TaskRowGeometry.verticalPadding(spacing);
        final gap = TaskRowGeometry.mobileBlockGap(spacing);
        expect(gap, [0, 2, 4][spacing.index]);
        for (final scale in [1.0, 1.3, 2.0, 3.0]) {
          final geometry = TaskRowGeometry(titleLineHeight: 24 * scale);
          expect(
            padding + geometry.titleInset + geometry.titleLineHeight / 2,
            padding + geometry.controlInset + TaskRowGeometry.controlSize / 2,
          );
          expect(padding + geometry.anchor, greaterThanOrEqualTo(22));
        }
      }
    },
  );

  test('branch arms meet the outer completion stroke in both directions', () {
    final radius =
        TaskRowGeometry.completionRadius(TaskRowGeometry.completionSize) +
        TaskRowGeometry.completionStrokeWidth / 2;
    expect(TaskRowGeometry.branchArm, 16.75);
    for (final direction in [1.0, -1.0]) {
      const rail = 60.0;
      final circleCenter = rail + direction * 28;
      final endpoint = rail + direction * TaskRowGeometry.branchArm;
      expect(endpoint, circleCenter - direction * radius);
      expect((endpoint - circleCenter).abs(), radius);
    }
  });

  test(
    'controls and the first title line share an anchor at every text scale',
    () {
      for (final scale in [1.0, 1.3, 2.0, 3.0]) {
        final geometry = TaskRowGeometry(titleLineHeight: 24 * scale);
        expect(
          geometry.titleInset + geometry.titleLineHeight / 2,
          geometry.anchor,
        );
        expect(
          geometry.controlInset + TaskRowGeometry.controlSize / 2,
          geometry.anchor,
        );
      }
    },
  );
}
