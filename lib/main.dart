import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/root_screen.dart';
import 'theme/tokens.dart';

void main() {
  runApp(const ProviderScope(child: ReplyLikeMeApp()));
}

class ReplyLikeMeApp extends StatelessWidget {
  const ReplyLikeMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ReplyLikeMe',
      debugShowCheckedModeBanner: false,
      theme: _theme,
      home: const RootScreen(),
    );
  }

  /// The design is a single warm-paper theme — it has no dark variant, so the
  /// app does not follow the system there.
  ThemeData get _theme {
    const scheme = ColorScheme.light(
      primary: Paper.accent,
      onPrimary: Colors.white,
      secondary: Paper.ink,
      onSecondary: Paper.onInk,
      surface: Paper.bg,
      onSurface: Paper.ink,
      error: Paper.errorText,
      onError: Colors.white,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: Paper.bg,
      fontFamily: Fonts.sans,
      splashFactory: InkSparkle.splashFactory,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Paper.accent,
        selectionColor: Color(0x33B4501E),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Paper.accent,
        linearTrackColor: Paper.borderSoft,
      ),
    );
  }
}
