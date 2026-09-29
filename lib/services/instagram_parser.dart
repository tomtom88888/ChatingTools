import 'dart:convert';

import '../models/chat_message.dart';
import '../models/parsed_chat.dart';
import 'whatsapp_parser.dart';

/// One conversation from an Instagram "Download your information" export.
class InstagramThread {
  const InstagramThread({
    required this.title,
    required this.participants,
    required this.messages,
  });

  /// The chat's name: the other person, or the group's name.
  final String title;
  final List<String> participants;

  /// As Instagram wrote them: one map per message, in any order.
  final List<Map<String, Object?>> messages;

  bool get isGroup => participants.length > 2;

  int get size => messages.length;

  /// The newest message's time, for listing threads most recent first.
  DateTime? get lastAt {
    var newest = 0;
    for (final m in messages) {
      final ms = m['timestamp_ms'];
      if (ms is num && ms > newest) newest = ms.toInt();
    }
    return newest == 0 ? null : DateTime.fromMillisecondsSinceEpoch(newest);
  }
}

/// Reads Instagram's JSON export: `messages/inbox/<chat>/message_1.json`,
/// with `message_2.json` and on for a long chat.
///
/// Two quirks of that export are handled here. Messages are listed newest
/// first. And every string is UTF-8 whose bytes were written out as if each
/// were its own character, so "café" arrives as "cafÃ©" and every emoji as
/// a run of accented letters; [repair] turns them back.
///
/// Pure Dart, so it is unit-testable without a device.
class InstagramParser {
  const InstagramParser._();

  /// Whether [text] is one of Instagram's message files.
  static bool looksLikeThread(String text) {
    final start = text.trimLeft();
    return start.startsWith('{') &&
        start.contains('"participants"') &&
        start.contains('"messages"');
  }

  /// Whether [path] is a message file inside the export: under
  /// `messages/inbox/` (older exports) or
  /// `your_instagram_activity/messages/inbox/` (newer ones).
  static bool isThreadFile(String path) => RegExp(
    r'(^|/)messages/inbox/[^/]+/message_\d+\.json$',
    caseSensitive: false,
  ).hasMatch(path.replaceAll(r'\', '/'));

  /// The folder a message file belongs to, which groups a long chat's
  /// several files together.
  static String threadFolder(String path) {
    final parts = path.replaceAll(r'\', '/').split('/');
    return parts.length >= 2 ? parts[parts.length - 2] : path;
  }

  /// One thread from the JSON of its message files.
  static InstagramThread thread(List<String> files) {
    var title = '';
    final participants = <String>[];
    final messages = <Map<String, Object?>>[];
    for (final file in files) {
      final Object? json;
      try {
        json = jsonDecode(file);
      } on FormatException {
        continue;
      }
      if (json is! Map) continue;
      final t = json['title'];
      if (title.isEmpty && t is String) title = repair(t);
      final people = json['participants'];
      if (participants.isEmpty && people is List) {
        for (final p in people) {
          final name = p is Map ? p['name'] : null;
          if (name is String && name.trim().isNotEmpty) {
            participants.add(repair(name).trim());
          }
        }
      }
      final list = json['messages'];
      if (list is List) {
        for (final m in list) {
          if (m is Map) messages.add(m.cast<String, Object?>());
        }
      }
    }
    return InstagramThread(
      title: title.isEmpty ? participants.join(', ') : title,
      participants: participants,
      messages: messages,
    );
  }

  /// Who made the export: the one person in every thread. `null` when that
  /// can't be told, as with a single one-to-one thread.
  static String? ownerOf(List<InstagramThread> threads) {
    if (threads.length < 2) return null;
    Set<String>? common;
    for (final t in threads) {
      final people = t.participants.toSet();
      common = common == null ? people : common.intersection(people);
    }
    return common != null && common.length == 1 ? common.single : null;
  }

  /// The thread as a parsed chat, oldest message first, in the same shape a
  /// WhatsApp export is read into.
  static ParsedChat toParsedChat(
    InstagramThread thread, {
    Duration maxTurnGap = WhatsAppParser.defaultTurnGap,
  }) {
    final rows = [...thread.messages]
      ..sort((a, b) {
        final x = a['timestamp_ms'];
        final y = b['timestamp_ms'];
        return (x is num ? x : 0).compareTo(y is num ? y : 0);
      });
    final messages = <ChatMessage>[];
    var media = 0;
    var deleted = 0;
    var system = 0;
    final counts = <String, int>{};
    for (final row in rows) {
      final message = _message(row);
      if (message == null) continue;
      switch (message.kind) {
        case MessageKind.media:
          media++;
        case MessageKind.deleted:
          deleted++;
        case MessageKind.system:
          system++;
        case MessageKind.text:
          break;
      }
      final sender = message.sender;
      if (sender != null) counts[sender] = (counts[sender] ?? 0) + 1;
      messages.add(message);
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ParsedChat(
      messages: messages,
      turns: WhatsAppParser.mergeTurns(messages, maxGap: maxTurnGap),
      format: ExportFormat.instagram,
      senderMessageCounts: Map.fromEntries(sorted),
      mediaCount: media,
      deletedCount: deleted,
      systemCount: system,
      unparsedLineCount: 0,
    );
  }

  /// Lines Instagram writes itself rather than the person typing them.
  static final List<RegExp> _generated = [
    RegExp(r'^liked a message$', caseSensitive: false),
    RegExp(r'^reacted .{1,12} to your message\s*$', caseSensitive: false),
    RegExp(r'sent an attachment\.?$', caseSensitive: false),
    RegExp(r'^you sent an attachment\.?$', caseSensitive: false),
    RegExp(r'shared a (story|post|reel)\.?$', caseSensitive: false),
    RegExp(r'^mentioned you in (their|a) story\.?$', caseSensitive: false),
    RegExp(
      r'(started|missed|ended) (a |the )?(video|audio) (chat|call)\.?$',
      caseSensitive: false,
    ),
    RegExp(r'^(this|a) message (was )?unsent\.?$', caseSensitive: false),
    RegExp(
      r'(named the group|changed the group|added .+ to the group|left the group)',
      caseSensitive: false,
    ),
  ];

  static ChatMessage? _message(Map<String, Object?> row) {
    final senderRaw = row['sender_name'];
    if (senderRaw is! String || senderRaw.trim().isEmpty) return null;
    final sender = repair(senderRaw).trim();
    final ms = row['timestamp_ms'];
    final at = ms is num
        ? DateTime.fromMillisecondsSinceEpoch(ms.toInt())
        : null;
    final contentRaw = row['content'];
    final content = contentRaw is String ? repair(contentRaw).trim() : '';
    final hasMedia = [
      'photos',
      'videos',
      'audio_files',
      'gifs',
      'files',
      'sticker',
    ].any((k) => row[k] != null);

    MessageKind kind;
    if (row['call_duration'] != null) {
      kind = MessageKind.system;
    } else if (row['is_unsent'] == true) {
      kind = MessageKind.deleted;
    } else if (content.isEmpty) {
      kind = hasMedia || row['share'] != null
          ? MessageKind.media
          : MessageKind.system;
    } else if (_generated.any((p) => p.hasMatch(content))) {
      kind = row['share'] != null || hasMedia
          ? MessageKind.media
          : MessageKind.system;
    } else {
      kind = MessageKind.text;
    }
    return ChatMessage(
      sender: kind == MessageKind.system ? null : sender,
      timestamp: at,
      text: kind == MessageKind.text ? content : '',
      kind: kind,
      rawText: content,
    );
  }

  /// Undoes Instagram's double encoding: each character of a string that
  /// really holds UTF-8 bytes becomes that byte again, and the bytes are
  /// decoded. A string with any character past U+00FF was never mangled, and
  /// one whose bytes aren't valid UTF-8 is left alone.
  static String repair(String text) {
    if (text.isEmpty) return text;
    var mangled = false;
    for (final unit in text.codeUnits) {
      if (unit > 0xFF) return text;
      if (unit >= 0x80) mangled = true;
    }
    if (!mangled) return text;
    try {
      return utf8.decode(text.codeUnits);
    } on FormatException {
      return text;
    }
  }
}
