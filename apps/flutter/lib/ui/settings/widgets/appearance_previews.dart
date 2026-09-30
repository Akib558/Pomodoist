import 'package:flutter/material.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/tasks/task_time.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/tasks/view_models/task_branch_rows.dart';
import 'package:pomodoist/ui/tasks/view_models/task_subtask_progress.dart';
import 'package:pomodoist/ui/tasks/widgets/task_list_item.dart';

/// Read-only samples keep their text semantics without exposing task actions.
class AppearancePreview extends StatelessWidget {
  const AppearancePreview({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: context.l10n.settingsAppearancePreview,
    child: ExcludeFocus(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.appColors.canvas,
          border: Border.all(color: context.appColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
    ),
  );
}

class TaskListAppearancePreview extends StatelessWidget {
  const TaskListAppearancePreview({
    required this.style,
    required this.spacing,
    required this.branchStyle,
    this.timeDisplayMode = TaskTimeDisplayMode.smart,
    this.timedMinutes = 30,
    super.key,
  });

  final TaskListStyle style;
  final TaskRowSpacing spacing;
  final TaskBranchStyle branchStyle;
  final TaskTimeDisplayMode timeDisplayMode;
  final int timedMinutes;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final day = DateUtils.dateOnly(DateTime.now());
    final project = ProjectItem(
      id: 'appearance-preview-project',
      userId: '',
      name: l10n.settingsPreviewProject,
      color: '#8B5CF6',
      orderKey: 'a0',
      createdAt: day,
      updatedAt: day,
      canEdit: false,
      canManage: false,
    );
    final titles = [
      l10n.themePreviewTask,
      l10n.settingsPreviewLongTask,
      l10n.settingsPreviewCompletedTask,
    ];
    final tasks = [
      for (var i = 0; i < titles.length; i++)
        TaskItem(
          id: 'appearance-preview-task-$i',
          userId: '',
          content: titles[i],
          projectId: project.id,
          priority: i == 0 ? 2 : 4,
          status: i == 2 ? 'completed' : 'open',
          completedFocusIntervals: i == 0 ? 1 : 0,
          totalFocusSeconds: 0,
          estimatedFocusIntervals: i == 0 ? 2 : null,
          orderKey: 'a$i',
          isDeleted: false,
          canEdit: false,
          createdAt: day,
          updatedAt: day,
          parentId: i == 0 ? null : 'appearance-preview-task-0',
          description: i == 0 ? l10n.themePreviewSecondary : null,
          dueJson: i == 2
              ? null
              : TaskSchedule.timed(
                  start: day.add(Duration(hours: 10 + i)),
                  end: day.add(Duration(hours: 11 + i, minutes: 20)),
                ).toJsonString(),
        ),
    ];
    final rows = visibleTaskRows(tasks, tasks);
    final progress = taskSubtaskProgressById(tasks);
    return AppearancePreview(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              TaskListDivider.preview(
                previous: rows[i - 1],
                next: rows[i],
                branchStyle: branchStyle,
                hasTrailingContent: true,
              ),
            TaskListRowPreview(
              task: rows[i].task,
              row: rows[i],
              style: style,
              spacing: spacing,
              branchStyle: branchStyle,
              project: i == 2 ? null : project,
              progress: progress[rows[i].task.id],
              timeDisplayMode: timeDisplayMode,
              timedMinutes: timedMinutes,
            ),
          ],
        ],
      ),
    );
  }
}
