import 'package:flutter/material.dart';

import '../models/stored_exchange.dart';
import '../theme/tokens.dart';
import '../widgets/paper_ui.dart';

/// The past exchanges similarity search pulled out of the style memory for one
/// generation.
///
/// This is the app showing its working: the suggestions are only as good as
/// what retrieval found, and the only way to judge that is to read it. Each
/// entry is a real conversation off this phone — nothing is fetched to display
/// it.
///
/// It is laid out as a transcript on the page rather than as cards: bubbles
/// inside a panel inside a card stacked three surfaces deep and read as mush.
/// Here the page is the only surface and the bubbles sit straight on it, the
/// way a chat log looks.
class RetrievedExchangesScreen extends StatelessWidget {
  const RetrievedExchangesScreen({
    required this.examples,
    required this.myName,
    required this.theirName,
    super.key,
  });

  final List<ScoredExchange> examples;
  final String myName;
  final String theirName;

  @override
  Widget build(BuildContext context) {
    return PaperScreen(
      gap: 0,
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: BackArrow(onTap: () => Navigator.of(context).pop()),
            ),
            Expanded(
              child: Text(
                'What it drew on',
                style: Type.strong(size: 15, height: 1.3),
              ),
            ),
          ],
        ),
        const SizedBox(height: Frame.gap),
        SerifTitle(
          examples.isEmpty
              ? 'Nothing in your memory matched.'
              : '${examples.length} past '
                    '${examples.length == 1 ? "exchange" : "exchanges"} '
                    'like this one',
          size: 28,
        ),
        const SizedBox(height: 9),
        Text(
          examples.isEmpty
              ? 'Similarity search came back empty, so the replies you were '
                    'offered are a general model guessing rather than your own '
                    'voice. Training on a longer export usually fixes it.'
              : 'Closest first. These are your real messages, read off this '
                    'phone — the model saw exactly this and copied from it. '
                    'Your reply is the one in colour.',
          style: Type.prose(size: 14),
        ),
        if (examples.isNotEmpty) ...[
          const SizedBox(height: 4),
          for (var i = 0; i < examples.length; i++)
            _Exchange(
              rank: i + 1,
              scored: examples[i],
              myName: myName,
              first: i == 0,
            ),
          const SizedBox(height: 20),
          const Footnote(
            'Read from the fingerprints stored on this phone. Nothing was '
            'fetched to show this.',
          ),
        ],
      ],
    );
  }
}

/// One retrieved conversation: a quiet header line, then the turns.
class _Exchange extends StatelessWidget {
  const _Exchange({
    required this.rank,
    required this.scored,
    required this.myName,
    required this.first,
  });

  final int rank;
  final ScoredExchange scored;
  final String myName;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final exchange = scored.exchange;
    final when = exchange.timestamp;

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!first)
            Padding(
              padding: EdgeInsets.only(bottom: 18),
              child: Divider(height: 1, thickness: 1, color: Paper.divider),
            ),
          Row(
            children: [
              Text(
                rank.toString().padLeft(2, '0'),
                style: Type.numeric(size: 12, color: Paper.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  when == null ? 'date unknown' : _when(when),
                  style: Type.numeric(
                    size: 12,
                    color: Paper.muted,
                    weight: FontWeight.w400,
                  ),
                ),
              ),
              Text(
                scored.similarity.toStringAsFixed(2),
                style: Type.numeric(size: 12, color: Paper.tertiary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final turn in exchange.context)
            _Bubble(text: turn.text, mine: turn.sender == myName),
          _Bubble(text: exchange.replyText, mine: true, isTheReply: true),
        ],
      ),
    );
  }

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

  static String _when(DateTime at) =>
      '${at.day} ${_months[at.month - 1]} ${at.year}';
}

/// A single message, sitting directly on the page.
///
/// Side says who spoke, as it does in WhatsApp and on the Generate screen, so
/// no name label is needed and a right-to-left name cannot mislead.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.mine,
    this.isTheReply = false,
  });

  final String text;
  final bool mine;

  /// The message actually sent, which is the thing worth reading.
  final bool isTheReply;

  @override
  Widget build(BuildContext context) {
    // Laid out like the chat itself: your bubbles green on the right, theirs
    // on the left. The reply that was actually sent is outlined in the
    // accent, because it is the part worth reading.
    final background = mine || isTheReply
        ? Paper.bubbleMine
        : Paper.bubbleTheirs;
    final foreground = Paper.ink;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.72,
              ),
              padding: const EdgeInsets.fromLTRB(13, 9, 13, 9),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.only(
                  topLeft: mine ? Corner.bubble : Corner.tail,
                  topRight: mine ? Corner.tail : Corner.bubble,
                  bottomLeft: Corner.bubble,
                  bottomRight: Corner.bubble,
                ),
                border: isTheReply
                    ? Border.all(color: Paper.accent, width: 1.5)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Paper.shadowSoft,
                    blurRadius: 1,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                text,
                style: Type.prose(size: 14, color: foreground, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
