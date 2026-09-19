import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/extracted_message.dart';
import '../models/finetune_job.dart';
import 'openai_exception.dart';

/// A message in an OpenAI chat request.
typedef ChatMessageJson = Map<String, Object?>;

/// Thin, direct client for the OpenAI REST API.
///
/// Deliberately has no Flutter dependency and no storage of its own: the key is
/// handed in per instance by whoever read it out of secure storage. The key is
/// never logged, never put in an exception, and never written to disk here.
class OpenAiService {
  OpenAiService({
    required String apiKey,
    http.Client? client,
    this.baseUrl = 'https://api.openai.com/v1',
    this.requestTimeout = const Duration(seconds: 60),
    this.visionTimeout = const Duration(seconds: 120),
    this.maxRetries = 3,
  }) : _apiKey = apiKey.trim(),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final String _apiKey;
  final http.Client _client;
  final bool _ownsClient;
  final String baseUrl;
  final Duration requestTimeout;
  final Duration visionTimeout;
  final int maxRetries;

  /// Newer models take `max_completion_tokens`; older ones only understand
  /// `max_tokens`. Discovered once from a 400 and remembered, so the fallback
  /// costs at most one wasted request per process.
  bool _useMaxCompletionTokens = true;

  /// Reasoning-tier models reject a `temperature` other than 1. Same trick.
  bool _sendTemperature = true;

  void close() {
    if (_ownsClient) _client.close();
  }

  bool get hasKey => _apiKey.isNotEmpty;

  // ---------------------------------------------------------------- embeddings

  /// Embeds [inputs] in one request and returns vectors in the same order.
  ///
  /// [dimensions] is only sent for models that support shortening
  /// (`text-embedding-3-*`); other models reject the parameter.
  Future<List<List<double>>> embed(
    List<String> inputs, {
    required String model,
    int? dimensions,
  }) async {
    if (inputs.isEmpty) return const [];
    final body = <String, Object?>{'model': model, 'input': inputs};
    if (dimensions != null && model.startsWith('text-embedding-3')) {
      body['dimensions'] = dimensions;
    }

    final json = await _postJson('/embeddings', body, timeout: requestTimeout);
    final data = json['data'];
    if (data is! List || data.length != inputs.length) {
      throw OpenAiException(
        OpenAiErrorKind.badResponse,
        'The embeddings response had ${data is List ? data.length : 0} vectors '
        'for ${inputs.length} inputs.',
      );
    }
    // The API documents that `data` may come back out of order, so index by
    // the `index` field rather than trusting position.
    final vectors = List<List<double>?>.filled(inputs.length, null);
    for (final entry in data) {
      if (entry is! Map) continue;
      final index = (entry['index'] as num?)?.toInt();
      final embedding = entry['embedding'];
      if (index == null || index < 0 || index >= inputs.length) continue;
      if (embedding is! List) continue;
      vectors[index] = embedding
          .whereType<num>()
          .map((n) => n.toDouble())
          .toList(growable: false);
    }
    if (vectors.any((v) => v == null || v.isEmpty)) {
      throw const OpenAiException(
        OpenAiErrorKind.badResponse,
        'The embeddings response was missing vectors.',
      );
    }
    return vectors.cast<List<double>>();
  }

  // --------------------------------------------------------------------- chat

  /// One chat completion, returning the assistant's text.
  Future<String> chat({
    required String model,
    required List<ChatMessageJson> messages,
    double? temperature,
    int? maxOutputTokens,
    bool jsonMode = false,
    Duration? timeout,
  }) async {
    final text = await _chat(
      model: model,
      messages: messages,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
      jsonMode: jsonMode,
      timeout: timeout ?? requestTimeout,
    );
    if (text.trim().isEmpty) {
      throw const OpenAiException(
        OpenAiErrorKind.badResponse,
        'The model returned an empty reply. Try again.',
      );
    }
    return text.trim();
  }

  Future<String> _chat({
    required String model,
    required List<ChatMessageJson> messages,
    required double? temperature,
    required int? maxOutputTokens,
    required bool jsonMode,
    required Duration timeout,
  }) async {
    // Up to two extra attempts, each dropping a parameter this model rejected.
    for (var attempt = 0; attempt < 3; attempt++) {
      final body = <String, Object?>{'model': model, 'messages': messages};
      if (maxOutputTokens != null) {
        body[_useMaxCompletionTokens ? 'max_completion_tokens' : 'max_tokens'] =
            maxOutputTokens;
      }
      if (temperature != null && _sendTemperature) {
        body['temperature'] = temperature;
      }
      if (jsonMode) {
        body['response_format'] = const {'type': 'json_object'};
      }

      try {
        final json = await _postJson(
          '/chat/completions',
          body,
          timeout: timeout,
        );
        return _firstChoiceContent(json);
      } on OpenAiException catch (error) {
        if (error.kind != OpenAiErrorKind.badRequest) rethrow;
        final complaint = error.message.toLowerCase();
        if (_useMaxCompletionTokens &&
            maxOutputTokens != null &&
            complaint.contains('max_completion_tokens')) {
          _useMaxCompletionTokens = false;
          continue;
        }
        if (_sendTemperature &&
            temperature != null &&
            complaint.contains('temperature')) {
          _sendTemperature = false;
          continue;
        }
        rethrow;
      }
    }
    throw OpenAiException(
      OpenAiErrorKind.badRequest,
      'The model "$model" rejected the request even after dropping optional '
      'parameters. Try a different model in Settings.',
    );
  }

  static String _firstChoiceContent(Map<String, Object?> json) {
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const OpenAiException(
        OpenAiErrorKind.badResponse,
        'The response contained no choices.',
      );
    }
    final message = (choices.first as Map)['message'];
    if (message is! Map) {
      throw const OpenAiException(
        OpenAiErrorKind.badResponse,
        'The response contained no message.',
      );
    }
    final content = message['content'];
    if (content is String) return content;
    // Some models return content as a list of typed parts.
    if (content is List) {
      return content
          .whereType<Map>()
          .map((part) => part['text'])
          .whereType<String>()
          .join();
    }
    throw const OpenAiException(
      OpenAiErrorKind.badResponse,
      'The response message had no text content.',
    );
  }

  // ------------------------------------------------------------------- vision

  /// Reads a WhatsApp conversation off a screenshot.
  ///
  /// Asks for strict JSON and validates it, so a model that free-associates
  /// produces a clear error rather than garbage messages.
  Future<List<ExtractedMessage>> extractConversation({
    required Uint8List imageBytes,
    required String model,
    String imageMimeType = 'image/jpeg',
  }) async {
    if (imageBytes.isEmpty) {
      throw const OpenAiException(
        OpenAiErrorKind.badRequest,
        'That screenshot is empty.',
      );
    }
    final dataUri =
        'data:$imageMimeType;base64,${base64Encode(imageBytes)}';

    final raw = await _chat(
      model: model,
      messages: [
        {'role': 'system', 'content': _visionSystemPrompt},
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': _visionUserPrompt},
            {
              'type': 'image_url',
              'image_url': {'url': dataUri, 'detail': 'high'},
            },
          ],
        },
      ],
      temperature: 0,
      maxOutputTokens: 4000,
      jsonMode: true,
      timeout: visionTimeout,
    );

    return parseExtractedConversation(raw);
  }

  static const String _visionSystemPrompt =
      'You transcribe WhatsApp conversation screenshots. In WhatsApp the '
      "user's own messages are the bubbles aligned to the RIGHT edge of the "
      'screen (usually green or blue-tinted), and the other person\'s messages '
      'are the bubbles aligned to the LEFT edge (usually white or grey). '
      'Alignment decides the sender, never the wording. Transcribe the visible '
      'messages in top-to-bottom order, exactly as written, keeping emoji, '
      'capitalisation, spelling and language as they appear. Ignore date '
      'separators, timestamps, read receipts, the contact header and the input '
      'box. Reply with JSON only.';

  static const String _visionUserPrompt =
      'Transcribe this conversation. Respond with a JSON object of the form '
      '{"messages": [{"sender": "me" | "them", "text": "..."}]} where "me" is '
      'a right-aligned bubble and "them" is a left-aligned bubble. If a bubble '
      'is only an image, sticker or voice note, use its text as an empty '
      'string. Output nothing but the JSON object.';

  /// Validates and parses the vision model's JSON.
  ///
  /// Accepts either `{"messages": [...]}` or a bare array, and tolerates the
  /// model wrapping its answer in a Markdown code fence.
  static List<ExtractedMessage> parseExtractedConversation(String raw) {
    final cleaned = _stripCodeFence(raw);
    final Object? decoded;
    try {
      decoded = jsonDecode(cleaned);
    } on FormatException {
      throw const OpenAiException(
        OpenAiErrorKind.badResponse,
        "Couldn't read that screenshot — the model didn't return valid JSON. "
        'Try a clearer screenshot, or a different vision model in Settings.',
      );
    }

    final Object? list;
    if (decoded is List) {
      list = decoded;
    } else if (decoded is Map) {
      list = decoded['messages'] ?? decoded['conversation'] ?? decoded['data'];
    } else {
      list = null;
    }
    if (list is! List) {
      throw const OpenAiException(
        OpenAiErrorKind.badResponse,
        "Couldn't read that screenshot — the model's JSON had no message list.",
      );
    }

    final messages = <ExtractedMessage>[];
    for (final entry in list) {
      try {
        final message = ExtractedMessage.fromJson(entry);
        if (message.text.isNotEmpty) messages.add(message);
      } on FormatException {
        // Skip the one bad entry rather than losing the whole transcription.
        continue;
      }
    }
    if (messages.isEmpty) {
      throw const OpenAiException(
        OpenAiErrorKind.badResponse,
        "Couldn't find any messages in that screenshot. Make sure the "
        'conversation itself is visible and try again.',
      );
    }
    return messages;
  }

  static String _stripCodeFence(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('```')) return trimmed;
    final firstNewline = trimmed.indexOf('\n');
    if (firstNewline == -1) return trimmed;
    var inner = trimmed.substring(firstNewline + 1);
    final closing = inner.lastIndexOf('```');
    if (closing != -1) inner = inner.substring(0, closing);
    return inner.trim();
  }

  // -------------------------------------------------------------------- models

  /// Model ids this account can actually use, so Settings never has to guess at
  /// OpenAI's current naming.
  Future<List<String>> listModels() async {
    final json = await _getJson('/models');
    final data = json['data'];
    if (data is! List) {
      throw const OpenAiException(
        OpenAiErrorKind.badResponse,
        'The model list came back in an unexpected shape.',
      );
    }
    final ids =
        data
            .whereType<Map>()
            .map((m) => m['id'])
            .whereType<String>()
            .toList()
          ..sort();
    return ids;
  }

  // --------------------------------------------------------------------- files

  /// Uploads a training file and returns its file id.
  Future<String> uploadTrainingFile({
    required String filename,
    required List<int> bytes,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/files'))
      ..headers['Authorization'] = 'Bearer $_apiKey'
      ..fields['purpose'] = 'fine-tune'
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );

    final response = await _send(
      () async =>
          http.Response.fromStream(await _client.send(request)),
      // Uploads are not safe to replay as a MultipartRequest can only be sent
      // once, so no retries here.
      retries: 0,
      timeout: const Duration(minutes: 5),
    );
    final json = _decodeBody(response);
    final id = json['id'];
    if (id is! String) {
      throw const OpenAiException(
        OpenAiErrorKind.badResponse,
        'The upload succeeded but returned no file id.',
      );
    }
    return id;
  }

  // ---------------------------------------------------------------- fine-tunes

  Future<FineTuneJob> createFineTuneJob({
    required String trainingFileId,
    required String baseModel,
    String? suffix,
    int? epochs,
  }) async {
    final body = <String, Object?>{
      'training_file': trainingFileId,
      'model': baseModel,
      if (suffix != null && suffix.isNotEmpty) 'suffix': suffix,
      if (epochs != null)
        'method': {
          'type': 'supervised',
          'supervised': {
            'hyperparameters': {'n_epochs': epochs},
          },
        },
    };
    final json = await _postJson('/fine_tuning/jobs', body);
    return FineTuneJob.fromJson(json);
  }

  Future<FineTuneJob> getFineTuneJob(String jobId) async {
    final json = await _getJson('/fine_tuning/jobs/$jobId');
    return FineTuneJob.fromJson(json);
  }

  Future<FineTuneJob> cancelFineTuneJob(String jobId) async {
    final json = await _postJson('/fine_tuning/jobs/$jobId/cancel', const {});
    return FineTuneJob.fromJson(json);
  }

  // ----------------------------------------------------------------- transport

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _jsonHeaders => {
    'Authorization': 'Bearer $_apiKey',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> body, {
    Duration? timeout,
  }) async {
    final response = await _send(
      () => _client.post(
        _uri(path),
        headers: _jsonHeaders,
        body: jsonEncode(body),
      ),
      timeout: timeout ?? requestTimeout,
    );
    return _decodeBody(response);
  }

  Future<Map<String, Object?>> _getJson(String path, {Duration? timeout}) async {
    final response = await _send(
      () => _client.get(_uri(path), headers: _jsonHeaders),
      timeout: timeout ?? requestTimeout,
    );
    return _decodeBody(response);
  }

  /// Sends a request, retrying transient failures with exponential backoff and
  /// honouring `Retry-After`, then converts any failure into an
  /// [OpenAiException] the UI can present.
  Future<http.Response> _send(
    Future<http.Response> Function() send, {
    required Duration timeout,
    int? retries,
  }) async {
    if (!hasKey) {
      throw const OpenAiException(
        OpenAiErrorKind.missingKey,
        'No OpenAI API key saved yet. Add one in Settings.',
      );
    }
    final attempts = (retries ?? maxRetries) + 1;
    OpenAiException? last;

    for (var attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) {
        final backoff =
            last?.retryAfter ??
            Duration(milliseconds: 500 * math.pow(2, attempt - 1).toInt());
        await Future<void>.delayed(backoff);
      }
      try {
        final response = await send().timeout(timeout);
        if (response.statusCode < 400) return response;
        final failure = _failureFor(response);
        if (!failure.isTransient || attempt == attempts - 1) throw failure;
        last = failure;
      } on OpenAiException {
        rethrow;
      } on TimeoutException {
        last = const OpenAiException(
          OpenAiErrorKind.timeout,
          'OpenAI took too long to answer. Check your connection and try '
          'again.',
        );
        if (attempt == attempts - 1) throw last;
      } on SocketException {
        last = const OpenAiException(
          OpenAiErrorKind.network,
          "Couldn't reach OpenAI. Check your internet connection.",
        );
        if (attempt == attempts - 1) throw last;
      } on http.ClientException {
        last = const OpenAiException(
          OpenAiErrorKind.network,
          "Couldn't reach OpenAI. Check your internet connection.",
        );
        if (attempt == attempts - 1) throw last;
      }
    }
    throw last ??
        const OpenAiException(
          OpenAiErrorKind.network,
          'The request to OpenAI failed.',
        );
  }

  static Map<String, Object?> _decodeBody(http.Response response) {
    if (response.statusCode >= 400) throw _failureFor(response);
    if (response.body.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, Object?>) return decoded;
      return {'data': decoded};
    } on FormatException {
      throw const OpenAiException(
        OpenAiErrorKind.badResponse,
        'OpenAI returned a response that was not JSON.',
      );
    }
  }

  /// Turns an error response into a message worth showing a person. Only the
  /// response body is read — request headers, and therefore the key, never are.
  static OpenAiException _failureFor(http.Response response) {
    final status = response.statusCode;
    String? apiMessage;
    String? apiType;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          if (error['message'] is String) {
            apiMessage = error['message'] as String;
          }
          if (error['type'] is String) apiType = error['type'] as String;
        }
      }
    } on FormatException {
      // Non-JSON error body; fall back to the generic messages below.
    }

    final retryAfterHeader = response.headers['retry-after'];
    final retryAfterSeconds = double.tryParse(retryAfterHeader ?? '');
    final retryAfter = retryAfterSeconds == null
        ? null
        : Duration(milliseconds: (retryAfterSeconds * 1000).round());

    return switch (status) {
      401 => const OpenAiException(
        OpenAiErrorKind.badKey,
        'OpenAI rejected that API key. Check it in Settings, or create a new '
        'one at platform.openai.com.',
        statusCode: 401,
      ),
      403 || 404 => OpenAiException(
        OpenAiErrorKind.notAvailable,
        apiMessage ??
            'Your OpenAI account cannot use that model or endpoint. Try a '
                'different model in Settings.',
        statusCode: status,
      ),
      429 =>
        apiType == 'insufficient_quota'
            ? OpenAiException(
                OpenAiErrorKind.insufficientQuota,
                apiMessage ??
                    'Your OpenAI account has no credit left. Add billing at '
                        'platform.openai.com and try again.',
                statusCode: 429,
              )
            : OpenAiException(
                OpenAiErrorKind.rateLimited,
                'OpenAI is rate-limiting this key. Waiting a moment and '
                'retrying.',
                statusCode: 429,
                retryAfter: retryAfter,
              ),
      >= 500 => OpenAiException(
        OpenAiErrorKind.serverError,
        apiMessage ?? 'OpenAI had a server error ($status).',
        statusCode: status,
        retryAfter: retryAfter,
      ),
      _ => OpenAiException(
        OpenAiErrorKind.badRequest,
        apiMessage ?? 'OpenAI rejected the request ($status).',
        statusCode: status,
      ),
    };
  }
}
