import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replylikeme/models/chat_stats.dart';
import 'package:replylikeme/models/stored_exchange.dart';
import 'package:replylikeme/services/whatsapp_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_smoke_test.dart'
    show FakeStore, exampleChat, exampleExchange, pumpApp;

/// Stats for a chat whose last message was sent [ago].
ChatStats endingAgo(Duration ago) {
  final at = DateTime.now().subtract(ago);
  String stamp(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/'
      '${d.year}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final before = at.subtract(const Duration(minutes: 5));
  return ChatStats.from(
    WhatsAppParser.parse(
      '${stamp(before)} - Sam: pub?\n${stamp(at)} - Robin: go on then',
    ),
    myName: 'Robin',
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('an export is out of date a month after its last message', () {
    ChatMemory ending(Duration ago) =>
        exampleChat().copyWith(stats: endingAgo(ago));
    expect(ending(const Duration(days: 10)).isOutOfDate(), isFalse);
    expect(ending(const Duration(days: 40)).isOutOfDate(), isTrue);
    // No dates known: nothing to say.
    expect(exampleChat().isOutOfDate(), isFalse);
  });

  testWidgets('home says when a ticked chat needs a newer export', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 7000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpApp(
      tester,
      apiKey: 'sk-test-0123456789abcdefghij',
      store: FakeStore(
        chats: [
          exampleChat().copyWith(stats: endingAgo(const Duration(days: 45))),
        ],
        rows: [exampleExchange()],
      ),
    );
    expect(find.byKey(const ValueKey('out-of-date')), findsOneWidget);
    expect(find.text('Time for a new export'), findsOneWidget);
    expect(find.textContaining('import a newer export'), findsOneWidget);

    await tester.tap(find.text('Import a newer export'));
    await tester.pumpAndSettle();
    expect(find.textContaining('export'), findsWidgets);
  });

  testWidgets('a recent export says nothing', (tester) async {
    tester.view.physicalSize = const Size(1200, 7000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpApp(
      tester,
      apiKey: 'sk-test-0123456789abcdefghij',
      store: FakeStore(
        chats: [
          exampleChat().copyWith(stats: endingAgo(const Duration(days: 3))),
        ],
        rows: [exampleExchange()],
      ),
    );
    expect(find.byKey(const ValueKey('out-of-date')), findsNothing);
    expect(find.textContaining('import a newer export'), findsNothing);
  });
}
