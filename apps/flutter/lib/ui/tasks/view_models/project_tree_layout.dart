import 'dart:math' as math;
import 'dart:ui';
import 'project_tree_data.dart';

class ProjectTreeLayout {
  const ProjectTreeLayout(this.size, this.rects, this.edges);
  final Size size;
  final Map<String, Rect> rects;
  final List<(String, String)> edges;
}

ProjectTreeLayout layoutProjectTree(
  ProjectTreeData tree,
  Map<String, Size> sizes, {
  bool rtl = false,
}) {
  const gap = 28.0, levelGap = 64.0;
  final rects = <String, Rect>{};
  final edges = <(String, String)>[];
  if (!tree.nodes.containsKey(tree.rootKey))
    return const ProjectTreeLayout(Size.zero, {}, []);
  final spans = <String, double>{};
  final widths = <int, double>{};
  final depths = <String, int>{tree.rootKey: 0};
  for (final key in tree.visibleKeys) {
    final depth = depths[key]!;
    widths[depth] = math.max(widths[depth] ?? 0, sizes[key]!.width);
    for (final child in tree.visibleChildren(key)) {
      depths[child] = depth + 1;
    }
  }
  for (final key in tree.visibleKeys.reversed) {
    final children = tree.visibleChildren(key);
    final sum =
        children.fold(0.0, (n, c) => n + spans[c]!) +
        math.max(0, children.length - 1) * gap;
    spans[key] = math.max(sizes[key]!.height, sum);
  }
  final xs = <int, double>{0: gap};
  for (var d = 1; d < widths.length; d++) {
    xs[d] = xs[d - 1]! + widths[d - 1]! + levelGap;
  }
  final tops = <String, double>{tree.rootKey: gap};
  for (final key in tree.visibleKeys) {
    rects[key] = Rect.fromLTWH(
      xs[depths[key]]!,
      tops[key]! + (spans[key]! - sizes[key]!.height) / 2,
      sizes[key]!.width,
      sizes[key]!.height,
    );
    var y = tops[key]!;
    for (final child in tree.visibleChildren(key)) {
      tops[child] = y;
      y += spans[child]! + gap;
      edges.add((key, child));
    }
  }
  final width = rects.values.fold(0.0, (v, r) => math.max(v, r.right)) + gap;
  final height = rects.values.fold(0.0, (v, r) => math.max(v, r.bottom)) + gap;
  Rect mirror(Rect r) =>
      Rect.fromLTWH(width - r.right, r.top, r.width, r.height);
  return ProjectTreeLayout(Size(width, height), {
    for (final entry in rects.entries)
      entry.key: rtl ? mirror(entry.value) : entry.value,
  }, edges);
}
