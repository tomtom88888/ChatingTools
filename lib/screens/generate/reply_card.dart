import 'package:flutter/material.dart';

import '../../models/reply_suggestion.dart';
import '../../services/reply_generator.dart';
import '../../theme/tokens.dart';
import '../../widgets/paper_ui.dart';

/// One suggested message: what it is for, its bubbles, and what can be done
/// with it — copy, tweak, or star it into the memory.
class ReplyCard extends StatelessWidget {
  const ReplyCard({
    required this.suggestion,
    required this.provenance,
    required this.bubblesCopied,
    required this.onCopy,
    required this.onRefine,
    this.refining,
    this.saved = false,
    this.saving = false,
    this.onSave,
    super.key,
  });

  final ReplySuggestion suggestion;
  final String provenance;

  /// How many of this suggestion's bubbles have been copied so far.
  final int bubblesCopied;

  /// Copies the next bubble, or the whole message if it is one bubble.
  final VoidCallback onCopy;

  final ValueChanged<Refinement> onRefine;

  /// The tweak being worked on, if any.
  final Refinement? refining;

  final bool saved;
  final bool saving;

  /// Stars it into the memory; `null` when there is no chat to save into.
  final VoidCallback? onSave;

  /// A line break in a suggestion means a separate WhatsApp bubble.
  static List<String> bubblesOf(String text) => text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final changesSubject = suggestion.isNewTopic;
    final bubbles = bubblesOf(suggestion.text);
    final split = bubbles.length > 1;
    final allCopied = bubblesCopied >= bubbles.length && bubblesCopied > 0;
    final copyLabel = !split
        ? (allCopied ? 'Copied' : 'Copy')
        : allCopied
        ? 'All copied'
        : 'Copy ${bubblesCopied + 1} of ${bubbles.length}';
    final busy = refining != null;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: PaperCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // What this option is for. The one that changes the subject is
            // marked in the accent colour because it is the odd one out, and
            // picking it by accident would send the conversation sideways.
            Row(
              children: [
                if (changesSubject)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(right: 7),
                    decoration: const BoxDecoration(
                      color: Paper.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                Expanded(
                  child: MonoLabel(
                    split
                        ? '${suggestion.kind.label} · ${bubbles.length} bubbles'
                        : suggestion.kind.label,
                    size: 10.5,
                    spacing: 0.14,
                    color: changesSubject ? Paper.accent : Paper.muted,
                  ),
                ),
                _StarButton(saved: saved, saving: saving, onTap: onSave),
              ],
            ),
            const SizedBox(height: 9),
            AnimatedOpacity(
              opacity: busy ? 0.4 : 1,
              duration: const Duration(milliseconds: 150),
              child: split
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < bubbles.length; i++)
                          _Bubble(text: bubbles[i], copied: i < bubblesCopied),
                      ],
                    )
                  : Text(
                      suggestion.text,
                      style: Type.prose(
                        size: 15.5,
                        color: Paper.ink,
                        height: 1.5,
                      ),
                    ),
            ),
            const SizedBox(height: 11),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final refinement in Refinement.values)
                  _Chip(
                    label: refinement.label,
                    busy: refining == refinement,
                    onTap: busy ? null : () => onRefine(refinement),
                  ),
              ],
            ),
            const SizedBox(height: 11),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Paper.divider)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      provenance,
                      style: Type.numeric(
                        size: 11.5,
                        color: Paper.muted,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: busy ? null : onCopy,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: allCopied ? Paper.green : Paper.ink,
                        borderRadius: Corner.all(Corner.pill),
                      ),
                      child: Text(
                        copyLabel,
                        style: Type.strong(size: 13, color: Paper.onInk),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One bubble of a message you would send as several.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.copied});

  final String text;
  final bool copied;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Container(
      padding: const EdgeInsets.fromLTRB(11, 7, 11, 7),
      decoration: BoxDecoration(
        color: copied ? Paper.greenPanel : Paper.panel,
        borderRadius: const BorderRadius.only(
          topLeft: Corner.bubble,
          topRight: Corner.bubble,
          bottomLeft: Corner.bubble,
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Text(
        text,
        style: Type.prose(size: 15, color: Paper.ink, height: 1.45),
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.busy, this.onTap});

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Paper.bg,
        borderRadius: Corner.all(Corner.pill),
        border: Border.all(color: Paper.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Type.prose(
              size: 12,
              color: onTap == null && !busy
                  ? Paper.placeholder
                  : Paper.secondary,
              height: 1.2,
              weight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

class _StarButton extends StatelessWidget {
  const _StarButton({
    required this.saved,
    required this.saving,
    required this.onTap,
  });

  final bool saved;
  final bool saving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (saving) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      );
    }
    return Tooltip(
      message: saved
          ? 'Saved to your memory'
          : onTap == null
          ? 'Pick a chat to save into'
          : 'I sent this — learn from it',
      child: GestureDetector(
        onTap: saved ? null : onTap,
        child: Icon(
          saved ? Icons.star : Icons.star_border,
          size: 20,
          color: saved
              ? Paper.amber
              : onTap == null
              ? Paper.placeholder
              : Paper.tertiary,
        ),
      ),
    );
  }
}
