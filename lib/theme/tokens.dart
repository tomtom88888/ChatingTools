import 'package:flutter/material.dart';

/// The design's palette, taken verbatim from the design document.
///
/// Warm paper rather than grey: the app is about someone's own words, and the
/// surfaces are meant to read as stationery rather than as a dashboard.
abstract final class Paper {
  /// Screen background.
  static const Color bg = Color(0xFFFAF7F0);

  /// Sunken panel — a step back from the page.
  static const Color panel = Color(0xFFF1ECE1);

  /// Raised card.
  static const Color card = Color(0xFFFFFFFF);

  /// Primary text, and the fill of dark cards and buttons.
  static const Color ink = Color(0xFF191713);

  /// Text on [ink].
  static const Color onInk = Color(0xFFFAF7F0);

  /// Body text inside a [panel].
  static const Color body = Color(0xFF3B372F);

  static const Color secondary = Color(0xFF5E584E);
  static const Color tertiary = Color(0xFF7A7266);

  /// Labels, captions, the quietest text that still has to be read.
  static const Color muted = Color(0xFF8A8377);

  /// Placeholder text inside an empty field.
  static const Color placeholder = Color(0xFFA9A296);

  /// The accent: terracotta. Links, step numbers, the primary action.
  static const Color accent = Color(0xFFB4501E);

  /// Amber — numerals and progress on dark surfaces only.
  static const Color amber = Color(0xFFE8A06A);

  /// Green, used for the privacy promise and for success.
  static const Color green = Color(0xFF2F5D45);
  static const Color greenText = Color(0xFF31513F);
  static const Color greenMuted = Color(0xFF5A7565);
  static const Color greenPanel = Color(0xFFE7EFE8);

  /// Error.
  static const Color errorPanel = Color(0xFFF7E9E2);
  static const Color errorText = Color(0xFF8C3B12);

  /// Caution — a state that is wrong but not broken.
  static const Color warnPanel = Color(0xFFFBF0E4);
  static const Color warnText = Color(0xFF6B4426);

  static const Color border = Color(0x24191713); // rgba(25,23,19,.14)
  static const Color borderSoft = Color(0x1F191713); // .12
  static const Color divider = Color(0x12191713); // .07
  static const Color dividerFirm = Color(0x14191713); // .08

  /// Card elevation, expressed as the design's two shadows.
  static const List<BoxShadow> lift = [
    BoxShadow(
      color: Color(0x0F191713),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];
  static const List<BoxShadow> liftCard = [
    BoxShadow(
      color: Color(0x12191713),
      blurRadius: 3,
      offset: Offset(0, 1),
    ),
  ];
}

/// Corner radii, named for what they are used on.
abstract final class Corner {
  static const Radius hero = Radius.circular(22);
  static const Radius steps = Radius.circular(20);
  static const Radius card = Radius.circular(18);
  static const Radius action = Radius.circular(16);
  static const Radius choice = Radius.circular(15);
  static const Radius field = Radius.circular(14);
  static const Radius bubble = Radius.circular(13);
  static const Radius small = Radius.circular(12);
  static const Radius pill = Radius.circular(999);

  static BorderRadius all(Radius r) => BorderRadius.all(r);
}

/// The three families the design uses, and the roles they play.
abstract final class Fonts {
  /// Headlines. Set large, never bold — the weight comes from the size.
  static const String serif = 'Instrument Serif';

  /// Everything a person reads as prose or taps as a control.
  static const String sans = 'Public Sans';

  /// Numerals, model identifiers, filenames, and the small uppercase labels
  /// that title a section.
  static const String mono = 'JetBrains Mono';
}

/// The design's type scale.
///
/// Sizes and line heights are the document's, converted to Flutter's `height`
/// multiplier. Letter spacing on the mono labels is what gives them their
/// engraved look, so it is not optional.
abstract final class Type {
  static TextStyle display(double size, {Color color = Paper.ink}) => TextStyle(
    fontFamily: Fonts.serif,
    fontWeight: FontWeight.w400,
    fontSize: size,
    height: 1.08,
    letterSpacing: -0.01 * size,
    color: color,
  );

  static TextStyle displayItalic(double size, {Color color = Paper.accent}) =>
      display(size, color: color).copyWith(fontStyle: FontStyle.italic);

  /// An uppercase mono label. [spacing] is in ems, as the document writes it.
  static TextStyle label({
    double size = 11,
    Color color = Paper.muted,
    double spacing = 0.14,
  }) => TextStyle(
    fontFamily: Fonts.mono,
    fontWeight: FontWeight.w500,
    fontSize: size,
    height: 1.3,
    letterSpacing: spacing * size,
    color: color,
  );

  /// Numerals and identifiers.
  static TextStyle numeric({
    double size = 13,
    Color color = Paper.ink,
    FontWeight weight = FontWeight.w500,
  }) => TextStyle(
    fontFamily: Fonts.mono,
    fontWeight: weight,
    fontSize: size,
    height: 1.3,
    color: color,
  );

  static TextStyle prose({
    double size = 14,
    Color color = Paper.secondary,
    double height = 1.5,
    FontWeight weight = FontWeight.w400,
  }) => TextStyle(
    fontFamily: Fonts.sans,
    fontWeight: weight,
    fontSize: size,
    height: height,
    color: color,
  );

  static TextStyle strong({
    double size = 16,
    Color color = Paper.ink,
    double height = 1.25,
  }) => TextStyle(
    fontFamily: Fonts.sans,
    fontWeight: FontWeight.w600,
    fontSize: size,
    height: height,
    color: color,
  );
}

/// The screen frame the design uses: 62 above, 22 either side, 40 below.
abstract final class Frame {
  static const EdgeInsets screen = EdgeInsets.fromLTRB(22, 62, 22, 40);
  static const EdgeInsets screenWide = EdgeInsets.fromLTRB(24, 66, 24, 40);

  /// Gap between the stacked blocks of a screen.
  static const double gap = 20;
}
