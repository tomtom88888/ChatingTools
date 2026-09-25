import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/root_screen.dart';
import 'theme/tokens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Paper.use(WidgetsBinding.instance.platformDispatcher.platformBrightness);
  runApp(const ProviderScope(child: DittoApp()));
}

/// The app, in light or dark to match the phone.
class DittoApp extends StatefulWidget {
  const DittoApp({super.key});

  @override
  State<DittoApp> createState() => _DittoAppState();
}

class _DittoAppState extends State<DittoApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The colours are read from [Paper] rather than from an inherited theme,
  /// so a switch between light and dark has to rebuild every widget — const
  /// ones included — for them to pick up the new palette. Screens keep their
  /// state; only their build methods run again.
  @override
  void didChangePlatformBrightness() {
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (Paper.isDark == (brightness == Brightness.dark)) return;
    Paper.use(brightness);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void rebuild(Element element) {
        element.markNeedsBuild();
        element.visitChildren(rebuild);
      }

      if (mounted) (context as Element).visitChildren(rebuild);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ditto',
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      home: const RootScreen(),
    );
  }

  /// Built from the palette in force, so Material's own pieces — dialogs,
  /// menus, sheets, snack bars, text selection — match the app's colours.
  ThemeData _theme() {
    final dark = Paper.isDark;
    final scheme = ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: Paper.accent,
      onPrimary: dark ? Paper.onInk : Colors.white,
      secondary: Paper.ink,
      onSecondary: Paper.onInk,
      surface: Paper.bg,
      onSurface: Paper.ink,
      surfaceContainerHighest: Paper.panel,
      error: Paper.errorText,
      onError: dark ? Paper.onInk : Colors.white,
    );
    return ThemeData(
      colorScheme: scheme,
      brightness: scheme.brightness,
      scaffoldBackgroundColor: Paper.bg,
      canvasColor: Paper.bg,
      fontFamily: Fonts.sans,
      splashFactory: InkSparkle.splashFactory,
      dialogTheme: DialogThemeData(backgroundColor: Paper.card),
      popupMenuTheme: PopupMenuThemeData(color: Paper.card),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: Paper.card),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: Paper.accent,
        selectionColor: Paper.accent.withValues(alpha: 0.25),
        selectionHandleColor: Paper.accent,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: Paper.accent,
        linearTrackColor: Paper.border,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Paper.accent
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(dark ? Paper.onInk : Colors.white),
      ),
    );
  }
}
