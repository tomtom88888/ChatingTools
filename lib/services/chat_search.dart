import 'dart:typed_data';

import '../models/stored_exchange.dart';
import 'exchange_store.dart';
import 'openai_service.dart';
import 'vector_math.dart';

/// One moment found by a search.
class SearchHit {
  const SearchHit({
    required this.exchange,
    required this.score,
    required this.wordMatch,
  });

  final StoredExchange exchange;

  /// Similarity to the query, with a lift for words that match exactly.
  final double score;

  /// Whether every word of the query appears in the moment.
  final bool wordMatch;
}

/// Finds moments in your chats by what they are about, not only by the
/// words in them: "that restaurant she mentioned" finds the evening she
/// raved about a ramen place.
///
/// The query is fingerprinted once (one embedding call) and compared with
/// every stored moment on the phone. A moment containing the query's words
/// gets a lift, so an exact name still comes first.
class ChatSearch {
  ChatSearch({required this.openai, required this.store});

  final OpenAiService openai;
  final ExchangeStore store;

  static const int defaultLimit = 25;

  /// Below this, a moment has too little to do with the query to show.
  static const double minScore = 0.25;

  /// Added when every query word appears in the moment.
  static const double wordBoost = 0.15;

  Future<List<SearchHit>> search(
    String query, {
    required Set<int> chatIds,
    required String embeddingModel,
    required int dimensions,
    int limit = defaultLimit,
  }) async {
    final text = query.trim();
    if (text.isEmpty || chatIds.isEmpty) return const [];
    final candidates = await store.all(chatIds: chatIds);
    if (candidates.isEmpty) return const [];
    final vectors = await openai.embed(
      [text],
      model: embeddingModel,
      dimensions: dimensions,
    );
    return rank(
      VectorMath.normalise(vectors.first),
      text,
      candidates,
      limit: limit,
    );
  }

  /// The best [limit] of [candidates] for a query, best first. Candidates
  /// fingerprinted at another size are skipped.
  static List<SearchHit> rank(
    Float32List query,
    String text,
    List<StoredExchange> candidates, {
    int limit = defaultLimit,
  }) {
    final words = _words(text);
    final hits = <SearchHit>[];
    for (final c in candidates) {
      if (c.vector.length != query.length) continue;
      final haystack = '${c.contextText}\n${c.replyText}'.toLowerCase();
      final matches =
          words.isNotEmpty && words.every((w) => haystack.contains(w));
      final score = VectorMath.dot(query, c.vector) + (matches ? wordBoost : 0);
      if (score < minScore) continue;
      hits.add(SearchHit(exchange: c, score: score, wordMatch: matches));
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList();
  }

  /// The query's words worth matching: three letters or more, so "a" and
  /// "is" don't count.
  static List<String> _words(String text) => [
    for (final w in text.toLowerCase().split(
      RegExp(r'[^\p{L}\p{N}]+', unicode: true),
    ))
      if (w.length >= 3) w,
  ];
}
