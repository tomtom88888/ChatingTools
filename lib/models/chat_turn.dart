import 'chat_message.dart';

/// Consecutive messages from the same sender, merged into one conversational
/// turn. WhatsApp users routinely split a thought across several bubbles, so a
/// turn is the unit that actually reflects how someone writes.
class ChatTurn {
  const ChatTurn({
    required this.sender,
    required this.text,
    required this.messageCount,
    this.firstTimestamp,
    this.lastTimestamp,
  });

  factory ChatTurn.fromMessages(List<ChatMessage> messages) {
    assert(messages.isNotEmpty, 'a turn needs at least one message');
    final stamps = messages
        .map((m) => m.timestamp)
        .whereType<DateTime>()
        .toList(growable: false);
    return ChatTurn(
      sender: messages.first.sender ?? '',
      text: messages.map((m) => m.text).join('\n'),
      messageCount: messages.length,
      firstTimestamp: stamps.isEmpty ? null : stamps.first,
      lastTimestamp: stamps.isEmpty ? null : stamps.last,
    );
  }

  final String sender;
  final String text;
  final int messageCount;
  final DateTime? firstTimestamp;
  final DateTime? lastTimestamp;

  Map<String, Object?> toJson() => {
    'sender': sender,
    'text': text,
    'messageCount': messageCount,
    'firstTimestamp': firstTimestamp?.millisecondsSinceEpoch,
    'lastTimestamp': lastTimestamp?.millisecondsSinceEpoch,
  };

  factory ChatTurn.fromJson(Map<String, Object?> json) {
    DateTime? at(Object? millis) => millis is num
        ? DateTime.fromMillisecondsSinceEpoch(millis.toInt())
        : null;
    return ChatTurn(
      sender: (json['sender'] as String?) ?? '',
      text: (json['text'] as String?) ?? '',
      messageCount: (json['messageCount'] as num?)?.toInt() ?? 1,
      firstTimestamp: at(json['firstTimestamp']),
      lastTimestamp: at(json['lastTimestamp']),
    );
  }

  @override
  String toString() => 'ChatTurn($sender x$messageCount: "$text")';
}
