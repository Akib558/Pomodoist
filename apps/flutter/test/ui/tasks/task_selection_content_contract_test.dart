import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selection panels cannot replace the mounted task content', () {
    final unit = parseString(
      content: File(
        'lib/ui/tasks/widgets/task_selection_region.dart',
      ).readAsStringSync(),
    ).unit;
    final state = unit.declarations.whereType<ClassDeclaration>().singleWhere(
      (node) => node.namePart.typeName.lexeme == '_TaskSelectionRegionState',
    );
    final build = state.body.childEntities
        .whereType<MethodDeclaration>()
        .singleWhere((node) => node.name.lexeme == 'build');
    final column = _calls(build.body, 'Column').single;
    final children = _namedArgument(column, 'children') as ListLiteral;
    final content = children.elements
        .whereType<Expression>()
        .map((node) => _arguments(node, 'KeyedSubtree'))
        .whereType<ArgumentList>()
        .toList();

    // A key on the scroll view alone cannot survive an unkeyed parent being
    // removed when both selection panels are inserted into the Column.
    expect(
      content,
      hasLength(1),
      reason: 'Task content needs an unconditional keyed child of the Column.',
    );
    final key = _namedArgument(content.single, 'key');
    expect(key, isA<InstanceCreationExpression>());
    final constantKey = key as InstanceCreationExpression;
    expect(constantKey.isConst, isTrue);
    expect(
      constantKey.constructorName.type.name.lexeme,
      anyOf('Key', 'ValueKey'),
    );
    expect(constantKey.argumentList.arguments.single, isA<StringLiteral>());

    final layout = _namedArgument(content.single, 'child');
    expect(layout, isA<ConditionalExpression>());
    final branches = layout as ConditionalExpression;
    expect(branches.condition.toSource(), 'widget.shrinkWrap');
    expect(branches.thenExpression.toSource(), 'widget.child');
    final expanded = _arguments(branches.elseExpression, 'Expanded');
    expect(expanded, isNotNull);
    expect(_namedArgument(expanded!, 'child').toSource(), 'widget.child');
  });
}

Expression _namedArgument(ArgumentList arguments, String name) => arguments
    .arguments
    .whereType<NamedExpression>()
    .singleWhere((argument) => argument.name.label.name == name)
    .expression;

ArgumentList? _arguments(AstNode node, String name) => switch (node) {
  InstanceCreationExpression()
      when node.constructorName.type.name.lexeme == name =>
    node.argumentList,
  MethodInvocation() when node.methodName.name == name => node.argumentList,
  _ => null,
};

Iterable<ArgumentList> _calls(AstNode node, String name) sync* {
  final arguments = _arguments(node, name);
  if (arguments != null) yield arguments;
  for (final child in node.childEntities.whereType<AstNode>()) {
    yield* _calls(child, name);
  }
}
