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
  const ExtractedMessage({
    required this.speaker,
    required this.text,
    this.quoted,
    this.author,
  });

  final Speaker speaker;

  /// What was typed in the bubble — never the quoted message above it.
  final String text;

  /// For a WhatsApp reply, the message it quotes (the small box at the top of
  /// the bubble). Shown for context only: it was not written by this sender
  /// in this bubble, so it is never part of [text] or of the prompt.
  final String? quoted;

  /// Who wrote it, when the chat shows names — in a group, the name above
  /// each of the other people's bubbles. `null` in a one-to-one chat.
  final String? author;

  ExtractedMessage copyWith({
    Speaker? speaker,
    String? text,
    String? quoted,
    String? author,
  }) => ExtractedMessage(
    speaker: speaker ?? this.speaker,
    text: text ?? this.text,
    quoted: quoted ?? this.quoted,
    author: author ?? this.author,
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
    final quoted = raw['quoted'] ?? raw['quote'] ?? raw['reply_to'];
    final author = raw['name'] ?? raw['author'];
    var body = text.trim();
    final name = author is String && author.trim().isNotEmpty
        ? author.trim()
        : null;
    // A model that copies the name label into the text as well.
    if (name != null && speaker == Speaker.them) {
      for (final prefix in ['$name\n', '$name: ', '$name:']) {
        if (body.startsWith(prefix)) {
          body = body.substring(prefix.length).trim();
          break;
        }
      }
    }
    return ExtractedMessage(
      speaker: speaker,
      text: body,
      quoted: quoted is String && quoted.trim().isNotEmpty
          ? quoted.trim()
          : null,
      author: speaker == Speaker.them ? name : null,
    );
  }

  Map<String, Object?> toJson() => {
    'sender': speaker.name,
    'text': text,
    if (quoted != null) 'quoted': quoted,
    if (author != null) 'name': author,
  };

  @override
  String toString() => '${speaker.name}: $text';
}
