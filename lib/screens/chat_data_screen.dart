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
      children: [
        Row(
          children: [
            BackArrow(onTap: () => Navigator.of(context).pop()),
            const SizedBox(width: 10),
            const MonoLabel('Chat data'),
          ],
        ),
        ...chats.when(
          loading: () => [const LinearProgressIndicator(minHeight: 3)],
          error: (error, _) => [FailureNotice(error: error)],
          data: (all) {
            if (all.isEmpty) {
              return [
                const SerifTitle('Nothing to count yet.', size: 34),
                const Notice(
                  'Import a chat export and its numbers appear here.',
                  tone: NoticeTone.caution,
                ),
              ];
            }
            final chat = all.firstWhere(
              (c) => c.id == _selectedId,
              orElse: () => all.first,
            );
            final them = _name(chat);
            return [
              SerifTitle(
                'Everything you and ',
                accent: bidiIsolate(them),
                trailing: ' have said.',
                size: 34,
              ),
              if (all.length > 1)
                _ChatPills(
                  chats: all,
                  selected: chat.id,
                  onPick: (id) => setState(() => _selectedId = id),
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
                ..._sections(chat.stats, them),
            ];
          },
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MonoLabel('How the suggestions have done'),
            const SizedBox(height: 10),
            feedback.when(
              loading: () => const LinearProgressIndicator(minHeight: 3),
              error: (error, _) => FailureNotice(error: error),
              data: (entries) =>
                  _FeedbackCard(summary: FeedbackSummary.of(entries)),
            ),
          ],
        ),
        const Footnote('Counted on your phone. No API calls.'),
      ],
    );
  }

  static String _name(ChatMemory chat) =>
      chat.theirName.isEmpty ? 'them' : chat.theirName;

  List<Widget> _sections(ChatStats stats, String them) {
    final highlights = Highlights.of(stats, them: them);
    return [
      _Hero(stats: stats, them: them),
      if (highlights.isNotEmpty)
        _Section(
          label: 'What stands out',
          child: _Highlights(lines: highlights),
        ),
      _Section(
        label: 'You and ${bidiIsolate(them)}',
        trailing: _Legend(them: them),
        child: _Duels(stats: stats, them: them),
      ),
      if (stats.members.length > 1)
        _Section(
          label: 'Who talks most',
          child: _Members(stats: stats),
        ),
      _Section(
        label: 'When you talk',
        child: _WhenYouTalk(stats: stats),
      ),
      if (stats.me.topWords.isNotEmpty ||
          stats.them.topWords.isNotEmpty ||
          stats.me.topEmoji.isNotEmpty ||
          stats.them.topEmoji.isNotEmpty)
        _Section(
          label: 'Favourites',
          child: _Favourites(stats: stats, them: them),
        ),
    ];
  }
}

/// A mono label over its content, the way home titles its blocks.
class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child, this.trailing});

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: MonoLabel(label)),
          ?trailing,
        ],
      ),
      const SizedBox(height: 10),
      child,
    ],
  );
}

/// Which chat, in the ink-or-outline pills the app uses for a choice.
class _ChatPills extends StatelessWidget {
  const _ChatPills({
    required this.chats,
    required this.selected,
    required this.onPick,
  });

  final List<ChatMemory> chats;
  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final chat in chats) ...[
          if (chat != chats.first) const SizedBox(width: 8),
          GestureDetector(
            onTap: () => onPick(chat.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: chat.id == selected ? Paper.accent : Paper.card,
                borderRadius: Corner.all(Corner.pill),
                border: chat.id == selected
                    ? null
                    : Border.all(color: Paper.border, width: 1.5),
              ),
              child: Text(
                chat.theirName.isEmpty ? 'Unnamed' : chat.theirName,
                style: Type.strong(
                  size: 14,
                  color: chat.id == selected ? Paper.onAccent : Paper.ink,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// The headline: how much has been said, over how long, and by whom.
class _Hero extends StatelessWidget {
  const _Hero({required this.stats, required this.them});

  final ChatStats stats;
  final String them;

  static const Color _faint = Paper.onHeroFaint;

  @override
  Widget build(BuildContext context) {
    final first = stats.firstAt;
    final last = stats.lastAt;
    final span = first != null && last != null
        ? last.difference(first).inDays + 1
        : null;

    Widget figure(String value, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Type.numeric(size: 17, color: Paper.amber)),
          const SizedBox(height: 2),
          Text(label, style: Type.prose(size: 12, color: _faint, height: 1.3)),
        ],
      ),
    );

    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (first != null)
            MonoLabel(
              'Since ${dayMonthYear(first)}',
              color: Paper.onHero.withValues(alpha: 0.50),
            ),
          const SizedBox(height: 10),
          Text(
            grouped(stats.totalMessages),
            style: Type.display(56, color: Paper.onHero),
          ),
          Text(
            'messages between you',
            style: Type.prose(size: 15, color: _faint, height: 1.3),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              figure(compactTokens(stats.totalWords), 'words'),
              if (span != null) figure(grouped(span), 'days'),
              figure(grouped(stats.activeDays), 'days you talked'),
            ],
          ),
          const SizedBox(height: 18),
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
    const faint = Paper.onHeroFaint;
    final mine = (share * 1000).round().clamp(1, 999);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: Corner.all(Corner.pill),
          child: SizedBox(
            height: 6,
            child: Row(
              // Without this the fills have no height and draw nothing.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: mine,
                  child: ColoredBox(color: Paper.amber),
                ),
                // The 2px gap between the two fills.
                const SizedBox(width: 2),
                Expanded(
                  flex: 1000 - mine,
                  child: ColoredBox(
                    color: Paper.onHero.withValues(alpha: 0.25),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: Text(
                'You · ${percent(share)}',
                style: Type.prose(size: 12.5, color: Paper.onHero, height: 1.3),
              ),
            ),
            Text(
              '${percent(1 - share)} · ${bidiIsolate(them)}',
              style: Type.prose(size: 12.5, color: faint, height: 1.3),
            ),
          ],
        ),
      ],
    );
  }
}

/// The few facts worth saying out loud, in plain sentences.
///
/// Each is only offered when the gap it describes is big enough to be
/// interesting, so a balanced chat gets fewer lines rather than dull ones.
class Highlights {
  const Highlights._();

  static List<String> of(ChatStats stats, {required String them}) {
    final me = stats.me;
    final other = stats.them;
    final name = bidiIsolate(them);
    final lines = <String>[];

    final mine = me.medianReplySeconds;
    final theirs = other.medianReplySeconds;
    if (mine != null && theirs != null) {
      lines.add(
        'You usually reply in *${replyTime(mine)}*; $name takes '
        '*${replyTime(theirs)}*.',
      );
    }

    final starts = me.conversationsStarted + other.conversationsStarted;
    if (starts >= 5) {
      final share = me.conversationsStarted / starts;
      if (share >= 0.58) {
        lines.add('You start *${percent(share)}* of your conversations.');
      } else if (share <= 0.42) {
        lines.add(
          '$name starts *${percent(1 - share)}* of your conversations.',
        );
      }
    }

    final a = me.wordsPerMessage;
    final b = other.wordsPerMessage;
    if (a > 0 && b > 0 && (a / b >= 1.3 || b / a >= 1.3)) {
      final longer = a > b;
      lines.add(
        '${longer ? "You write" : "$name writes"} longer: '
        '*${(longer ? a : b).toStringAsFixed(1)} words* a message to '
        '${longer ? "their" : "your"} ${(longer ? b : a).toStringAsFixed(1)}.',
      );
    }

    if (me.laughs >= 10 && other.laughs >= 10) {
      final ratio = me.laughs / other.laughs;
      if (ratio >= 1.5) {
        lines.add('You laugh *${ratio.toStringAsFixed(1)}×* as often.');
      } else if (ratio <= 1 / 1.5) {
        lines.add(
          '$name laughs *${(1 / ratio).toStringAsFixed(1)}×* as often.',
        );
      }
    }

    final busiest = stats.busiestDay;
    if (busiest != null && stats.busiestDayMessages >= 20) {
      lines.add(
        'Your busiest day was *${dayMonthYear(busiest)}*: '
        '${grouped(stats.busiestDayMessages)} messages.',
      );
    }

    if (stats.longestStreakDays >= 7) {
      lines.add(
        'At your longest, you talked *${grouped(stats.longestStreakDays)} '
        'days in a row*.',
      );
    }
    return lines.take(5).toList();
  }
}

/// Numbered lines, as home lists its three steps.
class _Highlights extends StatelessWidget {
  const _Highlights({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) => PaperPanel(
    radius: Corner.card,
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
    child: Column(
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 30,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    (i + 1).toString().padLeft(2, '0'),
                    style: Type.numeric(size: 12, color: Paper.accent),
                  ),
                ),
              ),
              Expanded(
                child: emphasised(lines[i], size: 14.5, color: Paper.body),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

/// You in ink, them in the accent — the key for the paired bars.
class _Legend extends StatelessWidget {
  const _Legend({required this.them});

  final String them;

  @override
  Widget build(BuildContext context) {
    Widget key(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: Corner.all(const Radius.circular(2)),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: Type.prose(size: 12, color: Paper.secondary, height: 1.2),
        ),
      ],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        key(Paper.ink, 'You'),
        const SizedBox(width: 12),
        key(Paper.accent, bidiIsolate(them)),
      ],
    );
  }
}

/// Every side-by-side figure, as paired bars grouped into three cards.
class _Duels extends StatelessWidget {
  const _Duels({required this.stats, required this.them});

  final ChatStats stats;
  final String them;

  @override
  Widget build(BuildContext context) {
    final me = stats.me;
    final other = stats.them;

    _Duel count(String label, int a, int b) =>
        _Duel(label, a.toDouble(), b.toDouble(), grouped(a), grouped(b));

    final groups = <(String, List<_Duel>)>[
      (
        'Talking',
        [
          count('Messages', me.messages, other.messages),
          count('Words', me.words, other.words),
          _Duel(
            'Words per message',
            me.wordsPerMessage,
            other.wordsPerMessage,
            me.wordsPerMessage.toStringAsFixed(1),
            other.wordsPerMessage.toStringAsFixed(1),
          ),
          count(
            'Longest message, in words',
            me.longestMessageWords,
            other.longestMessageWords,
          ),
        ],
      ),
      (
        'Replying',
        [
          _Duel(
            'Typical reply time',
            (me.medianReplySeconds ?? 0).toDouble(),
            (other.medianReplySeconds ?? 0).toDouble(),
            replyTime(me.medianReplySeconds),
            replyTime(other.medianReplySeconds),
          ),
          _Duel(
            'Replies within 5 minutes',
            me.quickReplyShare,
            other.quickReplyShare,
            percent(me.quickReplyShare),
            percent(other.quickReplyShare),
          ),
          count(
            'Conversations started',
            me.conversationsStarted,
            other.conversationsStarted,
          ),
          count('Double texts', me.doubleTexts, other.doubleTexts),
        ],
      ),
      (
        'Little things',
        [
          count('Questions', me.questions, other.questions),
          count('Laughs', me.laughs, other.laughs),
          count('Emoji', me.emoji, other.emoji),
          count('Photos & media', me.media, other.media),
          count('After midnight', me.lateNight, other.lateNight),
          count('Deleted', me.deleted, other.deleted),
        ],
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (title, duels) in groups) ...[
          if (title != groups.first.$1) const SizedBox(height: 12),
          PaperCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Type.display(22)),
                const SizedBox(height: 6),
                for (var i = 0; i < duels.length; i++)
                  _DuelRow(
                    duel: duels[i],
                    them: them,
                    last: i == duels.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Duel {
  const _Duel(this.label, this.mine, this.theirs, this.myText, this.theirText);

  final String label;
  final double mine;
  final double theirs;
  final String myText;
  final String theirText;
}

/// One figure for each of you: a label, then two thin bars on a shared scale
/// with the values beside them.
class _DuelRow extends StatelessWidget {
  const _DuelRow({required this.duel, required this.them, required this.last});

  final _Duel duel;
  final String them;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final top = duel.mine > duel.theirs ? duel.mine : duel.theirs;

    Widget bar(double value, Color color, String text, String semantic) =>
        Semantics(
          label: '$semantic: $text',
          excludeSemantics: true,
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = top <= 0
                        ? 0.0
                        : (value / top * constraints.maxWidth).clamp(
                            value > 0 ? 3.0 : 0.0,
                            constraints.maxWidth,
                          );
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: width,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(4),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 104,
                child: Text(
                  text,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.numeric(size: 12.5),
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: Paper.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            duel.label,
            style: Type.prose(size: 13, color: Paper.secondary, height: 1.3),
          ),
          const SizedBox(height: 7),
          bar(duel.mine, Paper.ink, duel.myText, 'You'),
          const SizedBox(height: 5),
          bar(duel.theirs, Paper.accent, duel.theirText, them),
        ],
      ),
    );
  }
}

/// In a group: everyone's message count, you included, most first.
class _Members extends StatelessWidget {
  const _Members({required this.stats});

  final ChatStats stats;

  static const int shown = 8;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('You', stats.me.messages, true),
      for (final m in stats.members.entries) (m.key, m.value, false),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final top = rows.first.$2;
    final hidden = rows.length - shown;
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (name, count, isMe) in rows.take(shown))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: isMe
                          ? Type.strong(size: 13.5)
                          : Type.prose(size: 13.5, color: Paper.body),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: top == 0
                              ? 0
                              : (count / top * box.maxWidth).clamp(
                                  count > 0 ? 3.0 : 0.0,
                                  box.maxWidth,
                                ),
                          height: 6,
                          decoration: BoxDecoration(
                            color: isMe ? Paper.ink : Paper.accent,
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 64,
                    child: Text(
                      grouped(count),
                      textAlign: TextAlign.end,
                      style: Type.numeric(size: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'and $hidden more',
                style: Type.prose(size: 12.5, color: Paper.muted),
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

    Widget record(String value, String label) => Expanded(
      child: PaperPanel(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Type.numeric(size: 18)),
            const SizedBox(height: 3),
            Text(
              label,
              style: Type.prose(size: 12, color: Paper.tertiary, height: 1.3),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaperCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stats.byHour.length == 24)
                BarStrip(
                  key: const ValueKey('by-hour'),
                  title: 'Through the day',
                  values: stats.byHour,
                  describe: (i) => '${_hour(i)}–${_hour((i + 1) % 24)}',
                  axisLabel: (i) =>
                      i % 6 == 0 ? i.toString().padLeft(2, '0') : '',
                ),
              const SizedBox(height: 22),
              if (stats.byWeekday.length == 7)
                BarStrip(
                  key: const ValueKey('by-weekday'),
                  title: 'Through the week',
                  values: stats.byWeekday,
                  describe: (i) => _days[i],
                  axisLabel: (i) => _days[i].substring(0, 1),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Equal heights, so the three tiles read as one row.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (busiest != null) ...[
                record(dayMonth(busiest), 'busiest day'),
                const SizedBox(width: 8),
              ],
              record(grouped(stats.longestStreakDays), 'days in a row'),
              const SizedBox(width: 8),
              if (stats.byHour.isNotEmpty)
                record(_hour(_peakHour()), 'busiest hour'),
            ],
          ),
        ),
      ],
    );
  }

  int _peakHour() {
    var best = 0;
    for (var i = 1; i < stats.byHour.length; i++) {
      if (stats.byHour[i] > stats.byHour[best]) best = i;
    }
    return best;
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

/// Top emoji and words, each side, with the words as pills.
class _Favourites extends StatelessWidget {
  const _Favourites({required this.stats, required this.them});

  final ChatStats stats;
  final String them;

  @override
  Widget build(BuildContext context) {
    Widget side(String who, PersonStats person, Color mark) {
      final emoji = person.topEmoji.keys.take(6).join('  ');
      final words = person.topWords.entries.take(6).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 7),
                decoration: BoxDecoration(
                  color: mark,
                  borderRadius: Corner.all(const Radius.circular(2)),
                ),
              ),
              Text(who, style: Type.strong(size: 14, height: 1.3)),
            ],
          ),
          if (emoji.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(emoji, style: const TextStyle(fontSize: 22, height: 1.3)),
          ],
          if (words.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final word in words)
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
                    decoration: BoxDecoration(
                      color: Paper.panel,
                      borderRadius: Corner.all(Corner.pill),
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: word.key,
                            style: Type.prose(
                              size: 13,
                              color: Paper.ink,
                              height: 1.2,
                            ),
                          ),
                          TextSpan(
                            text: '  ${grouped(word.value)}',
                            style: Type.numeric(
                              size: 11,
                              color: Paper.muted,
                              weight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      );
    }

    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          side('You', stats.me, Paper.ink),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 16),
            color: Paper.divider,
          ),
          side(bidiIsolate(them), stats.them, Paper.accent),
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
