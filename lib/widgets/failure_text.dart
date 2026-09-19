import 'package:flutter/material.dart';

import '../services/chat_export_reader.dart';
import '../services/openai_exception.dart';
import '../services/style_memory_service.dart';
import '../theme/tokens.dart';
import 'paper_ui.dart';

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

/// A failure stated in the design's own surface, with an optional retry.
class FailureNotice extends StatelessWidget {
  const FailureNotice({required this.error, this.onRetry, this.title, super.key});

  final Object error;
  final VoidCallback? onRetry;
  final String? title;

  @override
  Widget build(BuildContext context) => Notice(
    describeFailure(error),
    tone: NoticeTone.failure,
    title: title,
    actionLabel: onRetry == null ? null : 'Try again',
    onAction: onRetry,
  );
}

/// Shows [error] as a snack bar, for failures that don't replace the page.
void showFailureSnackBar(BuildContext context, Object error) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        describeFailure(error),
        style: Type.prose(size: 13.5, color: Paper.onInk, height: 1.45),
      ),
      backgroundColor: Paper.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: Corner.all(Corner.small)),
      duration: const Duration(seconds: 6),
    ),
  );
}

/// A brief confirmation, in the design's dark toast.
void showToast(BuildContext context, String message, {String? detail}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: Type.strong(size: 14, color: Paper.onInk)),
          if (detail != null) ...[
            const SizedBox(height: 3),
            Text(
              detail,
              style: Type.prose(
                size: 12.5,
                color: const Color(0x99FAF7F0),
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
      backgroundColor: Paper.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: Corner.all(Corner.small)),
      duration: const Duration(seconds: 3),
    ),
  );
}
