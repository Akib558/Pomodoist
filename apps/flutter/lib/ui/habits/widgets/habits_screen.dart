import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/widgets/app_action_menu.dart';
import 'package:pomodoist/ui/core/widgets/resizable_dialog.dart';
import 'package:pomodoist/ui/habits/view_models/habits_view_model.dart';
import 'package:pomodoist/ui/habits/widgets/habit_editor.dart';

class HabitsScreen extends ConsumerStatefulWidget {
  const HabitsScreen({super.key});
  @override
  ConsumerState<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends ConsumerState<HabitsScreen> {
  Habit? _editing;
  bool _editorOpen = false;
  void _openEditor(Habit? habit, bool wide) {
    if (wide) {
      setState(() {
        _editing = habit;
        _editorOpen = true;
      });
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      animationStyle: AnimationStyle(
        duration: AppMotion.duration(context, AppMotion.popup),
        reverseDuration: AppMotion.duration(context, AppMotion.popup),
        curve: AppMotion.curve,
      ),
      builder: (context) => ResizableDialog(
        initialSize: const Size(480, 760),
        minSize: const Size(300, 400),
        actions: const [],
        content: HabitEditor(
          habit: habit,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _delete(Habit habit) async {
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: AnimationStyle(
        duration: AppMotion.duration(context, AppMotion.popup),
        reverseDuration: AppMotion.duration(context, AppMotion.popup),
        curve: AppMotion.curve,
      ),
      builder: (context) => AlertDialog(
        title: Text(l.habitDeleteConfirm),
        content: Text(habit.title),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.commonCancel),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final success = await ref
          .read(habitsViewModelProvider.notifier)
          .deleteHabit(habit.id);
      if (success && mounted && _editing?.id == habit.id) {
        setState(() => _editorOpen = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(habitsViewModelProvider),
        vm = ref.read(habitsViewModelProvider.notifier),
        l = context.l10n;
    final colors = context.appColors;
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.navHabits,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l.habitsSubtitle,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: colors.mutedText),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          ShadButton(
                            onPressed: view.saving
                                ? null
                                : () => _openEditor(null, wide),
                            leading: const Icon(LucideIcons.plus, size: 18),
                            child: Text(l.habitNew),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              DateFormat.yMMMM(
                                l.localeName,
                              ).format(view.selectedDay),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          ShadButton.ghost(
                            onPressed: vm.selectToday,
                            child: Text(l.today),
                          ),
                          IconButton(
                            tooltip: l.habitPreviousWeek,
                            onPressed: () => vm.moveWeek(-1),
                            icon: const Icon(LucideIcons.chevronLeft, size: 18),
                          ),
                          IconButton(
                            tooltip: l.habitNextWeek,
                            onPressed: () => vm.moveWeek(1),
                            icon: const Icon(
                              LucideIcons.chevronRight,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (var i = 0; i < 7; i++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: _day(
                                  context,
                                  DateTime(
                                    view.weekStart.year,
                                    view.weekStart.month,
                                    view.weekStart.day + i,
                                  ),
                                  view,
                                  vm,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l.habitsSummary(view.completed, view.planned),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: view.planned == 0
                            ? 0
                            : view.completed / view.planned,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(4),
                        backgroundColor: colors.surfaceTint,
                        color: colors.accent,
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text(l.habitsActive),
                            selected: !view.finished,
                            onSelected: (_) => vm.showFinished(false),
                          ),
                          ChoiceChip(
                            label: Text(l.habitsFinished),
                            selected: view.finished,
                            onSelected: (_) => vm.showFinished(true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (view.futureDay)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            l.habitsFuture,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.mutedText),
                          ),
                        ),
                      if (view.loading)
                        const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (view.loadError)
                        Column(
                          children: [
                            Text(l.habitLoadError),
                            ShadButton.ghost(
                              onPressed: vm.retry,
                              child: Text(l.commonRetry),
                            ),
                          ],
                        )
                      else if (view.rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Column(
                            children: [
                              Icon(
                                LucideIcons.repeat2,
                                size: 32,
                                color: colors.mutedText,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                view.finished
                                    ? l.habitsFinishedEmpty
                                    : l.habitsEmpty,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      else
                        for (final row in view.rows)
                          _row(context, row, view, wide),
                      if (view.actionError)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            l.habitSaveError,
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (wide && _editorOpen)
                Container(
                  width: 380,
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(color: colors.border),
                    ),
                  ),
                  child: HabitEditor(
                    key: ValueKey(_editing?.id ?? 'new'),
                    habit: _editing,
                    onClose: () => setState(() => _editorOpen = false),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _day(
    BuildContext context,
    DateTime day,
    HabitsViewState view,
    HabitsViewModel vm,
  ) {
    final selected = day == view.selectedDay;
    final colors = context.appColors;
    return Semantics(
      selected: selected,
      label: DateFormat.yMMMMEEEEd(context.l10n.localeName).format(day),
      child: Material(
        color: selected ? colors.accentTint : colors.surfaceTint,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => vm.selectDay(day),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Text(
                  DateFormat.E(context.l10n.localeName).format(day),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? colors.accent : colors.mutedText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${day.day}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: selected ? colors.accent : null,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: day == view.today
                        ? colors.accent
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    HabitDayRow row,
    HabitsViewState view,
    bool wide,
  ) {
    final vm = ref.read(habitsViewModelProvider.notifier), l = context.l10n;
    final colors = context.appColors;
    final complete = row.count >= row.target;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: l.habitAddCheckIn,
            onPressed: row.canAdd && !view.saving
                ? () => vm.addCheckIn(row.habit.id)
                : null,
            icon: Icon(
              complete ? LucideIcons.circleCheck : LucideIcons.circlePlus,
              color: complete ? colors.accent : colors.mutedText,
              size: 24,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.habit.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (row.project != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      row.project!.name,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: colors.mutedText),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${row.count} / ${row.target}',
            style: AppTheme.monoTextStyle.copyWith(
              color: complete ? colors.accent : colors.mutedText,
            ),
          ),
          AppActionMenu(
            tooltip: l.habitEdit,
            enabled: !view.saving,
            items: [
              ShadContextMenuItem(
                enabled: row.canUndo,
                onPressed: () => vm.undoCheckIn(row.habit.id),
                child: Text(l.habitUndoCheckIn),
              ),
              ShadContextMenuItem(
                onPressed: () => _openEditor(row.habit, wide),
                child: Text(l.habitEdit),
              ),
              ShadContextMenuItem(
                onPressed: () => _delete(row.habit),
                child: Text(l.commonDelete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
