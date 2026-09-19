import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replylikeme/models/chat_turn.dart';
import 'package:replylikeme/models/stored_exchange.dart';
import 'package:replylikeme/screens/retrieved_exchanges_screen.dart';

ScoredExchange scored({
  required String theirLine,
  required String myReply,
  required double similarity,
  DateTime? at,
}) => ScoredExchange(
  similarity: similarity,
  exchange: StoredExchange(
    id: 1,
    context: [
      ChatTurn(sender: 'Priya', text: theirLine, messageCount: 1),
    ],
    contextText: 'Priya: $theirLine',
    replyText: myReply,
    vector: Float32List(2),
    timestamp: at,
  ),
);

Future<void> pump(WidgetTester tester, List<ScoredExchange> examples) =>
    tester.pumpWidget(
      MaterialApp(
        home: RetrievedExchangesScreen(
          examples: examples,
          myName: 'Sam',
          theirName: 'Priya',
        ),
      ),
    );

void main() {
  testWidgets('lists the retrieved exchanges, closest first', (tester) async {
    await pump(tester, [
      scored(
        theirLine: 'pub later?',
        myReply: 'go on then',
        similarity: 0.89,
        at: DateTime(2026, 2, 12),
      ),
      scored(
        theirLine: 'drinks?',
        myReply: 'cant tonight',
        similarity: 0.71,
        at: DateTime(2026, 1, 3),
      ),
    ]);

    expect(find.text('2 past exchanges like this one'), findsOneWidget);

    // Both sides of each exchange are readable, which is the point.
    expect(find.text('pub later?'), findsOneWidget);
    expect(find.text('go on then'), findsOneWidget);
    expect(find.text('drinks?'), findsOneWidget);
    expect(find.text('cant tonight'), findsOneWidget);

    // The similarity each one scored, matching the provenance line's figure.
    expect(find.text('0.89'), findsOneWidget);
    expect(find.text('0.71'), findsOneWidget);

    // Dated, so a user can tell recent voice from old voice.
    expect(find.text('12 Feb 2026'), findsOneWidget);
    expect(find.text('3 Jan 2026'), findsOneWidget);

    expect(
      find.textContaining('Nothing was fetched to show this'),
      findsOneWidget,
    );
  });

  testWidgets('says so plainly when retrieval found nothing', (tester) async {
    await pump(tester, const []);

    expect(find.text('Nothing in your memory matched.'), findsOneWidget);
    expect(
      find.textContaining('a general model guessing rather than your own '
          'voice'),
      findsOneWidget,
    );
  });

  testWidgets('copes with an exchange that has no timestamp', (tester) async {
    await pump(tester, [
      scored(theirLine: 'hi', myReply: 'yo', similarity: 0.5),
    ]);

    expect(find.text('date unknown'), findsOneWidget);
    expect(find.text('1 past exchange like this one'), findsOneWidget);
  });

  testWidgets('shows every turn of a multi-turn context', (tester) async {
    await pump(tester, [
      ScoredExchange(
        similarity: 0.8,
        exchange: StoredExchange(
          id: 1,
          context: const [
            ChatTurn(sender: 'Priya', text: 'you free', messageCount: 1),
            ChatTurn(sender: 'Sam', text: 'maybe', messageCount: 1),
            ChatTurn(sender: 'Priya', text: 'pub then', messageCount: 1),
          ],
          contextText: 'x',
          replyText: 'go on then',
          vector: Float32List(2),
        ),
      ),
    ]);

    for (final line in ['you free', 'maybe', 'pub then', 'go on then']) {
      expect(find.text(line), findsOneWidget);
    }
  });
}
