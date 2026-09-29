import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'paper_ui.dart';

/// Which app a chat is being exported from.
enum ExportApp { whatsapp, instagram }

/// How to get a chat out of WhatsApp or Instagram, in a few steps each, with
/// a switch between the two.
class ExportGuides extends StatefulWidget {
  const ExportGuides({this.who, super.key});

  /// The person whose chat is being exported, when known.
  final String? who;

  static List<String> whatsappSteps(String who) => [
    'Open the chat with *${bidiIsolate(who)}* in WhatsApp.',
    'iPhone: tap their *name* at the top. Android: tap the *three dots*, '
        'then *More*.',
    'Tap *Export chat*.',
    'Choose *Without media*: photos carry no style, and the file stays '
        'small.',
    'Share it to *Ditto*, or save it and pick it here.',
  ];

  static const List<String> instagramSteps = [
    'In Instagram, open your profile, tap the *menu* (three lines), then '
        '*Accounts Center*.',
    'Tap *Your information and permissions*, then *Download your '
        'information*.',
    'Choose *Some of your information* and tick only *Messages*.',
    'Pick *Download to device*, and set *Format* to *JSON* (not HTML), '
        '*Date range* to *All time* and *Media quality* to *Low*.',
    'Instagram tells you when it is ready: minutes to a day. Download the '
        '*.zip* and pick it here; Ditto asks which conversation to learn.',
  ];

  @override
  State<ExportGuides> createState() => _ExportGuidesState();
}

class _ExportGuidesState extends State<ExportGuides> {
  ExportApp _app = ExportApp.whatsapp;

  @override
  Widget build(BuildContext context) {
    final who = widget.who ?? 'the person';
    Widget pill(ExportApp app, String label) {
      final on = _app == app;
      return Expanded(
        child: GestureDetector(
          key: ValueKey('guide-${app.name}'),
          onTap: () => setState(() => _app = app),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Paper.accent : Colors.transparent,
              borderRadius: Corner.all(Corner.pill),
            ),
            child: Text(
              label,
              style: Type.strong(
                size: 14,
                color: on ? Paper.onAccent : Paper.secondary,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Paper.panel,
            borderRadius: Corner.all(Corner.pill),
          ),
          child: Row(
            children: [
              pill(ExportApp.whatsapp, 'WhatsApp'),
              const SizedBox(width: 4),
              pill(ExportApp.instagram, 'Instagram'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        NumberedSteps(
          _app == ExportApp.whatsapp
              ? ExportGuides.whatsappSteps(who)
              : ExportGuides.instagramSteps,
        ),
        if (_app == ExportApp.instagram) ...[
          const SizedBox(height: 10),
          Text(
            'One Instagram download holds all your conversations: keep the '
            'zip, and pick it again later to add another person.',
            style: Type.prose(size: 12.5, color: Paper.muted, height: 1.4),
          ),
        ],
      ],
    );
  }
}
