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
        final geometry = TaskRowGeometry(
          textScale: scale,
          titleLineHeight: 24 * scale,
        );
        expect(
          geometry.titleInset + geometry.titleLineHeight / 2,
          geometry.anchor,
        );
        expect(
          geometry.controlInset + TaskRowGeometry.controlSize / 2,
          geometry.anchor,
        );
        expect(geometry.focusWidth, greaterThanOrEqualTo(44));
        expect(geometry.branchWidth, greaterThanOrEqualTo(44));
      }
    },
  );

  test(
    'phone widths and nesting preserve either a readable project or a separate counter row',
    () {
      for (final width in [320.0, 375.0, 390.0, 430.0]) {
        for (final indent in [0.0, 12.0, 24.0, 28.0, 56.0]) {
          for (final scale in [1.0, 1.5, 2.0]) {
            final geometry = TaskRowGeometry(
              textScale: scale,
              titleLineHeight: 24 * scale,
            );
            final available =
                width - 24 - 4 - TaskRowGeometry.textStart - indent;
            final remaining =
                available - geometry.countersWidth - TaskRowGeometry.gap;
            if (geometry.stackCounters(available)) {
              expect(remaining, lessThan(64 * scale));
            } else {
              expect(remaining, greaterThanOrEqualTo(64 * scale));
            }
          }
        }
      }
    },
  );

  test(
    'metadata slots and title anchors are independent of absent values and extra text lines',
    () {
      const geometry = TaskRowGeometry(textScale: 1, titleLineHeight: 24);
      expect(geometry.stackCounters(200), isFalse);
      expect(geometry.stackCounters(199), isTrue);
      expect(geometry.focusWidth, 56);
      expect(geometry.branchWidth, 72);
      expect(geometry.anchor, 22);
      expect(geometry.titleInset, 10);
    },
  );
}
