import '../models/extracted_message.dart';

/// Joins what was read off several screenshots of one chat into a single
/// conversation.
///
/// Screenshots taken while scrolling overlap: the bottom of one is the top
/// of the next. The overlap is found by matching messages, and is kept once.
/// The same matching decides the order, so screenshots picked out of order
/// still join up; when nothing overlaps, the order they were picked in is
/// kept.
class ScreenshotStitcher {
  const ScreenshotStitcher._();

  /// Beyond this many parts every order is not tried; they are joined as
  /// given.
  static const int _maxReordered = 5;

  static List<ExtractedMessage> stitch(List<List<ExtractedMessage>> parts) {
    final nonEmpty = [
      for (final p in parts)
        if (p.isNotEmpty) p,
    ];
    if (nonEmpty.isEmpty) return const [];
    if (nonEmpty.length == 1) return List.of(nonEmpty.single);

    final order = nonEmpty.length <= _maxReordered
        ? _bestOrder(nonEmpty)
        : List<int>.generate(nonEmpty.length, (i) => i);

    final out = List.of(nonEmpty[order.first]);
    for (final i in order.skip(1)) {
      final next = nonEmpty[i];
      out.addAll(next.skip(overlap(out, next)));
    }
    return out;
  }

  /// How many messages at the start of [next] repeat the end of [before].
  ///
  /// A bubble cut off at the edge of a screenshot may be read in part, so at
  /// the boundary one text containing the other also counts as a match.
  static int overlap(
    List<ExtractedMessage> before,
    List<ExtractedMessage> next,
  ) {
    final most = before.length < next.length ? before.length : next.length;
    for (var k = most; k > 0; k--) {
      var matches = true;
      for (var j = 0; j < k; j++) {
        final a = before[before.length - k + j];
        final b = next[j];
        final edge = j == 0 || j == k - 1;
        if (!_same(a, b, partial: edge)) {
          matches = false;
          break;
        }
      }
      if (matches) return k;
    }
    return 0;
  }

  /// The order of [parts] that overlaps most; the given order wins ties.
  static List<int> _bestOrder(List<List<ExtractedMessage>> parts) {
    final n = parts.length;
    final pair = List.generate(
      n,
      (a) => List.generate(n, (b) => a == b ? 0 : overlap(parts[a], parts[b])),
    );
    var best = List<int>.generate(n, (i) => i);
    var bestScore = _score(best, pair);
    for (final order in _permutations(n)) {
      final score = _score(order, pair);
      if (score > bestScore) {
        best = order;
        bestScore = score;
      }
    }
    return best;
  }

  static int _score(List<int> order, List<List<int>> pair) {
    var total = 0;
    for (var i = 1; i < order.length; i++) {
      total += pair[order[i - 1]][order[i]];
    }
    return total;
  }

  static Iterable<List<int>> _permutations(int n) sync* {
    final items = List<int>.generate(n, (i) => i);
    Iterable<List<int>> permute(List<int> rest, List<int> prefix) sync* {
      if (rest.isEmpty) {
        yield prefix;
        return;
      }
      for (var i = 0; i < rest.length; i++) {
        yield* permute(
          [...rest.sublist(0, i), ...rest.sublist(i + 1)],
          [...prefix, rest[i]],
        );
      }
    }

    yield* permute(items, const []);
  }

  static bool _same(
    ExtractedMessage a,
    ExtractedMessage b, {
    required bool partial,
  }) {
    if (a.speaker != b.speaker) return false;
    final x = _normalised(a.text);
    final y = _normalised(b.text);
    if (x == y) return x.isNotEmpty;
    if (!partial) return false;
    // A partly read bubble: at least a few words, contained in the other.
    final shorter = x.length < y.length ? x : y;
    final longer = x.length < y.length ? y : x;
    return shorter.length >= 8 && longer.contains(shorter);
  }

  /// Lower case, no punctuation, single spaces. A message of only emoji or
  /// punctuation is compared as it is.
  static String _normalised(String text) {
    final plain = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return plain.isEmpty ? text.trim() : plain;
  }
}
