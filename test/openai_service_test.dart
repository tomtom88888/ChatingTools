import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:replylikeme/models/extracted_message.dart';
import 'package:replylikeme/services/openai_exception.dart';
import 'package:replylikeme/services/openai_service.dart';

/// Builds a service whose transport is scripted, so no network is touched.
OpenAiService serviceThat(
  Future<http.Response> Function(http.Request request) handler, {
  int maxRetries = 0,
}) => OpenAiService(
  apiKey: 'sk-test-0123456789abcdefghij',
  client: MockClient(handler),
  maxRetries: maxRetries,
);

http.Response jsonResponse(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> chatReply(String content) => {
  'choices': [
    {
      'message': {'role': 'assistant', 'content': content},
    },
  ],
};

void main() {
  group('embeddings', () {
    test('sends one request and keeps input order', () async {
      Map<String, Object?>? sent;
      final service = serviceThat((request) async {
        sent = jsonDecode(request.body) as Map<String, Object?>;
        return jsonResponse({
          'data': [
            // Deliberately out of order: the API documents it may be.
            {'index': 1, 'embedding': [0.0, 1.0]},
            {'index': 0, 'embedding': [1.0, 0.0]},
          ],
        });
      });

      final vectors = await service.embed(
        ['first', 'second'],
        model: 'text-embedding-3-small',
        dimensions: 512,
      );

      expect(vectors, [
        [1.0, 0.0],
        [0.0, 1.0],
      ]);
      expect(sent!['input'], ['first', 'second']);
      expect(sent!['dimensions'], 512);
    });

    test('omits dimensions for models that do not support shortening', () async {
      Map<String, Object?>? sent;
      final service = serviceThat((request) async {
        sent = jsonDecode(request.body) as Map<String, Object?>;
        return jsonResponse({
          'data': [
            {'index': 0, 'embedding': [1.0]},
          ],
        });
      });

      await service.embed(['x'], model: 'some-other-embedder', dimensions: 512);
      expect(sent!.containsKey('dimensions'), isFalse);
    });

    test('never calls out for an empty batch', () async {
      var calls = 0;
      final service = serviceThat((request) async {
        calls++;
        return jsonResponse(const {});
      });
      expect(await service.embed(const [], model: 'm'), isEmpty);
      expect(calls, 0);
    });

    test('reports a short response rather than silently misaligning', () async {
      final service = serviceThat(
        (request) async => jsonResponse({
          'data': [
            {'index': 0, 'embedding': [1.0]},
          ],
        }),
      );
      expect(
        () => service.embed(['a', 'b'], model: 'text-embedding-3-small'),
        throwsA(
          isA<OpenAiException>().having(
            (e) => e.kind,
            'kind',
            OpenAiErrorKind.badResponse,
          ),
        ),
      );
    });
  });

  group('error mapping', () {
    test('401 becomes a bad-key message naming Settings', () async {
      final service = serviceThat(
        (request) async => jsonResponse({
          'error': {'message': 'Incorrect API key provided: sk-abc'},
        }, status: 401),
      );
      await expectLater(
        service.chat(model: 'm', messages: const []),
        throwsA(
          isA<OpenAiException>()
              .having((e) => e.kind, 'kind', OpenAiErrorKind.badKey)
              .having((e) => e.message, 'message', contains('Settings')),
        ),
      );
    });

    test('429 insufficient_quota is told apart from rate limiting', () async {
      final service = serviceThat(
        (request) async => jsonResponse({
          'error': {
            'message': 'You exceeded your current quota.',
            'type': 'insufficient_quota',
          },
        }, status: 429),
      );
      await expectLater(
        service.chat(model: 'm', messages: const []),
        throwsA(
          isA<OpenAiException>().having(
            (e) => e.kind,
            'kind',
            OpenAiErrorKind.insufficientQuota,
          ),
        ),
      );
    });

    test('404 on a model points at Settings', () async {
      final service = serviceThat(
        (request) async => jsonResponse({
          'error': {'message': 'The model `nope` does not exist'},
        }, status: 404),
      );
      await expectLater(
        service.chat(model: 'nope', messages: const []),
        throwsA(
          isA<OpenAiException>()
              .having((e) => e.kind, 'kind', OpenAiErrorKind.notAvailable)
              .having((e) => e.message, 'message', contains('does not exist')),
        ),
      );
    });

    test('a 500 is retried and can succeed', () async {
      var calls = 0;
      final service = serviceThat((request) async {
        calls++;
        if (calls == 1) {
          return jsonResponse(const {'error': {'message': 'oops'}}, status: 500);
        }
        return jsonResponse(chatReply('second time lucky'));
      }, maxRetries: 2);

      expect(
        await service.chat(model: 'm', messages: const []),
        'second time lucky',
      );
      expect(calls, 2);
    });

    test('a non-JSON error body still yields a usable message', () async {
      final service = serviceThat(
        (request) async => http.Response('<html>gateway</html>', 400),
      );
      await expectLater(
        service.chat(model: 'm', messages: const []),
        throwsA(
          isA<OpenAiException>().having(
            (e) => e.message,
            'message',
            contains('400'),
          ),
        ),
      );
    });

    test('a missing key fails before any request is made', () async {
      var calls = 0;
      final service = OpenAiService(
        apiKey: '   ',
        client: MockClient((request) async {
          calls++;
          return jsonResponse(const {});
        }),
      );
      await expectLater(
        service.chat(model: 'm', messages: const []),
        throwsA(
          isA<OpenAiException>().having(
            (e) => e.kind,
            'kind',
            OpenAiErrorKind.missingKey,
          ),
        ),
      );
      expect(calls, 0);
    });
  });

  group('parameter compatibility', () {
    test('falls back to max_tokens when the model rejects the new name', () async {
      final bodies = <Map<String, Object?>>[];
      final service = serviceThat((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        bodies.add(body);
        if (body.containsKey('max_completion_tokens')) {
          return jsonResponse({
            'error': {
              'message': "Unsupported parameter: 'max_completion_tokens'",
            },
          }, status: 400);
        }
        return jsonResponse(chatReply('ok'));
      });

      expect(
        await service.chat(
          model: 'legacy',
          messages: const [],
          maxOutputTokens: 100,
        ),
        'ok',
      );
      expect(bodies, hasLength(2));
      expect(bodies.last['max_tokens'], 100);
    });

    test('drops temperature when the model insists on its default', () async {
      final bodies = <Map<String, Object?>>[];
      final service = serviceThat((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        bodies.add(body);
        if (body.containsKey('temperature')) {
          return jsonResponse({
            'error': {
              'message':
                  "Unsupported value: 'temperature' does not support 0.9",
            },
          }, status: 400);
        }
        return jsonResponse(chatReply('ok'));
      });

      expect(
        await service.chat(
          model: 'reasoner',
          messages: const [],
          temperature: 0.9,
        ),
        'ok',
      );
      expect(bodies, hasLength(2));
      expect(bodies.last.containsKey('temperature'), isFalse);
    });

    test('a 400 it cannot work around is surfaced', () async {
      final service = serviceThat(
        (request) async => jsonResponse({
          'error': {'message': 'messages must not be empty'},
        }, status: 400),
      );
      await expectLater(
        service.chat(model: 'm', messages: const []),
        throwsA(
          isA<OpenAiException>().having(
            (e) => e.message,
            'message',
            'messages must not be empty',
          ),
        ),
      );
    });
  });

  group('vision', () {
    Uint8List fakePng() => Uint8List.fromList(List.filled(32, 7));

    test('asks for JSON, sends the image inline, and parses the result', () async {
      Map<String, Object?>? sent;
      final service = serviceThat((request) async {
        sent = jsonDecode(request.body) as Map<String, Object?>;
        return jsonResponse(
          chatReply(
            jsonEncode({
              'messages': [
                {'sender': 'them', 'text': 'you coming?'},
                {'sender': 'me', 'text': 'yeah 2 secs'},
                {'sender': 'them', 'text': 'ok'},
              ],
            }),
          ),
        );
      });

      final messages = await service.extractConversation(
        imageBytes: fakePng(),
        model: 'gpt-5.6-terra',
        imageMimeType: 'image/png',
      );

      expect(messages.map((m) => m.speaker), [
        Speaker.them,
        Speaker.me,
        Speaker.them,
      ]);
      expect(messages.first.text, 'you coming?');
      expect(sent!['response_format'], {'type': 'json_object'});

      final content =
          ((sent!['messages'] as List).last as Map)['content'] as List;
      final imagePart = content.whereType<Map>().firstWhere(
        (part) => part['type'] == 'image_url',
      );
      final url = (imagePart['image_url'] as Map)['url'] as String;
      expect(url, startsWith('data:image/png;base64,'));
    });

    test('rejects an empty screenshot before spending a request', () async {
      var calls = 0;
      final service = serviceThat((request) async {
        calls++;
        return jsonResponse(const {});
      });
      await expectLater(
        service.extractConversation(
          imageBytes: Uint8List(0),
          model: 'gpt-5.6-terra',
        ),
        throwsA(isA<OpenAiException>()),
      );
      expect(calls, 0);
    });
  });

  group('parseExtractedConversation', () {
    test('accepts a bare array', () {
      final messages = OpenAiService.parseExtractedConversation(
        '[{"sender":"them","text":"hi"}]',
      );
      expect(messages.single.speaker, Speaker.them);
    });

    test('tolerates a markdown code fence', () {
      final messages = OpenAiService.parseExtractedConversation(
        '```json\n{"messages":[{"sender":"me","text":"sup"}]}\n```',
      );
      expect(messages.single.text, 'sup');
    });

    test('skips one malformed entry rather than losing the rest', () {
      final messages = OpenAiService.parseExtractedConversation(
        '{"messages":[{"sender":"nobody","text":"?"},'
        '{"sender":"them","text":"hi"}]}',
      );
      expect(messages, hasLength(1));
      expect(messages.single.text, 'hi');
    });

    test('drops image-only bubbles, which have no text', () {
      final messages = OpenAiService.parseExtractedConversation(
        '{"messages":[{"sender":"them","text":""},'
        '{"sender":"them","text":"look"}]}',
      );
      expect(messages, hasLength(1));
    });

    test('explains invalid JSON in words a user can act on', () {
      expect(
        () => OpenAiService.parseExtractedConversation('I see three messages'),
        throwsA(
          isA<OpenAiException>()
              .having((e) => e.kind, 'kind', OpenAiErrorKind.badResponse)
              .having((e) => e.message, 'message', contains('screenshot')),
        ),
      );
    });

    test('explains an empty transcription', () {
      expect(
        () => OpenAiService.parseExtractedConversation('{"messages":[]}'),
        throwsA(
          isA<OpenAiException>().having(
            (e) => e.message,
            'message',
            contains("Couldn't find any messages"),
          ),
        ),
      );
    });
  });

  group('listModels', () {
    test('returns sorted ids so Settings can offer the live list', () async {
      final service = serviceThat(
        (request) async => jsonResponse({
          'data': [
            {'id': 'text-embedding-3-small'},
            {'id': 'gpt-5.6-luna'},
            {'id': 'gpt-5.6-terra'},
          ],
        }),
      );
      expect(await service.listModels(), [
        'gpt-5.6-luna',
        'gpt-5.6-terra',
        'text-embedding-3-small',
      ]);
    });
  });
}
