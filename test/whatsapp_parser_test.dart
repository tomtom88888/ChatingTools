import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:replylikeme/models/chat_message.dart';
import 'package:replylikeme/models/parsed_chat.dart';
import 'package:replylikeme/services/whatsapp_parser.dart';

/// Both fixtures are synthetic — see test/fixtures/README.md.
String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('Android export', () {
    late ParsedChat chat;

    setUpAll(() => chat = WhatsAppParser.parse(_fixture('android_export.txt')));

    test('is detected as the Android layout', () {
      expect(chat.format, ExportFormat.android);
      expect(chat.isEmpty, isFalse);
      expect(chat.unparsedLineCount, 0);
    });

    test('splits every timestamped line into one message', () {
      expect(chat.messages, hasLength(15));
      expect(chat.textMessageCount, 11);
      expect(chat.mediaCount, 1);
      expect(chat.deletedCount, 1);
      expect(chat.systemCount, 2);
    });

    test('counts messages per sender, busiest first', () {
      expect(chat.senderMessageCounts, {'Sam': 8, 'Robin': 5});
      expect(chat.senders.first, 'Sam');
    });

    test('reads day-first dates and the 24-hour clock', () {
      final first = chat.messages.firstWhere((m) => m.isText);
      expect(first.text, 'yo');
      expect(first.timestamp, DateTime(2023, 3, 12, 19, 45));
    });

    test('keeps a multi-line message whole', () {
      final multiline = chat.messages.firstWhere(
        (m) => m.text.startsWith('anyway'),
      );
      expect(
        multiline.text,
        'anyway\nwe could do the late showing\nor just food?',
      );
      expect(multiline.sender, 'Sam');
    });

    test('strips the edit marker but records that it was edited', () {
      final edited = chat.messages.firstWhere((m) => m.wasEdited);
      expect(edited.text, 'food pls');
      expect(edited.kind, MessageKind.text);
    });

    test('splits on the first colon, so colons in the body survive', () {
      final withColon = chat.messages.firstWhere(
        (m) => m.text.contains('8.30'),
      );
      expect(withColon.sender, 'Sam');
      expect(withColon.text, 'deal: 8.30 then');
    });

    test('classifies placeholders and keeps their raw text', () {
      final media = chat.messages.firstWhere(
        (m) => m.kind == MessageKind.media,
      );
      expect(media.sender, 'Sam');
      expect(media.text, isEmpty);
      expect(media.rawText, '<Media omitted>');

      final deleted = chat.messages.firstWhere(
        (m) => m.kind == MessageKind.deleted,
      );
      expect(deleted.rawText, 'This message was deleted');
    });

    test('treats lines WhatsApp wrote itself as system lines', () {
      final system = chat.messages
          .where((m) => m.kind == MessageKind.system)
          .toList();
      expect(system, hasLength(2));
      expect(system.every((m) => m.sender == null), isTrue);
      expect(system.last.rawText, 'Robin created group "weekend plans"');
    });

    test('merges split bubbles and skips placeholders when building turns', () {
      expect(chat.turns, hasLength(9));
      expect(chat.turns.first.sender, 'Sam');
      expect(chat.turns.first.messageCount, 2);
      expect(chat.turns.first.text, 'yo\nyou around tonight?');

      // A photo between two of Sam's lines is not a change of speaker, so the
      // turn after Robin starts at "look at this".
      expect(chat.turns[2].text, 'look at this');
    });

    test('does not merge across an overnight gap', () {
      final morning = chat.turns.firstWhere((t) => t.text == 'morning');
      expect(morning.messageCount, 1);
      expect(morning.firstTimestamp, DateTime(2023, 3, 13, 9, 6));
    });
  });

  group('iOS export', () {
    late ParsedChat chat;

    setUpAll(() => chat = WhatsAppParser.parse(_fixture('ios_export.txt')));

    test('is detected as the iOS layout despite the bidi marks', () {
      expect(chat.format, ExportFormat.ios);
      expect(chat.unparsedLineCount, 0);
      expect(chat.messages, hasLength(11));
    });

    test('reads month-first two-digit dates and the 12-hour clock', () {
      final first = chat.messages.firstWhere((m) => m.isText);
      expect(first.text, 'yo');
      expect(first.timestamp, DateTime(2023, 3, 13, 19, 45, 10));
    });

    test('maps 12 AM to midnight of the next day', () {
      final midnight = chat.messages.firstWhere((m) => m.text == 'yes. 8.30');
      expect(midnight.timestamp, DateTime(2023, 3, 14, 0, 5));
    });

    test('maps 12 PM to noon', () {
      final noon = chat.messages.firstWhere((m) => m.text == 'nice one');
      expect(noon.timestamp, DateTime(2023, 3, 14, 12, 6));
    });

    test('recognises both iOS media forms', () {
      final media = chat.messages
          .where((m) => m.kind == MessageKind.media)
          .toList();
      expect(media, hasLength(2));
      expect(media.first.rawText, startsWith('<attached:'));
      expect(media.last.rawText, 'image omitted');
    });

    test('recognises the iOS deleted wording', () {
      expect(chat.deletedCount, 1);
      expect(
        chat.messages.firstWhere((m) => m.kind == MessageKind.deleted).sender,
        'Sam',
      );
    });

    test('keeps a multi-line message whole', () {
      final turn = chat.turns.firstWhere((t) => t.text.startsWith('haha'));
      // Sam's deleted message in between carries no style, so Robin's two
      // messages stay one turn.
      expect(turn.text, "haha\nthat's so you\nok so food? 🍜");
      expect(turn.messageCount, 2);
    });

    test('builds six turns', () {
      expect(chat.turns, hasLength(6));
      expect(chat.turns.map((t) => t.sender), [
        'Sam',
        'Robin',
        'Sam',
        'Robin',
        'Sam',
        'Robin',
      ]);
    });
  });

  group('normalisation', () {
    test('handles CRLF line endings', () {
      final chat = WhatsAppParser.parse(
        '12/03/2023, 19:45 - Sam: yo\r\n12/03/2023, 19:46 - Robin: hey\r\n',
      );
      expect(chat.messages, hasLength(2));
      expect(chat.messages.last.text, 'hey');
    });

    test('handles the narrow no-break space before AM/PM', () {
      final chat = WhatsAppParser.parse('12/03/2023, 7:45\u202fPM - Sam: yo\n');
      expect(chat.messages.single.timestamp, DateTime(2023, 3, 12, 19, 45));
    });

    test('handles dotted and dashed date separators', () {
      final chat = WhatsAppParser.parse(
        '12.03.2023, 19:45 - Sam: yo\n13.03.2023, 19:45 - Robin: hey\n',
      );
      expect(chat.messages.first.timestamp, DateTime(2023, 3, 12, 19, 45));
    });

    test('reads ISO dates', () {
      final chat = WhatsAppParser.parse('2023-03-12, 19:45 - Sam: yo\n');
      expect(chat.messages.single.timestamp, DateTime(2023, 3, 12, 19, 45));
    });
  });

  group('empty and unusable input', () {
    test('an empty file parses to an empty chat', () {
      expect(WhatsAppParser.parse('').isEmpty, isTrue);
      expect(WhatsAppParser.parse('   \n\n  ').isEmpty, isTrue);
    });

    test('a file that is not an export reports unknown format', () {
      final chat = WhatsAppParser.parse(
        'Dear diary\nnothing happened today\nthe end\n',
      );
      expect(chat.format, ExportFormat.unknown);
      expect(chat.isEmpty, isTrue);
      expect(chat.unparsedLineCount, 3);
    });

    test('a system line containing a colon is not read as a message', () {
      final chat = WhatsAppParser.parse(
        '12/03/2023, 19:45 - Sam: hi\n'
        '12/03/2023, 19:46 - Sam changed the subject to "Trip: Italy"\n'
        '12/03/2023, 19:47 - Robin: nice\n',
      );
      expect(chat.senderMessageCounts, {'Sam': 1, 'Robin': 1});
      expect(chat.systemCount, 1);
      expect(chat.turns, hasLength(2));
    });

    test('a colon inside a very long system line is not a sender', () {
      final chat = WhatsAppParser.parse(
        '12/03/2023, 19:45 - Robin created a group with a name that runs on '
        'well past fifty characters: finally a colon\n',
      );
      expect(chat.systemCount, 1);
      expect(chat.senderMessageCounts, isEmpty);
    });

    test('an export with only system lines yields no turns', () {
      final chat = WhatsAppParser.parse(
        '12/03/2023, 19:44 - Messages and calls are end-to-end encrypted.\n',
      );
      expect(chat.format, ExportFormat.android);
      expect(chat.isEmpty, isTrue);
      expect(chat.systemCount, 1);
    });
  });

  group('buildExchanges', () {
    late ParsedChat chat;

    setUpAll(() => chat = WhatsAppParser.parse(_fixture('android_export.txt')));

    test('pairs their turns with my reply', () {
      final exchanges = WhatsAppParser.buildExchanges(chat.turns, me: 'Robin');
      expect(exchanges, hasLength(4));

      final first = exchanges.first;
      expect(first.reply.sender, 'Robin');
      expect(first.reply.text, 'heyy\nyeah ish, got a thing till 8');
      expect(first.context.single.sender, 'Sam');
      expect(first.contextText, 'Sam: yo\nyou around tonight?');
    });

    test('skips an opener, which has no context to retrieve it by', () {
      final exchanges = WhatsAppParser.buildExchanges(chat.turns, me: 'Sam');
      expect(exchanges.every((e) => e.context.isNotEmpty), isTrue);
      expect(exchanges.every((e) => e.context.last.sender != 'Sam'), isTrue);
      // Sam opens the chat and also speaks twice in a row across the overnight
      // gap; neither is a reply.
      expect(exchanges, hasLength(3));
    });

    test('bounds the context window', () {
      final wide = WhatsAppParser.buildExchanges(
        chat.turns,
        me: 'Robin',
        maxContextTurns: 10,
      );
      final narrow = WhatsAppParser.buildExchanges(
        chat.turns,
        me: 'Robin',
        maxContextTurns: 1,
      );
      expect(narrow, hasLength(wide.length));
      expect(narrow.every((e) => e.context.length == 1), isTrue);
      expect(wide.last.context.length, greaterThan(1));
    });

    test('an unknown name yields nothing rather than throwing', () {
      expect(WhatsAppParser.buildExchanges(chat.turns, me: 'Nobody'), isEmpty);
    });

    test('rejects a context window smaller than one turn', () {
      expect(
        () => WhatsAppParser.buildExchanges(
          chat.turns,
          me: 'Robin',
          maxContextTurns: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
