import 'reply_suggestion.dart';

/// What happened to one set of suggestions: which you took, if any.
///
/// Kept on the phone only. It is the most honest measure the app has of
/// whether the replies sound like you: a copy is a yes, walking away from
/// all of them is a no.
class SuggestionFeedback {
  const SuggestionFeedback({
    required this.at,
    required this.shownKinds,
    this.id = -1,
    this.chatId,
    this.pickedIndex,
    this.pickedText,
    this.refinements = const [],
    this.saved = false,
    this.hadNote = false,
  });

  final int id;
  final DateTime at;

  /// The chat you were replying in, if it was one the app knows.
  final int? chatId;

  /// What each shown option was for, in order.
  final List<SuggestionKind> shownKinds;

  /// Which option was copied, or `null` if none was.
  final int? pickedIndex;

  final String? pickedText;

  /// The tweaks asked for along the way ("shorter", "warmer", ...).
  final List<String> refinements;

  /// Whether the picked option was also starred into the memory.
  final bool saved;

  /// Whether a note steered this set.
  final bool hadNote;

  bool get picked => pickedIndex != null;

  SuggestionKind? get pickedKind {
    final index = pickedIndex;
    if (index == null || index < 0 || index >= shownKinds.length) return null;
    return shownKinds[index];
  }

  Map<String, Object?> toJson() => {
    'shownKinds': [for (final k in shownKinds) k.name],
    'refinements': refinements,
    'hadNote': hadNote,
  };

  static List<SuggestionKind> kindsFromJson(Object? raw) => raw is List
      ? [
          for (final name in raw.whereType<String>())
            SuggestionKind.values.firstWhere(
              (k) => k.name == name,
              orElse: () => SuggestionKind.reply,
            ),
        ]
      : const [];
}

/// Totals over a run of [SuggestionFeedback], for the style report.
class FeedbackSummary {
  const FeedbackSummary({
    required this.sets,
    required this.picked,
    required this.newTopicShown,
    required this.newTopicPicked,
    required this.saved,
    required this.pickedByPosition,
    required this.refinements,
  });

  factory FeedbackSummary.of(Iterable<SuggestionFeedback> entries) {
    var sets = 0;
    var picked = 0;
    var newTopicShown = 0;
    var newTopicPicked = 0;
    var saved = 0;
    final byPosition = <int, int>{};
    final refinements = <String, int>{};
    for (final entry in entries) {
      sets++;
      if (entry.shownKinds.contains(SuggestionKind.newTopic)) newTopicShown++;
      if (entry.saved) saved++;
      for (final r in entry.refinements) {
        refinements[r] = (refinements[r] ?? 0) + 1;
      }
      final index = entry.pickedIndex;
      if (index == null) continue;
      picked++;
      byPosition[index] = (byPosition[index] ?? 0) + 1;
      if (entry.pickedKind == SuggestionKind.newTopic) newTopicPicked++;
    }
    return FeedbackSummary(
      sets: sets,
      picked: picked,
      newTopicShown: newTopicShown,
      newTopicPicked: newTopicPicked,
      saved: saved,
      pickedByPosition: byPosition,
      refinements: refinements,
    );
  }

  /// Sets of suggestions shown.
  final int sets;

  /// Sets where one option was copied.
  final int picked;

  final int newTopicShown;
  final int newTopicPicked;

  /// Picks also starred into the memory.
  final int saved;

  /// Picks by the position of the option, zero-based.
  final Map<int, int> pickedByPosition;

  /// How often each tweak was asked for.
  final Map<String, int> refinements;

  bool get isEmpty => sets == 0;

  double get pickRate => sets == 0 ? 0 : picked / sets;

  /// When a topic change was on offer, how often it was the one taken.
  double get newTopicRate =>
      newTopicShown == 0 ? 0 : newTopicPicked / newTopicShown;
}
