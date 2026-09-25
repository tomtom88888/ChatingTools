import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:replylikeme/models/app_settings.dart';
import 'package:replylikeme/models/chat_turn.dart';
import 'package:replylikeme/models/reply_suggestion.dart';
import 'package:replylikeme/models/stored_exchange.dart';
import 'package:replylikeme/models/style_profile.dart';
import 'package:replylikeme/screens/generate_screen.dart';
import 'package:replylikeme/services/memory_exchange_store.dart';
import 'package:replylikeme/services/openai_service.dart';
import 'package:replylikeme/services/vector_math.dart';
import 'package:replylikeme/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Key extends ApiKeyNotifier {
  @override
  Future<String?> build() async => 'sk-test-0123456789abcdefghij';
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  late String clipboard;
  late List<Map<String, Object?>> chatBodies;
  late MemoryExchangeStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    clipboard = 'Sam: pub later?\nme: maybe\nSam: go on';
    chatBodies = [];
    store = MemoryExchangeStore(
      chats: [
        ChatMemory(
          id: 1,
          myName: 'Robin',
          theirName: 'Sam',
          embeddingModel: AppSettings.defaultEmbeddingModel,
          dimensions: AppSettings.defaultEmbeddingDimensions,
          builtAt: DateTime(2026, 9, 1),
          profile: StyleProfile.measureTexts([
            for (var i = 0; i < 10; i++) 'yeah\ngo on',
          ]),
        ),
      ],
      rows: [
        StoredExchange(
          id: -1,
          chatId: 1,
          context: const [
            ChatTurn(sender: 'Sam', text: 'pub?', messageCount: 1),
          ],
          contextText: 'Sam: pub?',
          replyText: 'go on then',
          vector: VectorMath.normalise(
            List.filled(AppSettings.defaultEmbeddingDimensions, 1),
          ),
          timestamp: DateTime(2026, 2, 12),
        ),
      ],
    );
  });

  OpenAiService fakeOpenAi() => OpenAiService(
    apiKey: 'sk-test-0123456789abcdefghij',
    maxRetries: 0,
    client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      if (request.url.path.endsWith('/embeddings')) {
        final inputs = body['input']! as List;
        return _json({
          'data': [
            for (var i = 0; i < inputs.length; i++)
              {
                'index': i,
                'embedding': List.filled(
                  AppSettings.defaultEmbeddingDimensions,
                  1,
                ),
              },
          ],
        });
      }
      chatBodies.add(body);
      final system =
          ((body['messages']! as List).first as Map)['content'] as String;
      // Drafts for the answers, for the topic change, or for a tweak.
      final drafts = system.contains('You had drafted')
          ? ['nah']
          : system.contains('do not answer')
          ? ['did you see the match', 'did you see the match']
          : ['yeah\ngo on then\nhalf 8?', 'cant tonight', 'cant tonight'];
      return _json({
        'choices': [
          for (final text in drafts)
            {
              'message': {'content': text},
            },
        ],
      });
    }),
  );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 7200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        if (call.method == 'Clipboard.getData') return {'text': clipboard};
        return null;
      },
    );
    final openai = fakeOpenAi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyProvider.overrideWith(_Key.new),
          exchangeStoreProvider.overrideWithValue(store),
          openAiServiceProvider.overrideWithValue(openai),
        ],
        child: const MaterialApp(home: GenerateScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pasteAndWrite(WidgetTester tester) async {
    await tester.tap(find.text('Paste the conversation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write 3 replies'));
    await tester.pumpAndSettle();
  }

  testWidgets('a pasted chat is written from without a vision call', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Replying to \u2068Sam\u2069'), findsOneWidget);

    await pasteAndWrite(tester);

    // Only generation calls: drafts for the answers and for the topic
    // change. No screenshot to read.
    expect(chatBodies, hasLength(2));
    final messages = chatBodies.first['messages']! as List;
    String content(int i) => (messages[i] as Map)['content'] as String;
    // The live chat is the last turn, your own line marked.
    expect(content(messages.length - 1), 'pub later?\n(you) maybe\ngo on');
    // The stored exchange is in as a real turn: theirs, then your reply.
    expect(content(1), 'pub?');
    expect(content(2), 'go on then');
    final system = content(0);
    expect(system, contains("Measured from 10 of Robin's real replies"));
    expect(system, contains('a line break means a separate bubble'));
    expect(system, contains('- go on then'), reason: 'the voice sample');

    expect(find.text('Three ways you’d answer that'), findsOneWidget);
    expect(find.text('did you see the match'), findsOneWidget);
  });

  testWidgets('a split reply is copied one bubble at a time', (tester) async {
    await pump(tester);
    await pasteAndWrite(tester);

    expect(find.text('reply · 3 bubbles'), findsOneWidget);
    await tester.tap(find.text('Copy 1 of 3'));
    await tester.pumpAndSettle();
    expect(clipboard, 'yeah');
    await tester.tap(find.text('Copy 2 of 3'));
    await tester.pumpAndSettle();
    expect(clipboard, 'go on then');
    await tester.tap(find.text('Copy 3 of 3'));
    await tester.pumpAndSettle();
    expect(clipboard, 'half 8?');
    expect(find.text('All copied'), findsOneWidget);
  });

  testWidgets('a tweak rewrites just that card', (tester) async {
    await pump(tester);
    await pasteAndWrite(tester);

    final card = find.byKey(const ValueKey('reply-1'));
    await tester.tap(find.descendant(of: card, matching: find.text('Shorter')));
    await tester.pumpAndSettle();

    expect(find.text('cant tonight'), findsNothing);
    expect(find.text('nah'), findsOneWidget);
    expect(find.text('did you see the match'), findsOneWidget);
    final refine =
        ((chatBodies.last['messages']! as List).first as Map)['content']
            as String;
    expect(refine, contains('cant tonight'));
    expect(refine, contains('Make it shorter'));
  });

  testWidgets('starring saves into the chat, and the pick is logged', (
    tester,
  ) async {
    await pump(tester);
    await pasteAndWrite(tester);

    final card = find.byKey(const ValueKey('reply-2'));
    await tester.tap(
      find.descendant(of: card, matching: find.byIcon(Icons.star_border)),
    );
    await tester.pumpAndSettle();

    final saved = store.rows.where((r) => r.source == ExchangeSource.saved);
    expect(saved.single.replyText, 'did you see the match');
    expect(saved.single.chatId, 1);
    expect(
      find.descendant(of: card, matching: find.byIcon(Icons.star)),
      findsOneWidget,
    );

    await tester.tap(find.descendant(of: card, matching: find.text('Copy')));
    await tester.pumpAndSettle();

    // The "saved" and "copied" toasts sit over the buttons until they go.
    ScaffoldMessenger.of(
      tester.element(find.byType(GenerateScreen)),
    ).clearSnackBars();
    await tester.pumpAndSettle();

    // Asking for another set retires this one into the log.
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    final entry = store.feedbackLog.first;
    expect(entry.pickedIndex, 2);
    expect(entry.pickedKind, SuggestionKind.newTopic);
    expect(entry.saved, isTrue);
    expect(entry.chatId, 1);
  });

  testWidgets('walking away from every option is logged too', (tester) async {
    await pump(tester);
    await pasteAndWrite(tester);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    final entry = store.feedbackLog.single;
    expect(entry.picked, isFalse);
    expect(entry.shownKinds, hasLength(3));
  });

  testWidgets('a pasted group chat shows who said what', (tester) async {
    clipboard = 'Sam: friday?\nPriya: where though\nme: usual place';
    await pump(tester);
    await tester.tap(find.text('Paste the conversation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this'));
    await tester.pumpAndSettle();
    // Each of the others is named above their bubble, as in WhatsApp.
    expect(find.text('Sam'), findsWidgets);
    expect(find.text('Priya'), findsOneWidget);
  });
}
