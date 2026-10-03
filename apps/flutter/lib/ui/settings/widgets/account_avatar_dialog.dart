import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadButton, ShadInput;

import 'package:pomodoist/domain/models/account/avatar_emoji.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_motion.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';

class AccountAvatarDialog extends StatefulWidget {
  const AccountAvatarDialog({
    required this.emoji,
    required this.onSave,
    super.key,
  });

  final String? emoji;
  final Future<void> Function(String?) onSave;

  @override
  State<AccountAvatarDialog> createState() => _AccountAvatarDialogState();
}

class _AccountAvatarDialogState extends State<AccountAvatarDialog> {
  late final _input = TextEditingController(text: widget.emoji ?? '');
  late bool _reset = widget.emoji == null;
  bool _saving = false;
  String? _error;
  Emoji? _selected;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _select(Emoji emoji) {
    if (_saving) return;
    _input.value = TextEditingValue(
      text: emoji.emoji,
      selection: TextSelection.collapsed(offset: emoji.emoji.length),
    );
    setState(() {
      _selected = emoji;
      _reset = false;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final String? value;
    try {
      value = normalizeAvatarEmoji(_reset ? null : _input.text);
    } on ArgumentError {
      setState(() => _error = context.l10n.accountAvatarInvalid);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(value);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.accountAvatarSaveError);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;
    final preview = readAvatarEmoji(_input.text.trim());
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Text(
            l10n.accountChangeAvatar,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Semantics(
                    label: l10n.accountAvatar,
                    child: CircleAvatar(
                      radius: 32,
                      backgroundColor: colors.surfaceHover,
                      child: preview == null
                          ? Icon(
                              Icons.person_outline,
                              color: colors.primaryText,
                            )
                          : Text(preview, style: const TextStyle(fontSize: 36)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(l10n.accountAvatarInput),
                const SizedBox(height: 8),
                Semantics(
                  label: l10n.accountAvatarInput,
                  child: ShadInput(
                    key: const Key('account-avatar-input'),
                    controller: _input,
                    enabled: !_saving,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                    onChanged: (_) => setState(() {
                      _reset = false;
                      _selected = null;
                      _error = null;
                    }),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.accountAvatarHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(_error!, style: TextStyle(color: colors.error)),
                  ),
                ],
                if (_selected case final selected?
                    when selected.hasSkinTone) ...[
                  const SizedBox(height: 12),
                  Text(l10n.accountAvatarSkinTone),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final variant in [
                        EmojiPickerUtils().removeSkinTone(selected),
                        for (final tone in SkinTone.values)
                          EmojiPickerUtils().applySkinTone(selected, tone),
                      ])
                        if (readAvatarEmoji(variant.emoji) != null)
                          Semantics(
                            selected: variant.emoji == preview,
                            child: ShadButton.ghost(
                              width: 48,
                              height: 48,
                              padding: EdgeInsets.zero,
                              backgroundColor: variant.emoji == preview
                                  ? colors.accentTint
                                  : null,
                              enabled: !_saving,
                              onPressed: () => _select(variant),
                              child: Text(
                                variant.emoji,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                ExcludeFocus(
                  excluding: _saving,
                  child: IgnorePointer(
                    ignoring: _saving,
                    child: LayoutBuilder(
                      builder: (context, constraints) => EmojiPicker(
                        onEmojiSelected: (_, emoji) => _select(emoji),
                        config: Config(
                          height: 280,
                          locale: Localizations.localeOf(context),
                          checkPlatformCompatibility: false,
                          emojiViewConfig: EmojiViewConfig(
                            columns: (constraints.maxWidth / 48).floor().clamp(
                              1,
                              10,
                            ),
                            backgroundColor: colors.surface,
                            emojiSizeMax: 28,
                          ),
                          skinToneConfig: SkinToneConfig(
                            dialogBackgroundColor: colors.surface,
                            indicatorColor: colors.secondaryText,
                          ),
                          bottomActionBarConfig: const BottomActionBarConfig(
                            enabled: false,
                          ),
                          categoryViewConfig: CategoryViewConfig(
                            initCategory: Category.SMILEYS,
                            recentTabBehavior: RecentTabBehavior.NONE,
                            tabIndicatorAnimDuration: AppMotion.duration(
                              context,
                              AppMotion.popup,
                            ),
                            customCategoryView: (_, state, tabs, pages) =>
                                TabBar(
                                  controller: tabs,
                                  isScrollable: true,
                                  tabAlignment: TabAlignment.start,
                                  dividerColor: colors.border,
                                  labelColor: colors.accent,
                                  unselectedLabelColor: colors.secondaryText,
                                  indicatorColor: colors.accent,
                                  onTap: pages.jumpToPage,
                                  tabs: [
                                    for (final category in state.categoryEmoji)
                                      Tab(
                                        height: 48,
                                        text: _categoryLabel(
                                          context,
                                          category.category,
                                        ),
                                      ),
                                  ],
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              ShadButton.ghost(
                height: 48,
                enabled: !_saving,
                onPressed: () {
                  _input.clear();
                  setState(() {
                    _reset = true;
                    _selected = null;
                    _error = null;
                  });
                },
                child: Text(l10n.accountAvatarReset),
              ),
              ShadButton.ghost(
                height: 48,
                enabled: !_saving,
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              ShadButton(
                key: const Key('account-avatar-save'),
                height: 48,
                enabled: !_saving,
                onPressed: _save,
                leading: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                child: Text(l10n.commonSave),
              ),
            ],
          ),
        ),
      ],
    );
    return PopScope(
      canPop: !_saving,
      child: MediaQuery.sizeOf(context).width < 600
          ? Dialog.fullscreen(child: SafeArea(child: content))
          : Dialog(
              constraints: const BoxConstraints(maxWidth: 560),
              child: content,
            ),
    );
  }
}

String _categoryLabel(BuildContext context, Category category) {
  final l10n = context.l10n;
  return switch (category) {
    Category.RECENT => l10n.accountAvatar,
    Category.SMILEYS => l10n.accountAvatarSmileys,
    Category.ANIMALS => l10n.accountAvatarAnimals,
    Category.FOODS => l10n.accountAvatarFood,
    Category.ACTIVITIES => l10n.accountAvatarActivities,
    Category.TRAVEL => l10n.accountAvatarTravel,
    Category.OBJECTS => l10n.accountAvatarObjects,
    Category.SYMBOLS => l10n.accountAvatarSymbols,
    Category.FLAGS => l10n.accountAvatarFlags,
  };
}
