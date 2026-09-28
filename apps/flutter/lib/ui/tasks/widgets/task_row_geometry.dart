import 'dart:math' as math;

import 'package:pomodoist/domain/models/settings/task_preferences.dart';

/// Shared measurements for mobile rows, metadata, and branch connectors.
class TaskRowGeometry {
  const TaskRowGeometry({
    required this.textScale,
    required this.titleLineHeight,
  });

  final double textScale;
  final double titleLineHeight;
  static const controlSize = 44.0;
  static const textStart = 48.0;
  static const gap = 4.0;
  static double verticalPadding(TaskRowSpacing spacing) => switch (spacing) {
    TaskRowSpacing.compact => 0,
    TaskRowSpacing.comfortable => 8,
    TaskRowSpacing.spacious => 20,
  };

  static double blockGap(TaskRowSpacing spacing, double normal) =>
      spacing == TaskRowSpacing.compact ? math.min(normal, 2) : normal;

  static const completionSize = 24.0;
  static const completionStrokeWidth = 1.5;
  static double completionRadius(double diameter) =>
      diameter / 2 - completionStrokeWidth;
  static const completionOuterRadius =
      completionSize / 2 - completionStrokeWidth / 2;
  static const branchArm = 28 - completionOuterRadius;

  double get titleInset => math.max(0, (controlSize - titleLineHeight) / 2);
  double get controlInset => math.max(0, (titleLineHeight - controlSize) / 2);
  double get anchor => math.max(controlSize, titleLineHeight) / 2;
  double get focusWidth => math.max(controlSize, 56 * textScale);
  double get branchWidth => math.max(controlSize, 72 * textScale);
  double get countersWidth => focusWidth + branchWidth + gap;
  bool stackCounters(double availableWidth) =>
      availableWidth - countersWidth - gap < 64 * textScale;
}
