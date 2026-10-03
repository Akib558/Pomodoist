import 'dart:ui' show lerpDouble;
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:pomodoist/domain/models/settings/bottom_navigation_preferences.dart';

({bool expands, bool labelsBelow}) bottomNavigationLayout(
  BottomNavigationStyle style,
  int count,
) => (
  expands: count > 0 && (style == BottomNavigationStyle.labels || count >= 4),
  labelsBelow: style == BottomNavigationStyle.labels && count >= 3,
);

/// One animation drives the surface, buttons, labels and sliding accent.
class BottomNavigationFrame {
  BottomNavigationFrame({
    required List<double> widths,
    required List<double> labels,
    this.accentStart = 0,
    this.accentWidth = 0,
    this.accentOpacity = 0,
  }) : widths = List.unmodifiable(widths),
       labels = List.unmodifiable(labels);

  final List<double> widths;
  final List<double> labels;
  final double accentStart;
  final double accentWidth;
  final double accentOpacity;
  double get contentWidth => widths.fold(0, (sum, width) => sum + width);

  @override
  bool operator ==(Object other) =>
      other is BottomNavigationFrame &&
      listEquals(widths, other.widths) &&
      listEquals(labels, other.labels) &&
      accentStart == other.accentStart &&
      accentWidth == other.accentWidth &&
      accentOpacity == other.accentOpacity;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(widths),
    Object.hashAll(labels),
    accentStart,
    accentWidth,
    accentOpacity,
  );
}

class BottomNavigationTween extends Tween<BottomNavigationFrame> {
  BottomNavigationTween({super.begin, required BottomNavigationFrame end})
    : super(end: end);

  @override
  BottomNavigationFrame lerp(double t) {
    final from = begin ?? end!;
    final to = end!;
    return BottomNavigationFrame(
      widths: List.generate(
        to.widths.length,
        (i) => lerpDouble(from.widths[i], to.widths[i], t)!,
      ),
      labels: List.generate(
        to.labels.length,
        (i) => lerpDouble(from.labels[i], to.labels[i], t)!,
      ),
      accentStart: lerpDouble(from.accentStart, to.accentStart, t)!,
      accentWidth: lerpDouble(from.accentWidth, to.accentWidth, t)!,
      accentOpacity: lerpDouble(from.accentOpacity, to.accentOpacity, t)!,
    );
  }
}
