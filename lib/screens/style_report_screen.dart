import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stored_exchange.dart';
import '../models/style_profile.dart';
import '../models/suggestion_feedback.dart';
import '../services/reply_generator.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/failure_text.dart';
import '../widgets/format.dart';
import '../widgets/paper_ui.dart';

/// What the app has measured about how you text, chat by chat, and how its
/// suggestions have fared. Everything here is worked out on the phone.
class StyleReportScreen extends ConsumerWidget {
  const StyleReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        const SerifTitle('How you text', size: 34),
        Text(
          'Counted from your own replies in each export. These are the same '
          'numbers the model is given, so if something looks wrong here, '
          'that is why a reply sounded off.',
          style: Type.prose(size: 14, color: Paper.body),
        ),
        ...chats.when(
          loading: () => [const LinearProgressIndicator(minHeight: 3)],
          error: (error, _) => [FailureNotice(error: error)],
          data: (all) {
            final measured = all.where((c) => !c.profile.isEmpty).toList();
            if (measured.isEmpty) {
              return [
                const Notice(
                  'Import a chat export and its numbers appear here.',
                  tone: NoticeTone.caution,
                  title: 'Nothing measured yet',
                ),
              ];
            }
            return [
              if (measured.length > 1) ...[
                const MonoLabel('Where your chats differ'),
                _Differences(chats: measured),
              ],
              for (final chat in measured) ...[
                MonoLabel(
                  chat.theirName.isEmpty
                      ? 'Unnamed chat'
                      : 'With ${chat.theirName}',
                ),
                _ProfileCard(profile: chat.profile),
              ],
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
        const Footnote('No API calls are made to build this page.'),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final StyleProfile profile;

  @override
  Widget build(BuildContext context) {
    final emoji = profile.topEmoji.take(8).map((e) => e.key).join(' ');
    final phrases = profile.topPhrases
        .where((e) => e.value >= 2)
        .take(8)
        .map((e) => '“${e.key}” ×${e.value}')
        .join('   ');
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FigureRow('Replies measured', grouped(profile.turns), emphasis: true),
          FigureRow(
            'Half your replies are at most',
            '${profile.medianWords} '
                '${profile.medianWords == 1 ? "word" : "words"}',
          ),
          FigureRow('Nine in ten are at most', '${profile.longWords} words'),
          FigureRow('Start lowercase', percent(profile.lowercaseShare)),
          FigureRow('End with a full stop', percent(profile.fullStopShare)),
          FigureRow('Have an emoji', percent(profile.emojiShare)),
          FigureRow('Ask a question', percent(profile.questionShare)),
          FigureRow(
            'Sent as several bubbles',
            '${percent(profile.multiBubbleShare)} · '
                '${profile.bubblesPerReply.toStringAsFixed(1)} per reply',
          ),
          if (emoji.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Favourite emoji',
              style: Type.prose(size: 12, color: Paper.tertiary, height: 1.3),
            ),
            const SizedBox(height: 3),
            Text(emoji, style: const TextStyle(fontSize: 20, height: 1.4)),
          ],
          if (phrases.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Things you say a lot',
              style: Type.prose(size: 12, color: Paper.tertiary, height: 1.3),
            ),
            const SizedBox(height: 3),
            Text(
              phrases,
              style: Type.prose(size: 13.5, color: Paper.ink, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// For each habit, the chat where you do it most and least — shown only
/// where the gap is big enough to matter.
class _Differences extends StatelessWidget {
  const _Differences({required this.chats});

  final List<ChatMemory> chats;

  static const double _meaningful = 0.15;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[];

    void compare(
      String habit,
      double Function(StyleProfile) share, {
      bool asPercent = true,
      double threshold = _meaningful,
      String Function(double)? show,
    }) {
      final sorted = [...chats]
        ..sort((a, b) => share(b.profile).compareTo(share(a.profile)));
      final most = sorted.first;
      final least = sorted.last;
      final gap = share(most.profile) - share(least.profile);
      if (gap < threshold) return;
      final fmt = show ?? (v) => asPercent ? percent(v) : v.toStringAsFixed(1);
      lines.add(
        '$habit: ${fmt(share(most.profile))} with '
        '${bidiIsolate(_name(most))}, ${fmt(share(least.profile))} with '
        '${bidiIsolate(_name(least))}',
      );
    }

    compare(
      'Typical length',
      (p) => p.medianWords.toDouble(),
      threshold: 2,
      show: (v) => '${v.round()} words',
    );
    compare('Emoji', (p) => p.emojiShare);
    compare('Lowercase starts', (p) => p.lowercaseShare);
    compare('Full stops', (p) => p.fullStopShare);
    compare('Several bubbles', (p) => p.multiBubbleShare);
    compare('Questions', (p) => p.questionShare);

    return PaperPanel(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      child: lines.isEmpty
          ? Text(
              'You write much the same way in every chat here.',
              style: Type.prose(size: 13.5, color: Paper.body, height: 1.45),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      line,
                      style: Type.prose(
                        size: 13.5,
                        color: Paper.body,
                        height: 1.45,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  static String _name(ChatMemory chat) =>
      chat.theirName.isEmpty ? 'an unnamed chat' : chat.theirName;
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
