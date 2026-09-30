import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';
import 'package:pomodoist/domain/models/notifications/habit_reminder_status.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/habits/view_models/habits_view_model.dart';

class HabitEditor extends ConsumerStatefulWidget {
  const HabitEditor({this.habit, required this.onClose, super.key});
  final Habit? habit;
  final VoidCallback onClose;
  @override
  ConsumerState<HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends ConsumerState<HabitEditor> {
  late final TextEditingController _title, _target;
  late DateTime _start;
  DateTime? _end;
  late Set<int> _weekdays;
  late bool _daily, _reminder;
  late TimeOfDay _time;
  String? _project;
  int _duration = 0;
  bool _error = false;
  @override
  void initState() {
    super.initState();
    final habit = widget.habit;
    final schedule = habit?.scheduleHistory.last;
    _title = TextEditingController(text: habit?.title ?? '');
    _target = TextEditingController(text: '${schedule?.targetPerDay ?? 1}');
    _start = schedule?.startDate ?? ref.read(habitsViewModelProvider).today;
    _end = schedule?.endDate;
    _duration = _end == null ? 0 : -1;
    _weekdays = (schedule?.weekdays ?? [1, 2, 3, 4, 5, 6, 7]).toSet();
    _daily = _weekdays.length == 7;
    _reminder = habit?.reminderMinutes != null;
    final minutes = habit?.reminderMinutes ?? 1200;
    _time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    final projects = ref.read(habitsViewModelProvider).projects;
    _project = projects.any((p) => p.id == habit?.projectId)
        ? habit?.projectId
        : null;
  }

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    super.dispose();
  }

  String _date(DateTime day) =>
      DateFormat.yMMMd(context.l10n.localeName).format(day);
  Future<void> _pickDate(bool start) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: start ? _start : (_end ?? _start),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _start = selected;
        if (_duration > 0) _end = habitEndAfterDays(_start, _duration);
      } else {
        _end = selected;
        _duration = -1;
      }
    });
  }

  Future<void> _save() async {
    final saved = await ref
        .read(habitsViewModelProvider.notifier)
        .save(
          id: widget.habit?.id,
          title: _title.text,
          startDate: _start,
          endDate: _end,
          weekdays: _daily
              ? [1, 2, 3, 4, 5, 6, 7]
              : (_weekdays.toList()..sort()),
          target: _target.text,
          projectId:
              ref
                  .read(habitsViewModelProvider)
                  .projects
                  .any((p) => p.id == _project)
              ? _project
              : null,
          reminderMinutes: _reminder ? _time.hour * 60 + _time.minute : null,
        );
    if (!mounted) return;
    if (saved) {
      widget.onClose();
    } else {
      setState(() => _error = true);
    }
  }

  Widget _field(String label, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Semantics(label: label, child: child),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final l = context.l10n, view = ref.watch(habitsViewModelProvider);
    final colors = context.appColors;
    final allowed = view.reminderStatus != HabitReminderStatus.unsupported;
    final reminderMessage = switch (view.reminderStatus) {
      HabitReminderStatus.denied => l.habitReminderDenied,
      HabitReminderStatus.unsupported => l.habitReminderUnavailable,
      HabitReminderStatus.failed => l.habitReminderFailed,
      _ => null,
    };
    return Material(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.habit == null ? l.habitNew : l.habitEdit,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: l.commonClose,
                  onPressed: view.saving ? null : widget.onClose,
                  icon: const Icon(LucideIcons.x, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _field(
                      l.habitName,
                      ShadInput(
                        controller: _title,
                        maxLength: 200,
                        enabled: !view.saving,
                        placeholder: Text(l.habitName),
                      ),
                    ),
                    _field(
                      l.habitFrequency,
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text(l.habitDaily),
                            selected: _daily,
                            onSelected: view.saving
                                ? null
                                : (_) => setState(() => _daily = true),
                          ),
                          ChoiceChip(
                            label: Text(l.habitWeekdays),
                            selected: !_daily,
                            onSelected: view.saving
                                ? null
                                : (_) => setState(() => _daily = false),
                          ),
                        ],
                      ),
                    ),
                    if (!_daily)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (var d = 1; d <= 7; d++)
                              FilterChip(
                                label: Text(
                                  DateFormat.E(
                                    l.localeName,
                                  ).format(DateTime(2026, 9, 28 + d - 1)),
                                ),
                                selected: _weekdays.contains(d),
                                onSelected: view.saving
                                    ? null
                                    : (value) => setState(
                                        () => value
                                            ? _weekdays.add(d)
                                            : _weekdays.remove(d),
                                      ),
                              ),
                          ],
                        ),
                      ),
                    _field(
                      l.habitTarget,
                      ShadInput(
                        controller: _target,
                        enabled: !view.saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                      ),
                    ),
                    _field(
                      l.habitStart,
                      ShadButton.outline(
                        enabled: !view.saving,
                        onPressed: () => _pickDate(true),
                        leading: const Icon(LucideIcons.calendar, size: 16),
                        child: Text(_date(_start)),
                      ),
                    ),
                    _field(
                      l.habitEnd,
                      ShadSelect<int>(
                        key: ValueKey(_duration),
                        initialValue: _duration,
                        enabled: !view.saving,
                        options: [
                          ShadOption(value: 0, child: Text(l.habitForever)),
                          for (final d in [7, 21, 30, 365])
                            ShadOption(
                              value: d,
                              child: Text(l.habitDurationDays(d)),
                            ),
                          ShadOption(value: -1, child: Text(l.habitCustom)),
                        ],
                        selectedOptionBuilder: (context, value) => Text(
                          value == 0
                              ? l.habitForever
                              : value == -1
                              ? l.habitCustom
                              : l.habitDurationDays(value),
                        ),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _duration = value;
                            _end = value == 0
                                ? null
                                : value > 0
                                ? habitEndAfterDays(_start, value)
                                : (_end ?? _start);
                          });
                        },
                      ),
                    ),
                    if (_end != null)
                      _field(
                        l.habitEnd,
                        ShadButton.outline(
                          enabled: !view.saving,
                          onPressed: () => _pickDate(false),
                          child: Text(_date(_end!)),
                        ),
                      ),
                    _field(
                      l.habitProject,
                      ShadSelect<String>(
                        key: ValueKey(_project),
                        initialValue: _project ?? '',
                        enabled: !view.saving,
                        options: [
                          ShadOption(value: '', child: Text(l.habitNoProject)),
                          for (final p in view.projects)
                            ShadOption(value: p.id, child: Text(p.name)),
                        ],
                        selectedOptionBuilder: (context, value) => Text(
                          view.projects
                                  .where((p) => p.id == value)
                                  .firstOrNull
                                  ?.name ??
                              l.habitNoProject,
                        ),
                        onChanged: (value) => setState(
                          () => _project = value == '' ? null : value,
                        ),
                      ),
                    ),
                    ShadSwitch(
                      value: _reminder,
                      enabled: allowed && !view.saving,
                      onChanged: (value) => setState(() => _reminder = value),
                      label: Text(l.habitReminder),
                    ),
                    if (_reminder)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _field(
                          l.habitReminderTime,
                          ShadButton.outline(
                            enabled: allowed && !view.saving,
                            onPressed: () async {
                              final value = await showTimePicker(
                                context: context,
                                initialTime: _time,
                              );
                              if (value != null && mounted) {
                                setState(() => _time = value);
                              }
                            },
                            child: Text(_time.format(context)),
                          ),
                        ),
                      ),
                    if (reminderMessage != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          reminderMessage,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.mutedText),
                        ),
                      ),
                    if (view.reminderStatus == HabitReminderStatus.failed)
                      ShadButton.ghost(
                        onPressed: () => ref
                            .read(habitsViewModelProvider.notifier)
                            .retryReminders(),
                        child: Text(l.commonRetry),
                      ),
                    if (_error)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          l.habitSaveError,
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ShadButton(
              enabled: !view.saving,
              onPressed: _save,
              leading: view.saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              child: Text(l.commonSave),
            ),
          ],
        ),
      ),
    );
  }
}
