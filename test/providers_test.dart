import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:replylikeme/models/ai_provider.dart';
import 'package:replylikeme/models/api_usage.dart';
import 'package:replylikeme/models/app_settings.dart';
import 'package:replylikeme/services/openai_exception.dart';
import 'package:replylikeme/services/openai_service.dart';
import 'package:replylikeme/services/secure_key_store.dart';

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _claudeReply(String text) => {
  'content': [
    {'type': 'thinking', 'thinking': '…'},
    {'type': 'text', 'text': text},
  ],
  'stop_reason': 'end_turn',
  'usage': {'input_tokens': 12, 'output_tokens': 3},
};

Map<String, Object?> _geminiReply(String text) => {
  'candidates': [
    {
      'content': {
        'role': 'model',
        'parts': [
          {'text': 'thinking…', 'thought': true},
          {'text': text},
        ],
      },
      'finishReason': 'STOP',
    },
  ],
  'usageMetadata': {
    'promptTokenCount': 20,
    'candidatesTokenCount': 4,
    'thoughtsTokenCount': 6,
  },
};

void main() {
  group('AiProvider', () {
    test('tells the provider from the model name', () {
      expect(AiProvider.forModel('claude-opus-5-5'), AiProvider.anthropic);
      expect(AiProvider.forModel('gemini-3.8-flash'), AiProvider.gemini);
      expect(AiProvider.forModel('gemini-embedding-001'), AiProvider.gemini);
      expect(AiProvider.forModel('gpt-5.6-terra'), AiProvider.openai);
      expect(AiProvider.forModel('ft:gpt-4o-mini:me::x'), AiProvider.openai);
    });

    test('tells the provider from the key', () {
      expect(AiProvider.forKey('sk-ant-api03-abc'), AiProvider.anthropic);
      expect(AiProvider.forKey('sk-proj-abc'), AiProvider.openai);
      expect(AiProvider.forKey('AIzaSyabc'), AiProvider.gemini);
      expect(AiProvider.forKey('hello'), isNull);
    });

    test('any provider\'s key passes the shape check', () {
      expect(
        SecureKeyStore.validationError('sk-ant-api03-0123456789abcdef'),
        isNull,
      );
      expect(
        SecureKeyStore.validationError('AIzaSy0123456789abcdefghij'),
        isNull,
      );
      expect(
        SecureKeyStore.validationError('nope-0123456789abcdef'),
        isNotNull,
      );
    });
  });

  group('settings follow the keys', () {
    test('a Claude-only setup writes with Claude and has no fingerprint', () {
      final keys = const ApiKeys().withKey(AiProvider.anthropic, 'sk-ant-x');
      final fitted = const AppSettings().fittedTo(keys);
      expect(fitted.generationModel, 'claude-opus-5-5');
      expect(fitted.visionModel, 'claude-opus-5-5');
      // Nothing to move it to: left as it was.
      expect(fitted.embeddingModel, AppSettings.defaultEmbeddingModel);
      expect(keys.canFingerprint, isFalse);
    });

    test('Gemini takes over fingerprinting when OpenAI is gone', () {
      final keys = const ApiKeys()
          .withKey(AiProvider.anthropic, 'sk-ant-x')
          .withKey(AiProvider.gemini, 'AIza-x');
      final fitted = const AppSettings().fittedTo(keys);
      expect(fitted.generationModel, 'claude-opus-5-5');
      expect(fitted.embeddingModel, 'gemini-embedding-001');
    });

    test('models whose provider has a key are left alone', () {
      final keys = const ApiKeys()
          .withKey(AiProvider.openai, 'sk-x')
          .withKey(AiProvider.gemini, 'AIza-x');
      const mine = AppSettings(generationModel: 'gemini-3.5-flash-lite');
      final fitted = mine.fittedTo(keys);
      expect(fitted.generationModel, 'gemini-3.5-flash-lite');
      expect(fitted.visionModel, AppSettings.defaultVisionModel);
      expect(fitted.embeddingModel, AppSettings.defaultEmbeddingModel);
    });
  });

  group('Claude', () {
    test(
      'sends system on top, alternating turns, and reads the text',
      () async {
        late http.Request sent;
        final usage = <ApiUsage>[];
        final service = OpenAiService(
          anthropicKey: 'sk-ant-test',
          maxRetries: 0,
          onUsage: usage.add,
          client: MockClient((request) async {
            sent = request;
            return _json(_claudeReply('go on then'));
          }),
        );

        final text = await service.chat(
          model: 'claude-opus-5-5',
          temperature: 0.9,
          maxOutputTokens: 300,
          messages: [
            {'role': 'system', 'content': 'You are Robin.'},
            {'role': 'user', 'content': 'example 1'},
            {'role': 'user', 'content': 'example 2'},
            {'role': 'assistant', 'content': 'reply'},
            {'role': 'user', 'content': 'pub?'},
          ],
        );

        expect(text, 'go on then');
        expect(sent.url.toString(), 'https://api.anthropic.com/v1/messages');
        expect(sent.headers['x-api-key'], 'sk-ant-test');
        expect(sent.headers['anthropic-version'], '2023-06-01');
        expect(sent.headers['authorization'], isNull);
        final body = jsonDecode(sent.body) as Map<String, Object?>;
        expect(body['system'], 'You are Robin.');
        expect(body.containsKey('temperature'), isFalse);
        expect(body['max_tokens'], OpenAiService.claudeMaxTokens);
        expect(body['fallbacks'], 'default');
        expect(body['output_config'], {'effort': 'low'});
        final turns = body['messages']! as List;
        expect(
          [for (final t in turns) (t as Map)['role']],
          ['user', 'assistant', 'user'],
        );
        // The two user messages in a row became one turn.
        expect(((turns.first as Map)['content'] as List), hasLength(2));
        expect(usage.single.inputTokens, 12);
        expect(usage.single.outputTokens, 3);
      },
    );

    test('drafts are separate requests, sent together', () async {
      var calls = 0;
      final service = OpenAiService(
        anthropicKey: 'sk-ant-test',
        maxRetries: 0,
        client: MockClient((request) async {
          calls++;
          return _json(_claudeReply('draft $calls'));
        }),
      );
      final drafts = await service.chatDrafts(
        model: 'claude-sonnet-5-5',
        count: 3,
        messages: [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      expect(calls, 3);
      expect(drafts, hasLength(3));
    });

    test('a screenshot goes as a base64 image block', () async {
      late Map<String, Object?> body;
      final service = OpenAiService(
        anthropicKey: 'sk-ant-test',
        maxRetries: 0,
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, Object?>;
          return _json(
            _claudeReply(
              jsonEncode({
                'messages': [
                  {'sender': 'them', 'text': 'pub?'},
                ],
              }),
            ),
          );
        }),
      );
      final messages = await service.extractConversation(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        model: 'claude-opus-5-5',
        imageMimeType: 'image/png',
      );
      expect(messages.single.text, 'pub?');
      final content =
          ((body['messages']! as List).single as Map)['content'] as List;
      final image = content.firstWhere((b) => (b as Map)['type'] == 'image');
      expect((image as Map)['source'], {
        'type': 'base64',
        'media_type': 'image/png',
        'data': base64Encode([1, 2, 3]),
      });
      expect(body['system'], contains('JSON'));
    });

    test('a refusal is an error, not an empty reply', () async {
      final service = OpenAiService(
        anthropicKey: 'sk-ant-test',
        maxRetries: 0,
        client: MockClient(
          (request) async => _json({'content': [], 'stop_reason': 'refusal'}),
        ),
      );
      expect(
        () => service.chat(
          model: 'claude-opus-5-5',
          messages: [
            {'role': 'user', 'content': 'hi'},
          ],
        ),
        throwsA(
          isA<OpenAiException>().having(
            (e) => e.message,
            'message',
            contains('Claude declined'),
          ),
        ),
      );
    });

    test('a model that rejects fallbacks is asked again without', () async {
      final bodies = <Map<String, Object?>>[];
      final service = OpenAiService(
        anthropicKey: 'sk-ant-test',
        maxRetries: 0,
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          bodies.add(body);
          if (body.containsKey('fallbacks')) {
            return _json({
              'type': 'error',
              'error': {
                'type': 'invalid_request_error',
                'message': 'fallbacks: not supported for this model',
              },
            }, status: 400);
          }
          return _json(_claudeReply('ok'));
        }),
      );
      final text = await service.chat(
        model: 'claude-haiku-4-5',
        messages: [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      expect(text, 'ok');
      expect(bodies, hasLength(2));
    });

    test('Claude cannot fingerprint', () {
      final service = OpenAiService(anthropicKey: 'sk-ant-test');
      expect(
        () => service.embed(['x'], model: 'claude-opus-5-5'),
        throwsA(
          isA<OpenAiException>().having(
            (e) => e.kind,
            'kind',
            OpenAiErrorKind.notAvailable,
          ),
        ),
      );
    });

    test('a model without its key says which key is missing', () {
      final service = OpenAiService(apiKey: 'sk-test');
      expect(
        () => service.chat(
          model: 'claude-opus-5-5',
          messages: [
            {'role': 'user', 'content': 'hi'},
          ],
        ),
        throwsA(
          isA<OpenAiException>()
              .having((e) => e.kind, 'kind', OpenAiErrorKind.missingKey)
              .having((e) => e.message, 'message', contains('Claude')),
        ),
      );
    });
  });

  group('Gemini', () {
    test('writes with generateContent and skips the thinking', () async {
      late http.Request sent;
      final usage = <ApiUsage>[];
      final service = OpenAiService(
        geminiKey: 'AIza-test',
        maxRetries: 0,
        onUsage: usage.add,
        client: MockClient((request) async {
          sent = request;
          return _json(_geminiReply('{"facts": []}'));
        }),
      );
      final text = await service.chat(
        model: 'gemini-3.8-flash',
        temperature: 0.2,
        jsonMode: true,
        messages: [
          {'role': 'system', 'content': 'Find facts.'},
          {'role': 'user', 'content': 'Sam: I have a dog'},
          {'role': 'assistant', 'content': 'noted'},
          {'role': 'user', 'content': 'more'},
        ],
      );
      expect(text, '{"facts": []}');
      expect(
        sent.url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-3.8-flash:generateContent',
      );
      expect(sent.headers['x-goog-api-key'], 'AIza-test');
      final body = jsonDecode(sent.body) as Map<String, Object?>;
      expect(body['systemInstruction'], {
        'parts': [
          {'text': 'Find facts.'},
        ],
      });
      expect(
        [for (final c in body['contents']! as List) (c as Map)['role']],
        ['user', 'model', 'user'],
      );
      expect(body['generationConfig'], {
        'temperature': 0.2,
        'responseMimeType': 'application/json',
      });
      expect(usage.single.inputTokens, 20);
      expect(usage.single.outputTokens, 10);
    });

    test('fingerprints in one batch, at the asked size', () async {
      late Map<String, Object?> body;
      late Uri url;
      final service = OpenAiService(
        geminiKey: 'AIza-test',
        maxRetries: 0,
        client: MockClient((request) async {
          url = request.url;
          body = jsonDecode(request.body) as Map<String, Object?>;
          return _json({
            'embeddings': [
              {
                'values': [1.0, 0.0],
              },
              {
                'values': [0.0, 1.0],
              },
            ],
          });
        }),
      );
      final vectors = await service.embed(
        ['a', 'b'],
        model: 'gemini-embedding-001',
        dimensions: 512,
      );
      expect(vectors, [
        [1.0, 0.0],
        [0.0, 1.0],
      ]);
      expect(
        url.path,
        endsWith('models/gemini-embedding-001:batchEmbedContents'),
      );
      final first = (body['requests']! as List).first as Map;
      expect(first['model'], 'models/gemini-embedding-001');
      expect(first['outputDimensionality'], 512);
    });

    test('a bad key is called a bad key, though Gemini sends a 400', () {
      final service = OpenAiService(
        geminiKey: 'AIza-test',
        maxRetries: 0,
        client: MockClient(
          (request) async => _json({
            'error': {
              'code': 400,
              'message': 'API key not valid. Please pass a valid API key.',
              'status': 'INVALID_ARGUMENT',
            },
          }, status: 400),
        ),
      );
      expect(
        service.listModelsFor(AiProvider.gemini),
        throwsA(
          isA<OpenAiException>().having(
            (e) => e.kind,
            'kind',
            OpenAiErrorKind.badKey,
          ),
        ),
      );
    });

    test('lists only the models that write or fingerprint', () async {
      final service = OpenAiService(
        geminiKey: 'AIza-test',
        client: MockClient(
          (request) async => _json({
            'models': [
              {
                'name': 'models/gemini-3.8-flash',
                'supportedGenerationMethods': ['generateContent'],
              },
              {
                'name': 'models/gemini-embedding-001',
                'supportedGenerationMethods': [
                  'embedContent',
                  'batchEmbedContents',
                ],
              },
              {
                'name': 'models/aqa',
                'supportedGenerationMethods': ['generateAnswer'],
              },
            ],
          }),
        ),
      );
      expect(await service.listModels(), [
        'gemini-3.8-flash',
        'gemini-embedding-001',
      ]);
    });
  });

  group('when the app is sent away', () {
    test('any broken connection waits for it to come back', () async {
      var interruptions = 0;
      var calls = 0;
      final service = OpenAiService(
        apiKey: 'sk-test',
        maxRetries: 0,
        interruptions: () => interruptions,
        whenActive: () async {},
        client: MockClient((request) async {
          calls++;
          if (calls == 1) {
            interruptions++;
            throw const HandshakeException('connection reset');
          }
          return _json({
            'choices': [
              {
                'message': {'content': 'back'},
              },
            ],
          });
        }),
      );
      final text = await service.chat(
        model: 'gpt-5.6-terra',
        messages: [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      expect(text, 'back');
      expect(calls, 2);
    });

    test('every request runs inside keepAlive', () async {
      var held = 0;
      final service = OpenAiService(
        apiKey: 'sk-test',
        maxRetries: 0,
        keepAlive: <T>(Future<T> Function() work) {
          held++;
          return work();
        },
        client: MockClient(
          (request) async => _json({
            'choices': [
              {
                'message': {'content': 'ok'},
              },
            ],
          }),
        ),
      );
      await service.chat(
        model: 'gpt-5.6-terra',
        messages: [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      expect(held, 1);
    });
  });
}
