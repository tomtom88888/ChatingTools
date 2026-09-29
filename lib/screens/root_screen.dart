import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/failure_text.dart';
import '../widgets/paper_ui.dart';
import 'home_screen.dart';
import 'setup_screen.dart';

/// Setup until a key is saved, then Home.
class RootScreen extends ConsumerWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = ref.watch(apiKeysProvider);
    return keys.when(
      loading: () => Scaffold(
        backgroundColor: Paper.bg,
        body: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (error, _) => PaperScreen(
        children: [
          const DittoLogo(),
          FailureNotice(
            error: error,
            title: "Couldn't read the saved keys",
            onRetry: () => ref.invalidate(apiKeysProvider),
          ),
        ],
      ),
      data: (value) => value.isEmpty ? const SetupScreen() : const HomeScreen(),
    );
  }
}
