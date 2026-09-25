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
    final key = ref.watch(apiKeyProvider);
    return key.when(
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
            title: "Couldn't read the saved key",
            onRetry: () => ref.invalidate(apiKeyProvider),
          ),
        ],
      ),
      data: (value) => value == null || value.isEmpty
          ? const SetupScreen()
          : const HomeScreen(),
    );
  }
}
