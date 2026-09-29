import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'keep_awake.dart';

/// Where a long job has got to.
enum TaskStatus { running, done, failed }

/// A long job that runs whatever screen is open: reading a chat for things
/// to remember, grouping replies, learning a chat. Shown in the tray at the
/// bottom of every screen until it finishes or is stopped.
class BackgroundTask {
  const BackgroundTask({
    required this.id,
    required this.title,
    this.detail = '',
    this.progress,
    this.status = TaskStatus.running,
    this.error,
    this.result,
  });

  /// Identifies the job, so the same one isn't started twice and a screen
  /// can find its own.
  final String id;
  final String title;
  final String detail;

  /// 0 to 1, or null while there's no telling.
  final double? progress;
  final TaskStatus status;
  final Object? error;

  /// What the job made, once it is done, for the screen that started it.
  final Object? result;

  bool get running => status == TaskStatus.running;

  BackgroundTask copyWith({
    String? detail,
    double? progress,
    bool clearProgress = false,
    TaskStatus? status,
    Object? error,
    Object? result,
  }) => BackgroundTask(
    id: id,
    title: title,
    detail: detail ?? this.detail,
    progress: clearProgress ? null : (progress ?? this.progress),
    status: status ?? this.status,
    error: error ?? this.error,
    result: result ?? this.result,
  );
}

/// Thrown inside a job when Stop was pressed; the job just ends.
class TaskCancelled implements Exception {
  const TaskCancelled();
}

/// What a running job uses to report progress and notice Stop.
class TaskHandle {
  TaskHandle._(this._center, this.id);

  final TaskCenter _center;
  final String id;
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  /// Ends the job here if Stop has been pressed. Call it between steps, and
  /// before saving anything.
  void check() {
    if (_cancelled) throw const TaskCancelled();
  }

  void report({String? detail, double? progress}) {
    if (_cancelled) return;
    _center._update(
      id,
      (t) => t.copyWith(
        detail: detail,
        progress: progress,
        clearProgress: progress == null,
      ),
    );
  }
}

/// Every long job in the app, running or just finished.
class TaskCenter extends Notifier<List<BackgroundTask>> {
  final Map<String, TaskHandle> _handles = {};
  final Map<String, Timer> _timers = {};

  /// How long a finished job stays in the tray before it goes by itself.
  static const Duration doneShownFor = Duration(seconds: 5);

  @override
  List<BackgroundTask> build() {
    ref.onDispose(() {
      for (final t in _timers.values) {
        t.cancel();
      }
      for (final h in _handles.values) {
        h._cancelled = true;
      }
    });
    return const [];
  }

  BackgroundTask? byId(String id) {
    for (final t in state) {
      if (t.id == id) return t;
    }
    return null;
  }

  bool isRunning(String id) => byId(id)?.running ?? false;

  /// Starts [work] as the job [id] unless it is already running, and
  /// returns straight away: the job carries on whichever screen is open.
  /// Stop ends it quietly; a failure stays in the tray until dismissed.
  void start({
    required String id,
    required String title,
    String detail = '',
    required Future<Object?> Function(TaskHandle handle) work,
  }) {
    if (isRunning(id)) return;
    final handle = TaskHandle._(this, id);
    _handles[id] = handle;
    state = [
      for (final t in state)
        if (t.id != id) t,
      BackgroundTask(id: id, title: title, detail: detail),
    ];
    // The job keeps going with the screen off or another app in front.
    KeepAwake.instance.describe(title);
    unawaited(KeepAwake.instance.during(() => _run(handle, work)));
  }

  Future<void> _run(
    TaskHandle handle,
    Future<Object?> Function(TaskHandle handle) work,
  ) async {
    try {
      final result = await work(handle);
      if (handle.cancelled) return;
      _update(
        handle.id,
        (t) => t.copyWith(status: TaskStatus.done, progress: 1, result: result),
      );
      _timers[handle.id]?.cancel();
      _timers[handle.id] = Timer(doneShownFor, () {
        _timers.remove(handle.id);
        if (byId(handle.id)?.status == TaskStatus.done) dismiss(handle.id);
      });
    } on TaskCancelled {
      // Already taken off the tray by [cancel].
    } on Object catch (error) {
      if (handle.cancelled) return;
      _update(
        handle.id,
        (t) => t.copyWith(status: TaskStatus.failed, error: error),
      );
    } finally {
      if (identical(_handles[handle.id], handle)) _handles.remove(handle.id);
    }
  }

  /// Stops the job: it ends at its next step, and nothing it was making is
  /// kept. It leaves the tray at once.
  void cancel(String id) {
    _handles[id]?._cancelled = true;
    dismiss(id);
  }

  void dismiss(String id) {
    state = [
      for (final t in state)
        if (t.id != id) t,
    ];
  }

  void _update(String id, BackgroundTask Function(BackgroundTask) change) {
    state = [for (final t in state) t.id == id ? change(t) : t];
  }
}

final taskCenterProvider = NotifierProvider<TaskCenter, List<BackgroundTask>>(
  TaskCenter.new,
);
