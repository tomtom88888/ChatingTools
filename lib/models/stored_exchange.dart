import 'dart:convert';
import 'dart:typed_data';

import 'chat_turn.dart';
import 'exchange.dart';
import 'style_profile.dart';

/// Where a stored exchange came from.
enum ExchangeSource {
  /// Parsed out of a WhatsApp export.
  export,

  /// A suggestion you starred as one you actually sent.
  saved,
}

/// An [Exchange] as it lives in the local database, with its embedding.
class StoredExchange {
  const StoredExchange({
    required this.id,
    required this.context,
    required this.contextText,
    required this.replyText,
    required this.vector,
    this.timestamp,
    this.chatId = -1,
    this.hash = '',
    this.source = ExchangeSource.export,
  });

  /// Row id; -1 before insertion.
  final int id;

  /// The chat this belongs to; -1 before insertion.
  final int chatId;

  /// The turns leading up to the reply, oldest first.
  final List<ChatTurn> context;

  /// Exactly the text that was embedded.
  final String contextText;

  final String replyText;

  /// Unit-length embedding, so cosine similarity is a plain dot product.
  final Float32List vector;

  final DateTime? timestamp;

  /// Identifies the exchange's content, so re-importing an export only embeds
  /// what is new. See [contentHash].
  final String hash;

  final ExchangeSource source;

  StoredExchange copyWith({int? id, int? chatId}) => StoredExchange(
    id: id ?? this.id,
    chatId: chatId ?? this.chatId,
    context: context,
    contextText: contextText,
    replyText: replyText,
    vector: vector,
    timestamp: timestamp,
    hash: hash,
    source: source,
  );

  /// A stable fingerprint of an exchange's text: 64-bit FNV-1a over the
  /// context, a separator, and the reply.
  ///
  /// Not cryptographic, and it doesn't need to be: it only has to tell apart
  /// exchanges within one person's chat, where a collision costs one skipped
  /// example.
  static String contentHash(String contextText, String replyText) {
    // FNV-1a 64-bit, split into two 32-bit halves so it behaves the same on
    // every platform Dart runs on.
    var hi = 0xcbf29ce4;
    var lo = 0x84222325;
    for (final byte in utf8.encode('$contextText\u0000$replyText')) {
      lo ^= byte;
      // Multiply the 64-bit value (hi:lo) by the FNV prime 0x100000001b3.
      final loTimes = lo * 0x1b3;
      final carry = loTimes ~/ 0x100000000;
      final newLo = loTimes & 0xffffffff;
      final newHi = (hi * 0x1b3 + (lo << 8) + carry) & 0xffffffff;
      hi = newHi;
      lo = newLo;
    }
    return hi.toRadixString(16).padLeft(8, '0') +
        lo.toRadixString(16).padLeft(8, '0');
  }

  static String hashOf(Exchange exchange) =>
      contentHash(exchange.contextText, exchange.replyText);
}

/// A [StoredExchange] together with how similar it was to the query.
class ScoredExchange {
  const ScoredExchange({required this.exchange, required this.similarity});

  final StoredExchange exchange;

  /// Cosine similarity in [-1, 1].
  final double similarity;
}

/// One learned conversation: whose chat it is, what it was built with, and
/// whether generation draws on it.
///
/// Shown as a checkable row on the home screen, so you can choose which of
/// your voices a reply is written in — how you text a partner is not how you
/// text your manager.
class ChatMemory {
  const ChatMemory({
    this.id = -1,
    required this.myName,
    required this.theirName,
    required this.embeddingModel,
    required this.dimensions,
    required this.builtAt,
    this.exchangeCount = 0,
    this.savedCount = 0,
    this.enabled = true,
    this.profile = StyleProfile.empty,
  });

  /// Row id; -1 before insertion.
  final int id;

  final String myName;
  final String theirName;
  final String embeddingModel;
  final int dimensions;

  /// When an export was last imported into it.
  final DateTime builtAt;

  /// Exchanges stored, including [savedCount].
  final int exchangeCount;

  /// Exchanges added by starring a suggestion rather than from an export.
  final int savedCount;

  /// Whether generation retrieves from this chat.
  final bool enabled;

  /// How you write in this chat, measured from the export.
  final StyleProfile profile;

  bool get isEmpty => exchangeCount == 0;

  /// Whether this chat's vectors can be compared with a query embedded using
  /// [model] at [dims].
  bool matches(String model, int dims) =>
      embeddingModel == model && dimensions == dims;

  ChatMemory copyWith({
    int? id,
    String? myName,
    String? theirName,
    String? embeddingModel,
    int? dimensions,
    DateTime? builtAt,
    int? exchangeCount,
    int? savedCount,
    bool? enabled,
    StyleProfile? profile,
  }) => ChatMemory(
    id: id ?? this.id,
    myName: myName ?? this.myName,
    theirName: theirName ?? this.theirName,
    embeddingModel: embeddingModel ?? this.embeddingModel,
    dimensions: dimensions ?? this.dimensions,
    builtAt: builtAt ?? this.builtAt,
    exchangeCount: exchangeCount ?? this.exchangeCount,
    savedCount: savedCount ?? this.savedCount,
    enabled: enabled ?? this.enabled,
    profile: profile ?? this.profile,
  );

  @override
  String toString() =>
      'ChatMemory($id: $myName -> $theirName, '
      '$exchangeCount exchanges${enabled ? "" : ", off"})';
}
