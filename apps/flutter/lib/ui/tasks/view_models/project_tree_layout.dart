import 'dart:math' as math;
import 'dart:ui';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'project_tree_data.dart';

class ProjectTreeLayout {
  const ProjectTreeLayout(
    this.size,
    this.rects,
    this.edges, {
    this.ownTasksHeader,
  });
  final Size size;
  final Map<String, Rect> rects;
  final List<(String, String)> edges;
  final Rect? ownTasksHeader;
}

ProjectTreeLayout layoutProjectTree(
  ProjectTreeData tree,
  ProjectViewMode mode,
  Map<String, Size> sizes, {
  bool rtl = false,
}) {
  const gap = 28.0, levelGap = 64.0;
  final rects = <String, Rect>{};
  final edges = <(String, String)>[];
  Rect? ownHeader;
  if (!tree.nodes.containsKey(tree.rootKey))
    return const ProjectTreeLayout(Size.zero, {}, []);
  if (mode == ProjectViewMode.map) {
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
  } else {
    final roots = tree.visibleChildren(tree.rootKey);
    final columns = <List<String>>[
      for (final key in roots.where((k) => tree.nodes[k]!.project != null))
        [key],
      if (roots.any((k) => tree.nodes[k]!.task != null))
        roots.where((k) => tree.nodes[k]!.task != null).toList(),
    ];
    var x = gap;
    final rootSize = sizes[tree.rootKey]!;
    for (final roots in columns) {
      final own = tree.nodes[roots.first]!.task != null;
      var y = gap + rootSize.height + levelGap;
      var columnWidth = 0.0;
      if (own) {
        ownHeader = Rect.fromLTWH(x, y, sizes[roots.first]!.width, 44);
        y += 56;
      }
      final stack = [for (final key in roots.reversed) (key, 0)];
      while (stack.isNotEmpty) {
        final (key, depth) = stack.removeLast();
        final size = sizes[key]!;
        final indent = depth * 24.0;
        rects[key] = Rect.fromLTWH(x + indent, y, size.width, size.height);
        columnWidth = math.max(columnWidth, indent + size.width);
        y += size.height + gap;
        final parent = tree.nodes[key]!.parentKey;
        if (parent != null) edges.add((parent, key));
        for (final child in tree.visibleChildren(key).reversed) {
          stack.add((child, depth + 1));
        }
      }
      x += columnWidth + gap;
    }
    rects[tree.rootKey] = Rect.fromLTWH(
      math.max(gap, (x - rootSize.width) / 2),
      gap,
      rootSize.width,
      rootSize.height,
    );
  }
  final width = rects.values.fold(0.0, (v, r) => math.max(v, r.right)) + gap;
  final height = rects.values.fold(0.0, (v, r) => math.max(v, r.bottom)) + gap;
  Rect mirror(Rect r) =>
      Rect.fromLTWH(width - r.right, r.top, r.width, r.height);
  return ProjectTreeLayout(
    Size(width, height),
    {
      for (final entry in rects.entries)
        entry.key: rtl ? mirror(entry.value) : entry.value,
    },
    edges,
    ownTasksHeader: ownHeader == null
        ? null
        : rtl
        ? mirror(ownHeader)
        : ownHeader,
  );
}
