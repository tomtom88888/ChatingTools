import 'package:flutter_test/flutter_test.dart';
import 'package:replylikeme/models/chat_stats.dart';
import 'package:replylikeme/screens/chat_data_screen.dart';

void main() {
  test('says what stands out, in plain sentences', () {
    final lines = Highlights.of(
      ChatStats(
        me: const PersonStats(
          messages: 100,
          words: 500,
          medianReplySeconds: 240,
          conversationsStarted: 20,
          laughs: 60,
        ),
        them: const PersonStats(
          messages: 100,
          words: 800,
          medianReplySeconds: 1260,
          conversationsStarted: 40,
          laughs: 20,
        ),
        busiestDay: DateTime(2025, 2, 14),
        busiestDayMessages: 312,
        longestStreakDays: 3,
      ),
      them: 'Sam',
    );
    final plain = lines.map((l) => l.replaceAll('*', '')).toList();
    expect(plain, [
      'You usually reply in 4 min; \u2068Sam\u2069 takes 21 min.',
      '\u2068Sam\u2069 starts 67% of your conversations.',
      '\u2068Sam\u2069 writes longer: 8.0 words a message to your 5.0.',
      'You laugh 3.0× as often.',
      'Your busiest day was 14 Feb 2025: 312 messages.',
    ]);
  });

  test('a balanced chat gets fewer lines, not dull ones', () {
    const even = PersonStats(
      messages: 100,
      words: 500,
      conversationsStarted: 10,
      laughs: 30,
    );
    final lines = Highlights.of(
      const ChatStats(me: even, them: even, longestStreakDays: 2),
      them: 'Sam',
    );
    expect(lines, isEmpty);
  });
}
