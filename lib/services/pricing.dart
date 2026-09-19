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
