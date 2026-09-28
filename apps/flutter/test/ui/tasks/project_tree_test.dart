import 'package:flutter/widgets.dart';
import 'package:pomodoist/ui/tasks/widgets/project_diagram.dart';
import 'package:pomodoist/ui/tasks/widgets/project_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/tasks/project_hierarchy.dart';
import 'package:pomodoist/ui/tasks/view_models/project_tree_data.dart';
import 'package:pomodoist/ui/tasks/view_models/project_tree_layout.dart';
import '../../../testing/models/task_fixtures.dart';

void main() {
  final projects = [
    buildProject(id: 'root'),
    buildProject(id: 'child', parentId: 'root'),
    buildProject(id: 'deep', parentId: 'child'),
    buildProject(id: 'empty', parentId: 'root'),
    buildProject(id: 'archive', parentId: 'root', isArchived: true),
  ];
  final tasks = [
    buildTask(id: 'own', projectId: 'root'),
    buildTask(id: 'a', projectId: 'child'),
    buildTask(id: 'b', projectId: 'child', parentId: 'a', status: 'completed'),
    buildTask(id: 'c', projectId: 'child', parentId: 'b'),
    buildTask(id: 'hidden', projectId: 'archive'),
    buildTask(id: 'orphan', projectId: 'deep', parentId: 'missing'),
  ];
  ProjectTreeData data({
    bool completed = false,
    Map<String, bool> expansion = const {},
  }) => projectTreeData(
    'root',
    projects,
    tasks,
    showCompleted: completed,
    expansion: expansion,
  );

  test(
    'projects, own tasks and descendants have one owner; progress ignores filters',
    () {
      final tree = data();
      expect(
        tree.nodes.keys,
        containsAll(['p:root', 'p:child', 'p:empty', 't:own']),
      );
      expect(tree.nodes.containsKey('p:archive'), false);
      expect(tree.nodes.containsKey('t:hidden'), false);
      expect(tree.nodes.containsKey('t:b'), false);
      expect(tree.nodes['t:c']!.parentKey, 'p:child');
      expect(tree.nodes['t:orphan']!.parentKey, 'p:deep');
      expect(tree.nodes['p:root']!.progress.total, 5);
      expect(tree.nodes['p:root']!.progress.completed, 1);
      expect(data(completed: true).nodes['t:c']!.parentKey, 't:b');
    },
  );
  test(
    'expansion is shared, defaults open through first level and keeps empty projects',
    () {
      final tree = data();
      expect(
        tree.visibleKeys,
        containsAll(['p:root', 'p:child', 'p:deep', 'p:empty', 't:a']),
      );
      expect(tree.visibleKeys, isNot(contains('t:orphan')));
      final open = data(expansion: {'p:deep': true});
      expect(open.visibleKeys, contains('t:orphan'));
      final closed = data(expansion: {'p:child': false});
      expect(closed.visibleKeys, isNot(contains('t:a')));
      expect(closed.nodes['p:root']!.progress.total, 5);
    },
  );
  test('task cycles remain reachable without duplicated nodes', () {
    final tree = projectTreeData(
      'root',
      projects,
      [
        buildTask(id: 'x', projectId: 'root', parentId: 'y'),
        buildTask(id: 'y', projectId: 'root', parentId: 'x'),
      ],
      expansion: {'t:x': true, 't:y': true},
    );
    expect(tree.visibleKeys.where((k) => k.startsWith('t:')).toSet(), {
      't:x',
      't:y',
    });
  });
  test(
    'drop targets distinguish task/project parents, reject cycles and read-only targets',
    () {
      final tree = data(completed: true, expansion: {'t:a': true});
      expect(
        projectDiagramDrop(tree, 't:a', 't:b', ProjectDropPosition.inside),
        isNull,
      );
      expect(
        projectDiagramDrop(
          tree,
          'p:child',
          'p:deep',
          ProjectDropPosition.inside,
        ),
        isNull,
      );
      expect(
        projectDiagramDrop(
          tree,
          'p:child',
          't:own',
          ProjectDropPosition.inside,
        ),
        isNull,
      );
      final target = projectDiagramDrop(
        tree,
        't:a',
        'p:empty',
        ProjectDropPosition.inside,
      )!;
      expect(target.projectId, 'empty');
      expect(target.parentId, isNull);
      final restricted = projectTreeData(
        'root',
        [
          buildProject(id: 'root'),
          buildProject(id: 'locked', parentId: 'root', canEdit: false),
        ],
        [buildTask(id: 'own', projectId: 'root')],
      );
      expect(
        projectDiagramDrop(
          restricted,
          't:own',
          'p:locked',
          ProjectDropPosition.inside,
        ),
        isNull,
      );
    },
  );
  test('entering an invalid edge can still reach a valid inside drop', () {
    final tree = data();
    expect(
      projectDiagramDrop(tree, 't:own', 'p:child', ProjectDropPosition.before),
      isNull,
    );
    expect(canEnterProjectDiagramDrop(tree, 't:own', 'p:child'), true);
  });
  test('reordering promoted tasks preserves their real completed parent', () {
    final tree = data();
    final target = projectDiagramDrop(
      tree,
      't:own',
      't:c',
      ProjectDropPosition.before,
    )!;
    expect(target.projectId, 'child');
    expect(target.parentId, 'b');
    expect(target.beforeId, 'c');
  });
  test('read-only shared roots retain personal-hierarchy movement only', () {
    final tree = projectTreeData('root', [
      buildProject(id: 'root'),
      buildProject(
        id: 'shared',
        parentId: 'root',
        scopeId: 'scope',
        canEdit: false,
      ),
      buildProject(
        id: 'inside',
        parentId: 'shared',
        scopeId: 'scope',
        canEdit: false,
      ),
      buildProject(id: 'other', parentId: 'root'),
    ], []);
    expect(canMoveProjectDiagramNode(tree, 'p:shared'), true);
    expect(canMoveProjectDiagramNode(tree, 'p:inside'), false);
    expect(canMoveProjectDiagramNode(tree, 'p:root'), false);
    expect(
      projectDiagramDrop(
        tree,
        'p:shared',
        'p:other',
        ProjectDropPosition.inside,
      ),
      isNotNull,
    );
  });
  test('card measurements grow for long titles and accessibility text scale', () {
    const title =
        'A long localized project title with nested tasks and more context to display';
    final normal = projectDiagramNodeSize(
      'Short',
      const TextStyle(fontSize: 14),
      TextScaler.noScaling,
      TextDirection.ltr,
    );
    final large = projectDiagramNodeSize(
      title,
      const TextStyle(fontSize: 14),
      TextScaler.linear(2),
      TextDirection.rtl,
    );
    expect(large.height, greaterThan(normal.height));
    expect(large.width, greaterThan(normal.width));
    expect(const ProjectScreen(projectId: 'root').projectId, 'root');
  });
  test(
    'map layout uses measured sizes, has no overlaps and mirrors in RTL',
    () {
      final tree = data(
        completed: true,
        expansion: {'p:deep': true, 't:a': true, 't:b': true},
      );
      final sizes = {
        for (final key in tree.visibleKeys)
          key: Size(380, key == 't:a' ? 220 : 120),
      };
      final layout = layoutProjectTree(tree, sizes);
      final rtl = layoutProjectTree(tree, sizes, rtl: true);
      final entries = layout.rects.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        expect(entries[i].value.size, sizes[entries[i].key]);
        expect(
          rtl.rects[entries[i].key]!.left,
          closeTo(layout.size.width - entries[i].value.right, .01),
        );
        for (var j = i + 1; j < entries.length; j++) {
          expect(
            entries[i].value.overlaps(entries[j].value),
            false,
            reason: '${entries[i].key} / ${entries[j].key}',
          );
        }
      }
    },
  );
}
