import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadButton, ShadDialog, ShadInput;

import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/tasks/view_models/task_detail_view_model.dart';

Future<void> showTaskTitleDialog(BuildContext context, TaskItem task) async {
  if (!task.canEdit) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    animationStyle: AnimationStyle(
      duration: AppMotion.duration(context, AppMotion.popup),
      reverseDuration: AppMotion.duration(context, AppMotion.popup),
      curve: AppMotion.curve,
    ),
    builder: (_) => _TaskTitleDialog(task: task),
  );
}

class _TaskTitleDialog extends ConsumerStatefulWidget {
  const _TaskTitleDialog({required this.task});
  final TaskItem task;
  @override
  ConsumerState<_TaskTitleDialog> createState() => _TaskTitleDialogState();
}

class _TaskTitleDialogState extends ConsumerState<_TaskTitleDialog> {
  final _identity = Object();
  late final _text = TextEditingController(text: widget.task.content)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.task.content.length,
    );
  bool _error = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final provider = taskEditorViewModelProvider(_identity);
    if (!widget.task.canEdit ||
        ref.read(provider).saving ||
        _text.text.trim().isEmpty) {
      return;
    }
    setState(() => _error = false);
    try {
      final saved = await ref
          .read(provider.notifier)
          .saveTitle(widget.task, _text.text);
      if (mounted && saved) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(taskEditorViewModelProvider(_identity));
    final l10n = context.l10n;
    return PopScope(
      canPop: !state.saving,
      child: ShadDialog(
        closeIcon: const SizedBox.shrink(),
        title: Text(l10n.taskTitleHint),
        actions: [
          ShadButton.outline(
            enabled: !state.saving,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          ShadButton(
            enabled: !state.saving && _text.text.trim().isNotEmpty,
            onPressed: () => unawaited(_save()),
            child: Text(l10n.commonSave),
          ),
        ],
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadInput(
                key: const Key('map-task-title-input'),
                controller: _text,
                autofocus: true,
                enabled: !state.saving,
                maxLines: null,
                textInputAction: TextInputAction.done,
                onChanged: (value) => ref
                    .read(taskEditorViewModelProvider(_identity).notifier)
                    .updateDraft(value),
                onSubmitted: (_) => unawaited(_save()),
              ),
              if (_error || state.failed)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      l10n.taskActionFailedCount(1),
                      style: TextStyle(color: context.appColors.error),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
