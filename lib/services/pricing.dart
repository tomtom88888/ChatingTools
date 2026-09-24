import '../models/api_usage.dart';

/// Rough cost estimation.
///
/// OpenAI's prices change, so these are defaults the user can override in the
/// fine-tuning screen rather than facts. Every number the UI shows from here is
/// labelled as an estimate.
class Pricing {
  const Pricing._();

  /// Characters per token. Real tokenisation varies by language — emoji and
  /// non-Latin scripts cost more — so this is deliberately conservative.
  static const double charactersPerToken = 3.5;

  /// USD per million tokens, checked against OpenAI's pricing page in
  /// September 2026.
  static const double embeddingUsdPerMillionTokens = 0.02;
  static const double fineTuneTrainingUsdPerMillionTokens = 3.0;

  /// Embedding prices by model, per million tokens. Chat model prices change
  /// too often to hard-code, so those are entered in Settings.
  static const Map<String, double> embeddingUsdPerMillionByModel = {
    'text-embedding-3-small': 0.02,
    'text-embedding-3-large': 0.13,
    'text-embedding-ada-002': 0.10,
  };

  /// What a month of usage cost, as far as the known prices allow.
  ///
  /// Embedding costs use [embeddingUsdPerMillionByModel] for [embeddingModel].
  /// Chat costs (reading screenshots, writing replies) need the per-million
  /// prices from Settings; when either is unset those calls are left out and
  /// [UsageCost.complete] is false, so the UI never passes off a partial
  /// figure as the whole bill.
  static UsageCost costOf(
    MonthlyUsage usage, {
    required String embeddingModel,
    double? chatInputUsdPerMillion,
    double? chatOutputUsdPerMillion,
  }) {
    var usd = 0.0;
    var complete = true;

    final embedding = usage[UsageKind.embedding];
    if (embedding.requests > 0) {
      final price = embeddingUsdPerMillionByModel[embeddingModel];
      if (price == null) {
        complete = false;
      } else {
        usd += Pricing.usd(embedding.inputTokens, price);
      }
    }

    for (final kind in [UsageKind.vision, UsageKind.generation]) {
      final totals = usage[kind];
      if (totals.requests == 0) continue;
      if (chatInputUsdPerMillion == null || chatOutputUsdPerMillion == null) {
        complete = false;
        continue;
      }
      usd +=
          Pricing.usd(totals.inputTokens, chatInputUsdPerMillion) +
          Pricing.usd(totals.outputTokens, chatOutputUsdPerMillion);
    }
    return UsageCost(usd: usd, complete: complete);
  }

  static int estimateTokens(String text) =>
      (text.length / charactersPerToken).ceil();

  static int estimateTokensForAll(Iterable<String> texts) =>
      texts.fold(0, (sum, text) => sum + estimateTokens(text));

  static double usd(int tokens, double usdPerMillionTokens) =>
      tokens / 1000000 * usdPerMillionTokens;

  /// Formats a USD amount for display, never rounding a real cost down to
  /// "$0.00" — a non-zero cost always reads as at least "<$0.01".
  static String formatUsd(double amount) {
    if (amount <= 0) return r'$0.00';
    if (amount < 0.01) return r'<$0.01';
    return '\$${amount.toStringAsFixed(2)}';
  }
}

/// The result of [Pricing.costOf].
class UsageCost {
  const UsageCost({required this.usd, required this.complete});

  final double usd;

  /// False when some calls could not be priced.
  final bool complete;
}
