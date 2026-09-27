import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons, ShadButton;

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/tasks/project_colors.dart';
import 'package:pomodoist/ui/tasks/widgets/project_color_picker.dart';

IconData labelIconData(String? name) => switch (name) {
  'bookmark' => LucideIcons.bookmark,
  'flag' => LucideIcons.flag,
  'bolt' => LucideIcons.bolt,
  'lightbulb' => LucideIcons.lightbulb,
  'clock' => LucideIcons.clock,
  'bell' => LucideIcons.bell,
  'pin' => LucideIcons.pin,
  'phone' => LucideIcons.phone,
  'mail' => LucideIcons.mail,
  'link' => LucideIcons.link,
  'wrench' => LucideIcons.wrench,
  _ => LucideIcons.tag,
};

class LabelIconView extends StatelessWidget {
  const LabelIconView({required this.label, this.size = 20, super.key});

  final LabelItem label;
  final double size;

  @override
  Widget build(BuildContext context) => Icon(
    labelIconData(label.icon),
    color: projectColorValue(effectiveLabelColor(label)),
    size: size,
  );
}

Future<String?> showLabelIconPicker(
  BuildContext context, {
  String? selectedIcon,
}) => showDialog<String>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(context.l10n.labelIcon),
    content: SizedBox(
      width: 280,
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final icon in LabelIcon.values)
              Semantics(
                selected: icon.name == (selectedIcon ?? 'tag'),
                child: IconButton.outlined(
                  tooltip: context.l10n.labelIconOption(icon.name),
                  isSelected: icon.name == (selectedIcon ?? 'tag'),
                  onPressed: () => Navigator.of(context).pop(icon.name),
                  icon: Icon(labelIconData(icon.name)),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      ShadButton.ghost(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.l10n.commonCancel),
      ),
    ],
  ),
);
