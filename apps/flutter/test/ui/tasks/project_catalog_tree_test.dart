import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/tasks/project_hierarchy.dart';
import 'package:pomodoist/ui/tasks/view_models/project_tree_data.dart';
import 'package:pomodoist/ui/tasks/view_models/project_tree_layout.dart';
import '../../../testing/models/task_fixtures.dart';

void main() {
  final projects = [
    buildProject(id: inboxProjectId),
    buildProject(id: 'alpha', name: 'Alpha', orderKey: 'a'),
    buildProject(id: 'nested', name: 'Nested', parentId: 'alpha'),
    buildProject(id: 'beta', name: 'Beta', orderKey: 'b'),
    buildProject(id: 'archive', name: 'Archive', isArchived: true),
    buildProject(id: 'archild', parentId: 'alpha', isArchived: true),
    buildProject(id: 'orphan', parentId: 'archive'),
  ];
  final tasks = [
    buildTask(id: 'one', projectId: 'alpha', content: 'Unrelated'),
    buildTask(id: 'two', projectId: 'nested', content: 'Find needle'),
    buildTask(
      id: 'three',
      projectId: 'nested',
      parentId: 'two',
      content: 'Needle child',
    ),
    buildTask(
      id: 'done',
      projectId: 'alpha',
      content: 'Completed needle',
      status: 'completed',
    ),
    buildTask(id: 'archtask', projectId: 'archive'),
    buildTask(id: 'inbox', projectId: inboxProjectId),
  ];
  ProjectTreeData data({
    String search = '',
    bool archive = false,
    bool completed = false,
    Map<String, bool> expansion = const {},
  }) => projectTreeData(
    null,
    projects,
    tasks,
    search: search,
    archivedOnly: archive,
    showCompleted: completed,
    expansion: expansion,
  );

  test(
    'catalog has a virtual root and reachable independent project trees',
    () {
      final tree = data();
      expect(tree.nodes[tree.rootKey]!.isCatalogRoot, true);
      expect(tree.nodes[tree.rootKey]!.project, isNull);
      expect(
        tree.nodes[tree.rootKey]!.children,
        containsAll(['p:alpha', 'p:beta', 'p:orphan']),
      );
      expect(tree.nodes['p:orphan']!.parentKey, tree.rootKey);
      expect(tree.nodes.keys, isNot(contains('p:$inboxProjectId')));
      expect(tree.nodes.keys, isNot(contains('p:archive')));
      expect(tree.nodes[tree.rootKey]!.progress.total, 4);
      expect(tree.nodes[tree.rootKey]!.progress.completed, 1);
      expect(tree.visibleKeys, contains('t:one'));
      expect(tree.visibleKeys, isNot(contains('t:two')));
    },
  );
  test(
    'task search keeps ancestors, reveals paths, and does not persist expansion',
    () {
      final expansion = {'p:alpha': false, 'p:nested': false, 't:two': false};
      final tree = data(search: 'NEEDLE', expansion: expansion);
      expect(tree.nodes.keys.toSet(), {
        tree.rootKey,
        'p:alpha',
        'p:nested',
        't:two',
        't:three',
      });
      expect(tree.visibleKeys.toSet(), tree.nodes.keys.toSet());
      expect(tree.visibleKeys.length, tree.nodes.length);
      expect(tree.nodes[tree.rootKey]!.progress.total, 4);
      expect(
        data(expansion: expansion).visibleKeys,
        isNot(contains('p:nested')),
      );
      expect(data(search: 'needle', completed: true).nodes, contains('t:done'));
      expect(tree.movesEnabled, false);
    },
  );
  test(
    'project match includes contents and empty match keeps an empty root',
    () {
      final tree = data(search: 'ALPHA');
      expect(
        tree.nodes.keys,
        containsAll(['p:alpha', 'p:nested', 't:one', 't:two', 't:three']),
      );
      expect(tree.nodes.keys, isNot(contains('p:beta')));
      expect(data(search: 'not found').nodes.length, 1);
    },
  );
  test('archive promotes filtered parents and disables structural moves', () {
    final tree = data(archive: true);
    expect(tree.nodes[tree.rootKey]!.children.toSet(), {
      'p:archive',
      'p:archild',
    });
    expect(tree.nodes.keys, contains('t:archtask'));
    expect(tree.movesEnabled, false);
    expect(canMoveProjectDiagramNode(tree, 't:archtask'), false);
  });
  test(
    'cycles and missing parents remain reachable without duplicate nodes',
    () {
      final tree = projectTreeData(
        null,
        [
          buildProject(id: 'a', parentId: 'b'),
          buildProject(id: 'b', parentId: 'a'),
          buildProject(id: 'c', parentId: 'missing'),
        ],
        [
          buildTask(id: 'x', projectId: 'a', parentId: 'y'),
          buildTask(id: 'y', projectId: 'a', parentId: 'x'),
        ],
        search: '',
      );
      expect(tree.nodes.keys, containsAll(['p:a', 'p:b', 'p:c', 't:x', 't:y']));
      expect(tree.visibleKeys.length, tree.visibleKeys.toSet().length);
    },
  );
  test(
    'only project moves can target catalog root; root sibling reorder works',
    () {
      final tree = data();
      expect(
        projectDiagramDrop(
          tree,
          'p:nested',
          tree.rootKey,
          ProjectDropPosition.inside,
        )!.parentId,
        isNull,
      );
      expect(
        projectDiagramDrop(
          tree,
          't:one',
          tree.rootKey,
          ProjectDropPosition.inside,
        ),
        isNull,
      );
      expect(
        projectDiagramDrop(
          tree,
          'p:beta',
          'p:alpha',
          ProjectDropPosition.before,
        )!.beforeId,
        'alpha',
      );
      expect(
        projectDiagramDrop(
          data(search: 'Alpha'),
          'p:nested',
          'p:alpha',
          ProjectDropPosition.inside,
        ),
        isNull,
      );
      expect(canMoveProjectDiagramNode(tree, tree.rootKey), false);
    },
  );
  test(
    'project matches retain descendants even when an earlier task also matches',
    () {
      final tree = projectTreeData(
        null,
        [buildProject(id: 'p', name: 'Match')],
        [
          buildTask(id: 'a', projectId: 'p', content: 'Match'),
          buildTask(id: 'b', projectId: 'p', parentId: 'a', content: 'Other'),
          buildTask(id: 'c', projectId: 'p', parentId: 'b', content: 'Other'),
        ],
        search: 'match',
      );
      expect(tree.nodes.keys, containsAll(['t:a', 't:b', 't:c']));
    },
  );
  test(
    'shared roots may move as personal links but shared descendants cannot escape',
    () {
      final tree = projectTreeData(null, [
        buildProject(id: 'personal'),
        buildProject(id: 'shared', scopeId: 's', canEdit: false),
        buildProject(id: 'shared-child', parentId: 'shared', scopeId: 's'),
        buildProject(id: 'locked', canEdit: false),
      ], []);
      expect(
        projectDiagramDrop(
          tree,
          'p:shared',
          tree.rootKey,
          ProjectDropPosition.inside,
        ),
        isNotNull,
      );
      expect(
        projectDiagramDrop(
          tree,
          'p:shared',
          'p:personal',
          ProjectDropPosition.before,
        ),
        isNotNull,
      );
      expect(
        projectDiagramDrop(
          tree,
          'p:shared-child',
          tree.rootKey,
          ProjectDropPosition.inside,
        ),
        isNull,
      );
      expect(
        projectDiagramDrop(
          tree,
          'p:shared-child',
          'p:personal',
          ProjectDropPosition.before,
        ),
        isNull,
      );
      expect(
        projectDiagramDrop(
          tree,
          'p:locked',
          tree.rootKey,
          ProjectDropPosition.inside,
        ),
        isNull,
      );
    },
  );
  test(
    'an empty catalog and a project without subprojects both have finite layouts',
    () {
      for (final tree in [
        projectTreeData(null, [], []),
        projectTreeData(
          null,
          [buildProject(id: 'p')],
          [buildTask(id: 't', projectId: 'p')],
        ),
      ]) {
        final layout = layoutProjectTree(tree, {
          for (final key in tree.visibleKeys) key: const Size(304, 180),
        });
        expect(layout.size.isFinite, true);
        expect(layout.rects.keys.toSet(), tree.visibleKeys.toSet());
      }
    },
  );
  test(
    'catalog map covers every visible node without overlaps and mirrors RTL',
    () {
      final tree = data(search: 'alpha');
      final sizes = {
        for (final key in tree.visibleKeys)
          key: Size(440, key.length * 20.0 + 150),
      };
      final layout = layoutProjectTree(tree, sizes);
      final rtl = layoutProjectTree(tree, sizes, rtl: true);
      expect(layout.rects.keys.toSet(), tree.visibleKeys.toSet());
      final rects = layout.rects.values.toList();
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), false);
        }
      }
      for (final key in layout.rects.keys) {
        expect(
          rtl.rects[key]!.left,
          closeTo(layout.size.width - layout.rects[key]!.right, .01),
        );
      }
    },
  );
}
