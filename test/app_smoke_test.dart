import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:replylikeme/main.dart';
import 'package:replylikeme/models/app_settings.dart';
import 'package:replylikeme/models/chat_turn.dart';
import 'package:replylikeme/models/stored_exchange.dart';
import 'package:replylikeme/screens/settings_screen.dart';
import 'package:replylikeme/services/exchange_store.dart';
import 'package:replylikeme/state/providers.dart';
import 'package:replylikeme/widgets/paper_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory style memory, so no database is touched.
class FakeStore implements ExchangeStore {
  FakeStore({this.savedStats, List<StoredExchange>? rows})
    : rows = rows ?? <StoredExchange>[];

  List<StoredExchange> rows;
  StyleMemoryStats? savedStats;

  @override
  Future<void> replaceAll(
    List<StoredExchange> exchanges, {
    required StyleMemoryStats stats,
  }) async {
    rows = List.of(exchanges);
    savedStats = stats;
  }

  @override
  Future<StyleMemoryStats?> stats() async => savedStats;

  @override
  Future<int> count() async => rows.length;

  @override
  Future<List<StoredExchange>> all() async => rows;

  @override
  Future<List<ScoredExchange>> mostSimilar(
    Float32List query, {
    int limit = 8,
  }) async => const [];

  @override
  Future<void> deleteEverything() async {
    rows = [];
    savedStats = null;
  }
}

/// Stands in for the keystore-backed notifier.
class FakeApiKey extends ApiKeyNotifier {
  FakeApiKey(this.key);

  final String? key;

  @override
  Future<String?> build() async => key;
}

StoredExchange exampleExchange() => StoredExchange(
  id: 1,
  context: const [ChatTurn(sender: 'Sam', text: 'pub?', messageCount: 1)],
  contextText: 'Sam: pub?',
  replyText: 'go on then',
  vector: Float32List(2),
);

StyleMemoryStats exampleStats() => StyleMemoryStats(
  exchangeCount: 1,
  embeddingModel: AppSettings.defaultEmbeddingModel,
  dimensions: 512,
  myName: 'Robin',
  theirName: 'Sam',
  builtAt: DateTime(2026, 9, 19, 14, 30),
);

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
      store: FakeStore(
        savedStats: exampleStats(),
        rows: [exampleExchange()],
      ),
    );

    // The hero names who it knows and how much of you it read. 'Sam' appears
    // twice now: once in the hero, once in the learning-from pair below it.
    expect(find.text('Sam'), findsNWidgets(2));
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
    expect(find.text('From a screenshot of your chat'), findsOneWidget);
    expect(find.text('Refresh the memory'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });

  testWidgets('settings opens and shows the masked key and defaults', (
    tester,
  ) async {
    await pumpApp(
      tester,
      apiKey: 'sk-proj-0123456789abcdefghij',
      store: FakeStore(savedStats: exampleStats()),
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

    await scrollTo(tester, find.text('Delete all my data'));
    expect(find.text('Delete all my data'), findsOneWidget);
  });

  testWidgets('the system prompt is editable and resettable', (tester) async {
    await pumpApp(
      tester,
      apiKey: 'sk-test-0123456789abcdefghij',
      store: FakeStore(savedStats: exampleStats()),
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
    final store = FakeStore(
      savedStats: exampleStats(),
      rows: [exampleExchange()],
    );
    await pumpApp(
      tester,
      apiKey: 'sk-test-0123456789abcdefghij',
      store: store,
    );

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
    expect(store.savedStats, isNull);
  });
}
