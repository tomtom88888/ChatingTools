import 'chat_turn.dart';

/// One training example: the turns leading up to a reply of mine, plus the
/// reply I actually sent.
///
/// [context] is chronological and its last entry is always the other person's
/// turn — that is what makes this a reply rather than an opener.
class Exchange {
  const Exchange({required this.context, required this.reply});

  final List<ChatTurn> context;
  final ChatTurn reply;

  /// The text that gets embedded and searched against at generation time.
  String get contextText => renderContext(context);

  String get replyText => reply.text;

  DateTime? get timestamp => reply.firstTimestamp ?? reply.lastTimestamp;

  /// Renders turns as `Name: text` lines. Used for both embedding and for the
  /// examples handed to the model, so the two always look the same.
  static String renderContext(Iterable<ChatTurn> turns) =>
      turns.map((t) => '${t.sender}: ${t.text}').join('\n');

  @override
  String toString() =>
      'Exchange(context: ${context.length} turns -> "${reply.text}")';
}
