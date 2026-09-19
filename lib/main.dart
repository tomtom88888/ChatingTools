import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/root_screen.dart';

void main() {
  runApp(const ProviderScope(child: ReplyLikeMeApp()));
}

class ReplyLikeMeApp extends StatelessWidget {
  const ReplyLikeMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF128C7E));
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF128C7E),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'ReplyLikeMe',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _theme(scheme),
      darkTheme: _theme(darkScheme),
      home: const RootScreen(),
    );
  }

  // Only colorScheme is set on purpose: the per-component theme classes
  // (AppBarTheme, CardTheme, InputDecorationTheme) have been renamed across
  // recent Flutter releases, and nothing here needs them.
  ThemeData _theme(ColorScheme scheme) => ThemeData(colorScheme: scheme);
}
