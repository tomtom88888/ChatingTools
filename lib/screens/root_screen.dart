import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../widgets/failure_text.dart';
import 'home_screen.dart';
import 'setup_screen.dart';

/// Sends you to setup until a key is saved, then to the home screen.
class RootScreen extends ConsumerWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = ref.watch(apiKeyProvider);
    return key.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: FailureCard(
              error: error,
              onRetry: () => ref.invalidate(apiKeyProvider),
            ),
          ),
        ),
      ),
      data: (value) => value == null || value.isEmpty
          ? const SetupScreen()
          : const HomeScreen(),
    );
  }
}
