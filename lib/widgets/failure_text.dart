import 'package:flutter/material.dart';

import '../services/chat_export_reader.dart';
import '../services/openai_exception.dart';
import '../services/style_memory_service.dart';

/// Turns any thrown object into a sentence worth showing a person.
///
/// The app's own exceptions already carry user-facing wording; anything else
/// gets a plain fallback rather than a Dart stack trace.
String describeFailure(Object error) {
  if (error is OpenAiException) return error.message;
  if (error is ChatExportException) return error.message;
  if (error is StyleMemoryCancelled) return 'Training cancelled.';
  if (error is ArgumentError) {
    final message = error.message;
    if (message is String && message.isNotEmpty) return message;
  }
  return 'Something went wrong: $error';
}

/// A red card explaining what failed, with an optional retry.
class FailureCard extends StatelessWidget {
  const FailureCard({required this.error, this.onRetry, super.key});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: scheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    describeFailure(error),
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows [error] as a snack bar. Used for failures that don't replace the page.
void showFailureSnackBar(BuildContext context, Object error) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(describeFailure(error)),
      backgroundColor: Theme.of(context).colorScheme.error,
      duration: const Duration(seconds: 6),
    ),
  );
}
