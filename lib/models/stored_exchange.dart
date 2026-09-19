import 'dart:typed_data';

import 'chat_turn.dart';
import 'exchange.dart';

/// An [Exchange] as it lives in the local database, with its embedding.
class StoredExchange {
  const StoredExchange({
    required this.id,
    required this.context,
    required this.contextText,
    required this.replyText,
    required this.vector,
    this.timestamp,
  });

  /// Row id; -1 before insertion.
  final int id;

  /// The turns leading up to the reply, oldest first.
  final List<ChatTurn> context;

  /// Exactly the text that was embedded.
  final String contextText;

  final String replyText;

  /// Unit-length embedding, so cosine similarity is a plain dot product.
  final Float32List vector;

  final DateTime? timestamp;

  StoredExchange copyWith({int? id}) => StoredExchange(
    id: id ?? this.id,
    context: context,
    contextText: contextText,
    replyText: replyText,
    vector: vector,
    timestamp: timestamp,
  );
}

/// A [StoredExchange] together with how similar it was to the query.
class ScoredExchange {
  const ScoredExchange({required this.exchange, required this.similarity});

  final StoredExchange exchange;

  /// Cosine similarity in [-1, 1].
  final double similarity;
}

/// What a style memory was built from. Shown on the home screen so it is
/// obvious when the memory is stale.
class StyleMemoryStats {
  const StyleMemoryStats({
    required this.exchangeCount,
    required this.embeddingModel,
    required this.dimensions,
    required this.myName,
    required this.theirName,
    required this.builtAt,
  });

  final int exchangeCount;
  final String embeddingModel;
  final int dimensions;
  final String myName;
  final String theirName;
  final DateTime builtAt;

  bool get isEmpty => exchangeCount == 0;
}
