import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:replylikeme/main.dart';
import 'package:replylikeme/models/app_settings.dart';
import 'package:replylikeme/models/chat_stats.dart';
import 'package:replylikeme/models/chat_turn.dart';
import 'package:replylikeme/models/stored_exchange.dart';
import 'package:replylikeme/screens/settings_screen.dart';
import 'package:replylikeme/services/memory_exchange_store.dart';
import 'package:replylikeme/services/whatsapp_parser.dart';
import 'package:replylikeme/state/providers.dart';
import 'package:replylikeme/widgets/paper_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory style memory, so no database is touched.
typedef FakeStore = MemoryExchangeStore;

/// Stands in for the keystore-backed notifier.
class FakeApiKey extends ApiKeyNotifier {
  FakeApiKey(this.key);

  final String? key;

  @override
  Future<String?> build() async => key;
}

StoredExchange exampleExchange({int chatId = 1}) => StoredExchange(
  id: -1,
  chatId: chatId,
  context: const [ChatTurn(sender: 'Sam', text: 'pub?', messageCount: 1)],
  contextText: 'Sam: pub?',
  replyText: 'go on then',
  vector: Float32List(2),
);

ChatMemory exampleChat({int id = 1, String them = 'Sam'}) => ChatMemory(
  id: id,
  embeddingModel: AppSettings.defaultEmbeddingModel,
  dimensions: 512,
  myName: 'Robin',
  theirName: them,
  builtAt: DateTime(2026, 9, 19, 14, 30),
);

/// A store holding one learned chat with Sam.
FakeStore trainedStore() =>
    FakeStore(chats: [exampleChat()], rows: [exampleExchange()]);

/// The test viewport is short, so anything below the fold has to be scrolled
/// into view before it is built at all.
Future<void> scrollTo(WidgetTester tester, Finder target) async {
  await tester.dragUntilVisible(
    target,
    find.byType(ListView).last,
    const Offset(0, -200),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpApp(
  WidgetTester tester, {
  String? apiKey,
  FakeStore? store,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiKeyProvider.overrideWith(() => FakeApiKey(apiKey)),
        exchangeStoreProvider.overrideWithValue(store ?? FakeStore()),
      ],
      child: const ReplyLikeMeApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ReceiveSharingIntent.setMockValues(
      initialMedia: const [],
      mediaStream: const Stream.empty(),
    );
  });

  testWidgets('with no key saved, the app opens on setup', (tester) async {
    await pumpApp(tester);

    expect(find.text('Your OpenAI API key'), findsOneWidget);
    expect(find.text('Check key & continue'), findsOneWidget);
    // The privacy promise is made before the key is asked for.
    expect(find.text('WHERE YOUR WORDS GO'), findsOneWidget);
    expect(
      find.text('Your chat file stays on this phone. Always.'),
      findsOneWidget,
    );
  });

  testWidgets('a malformed key is rejected without a network call', (
    tester,
  ) async {
    await pumpApp(tester);

    // The design dims the button until there is something to check, so the
    // frame has to land before it can be tapped.
    await tester.enterText(find.byType(TextField), 'not-a-key');
    await tester.pump();
    await tester.tap(find.text('Check key & continue'));
    await tester.pump();

    expect(find.textContaining('OpenAI keys start with sk-'), findsOneWidget);
  });

  testWidgets('with a key but nothing learned, home says so', (tester) async {
    await pumpApp(tester, apiKey: 'sk-test-0123456789abcdefghij');

    expect(find.text('REPLYLIKEME'), findsOneWidget);
    expect(find.text("It doesn't know you yet."), findsOneWidget);
    expect(find.text('Teach it your voice'), findsOneWidget);

    // Writing a reply is locked until there is something to imitate.
    expect(find.text('Write a reply'), findsOneWidget);
    expect(
      find.text('Nothing learned yet \u2014 teach it first'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('a trained memory is summarised on home', (tester) async {
    await pumpApp(
      tester,
      apiKey: 'sk-test-0123456789abcdefghij',
      store: trainedStore(),
    );

    // The hero names who it knows and how much of you it read. 'Sam' appears
    // three times: in the hero, in the chat list, and in the learning-from
    // pair.
    expect(find.text('Sam'), findsNWidgets(3));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('of your replies learned'), findsOneWidget);
    // The two names are separate widgets, so their order is fixed by the
    // widget list rather than by bidirectional text resolution.
    final pair = tester.widget<NamePairValue>(find.byType(NamePairValue));
    expect(pair.me, 'Robin');
    expect(pair.them, 'Sam');

    expect(find.textContaining('text-embedding-3-small'), findsOneWidget);

    // Trained, writing leads and refreshing is the secondary action.
    expect(find.text('Write a reply'), findsOneWidget);
    expect(find.text('From a screenshot or pasted chat'), findsOneWidget);
    expect(find.text('Add or refresh a chat'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });

  testWidgets('settings opens and shows the masked key and defaults', (
    tester,
  ) async {
    await pumpApp(
      tester,
      apiKey: 'sk-proj-0123456789abcdefghij',
      store: FakeStore(chats: [exampleChat()]),
    );

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    // Masked, never the whole key.
    expect(find.text('sk-proj******ghij'), findsOneWidget);
    expect(find.text('sk-proj-0123456789abcdefghij'), findsNothing);

    // The defaults the README documents. The vision and generation fields
    // share a default, so that id appears twice.
    expect(find.text(AppSettings.defaultVisionModel), findsNWidgets(2));
    expect(find.text(AppSettings.defaultEmbeddingModel), findsOneWidget);

    await scrollTo(tester, find.text('Style memory'));
    expect(find.text('Style memory'), findsOneWidget);
    expect(find.text('Fine-tuned'), findsOneWidget);

    // Spending is tallied on the phone; nothing has been spent yet.
    await scrollTo(tester, find.text('SPENDING'));
    expect(find.text('nothing yet'), findsOneWidget);
    expect(find.text('Chat input price'), findsOneWidget);

    await scrollTo(tester, find.text('Delete all my data'));
    expect(find.text('Delete all my data'), findsOneWidget);
  });

  testWidgets('the system prompt is editable and resettable', (tester) async {
    await pumpApp(
      tester,
      apiKey: 'sk-test-0123456789abcdefghij',
      store: FakeStore(chats: [exampleChat()]),
    );

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    await scrollTo(
      tester,
      find.text('What the model is told before your examples'),
    );

    // Unedited, there is nothing to undo, so no reset is offered.
    expect(find.text('Reset to default'), findsNothing);

    final field = find.byWidgetPredicate(
      (w) => w is TextField && (w.controller?.text ?? '').contains('{me}'),
    );
    expect(field, findsOneWidget);

    await tester.enterText(field, 'Answer as {me}. Be terse.');
    await tester.pump();
    // The edit is committed when the field loses focus.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    await scrollTo(tester, find.text('Reset to default'));
    expect(find.text('Reset to default'), findsOneWidget);

    await tester.tap(find.text('Reset to default'));
    await tester.pumpAndSettle();
    expect(find.text('Reset to default'), findsNothing);
  });

  testWidgets('the delete dialog separates the data from the key', (
    tester,
  ) async {
    final store = trainedStore();
    await pumpApp(tester, apiKey: 'sk-test-0123456789abcdefghij', store: store);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Delete all my data'));
    await tester.tap(find.text('Delete all my data'));
    await tester.pumpAndSettle();

    expect(find.text('Delete all my data?'), findsOneWidget);
    expect(find.text('Delete, keep my key'), findsOneWidget);

    await tester.tap(find.text('Delete, keep my key'));
    await tester.pumpAndSettle();

    expect(store.rows, isEmpty);
    expect(await store.chats(), isEmpty);
  });

  testWidgets('each chat has a tick box that decides what is written from', (
    tester,
  ) async {
    final store = FakeStore(
      chats: [
        exampleChat(),
        exampleChat(id: 2, them: 'Mum'),
      ],
      rows: [exampleExchange(), exampleExchange(chatId: 2)],
    );
    await pumpApp(tester, apiKey: 'sk-test-0123456789abcdefghij', store: store);

    expect(find.text('CHATS IT WRITES FROM'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(find.text('Sam & Mum'), findsWidgets);
    expect(find.text('2 of 2 on'), findsOneWidget);

    // Unticking one takes it out of the hero and out of the store's set.
    await tester.ensureVisible(find.byKey(const ValueKey('chat-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-2')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 on'), findsOneWidget);
    expect((await store.chats()).last.enabled, isFalse);

    // With nothing ticked, writing is locked until something is.
    await tester.ensureVisible(find.byKey(const ValueKey('chat-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-1')));
    await tester.pumpAndSettle();
    expect(find.text('Tick at least one chat above'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('chat data asks for a re-import when a chat has no numbers', (
    tester,
  ) async {
    await pumpApp(
      tester,
      apiKey: 'sk-test-0123456789abcdefghij',
      store: FakeStore(chats: [exampleChat()], rows: [exampleExchange()]),
    );
    await scrollTo(tester, find.text('Chat data'));
    await tester.tap(find.text('Chat data'));
    await tester.pumpAndSettle();

    expect(find.text('No numbers yet'), findsOneWidget);
    expect(find.text('Counted on your phone. No API calls.'), findsOneWidget);
  });

  testWidgets('chat data shows the numbers for the chat picked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 9000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final stats = ChatStats.from(
      WhatsAppParser.parse(
        '02/03/2026, 09:00 - Sam: pub tonight?\n'
        '02/03/2026, 09:04 - Robin: go on then\n'
        '02/03/2026, 21:00 - Sam: home safe?\n'
        '02/03/2026, 21:02 - Robin: yep',
      ),
      myName: 'Robin',
    );
    await pumpApp(
      tester,
      apiKey: 'sk-test-0123456789abcdefghij',
      store: FakeStore(
        chats: [
          exampleChat().copyWith(stats: stats),
          exampleChat(id: 2, them: 'Mum'),
        ],
        rows: [exampleExchange(), exampleExchange(chatId: 2)],
      ),
    );
    await tester.tap(find.text('Chat data'));
    await tester.pumpAndSettle();

    // Sam's chat is first, and has numbers.
    expect(find.text('4'), findsWidgets);
    expect(find.text('Typical reply time'), findsOneWidget);
    expect(find.text('3 min'), findsOneWidget, reason: 'median of 4 and 2');
    expect(find.text('Through the day'), findsOneWidget);
    expect(find.text('WHAT STANDS OUT'), findsOneWidget);
    expect(find.text('09:00–10:00 · 2 messages — the busiest'), findsOneWidget);

    // Tapping a bar reads out that bar.
    final hours = find.byKey(const ValueKey('by-hour'));
    final bars = find.descendant(
      of: hours,
      matching: find.byType(GestureDetector),
    );
    await tester.tap(bars.at(21));
    await tester.pumpAndSettle();
    expect(find.text('21:00–22:00 · 2 messages'), findsOneWidget);

    // Mum's chat was imported before numbers were counted.
    await tester.tap(find.text('Mum'));
    await tester.pumpAndSettle();
    expect(find.text('No numbers yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
