import 'package:flutter_test/flutter_test.dart';
import 'package:replylikeme/models/extracted_message.dart';
import 'package:replylikeme/services/openai_service.dart';
import 'package:replylikeme/services/quoted_replies.dart';

ExtractedMessage them(String text, {String? quoted}) =>
    ExtractedMessage(speaker: Speaker.them, text: text, quoted: quoted);
ExtractedMessage me(String text, {String? quoted}) =>
    ExtractedMessage(speaker: Speaker.me, text: text, quoted: quoted);

List<String> texts(List<ExtractedMessage> messages) => [
  for (final m in messages) m.text,
];

void main() {
  group('a quote the model kept inside the reply', () {
    test('is taken off when it repeats an earlier message', () {
      final cleaned = QuotedReplies.clean([
        them('are you coming to the pub later?'),
        me('are you coming to the pub later? yeah defo'),
      ]);
      expect(texts(cleaned), ['are you coming to the pub later?', 'yeah defo']);
      expect(cleaned.last.quoted, 'are you coming to the pub later?');
    });

    test('is taken off with the quoted name line above it', () {
      final cleaned = QuotedReplies.clean([
        them('pub later?'),
        them('or cinema'),
        me('Sam\npub later?\ngo on then'),
      ]);
      expect(cleaned.last.text, 'go on then');
      expect(cleaned.last.quoted, 'pub later?');
    });

    test('is taken off when the quote box cut it short', () {
      final cleaned = QuotedReplies.clean([
        them('shall we get food before the film or after, your call'),
        me('shall we get food before the…\nafter!'),
      ]);
      expect(cleaned.last.text, 'after!');
    });

    test('is taken off when the model named it but also left it in', () {
      final cleaned = QuotedReplies.clean([
        me('ok', quoted: 'did you book it'),
      ]);
      expect(cleaned.single.text, 'ok');

      final doubled = QuotedReplies.clean([
        me('did you book it\nnot yet', quoted: 'did you book it'),
      ]);
      expect(doubled.single.text, 'not yet');
      expect(doubled.single.quoted, 'did you book it');
    });

    test('works for their replies to my messages too', () {
      final cleaned = QuotedReplies.clean([
        me('want to come over on saturday?'),
        them('You\nwant to come over on saturday?\nyesss'),
      ]);
      expect(cleaned.last.text, 'yesss');
    });
  });

  group('messages that are not quotes', () {
    test('a reply that merely starts with the same short word is kept', () {
      final cleaned = QuotedReplies.clean([them('ok'), me('ok see you then')]);
      expect(texts(cleaned), ['ok', 'ok see you then']);
    });

    test('a match that stops mid-word is kept', () {
      final cleaned = QuotedReplies.clean([
        them('see you at the station'),
        me('see you at the stationery shop?'),
      ]);
      expect(cleaned.last.text, 'see you at the stationery shop?');
    });

    test('a message that is only the earlier text is kept', () {
      final cleaned = QuotedReplies.clean([
        them('happy birthday!!'),
        me('happy birthday!!'),
      ]);
      expect(texts(cleaned), ['happy birthday!!', 'happy birthday!!']);
    });
  });

  test('a quote box transcribed as its own bubble is dropped', () {
    final cleaned = QuotedReplies.clean([
      them('pub later?'),
      me('pub later?'),
      me('go on then', quoted: 'pub later?'),
    ]);
    expect(texts(cleaned), ['pub later?', 'go on then']);
  });

  group('reading a screenshot', () {
    test('the quoted field is read and never ends up in the text', () {
      final messages = OpenAiService.parseExtractedConversation(
        '{"messages":['
        '{"sender":"them","text":"pub later?"},'
        '{"sender":"me","text":"go on then","quoted":"pub later?"}]}',
      );
      expect(texts(messages), ['pub later?', 'go on then']);
      expect(messages.last.quoted, 'pub later?');
    });

    test('a merged quote is split out after parsing', () {
      final messages = OpenAiService.parseExtractedConversation(
        '{"messages":['
        '{"sender":"them","text":"what time is dinner"},'
        '{"sender":"me","text":"what time is dinner 8ish"}]}',
      );
      expect(messages.last.text, '8ish');
    });
  });
}
