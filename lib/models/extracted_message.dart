/// Who sent a message the vision model read off a screenshot.
enum Speaker {
  /// A right-aligned bubble in WhatsApp.
  me,

  /// A left-aligned bubble.
  them,
}

/// One message read off a conversation screenshot. Editable before generating,
/// because vision models do misread bubble alignment.
class ExtractedMessage {
  const ExtractedMessage({required this.speaker, required this.text});

  final Speaker speaker;
  final String text;

  ExtractedMessage copyWith({Speaker? speaker, String? text}) =>
      ExtractedMessage(
        speaker: speaker ?? this.speaker,
        text: text ?? this.text,
      );

  /// Parses one `{"sender": "me"|"them", "text": "..."}` entry.
  ///
  /// Throws [FormatException] rather than guessing, so a malformed response is
  /// reported to the user instead of silently producing nonsense.
  factory ExtractedMessage.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('expected an object with sender and text');
    }
    final sender = raw['sender'];
    final text = raw['text'];
    if (sender is! String) {
      throw const FormatException('"sender" must be "me" or "them"');
    }
    if (text is! String) {
      throw const FormatException('"text" must be a string');
    }
    final normalised = sender.trim().toLowerCase();
    final speaker = switch (normalised) {
      'me' || 'self' || 'mine' => Speaker.me,
      'them' || 'other' || 'they' => Speaker.them,
      _ => throw FormatException('unknown sender "$sender"'),
    };
    return ExtractedMessage(speaker: speaker, text: text.trim());
  }

  Map<String, Object?> toJson() => {'sender': speaker.name, 'text': text};

  @override
  String toString() => '${speaker.name}: $text';
}
