import 'package:flutter/material.dart';

import '../models/stored_exchange.dart';
import '../theme/tokens.dart';
import '../widgets/paper_ui.dart';

/// Shows the past exchanges pulled out of the style memory for one generation.
///
/// This is the app explaining itself: the suggestions are only as good as what
/// similarity search found, and the only way to judge that is to read it. Each
/// entry is a real conversation off this phone, so nothing here is fetched and
/// nothing leaves the device to display it.
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
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const Padding(
                padding: EdgeInsets.only(right: 14),
                child: Text(
                  '←',
                  style: TextStyle(fontSize: 19, color: Paper.secondary),
                ),
              ),
            ),
            Expanded(
              child: Text(
                'What it drew on',
                style: Type.strong(size: 15, height: 1.3),
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  ? 'Similarity search came back empty, so the replies you '
                        'were offered are a general model guessing rather than '
                        'your own voice. Training on a longer export usually '
                        'fixes it.'
                  : 'Closest first. These are your real messages, read off '
                        'this phone — the model saw exactly this, and '
                        'copied from it.',
              style: Type.prose(size: 14),
            ),
          ],
        ),
        if (examples.isNotEmpty)
          for (var i = 0; i < examples.length; i++)
            _ExchangeCard(
              rank: i + 1,
              scored: examples[i],
              myName: myName,
              theirName: theirName,
            ),
        if (examples.isNotEmpty)
          const Footnote(
            'Retrieved from the fingerprints stored on this phone. Nothing was '
            'fetched to show this.',
          ),
      ],
    );
  }
}

class _ExchangeCard extends StatelessWidget {
  const _ExchangeCard({
    required this.rank,
    required this.scored,
    required this.myName,
    required this.theirName,
  });

  final int rank;
  final ScoredExchange scored;
  final String myName;
  final String theirName;

  @override
  Widget build(BuildContext context) {
    final exchange = scored.exchange;
    final when = exchange.timestamp;

    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  style: Type.prose(
                    size: 12,
                    color: Paper.tertiary,
                    height: 1.3,
                  ),
                ),
              ),
              _Similarity(value: scored.similarity),
            ],
          ),
          const SizedBox(height: 12),
          // The conversation as it happened, in the same bubble language the
          // Generate screen uses for the screenshot it read.
          PaperPanel(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final turn in exchange.context)
                  _Bubble(
                    text: turn.text,
                    mine: turn.sender == myName,
                    label: turn.sender,
                  ),
                _Bubble(
                  text: exchange.replyText,
                  mine: true,
                  label: myName,
                  highlighted: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'You replied with the highlighted message.',
            style: Type.prose(size: 12, color: Paper.muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _when(DateTime at) =>
      '${at.day} ${_months[at.month - 1]} ${at.year}';
}

/// Cosine similarity, shown as the raw figure the provenance line quotes.
class _Similarity extends StatelessWidget {
  const _Similarity({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: Paper.panel,
      borderRadius: Corner.all(Corner.pill),
    ),
    child: Text(
      value.toStringAsFixed(2),
      style: Type.numeric(size: 11.5, color: Paper.secondary),
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.mine,
    required this.label,
    this.highlighted = false,
  });

  final String text;
  final bool mine;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final bg = mine
        ? (highlighted ? Paper.accent : Paper.ink)
        : Paper.card;
    final fg = mine ? Colors.white : Paper.ink;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.66,
            ),
            padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.only(
                topLeft: Corner.bubble,
                topRight: Corner.bubble,
                bottomLeft: mine ? Corner.bubble : const Radius.circular(4),
                bottomRight: mine ? const Radius.circular(4) : Corner.bubble,
              ),
            ),
            child: Text(
              text,
              style: Type.prose(size: 13.5, color: fg, height: 1.4),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Type.prose(size: 10.5, color: Paper.muted, height: 1.2),
          ),
        ],
      ),
    );
  }
}
