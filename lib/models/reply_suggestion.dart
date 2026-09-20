/// What a suggested message is trying to do.
enum SuggestionKind {
  /// Answers what the other person just said.
  reply,

  /// Moves the conversation on to something else instead of answering.
  ///
  /// Every set of suggestions offers one of these, because a chat often needs
  /// changing the subject more than it needs another answer, and that is the
  /// hardest kind of message to write from a cold start.
  newTopic;

  /// The wire value used in the model's JSON, and accepted loosely because
  /// models vary on spelling.
  static SuggestionKind parse(Object? raw) {
    if (raw is! String) return reply;
    final normalised = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    return switch (normalised) {
      'newtopic' || 'topic' || 'topicchange' || 'change' || 'transition' =>
        newTopic,
      _ => reply,
    };
  }

  /// The tag shown on the suggestion.
  String get label => switch (this) {
    reply => 'reply',
    newTopic => 'new topic',
  };
}

/// One suggested message, and what it is for.
class ReplySuggestion {
  const ReplySuggestion({required this.text, required this.kind});

  const ReplySuggestion.reply(this.text) : kind = SuggestionKind.reply;

  final String text;
  final SuggestionKind kind;

  bool get isNewTopic => kind == SuggestionKind.newTopic;

  ReplySuggestion copyWith({String? text, SuggestionKind? kind}) =>
      ReplySuggestion(text: text ?? this.text, kind: kind ?? this.kind);

  @override
  String toString() => '${kind.name}: $text';
}
