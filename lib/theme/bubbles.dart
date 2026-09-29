import 'package:flutter/painting.dart';

import '../models/chat_app.dart';
import 'tokens.dart';

/// Chat bubble colours in the look of the app a chat came from: WhatsApp's
/// green and white, or Instagram's purple-to-blue and grey.
class Bubbles {
  const Bubbles._(this.app);

  factory Bubbles.of(ChatApp app) => Bubbles._(app);

  final ChatApp app;

  bool get _instagram => app == ChatApp.instagram;

  static const LinearGradient _instagramSent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFA033FF), Color(0xFF5B51F8)],
  );

  /// The fill of your bubbles, when it is a single colour.
  Color get mine => _instagram ? const Color(0xFF7B42FA) : Paper.bubbleMine;

  /// The fill of your bubbles, when it is a gradient.
  Gradient? get mineGradient => _instagram ? _instagramSent : null;

  Color get mineText => _instagram ? const Color(0xFFFFFFFF) : Paper.ink;

  Color get theirs => _instagram
      ? (Paper.isDark ? const Color(0xFF262626) : const Color(0xFFEFEFEF))
      : Paper.bubbleTheirs;

  Color get theirsText => _instagram
      ? (Paper.isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000))
      : Paper.ink;

  /// Secondary text (times, names) on your bubbles.
  Color get mineMuted => _instagram ? const Color(0xCCFFFFFF) : Paper.tertiary;

  /// A bubble's decoration, before its corners and border.
  BoxDecoration fill({required bool mine}) => BoxDecoration(
    color: mine ? (mineGradient == null ? this.mine : null) : theirs,
    gradient: mine ? mineGradient : null,
  );

  Color text({required bool mine}) => mine ? mineText : theirsText;
}
