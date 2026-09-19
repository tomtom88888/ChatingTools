import 'dart:convert';

import '../models/app_settings.dart';
import '../models/chat_turn.dart';
import '../models/extracted_message.dart';
import '../models/stored_exchange.dart';
import 'openai_exception.dart';
import 'openai_service.dart';

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
  Future<List<String>> generate({
    required List<ChatTurn> conversation,
    required List<ScoredExchange> examples,
    required AppSettings settings,
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
    final userPrompt = buildUserPrompt(
      conversation: conversation,
      examples: examples,
      settings: settings,
      askForJson: !usingFineTune,
    );

    if (usingFineTune) {
      final variants = <String>[];
      for (var i = 0; i < settings.variantCount; i++) {
        final reply = await openai.chat(
          model: model,
          messages: [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          temperature: 0.9,
          maxOutputTokens: 400,
        );
        variants.add(_tidy(reply));
      }
      return _deduplicate(variants);
    }

    final raw = await openai.chat(
      model: model,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      temperature: 0.9,
      maxOutputTokens: 800,
      jsonMode: true,
    );
    return parseVariants(raw, expected: settings.variantCount);
  }

  /// The system prompt. Everything the spec asks the model to match is named
  /// explicitly, because a model told only "match my style" defaults to
  /// polished, punctuated, assistant-flavoured prose.
  static String buildSystemPrompt(AppSettings settings) {
    final me = settings.myName.isEmpty ? 'the user' : settings.myName;
    final them = settings.theirName.isEmpty
        ? 'someone they know'
        : settings.theirName;
    return 'You are writing a single WhatsApp message as $me, replying to '
        '$them.\n'
        '\n'
        'Write the way $me actually writes. The examples of real past messages '
        'you are given are the only style reference that matters; copy their:\n'
        '- tone and level of warmth or bluntness\n'
        '- typical message length (usually short)\n'
        '- slang, abbreviations, filler words and in-jokes\n'
        '- emoji use, including using none\n'
        '- capitalisation and punctuation habits, including lowercase starts, '
        'missing full stops and repeated letters\n'
        '- language, and any mixing or switching between languages mid-message\n'
        '\n'
        'Never explain yourself, never add a greeting or sign-off that $me '
        'would not use, and never sound like an assistant. Do not mention that '
        'you are an AI or that you were given examples.';
  }

  /// The user prompt: retrieved real exchanges, then the live conversation.
  static String buildUserPrompt({
    required List<ChatTurn> conversation,
    required List<ScoredExchange> examples,
    required AppSettings settings,
    required bool askForJson,
  }) {
    final buffer = StringBuffer();

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

    final recent = conversation.length > settings.contextTurns
        ? conversation.sublist(conversation.length - settings.contextTurns)
        : conversation;

    buffer.writeln('--- the conversation right now ---');
    for (final turn in recent) {
      buffer.writeln('${turn.sender}: ${turn.text}');
    }
    buffer.writeln();

    if (askForJson) {
      buffer.writeln(
        'Write the next message as ${_name(settings.myName, "the user")}. '
        'Give ${settings.variantCount} genuinely different options — vary the '
        'length and the angle, not just the wording. Respond with JSON only, '
        'of the form {"replies": ["...", "..."]}, and put nothing but the '
        'message text in each string.',
      );
    } else {
      buffer.writeln(
        'Write the next message as ${_name(settings.myName, "the user")}. '
        'Output only the message itself.',
      );
    }
    return buffer.toString();
  }

  static String _name(String name, String fallback) =>
      name.isEmpty ? fallback : name;

  /// Validates the JSON-mode reply and returns the variants.
  static List<String> parseVariants(String raw, {required int expected}) {
    final cleaned = _stripFence(raw);
    Object? decoded;
    try {
      decoded = jsonDecode(cleaned);
    } on FormatException {
      decoded = null;
    }

    final List<String> variants;
    if (decoded is Map && decoded['replies'] is List) {
      variants = (decoded['replies'] as List)
          .whereType<String>()
          .map(_tidy)
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (decoded is List) {
      variants = decoded
          .whereType<String>()
          .map(_tidy)
          .where((s) => s.isNotEmpty)
          .toList();
    } else {
      // The model ignored the format. Rather than failing, treat the whole
      // answer as one usable reply.
      final single = _tidy(cleaned);
      variants = single.isEmpty ? const [] : [single];
    }

    if (variants.isEmpty) {
      throw const OpenAiException(
        OpenAiErrorKind.badResponse,
        'The model did not return any replies. Try again.',
      );
    }
    final unique = _deduplicate(variants);
    return unique.length > expected ? unique.sublist(0, expected) : unique;
  }

  static List<String> _deduplicate(List<String> variants) {
    final seen = <String>{};
    final out = <String>[];
    for (final variant in variants) {
      if (variant.isEmpty) continue;
      if (seen.add(variant.toLowerCase())) out.add(variant);
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
