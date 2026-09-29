import 'package:flutter/material.dart';

import '../../services/chat_groupings.dart';
import '../../services/topic_timeline.dart';
import '../../theme/tokens.dart';
import '../../widgets/format.dart';
import '../../widgets/paper_ui.dart';
import 'group_map_card.dart';

/// How the groups' share of your replies moved over time: one stacked
/// column per week, month or quarter, in the map's colours, with the
/// biggest group at the bottom. Tapping a column reads out its mix.
class TopicTimelineCard extends StatefulWidget {
  const TopicTimelineCard({
    required this.groups,
    required this.timeline,
    super.key,
  });

  final List<ChatGroup> groups;
  final TopicTimeline timeline;

  @override
  State<TopicTimelineCard> createState() => _TopicTimelineCardState();
}

class _TopicTimelineCardState extends State<TopicTimelineCard> {
  int? _selected;

  static const double _height = 150;
  static const double _minColumn = 10;

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _label(DateTime start) => switch (widget.timeline.step) {
    TimelineStep.week => '${start.day} ${_months[start.month - 1]}',
    TimelineStep.month => '${_months[start.month - 1]} ${start.year % 100}',
    TimelineStep.quarter =>
      'Q${(start.month - 1) ~/ 3 + 1} ${start.year % 100}',
  };

  String _longLabel(DateTime start) => switch (widget.timeline.step) {
    TimelineStep.week =>
      'Week of ${start.day} ${_months[start.month - 1]} ${start.year}',
    TimelineStep.month => '${_months[start.month - 1]} ${start.year}',
    TimelineStep.quarter => 'Q${(start.month - 1) ~/ 3 + 1} ${start.year}',
  };

  String _readout() {
    final buckets = widget.timeline.buckets;
    final i = _selected;
    if (i == null) {
      final busiest = buckets.reduce((a, b) => b.total > a.total ? b : a);
      return 'Busiest: ${_longLabel(busiest.start)}, '
          '${grouped(busiest.total)} replies. Tap a column for its mix.';
    }
    final bucket = buckets[i];
    if (bucket.total == 0) return '${_longLabel(bucket.start)} · no replies';
    final top = [
      for (var g = 0; g < bucket.counts.length; g++)
        if (bucket.counts[g] > 0) (g, bucket.counts[g]),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final mix = top
        .take(3)
        .map(
          (e) => '${widget.groups[e.$1].name} ${percent(e.$2 / bucket.total)}',
        )
        .join(', ');
    return '${_longLabel(bucket.start)} · ${grouped(bucket.total)} replies · '
        '$mix';
  }

  @override
  Widget build(BuildContext context) {
    final buckets = widget.timeline.buckets;
    final peak = buckets.fold(0, (m, b) => b.total > m ? b.total : m);

    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Over time', style: Type.display(22)),
          const SizedBox(height: 2),
          Text(
            'Your replies per '
            '${switch (widget.timeline.step) {
              TimelineStep.week => "week",
              TimelineStep.month => "month",
              TimelineStep.quarter => "quarter",
            }}, split by group. Taller is busier.',
            style: Type.prose(size: 12.5, color: Paper.tertiary, height: 1.4),
          ),
          const SizedBox(height: 10),
          Text(
            _readout(),
            key: const ValueKey('timeline-readout'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Type.prose(size: 12.5, color: Paper.secondary, height: 1.35),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) {
              final fits = box.maxWidth / buckets.length >= _minColumn;
              final column = fits ? box.maxWidth / buckets.length : _minColumn;
              final width = column * buckets.length;
              // Label every nth column so the labels never collide.
              final every = (46 / column).ceil().clamp(1, 1 << 20);
              final chart = SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: _height,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < buckets.length; i++)
                            SizedBox(
                              width: column,
                              child: GestureDetector(
                                key: ValueKey('timeline-$i'),
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(
                                  () => _selected = _selected == i ? null : i,
                                ),
                                child: _Column(
                                  bucket: buckets[i],
                                  peak: peak,
                                  height: _height,
                                  dimmed: _selected != null && _selected != i,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(height: 1, color: Paper.dividerFirm),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 14,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (var i = 0; i < buckets.length; i += every)
                            Positioned(
                              left: i * column,
                              child: Text(
                                _label(buckets[i].start),
                                softWrap: false,
                                style: Type.numeric(
                                  size: 10,
                                  color: Paper.muted,
                                  weight: FontWeight.w400,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              return fits
                  ? chart
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      // Newest on the right, and that is where it opens.
                      reverse: true,
                      child: chart,
                    );
            },
          ),
          if (widget.timeline.undated > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${grouped(widget.timeline.undated)} replies had no date and '
              'are left out.',
              style: Type.prose(size: 12, color: Paper.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// One stacked column: the groups bottom to top, biggest first, with a
/// hairline gap between them and a rounded top.
class _Column extends StatelessWidget {
  const _Column({
    required this.bucket,
    required this.peak,
    required this.height,
    required this.dimmed,
  });

  final TimelineBucket bucket;
  final int peak;
  final double height;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    if (bucket.total == 0 || peak == 0) return const SizedBox.shrink();
    final full = height * bucket.total / peak;
    final parts = [
      for (var g = 0; g < bucket.counts.length; g++)
        if (bucket.counts[g] > 0) (g, bucket.counts[g]),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Opacity(
        opacity: dimmed ? 0.35 : 1,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          child: SizedBox(
            height: full.clamp(2.0, height),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Drawn top to bottom, so the biggest group (first) ends up
                // on the baseline.
                for (final (g, count) in parts.reversed)
                  Expanded(
                    flex: count,
                    child: Container(
                      margin: EdgeInsets.only(
                        bottom: g == parts.first.$1 ? 0 : 1,
                      ),
                      color: GroupMapCard.colourOf(g),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
