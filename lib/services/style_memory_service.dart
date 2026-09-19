import 'dart:typed_data';

import '../models/chat_turn.dart';
import '../models/exchange.dart';
import '../models/parsed_chat.dart';
import '../models/stored_exchange.dart';
import 'exchange_store.dart';
import 'openai_exception.dart';
import 'openai_service.dart';
import 'pricing.dart';
import 'vector_math.dart';
import 'whatsapp_parser.dart';

/// Progress of a style-memory build, for the training screen.
class StyleMemoryProgress {
  const StyleMemoryProgress({
    required this.embedded,
    required this.total,
    required this.stage,
  });

  final int embedded;
  final int total;
  final String stage;

  double get fraction => total == 0 ? 0 : embedded / total;
}

/// What a build would cost and how much data it would use.
class StyleMemoryEstimate {
  const StyleMemoryEstimate({
    required this.exchangeCount,
    required this.estimatedTokens,
    required this.estimatedUsd,
  });

  final int exchangeCount;
  final int estimatedTokens;
  final double estimatedUsd;
}

/// Mode A: builds and queries the local style memory.
///
/// Building embeds every `their turn(s) -> my reply` exchange and stores the
/// vectors on the device. Querying embeds the current conversation and returns
/// the closest past exchanges. Nothing but the text being embedded leaves the
/// phone.
class StyleMemoryService {
  StyleMemoryService({required this.openai, required this.store});

  final OpenAiService openai;
  final ExchangeStore store;

  /// Exchanges per embeddings request. Large enough to keep the round-trip
  /// count low, small enough to stay well inside the request size limit.
  static const int embedBatchSize = 96;

  /// OpenAI's retrieval quality falls off with very short contexts and the
  /// embedding cost is dominated by long ones, so contexts are capped.
  static const int maxContextCharacters = 4000;

  StyleMemoryEstimate estimate(List<Exchange> exchanges) {
    final tokens = Pricing.estimateTokensForAll(
      exchanges.map((e) => _embedText(e.contextText)),
    );
    return StyleMemoryEstimate(
      exchangeCount: exchanges.length,
      estimatedTokens: tokens,
      estimatedUsd: Pricing.usd(tokens, Pricing.embeddingUsdPerMillionTokens),
    );
  }

  /// Turns a parsed export into training exchanges.
  List<Exchange> exchangesFrom(
    ParsedChat chat, {
    required String myName,
    required int contextTurns,
  }) => WhatsAppParser.buildExchanges(
    chat.turns,
    me: myName,
    maxContextTurns: contextTurns,
  );

  /// Embeds every exchange and replaces the stored memory.
  ///
  /// Reports progress after each batch. If [isCancelled] starts returning true
  /// the build stops and the existing memory is left untouched, because
  /// [ExchangeStore.replaceAll] is only called once everything is embedded.
  Future<StyleMemoryStats> build({
    required List<Exchange> exchanges,
    required String myName,
    required String theirName,
    required String embeddingModel,
    required int dimensions,
    void Function(StyleMemoryProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (exchanges.isEmpty) {
      throw const OpenAiException(
        OpenAiErrorKind.badRequest,
        'There are no replies of yours to learn from. Check that you picked '
        'the right name for yourself, and that the export is a chat you '
        'actually replied in.',
      );
    }

    final stored = <StoredExchange>[];
    onProgress?.call(
      StyleMemoryProgress(
        embedded: 0,
        total: exchanges.length,
        stage: 'Embedding ${exchanges.length} exchanges',
      ),
    );

    for (var start = 0; start < exchanges.length; start += embedBatchSize) {
      if (isCancelled?.call() ?? false) {
        throw const StyleMemoryCancelled();
      }
      final end = (start + embedBatchSize).clamp(0, exchanges.length);
      final batch = exchanges.sublist(start, end);
      final vectors = await openai.embed(
        batch.map((e) => _embedText(e.contextText)).toList(growable: false),
        model: embeddingModel,
        dimensions: dimensions,
      );

      for (var i = 0; i < batch.length; i++) {
        final exchange = batch[i];
        stored.add(
          StoredExchange(
            id: -1,
            context: exchange.context,
            contextText: exchange.contextText,
            replyText: exchange.replyText,
            vector: VectorMath.normalise(vectors[i]),
            timestamp: exchange.timestamp,
          ),
        );
      }
      onProgress?.call(
        StyleMemoryProgress(
          embedded: stored.length,
          total: exchanges.length,
          stage: 'Embedding ${exchanges.length} exchanges',
        ),
      );
    }

    final stats = StyleMemoryStats(
      exchangeCount: stored.length,
      embeddingModel: embeddingModel,
      dimensions: stored.first.vector.length,
      myName: myName,
      theirName: theirName,
      builtAt: DateTime.now(),
    );
    onProgress?.call(
      StyleMemoryProgress(
        embedded: stored.length,
        total: exchanges.length,
        stage: 'Saving to this device',
      ),
    );
    await store.replaceAll(stored, stats: stats);
    return stats;
  }

  /// The [limit] past exchanges most similar to the conversation so far.
  Future<List<ScoredExchange>> retrieve({
    required List<ChatTurn> context,
    required String embeddingModel,
    required int dimensions,
    required int limit,
  }) async {
    if (await store.count() == 0) return const [];
    final queryText = _embedText(Exchange.renderContext(context));
    if (queryText.trim().isEmpty) return const [];

    final vectors = await openai.embed(
      [queryText],
      model: embeddingModel,
      dimensions: dimensions,
    );
    final Float32List query = VectorMath.normalise(vectors.first);
    return store.mostSimilar(query, limit: limit);
  }

  /// Keeps the tail of a long context: the most recent turns are what a reply
  /// actually responds to.
  static String _embedText(String contextText) {
    if (contextText.length <= maxContextCharacters) return contextText;
    return contextText.substring(contextText.length - maxContextCharacters);
  }
}

/// Thrown when the user cancels a build.
class StyleMemoryCancelled implements Exception {
  const StyleMemoryCancelled();

  @override
  String toString() => 'Training cancelled.';
}
