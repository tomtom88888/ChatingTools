import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:replylikeme/models/app_settings.dart';
import 'package:replylikeme/models/chat_turn.dart';
import 'package:replylikeme/models/extracted_message.dart';
import 'package:replylikeme/models/stored_exchange.dart';
import 'package:replylikeme/services/openai_exception.dart';
import 'package:replylikeme/services/openai_service.dart';
import 'package:replylikeme/services/reply_generator.dart';

ChatTurn turn(String sender, String text) =>
    ChatTurn(sender: sender, text: text, messageCount: 1);

ScoredExchange example(String context, String reply, double similarity) =>
    ScoredExchange(
      similarity: similarity,
      exchange: StoredExchange(
        id: 1,
        context: [turn('Sam', context)],
        contextText: 'Sam: $context',
        replyText: reply,
        vector: Float32List(2),
      ),
    );

void main() {
  const settings = AppSettings(myName: 'Robin', theirName: 'Sam');

  group('turnsFrom', () {
    test('merges consecutive messages from one side, as training did', () {
      final turns = ReplyGenerator.turnsFrom(
        const [
          ExtractedMessage(speaker: Speaker.them, text: 'yo'),
          ExtractedMessage(speaker: Speaker.them, text: 'you up?'),
          ExtractedMessage(speaker: Speaker.me, text: 'barely'),
          ExtractedMessage(speaker: Speaker.them, text: 'lol'),
        ],
        myName: 'Robin',
        theirName: 'Sam',
      );

      expect(turns, hasLength(3));
      expect(turns.first.sender, 'Sam');
      expect(turns.first.text, 'yo\nyou up?');
      expect(turns.first.messageCount, 2);
      expect(turns[1].sender, 'Robin');
    });

    test('skips blank bubbles', () {
      final turns = ReplyGenerator.turnsFrom(
        const [
          ExtractedMessage(speaker: Speaker.them, text: '   '),
          ExtractedMessage(speaker: Speaker.them, text: 'hi'),
        ],
        myName: 'Robin',
        theirName: 'Sam',
      );
      expect(turns.single.messageCount, 1);
    });
  });

  group('prompts', () {
    test('the system prompt names every trait that must be matched', () {
      final prompt = ReplyGenerator.buildSystemPrompt(settings);
      expect(prompt, contains('Robin'));
      expect(prompt, contains('Sam'));
      for (final trait in [
        'tone',
        'length',
        'slang',
        'emoji',
        'capitalisation',
        'language',
      ]) {
        expect(prompt.toLowerCase(), contains(trait));
      }
      expect(prompt, contains('never sound like an assistant'));
    });

    test('the user prompt carries the retrieved real examples', () {
      final prompt = ReplyGenerator.buildUserPrompt(
        conversation: [turn('Sam', 'pub later?')],
        examples: [example('drinks tonight?', 'yeah go on then', 0.9)],
        settings: settings,
        askForJson: true,
      );
      expect(prompt, contains('Sam: drinks tonight?'));
      expect(prompt, contains('yeah go on then'));
      expect(prompt, contains('Sam: pub later?'));
      expect(prompt, contains('"replies"'));
    });

    test('says so plainly when there is nothing to retrieve', () {
      final prompt = ReplyGenerator.buildUserPrompt(
        conversation: [turn('Sam', 'hi')],
        examples: const [],
        settings: settings,
        askForJson: true,
      );
      expect(prompt, contains('No past examples'));
    });

    test('trims the conversation to the configured context window', () {
      final prompt = ReplyGenerator.buildUserPrompt(
        conversation: [
          turn('Sam', 'one'),
          turn('Robin', 'two'),
          turn('Sam', 'three'),
        ],
        examples: const [],
        settings: settings.copyWith(contextTurns: 2),
        askForJson: true,
      );
      expect(prompt, isNot(contains('one')));
      expect(prompt, contains('three'));
    });

    test('asks for a bare message when a fine-tuned model will answer', () {
      final prompt = ReplyGenerator.buildUserPrompt(
        conversation: [turn('Sam', 'hi')],
        examples: const [],
        settings: settings,
        askForJson: false,
      );
      expect(prompt, contains('Output only the message itself'));
      expect(prompt, isNot(contains('"replies"')));
    });
  });

  group('parseVariants', () {
    test('reads the replies array', () {
      final variants = ReplyGenerator.parseVariants(
        '{"replies":["yeah","yeah go on","cant tonight sorry"]}',
        expected: 3,
      );
      expect(variants, ['yeah', 'yeah go on', 'cant tonight sorry']);
    });

    test('drops duplicates that differ only in case', () {
      final variants = ReplyGenerator.parseVariants(
        '{"replies":["Yeah","yeah","nah"]}',
        expected: 3,
      );
      expect(variants, ['Yeah', 'nah']);
    });

    test('caps at the requested count', () {
      final variants = ReplyGenerator.parseVariants(
        '{"replies":["a","b","c","d","e"]}',
        expected: 3,
      );
      expect(variants, hasLength(3));
    });

    test('strips the quotes and labels models like to add', () {
      final variants = ReplyGenerator.parseVariants(
        '{"replies":["\\"yeah ok\\"","Reply: on my way"]}',
        expected: 2,
      );
      expect(variants, ['yeah ok', 'on my way']);
    });

    test('falls back to the whole answer when the model ignores JSON', () {
      final variants = ReplyGenerator.parseVariants(
        'yeah sounds good',
        expected: 3,
      );
      expect(variants, ['yeah sounds good']);
    });

    test('complains when there is nothing usable at all', () {
      expect(
        () => ReplyGenerator.parseVariants('{"replies":[]}', expected: 3),
        throwsA(isA<OpenAiException>()),
      );
    });
  });

  group('generate', () {
    OpenAiService serviceThat(
      Future<http.Response> Function(http.Request) handler,
    ) => OpenAiService(
      apiKey: 'sk-test-0123456789abcdefghij',
      client: MockClient(handler),
      maxRetries: 0,
    );

    http.Response chatReply(String content) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': content},
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

    test('makes one JSON call with a base model', () async {
      var calls = 0;
      Map<String, Object?>? sent;
      final generator = ReplyGenerator(
        openai: serviceThat((request) async {
          calls++;
          sent = jsonDecode(request.body) as Map<String, Object?>;
          return chatReply('{"replies":["a","b","c"]}');
        }),
      );

      final variants = await generator.generate(
        conversation: [turn('Sam', 'pub?')],
        examples: [example('drinks?', 'go on then', 0.8)],
        settings: settings,
      );

      expect(variants, ['a', 'b', 'c']);
      expect(calls, 1);
      expect(sent!['model'], AppSettings.defaultGenerationModel);
      expect(sent!['response_format'], isNotNull);
    });

    test('uses the fine-tuned model and one plain call per variant', () async {
      final models = <String>[];
      final generator = ReplyGenerator(
        openai: serviceThat((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          models.add(body['model']! as String);
          expect(body.containsKey('response_format'), isFalse);
          return chatReply('reply ${models.length}');
        }),
      );

      final variants = await generator.generate(
        conversation: [turn('Sam', 'pub?')],
        examples: [example('drinks?', 'go on then', 0.8)],
        settings: settings.copyWith(
          mode: TrainingMode.fineTune,
          fineTunedModel: 'ft:gpt-4o-mini-2024-07-18:me::abc123',
          variantCount: 3,
        ),
      );

      expect(variants, ['reply 1', 'reply 2', 'reply 3']);
      expect(models, everyElement('ft:gpt-4o-mini-2024-07-18:me::abc123'));
    });

    test('still sends the retrieved examples to a fine-tuned model', () async {
      String? prompt;
      final generator = ReplyGenerator(
        openai: serviceThat((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          prompt =
              ((body['messages'] as List).last as Map)['content'] as String;
          return chatReply('ok');
        }),
      );

      await generator.generate(
        conversation: [turn('Sam', 'pub?')],
        examples: [example('drinks?', 'go on then', 0.8)],
        settings: settings.copyWith(
          mode: TrainingMode.fineTune,
          fineTunedModel: 'ft:model',
          variantCount: 1,
        ),
      );
      expect(prompt, contains('go on then'));
    });

    test('refuses when the last message is already mine', () async {
      final generator = ReplyGenerator(
        openai: serviceThat((request) async => chatReply('unused')),
      );
      await expectLater(
        generator.generate(
          conversation: [turn('Sam', 'hi'), turn('Robin', 'hey')],
          examples: const [],
          settings: settings,
        ),
        throwsA(
          isA<OpenAiException>().having(
            (e) => e.message,
            'message',
            contains('nothing to reply to'),
          ),
        ),
      );
    });

    test('refuses an empty conversation', () async {
      final generator = ReplyGenerator(
        openai: serviceThat((request) async => chatReply('unused')),
      );
      await expectLater(
        generator.generate(
          conversation: const [],
          examples: const [],
          settings: settings,
        ),
        throwsA(isA<OpenAiException>()),
      );
    });
  });
}
