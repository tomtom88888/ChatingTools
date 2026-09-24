import 'dart:math' as math;

import '../models/style_profile.dart';

/// Holds drafts to the habits measured from your real replies.
///
/// Models capitalise, punctuate and elaborate by reflex, even when every
/// example in front of them does none of it. Two things counter that, both
/// driven only by [StyleProfile] numbers and only where they are clear-cut:
///
/// - [conform] fixes the reflexes directly: a capital you almost never use,
///   a full stop you almost never type, emoji you never send.
/// - [distance] scores how far a draft sits from your usual length, bubble
///   count and emoji use, so the closest drafts can be kept.
///
/// With too few replies measured to be sure, both leave drafts alone.
class StyleConformer {
  const StyleConformer._();

  /// Fewer replies than this, and the habits are not trusted.
  static const int minimumReplies = 20;

  /// "Almost always" and "almost never", as shares of your replies.
  static const double usually = 0.8;
  static const double rarely = 0.1;

  static final RegExp _emoji = RegExp(
    r'(?:[\u{1F1E6}-\u{1F1FF}]{2}|[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]'
    r'(?:\u{FE0F})?(?:[\u{1F3FB}-\u{1F3FF}])?'
    r'(?:\u{200D}[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}](?:\u{FE0F})?)*)',
    unicode: true,
  );
  static final RegExp _space = RegExp(r'\s+');

  /// [text] with the reflexes you don't share taken out, bubble by bubble.
  static String conform(String text, StyleProfile profile) {
    if (profile.turns < minimumReplies) return text;
    final bubbles = text
        .split('\n')
        .map((line) => _conformBubble(line.trim(), profile))
        .where((line) => line.isNotEmpty)
        .toList();
    return bubbles.isEmpty ? text : bubbles.join('\n');
  }

  static String _conformBubble(String bubble, StyleProfile profile) {
    var out = bubble;
    if (profile.emojiShare <= rarely / 3) {
      out = out.replaceAll(_emoji, '').replaceAll(_space, ' ').trim();
    }
    if (profile.fullStopShare <= rarely &&
        out.endsWith('.') &&
        !out.endsWith('..')) {
      out = out.substring(0, out.length - 1).trimRight();
    }
    if (profile.lowercaseShare >= usually) out = _lowerFirst(out);
    return out;
  }

  /// Lowercases the first letter, unless the first word is "I", an acronym,
  /// or looks like a name you'd capitalise anyway.
  static String _lowerFirst(String text) {
    if (text.isEmpty) return text;
    final firstWord = text.split(_space).first;
    // "I", "I'm", "I’ll": the pronoun keeps its capital.
    if (RegExp(r"^I(?:$|['’])").hasMatch(firstWord)) return text;
    final letters = firstWord.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters.isEmpty) return text;
    if (letters.length > 1 && letters == letters.toUpperCase()) return text;
    final first = text[0];
    if (first.toUpperCase() != first || first.toLowerCase() == first) {
      return text;
    }
    return first.toLowerCase() + text.substring(1);
  }

  /// How unlike your usual reply [text] is: 0 is typical, higher is further
  /// off. Length counts most, then bubbles and emoji.
  static double distance(String text, StyleProfile profile) {
    if (profile.turns < minimumReplies) return 0;
    final words = text.trim().split(_space).where((w) => w.isNotEmpty).length;
    final median = profile.medianWords;
    final spread = math.max(2, profile.longWords - median);
    var score = (words - median).abs() / spread;
    // Longer than nine in ten of your replies is worse than being short.
    if (words > profile.longWords) score += 1;

    final bubbles = '\n'.allMatches(text.trim()).length + 1;
    if (bubbles > 1 && profile.multiBubbleShare < rarely) score += 1;
    if (bubbles == 1 && profile.multiBubbleShare > 0.5 && words > median) {
      score += 0.5;
    }

    final hasEmoji = _emoji.hasMatch(text);
    if (hasEmoji && profile.emojiShare < rarely) score += 0.5;
    if (!hasEmoji && profile.emojiShare > 0.6) score += 0.25;
    return score;
  }

  /// [drafts] closest to your habits first, ties in their original order.
  static List<String> rank(List<String> drafts, StyleProfile profile) {
    final indexed =
        [
          for (var i = 0; i < drafts.length; i++)
            (i: i, text: drafts[i], score: distance(drafts[i], profile)),
        ]..sort((a, b) {
          final byScore = a.score.compareTo(b.score);
          return byScore != 0 ? byScore : a.i.compareTo(b.i);
        });
    return [for (final d in indexed) d.text];
  }
}
