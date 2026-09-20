import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/app_settings.dart';
import '../models/extracted_message.dart';
import '../models/stored_exchange.dart';
import '../services/reply_generator.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/failure_text.dart';
import '../widgets/paper_ui.dart';
import 'retrieved_exchanges_screen.dart';

/// Pick a screenshot, check what was read off it, take one of three replies.
class GenerateScreen extends ConsumerStatefulWidget {
  const GenerateScreen({super.key});

  @override
  ConsumerState<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends ConsumerState<GenerateScreen> {
  Uint8List? _screenshot;
  List<ExtractedMessage> _messages = [];
  List<String> _variants = [];
  List<ScoredExchange> _examples = [];

  bool _reading = false;
  bool _generating = false;
  bool _fixing = false;
  int? _copiedIndex;
  Object? _error;

  Future<void> _pickScreenshot() async {
    setState(() => _error = null);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // Big enough for small text to stay legible, small enough to keep the
        // vision call cheap.
        maxWidth: 1400,
        imageQuality: 90,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        _screenshot = bytes;
        _messages = [];
        _variants = [];
        _examples = [];
        _copiedIndex = null;
      });
      await _extract(bytes, picked.mimeType ?? _guessMimeType(picked.name));
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  static String _guessMimeType(String name) =>
      name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';

  Future<void> _extract(Uint8List bytes, String mimeType) async {
    final openai = ref.read(openAiServiceProvider);
    if (openai == null) return;
    final settings = await ref.read(settingsProvider.future);

    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final messages = await openai.extractConversation(
        imageBytes: bytes,
        model: settings.visionModel,
        imageMimeType: mimeType,
      );
      if (mounted) setState(() => _messages = messages);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _generate() async {
    final generator = ref.read(replyGeneratorProvider);
    final memory = ref.read(styleMemoryServiceProvider);
    if (generator == null || memory == null) return;
    final settings = await ref.read(settingsProvider.future);
    final named = settings.copyWith(
      myName: settings.myName.isEmpty ? 'Me' : settings.myName,
      theirName: settings.theirName.isEmpty ? 'Them' : settings.theirName,
    );

    setState(() {
      _generating = true;
      _error = null;
      _variants = [];
      _copiedIndex = null;
    });
    try {
      final conversation = ReplyGenerator.turnsFrom(
        _messages,
        myName: named.myName,
        theirName: named.theirName,
      );
      final examples = await memory.retrieve(
        context: conversation,
        embeddingModel: named.embeddingModel,
        dimensions: named.embeddingDimensions,
        limit: named.retrievedExampleCount,
      );
      final variants = await generator.generate(
        conversation: conversation,
        examples: examples,
        settings: named,
      );
      if (mounted) {
        setState(() {
          _examples = examples;
          _variants = variants;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _copy(int index) async {
    await Clipboard.setData(ClipboardData(text: _variants[index]));
    if (!mounted) return;
    setState(() => _copiedIndex = index);
    showToast(
      context,
      'Copied. Go paste it.',
      detail: "The app can't send it — you're leaving for WhatsApp now.",
    );
  }

  void _flipAll() {
    setState(() {
      _messages = [
        for (final m in _messages)
          m.copyWith(
            speaker: m.speaker == Speaker.me ? Speaker.them : Speaker.me,
          ),
      ];
      _variants = [];
      _error = null;
    });
  }

  void _toggleSide(int index) {
    setState(() {
      final message = _messages[index];
      _messages[index] = message.copyWith(
        speaker: message.speaker == Speaker.me ? Speaker.them : Speaker.me,
      );
      _variants = [];
    });
  }

  Future<void> _editText(int index) async {
    final controller = TextEditingController(text: _messages[index].text);
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Paper.bg,
        surfaceTintColor: Paper.bg,
        shape: RoundedRectangleBorder(borderRadius: Corner.all(Corner.card)),
        title: Text('Fix the text', style: Type.strong(size: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          style: Type.prose(size: 15, color: Paper.ink),
          decoration: InputDecoration(
            filled: true,
            fillColor: Paper.card,
            border: OutlineInputBorder(
              borderRadius: Corner.all(Corner.small),
              borderSide: const BorderSide(color: Paper.border, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: Corner.all(Corner.small),
              borderSide: const BorderSide(color: Paper.border, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: Corner.all(Corner.small),
              borderSide: const BorderSide(color: Paper.accent, width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: Type.strong(size: 14, color: Paper.secondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text('Save', style: Type.strong(size: 14, color: Paper.accent)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updated == null || !mounted) return;
    setState(() {
      if (updated.trim().isEmpty) {
        _messages.removeAt(index);
      } else {
        _messages[index] = _messages[index].copyWith(text: updated.trim());
      }
      _variants = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final them = settings.theirName.isEmpty ? 'them' : settings.theirName;
    final ready = _messages.isNotEmpty && !_generating && !_reading;
    final lastIsMine =
        _messages.isNotEmpty && _messages.last.speaker == Speaker.me;

    return PaperScreen(
      padding: const EdgeInsets.fromLTRB(22, 62, 22, 34),
      gap: 16,
      bottom: _variants.isEmpty
          ? null
          : Row(
              children: [
                Expanded(
                  child: PaperAction(
                    title: 'Three more',
                    centred: true,
                    radius: Corner.choice,
                    onTap: _generating ? null : _generate,
                  ),
                ),
                const SizedBox(width: 10),
                PaperAction(
                  title: 'New shot',
                  centred: true,
                  tone: ActionTone.outline,
                  radius: Corner.choice,
                  onTap: _pickScreenshot,
                ),
              ],
            ),
      children: [
        _Header(
          them: them,
          onBack: () => Navigator.of(context).pop(),
          onChangeShot: _screenshot == null ? null : _pickScreenshot,
        ),
        if (_error != null)
          _Refusal(
            error: _error!,
            onFlipAll: lastIsMine ? _flipAll : null,
            onFix: _messages.isEmpty ? null : () => setState(() => _fixing = true),
          ),
        if (_screenshot == null)
          _EmptyState(onPick: _pickScreenshot)
        else if (_reading)
          const _ReadingState()
        else if (_messages.isNotEmpty)
          _Transcript(
            messages: _messages,
            settings: settings,
            fixing: _fixing,
            onToggleFixing: () => setState(() => _fixing = !_fixing),
            onToggleSide: _toggleSide,
            onEdit: _editText,
          ),
        if (_messages.isNotEmpty && _variants.isEmpty && !_generating)
          PaperAction(
            title: 'Write ${settings.variantCount} replies',
            centred: true,
            tone: ActionTone.accent,
            onTap: ready ? _generate : null,
          ),
        if (_generating) const _GeneratingState(),
        if (_variants.isNotEmpty) ...[
          SerifTitle('Three ways you’d answer that', size: 22),
          for (var i = 0; i < _variants.length; i++)
            _ReplyCard(
              text: _variants[i],
              copied: _copiedIndex == i,
              provenance: _provenance(i),
              onCopy: () => _copy(i),
            ),
          _Provenance(
            examples: _examples,
            model: settings.effectiveGenerationModel,
            mode: settings.mode == TrainingMode.fineTune &&
                    settings.hasFineTunedModel
                ? 'fine-tuned model'
                : 'style memory',
            onInspect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RetrievedExchangesScreen(
                  examples: _examples,
                  myName: settings.myName.isEmpty ? 'Me' : settings.myName,
                  theirName: settings.theirName.isEmpty
                      ? 'Them'
                      : settings.theirName,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The design labels each reply with its shape and the date of the example it
  /// most resembles; without a match it says only how long it is.
  String _provenance(int index) {
    final lines = _variants[index].split('\n').length;
    final unit = lines == 1 ? 'line' : 'lines';
    if (_examples.isEmpty) return '$lines $unit';
    final when = _examples[index % _examples.length].exchange.timestamp;
    if (when == null) return '$lines $unit · like you before';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '$lines $unit · like you on '
        '${when.day} ${months[when.month - 1]}';
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.them,
    required this.onBack,
    required this.onChangeShot,
  });

  final String them;
  final VoidCallback onBack;
  final VoidCallback? onChangeShot;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      GestureDetector(
        onTap: onBack,
        child: const Text(
          '←',
          style: TextStyle(fontSize: 19, color: Paper.secondary),
        ),
      ),
      Expanded(
        child: Center(
          child: Text(
            'Replying to ${bidiIsolate(them)}',
            style: Type.strong(size: 15, height: 1.3),
          ),
        ),
      ),
      GestureDetector(
        onTap: onChangeShot,
        child: Text(
          'Change shot',
          style: Type.prose(
            size: 12,
            color: onChangeShot == null ? Paper.muted : Paper.accent,
            height: 1.3,
            weight: FontWeight.w500,
          ),
        ),
      ),
    ],
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PaperPanel(
        radius: Corner.hero,
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SerifTitle('Screenshot the chat as it stands.', size: 30),
            const SizedBox(height: 10),
            Text(
              'A straight screenshot of the conversation works best — not '
              'a crop, and not a photo of a screen. It reads who said what off '
              'which side the bubbles sit on.',
              style: Type.prose(size: 14.5),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      PaperAction(
        title: 'Pick a screenshot',
        centred: true,
        tone: ActionTone.accent,
        onTap: onPick,
      ),
    ],
  );
}

class _ReadingState extends StatelessWidget {
  const _ReadingState();

  @override
  Widget build(BuildContext context) => PaperPanel(
    padding: const EdgeInsets.fromLTRB(15, 15, 15, 15),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MonoLabel('Reading the screenshot', spacing: 0.12),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: Corner.all(Corner.pill),
          child: const LinearProgressIndicator(minHeight: 4),
        ),
        const SizedBox(height: 10),
        Text(
          'Working out who said what, oldest first.',
          style: Type.prose(size: 13, color: Paper.body, height: 1.45),
        ),
      ],
    ),
  );
}

class _GeneratingState extends StatelessWidget {
  const _GeneratingState();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < 3; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        Container(
          height: 92,
          decoration: BoxDecoration(
            color: Paper.card,
            borderRadius: Corner.all(Corner.card),
            boxShadow: Paper.liftCard,
          ),
        ),
      ],
    ],
  );
}

/// What the vision model read, and the correction affordances.
class _Transcript extends StatelessWidget {
  const _Transcript({
    required this.messages,
    required this.settings,
    required this.fixing,
    required this.onToggleFixing,
    required this.onToggleSide,
    required this.onEdit,
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
                  style: Type.prose(
                    size: 12,
                    color: Paper.muted,
                    height: 1.3,
                  ),
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
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
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

class _ReplyCard extends StatelessWidget {
  const _ReplyCard({
    required this.text,
    required this.copied,
    required this.provenance,
    required this.onCopy,
  });

  final String text;
  final bool copied;
  final String provenance;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: PaperCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            text,
            style: Type.prose(size: 15.5, color: Paper.ink, height: 1.5),
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
                  onTap: onCopy,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: copied ? Paper.green : Paper.ink,
                      borderRadius: Corner.all(Corner.pill),
                    ),
                    child: Text(
                      copied ? 'Copied' : 'Copy',
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

/// Where the replies came from — and the way into reading it.
class _Provenance extends StatelessWidget {
  const _Provenance({
    required this.examples,
    required this.model,
    required this.mode,
    required this.onInspect,
  });

  final List<ScoredExchange> examples;
  final String model;
  final String mode;
  final VoidCallback onInspect;

  @override
  Widget build(BuildContext context) {
    final none = examples.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (none)
          const Notice(
            'No past exchange resembled this one. These are a general '
            "model's guesses, not your voice.",
            tone: NoticeTone.caution,
            title: 'Nothing similar in your memory',
          )
        else
          emphasised(
            'Built from *${examples.length} past '
            '${examples.length == 1 ? "exchange" : "exchanges"}* that looked '
            'like this one — closest match '
            '${examples.first.similarity.toStringAsFixed(2)}.',
            size: 12.5,
            color: Paper.tertiary,
          ),
        const SizedBox(height: 6),
        Text(
          'written by $model · $mode',
          style: Type.numeric(
            size: 12.5,
            color: Paper.muted,
            weight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 12),
        // The app showing its working: the retrieved conversations are the
        // whole reason the replies sound like the user, so they are readable.
        PaperAction(
          title: none
              ? 'See why nothing matched'
              : 'Read the ${examples.length} chats it drew on',
          subtitle: none
              ? 'What retrieval looked for'
              : 'Your real exchanges, closest first',
          tone: ActionTone.outline,
          onTap: onInspect,
        ),
      ],
    );
  }
}

/// The three refusals, each with the way out the design gives it.
class _Refusal extends StatelessWidget {
  const _Refusal({required this.error, this.onFlipAll, this.onFix});

  final Object error;
  final VoidCallback? onFlipAll;
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) {
    final message = describeFailure(error);
    final sidesLikelyBackwards = onFlipAll != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Notice(
          sidesLikelyBackwards
              ? 'The last message reads as yours, so there’s nothing to '
                    'reply to. Usually the sides came out backwards.'
              : message,
          tone: NoticeTone.failure,
        ),
        if (sidesLikelyBackwards) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: PaperAction(
                  title: 'Flip everything',
                  centred: true,
                  radius: Corner.small,
                  onTap: onFlipAll,
                ),
              ),
              if (onFix != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: PaperAction(
                    title: 'Fix the reading',
                    centred: true,
                    tone: ActionTone.outline,
                    radius: Corner.small,
                    onTap: onFix,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
