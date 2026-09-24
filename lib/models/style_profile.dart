import 'dart:math' as math;

import 'chat_turn.dart';

/// Measurable habits in how you write, counted from your own replies.
///
/// Everything is stored as raw counts rather than percentages, so profiles
/// from several chats merge by adding them together and the derived figures
/// stay correct. Nothing here needs an API call.
class StyleProfile {
  const StyleProfile({
    this.turns = 0,
    this.bubbles = 0,
    this.words = 0,
    this.lengthBuckets = const [],
    this.lowercaseStarts = 0,
    this.fullStopEnds = 0,
    this.turnsWithEmoji = 0,
    this.questions = 0,
    this.multiBubbleTurns = 0,
    this.emoji = const {},
    this.phrases = const {},
  });

  static const StyleProfile empty = StyleProfile();

  /// Word counts above this share the last bucket.
  static const int maxBucket = 60;

  /// How many emoji and phrases are kept; the long tail is noise.
  static const int keepTop = 24;

  /// Replies measured.
  final int turns;

  /// Separate WhatsApp bubbles across those replies.
  final int bubbles;

  final int words;

  /// `lengthBuckets[n]` is how many replies had `n` words, capped at
  /// [maxBucket]. Kept so the median survives a merge.
  final List<int> lengthBuckets;

  /// Replies whose first letter is lowercase.
  final int lowercaseStarts;

  /// Replies ending in a full stop.
  final int fullStopEnds;

  final int turnsWithEmoji;

  /// Replies containing a question mark.
  final int questions;

  /// Replies sent as more than one bubble.
  final int multiBubbleTurns;

  /// Emoji and how often they appear.
  final Map<String, int> emoji;

  /// Short replies you send again and again, with their counts.
  final Map<String, int> phrases;

  bool get isEmpty => turns == 0;

  // ------------------------------------------------------------------ derived

  double _share(int count) => turns == 0 ? 0 : count / turns;

  double get lowercaseShare => _share(lowercaseStarts);
  double get fullStopShare => _share(fullStopEnds);
  double get emojiShare => _share(turnsWithEmoji);
  double get questionShare => _share(questions);
  double get multiBubbleShare => _share(multiBubbleTurns);

  double get bubblesPerReply => turns == 0 ? 1 : bubbles / turns;

  double get meanWords => turns == 0 ? 0 : words / turns;

  /// The word count half your replies are at or under.
  int get medianWords => _percentile(0.5);

  /// The word count nine in ten of your replies are at or under.
  int get longWords => _percentile(0.9);

  int _percentile(double p) {
    if (turns == 0) return 0;
    final target = (turns * p).ceil().clamp(1, turns);
    var seen = 0;
    for (var i = 0; i < lengthBuckets.length; i++) {
      seen += lengthBuckets[i];
      if (seen >= target) return i;
    }
    return lengthBuckets.isEmpty ? 0 : lengthBuckets.length - 1;
  }

  List<MapEntry<String, int>> get topEmoji => _top(emoji);
  List<MapEntry<String, int>> get topPhrases => _top(phrases);

  static List<MapEntry<String, int>> _top(Map<String, int> counts) =>
      (counts.entries.toList()..sort((a, b) {
            final byCount = b.value.compareTo(a.value);
            return byCount != 0 ? byCount : a.key.compareTo(b.key);
          }))
          .toList(growable: false);

  // ------------------------------------------------------------------ building

  /// Measures the replies sent by [me] in [turns].
  static StyleProfile measure(Iterable<ChatTurn> turns, {required String me}) {
    final builder = _Builder();
    for (final turn in turns) {
      if (turn.sender != me) continue;
      builder.add(turn.text, bubbles: turn.messageCount);
    }
    return builder.build();
  }

  /// Measures bare reply texts, one bubble per line.
  static StyleProfile measureTexts(Iterable<String> replies) {
    final builder = _Builder();
    for (final reply in replies) {
      builder.add(reply, bubbles: '\n'.allMatches(reply.trim()).length + 1);
    }
    return builder.build();
  }

  /// Adds two profiles, as if their replies had been measured together.
  StyleProfile merge(StyleProfile other) {
    if (other.isEmpty) return this;
    if (isEmpty) return other;
    final buckets = List<int>.filled(
      math.max(lengthBuckets.length, other.lengthBuckets.length),
      0,
    );
    for (var i = 0; i < buckets.length; i++) {
      buckets[i] =
          (i < lengthBuckets.length ? lengthBuckets[i] : 0) +
          (i < other.lengthBuckets.length ? other.lengthBuckets[i] : 0);
    }
    return StyleProfile(
      turns: turns + other.turns,
      bubbles: bubbles + other.bubbles,
      words: words + other.words,
      lengthBuckets: buckets,
      lowercaseStarts: lowercaseStarts + other.lowercaseStarts,
      fullStopEnds: fullStopEnds + other.fullStopEnds,
      turnsWithEmoji: turnsWithEmoji + other.turnsWithEmoji,
      questions: questions + other.questions,
      multiBubbleTurns: multiBubbleTurns + other.multiBubbleTurns,
      emoji: _addCounts(emoji, other.emoji),
      phrases: _addCounts(phrases, other.phrases),
    );
  }

  static StyleProfile mergeAll(Iterable<StyleProfile> profiles) =>
      profiles.fold(StyleProfile.empty, (sum, p) => sum.merge(p));

  static Map<String, int> _addCounts(Map<String, int> a, Map<String, int> b) {
    final out = Map<String, int>.of(a);
    b.forEach((key, value) => out[key] = (out[key] ?? 0) + value);
    return _keepTop(out);
  }

  static Map<String, int> _keepTop(Map<String, int> counts) {
    if (counts.length <= keepTop) return counts;
    return Map.fromEntries(_top(counts).take(keepTop));
  }

  // ---------------------------------------------------------------- prompting

  /// The profile in plain words, for the generating model.
  ///
  /// Models told only to "match the examples" drift towards longer, tidier
  /// messages; numbers are harder to smooth away than adjectives.
  String describe(String me) {
    if (turns < 5) return '';
    String pct(double share) => '${(share * 100).round()}%';
    final lines = <String>[
      'Measured from $turns of $me\'s real replies:',
      '- length: half are $medianWords '
          '${medianWords == 1 ? "word" : "words"} or fewer, and nine in ten '
          'are $longWords or fewer',
      '- starts with a lowercase letter: ${pct(lowercaseShare)}',
      '- ends with a full stop: ${pct(fullStopShare)}',
      '- contains an emoji: ${pct(emojiShare)}',
      '- asks a question: ${pct(questionShare)}',
      '- sent as several bubbles in a row: ${pct(multiBubbleShare)}',
    ];
    final favourites = topEmoji.take(6).map((e) => e.key).join(' ');
    if (favourites.isNotEmpty) lines.add('- most used emoji: $favourites');
    final said = topPhrases
        .where((e) => e.value >= 3)
        .take(8)
        .map((e) => '"${e.key}"')
        .join(', ');
    if (said.isNotEmpty) lines.add('- things $me says a lot: $said');
    return lines.join('\n');
  }

  // --------------------------------------------------------------- persistence

  Map<String, Object?> toJson() => {
    'turns': turns,
    'bubbles': bubbles,
    'words': words,
    'lengthBuckets': lengthBuckets,
    'lowercaseStarts': lowercaseStarts,
    'fullStopEnds': fullStopEnds,
    'turnsWithEmoji': turnsWithEmoji,
    'questions': questions,
    'multiBubbleTurns': multiBubbleTurns,
    'emoji': emoji,
    'phrases': phrases,
  };

  factory StyleProfile.fromJson(Object? raw) {
    if (raw is! Map) return StyleProfile.empty;
    int n(String key) => (raw[key] as num?)?.toInt() ?? 0;
    Map<String, int> counts(String key) {
      final value = raw[key];
      if (value is! Map) return const {};
      return {
        for (final entry in value.entries)
          if (entry.key is String && entry.value is num)
            entry.key as String: (entry.value as num).toInt(),
      };
    }

    final buckets = raw['lengthBuckets'];
    return StyleProfile(
      turns: n('turns'),
      bubbles: n('bubbles'),
      words: n('words'),
      lengthBuckets: buckets is List
          ? buckets.whereType<num>().map((v) => v.toInt()).toList()
          : const [],
      lowercaseStarts: n('lowercaseStarts'),
      fullStopEnds: n('fullStopEnds'),
      turnsWithEmoji: n('turnsWithEmoji'),
      questions: n('questions'),
      multiBubbleTurns: n('multiBubbleTurns'),
      emoji: counts('emoji'),
      phrases: counts('phrases'),
    );
  }
}

/// Accumulates counts while measuring.
class _Builder {
  int turns = 0;
  int bubbles = 0;
  int words = 0;
  final List<int> buckets = List<int>.filled(StyleProfile.maxBucket + 1, 0);
  int lowercase = 0;
  int fullStops = 0;
  int withEmoji = 0;
  int questions = 0;
  int multi = 0;
  final Map<String, int> emoji = {};
  final Map<String, int> phrases = {};

  static final RegExp _whitespace = RegExp(r'\s+');

  // Pictographs, dingbats, flags and the symbol blocks emoji live in. Skin-tone
  // modifiers and joiners are left attached to the emoji they belong to.
  static final RegExp _emoji = RegExp(
    r'(?:[\u{1F1E6}-\u{1F1FF}]{2}|[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]'
    r'(?:\u{FE0F})?(?:[\u{1F3FB}-\u{1F3FF}])?'
    r'(?:\u{200D}[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}](?:\u{FE0F})?)*)',
    unicode: true,
  );

  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);

  void add(String text, {required int bubbles}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    turns++;
    this.bubbles += math.max(1, bubbles);
    if (bubbles > 1) multi++;

    final wordCount = trimmed.split(_whitespace).where((w) => w.isNotEmpty);
    final count = wordCount.length;
    words += count;
    buckets[math.min(count, StyleProfile.maxBucket)]++;

    final first = _letter.firstMatch(trimmed)?.group(0);
    // Only scripts with case can start lowercase; Hebrew or Chinese can't.
    if (first != null &&
        first != first.toUpperCase() &&
        first == first.toLowerCase()) {
      lowercase++;
    }
    final lastLine = trimmed.split('\n').last.trimRight();
    if (lastLine.endsWith('.') && !lastLine.endsWith('..')) fullStops++;
    if (trimmed.contains('?')) questions++;

    final found = _emoji.allMatches(trimmed).map((m) => m.group(0)!).toList();
    if (found.isNotEmpty) withEmoji++;
    for (final e in found) {
      emoji[e] = (emoji[e] ?? 0) + 1;
    }

    // A "phrase" is a whole short bubble: the "haha"s and "omw"s that make a
    // voice recognisable. Longer bubbles almost never repeat verbatim.
    for (final line in trimmed.split('\n')) {
      final phrase = line.trim().toLowerCase();
      if (phrase.isEmpty || phrase.length > 24) continue;
      if (phrase.split(_whitespace).length > 4) continue;
      phrases[phrase] = (phrases[phrase] ?? 0) + 1;
    }
  }

  StyleProfile build() {
    var last = buckets.length - 1;
    while (last > 0 && buckets[last] == 0) {
      last--;
    }
    return StyleProfile(
      turns: turns,
      bubbles: bubbles,
      words: words,
      lengthBuckets: turns == 0 ? const [] : buckets.sublist(0, last + 1),
      lowercaseStarts: lowercase,
      fullStopEnds: fullStops,
      turnsWithEmoji: withEmoji,
      questions: questions,
      multiBubbleTurns: multi,
      emoji: StyleProfile._keepTop(emoji),
      // Once-off bubbles are kept so they can add up across chats; the prompt
      // and the report only show ones said repeatedly.
      phrases: StyleProfile._keepTop(phrases),
    );
  }
}
