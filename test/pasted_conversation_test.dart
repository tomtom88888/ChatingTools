import 'package:flutter_test/flutter_test.dart';
import 'package:replylikeme/models/extracted_message.dart';
import 'package:replylikeme/services/pasted_conversation.dart';

String render(List<ExtractedMessage> messages) =>
    messages.map((m) => '${m.speaker.name}: ${m.text}').join(' | ');

void main() {
  test('reads export-style lines and finds my side by name', () {
    final messages = PastedConversation.parse(
      '12/03/2023, 19:45 - Sam: pub?\n'
      '12/03/2023, 19:46 - Robin: go on then\n'
      '12/03/2023, 19:46 - Sam: <Media omitted>',
      myName: 'Robin',
    );
    expect(render(messages), 'them: pub? | me: go on then');
  });

  test("reads WhatsApp's copy of several messages", () {
    final messages = PastedConversation.parse(
      '[19:45, 12/03/2023] Sam: pub?\n'
      '[19:46, 12/03/2023] Robin: go on then\n'
      'see you at 8',
      myName: 'robin',
    );
    expect(render(messages), 'them: pub? | me: go on then\nsee you at 8');
  });

  test('"me:" and "I:" mark my lines when no name is set', () {
    final messages = PastedConversation.parse(
      'Sam: you coming?\nme: maybe\nI: depends',
      myName: '',
    );
    expect(render(messages), 'them: you coming? | me: maybe | me: depends');
  });

  test('plain lines become their messages, one per line', () {
    final messages = PastedConversation.parse(
      'are you around later\n\nwant to grab food',
      myName: 'Robin',
    );
    expect(
      render(messages),
      'them: are you around later | them: want to grab food',
    );
  });

  test('nothing pasted is nothing parsed', () {
    expect(PastedConversation.parse('  \n ', myName: 'Robin'), isEmpty);
  });
}
