import 'avatar_emoji_data.dart';

/// Validates one complete Unicode emoji without truncating its sequence.
/// Only null clears an avatar; empty or non-emoji input is a validation error.
String? normalizeAvatarEmoji(String? input) {
  if (input == null) return null;
  final value = input.trim();
  if (!avatarEmojiSequences.contains(value)) {
    throw ArgumentError.value(input, 'avatarEmoji', 'Expected one emoji.');
  }
  return value;
}

/// Malformed presentation data must never break profile rendering.
String? readAvatarEmoji(Object? input) =>
    input is String && avatarEmojiSequences.contains(input) ? input : null;
