import 'chat_groupings.dart';

/// How big a slice of time each column of the timeline covers.
enum TimelineStep { week, month, quarter }

/// One slice of time: when it starts, and how many replies each group had
/// in it.
class TimelineBucket {
  const TimelineBucket({required this.start, required this.counts});

  final DateTime start;

  /// Per group, in the groups' order.
  final List<int> counts;

  int get total => counts.fold(0, (sum, c) => sum + c);
}

/// How the groups' share of your replies changes over time.
///
/// Replies are counted per month; a chat spanning under three months is
/// counted per week, and one spanning over four years per quarter, so there
/// are always a readable number of columns. Empty slices in between are
/// kept, so gaps show as gaps. Replies without a date are left out.
///
/// Pure Dart, so it is unit-testable.
class TopicTimeline {
  const TopicTimeline._(this.step, this.buckets, this.undated);

  final TimelineStep step;
  final List<TimelineBucket> buckets;

  /// Replies with no date, not counted in any slice.
  final int undated;

  bool get isEmpty => buckets.isEmpty;

  static TopicTimeline of(List<ChatGroup> groups) {
    final dated = <(int, DateTime)>[];
    var undated = 0;
    for (var g = 0; g < groups.length; g++) {
      for (final m in groups[g].members) {
        final at = m.timestamp;
        if (at == null) {
          undated++;
        } else {
          dated.add((g, at));
        }
      }
    }
    if (dated.isEmpty) return TopicTimeline._(TimelineStep.month, [], undated);

    var first = dated.first.$2;
    var last = first;
    for (final (_, at) in dated) {
      if (at.isBefore(first)) first = at;
      if (at.isAfter(last)) last = at;
    }
    final days = last.difference(first).inDays;
    final step = days < 90
        ? TimelineStep.week
        : days > 4 * 365
        ? TimelineStep.quarter
        : TimelineStep.month;

    final starts = <DateTime>[];
    for (
      var at = startOf(first, step);
      !at.isAfter(last);
      at = next(at, step)
    ) {
      starts.add(at);
    }
    final index = {for (var i = 0; i < starts.length; i++) starts[i]: i};
    final counts = List.generate(
      starts.length,
      (_) => List<int>.filled(groups.length, 0),
    );
    for (final (g, at) in dated) {
      counts[index[startOf(at, step)]!][g]++;
    }
    return TopicTimeline._(step, [
      for (var i = 0; i < starts.length; i++)
        TimelineBucket(start: starts[i], counts: counts[i]),
    ], undated);
  }

  /// The start of the slice [at] falls in: a Monday, the 1st of a month, or
  /// the 1st of a quarter.
  static DateTime startOf(DateTime at, TimelineStep step) => switch (step) {
    TimelineStep.week => DateTime(at.year, at.month, at.day - at.weekday + 1),
    TimelineStep.month => DateTime(at.year, at.month),
    TimelineStep.quarter => DateTime(at.year, ((at.month - 1) ~/ 3) * 3 + 1),
  };

  static DateTime next(DateTime start, TimelineStep step) => switch (step) {
    // Calendar arithmetic, not 7 × 24 hours, so a clock change can't skew
    // the start of a week.
    TimelineStep.week => DateTime(start.year, start.month, start.day + 7),
    TimelineStep.month => DateTime(start.year, start.month + 1),
    TimelineStep.quarter => DateTime(start.year, start.month + 3),
  };
}
