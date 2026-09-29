import 'package:flutter/material.dart';

import '../state/tasks.dart';
import '../theme/tokens.dart';
import 'paper_ui.dart';

/// A job running in the background, as shown on the screen that started it:
/// how far it has got, that it is safe to leave, and a Stop button.
class BackgroundJobCard extends StatelessWidget {
  const BackgroundJobCard({
    required this.task,
    required this.onStop,
    super.key,
  });

  final BackgroundTask task;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => PaperPanel(
    key: const ValueKey('background-job'),
    padding: const EdgeInsets.fromLTRB(15, 15, 15, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MonoLabel(task.title, spacing: 0.12),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: Corner.all(Corner.pill),
          child: LinearProgressIndicator(
            minHeight: 4,
            value: task.progress,
            color: Paper.accent,
            backgroundColor: Paper.accentSoft,
          ),
        ),
        if (task.detail.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            task.detail,
            style: Type.prose(size: 13, color: Paper.body, height: 1.4),
          ),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Paper.accentSoft,
            borderRadius: Corner.all(Corner.small),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.directions_walk_rounded,
                  size: 17,
                  color: Paper.accent,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'You can leave this screen; it keeps going.',
                  style: Type.prose(size: 13, color: Paper.ink, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const ValueKey('background-job-stop'),
            onPressed: onStop,
            child: Text(
              'Stop',
              style: Type.strong(size: 13.5, color: Paper.errorText),
            ),
          ),
        ),
      ],
    ),
  );
}
