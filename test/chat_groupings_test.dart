import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:replylikeme/main.dart';
import 'package:replylikeme/models/chat_turn.dart';
import 'package:replylikeme/models/stored_exchange.dart';
import 'package:replylikeme/services/chat_groupings.dart';
import 'package:replylikeme/services/openai_service.dart';
import 'package:replylikeme/services/vector_math.dart';
import 'package:replylikeme/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_smoke_test.dart' show FakeApiKey, FakeStore, exampleChat;

/// A unit vector near axis [axis] of [dims], nudged by [jitter].
Float32List near(int axis, {int dims = 8, double jitter = 0, int seed = 0}) {
  final random = math.Random(seed);
  return VectorMath.normalise([
    for (var d = 0; d < dims; d++)
      (d == axis ? 1.0 : 0.0) + (random.nextDouble() - 0.5) * jitter,
  ]);
}

StoredExchange exchange(
  Float32List vector, {
  String said = 'hi',
  String reply = 'hey',
  int chatId = 1,
}) => StoredExchange(
  id: -1,
  chatId: chatId,
  context: [ChatTurn(sender: 'Sam', text: said, messageCount: 1)],
  contextText: 'Sam: $said',
  replyText: reply,
  vector: vector,
);

OpenAiService fakeOpenAi(
  String Function(Map<String, Object?> body) answer, {
  List<Map<String, Object?>>? sent,
}) => OpenAiService(
  apiKey: 'sk-test-0123456789abcdefghij',
  maxRetries: 0,
  client: MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, Object?>;
    sent?.add(body);
    return http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': answer(body)},
          },
        ],
      }),
      200,
    );
  }),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('KMeans', () {
    test('separates three clear clumps', () {
      final vectors = [
        for (var axis = 0; axis < 3; axis++)
          for (var i = 0; i < 12; i++)
            near(axis, jitter: 0.3, seed: axis * 100 + i),
      ];
      final groups = KMeans.assign(vectors, 3);
      for (var axis = 0; axis < 3; axis++) {
        final clump = groups.sublist(axis * 12, axis * 12 + 12).toSet();
        expect(clump, hasLength(1), reason: 'clump $axis stays together');
      }
      expect(groups.toSet(), hasLength(3));
    });

    test('is the same every run', () {
      final vectors = [
        for (var i = 0; i < 40; i++) near(i % 5, jitter: 0.8, seed: i),
      ];
      expect(KMeans.assign(vectors, 4), KMeans.assign(vectors, 4));
    });

    test('never leaves a group empty, even with duplicates', () {
      final vectors = [for (var i = 0; i < 6; i++) near(0), near(1), near(2)];
      final groups = KMeans.assign(vectors, 5);
      expect(groups.toSet(), {0, 1, 2, 3, 4});
    });

    test('asks for no more groups than there are points', () {
      final groups = KMeans.assign([near(0), near(1)], 10);
      expect(groups.toSet(), hasLength(2));
      expect(KMeans.assign(const [], 3), isEmpty);
    });
  });

  group('ChatGrouper', () {
    test('arranges biggest first, most typical member first', () {
      final exchanges = [
        exchange(near(0), reply: 'a'),
        exchange(near(1, jitter: 0.6, seed: 3), reply: 'b-edge'),
        exchange(near(1), reply: 'b-core'),
        exchange(near(1, jitter: 0.1, seed: 4), reply: 'b-near'),
      ];
      final groups = ChatGrouper.arrange(exchanges, [0, 1, 1, 1]);
      expect(groups.map((g) => g.size), [3, 1]);
      expect(groups.map((g) => g.name), ['Group 1', 'Group 2']);
      expect(groups.first.members.last.replyText, 'b-edge');
    });

    test('reads names out of the reply, fenced or not', () {
      expect(
        ChatGrouper.parseNames(
          '```json\n{"groups": [{"group": 2, "name": " Food plans ", '
          '"about": "Where to eat."}, {"group": 1, "name": ""}, "junk"]}\n```',
        ),
        {2: ('Food plans', 'Where to eat.')},
      );
      expect(ChatGrouper.parseNames('no json here'), isEmpty);
      expect(ChatGrouper.parseNames('{"groups": 3'), isEmpty);
    });

    test('shows the model clipped samples, numbered by group', () {
      final groups = ChatGrouper.arrange(
        [
          exchange(near(0), said: 'pub?', reply: 'go on then'),
          exchange(near(1), said: 'x' * 400, reply: 'ok'),
        ],
        [0, 1],
      );
      final prompt = ChatGrouper.namingPrompt(groups);
      expect(prompt, contains('Group 1 (1 exchanges):'));
      expect(prompt, contains('- them: "pub?" → me: "go on then"'));
      expect(prompt, isNot(contains('x' * 200)));
      expect(prompt, contains('…'));
    });

    test('groups, then names what the model named', () async {
      final sent = <Map<String, Object?>>[];
      final grouper = ChatGrouper(
        openai: fakeOpenAi(
          (_) =>
              '{"groups": [{"group": 1, "name": "Pub", "about": "Drinks."}]}',
          sent: sent,
        ),
      );
      final groups = await grouper.group(
        [
          for (var i = 0; i < 6; i++)
            exchange(near(0, jitter: 0.1, seed: i), said: 'pub?'),
          for (var i = 0; i < 3; i++)
            exchange(near(4, jitter: 0.1, seed: i), said: 'work?'),
          // Built with another fingerprint size: left out.
          exchange(near(0, dims: 4)),
        ],
        count: 2,
        model: 'gpt-test',
      );
      expect(groups.map((g) => (g.name, g.size)), [('Pub', 6), ('Group 2', 3)]);
      expect(groups.first.about, 'Drinks.');
      expect(sent, hasLength(1));
      expect(sent.single['model'], 'gpt-test');
      expect(sent.single['response_format'], {'type': 'json_object'});
    });
  });

  testWidgets('home opens chat groupings, which groups and names', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 9000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final rows = [
      for (var i = 0; i < 8; i++)
        exchange(
          near(i.isEven ? 0 : 3, dims: 512),
          said: i.isEven ? 'pub?' : 'meeting at 9',
          reply: i.isEven ? 'go on then' : 'on my way',
        ),
    ];
    final sent = <Map<String, Object?>>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyProvider.overrideWith(
            () => FakeApiKey('sk-test-0123456789abcdefghij'),
          ),
          exchangeStoreProvider.overrideWithValue(
            FakeStore(
              chats: [exampleChat().copyWith(exchangeCount: rows.length)],
              rows: rows,
            ),
          ),
          chatGrouperProvider.overrideWithValue(
            ChatGrouper(
              openai: fakeOpenAi(
                (_) =>
                    '{"groups": [{"group": 1, "name": "Nights out", '
                    '"about": "Plans for the pub."}, {"group": 2, '
                    '"name": "Work runs", "about": ""}]}',
                sent: sent,
              ),
            ),
          ),
        ],
        child: const DittoApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chat groupings'));
    await tester.pumpAndSettle();
    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('10'), findsOneWidget, reason: 'ten groups by default');

    // Fewer groups, down to two.
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
    }
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text('Group my chats'));
    await tester.pumpAndSettle();

    expect(sent, hasLength(1));
    expect(find.text('Nights out'), findsOneWidget);
    expect(find.text('Plans for the pub.'), findsOneWidget);
    expect(find.text('Work runs'), findsOneWidget);
    expect(find.text('4 · 50%'), findsNWidgets(2));
    expect(find.text('go on then'), findsWidgets);
    expect(find.text('Group again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
