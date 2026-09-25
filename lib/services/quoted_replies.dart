import '../models/extracted_message.dart';

/// Separates a WhatsApp reply from the message it quotes.
///
/// A reply bubble carries a small box at its top showing the message being
/// replied to — its sender's name and its text, often cut short with "…".
/// Vision models are asked to put that in a separate `quoted` field, but they
/// don't always manage it, and then the bubble comes back as
/// "{quoted message} {my reply}". Left like that, the model writing the next
/// message sees words you never sent as yours.
///
/// [clean] removes such a quote from the front of a message when it matches
/// the `quoted` field the model did return, or a message earlier in the same
/// screenshot, and records it in [ExtractedMessage.quoted] instead.
class QuotedReplies {
  const QuotedReplies._();

  /// A quote this short matching an earlier message could just be you
  /// starting with the same word ("ok", "haha"), so it is only stripped when
  /// the quote sits on its own line.
  static const int _minInlineQuote = 8;

  /// The longest line taken to be the quoted sender's name.
  static const int _maxNameLine = 30;

  static final RegExp _ellipsis = RegExp(r'(?:…|\.\.\.)\s*$');
  static final RegExp _wordChar = RegExp(r'^[\p{L}\p{N}]', unicode: true);

  static List<ExtractedMessage> clean(List<ExtractedMessage> messages) {
    final out = <ExtractedMessage>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (_isStrayQuoteBox(message, i, messages, out)) continue;
      out.add(_cleanOne(message, out));
    }
    return out;
  }

  /// The quote box transcribed as a bubble of its own: it repeats an earlier
  /// message word for word, and the next bubble says it quotes exactly that.
  static bool _isStrayQuoteBox(
    ExtractedMessage message,
    int index,
    List<ExtractedMessage> all,
    List<ExtractedMessage> kept,
  ) {
    if (index + 1 >= all.length) return false;
    final next = all[index + 1].quoted?.trim();
    final text = message.text.trim();
    if (next == null || next.isEmpty) return false;
    final core = next.replaceFirst(_ellipsis, '').trimRight();
    if (text != next && text != core) return false;
    return kept.any((e) => e.text.trim().startsWith(core));
  }

  static ExtractedMessage _cleanOne(
    ExtractedMessage message,
    List<ExtractedMessage> earlier,
  ) {
    final text = message.text.trim();
    final explicit = message.quoted;
    final candidates = <({String quote, bool trusted})>[
      if (explicit != null && explicit.trim().isNotEmpty)
        (quote: explicit.trim(), trusted: true),
      // Most recent first: a reply usually quotes something just above it.
      for (final e in earlier.reversed)
        if (e.text.trim().isNotEmpty) (quote: e.text.trim(), trusted: false),
    ];
    if (candidates.isEmpty) return message;

    // The quote may be preceded by a line with its sender's name.
    final starts = <int>[0];
    final firstBreak = text.indexOf('\n');
    if (firstBreak > 0 && firstBreak <= _maxNameLine) {
      starts.add(firstBreak + 1);
    }

    for (final start in starts) {
      final body = text.substring(start);
      for (final candidate in candidates) {
        final rest = _afterQuote(body, candidate.quote, candidate.trusted);
        // With a name line, only a real match counts, never the name alone.
        if (rest != null && rest.isNotEmpty) {
          return ExtractedMessage(
            speaker: message.speaker,
            text: rest,
            quoted: explicit ?? candidate.quote,
            author: message.author,
          );
        }
      }
    }
    return message;
  }

  /// What follows [quote] at the start of [body], or `null` if it isn't there.
  static String? _afterQuote(String body, String quote, bool trusted) {
    // The quote box shows the start of a long message and cuts it with "…".
    final truncated = _ellipsis.hasMatch(quote);
    final core = quote.replaceFirst(_ellipsis, '').trimRight();
    if (core.isEmpty) return null;

    String? rest;
    if (body.startsWith(core)) {
      rest = body.substring(core.length);
      if (truncated || rest.startsWith('…') || rest.startsWith('...')) {
        rest = rest.replaceFirst(RegExp(r'^\s*(?:…|\.\.\.)'), '');
      }
    } else {
      // The bubble shows a cut-down quote of a full earlier message: its first
      // line ends in "…" and is the start of that message.
      final lineEnd = body.indexOf('\n');
      if (lineEnd <= 0) return null;
      final line = body.substring(0, lineEnd);
      if (!_ellipsis.hasMatch(line)) return null;
      final shown = line.replaceFirst(_ellipsis, '').trimRight();
      if (shown.length < _minInlineQuote || !core.startsWith(shown)) {
        return null;
      }
      return body.substring(lineEnd + 1).trim();
    }

    final onOwnLine = rest.startsWith('\n') || rest.startsWith('\r');
    if (!trusted && !onOwnLine && core.length < _minInlineQuote) return null;
    // Mid-word is not a quote boundary: "okay" does not start with quote "ok".
    if (!onOwnLine && rest.isNotEmpty && _wordChar.hasMatch(rest)) return null;
    return rest.trim();
  }
}
