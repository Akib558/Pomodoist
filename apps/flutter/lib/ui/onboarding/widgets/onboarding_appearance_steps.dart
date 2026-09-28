import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';
import 'package:pomodoist/ui/core/view_models/app_theme_mode_view_model.dart';
import 'package:pomodoist/ui/settings/view_models/task_settings_view_model.dart';
import 'package:pomodoist/ui/settings/view_models/theme_settings_view_model.dart';
import 'package:pomodoist/ui/settings/widgets/theme_settings_card.dart'
    show themeDisplayName;
import 'package:pomodoist/ui/tasks/widgets/task_row_geometry.dart';

class OnboardingTasksStep extends ConsumerWidget {
  const OnboardingTasksStep({
    required this.enabled,
    required this.onSave,
    super.key,
  });

  final bool enabled;
  final void Function(Future<void> Function()) onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(taskListSettingsViewModelProvider);
    final controller = ref.read(taskListSettingsViewModelProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.settingsTaskListStyle,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 320 ||
                MediaQuery.textScalerOf(context).scale(14) > 18;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in TaskListStyle.values)
                  SizedBox(
                    width: stacked
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 8) / 2,
                    child: _Choice(
                      selected: settings.style == style,
                      onPressed: enabled
                          ? () => onSave(() => controller.setStyle(style))
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ExcludeSemantics(
                            child: _StyleThumbnail(style: style),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            style == TaskListStyle.modern
                                ? l10n.settingsTaskListModern
                                : l10n.settingsTaskListClassic,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            style == TaskListStyle.modern
                                ? l10n.onboardingModernDescription
                                : l10n.onboardingClassicDescription,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: context.appColors.secondaryText,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Text(
          l10n.settingsTaskRowSpacing,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final spacing in TaskRowSpacing.values)
              _Choice(
                selected: settings.spacing == spacing,
                onPressed: enabled
                    ? () => onSave(() => controller.setSpacing(spacing))
                    : null,
                child: Text(switch (spacing) {
                  TaskRowSpacing.compact => l10n.settingsTaskRowSpacingCompact,
                  TaskRowSpacing.comfortable =>
                    l10n.settingsTaskRowSpacingComfortable,
                  TaskRowSpacing.spacious =>
                    l10n.settingsTaskRowSpacingSpacious,
                }),
              ),
          ],
        ),
        const SizedBox(height: 20),
        const _TaskPreview(),
        const SizedBox(height: 20),
        Text(
          l10n.settingsTaskBranchStyle,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final branch in TaskBranchStyle.values)
              _Choice(
                selected: settings.branchStyle == branch,
                onPressed: enabled
                    ? () => onSave(() => controller.setBranchStyle(branch))
                    : null,
                child: Text(
                  branch == TaskBranchStyle.connected
                      ? l10n.settingsTaskBranchConnected
                      : l10n.settingsTaskBranchGrouped,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          l10n.onboardingAppearanceHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class OnboardingThemeStep extends ConsumerWidget {
  const OnboardingThemeStep({
    required this.enabled,
    required this.onSave,
    super.key,
  });

  final bool enabled;
  final void Function(Future<void> Function()) onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(appThemeSettingsProvider);
    final mode = ref.watch(appThemeModeProvider);
    final ready =
        enabled &&
        settings.isLoaded &&
        !settings.isSaving &&
        settings.preview == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in AppThemeMode.values)
              _Choice(
                selected: mode == value,
                onPressed: enabled
                    ? () => onSave(
                        () => ref
                            .read(appThemeModeProvider.notifier)
                            .setThemeMode(value),
                      )
                    : null,
                child: Text(switch (value) {
                  AppThemeMode.system => l10n.settingsThemeSystem,
                  AppThemeMode.light => l10n.settingsThemeLight,
                  AppThemeMode.dark => l10n.settingsThemeDark,
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (settings.loadFailed) ...[
          Text(l10n.themeLoadError),
          TextButton(
            onPressed: enabled
                ? () => onSave(
                    () => ref.read(appThemeSettingsProvider.notifier).load(),
                  )
                : null,
            child: Text(l10n.commonRetry),
          ),
        ] else if (!settings.isLoaded)
          const LinearProgressIndicator(),
        for (final theme in builtinAppThemes) ...[
          Builder(
            builder: (context) {
              final selected = settings.selectedId == theme.id;
              final colors = Theme.of(context).brightness == Brightness.dark
                  ? theme.dark
                  : theme.light;
              return Semantics(
                selected: selected,
                child: TextButton(
                  onPressed: ready
                      ? () => onSave(
                          () => ref
                              .read(appThemeSettingsProvider.notifier)
                              .selectTheme(theme.id),
                        )
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor: context.appColors.primaryText,
                    minimumSize: const Size(0, 64),
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final color in [
                              colors.accent,
                              colors.surfaceTint,
                              colors.primaryText,
                            ])
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 4,
                                ),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const SizedBox.square(dimension: 14),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(themeDisplayName(l10n, theme)),
                            const SizedBox(height: 4),
                            Text(
                              switch (theme.id) {
                                'classic' =>
                                  l10n.onboardingClassicThemeDescription,
                                'ocean' => l10n.onboardingOceanDescription,
                                'forest' => l10n.onboardingForestDescription,
                                'sepia' => l10n.onboardingSepiaDescription,
                                _ => l10n.onboardingGraphiteDescription,
                              },
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: context.appColors.secondaryText,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        selected ? LucideIcons.circleCheck : LucideIcons.circle,
                        size: 20,
                        color: selected
                            ? context.appColors.accent
                            : context.appColors.border,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (theme != builtinAppThemes.last)
            Divider(height: 1, color: context.appColors.border),
        ],
        const SizedBox(height: 20),
        const _TaskPreview(),
        const SizedBox(height: 16),
        Text(
          l10n.onboardingThemeHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.onPressed,
    required this.child,
  });
  final bool selected;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: context.appColors.primaryText,
        backgroundColor: selected
            ? context.appColors.accentTint
            : context.appColors.surface,
        side: BorderSide(
          color: selected ? context.appColors.accent : context.appColors.border,
        ),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: child,
    ),
  );
}

class _StyleThumbnail extends StatelessWidget {
  const _StyleThumbnail({required this.style});
  final TaskListStyle style;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < 2; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Icon(
                LucideIcons.circle,
                size: 12,
                color: context.appColors.secondaryText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: style == TaskListStyle.modern ? 5 : 3,
                      color: context.appColors.secondaryText,
                    ),
                    const SizedBox(height: 5),
                    FractionallySizedBox(
                      widthFactor: .6,
                      child: Container(
                        height: 3,
                        color: context.appColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Decorative sample only: never creates tasks or exposes task actions.
class _TaskPreview extends ConsumerWidget {
  const _TaskPreview();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(taskListSettingsViewModelProvider);
    final colors = context.appColors;
    final l10n = context.l10n;
    final grouped = settings.branchStyle == TaskBranchStyle.grouped;
    Widget row(String title, {bool child = false}) => Padding(
      padding: EdgeInsets.symmetric(
        vertical: TaskRowGeometry.verticalPadding(settings.spacing),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (child)
            SizedBox(
              width: grouped ? 12 : 28,
              height: 24,
              child: grouped
                  ? null
                  : Center(
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: colors.border,
                      ),
                    ),
            ),
          SizedBox(
            width: 24,
            height: 24,
            child: Icon(
              LucideIcons.circle,
              size: 20,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: settings.style == TaskListStyle.modern
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                SizedBox(height: TaskRowGeometry.blockGap(settings.spacing, 4)),
                Text(
                  child ? l10n.navToday : l10n.themePreviewSecondary,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: child ? colors.accent : colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final branch = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(l10n.themePreviewTask),
        Divider(height: 1, color: colors.border),
        row(l10n.onboardingPreviewSubtask, child: true),
      ],
    );
    return ExcludeSemantics(
      child: IgnorePointer(
        child: MediaQuery.withNoTextScaling(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceTint,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.navToday,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                if (grouped)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(color: colors.border),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: branch,
                  )
                else
                  branch,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
