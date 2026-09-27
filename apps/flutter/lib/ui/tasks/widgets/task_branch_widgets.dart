import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/widgets/action_feedback.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_rows.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_view_model.dart';
import 'package:pomodoist/ui/tasks/view_models/task_subtask_progress.dart';

bool get usesTouchTaskInteraction =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Mobile disclosure uses the trailing action slot, not a leading margin.
double get taskBranchGutterWidth => usesTouchTaskInteraction ? 0 : 24;

Future<void> setTaskBranchExpanded(
  BuildContext context,
  WidgetRef ref,
  String scopeKey,
  String taskId,
  bool expanded,
) async {
  try {
    await ref
        .read(taskBranchViewModelProvider(scopeKey).notifier)
        .setExpanded(taskId, expanded);
  } catch (_) {
    if (context.mounted) _saveError(context);
  }
}

Future<void> revealCreatedTaskBranches(
  BuildContext context,
  WidgetRef ref,
  String scopeKey,
  Iterable<String> taskIds,
) async {
  try {
    await ref
        .read(taskBranchViewModelProvider(scopeKey).notifier)
        .revealCreatedTasks(taskIds);
  } catch (_) {
    if (context.mounted) _saveError(context);
  }
}

void _saveError(BuildContext context) => showActionFeedback(
  context,
  message: context.l10n.settingsSaveError,
  icon: LucideIcons.circleAlert,
  sound: ActionFeedbackSound.none,
  haptic: AppHapticCue.none,
);

class TaskParentContext extends StatelessWidget {
  const TaskParentContext({
    required this.task,
    required this.ancestors,
    super.key,
  });
  final TaskItem task;
  final List<TaskItem> ancestors;

  @override
  Widget build(BuildContext context) {
    final parent = ancestors
        .where((item) => item.id == task.parentId)
        .firstOrNull;
    final label = parent == null
        ? context.l10n.taskParentUnavailable
        : context.l10n.taskParentPath(
            ancestors.map((item) => item.content).join(' / '),
          );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.flip(
          flipX: Directionality.of(context) == TextDirection.rtl,
          child: const Icon(LucideIcons.cornerDownRight, size: 12),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.appColors.secondaryText,
            ),
          ),
        ),
      ],
    );
    if (parent == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: content,
      );
    }
    return Tooltip(
      message: label,
      child: TextButton(
        onPressed: () => openTaskDetails(context, parent.id),
        style: TextButton.styleFrom(
          alignment: AlignmentDirectional.centerStart,
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          foregroundColor: context.appColors.secondaryText,
        ),
        child: content,
      ),
    );
  }
}

class TaskBranchProgressButton extends StatefulWidget {
  const TaskBranchProgressButton({
    required this.taskId,
    required this.progress,
    this.expanded,
    this.onToggle,
    this.showProgress = true,
    super.key,
  });
  final String taskId;
  final TaskSubtaskProgress progress;
  final bool? expanded;
  final VoidCallback? onToggle;
  final bool showProgress;

  @override
  State<TaskBranchProgressButton> createState() =>
      _TaskBranchProgressButtonState();
}

class _TaskBranchProgressButtonState extends State<TaskBranchProgressButton> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final action = widget.onToggle == null
        ? l10n.taskOpenFullBranch
        : widget.expanded!
        ? l10n.taskCollapseSubtasks
        : l10n.taskExpandSubtasks;
    final label =
        '$action. ${l10n.taskAllSubtasksProgress(widget.progress.completed, widget.progress.total)}';
    return Semantics(
      expanded: widget.onToggle == null ? null : widget.expanded,
      child: Tooltip(
        message: label,
        child: TextButton(
          key: ValueKey('task-branch-toggle-${widget.taskId}'),
          focusNode: _focus,
          onPressed: () {
            if (widget.onToggle == null) {
              openTaskDetails(context, widget.taskId);
            } else {
              _focus.requestFocus();
              widget.onToggle!();
            }
          },
          style: TextButton.styleFrom(
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            foregroundColor: context.appColors.secondaryText,
            alignment: widget.onToggle == null
                ? AlignmentDirectional.centerStart
                : Alignment.center,
          ),
          child: Semantics(
            label: label,
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.flip(
                  flipX:
                      widget.onToggle != null &&
                      !widget.expanded! &&
                      Directionality.of(context) == TextDirection.rtl,
                  child: Icon(
                    widget.onToggle == null
                        ? LucideIcons.gitBranch
                        : widget.expanded!
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronRight,
                    size: 12,
                  ),
                ),
                if (widget.showProgress) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      widget.progress.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.monoTextStyle.copyWith(fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact cards retain their own activation target and fixed geometry.
class TaskHierarchySummary extends ConsumerWidget {
  const TaskHierarchySummary({
    required this.task,
    this.compact = false,
    super.key,
  });
  final TaskItem task;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(taskHierarchyViewModelProvider);
    final ancestors = hierarchyAncestors(task, data);
    final progress = data.progress[task.id];
    if (task.parentId == null && progress == null) {
      return const SizedBox.shrink();
    }
    if (!compact) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (task.parentId != null)
            TaskParentContext(task: task, ancestors: ancestors),
          if (progress != null)
            TaskBranchProgressButton(taskId: task.id, progress: progress),
        ],
      );
    }
    final parentLabel = task.parentId == null
        ? null
        : ancestors.isEmpty
        ? context.l10n.taskParentUnavailable
        : context.l10n.taskParentPath(
            ancestors.map((item) => item.content).join(' / '),
          );
    final label = [
      ?parentLabel,
      if (progress != null)
        context.l10n.taskAllSubtasksProgress(
          progress.completed,
          progress.total,
        ),
    ].join(' · ');
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Transform.flip(
                    flipX:
                        parentLabel != null &&
                        Directionality.of(context) == TextDirection.rtl,
                    child: Icon(
                      parentLabel == null
                          ? LucideIcons.gitBranch
                          : LucideIcons.cornerDownRight,
                      size: 12,
                      color: context.appColors.secondaryText,
                    ),
                  ),
                ),
              ),
              TextSpan(
                text: [
                  ?parentLabel,
                  if (progress != null) progress.label,
                ].join(' · '),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: context.appColors.secondaryText,
          ),
        ),
      ),
    );
  }
}

class TaskBranchLines extends StatelessWidget {
  const TaskBranchLines({
    required this.row,
    required this.child,
    this.divider = false,
    super.key,
  });
  final VisibleTaskRow row;
  final Widget child;
  final bool divider;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _BranchPainter(
      row,
      context.appColors.border,
      Directionality.of(context),
      divider,
    ),
    child: child,
  );
}

class _BranchPainter extends CustomPainter {
  _BranchPainter(this.row, this.color, this.direction, this.divider);
  final VisibleTaskRow row;
  final Color color;
  final TextDirection direction;
  final bool divider;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    double x(int level) {
      final offset = taskBranchGutterWidth + 17.0 + 28 * level;
      return direction == TextDirection.ltr ? offset : size.width - offset;
    }

    for (var level = 0; level < row.displayDepth; level++) {
      final direct = level == row.displayDepth - 1;
      // Continuations describe the siblings of the child at each level.
      final continues = direct
          ? !row.isLastSibling
          : row.ancestorContinuations.length > level + 1 &&
                row.ancestorContinuations[level + 1];
      if (!direct && !continues) continue;
      canvas.drawLine(
        Offset(x(level), 0),
        Offset(
          x(level),
          divider || !direct || continues ? size.height : size.height / 2,
        ),
        paint,
      );
      if (direct && !divider) {
        canvas.drawLine(
          Offset(x(level), size.height / 2),
          Offset(
            x(level) + (direction == TextDirection.ltr ? 20 : -20),
            size.height / 2,
          ),
          paint,
        );
      }
    }
    if (!divider && row.hasVisibleChildren && row.expanded && row.depth < 2) {
      canvas.drawLine(
        Offset(x(row.displayDepth), size.height / 2 + 12),
        Offset(x(row.displayDepth), size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BranchPainter old) =>
      old.row != row ||
      old.color != color ||
      old.direction != direction ||
      old.divider != divider;
}
