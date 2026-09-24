import 'package:flutter/material.dart';

import '../../models/app_settings.dart';
import '../../models/extracted_message.dart';
import '../../theme/tokens.dart';
import '../../widgets/paper_ui.dart';

/// What the vision model read, and the correction affordances.
class Transcript extends StatelessWidget {
  const Transcript({
    required this.messages,
    required this.settings,
    required this.fixing,
    required this.onToggleFixing,
    required this.onToggleSide,
    required this.onEdit,
    super.key,
  });

  final List<ExtractedMessage> messages;
  final AppSettings settings;
  final bool fixing;
  final VoidCallback onToggleFixing;
  final ValueChanged<int> onToggleSide;
  final ValueChanged<int> onEdit;

  @override
  Widget build(BuildContext context) {
    // Collapsed, the transcript shows only the tail — the exchange being
    // replied to. Fixing shows every message with its controls.
    final visible = fixing || messages.length <= 3
        ? messages
        : messages.sublist(messages.length - 3);
    final hidden = messages.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: MonoLabel(
                'It read ${messages.length} '
                '${messages.length == 1 ? "message" : "messages"}',
                spacing: 0.12,
              ),
            ),
            GestureDetector(
              onTap: onToggleFixing,
              child: Text(
                fixing ? 'Done fixing' : 'Fix the reading',
                style: Type.prose(
                  size: 12,
                  color: Paper.accent,
                  height: 1.3,
                  weight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        PaperPanel(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hidden > 0) ...[
                Text(
                  '…$hidden earlier',
                  style: Type.prose(size: 12, color: Paper.muted, height: 1.3),
                ),
                const SizedBox(height: 7),
              ],
              for (var i = 0; i < visible.length; i++)
                _TranscriptLine(
                  message: visible[i],
                  settings: settings,
                  fixing: fixing,
                  onToggleSide: () =>
                      onToggleSide(messages.length - visible.length + i),
                  onEdit: () => onEdit(messages.length - visible.length + i),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TranscriptLine extends StatelessWidget {
  const _TranscriptLine({
    required this.message,
    required this.settings,
    required this.fixing,
    required this.onToggleSide,
    required this.onEdit,
  });

  final ExtractedMessage message;
  final AppSettings settings;
  final bool fixing;
  final VoidCallback onToggleSide;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final mine = message.speaker == Speaker.me;
    final bubble = GestureDetector(
      onTap: fixing ? onEdit : null,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.62,
        ),
        padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
        decoration: BoxDecoration(
          color: mine ? Paper.ink : Paper.card,
          borderRadius: BorderRadius.only(
            topLeft: Corner.bubble,
            topRight: Corner.bubble,
            bottomLeft: mine ? Corner.bubble : const Radius.circular(4),
            bottomRight: mine ? const Radius.circular(4) : Corner.bubble,
          ),
        ),
        child: Text(
          message.text,
          style: Type.prose(
            size: 13.5,
            color: mine ? Paper.onInk : Paper.ink,
            height: 1.4,
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (mine && fixing) _SideToggle(onTap: onToggleSide, mine: true),
          bubble,
          if (!mine && fixing) _SideToggle(onTap: onToggleSide, mine: false),
        ],
      ),
    );
  }
}

/// The correction that matters most: which side a message came from.
class _SideToggle extends StatelessWidget {
  const _SideToggle({required this.onTap, required this.mine});

  final VoidCallback onTap;
  final bool mine;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: EdgeInsets.only(right: mine ? 8 : 0, left: mine ? 0 : 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Paper.card,
        borderRadius: Corner.all(Corner.pill),
        border: Border.all(color: Paper.border),
      ),
      child: Text(
        mine ? '→ them' : 'me ←',
        style: Type.prose(
          size: 11,
          color: Paper.secondary,
          height: 1.2,
          weight: FontWeight.w500,
        ),
      ),
    ),
  );
}
