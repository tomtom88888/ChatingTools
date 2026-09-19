import 'chat_message.dart';
import 'chat_turn.dart';

/// Which export layout a file turned out to use.
enum ExportFormat {
  /// `12/03/2023, 19:45 - Alice: hello`
  android,

  /// `[12/03/2023, 19:45:12] Alice: hello`
  ios,

  /// Nothing matched — almost always "this isn't a WhatsApp export".
  unknown,
}

/// The result of parsing one export file.
class ParsedChat {
  const ParsedChat({
    required this.messages,
    required this.turns,
    required this.format,
    required this.senderMessageCounts,
    required this.mediaCount,
    required this.deletedCount,
    required this.systemCount,
    required this.unparsedLineCount,
  });

  static const ParsedChat empty = ParsedChat(
    messages: [],
    turns: [],
    format: ExportFormat.unknown,
    senderMessageCounts: {},
    mediaCount: 0,
    deletedCount: 0,
    systemCount: 0,
    unparsedLineCount: 0,
  );

  final List<ChatMessage> messages;

  /// Style-carrying messages merged per sender. Media, deleted and system
  /// lines are left out, so this is what training actually reads.
  final List<ChatTurn> turns;

  final ExportFormat format;

  /// Message count per sender, highest first, counting media and deleted
  /// messages too — it is meant to help you recognise who is who.
  final Map<String, int> senderMessageCounts;

  final int mediaCount;
  final int deletedCount;
  final int systemCount;

  /// Lines that matched no timestamp and had no preceding message to attach
  /// to. A large number here means the file probably isn't an export.
  final int unparsedLineCount;

  bool get isEmpty => turns.isEmpty;

  List<String> get senders => senderMessageCounts.keys.toList(growable: false);

  int get textMessageCount => messages.where((m) => m.carriesStyle).length;
}
