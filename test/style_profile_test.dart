import 'package:flutter_test/flutter_test.dart';
import 'package:replylikeme/models/chat_turn.dart';
import 'package:replylikeme/models/style_profile.dart';

ChatTurn turn(String sender, String text, {int bubbles = 1}) =>
    ChatTurn(sender: sender, text: text, messageCount: bubbles);

void main() {
  group('measure', () {
    final profile = StyleProfile.measure([
      turn('Robin', 'haha yes'),
      turn('Sam', 'This Is Not Mine.'),
      turn('Robin', 'omw'),
      turn('Robin', 'Sounds good.'),
      turn('Robin', 'haha\nsee you there 😂', bubbles: 2),
      turn('Robin', 'omw'),
      turn('Robin', 'are you coming?'),
    ], me: 'Robin');

    test('counts only my replies', () {
      expect(profile.turns, 6);
      expect(profile.bubbles, 7);
      expect(profile.multiBubbleTurns, 1);
      expect(profile.multiBubbleShare, closeTo(1 / 6, 1e-9));
    });

    test('works out length percentiles from word counts', () {
      // Word counts (an emoji is a word): 2, 1, 2, 5, 1, 3 -> 1 1 2 2 3 5.
      expect(profile.medianWords, 2);
      expect(profile.longWords, 5);
      expect(profile.meanWords, closeTo(14 / 6, 1e-9));
    });

    test('records casing, full stops, questions and emoji', () {
      expect(profile.lowercaseStarts, 5);
      expect(profile.fullStopEnds, 1);
      expect(profile.questions, 1);
      expect(profile.turnsWithEmoji, 1);
      expect(profile.emoji, {'😂': 1});
    });

    test('counts short bubbles as phrases, repeats first', () {
      expect(profile.phrases['omw'], 2);
      // "haha" as its own bubble once; "haha yes" is a different bubble.
      expect(profile.phrases['haha'], 1);
      expect(profile.topPhrases.first.key, 'omw');
    });

    test('scripts without case never count as lowercase', () {
      final hebrew = StyleProfile.measureTexts(['מה קורה', 'בסדר']);
      expect(hebrew.turns, 2);
      expect(hebrew.lowercaseStarts, 0);
    });
  });

  group('merge', () {
    test('is the same as measuring everything at once', () {
      final a = ['ok', 'sure thing.', 'haha 😂'];
      final b = ['Right, see you at 8', 'ok', 'lol'];
      final merged = StyleProfile.measureTexts(
        a,
      ).merge(StyleProfile.measureTexts(b));
      final together = StyleProfile.measureTexts([...a, ...b]);

      expect(merged.turns, together.turns);
      expect(merged.words, together.words);
      expect(merged.medianWords, together.medianWords);
      expect(merged.longWords, together.longWords);
      expect(merged.lowercaseStarts, together.lowercaseStarts);
      expect(merged.fullStopEnds, together.fullStopEnds);
      expect(merged.emoji, together.emoji);
      // Phrases need two sightings; "ok" gets them only across both halves.
      expect(merged.phrases['ok'], 2);
    });

    test('with an empty profile changes nothing', () {
      final p = StyleProfile.measureTexts(['yo', 'hey']);
      expect(p.merge(StyleProfile.empty).turns, 2);
      expect(StyleProfile.empty.merge(p).turns, 2);
      expect(StyleProfile.mergeAll([]).isEmpty, isTrue);
    });
  });

  group('describe', () {
    test('turns the numbers into prompt lines', () {
      final p = StyleProfile.measureTexts([
        for (var i = 0; i < 10; i++) 'omw 😂',
      ]);
      final text = p.describe('Robin');
      expect(text, contains("Measured from 10 of Robin's real replies"));
      expect(text, contains('half are 2 words or fewer'));
      expect(text, contains('starts with a lowercase letter: 100%'));
      expect(text, contains('most used emoji: 😂'));
      expect(text, contains('"omw 😂"'));
    });

    test('says nothing from too few replies to trust', () {
      expect(StyleProfile.measureTexts(['hi', 'yo']).describe('Robin'), '');
    });
  });

  test('survives a JSON round trip', () {
    final p = StyleProfile.measureTexts(['ok', 'ok', 'Great.', 'lol 😂\nyes']);
    final back = StyleProfile.fromJson(p.toJson());
    expect(back.turns, p.turns);
    expect(back.lengthBuckets, p.lengthBuckets);
    expect(back.emoji, p.emoji);
    expect(back.phrases, p.phrases);
    expect(back.multiBubbleTurns, p.multiBubbleTurns);
    expect(StyleProfile.fromJson('nonsense').isEmpty, isTrue);
  });
}
