import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/tasks.dart';
import '../theme/tokens.dart';
import 'failure_text.dart';

/// The long jobs in progress, pinned under every screen: what each is, how
/// far it has got, and a Stop button. Jobs carry on while you use the rest
/// of the app; one that finished shows a tick for a few seconds, one that
/// failed stays until dismissed.
///
/// The screen above is told the tray takes the bottom inset, so nothing on
/// it is hidden underneath.
class TaskTrayFrame extends ConsumerWidget {
  const TaskTrayFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(taskCenterProvider);
    if (tasks.isEmpty) return child;
    return Column(
      children: [
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: child,
          ),
        ),
        _Tray(tasks: tasks),
      ],
    );
  }
}

class _Tray extends ConsumerWidget {
  const _Tray({required this.tasks});

  final List<BackgroundTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        key: const ValueKey('task-tray'),
        decoration: BoxDecoration(
          color: Paper.card,
          border: Border(top: BorderSide(color: Paper.divider)),
          boxShadow: Paper.liftCard,
        ),
        padding: EdgeInsets.fromLTRB(18, 10, 8, 10 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final task in tasks)
              _TaskRow(
                key: ValueKey('task-${task.id}'),
                task: task,
                onStop: () =>
                    ref.read(taskCenterProvider.notifier).cancel(task.id),
                onDismiss: () =>
                    ref.read(taskCenterProvider.notifier).dismiss(task.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.onStop,
    required this.onDismiss,
    super.key,
  });

  final BackgroundTask task;
  final VoidCallback onStop;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = switch (task.status) {
      TaskStatus.running => (null, Paper.accent),
      TaskStatus.done => (Icons.check_circle_rounded, Paper.green),
      TaskStatus.failed => (Icons.error_outline_rounded, Paper.errorText),
    };
    final detail = switch (task.status) {
      TaskStatus.running => task.detail,
      TaskStatus.done => 'Done',
      TaskStatus.failed => describeFailure(
        task.error ?? 'Something went wrong.',
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: icon == null
                ? Padding(
                    padding: const EdgeInsets.all(3),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colour,
                    ),
                  )
                : Icon(icon, size: 20, color: colour),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.strong(size: 13.5, height: 1.3),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Type.prose(
                      size: 12,
                      color: task.status == TaskStatus.failed
                          ? Paper.errorText
                          : Paper.tertiary,
                      height: 1.3,
                    ),
                  ),
                if (task.running) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: Corner.all(Corner.pill),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      value: task.progress,
                      color: Paper.accent,
                      backgroundColor: Paper.accentSoft,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (task.running)
            TextButton(
              key: ValueKey('task-stop-${task.id}'),
              onPressed: onStop,
              style: TextButton.styleFrom(foregroundColor: Paper.errorText),
              child: Text(
                'Stop',
                style: Type.strong(size: 13, color: Paper.errorText),
              ),
            )
          else
            // No tooltip: the tray sits outside the navigator's overlay,
            // which tooltips need.
            Semantics(
              button: true,
              label: 'Dismiss',
              child: InkResponse(
                key: ValueKey('task-dismiss-${task.id}'),
                onTap: onDismiss,
                radius: 20,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Paper.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
