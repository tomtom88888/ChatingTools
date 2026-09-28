import 'dart:math' as math;
import 'dart:typed_data';

import '../models/stored_exchange.dart';
import 'vector_math.dart';

/// Chooses which past exchanges the model is shown.
///
/// Plain top-k by similarity tends to return near-copies of each other —
/// eight versions of "ok see you then" — which teaches the model one reply
/// rather than a voice. So selection runs in two stages:
///
/// 1. a shortlist of the most similar exchanges (a heap pass over the chats
///    that are switched on), then
/// 2. maximal marginal relevance over that shortlist: each pick balances how
///    relevant an exchange is against how much it repeats the ones already
///    picked, and exact repeats of a reply already chosen are passed over.
///
/// Relevance gets a small boost for recent exchanges, fading by half every
/// [recencyHalfLife], so the examples lean towards how you text now rather
/// than how you texted years ago. The boost is small enough that a clearly
/// better old match still wins. Exchanges from the chat being replied in get
/// a similar nudge, [preferredChatBoost].
///
/// Weak matches are dropped rather than used to fill the quota: anything
/// under [minSimilarity], or further than [maxGapFromBest] below the best
/// match. A handful of close examples teaches the model more than a full set
/// padded with unrelated ones, which it would dutifully imitate.
class Retrieval {
  const Retrieval({
    this.relevanceWeight = 0.8,
    this.recencyBoost = 0.03,
    this.recencyHalfLife = const Duration(days: 365),
    this.shortlistFactor = 4,
    this.minSimilarity = defaultMinSimilarity,
    this.maxGapFromBest = 0.2,
    this.preferredChatBoost = 0.04,
  });

  /// Below this, two conversations have little more in common than being
  /// text messages.
  static const double defaultMinSimilarity = 0.3;

  /// 1.0 is plain similarity ranking; lower values favour variety.
  final double relevanceWeight;

  /// The least similarity an exchange needs to be used at all.
  final double minSimilarity;

  /// How far below the best match an exchange may be and still be used.
  final double maxGapFromBest;

  /// Added to the relevance of exchanges from the preferred chat.
  final double preferredChatBoost;

  /// The most recency can add to a similarity score.
  final double recencyBoost;

  final Duration recencyHalfLife;

  /// How many candidates per wanted example go through to the second stage.
  final int shortlistFactor;

  /// Up to [limit] of the best exchanges from [candidates] for [query], most
  /// similar first; fewer, or none, when the rest are weak matches.
  /// Exchanges from [preferChatId] rank a little higher.
  ///
  /// Throws [ArgumentError] if a candidate's vector has a different length to
  /// the query: that chat was built with another embedding model.
  List<ScoredExchange> select(
    Float32List query,
    List<StoredExchange> candidates, {
    required int limit,
    DateTime? now,
    int? preferChatId,
  }) {
    if (limit < 1 || candidates.isEmpty) return const [];
    final vectors = [for (final c in candidates) c.vector];
    final ranked = VectorMath.topKScored(
      query,
      vectors,
      math.max(limit, limit * shortlistFactor),
    );
    if (ranked.isEmpty) return const [];
    final best = ranked.map((s) => s.score).reduce(math.max);
    final floor = math.max(minSimilarity, best - maxGapFromBest);
    final shortlist = [
      for (final s in ranked)
        if (s.score >= floor) s,
    ];
    if (shortlist.length <= 1) {
      return [
        for (final s in shortlist)
          ScoredExchange(exchange: candidates[s.index], similarity: s.score),
      ];
    }

    final at = now ?? DateTime.now();
    final relevance = [
      for (final s in shortlist)
        s.score +
            _recency(candidates[s.index].timestamp, at) +
            (preferChatId != null && candidates[s.index].chatId == preferChatId
                ? preferredChatBoost
                : 0),
    ];

    final chosen = <int>[]; // positions in shortlist
    final chosenReplies = <String>{};
    final remaining = List<int>.generate(shortlist.length, (i) => i);
    // Each remaining candidate's highest similarity to anything chosen.
    final redundancy = List<double>.filled(shortlist.length, -1);

    while (chosen.length < limit && remaining.isNotEmpty) {
      var best = -1;
      var bestScore = double.negativeInfinity;
      var bestIsRepeat = true;
      for (final i in remaining) {
        final reply = _normalised(candidates[shortlist[i].index].replyText);
        final isRepeat = chosenReplies.contains(reply);
        final score = chosen.isEmpty
            ? relevance[i]
            : relevanceWeight * relevance[i] -
                  (1 - relevanceWeight) * redundancy[i];
        // A fresh reply always beats a repeat; among equals, the higher score.
        final better = bestIsRepeat && !isRepeat
            ? true
            : (!bestIsRepeat && isRepeat)
            ? false
            : score > bestScore;
        if (best == -1 || better) {
          best = i;
          bestScore = score;
          bestIsRepeat = isRepeat;
        }
      }
      // Only repeats are left: stop rather than pad the prompt with them.
      if (bestIsRepeat && chosen.isNotEmpty) break;

      chosen.add(best);
      remaining.remove(best);
      chosenReplies.add(
        _normalised(candidates[shortlist[best].index].replyText),
      );
      final picked = vectors[shortlist[best].index];
      for (final i in remaining) {
        final overlap = VectorMath.dot(vectors[shortlist[i].index], picked);
        if (overlap > redundancy[i]) redundancy[i] = overlap;
      }
    }

    final out = [
      for (final i in chosen)
        ScoredExchange(
          exchange: candidates[shortlist[i].index],
          similarity: shortlist[i].score,
        ),
    ]..sort((a, b) => b.similarity.compareTo(a.similarity));
    return out;
  }

  double _recency(DateTime? timestamp, DateTime now) {
    if (timestamp == null || recencyBoost == 0) return 0;
    final age = now.difference(timestamp);
    if (age.isNegative) return recencyBoost;
    final halfLives = age.inMinutes / recencyHalfLife.inMinutes;
    return recencyBoost * math.pow(0.5, halfLives);
  }

  static String _normalised(String reply) =>
      reply.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
