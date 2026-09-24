import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_stats.dart';
import '../models/stored_exchange.dart';
import '../models/suggestion_feedback.dart';
import '../services/reply_generator.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/failure_text.dart';
import '../widgets/format.dart';
import '../widgets/paper_ui.dart';

/// The numbers behind each learned chat: who says how much, how fast each of
/// you answers, and when you talk. Counted on the phone from the export; no
/// API calls.
class ChatDataScreen extends ConsumerStatefulWidget {
  const ChatDataScreen({super.key});

  @override
  ConsumerState<ChatDataScreen> createState() => _ChatDataScreenState();
}

class _ChatDataScreenState extends ConsumerState<ChatDataScreen> {
  int? _selectedId;

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatsProvider);
    final feedback = ref.watch(feedbackProvider);

    return PaperScreen(
      gap: 16,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Text(
              '←',
              style: TextStyle(fontSize: 19, color: Paper.secondary),
            ),
          ),
        ),
        const SerifTitle('Chat data', size: 34),
        ...chats.when(
          loading: () => [const LinearProgressIndicator(minHeight: 3)],
          error: (error, _) => [FailureNotice(error: error)],
          data: (all) {
            if (all.isEmpty) {
              return [
                const Notice(
                  'Import a chat export and its numbers appear here.',
                  tone: NoticeTone.caution,
                  title: 'No chats yet',
                ),
              ];
            }
            final chat = all.firstWhere(
              (c) => c.id == _selectedId,
              orElse: () => all.first,
            );
            return [
              if (all.length > 1)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in all)
                      ChoiceChip(
                        label: Text(_name(c)),
                        selected: c.id == chat.id,
                        onSelected: (_) => setState(() => _selectedId = c.id),
                        showCheckmark: false,
                        backgroundColor: Paper.card,
                        selectedColor: Paper.ink,
                        side: const BorderSide(color: Paper.border),
                        labelStyle: Type.strong(
                          size: 13,
                          color: c.id == chat.id ? Paper.onInk : Paper.ink,
                        ),
                      ),
                  ],
                ),
              if (chat.stats.isEmpty)
                const Notice(
                  'This chat was imported before its numbers were counted. '
                  'Import the same export again: nothing new is sent to '
                  'OpenAI, so it costs nothing.',
                  tone: NoticeTone.caution,
                  title: 'No numbers yet',
                )
              else
                ..._sections(chat),
            ];
          },
        ),
        const MonoLabel('How the suggestions have done'),
        feedback.when(
          loading: () => const LinearProgressIndicator(minHeight: 3),
          error: (error, _) => FailureNotice(error: error),
          data: (entries) =>
              _FeedbackCard(summary: FeedbackSummary.of(entries)),
        ),
        const Footnote('Counted on your phone. No API calls.'),
      ],
    );
  }

  static String _name(ChatMemory chat) =>
      chat.theirName.isEmpty ? 'Unnamed chat' : chat.theirName;

  List<Widget> _sections(ChatMemory chat) {
    final stats = chat.stats;
    final them = _name(chat);
    return [
      _Hero(stats: stats, them: them),
      const MonoLabel('You and them'),
      _Comparison(stats: stats, them: them),
      const MonoLabel('When you talk'),
      _WhenYouTalk(stats: stats),
      if (stats.me.topWords.isNotEmpty ||
          stats.them.topWords.isNotEmpty ||
          stats.me.topEmoji.isNotEmpty ||
          stats.them.topEmoji.isNotEmpty) ...[
        const MonoLabel('Favourites'),
        _Favourites(stats: stats, them: them),
      ],
    ];
  }
}

/// The headline: how much has been said, over how long.
class _Hero extends StatelessWidget {
  const _Hero({required this.stats, required this.them});

  final ChatStats stats;
  final String them;

  @override
  Widget build(BuildContext context) {
    final first = stats.firstAt;
    final last = stats.lastAt;
    final span = first != null && last != null
        ? last.difference(first).inDays + 1
        : null;
    const faint = Color(0x9EFAF7F0);
    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You and ${bidiIsolate(them)} have sent',
            style: Type.prose(size: 15, color: faint, height: 1.3),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                grouped(stats.totalMessages),
                style: Type.numeric(size: 40, color: Paper.amber),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'messages',
                  style: Type.prose(size: 15, color: faint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            [
              '${grouped(stats.totalWords)} words',
              if (span != null)
                'over ${grouped(span)} ${span == 1 ? "day" : "days"}',
              if (first != null && last != null)
                '${dayMonthYear(first)} – ${dayMonthYear(last)}',
            ].join(' · '),
            style: Type.prose(size: 13, color: faint, height: 1.45),
          ),
          const SizedBox(height: 14),
          _ShareBar(share: stats.myShare, them: them),
        ],
      ),
    );
  }
}

/// Who sends more, as one split bar with both ends labelled.
class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.share, required this.them});

  final double share;
  final String them;

  @override
  Widget build(BuildContext context) {
    const faint = Color(0x9EFAF7F0);
    final mine = (share * 1000).round().clamp(1, 999);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: Corner.all(Corner.pill),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                Expanded(
                  flex: mine,
                  child: const ColoredBox(color: Paper.amber),
                ),
                // The 2px gap between the two fills.
                const SizedBox(width: 2),
                Expanded(
                  flex: 1000 - mine,
                  child: const ColoredBox(color: Color(0x40FAF7F0)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                'You ${percent(share)}',
                style: Type.numeric(size: 12, color: Paper.onInk),
              ),
            ),
            Text(
              '${percent(1 - share)} ${bidiIsolate(them)}',
              style: Type.numeric(size: 12, color: faint),
            ),
          ],
        ),
      ],
    );
  }
}

/// Side-by-side figures for each of you.
class _Comparison extends StatelessWidget {
  const _Comparison({required this.stats, required this.them});

  final ChatStats stats;
  final String them;

  @override
  Widget build(BuildContext context) {
    final me = stats.me;
    final other = stats.them;
    final rows = <(String, String, String)>[
      ('Messages', grouped(me.messages), grouped(other.messages)),
      ('Words', grouped(me.words), grouped(other.words)),
      (
        'Words per message',
        me.wordsPerMessage.toStringAsFixed(1),
        other.wordsPerMessage.toStringAsFixed(1),
      ),
      (
        'Longest message',
        '${grouped(me.longestMessageWords)} words',
        '${grouped(other.longestMessageWords)} words',
      ),
      (
        'Typical reply time',
        replyTime(me.medianReplySeconds),
        replyTime(other.medianReplySeconds),
      ),
      (
        'Replies within 5 min',
        percent(me.quickReplyShare),
        percent(other.quickReplyShare),
      ),
      (
        'Conversations started',
        grouped(me.conversationsStarted),
        grouped(other.conversationsStarted),
      ),
      ('Double texts', grouped(me.doubleTexts), grouped(other.doubleTexts)),
      ('Questions asked', grouped(me.questions), grouped(other.questions)),
      ('Laughs', grouped(me.laughs), grouped(other.laughs)),
      ('Emoji', grouped(me.emoji), grouped(other.emoji)),
      ('Photos & media', grouped(me.media), grouped(other.media)),
      ('After midnight', grouped(me.lateNight), grouped(other.lateNight)),
      ('Deleted', grouped(me.deleted), grouped(other.deleted)),
    ];

    Widget cell(String text, {bool head = false, bool alignEnd = true}) => Text(
      text,
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: head
          ? Type.strong(size: 12.5, color: Paper.tertiary, height: 1.3)
          : Type.numeric(size: 13, weight: FontWeight.w500),
    );

    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(flex: 5, child: SizedBox()),
              Expanded(flex: 3, child: cell('You', head: true)),
              Expanded(flex: 3, child: cell(bidiIsolate(them), head: true)),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : const Border(bottom: BorderSide(color: Paper.divider)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      rows[i].$1,
                      style: Type.prose(
                        size: 13,
                        color: Paper.secondary,
                        height: 1.3,
                      ),
                    ),
                  ),
                  Expanded(flex: 3, child: cell(rows[i].$2)),
                  Expanded(flex: 3, child: cell(rows[i].$3)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Messages by hour and by weekday, and the day records.
class _WhenYouTalk extends StatelessWidget {
  const _WhenYouTalk({required this.stats});

  final ChatStats stats;

  static const List<String> _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static String _hour(int h) => '${h.toString().padLeft(2, '0')}:00';

  @override
  Widget build(BuildContext context) {
    final busiest = stats.busiestDay;
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stats.byHour.length == 24)
            BarStrip(
              key: const ValueKey('by-hour'),
              title: 'By hour of the day',
              values: stats.byHour,
              describe: (i) => '${_hour(i)}–${_hour((i + 1) % 24)}',
              axisLabel: (i) => i % 6 == 0 ? i.toString().padLeft(2, '0') : '',
            ),
          const SizedBox(height: 18),
          if (stats.byWeekday.length == 7)
            BarStrip(
              key: const ValueKey('by-weekday'),
              title: 'By day of the week',
              values: stats.byWeekday,
              describe: (i) => _days[i],
              axisLabel: (i) => _days[i].substring(0, 1),
            ),
          const SizedBox(height: 12),
          if (busiest != null)
            FigureRow(
              'Busiest day',
              '${dayMonthYear(busiest)} · ${grouped(stats.busiestDayMessages)}',
            ),
          FigureRow(
            'Longest streak',
            '${grouped(stats.longestStreakDays)} days in a row',
          ),
          FigureRow('Days you talked', grouped(stats.activeDays)),
        ],
      ),
    );
  }
}

/// A single-series bar chart of counts: one hue, the peak labelled, and a tap
/// on any bar reads out its exact value.
class BarStrip extends StatefulWidget {
  const BarStrip({
    required this.title,
    required this.values,
    required this.describe,
    required this.axisLabel,
    super.key,
  });

  final String title;
  final List<int> values;

  /// The name of bar i, for the read-out.
  final String Function(int i) describe;

  /// The label under bar i; empty for none.
  final String Function(int i) axisLabel;

  @override
  State<BarStrip> createState() => _BarStripState();
}

class _BarStripState extends State<BarStrip> {
  int? _selected;

  static const double _height = 72;

  @override
  Widget build(BuildContext context) {
    final values = widget.values;
    final peak = values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b);
    final peakIndex = values.indexOf(peak);
    final shown = _selected ?? peakIndex;
    final readout = peak == 0
        ? 'No timestamps to count'
        : '${widget.describe(shown)} · ${grouped(values[shown])} messages'
              '${_selected == null ? " — the busiest" : ""}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Type.strong(size: 13, height: 1.35)),
        const SizedBox(height: 2),
        Text(
          readout,
          style: Type.numeric(
            size: 12,
            color: Paper.secondary,
            weight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: GestureDetector(
                    // The whole column is the hit target, not just the bar.
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        setState(() => _selected = _selected == i ? null : i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: peak == 0
                              ? 0
                              : (values[i] / peak * _height).clamp(
                                  values[i] > 0 ? 2.0 : 0.0,
                                  _height,
                                ),
                          decoration: BoxDecoration(
                            color: i == shown
                                ? Paper.accent
                                : Paper.accent.withValues(alpha: 0.45),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(height: 1, color: Paper.dividerFirm),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < values.length; i++)
              Expanded(
                child: Text(
                  widget.axisLabel(i),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
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
      ],
    );
  }
}

/// Top emoji and words, each side.
class _Favourites extends StatelessWidget {
  const _Favourites({required this.stats, required this.them});

  final ChatStats stats;
  final String them;

  @override
  Widget build(BuildContext context) {
    Widget side(String who, PersonStats person) {
      final emoji = person.topEmoji.keys.take(6).join(' ');
      final words = person.topWords.entries
          .take(6)
          .map((e) => '${e.key} ×${e.value}')
          .join('   ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(who, style: Type.strong(size: 13, height: 1.35)),
          if (emoji.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(emoji, style: const TextStyle(fontSize: 20, height: 1.4)),
          ],
          if (words.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              words,
              style: Type.prose(size: 13, color: Paper.body, height: 1.5),
            ),
          ],
        ],
      );
    }

    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          side('You', stats.me),
          const SizedBox(height: 14),
          side(them, stats.them),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.summary});

  final FeedbackSummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.isEmpty) {
      return PaperPanel(
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
        child: Text(
          'Nothing yet. Every time you copy a suggestion — or walk away from '
          'all of them — it is noted here, on the phone only.',
          style: Type.prose(size: 13.5, color: Paper.body, height: 1.45),
        ),
      );
    }
    final positions = summary.pickedByPosition.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final tweaks = summary.refinements.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    String tweakLabel(String name) => Refinement.values
        .firstWhere((r) => r.name == name, orElse: () => Refinement.moreLikeMe)
        .label;

    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FigureRow('Sets of suggestions', grouped(summary.sets)),
          FigureRow(
            'One was copied',
            '${percent(summary.pickRate)} · ${grouped(summary.picked)}',
            emphasis: true,
          ),
          for (final entry in positions)
            FigureRow('Option ${entry.key + 1} taken', grouped(entry.value)),
          if (summary.newTopicShown > 0)
            FigureRow(
              'Topic change taken when offered',
              percent(summary.newTopicRate),
            ),
          if (tweaks.isNotEmpty)
            FigureRow(
              'Most asked-for tweak',
              '${tweakLabel(tweaks.first.key)} · ${tweaks.first.value}',
            ),
          FigureRow('Starred into the memory', grouped(summary.saved)),
          if (summary.pickRate < 0.4 && summary.sets >= 10) ...[
            const SizedBox(height: 8),
            Text(
              'Most sets go unused. Try ticking fewer, closer chats on the '
              'home screen, or raise "Retrieved examples" in Settings.',
              style: Type.prose(size: 12.5, color: Paper.muted, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
