import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pomodoist/ui/tasks/widgets/task_detail_screen.dart';
import 'package:pomodoist/routing/task_detail_navigation.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';

/// Keeps the task route mounted while the shared panel opens and resizes.
class TaskDetailsHost extends StatelessWidget {
  const TaskDetailsHost({required this.taskId, required this.child, super.key});

  final String? taskId;
  final Widget child;

  @override
  Widget build(BuildContext context) => DetailsPanelHost(
    onClose: () => closeTaskDetails(context),
    panel: taskId == null
        ? null
        : TaskDetailScreen(
            key: ValueKey(taskId),
            taskId: taskId!,
            isPanel: true,
            onClose: () => closeTaskDetails(context),
          ),
    child: child,
  );
}

/// Full-height contextual panels share layout, motion and focus restoration.
class DetailsPanelHost extends StatefulWidget {
  const DetailsPanelHost({
    required this.panel,
    required this.onClose,
    required this.child,
    super.key,
  });

  final Widget? panel;
  final VoidCallback onClose;
  final Widget child;

  @override
  State<DetailsPanelHost> createState() => _DetailsPanelHostState();
}

class _DetailsPanelHostState extends State<DetailsPanelHost> {
  FocusNode? _returnFocus;

  @override
  void didUpdateWidget(covariant DetailsPanelHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panel == null && widget.panel != null) {
      _returnFocus = FocusManager.instance.primaryFocus;
    } else if (oldWidget.panel != null && widget.panel == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _returnFocus?.context != null) {
          _returnFocus?.requestFocus();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final open = widget.panel != null;
      final sideBySide = constraints.maxWidth >= 960;
      final panelWidth = sideBySide ? 440.0 : constraints.maxWidth;
      final duration = AppMotion.duration(context, AppMotion.panel);
      return BackButtonListener(
        onBackButtonPressed: () async {
          if (!open) return false;
          widget.onClose();
          return true;
        },
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (node, event) {
            if (open &&
                event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              widget.onClose();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedPositioned(
                duration: duration,
                curve: AppMotion.curve,
                top: 0,
                bottom: 0,
                left: 0,
                right: open && sideBySide ? panelWidth : 0,
                child: ExcludeFocus(
                  excluding: open && !sideBySide,
                  child: ExcludeSemantics(
                    excluding: open && !sideBySide,
                    child: widget.child,
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: duration,
                curve: AppMotion.curve,
                top: 0,
                bottom: 0,
                width: panelWidth,
                right: open ? 0 : -panelWidth,
                child: open
                    ? Material(
                        color: context.appColors.surface,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: context.appColors.border),
                            ),
                          ),
                          child: FocusScope(
                            autofocus: true,
                            child: widget.panel!,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    },
  );
}
