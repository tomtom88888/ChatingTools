import 'package:flutter_test/flutter_test.dart';
import 'package:replylikeme/models/chat_stats.dart';
import 'package:replylikeme/services/whatsapp_parser.dart';

/// Monday 2 March 2026 onwards, in Android's export layout.
const String export = '''
02/03/2026, 09:00 - Sam: morning! pub tonight?
02/03/2026, 09:04 - Robin: haha yes 😂
02/03/2026, 09:05 - Robin: what time
02/03/2026, 09:35 - Sam: 8 at the usual
02/03/2026, 11:00 - Robin: <Media omitted>
02/03/2026, 23:30 - Sam: you home?
03/03/2026, 01:30 - Sam: hello??
03/03/2026, 02:00 - Robin: sorry fell asleep 😴 😂
04/03/2026, 18:00 - Robin: dinner friday? pub pub pub
04/03/2026, 18:10 - Sam: This message was deleted
''';

void main() {
  final stats = ChatStats.from(WhatsAppParser.parse(export), myName: 'Robin');

  test('counts messages and words per person', () {
    expect(stats.me.messages, 4);
    expect(stats.them.messages, 4);
    expect(stats.totalMessages, 8);
    expect(stats.me.words, 3 + 2 + 5 + 5);
    expect(stats.me.longestMessageWords, 5);
    expect(stats.me.media, 1);
    expect(stats.them.deleted, 1);
    expect(stats.myShare, 0.5);
  });

  test('times replies, and calls a long wait a new conversation', () {
    // Robin answered after 4 min, then after 30 min (01:30 -> 02:00), and
    // after 85 min to "8 at the usual" (the media message). Median: 30 min.
    expect(stats.me.replies, 3);
    expect(stats.me.medianReplySeconds, 30 * 60);
    expect(stats.me.quickReplies, 1);
    // Sam answered after 30 min, 12 h 25 min is too long, 10 min.
    expect(stats.them.replies, 2);
    expect(stats.them.quickReplies, 0);
  });

  test('sees who starts conversations and who double texts', () {
    // Sam opens the export; 23:30 after 12 h of silence is Sam again;
    // Wednesday 18:00 is Robin.
    expect(stats.them.conversationsStarted, 2);
    expect(stats.me.conversationsStarted, 1);
    // Sam's "hello??" came 2 h after an unanswered "you home?".
    expect(stats.them.doubleTexts, 1);
    // Robin's Wednesday message follows Robin's own 2am one, but two days
    // later: a new conversation, not a double text.
    expect(stats.me.doubleTexts, 0);
  });

  test('counts questions, laughs, emoji and late nights', () {
    expect(stats.them.questions, 3);
    expect(stats.me.questions, 1);
    expect(stats.me.laughs, 2);
    expect(stats.me.emoji, 3);
    expect(stats.me.topEmoji.keys.first, '😂');
    expect(stats.them.lateNight, 1);
    expect(stats.me.lateNight, 1);
  });

  test('keeps favourite words, skipping the filler', () {
    expect(stats.me.topWords.keys.first, 'pub');
    expect(stats.me.topWords['pub'], 3);
    expect(stats.me.topWords.containsKey('what'), isFalse);
  });

  test('knows when you talk', () {
    expect(stats.firstAt, DateTime(2026, 3, 2, 9));
    expect(stats.activeDays, 3);
    expect(stats.longestStreakDays, 3);
    expect(stats.busiestDay, DateTime(2026, 3, 2));
    expect(stats.busiestDayMessages, 6);
    expect(stats.byHour[9], 4);
    expect(stats.byWeekday[0], 6, reason: 'Monday');
    expect(stats.byWeekday.reduce((a, b) => a + b), 10);
  });

  test('survives a JSON round trip', () {
    final back = ChatStats.fromJson(stats.toJson());
    expect(back.totalMessages, stats.totalMessages);
    expect(back.me.medianReplySeconds, stats.me.medianReplySeconds);
    expect(back.them.topWords, stats.them.topWords);
    expect(back.byHour, stats.byHour);
    expect(back.busiestDay, stats.busiestDay);
    expect(ChatStats.fromJson(null).isEmpty, isTrue);
  });
}
