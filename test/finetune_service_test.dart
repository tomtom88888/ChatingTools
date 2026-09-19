import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:replylikeme/models/chat_turn.dart';
import 'package:replylikeme/models/finetune_job.dart';
import 'package:replylikeme/models/stored_exchange.dart';
import 'package:replylikeme/services/finetune_service.dart';
import 'package:replylikeme/services/openai_exception.dart';
import 'package:replylikeme/services/openai_service.dart';

ChatTurn turn(String sender, String text) =>
    ChatTurn(sender: sender, text: text, messageCount: 1);

StoredExchange stored(List<ChatTurn> context, String reply) => StoredExchange(
  id: 1,
  context: context,
  contextText: context.map((t) => '${t.sender}: ${t.text}').join('\n'),
  replyText: reply,
  vector: Float32List(2),
);

void main() {
  group('buildJsonl', () {
    test('writes one chat-format object per line', () {
      final jsonl = FineTuneService.buildJsonl(
        [
          stored([turn('Sam', 'pub?')], 'go on then'),
          stored([turn('Sam', 'when')], 'half 8'),
        ],
        myName: 'Robin',
        theirName: 'Sam',
        contextTurns: 10,
      );

      final lines = jsonl.trim().split('\n');
      expect(lines, hasLength(2));

      final first = jsonDecode(lines.first) as Map<String, Object?>;
      final messages = (first['messages']! as List)
          .cast<Map<String, Object?>>();
      expect(messages.first['role'], 'system');
      expect(messages.first['content'], contains('Robin'));
      expect(messages.first['content'], contains('Sam'));
      expect(messages[1], {'role': 'user', 'content': 'pub?'});
      expect(messages.last, {'role': 'assistant', 'content': 'go on then'});
    });

    test('maps my earlier turns to assistant and theirs to user', () {
      final jsonl = FineTuneService.buildJsonl(
        [
          stored([
            turn('Sam', 'you free'),
            turn('Robin', 'maybe'),
            turn('Sam', 'pub then'),
          ], 'go on then'),
        ],
        myName: 'Robin',
        theirName: 'Sam',
        contextTurns: 10,
      );
      final messages =
          ((jsonDecode(jsonl.trim()) as Map)['messages']! as List)
              .cast<Map<String, Object?>>();
      expect(messages.map((m) => m['role']), [
        'system',
        'user',
        'assistant',
        'user',
        'assistant',
      ]);
    });

    test('ends every line with my reply as the assistant target', () {
      final jsonl = FineTuneService.buildJsonl(
        [stored([turn('Sam', 'a'), turn('Robin', 'b'), turn('Sam', 'c')], 'd')],
        myName: 'Robin',
        theirName: 'Sam',
        contextTurns: 10,
      );
      final messages =
          ((jsonDecode(jsonl.trim()) as Map)['messages']! as List)
              .cast<Map<String, Object?>>();
      expect(messages.last['role'], 'assistant');
      expect(messages.last['content'], 'd');
      expect(messages[messages.length - 2]['role'], 'user');
    });

    test('honours the context-turn limit', () {
      final context = [
        for (var i = 0; i < 20; i++)
          turn(i.isEven ? 'Sam' : 'Robin', 'turn $i'),
      ];
      final jsonl = FineTuneService.buildJsonl(
        [stored(context, 'reply')],
        myName: 'Robin',
        theirName: 'Sam',
        contextTurns: 4,
      );
      final messages =
          ((jsonDecode(jsonl.trim()) as Map)['messages']! as List)
              .cast<Map<String, Object?>>();
      // system + 4 context turns + the target
      expect(messages, hasLength(6));
      expect(messages[1]['content'], 'turn 16');
    });

    test('skips exchanges with no reply or no context', () {
      final jsonl = FineTuneService.buildJsonl(
        [
          stored([turn('Sam', 'a')], '   '),
          stored(const [], 'orphan'),
          stored([turn('Sam', 'a')], 'real'),
        ],
        myName: 'Robin',
        theirName: 'Sam',
        contextTurns: 10,
      );
      expect(jsonl.trim().split('\n'), hasLength(1));
    });

    test('is empty, not malformed, when there is nothing to write', () {
      expect(
        FineTuneService.buildJsonl(
          const [],
          myName: 'Robin',
          theirName: 'Sam',
          contextTurns: 10,
        ),
        isEmpty,
      );
    });

    test('every line is valid JSON on its own', () {
      final jsonl = FineTuneService.buildJsonl(
        [
          stored([turn('Sam', 'line\nbreaks "and" quotes')], 'fine \u{1f600}'),
        ],
        myName: 'Robin',
        theirName: 'Sam',
        contextTurns: 10,
      );
      expect(jsonl.trim().split('\n'), hasLength(1));
      expect(() => jsonDecode(jsonl.trim()), returnsNormally);
    });
  });

  group('estimate', () {
    test('counts message content across epochs', () {
      final jsonl = FineTuneService.buildJsonl(
        [
          for (var i = 0; i < 12; i++)
            stored([turn('Sam', 'question $i')], 'answer $i'),
        ],
        myName: 'Robin',
        theirName: 'Sam',
        contextTurns: 10,
      );
      final estimate = FineTuneService.estimate(jsonl, epochs: 3);

      expect(estimate.exampleCount, 12);
      expect(estimate.epochs, 3);
      expect(estimate.estimatedTotalTokens, estimate.estimatedTokensPerEpoch * 3);
      expect(estimate.estimatedTokensPerEpoch, greaterThan(0));
      expect(estimate.estimatedUsd, greaterThan(0));
    });

    test('never shows a real cost as zero', () {
      final jsonl = FineTuneService.buildJsonl(
        [stored([turn('Sam', 'hi')], 'yo')],
        myName: 'Robin',
        theirName: 'Sam',
        contextTurns: 10,
      );
      expect(FineTuneService.estimate(jsonl).formattedUsd, r'<$0.01');
    });

    test('an empty dataset costs nothing', () {
      final estimate = FineTuneService.estimate('');
      expect(estimate.exampleCount, 0);
      expect(estimate.estimatedUsd, 0);
      expect(estimate.formattedUsd, r'$0.00');
    });
  });

  group('start', () {
    OpenAiService serviceThat(
      Future<http.Response> Function(http.BaseRequest, List<int>) handler,
    ) => OpenAiService(
      apiKey: 'sk-test-0123456789abcdefghij',
      maxRetries: 0,
      client: MockClient.streaming((request, bodyStream) async {
        final body = await bodyStream.toBytes();
        final response = await handler(request, body);
        return http.StreamedResponse(
          Stream.value(response.bodyBytes),
          response.statusCode,
          headers: response.headers,
        );
      }),
    );

    http.Response ok(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

    String jsonlWith(int examples) => FineTuneService.buildJsonl(
      [
        for (var i = 0; i < examples; i++)
          stored([turn('Sam', 'q$i')], 'a$i'),
      ],
      myName: 'Robin',
      theirName: 'Sam',
      contextTurns: 10,
    );

    test("refuses a dataset below OpenAI's minimum without uploading", () async {
      var calls = 0;
      final service = serviceThat((request, body) async {
        calls++;
        return ok(const {});
      });
      await expectLater(
        FineTuneService(openai: service).start(
          jsonl: jsonlWith(3),
          baseModel: 'gpt-4o-mini-2024-07-18',
        ),
        throwsA(
          isA<OpenAiException>().having(
            (e) => e.message,
            'message',
            contains('at least 10 examples'),
          ),
        ),
      );
      expect(calls, 0);
    });

    test('uploads the file, then creates the job with it', () async {
      final paths = <String>[];
      Map<String, Object?>? jobBody;
      final service = serviceThat((request, body) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/files')) {
          final text = utf8.decode(body);
          expect(text, contains('replylikeme-training.jsonl'));
          expect(text, contains('fine-tune'));
          return ok(const {'id': 'file-abc'});
        }
        jobBody = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
        return ok(const {
          'id': 'ftjob-1',
          'status': 'queued',
          'model': 'gpt-4o-mini-2024-07-18',
        });
      });

      final job = await FineTuneService(openai: service).start(
        jsonl: jsonlWith(12),
        baseModel: 'gpt-4o-mini-2024-07-18',
        suffix: 'replylikeme',
        epochs: 3,
      );

      expect(paths, ['/v1/files', '/v1/fine_tuning/jobs']);
      expect(jobBody!['training_file'], 'file-abc');
      expect(jobBody!['suffix'], 'replylikeme');
      expect(job.id, 'ftjob-1');
      expect(job.status, FineTuneStatus.queued);
      expect(job.isTerminal, isFalse);
    });

    test('surfaces a refusal from an account that cannot fine-tune', () async {
      final service = serviceThat((request, body) async {
        if (request.url.path.endsWith('/files')) {
          return ok(const {'id': 'file-abc'});
        }
        return http.Response(
          jsonEncode(const {
            'error': {
              'message':
                  'Fine-tuning is not available for this organization.',
            },
          }),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      await expectLater(
        FineTuneService(openai: service).start(
          jsonl: jsonlWith(12),
          baseModel: 'gpt-4o-mini-2024-07-18',
        ),
        throwsA(
          isA<OpenAiException>()
              .having((e) => e.kind, 'kind', OpenAiErrorKind.notAvailable)
              .having(
                (e) => e.message,
                'message',
                contains('not available for this organization'),
              ),
        ),
      );
    });
  });

  group('watch', () {
    test('polls until the job is terminal, then stops', () async {
      final statuses = ['queued', 'running', 'succeeded'];
      var call = 0;
      final service = OpenAiService(
        apiKey: 'sk-test-0123456789abcdefghij',
        maxRetries: 0,
        client: MockClient((request) async {
          final status = statuses[call.clamp(0, statuses.length - 1)];
          call++;
          return http.Response(
            jsonEncode({
              'id': 'ftjob-1',
              'status': status,
              'model': 'gpt-4o-mini-2024-07-18',
              if (status == 'succeeded')
                'fine_tuned_model': 'ft:gpt-4o-mini-2024-07-18:me::xyz',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final seen = await FineTuneService(openai: service)
          .watch('ftjob-1', interval: Duration.zero)
          .toList();

      expect(seen.map((j) => j.status), [
        FineTuneStatus.queued,
        FineTuneStatus.running,
        FineTuneStatus.succeeded,
      ]);
      expect(seen.last.fineTunedModel, 'ft:gpt-4o-mini-2024-07-18:me::xyz');
      expect(call, 3);
    });

    test('stops on failure and keeps the reason', () async {
      final service = OpenAiService(
        apiKey: 'sk-test-0123456789abcdefghij',
        maxRetries: 0,
        client: MockClient(
          (request) async => http.Response(
            jsonEncode(const {
              'id': 'ftjob-1',
              'status': 'failed',
              'model': 'gpt-4o-mini-2024-07-18',
              'error': {'message': 'training file was invalid'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final seen = await FineTuneService(openai: service)
          .watch('ftjob-1', interval: Duration.zero)
          .toList();
      expect(seen, hasLength(1));
      expect(seen.single.status, FineTuneStatus.failed);
      expect(seen.single.error, 'training file was invalid');
    });
  });
}
