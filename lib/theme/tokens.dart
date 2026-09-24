import 'package:flutter/material.dart';

/// One complete set of colours. The app has two, [light] and [dark], and
/// follows the phone.
///
/// The look is a messaging app's: a teal accent, green "sent" bubbles for
/// your side of a conversation, white "received" ones for theirs, and soft
/// surfaces between them — because everything the app makes is a message.
class Palette {
  const Palette({
    required this.bg,
    required this.panel,
    required this.card,
    required this.ink,
    required this.onInk,
    required this.body,
    required this.secondary,
    required this.tertiary,
    required this.muted,
    required this.placeholder,
    required this.accent,
    required this.accentSoft,
    required this.heroStart,
    required this.heroEnd,
    required this.highlight,
    required this.bubbleMine,
    required this.bubbleTheirs,
    required this.chatBg,
    required this.green,
    required this.greenText,
    required this.greenPanel,
    required this.errorPanel,
    required this.errorText,
    required this.warnPanel,
    required this.warnText,
    required this.border,
    required this.divider,
    required this.shadow,
  });

  final Color bg;
  final Color panel;
  final Color card;
  final Color ink;
  final Color onInk;
  final Color body;
  final Color secondary;
  final Color tertiary;
  final Color muted;
  final Color placeholder;
  final Color accent;
  final Color accentSoft;
  final Color heroStart;
  final Color heroEnd;
  final Color highlight;
  final Color bubbleMine;
  final Color bubbleTheirs;
  final Color chatBg;
  final Color green;
  final Color greenText;
  final Color greenPanel;
  final Color errorPanel;
  final Color errorText;
  final Color warnPanel;
  final Color warnText;
  final Color border;
  final Color divider;
  final Color shadow;

  static const Palette light = Palette(
    bg: Color(0xFFF4F7F6),
    panel: Color(0xFFE9EFEC),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF111B21),
    onInk: Color(0xFFFFFFFF),
    body: Color(0xFF2A3942),
    secondary: Color(0xFF54656F),
    tertiary: Color(0xFF667781),
    muted: Color(0xFF7D8D96),
    placeholder: Color(0xFFA5B2B9),
    accent: Color(0xFF008069),
    accentSoft: Color(0xFFD8F1EA),
    heroStart: Color(0xFF00A884),
    heroEnd: Color(0xFF00705C),
    highlight: Color(0xFFC9FBEA),
    bubbleMine: Color(0xFFD9FDD3),
    bubbleTheirs: Color(0xFFFFFFFF),
    chatBg: Color(0xFFEFEAE2),
    green: Color(0xFF1DA851),
    greenText: Color(0xFF0E6B3B),
    greenPanel: Color(0xFFE2F6E9),
    errorPanel: Color(0xFFFDECEC),
    errorText: Color(0xFFB42318),
    warnPanel: Color(0xFFFFF4DF),
    warnText: Color(0xFF8A5300),
    border: Color(0x24111B21),
    divider: Color(0x14111B21),
    shadow: Color(0x14111B21),
  );

  static const Palette dark = Palette(
    bg: Color(0xFF0B141A),
    panel: Color(0xFF16232B),
    card: Color(0xFF1F2C34),
    ink: Color(0xFFE9EDEF),
    onInk: Color(0xFF0B141A),
    body: Color(0xFFD1D7DB),
    secondary: Color(0xFFAEBAC1),
    tertiary: Color(0xFF93A2AA),
    muted: Color(0xFF8696A0),
    placeholder: Color(0xFF5F717A),
    accent: Color(0xFF00C49A),
    accentSoft: Color(0xFF103B33),
    heroStart: Color(0xFF00806A),
    heroEnd: Color(0xFF004E42),
    highlight: Color(0xFFA6F2D8),
    bubbleMine: Color(0xFF005C4B),
    bubbleTheirs: Color(0xFF1F2C34),
    chatBg: Color(0xFF0E1A20),
    green: Color(0xFF21C063),
    greenText: Color(0xFF86E2AE),
    greenPanel: Color(0xFF0F3324),
    errorPanel: Color(0xFF3B1C1C),
    errorText: Color(0xFFF7A8A8),
    warnPanel: Color(0xFF392C12),
    warnText: Color(0xFFF2CD83),
    border: Color(0x33E9EDEF),
    divider: Color(0x1FE9EDEF),
    shadow: Color(0x00000000),
  );
}

/// The colours in force, by role.
///
/// The name is historical — the first design was warm paper — and kept so
/// every widget reads its colours the same way. The values come from the
/// current [Palette]; [use] switches it when the phone changes between light
/// and dark, and the app then rebuilds everything.
abstract final class Paper {
  static Palette _palette = Palette.light;

  static void use(Brightness brightness) =>
      _palette = brightness == Brightness.dark ? Palette.dark : Palette.light;

  static bool get isDark => identical(_palette, Palette.dark);

  /// Screen background.
  static Color get bg => _palette.bg;

  /// Sunken panel — a step back from the page.
  static Color get panel => _palette.panel;

  /// Raised card.
  static Color get card => _palette.card;

  /// Primary text, and the fill of strong neutral buttons.
  static Color get ink => _palette.ink;

  /// Text on [ink].
  static Color get onInk => _palette.onInk;

  static Color get body => _palette.body;
  static Color get secondary => _palette.secondary;
  static Color get tertiary => _palette.tertiary;
  static Color get muted => _palette.muted;
  static Color get placeholder => _palette.placeholder;

  /// Teal: links, the primary action, and anything that is "the app".
  static Color get accent => _palette.accent;

  /// Text and icons on an [accent] fill.
  static Color get onAccent =>
      isDark ? _palette.onInk : const Color(0xFFFFFFFF);

  /// A tint of [accent] for chips and quiet highlights.
  static Color get accentSoft => _palette.accentSoft;

  /// The hero card's gradient, and what sits on it.
  static Color get heroStart => _palette.heroStart;
  static Color get heroEnd => _palette.heroEnd;
  static const Color onHero = Color(0xFFFFFFFF);
  static const Color onHeroFaint = Color(0xB3FFFFFF);
  static const Color onHeroQuiet = Color(0x33FFFFFF);

  /// Numbers and progress on the hero card.
  static Color get amber => _palette.highlight;

  /// Your messages, and theirs.
  static Color get bubbleMine => _palette.bubbleMine;
  static Color get bubbleTheirs => _palette.bubbleTheirs;

  /// Behind a run of bubbles, like a chat's wallpaper.
  static Color get chatBg => _palette.chatBg;

  /// Success.
  static Color get green => _palette.green;
  static Color get greenText => _palette.greenText;
  static Color get greenPanel => _palette.greenPanel;

  /// Error.
  static Color get errorPanel => _palette.errorPanel;
  static Color get errorText => _palette.errorText;

  /// Caution — a state that is wrong but not broken.
  static Color get warnPanel => _palette.warnPanel;
  static Color get warnText => _palette.warnText;

  /// The hairline under a chat bubble.
  static Color get shadowSoft =>
      isDark ? const Color(0x00000000) : const Color(0x1A0B141A);

  static Color get border => _palette.border;
  static Color get borderSoft => _palette.border;
  static Color get divider => _palette.divider;
  static Color get dividerFirm => _palette.divider;

  /// Card elevation: a soft shadow in light mode, none in dark, where cards
  /// are told apart by their lighter surface instead.
  static List<BoxShadow> get lift => [
    BoxShadow(
      color: _palette.shadow,
      blurRadius: 14,
      offset: const Offset(0, 3),
    ),
  ];
  static List<BoxShadow> get liftCard => lift;

  /// The hero gradient.
  static LinearGradient get heroGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [heroStart, heroEnd],
  );
}

/// Corner radii, named for what they are used on.
abstract final class Corner {
  static const Radius hero = Radius.circular(26);
  static const Radius steps = Radius.circular(22);
  static const Radius card = Radius.circular(22);
  static const Radius action = Radius.circular(20);
  static const Radius choice = Radius.circular(18);
  static const Radius field = Radius.circular(16);
  static const Radius bubble = Radius.circular(18);
  static const Radius small = Radius.circular(14);

  /// The squared-off corner of a chat bubble, on the sender's side.
  static const Radius tail = Radius.circular(5);
  static const Radius pill = Radius.circular(999);

  static BorderRadius all(Radius r) => BorderRadius.all(r);
}

/// The one family the app uses: Nunito, rounded and friendly, in five
/// weights. Hebrew, Arabic and other scripts it lacks fall back to the
/// phone's own font.
abstract final class Fonts {
  static const String sans = 'Nunito';

  /// Kept as aliases so every style reads its family the same way.
  static const String serif = sans;
  static const String mono = sans;
}

/// The type scale. Headlines are heavy rather than large; numbers use
/// tabular figures so columns of them line up.
abstract final class Type {
  static TextStyle display(double size, {Color? color}) => TextStyle(
    fontFamily: Fonts.sans,
    fontWeight: FontWeight.w800,
    fontSize: size * 0.82,
    height: 1.15,
    letterSpacing: -0.015 * size,
    color: color ?? Paper.ink,
  );

  /// The accent clause of a headline: the same weight, in the accent colour.
  static TextStyle displayItalic(double size, {Color? color}) =>
      display(size, color: color ?? Paper.accent);

  /// A section label.
  static TextStyle label({
    double size = 11,
    Color? color,
    double spacing = 0.14,
  }) => TextStyle(
    fontFamily: Fonts.sans,
    fontWeight: FontWeight.w800,
    fontSize: size + 1.5,
    height: 1.3,
    letterSpacing: 0.2,
    color: color ?? Paper.secondary,
  );

  /// Numerals and identifiers.
  static TextStyle numeric({
    double size = 13,
    Color? color,
    FontWeight weight = FontWeight.w500,
  }) => TextStyle(
    fontFamily: Fonts.sans,
    fontWeight: weight == FontWeight.w400 ? FontWeight.w600 : FontWeight.w700,
    fontSize: size,
    height: 1.3,
    fontFeatures: const [FontFeature.tabularFigures()],
    color: color ?? Paper.ink,
  );

  static TextStyle prose({
    double size = 14,
    Color? color,
    double height = 1.5,
    FontWeight weight = FontWeight.w400,
  }) => TextStyle(
    fontFamily: Fonts.sans,
    fontWeight: weight == FontWeight.w400 ? FontWeight.w500 : FontWeight.w600,
    fontSize: size,
    height: height,
    color: color ?? Paper.secondary,
  );

  static TextStyle strong({
    double size = 16,
    Color? color,
    double height = 1.25,
  }) => TextStyle(
    fontFamily: Fonts.sans,
    fontWeight: FontWeight.w700,
    fontSize: size,
    height: height,
    color: color ?? Paper.ink,
  );
}

/// The screen frame the design uses: 62 above, 22 either side, 40 below.
abstract final class Frame {
  static const EdgeInsets screen = EdgeInsets.fromLTRB(22, 62, 22, 40);
  static const EdgeInsets screenWide = EdgeInsets.fromLTRB(24, 66, 24, 40);

  /// Gap between the stacked blocks of a screen.
  static const double gap = 20;
}
