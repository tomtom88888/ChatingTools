import 'dart:async';
import 'dart:convert';

import '../models/finetune_job.dart';
import '../models/stored_exchange.dart';
import 'openai_exception.dart';
import 'openai_service.dart';
import 'pricing.dart';

/// What a fine-tuning run would cost, shown before anything is uploaded.
class FineTuneEstimate {
  const FineTuneEstimate({
    required this.exampleCount,
    required this.estimatedTokensPerEpoch,
    required this.epochs,
    required this.estimatedUsd,
    required this.usdPerMillionTokens,
  });

  final int exampleCount;
  final int estimatedTokensPerEpoch;
  final int epochs;
  final double estimatedUsd;
  final double usdPerMillionTokens;

  int get estimatedTotalTokens => estimatedTokensPerEpoch * epochs;

  String get formattedUsd => Pricing.formatUsd(estimatedUsd);
}

/// Mode B: builds a chat-format JSONL dataset from the style memory, uploads
/// it, and runs an OpenAI fine-tuning job.
///
/// Note that OpenAI is winding the fine-tuning platform down: since May 2026
/// organisations that never fine-tuned before cannot create jobs, and existing
/// ones lose access in January 2027. [start] surfaces the API's refusal as-is
/// rather than pretending otherwise.
class FineTuneService {
  const FineTuneService({required this.openai});

  final OpenAiService openai;

  /// OpenAI rejects a training file with fewer examples than this.
  static const int minimumExamples = 10;

  /// The default number of passes over the data.
  static const int defaultEpochs = 3;

  /// Builds one JSONL line per exchange in OpenAI's chat fine-tuning format.
  ///
  /// Each line is a system message describing you texting them, the previous
  /// turns as alternating user/assistant messages, and your real reply as the
  /// final assistant message — the target the model learns to produce.
  ///
  /// With several chats in the dataset, [chats] gives each exchange the names
  /// from its own chat; [myName] and [theirName] cover anything not in it.
  static String buildJsonl(
    List<StoredExchange> exchanges, {
    required String myName,
    required String theirName,
    required int contextTurns,
    Map<int, ChatMemory> chats = const {},
  }) {
    final lines = <String>[];
    for (final exchange in exchanges) {
      if (exchange.replyText.trim().isEmpty) continue;
      final chat = chats[exchange.chatId];
      final me = chat == null || chat.myName.isEmpty ? myName : chat.myName;
      final them = chat == null || chat.theirName.isEmpty
          ? theirName
          : chat.theirName;

      final context = exchange.context.length > contextTurns
          ? exchange.context.sublist(exchange.context.length - contextTurns)
          : exchange.context;
      if (context.isEmpty) continue;

      final messages = <Map<String, String>>[
        {'role': 'system', 'content': systemMessage(me, them)},
        for (final turn in context)
          {
            'role': turn.sender == me ? 'assistant' : 'user',
            'content': turn.text,
          },
        {'role': 'assistant', 'content': exchange.replyText},
      ];
      lines.add(jsonEncode({'messages': messages}));
    }
    // JSONL: one JSON object per line, trailing newline included.
    return lines.isEmpty ? '' : '${lines.join('\n')}\n';
  }

  static String systemMessage(String myName, String theirName) {
    final me = myName.isEmpty ? 'the user' : myName;
    final them = theirName.isEmpty ? 'a friend' : theirName;
    return 'You are $me, texting $them on WhatsApp. Reply exactly as $me '
        'would: same tone, length, slang, emoji use, capitalisation and '
        'language mix. Output only the message.';
  }

  /// Estimates cost from the built JSONL, so the number shown is derived from
  /// the exact bytes that would be uploaded.
  static FineTuneEstimate estimate(
    String jsonl, {
    int epochs = defaultEpochs,
    double usdPerMillionTokens = Pricing.fineTuneTrainingUsdPerMillionTokens,
  }) {
    final lines = jsonl
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);

    // Only the message content is billed, not the JSON scaffolding.
    var contentCharacters = 0;
    for (final line in lines) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        final messages = decoded['messages'];
        if (messages is! List) continue;
        for (final message in messages) {
          if (message is Map && message['content'] is String) {
            contentCharacters += (message['content'] as String).length;
          }
        }
      } on FormatException {
        continue;
      }
    }
    final tokensPerEpoch = (contentCharacters / Pricing.charactersPerToken)
        .ceil();
    return FineTuneEstimate(
      exampleCount: lines.length,
      estimatedTokensPerEpoch: tokensPerEpoch,
      epochs: epochs,
      estimatedUsd: Pricing.usd(tokensPerEpoch * epochs, usdPerMillionTokens),
      usdPerMillionTokens: usdPerMillionTokens,
    );
  }

  /// Uploads the dataset and starts the job.
  ///
  /// The caller must have taken the user's confirmation first: this spends
  /// money.
  Future<FineTuneJob> start({
    required String jsonl,
    required String baseModel,
    String? suffix,
    int epochs = defaultEpochs,
  }) async {
    final exampleCount = jsonl
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .length;
    if (exampleCount < minimumExamples) {
      throw OpenAiException(
        OpenAiErrorKind.badRequest,
        'Fine-tuning needs at least $minimumExamples examples and this export '
        'produced $exampleCount. Import a longer chat, or stay on style '
        'memory.',
      );
    }

    final fileId = await openai.uploadTrainingFile(
      filename: 'replylikeme-training.jsonl',
      bytes: utf8.encode(jsonl),
    );
    return openai.createFineTuneJob(
      trainingFileId: fileId,
      baseModel: baseModel,
      suffix: suffix,
      epochs: epochs,
    );
  }

  /// Polls a job until it reaches a terminal state, emitting every status read.
  ///
  /// Fine-tuning takes minutes to hours, so the caller is expected to keep the
  /// job id and be able to resume polling in a later session.
  Stream<FineTuneJob> watch(
    String jobId, {
    Duration interval = const Duration(seconds: 20),
  }) async* {
    while (true) {
      final job = await openai.getFineTuneJob(jobId);
      yield job;
      if (job.isTerminal) return;
      await Future<void>.delayed(interval);
    }
  }

  Future<FineTuneJob> cancel(String jobId) => openai.cancelFineTuneJob(jobId);
}
