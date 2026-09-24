import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:replylikeme/models/app_settings.dart';
import 'package:replylikeme/models/chat_turn.dart';
import 'package:replylikeme/models/extracted_message.dart';
import 'package:replylikeme/models/reply_suggestion.dart';
import 'package:replylikeme/models/stored_exchange.dart';
import 'package:replylikeme/models/style_profile.dart';
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
      // The dropped turn's transcript line, not the bare word: the topic-change
      // instruction legitimately says "exactly one".
      expect(prompt, isNot(contains('Sam: one')));
      expect(prompt, contains('Sam: three'));
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

  group('the editable system prompt', () {
    test('the default is a template, not finished text', () {
      expect(AppSettings.defaultSystemPrompt, contains('{me}'));
      expect(AppSettings.defaultSystemPrompt, contains('{them}'));
    });

    test('names are filled in when the prompt is built', () {
      final prompt = ReplyGenerator.buildSystemPrompt(settings);
      expect(prompt, contains('Robin'));
      expect(prompt, contains('Sam'));
      expect(prompt, isNot(contains('{me}')));
      expect(prompt, isNot(contains('{them}')));
    });

    test('an edited prompt replaces the default', () {
      final prompt = ReplyGenerator.buildSystemPrompt(
        settings.copyWith(systemPrompt: 'Answer as {me}. Be terse.'),
      );
      expect(prompt, 'Answer as Robin. Be terse.');
    });

    test('an empty edit falls back rather than sending no instructions', () {
      for (final empty in ['', '   ', '\n']) {
        final s = settings.copyWith(systemPrompt: empty);
        expect(s.effectiveSystemPrompt, AppSettings.defaultSystemPrompt);
        expect(s.hasCustomSystemPrompt, isFalse);
      }
    });

    test('an edit is recognised as one, and reset undoes it', () {
      final edited = settings.copyWith(systemPrompt: 'Be terse.');
      expect(edited.hasCustomSystemPrompt, isTrue);

      final reset = edited.copyWith(resetSystemPrompt: true);
      expect(reset.systemPrompt, isNull);
      expect(reset.hasCustomSystemPrompt, isFalse);
      expect(reset.effectiveSystemPrompt, AppSettings.defaultSystemPrompt);
    });

    test('re-saving the default text is not treated as an edit', () {
      final same = settings.copyWith(
        systemPrompt: AppSettings.defaultSystemPrompt,
      );
      expect(same.hasCustomSystemPrompt, isFalse);
    });

    test('an edited prompt survives being stored and read back', () {
      final edited = settings.copyWith(systemPrompt: 'Answer as {me}.');
      final restored = AppSettings.fromJson(edited.toJson());
      expect(restored.systemPrompt, 'Answer as {me}.');
      expect(restored.hasCustomSystemPrompt, isTrue);
    });

    test('the names still reach an edited prompt that uses the tokens', () {
      final prompt = ReplyGenerator.buildSystemPrompt(
        settings.copyWith(systemPrompt: '{me} is replying to {them}. {me}!'),
      );
      expect(prompt, 'Robin is replying to Sam. Robin!');
    });
  });

  group('parseVariants', () {
    test('reads the typed replies array', () {
      final variants = ReplyGenerator.parseVariants(
        '{"replies":['
        '{"kind":"reply","text":"yeah"},'
        '{"kind":"reply","text":"yeah go on"},'
        '{"kind":"new_topic","text":"anyway did you see the thing"}]}',
        expected: 3,
      );
      expect(variants.map((v) => v.text), [
        'yeah',
        'yeah go on',
        'anyway did you see the thing',
      ]);
      expect(variants.map((v) => v.kind), [
        SuggestionKind.reply,
        SuggestionKind.reply,
        SuggestionKind.newTopic,
      ]);
    });

    test('accepts the spellings a model might choose for the kind', () {
      for (final spelling in ['new_topic', 'newTopic', 'new topic', 'TOPIC']) {
        final variants = ReplyGenerator.parseVariants(
          '{"replies":[{"kind":"$spelling","text":"anyway"}]}',
          expected: 1,
        );
        expect(variants.single.kind, SuggestionKind.newTopic, reason: spelling);
      }
    });

    test('an unknown or missing kind is a plain reply', () {
      final variants = ReplyGenerator.parseVariants(
        '{"replies":[{"text":"yeah"},{"kind":"banter","text":"ha"}]}',
        expected: 2,
      );
      expect(variants.every((v) => v.kind == SuggestionKind.reply), isTrue);
    });

    test('plain strings still work, as plain replies', () {
      final variants = ReplyGenerator.parseVariants(
        '{"replies":["yeah","nah"]}',
        expected: 2,
      );
      expect(variants.map((v) => v.text), ['yeah', 'nah']);
      expect(variants.every((v) => v.kind == SuggestionKind.reply), isTrue);
    });

    test('keeps the first topic change and demotes the rest', () {
      final variants = ReplyGenerator.parseVariants(
        '{"replies":['
        '{"kind":"new_topic","text":"anyway"},'
        '{"kind":"new_topic","text":"also"},'
        '{"kind":"new_topic","text":"oh and"}]}',
        expected: 3,
      );
      expect(variants.where((v) => v.isNewTopic).length, 1);
      expect(variants.first.isNewTopic, isTrue);
    });

    test('never invents a topic change the model did not return', () {
      final variants = ReplyGenerator.parseVariants(
        '{"replies":[{"kind":"reply","text":"yeah"},'
        '{"kind":"reply","text":"nah"}]}',
        expected: 2,
      );
      expect(variants.any((v) => v.isNewTopic), isFalse);
    });

    test('drops duplicates that differ only in case', () {
      final variants = ReplyGenerator.parseVariants(
        '{"replies":["Yeah","yeah","nah"]}',
        expected: 3,
      );
      expect(variants.map((v) => v.text), ['Yeah', 'nah']);
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
        r'{"replies":["\"yeah ok\"","Reply: on my way"]}',
        expected: 2,
      );
      expect(variants.map((v) => v.text), ['yeah ok', 'on my way']);
    });

    test('falls back to the whole answer when the model ignores JSON', () {
      final variants = ReplyGenerator.parseVariants(
        'yeah sounds good',
        expected: 3,
      );
      expect(variants.single.text, 'yeah sounds good');
    });

    test('complains when there is nothing usable at all', () {
      expect(
        () => ReplyGenerator.parseVariants('{"replies":[]}', expected: 3),
        throwsA(isA<OpenAiException>()),
      );
    });
  });

  group('the note', () {
    test('is included and told to outrank the examples', () {
      final prompt = ReplyGenerator.buildUserPrompt(
        conversation: [turn('Sam', 'pub?')],
        examples: const [],
        settings: settings,
        askForJson: true,
        note: "tell her I'm running late",
      );
      expect(prompt, contains("tell her I'm running late"));
      expect(prompt, contains('It decides what the message says'));
      expect(prompt, contains('Do not quote the note back'));
    });

    test('is left out entirely when empty', () {
      for (final empty in ['', '   ']) {
        final prompt = ReplyGenerator.buildUserPrompt(
          conversation: [turn('Sam', 'pub?')],
          examples: const [],
          settings: settings,
          askForJson: true,
          note: empty,
        );
        expect(prompt, isNot(contains('wants this message to do')));
      }
    });
  });

  group('the topic-change option', () {
    test('is asked for once, alongside the plain replies', () {
      final prompt = ReplyGenerator.buildUserPrompt(
        conversation: [turn('Sam', 'pub?')],
        examples: const [],
        settings: settings,
        askForJson: true,
      );
      expect(prompt, contains('Give 3 options'));
      expect(prompt, contains('2 of them answer what was just said'));
      expect(prompt, contains('Exactly one of them does not answer'));
      expect(prompt, contains('new_topic'));
    });

    test('is not asked for when only one option is wanted', () {
      final prompt = ReplyGenerator.buildUserPrompt(
        conversation: [turn('Sam', 'pub?')],
        examples: const [],
        settings: settings.copyWith(variantCount: 1),
        askForJson: true,
      );
      expect(prompt, contains('Give 1 options'));
      expect(prompt, isNot(contains('Exactly one of them does not answer')));
    });

    test('has its own instruction on the fine-tuned path', () {
      final prompt = ReplyGenerator.buildUserPrompt(
        conversation: [turn('Sam', 'pub?')],
        examples: const [],
        settings: settings,
        askForJson: false,
        askForNewTopic: true,
      );
      expect(prompt, contains('do not answer what was just said'));
      expect(prompt, contains('change the topic'));
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
          return chatReply(
            '{"replies":[{"kind":"reply","text":"a"},'
            '{"kind":"reply","text":"b"},'
            '{"kind":"new_topic","text":"c"}]}',
          );
        }),
      );

      final variants = await generator.generate(
        conversation: [turn('Sam', 'pub?')],
        examples: [example('drinks?', 'go on then', 0.8)],
        settings: settings,
      );

      expect(variants.map((v) => v.text), ['a', 'b', 'c']);
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

      expect(variants.map((v) => v.text), ['reply 1', 'reply 2', 'reply 3']);
      expect(models, everyElement('ft:gpt-4o-mini-2024-07-18:me::abc123'));
      // The last of the separate calls is the one asked to change the subject.
      expect(variants.map((v) => v.kind), [
        SuggestionKind.reply,
        SuggestionKind.reply,
        SuggestionKind.newTopic,
      ]);
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

  group('measured style in the prompt', () {
    final chatty = StyleProfile.measure([
      for (var i = 0; i < 10; i++)
        ChatTurn(sender: 'Robin', text: 'haha\nok', messageCount: 2),
    ], me: 'Robin');
    final single = StyleProfile.measureTexts([
      for (var i = 0; i < 10; i++) 'ok',
    ]);

    test('includes the numbers and asks to stay inside them', () {
      final prompt = ReplyGenerator.buildUserPrompt(
        conversation: [turn('Sam', 'pub?')],
        examples: const [],
        settings: settings,
        askForJson: true,
        profile: single,
      );
      expect(prompt, contains('how Robin texts, in numbers'));
      expect(prompt, contains('half are 1 word or fewer'));
      expect(prompt, contains('out of character'));
    });

    test('asks for bubbles on separate lines when I split messages', () {
      final prompt = ReplyGenerator.buildUserPrompt(
        conversation: [turn('Sam', 'pub?')],
        examples: const [],
        settings: settings,
        askForJson: true,
        profile: chatty,
      );
      expect(prompt, contains('several bubbles in a row 100%'));
      expect(prompt, contains('a line break means a separate bubble'));
    });

    test('asks for one bubble when I rarely split', () {
      final prompt = ReplyGenerator.buildUserPrompt(
        conversation: [turn('Sam', 'pub?')],
        examples: const [],
        settings: settings,
        askForJson: false,
        profile: single,
      );
      expect(prompt, contains('single bubble with no line breaks'));
    });

    test('says nothing about style with no profile', () {
      final prompt = ReplyGenerator.buildUserPrompt(
        conversation: [turn('Sam', 'pub?')],
        examples: const [],
        settings: settings,
        askForJson: true,
      );
      expect(prompt, isNot(contains('in numbers')));
      expect(prompt, isNot(contains('bubble')));
    });
  });

  group('refine', () {
    test('sends the draft and the tweak, and keeps what it was for', () async {
      Map<String, Object?>? sent;
      final generator = ReplyGenerator(
        openai: OpenAiService(
          apiKey: 'sk-test-0123456789abcdefghij',
          maxRetries: 0,
          client: MockClient((request) async {
            sent = jsonDecode(request.body) as Map<String, Object?>;
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': '"anyway, weekend?"'},
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      final result = await generator.refine(
        suggestion: const ReplySuggestion(
          text: 'anyway, how are your plans for the weekend looking?',
          kind: SuggestionKind.newTopic,
        ),
        refinement: Refinement.shorter,
        conversation: [turn('Sam', 'pub?')],
        examples: const [],
        settings: settings,
      );

      expect(result.text, 'anyway, weekend?');
      expect(result.kind, SuggestionKind.newTopic);
      final user = ((sent!['messages']! as List).last as Map)['content']
          as String;
      expect(user, contains('--- a draft of that message ---'));
      expect(user, contains('how are your plans for the weekend'));
      expect(user, contains('Make it shorter'));
      // A topic change is refined as a topic change.
      expect(user, contains('do not answer what was just said'));
    });
  });
}
