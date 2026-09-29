import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replylikeme/models/chat_message.dart';
import 'package:replylikeme/models/parsed_chat.dart';
import 'package:replylikeme/screens/train_screen.dart';
import 'package:replylikeme/services/chat_export_reader.dart';
import 'package:replylikeme/services/instagram_parser.dart';
import 'package:replylikeme/services/memory_exchange_store.dart';
import 'package:replylikeme/services/share_intake.dart';
import 'package:replylikeme/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:replylikeme/services/whatsapp_parser.dart';
import 'package:replylikeme/widgets/export_guides.dart';

/// What Instagram does to text: UTF-8 bytes written out one per character.
String mangle(String text) => String.fromCharCodes(utf8.encode(text));

int ms(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 3, day, hour, minute).millisecondsSinceEpoch;

/// One message file, newest message first, as Instagram writes it.
String threadJson({
  required String title,
  required List<String> people,
  required List<Map<String, Object?>> messages,
}) => jsonEncode({
  'participants': [
    for (final p in people) {'name': mangle(p)},
  ],
  'messages': [
    for (final m in messages.reversed)
      {
        ...m,
        if (m['sender_name'] is String)
          'sender_name': mangle(m['sender_name']! as String),
        if (m['content'] is String) 'content': mangle(m['content']! as String),
      },
  ],
  'title': mangle(title),
  'is_still_participant': true,
  'thread_path': 'inbox/${title.toLowerCase()}_123',
  'magic_words': [],
});

final mayaThread = threadJson(
  title: 'Maya',
  people: ['Maya', 'Tom Heim'],
  messages: [
    {
      'sender_name': 'Maya',
      'timestamp_ms': ms(1, 20),
      'content': 'café tonight? 😂',
    },
    {
      'sender_name': 'Maya',
      'timestamp_ms': ms(1, 20, 1),
      'content': 'or ramen',
    },
    {
      'sender_name': 'Tom Heim',
      'timestamp_ms': ms(1, 20, 5),
      'content': 'ramen obviously',
    },
    {
      'sender_name': 'Tom Heim',
      'timestamp_ms': ms(1, 20, 6),
      'content': 'Liked a message',
    },
    {
      'sender_name': 'Maya',
      'timestamp_ms': ms(1, 20, 7),
      'content': 'Maya sent an attachment.',
      'share': {'link': 'https://instagram.com/p/x'},
    },
    {
      'sender_name': 'Maya',
      'timestamp_ms': ms(1, 20, 8),
      'photos': [
        {'uri': 'photo.jpg'},
      ],
    },
    {'sender_name': 'Tom Heim', 'timestamp_ms': ms(1, 21), 'call_duration': 60},
    {'sender_name': 'Maya', 'timestamp_ms': ms(2, 9), 'content': 'morning ☀️'},
    {
      'sender_name': 'Tom Heim',
      'timestamp_ms': ms(2, 9, 30),
      'content': 'hey you',
    },
  ],
);

final groupThread = threadJson(
  title: 'Five-a-side',
  people: ['Sam', 'Alex', 'Tom Heim'],
  messages: [
    {'sender_name': 'Sam', 'timestamp_ms': ms(5, 18), 'content': 'pitch at 7?'},
    {'sender_name': 'Tom Heim', 'timestamp_ms': ms(5, 18, 2), 'content': 'in'},
  ],
);

List<int> zipOf(Map<String, String> files) {
  final archive = Archive();
  for (final e in files.entries) {
    final bytes = utf8.encode(e.value);
    archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive);
}

void main() {
  group('repair', () {
    test('undoes the double encoding of accents and emoji', () {
      expect(
        InstagramParser.repair(mangle('café 😂 ☀️ שלום')),
        'café 😂 ☀️ שלום',
      );
    });

    test('leaves plain and already-correct text alone', () {
      expect(InstagramParser.repair('hello'), 'hello');
      expect(InstagramParser.repair('שלום'), 'שלום');
      // Latin-1 that isn't valid UTF-8 bytes stays as it is.
      expect(InstagramParser.repair('naïve'), 'naïve');
    });
  });

  test('a thread reads oldest first, in the shape training expects', () {
    final thread = InstagramParser.thread([mayaThread]);
    expect(thread.title, 'Maya');
    expect(thread.participants, ['Maya', 'Tom Heim']);
    expect(thread.isGroup, isFalse);

    final chat = InstagramParser.toParsedChat(thread);
    expect(chat.format, ExportFormat.instagram);
    expect(chat.senders.toSet(), {'Maya', 'Tom Heim'});
    final texts = [
      for (final m in chat.messages)
        if (m.kind == MessageKind.text) m.text,
    ];
    expect(texts, [
      'café tonight? 😂',
      'or ramen',
      'ramen obviously',
      'morning ☀️',
      'hey you',
    ]);
    expect(chat.mediaCount, 2, reason: 'the shared post and the photo');
    expect(chat.systemCount, 2, reason: 'the like and the call');
    // Maya's two messages in a row are one turn.
    expect(chat.turns.first.text, 'café tonight? 😂\nor ramen');

    final exchanges = WhatsAppParser.buildExchanges(chat.turns, me: 'Tom Heim');
    expect(exchanges.map((e) => e.replyText), ['ramen obviously', 'hey you']);
  });

  test('one message_1.json is one conversation', () {
    final source = ChatExportReader.open(
      utf8.encode(mayaThread),
      filename: 'message_1.json',
    );
    expect(source, isA<InstagramSource>());
    expect((source as InstagramSource).threads.single.title, 'Maya');
  });

  test('a whole-account zip lists every conversation, newest first, and '
      'knows whose it is', () {
    final source = ChatExportReader.open(
      zipOf({
        'your_instagram_activity/messages/inbox/maya_123/message_1.json':
            mayaThread,
        'your_instagram_activity/messages/inbox/fiveaside_9/message_1.json':
            groupThread,
        'your_instagram_activity/likes/liked_posts.json': '{}',
        'media/photo.jpg': 'jpeg',
      }),
      filename: 'instagram-tomheim-2026-09-29.zip',
    );
    final threads = (source as InstagramSource).threads;
    expect(threads.map((t) => t.title), ['Five-a-side', 'Maya']);
    expect(threads.first.isGroup, isTrue);
    expect(InstagramParser.ownerOf(threads), 'Tom Heim');
  });

  test("a long chat's several files are read as one", () {
    final older = threadJson(
      title: 'Maya',
      people: ['Maya', 'Tom Heim'],
      messages: [
        {
          'sender_name': 'Maya',
          'timestamp_ms': ms(1, 8),
          'content': 'first ever',
        },
      ],
    );
    final source = ChatExportReader.open(
      zipOf({
        'messages/inbox/maya_123/message_1.json': mayaThread,
        'messages/inbox/maya_123/message_2.json': older,
      }),
    );
    final thread = (source as InstagramSource).threads.single;
    final chat = InstagramParser.toParsedChat(thread);
    expect(chat.messages.first.text, 'first ever');
  });

  test('WhatsApp exports still read as before', () {
    final source = ChatExportReader.open(
      utf8.encode(
        '12/03/2023, 19:45 - Sam: yo\n12/03/2023, 19:46 - Robin: hey',
      ),
      filename: 'WhatsApp Chat with Sam.txt',
    );
    expect(source, isA<WhatsAppSource>());
  });

  test('a zip with no messages says what to tick', () {
    expect(
      () => ChatExportReader.open(
        zipOf({
          'messages/inbox/empty_1/message_1.json': jsonEncode({
            'participants': [],
            'messages': [],
          }),
        }),
      ),
      throwsA(
        isA<ChatExportException>().having(
          (e) => e.message,
          'message',
          contains('tick Messages and choose JSON'),
        ),
      ),
    );
  });

  testWidgets('the export guide switches between the two apps', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ExportGuides(who: 'Maya')),
        ),
      ),
    );
    expect(
      find.textContaining('Export chat', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('guide-instagram')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Accounts Center', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('JSON', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('Export chat', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('sharing an Instagram zip asks which conversation, then knows '
      'who you are', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final file = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('ig');
      final f = File('${dir.path}/instagram-export.zip');
      await f.writeAsBytes(
        zipOf({
          'messages/inbox/maya_123/message_1.json': mayaThread,
          'messages/inbox/fiveaside_9/message_1.json': groupThread,
        }),
      );
      return f;
    });
    // The shared file is read from disk as the screen opens, which needs
    // real time to pass.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exchangeStoreProvider.overrideWithValue(MemoryExchangeStore()),
          ],
          child: MaterialApp(
            home: TrainScreen(
              sharedExport: SharedExport(
                path: file!.path,
                name: 'instagram-export.zip',
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    expect(find.text('Which conversation?'), findsOneWidget);
    expect(find.text('Five-a-side'), findsOneWidget);
    await tester.tap(find.text('Maya'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    // The name in every conversation is yours, even though Settings has
    // never heard it.
    expect(find.textContaining('Tom Heim', findRichText: true), findsWidgets);
    expect(
      find.textContaining('Instagram export', findRichText: true),
      findsWidgets,
    );
  });
}
