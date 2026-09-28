import 'package:flutter_test/flutter_test.dart';
import 'package:replylikeme/models/extracted_message.dart';
import 'package:replylikeme/services/screenshot_stitcher.dart';

ExtractedMessage them(String text) =>
    ExtractedMessage(speaker: Speaker.them, text: text);
ExtractedMessage me(String text) =>
    ExtractedMessage(speaker: Speaker.me, text: text);

List<String> texts(List<ExtractedMessage> messages) => [
  for (final m in messages) m.text,
];

void main() {
  final top = [them('pub tonight?'), me('maybe'), them('go on')];
  final bottom = [them('go on'), me('fine, 8?'), them('see you there')];

  test('keeps the overlap once', () {
    expect(texts(ScreenshotStitcher.stitch([top, bottom])), [
      'pub tonight?',
      'maybe',
      'go on',
      'fine, 8?',
      'see you there',
    ]);
  });

  test('puts screenshots picked out of order the right way round', () {
    expect(
      texts(ScreenshotStitcher.stitch([bottom, top])),
      texts(ScreenshotStitcher.stitch([top, bottom])),
    );
  });

  test('joins three, however they were picked', () {
    final middle = [me('maybe'), them('go on'), me('fine, 8?')];
    final first = [them('hey'), them('pub tonight?'), me('maybe')];
    final last = [me('fine, 8?'), them('see you there')];
    expect(texts(ScreenshotStitcher.stitch([last, first, middle])), [
      'hey',
      'pub tonight?',
      'maybe',
      'go on',
      'fine, 8?',
      'see you there',
    ]);
  });

  test('matches a bubble cut off at the edge, and ignores punctuation', () {
    final a = [
      them('are you coming to the thing on friday or not'),
      me('Yes!'),
    ];
    final b = [them('the thing on friday or not'), me('yes'), them('great')];
    expect(texts(ScreenshotStitcher.stitch([a, b])), [
      'are you coming to the thing on friday or not',
      'Yes!',
      'great',
    ]);
  });

  test('a matching text from the other side is not an overlap', () {
    final a = [them('lol'), me('ok')];
    final b = [them('ok'), me('bye')];
    expect(ScreenshotStitcher.overlap(a, b), 0);
    expect(texts(ScreenshotStitcher.stitch([a, b])), [
      'lol',
      'ok',
      'ok',
      'bye',
    ]);
  });

  test('screenshots that do not overlap are kept in the order picked', () {
    final a = [them('one'), me('two')];
    final b = [them('three'), me('four')];
    expect(texts(ScreenshotStitcher.stitch([a, b])), [
      'one',
      'two',
      'three',
      'four',
    ]);
    expect(ScreenshotStitcher.stitch([[], a, []]), hasLength(2));
    expect(ScreenshotStitcher.stitch([]), isEmpty);
  });

  test('emoji-only bubbles still line up', () {
    final a = [them('good game'), me('🔥🔥')];
    final b = [me('🔥🔥'), them('rematch?')];
    expect(texts(ScreenshotStitcher.stitch([a, b])), [
      'good game',
      '🔥🔥',
      'rematch?',
    ]);
  });
}
