import 'dart:convert';

import '../models/app_settings.dart';
import '../models/chat_turn.dart';
import '../models/extracted_message.dart';
import '../models/reply_suggestion.dart';
import '../models/stored_exchange.dart';
import '../models/style_profile.dart';
import 'openai_exception.dart';
import 'openai_service.dart';

/// A one-tap adjustment to a single suggestion.
enum Refinement {
  shorter,
  warmer,
  moreLikeMe;

  String get label => switch (this) {
    shorter => 'Shorter',
    warmer => 'Warmer',
    moreLikeMe => 'More like me',
  };

  /// What the model is asked to change, and nothing else.
  String instruction(String me) => switch (this) {
    shorter =>
      'Make it shorter — cut it down to what $me would actually bother to '
          'type, keeping the meaning.',
    warmer =>
      'Make it warmer and friendlier, the way $me is when they are in a good '
          'mood with this person. Do not make it longer than it needs to be.',
    moreLikeMe =>
      'It does not sound enough like $me. Rewrite it to match the examples '
          'and the measured habits more closely — their length, casing, '
          'punctuation, slang and emoji — even if that makes it rougher.',
  };
}

/// Writes the next message as you, using your retrieved real replies as the
/// only style reference.
class ReplyGenerator {
  const ReplyGenerator({required this.openai});

  final OpenAiService openai;

  /// Turns the screenshot transcription into turns, merging consecutive
  /// messages from the same side exactly as training did.
  static List<ChatTurn> turnsFrom(
    List<ExtractedMessage> messages, {
    required String myName,
    required String theirName,
  }) {
    final turns = <ChatTurn>[];
    final buffer = <String>[];
    Speaker? current;

    void flush() {
      if (current == null || buffer.isEmpty) return;
      turns.add(
        ChatTurn(
          sender: current == Speaker.me ? myName : theirName,
          text: buffer.join('\n'),
          messageCount: buffer.length,
        ),
      );
      buffer.clear();
    }

    for (final message in messages) {
      if (message.text.trim().isEmpty) continue;
      if (current != message.speaker) {
        flush();
        current = message.speaker;
      }
      buffer.add(message.text);
    }
    flush();
    return turns;
  }

  /// Generates [AppSettings.variantCount] candidate replies.
  ///
  /// With a fine-tuned model the style already lives in the weights and the
  /// model was trained to emit a bare reply, so variants come from separate
  /// plain calls. With a base model one JSON-mode call returns all the variants
  /// at once, which is cheaper and gives the model a reason to make them
  /// genuinely different from each other.
  Future<List<ReplySuggestion>> generate({
    required List<ChatTurn> conversation,
    required List<ScoredExchange> examples,
    required AppSettings settings,
    String note = '',
    StyleProfile profile = StyleProfile.empty,
  }) async {
    if (conversation.isEmpty) {
      throw const OpenAiException(
        OpenAiErrorKind.badRequest,
        'There is nothing to reply to yet.',
      );
    }
    if (conversation.last.sender == settings.myName) {
      throw const OpenAiException(
        OpenAiErrorKind.badRequest,
        'The last message in the screenshot is yours, so there is nothing to '
        'reply to. Check the sides are right and try again.',
      );
    }

    final usingFineTune =
        settings.mode == TrainingMode.fineTune && settings.hasFineTunedModel;
    final model = settings.effectiveGenerationModel;
    final systemPrompt = buildSystemPrompt(settings);

    if (usingFineTune) {
      // A fine-tuned model was trained to emit one bare reply, so each variant
      // is its own call and the topic change is asked for explicitly on the
      // last one rather than through a schema.
      final variants = <ReplySuggestion>[];
      for (var i = 0; i < settings.variantCount; i++) {
        final wantsNewTopic =
            settings.variantCount > 1 && i == settings.variantCount - 1;
        final reply = await openai.chat(
          model: model,
          messages: [
            {'role': 'system', 'content': systemPrompt},
            {
              'role': 'user',
              'content': buildUserPrompt(
                conversation: conversation,
                examples: examples,
                settings: settings,
                note: note,
                profile: profile,
                askForJson: false,
                askForNewTopic: wantsNewTopic,
              ),
            },
          ],
          temperature: 0.9,
          maxOutputTokens: 400,
        );
        variants.add(
          ReplySuggestion(
            text: _tidy(reply),
            kind: wantsNewTopic
                ? SuggestionKind.newTopic
                : SuggestionKind.reply,
          ),
        );
      }
      return _deduplicate(variants);
    }

    final raw = await openai.chat(
      model: model,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {
          'role': 'user',
          'content': buildUserPrompt(
            conversation: conversation,
            examples: examples,
            settings: settings,
            note: note,
            profile: profile,
            askForJson: true,
          ),
        },
      ],
      temperature: 0.9,
      maxOutputTokens: 800,
      jsonMode: true,
    );
    return parseVariants(raw, expected: settings.variantCount);
  }

  /// Rewrites one suggestion according to [refinement], keeping what it is
  /// for: a topic change stays a topic change.
  Future<ReplySuggestion> refine({
    required ReplySuggestion suggestion,
    required Refinement refinement,
    required List<ChatTurn> conversation,
    required List<ScoredExchange> examples,
    required AppSettings settings,
    String note = '',
    StyleProfile profile = StyleProfile.empty,
  }) async {
    final me = _name(settings.myName, 'the user');
    final prompt = StringBuffer()
      ..write(
        buildUserPrompt(
          conversation: conversation,
          examples: examples,
          settings: settings,
          note: note,
          profile: profile,
          askForJson: false,
          askForNewTopic: suggestion.isNewTopic,
        ),
      )
      ..writeln()
      ..writeln('--- a draft of that message ---')
      ..writeln(suggestion.text)
      ..writeln()
      ..writeln(refinement.instruction(me))
      ..write('Output only the rewritten message.');

    final raw = await openai.chat(
      model: settings.effectiveGenerationModel,
      messages: [
        {'role': 'system', 'content': buildSystemPrompt(settings)},
        {'role': 'user', 'content': prompt.toString()},
      ],
      temperature: 0.8,
      maxOutputTokens: 400,
    );
    final text = _tidy(raw);
    if (text.isEmpty) {
      throw const OpenAiException(
        OpenAiErrorKind.badResponse,
        'The model returned an empty rewrite. Try again.',
      );
    }
    return suggestion.copyWith(text: text);
  }

  /// The system prompt, with the two names filled in.
  ///
  /// The wording comes from settings so it can be edited in the app; the
  /// default names every trait a model would otherwise smooth away, because
  /// one told only "match my style" writes polished, punctuated, assistant
  /// prose.
  static String buildSystemPrompt(AppSettings settings) {
    final me = settings.myName.isEmpty ? 'the user' : settings.myName;
    final them = settings.theirName.isEmpty
        ? 'someone they know'
        : settings.theirName;
    return settings.effectiveSystemPrompt
        .replaceAll('{me}', me)
        .replaceAll('{them}', them);
  }

  /// The user prompt: retrieved real exchanges, the live conversation, the
  /// user's own note, and what to produce.
  static String buildUserPrompt({
    required List<ChatTurn> conversation,
    required List<ScoredExchange> examples,
    required AppSettings settings,
    required bool askForJson,
    String note = '',
    bool askForNewTopic = false,
    StyleProfile profile = StyleProfile.empty,
  }) {
    final buffer = StringBuffer();
    final me = _name(settings.myName, 'the user');

    if (examples.isNotEmpty) {
      buffer.writeln(
        'Real past exchanges from this chat, most similar to the current one '
        'first. The reply line is what ${_name(settings.myName, "you")} '
        'actually sent:',
      );
      buffer.writeln();
      for (var i = 0; i < examples.length; i++) {
        final example = examples[i];
        buffer.writeln('--- example ${i + 1} ---');
        buffer.writeln(example.exchange.contextText);
        buffer.writeln(
          '${_name(settings.myName, "You")} replied: '
          '${example.exchange.replyText}',
        );
        buffer.writeln();
      }
    } else {
      buffer.writeln(
        'No past examples are available, so write plainly and briefly, the way '
        'people text.',
      );
      buffer.writeln();
    }

    final measured = profile.describe(me);
    if (measured.isNotEmpty) {
      buffer.writeln('--- how $me texts, in numbers ---');
      buffer.writeln(measured);
      buffer.writeln(
        'Stay inside these habits: a reply much longer, tidier or more '
        'punctuated than this is out of character.',
      );
      buffer.writeln();
    }

    final recent = conversation.length > settings.contextTurns
        ? conversation.sublist(conversation.length - settings.contextTurns)
        : conversation;

    buffer.writeln('--- the conversation right now ---');
    for (final turn in recent) {
      buffer.writeln('${turn.sender}: ${turn.text}');
    }
    buffer.writeln();

    // The note is the one place the user speaks directly to the model, so it
    // outranks the examples where the two disagree - the examples describe how
    // they write, the note says what they want to say this time.
    if (note.trim().isNotEmpty) {
      buffer.writeln('--- what $me wants this message to do ---');
      buffer.writeln(note.trim());
      buffer.writeln();
      buffer.writeln(
        'Follow that note. It decides what the message says; the examples only '
        'decide how it is written. Do not quote the note back.',
      );
      buffer.writeln();
    }

    final bubbles = _bubbleGuidance(profile, me);

    if (askForJson) {
      final count = settings.variantCount;
      buffer.writeln('Write the next message as $me. Give $count options.');
      if (count > 1) {
        buffer.writeln(
          '- ${count - 1} of them answer what was just said.\n'
          '- Exactly one of them does not answer: it moves the conversation '
          'on to a different subject, the way $me would change the topic. It '
          'still has to sound like $me and fit where the chat has got to.',
        );
      }
      buffer.writeln(
        'Vary the length and the angle, not just the wording. Respond with '
        'JSON only, of the form {"replies": [{"kind": "reply", "text": "..."}, '
        '{"kind": "new_topic", "text": "..."}]}, and put nothing but the '
        'message text in each "text".',
      );
      if (bubbles.isNotEmpty) buffer.writeln(bubbles);
    } else if (askForNewTopic) {
      buffer.writeln(
        'Write the next message as $me, but do not answer what was just said '
        '\u2014 move the conversation on to a different subject, the way $me '
        'would change the topic. Output only the message itself.',
      );
      if (bubbles.isNotEmpty) buffer.writeln(bubbles);
    } else {
      buffer.writeln(
        'Write the next message as $me. Output only the message itself.',
      );
      if (bubbles.isNotEmpty) buffer.writeln(bubbles);
    }
    return buffer.toString().trimRight();
  }

  /// Whether to split a message into bubbles, from how often [me] does.
  ///
  /// A line break in the output means a separate bubble, which the app lets
  /// you copy one at a time.
  static String _bubbleGuidance(StyleProfile profile, String me) {
    if (profile.turns < 5) return '';
    final share = profile.multiBubbleShare;
    if (share >= 0.15) {
      return '$me sends several bubbles in a row ${(share * 100).round()}% '
          'of the time, about ${profile.bubblesPerReply.toStringAsFixed(1)} '
          'per reply. When $me would split a message, put each bubble on its '
          'own line; a line break means a separate bubble.';
    }
    return '$me almost always sends one bubble at a time, so keep each '
        'message to a single bubble with no line breaks.';
  }

  static String _name(String name, String fallback) =>
      name.isEmpty ? fallback : name;

  /// Validates the JSON-mode reply and returns the typed suggestions.
  ///
  /// Accepts the documented shape, a bare array, and plain strings, because a
  /// model that ignores the schema should still produce something usable
  /// rather than an error.
  static List<ReplySuggestion> parseVariants(
    String raw, {
    required int expected,
  }) {
    final cleaned = _stripFence(raw);
    Object? decoded;
    try {
      decoded = jsonDecode(cleaned);
    } on FormatException {
      decoded = null;
    }

    Object? list;
    if (decoded is Map) {
      list = decoded['replies'] ?? decoded['options'] ?? decoded['messages'];
    } else if (decoded is List) {
      list = decoded;
    }

    final variants = <ReplySuggestion>[];
    if (list is List) {
      for (final entry in list) {
        if (entry is String) {
          final text = _tidy(entry);
          if (text.isNotEmpty) variants.add(ReplySuggestion.reply(text));
        } else if (entry is Map) {
          final text = _tidy(
            entry['text'] as String? ?? entry['reply'] as String? ?? '',
          );
          if (text.isNotEmpty) {
            variants.add(
              ReplySuggestion(
                text: text,
                kind: SuggestionKind.parse(entry['kind'] ?? entry['type']),
              ),
            );
          }
        }
      }
    } else {
      // The model ignored the format entirely. Rather than failing, treat the
      // whole answer as one usable reply.
      final single = _tidy(cleaned);
      if (single.isNotEmpty) variants.add(ReplySuggestion.reply(single));
    }

    if (variants.isEmpty) {
      throw const OpenAiException(
        OpenAiErrorKind.badResponse,
        'The model did not return any replies. Try again.',
      );
    }

    final unique = _deduplicate(variants);
    final capped = unique.length > expected
        ? unique.sublist(0, expected)
        : unique;
    return _atMostOneNewTopic(capped);
  }

  /// Keeps the first topic change and demotes any others.
  ///
  /// Nothing is promoted: labelling a plain reply as a topic change to make
  /// the set look right would be a lie about what the model produced.
  static List<ReplySuggestion> _atMostOneNewTopic(
    List<ReplySuggestion> variants,
  ) {
    var seen = false;
    return [
      for (final variant in variants)
        if (!variant.isNewTopic)
          variant
        else if (!seen)
          (() {
            seen = true;
            return variant;
          })()
        else
          variant.copyWith(kind: SuggestionKind.reply),
    ];
  }

  static List<ReplySuggestion> _deduplicate(List<ReplySuggestion> variants) {
    final seen = <String>{};
    final out = <ReplySuggestion>[];
    for (final variant in variants) {
      if (variant.text.isEmpty) continue;
      if (seen.add(variant.text.toLowerCase())) out.add(variant);
    }
    return out;
  }

  /// Strips the quotes and labels models like to wrap a single message in.
  static String _tidy(String reply) {
    var out = reply.trim();
    out = out.replaceFirst(
      RegExp(r'^(?:reply|message|option \d+)\s*:\s*', caseSensitive: false),
      '',
    );
    if (out.length > 1) {
      const pairs = {'"': '"', "'": "'", '\u201c': '\u201d'};
      final closing = pairs[out[0]];
      if (closing != null && out.endsWith(closing)) {
        out = out.substring(1, out.length - 1);
      }
    }
    return out.trim();
  }

  static String _stripFence(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('```')) return trimmed;
    final newline = trimmed.indexOf('\n');
    if (newline == -1) return trimmed;
    var inner = trimmed.substring(newline + 1);
    final close = inner.lastIndexOf('```');
    if (close != -1) inner = inner.substring(0, close);
    return inner.trim();
  }
}
