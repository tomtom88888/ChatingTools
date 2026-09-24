import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/exchange.dart';
import '../models/parsed_chat.dart';
import '../models/stored_exchange.dart';
import '../models/style_profile.dart';
import '../services/chat_export_reader.dart';
import '../services/pricing.dart';
import '../services/share_intake.dart';
import '../services/style_memory_service.dart';
import '../services/whatsapp_parser.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/failure_text.dart';
import '../widgets/format.dart';
import '../widgets/paper_ui.dart';
import 'finetune_screen.dart';

/// Which of the four jobs the screen is on.
enum _Step {
  /// Get the export out of WhatsApp.
  export,

  /// Read it, and say who is who.
  read,

  /// Build, and report the outcome.
  build,
}

/// Import an export, declare who you are, and build the style memory.
class TrainScreen extends ConsumerStatefulWidget {
  const TrainScreen({this.sharedExport, super.key});

  /// Set when the app was opened through the share sheet.
  final SharedExport? sharedExport;

  @override
  ConsumerState<TrainScreen> createState() => _TrainScreenState();
}

class _TrainScreenState extends ConsumerState<TrainScreen> {
  _Step _step = _Step.export;

  ParsedChat? _chat;
  String? _sourceName;
  String? _myName;
  String? _theirName;
  List<Exchange> _exchanges = const [];

  /// What building would do with [_exchanges]: which are new, and whether it
  /// adds to a chat already learned. Worked out whenever the names change.
  ImportPlan? _plan;
  int _planGeneration = 0;

  bool _reading = false;
  bool _cancelRequested = false;
  StyleMemoryProgress? _progress;
  Object? _error;
  ChatMemory? _built;
  int? _addedCount;

  @override
  void initState() {
    super.initState();
    final shared = widget.sharedExport;
    if (shared != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadFile(File(shared.path), shared.name),
      );
    }
  }

  Future<void> _pickFile() async {
    setState(() => _error = null);
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Pick a WhatsApp chat export',
        type: FileType.custom,
        allowedExtensions: const ['txt', 'zip'],
      );
      if (picked == null) return;
      await _loadBytes(await picked.xFile.readAsBytes(), picked.name);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _loadFile(File file, String name) async {
    try {
      await _loadBytes(await file.readAsBytes(), name);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _loadBytes(List<int> bytes, String name) async {
    setState(() {
      _reading = true;
      _error = null;
      _built = null;
      _addedCount = null;
    });
    try {
      final text = ChatExportReader.read(bytes, filename: name);
      final chat = WhatsAppParser.parse(text);

      if (chat.format == ExportFormat.unknown) {
        throw const ChatExportException(
          "This doesn't have WhatsApp's date-and-name lines. Did another app "
          'make it?',
        );
      }
      if (chat.senders.length < 2) {
        final only = chat.senders.isEmpty ? 'one person' : chat.senders.first;
        throw ChatExportException(
          'Every line here is from $only. An export with no one replying '
          "can't teach it to reply.",
        );
      }

      final settings = await ref.read(settingsProvider.future);
      final senders = chat.senders;
      final mine = senders.contains(settings.myName)
          ? settings.myName
          : senders.first;
      final theirs =
          senders.contains(settings.theirName) && settings.theirName != mine
          ? settings.theirName
          : senders.firstWhere((s) => s != mine, orElse: () => senders.last);
      setState(() {
        _chat = chat;
        _sourceName = name;
        _myName = mine;
        _theirName = theirs;
        _step = _Step.read;
      });
      _recomputeExchanges();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  /// Exchanges follow from the export and the chosen name, so they are
  /// recomputed when either changes rather than on every rebuild.
  void _recomputeExchanges() {
    if (!mounted) return;
    final chat = _chat;
    final me = _myName;
    if (chat == null || me == null) {
      setState(() => _exchanges = const []);
      return;
    }
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    setState(() {
      _exchanges = WhatsAppParser.buildExchanges(
        chat.turns,
        me: me,
        maxContextTurns: settings.contextTurns,
      );
      _plan = null;
    });
    unawaited(_replan());
  }

  /// Checks the export against what is already stored, so the cost shown is
  /// only for replies not learned before.
  Future<void> _replan() async {
    final service = ref.read(styleMemoryServiceProvider);
    final me = _myName;
    final them = _theirName;
    if (service == null || me == null || them == null) return;
    final generation = ++_planGeneration;
    try {
      final settings = await ref.read(settingsProvider.future);
      final plan = await service.plan(
        exchanges: _exchanges,
        myName: me,
        theirName: them,
        embeddingModel: settings.embeddingModel,
        dimensions: settings.embeddingDimensions,
      );
      // A newer swap may have landed while this one was reading.
      if (mounted && generation == _planGeneration) {
        setState(() => _plan = plan);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _swapNames() {
    setState(() {
      final was = _myName;
      _myName = _theirName;
      _theirName = was;
    });
    _recomputeExchanges();
  }

  Future<void> _build() async {
    final service = ref.read(styleMemoryServiceProvider);
    final me = _myName;
    final them = _theirName;
    if (service == null || me == null || them == null) return;

    final settings = await ref.read(settingsProvider.future);
    final chat = _chat;
    final plan = _plan;

    setState(() {
      _step = _Step.build;
      _cancelRequested = false;
      _error = null;
      _progress = null;
    });

    try {
      final built = await service.build(
        exchanges: _exchanges,
        myName: me,
        theirName: them,
        embeddingModel: settings.embeddingModel,
        dimensions: settings.embeddingDimensions,
        profile: chat == null
            ? StyleProfile.empty
            : StyleProfile.measure(chat.turns, me: me),
        importPlan: plan,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        isCancelled: () => _cancelRequested,
      );

      // Remember who is who, so generating and fine-tuning agree with training.
      await ref
          .read(settingsProvider.notifier)
          .edit((current) => current.copyWith(myName: me, theirName: them));
      await ref.read(chatsProvider.notifier).reload();

      if (mounted) {
        setState(() {
          _built = built;
          _addedCount = plan?.toEmbed.length;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _step = _Step.read;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _progress = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) => switch (_step) {
    _Step.export => _exportStep(),
    _Step.read => _readStep(),
    _Step.build => _buildStep(),
  };

  // ------------------------------------------------------------------ step 1

  Widget _exportStep() {
    final them = ref.watch(settingsProvider).value?.theirName ?? '';
    final who = them.isEmpty ? 'the person' : them;

    return PaperScreen(
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaperAction(
            title: _reading ? 'Reading it…' : 'Choose the exported file',
            centred: true,
            busy: _reading,
            onTap: _reading ? null : _pickFile,
          ),
          const SizedBox(height: 11),
          const Footnote(
            'A .txt, or the .zip WhatsApp makes if media slipped in.',
          ),
        ],
      ),
      children: [
        StepRail(step: 1, total: 4, onBack: () => Navigator.of(context).pop()),
        if (_error != null) FailureNotice(error: _error!),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SerifTitle('Get the chat out of WhatsApp'),
            const SizedBox(height: 9),
            Text(
              'WhatsApp can hand you a plain text file of one conversation. '
              "It's buried, so here it is exactly:",
              style: Type.prose(size: 14.5),
            ),
          ],
        ),
        NumberedSteps([
          'Open the chat with *${bidiIsolate(who)}* in WhatsApp.',
          'Tap their *name* at the top.',
          'Scroll right to the bottom of that page.',
          'Tap *Export chat*.',
          'Choose *Without Media* — photos carry no style, and the file '
              'stays small.',
        ]),
        PaperPanel(
          child: Text(
            "Share it straight to ReplyLikeMe from that menu and you'll land "
            'on the next step automatically.',
            style: Type.prose(size: 13, color: Paper.body, height: 1.45),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- steps 2-3

  Widget _readStep() {
    final chat = _chat!;
    final plan = _plan;
    final estimate = plan?.estimate;
    final noQualifying = _exchanges.isEmpty;
    final them = bidiIsolate(_theirName ?? 'them');
    final footnote = plan == null
        ? 'Checking what it already knows…'
        : plan.isNewChat
        ? 'Adds $them as a new chat. Your other chats are not touched.'
        : plan.replacesExisting
        ? 'Rebuilds $them from scratch: it was fingerprinted with a '
              'different model. Only once it finishes.'
        : 'Adds to what it knows about $them. Nothing is replaced.';
    final layout = switch (chat.format) {
      ExportFormat.android => 'Android export',
      ExportFormat.ios => 'iOS export',
      ExportFormat.unknown => 'unrecognised layout',
    };

    return PaperScreen(
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (noQualifying)
            Notice(
              'Nothing to learn from. This nearly always means the wrong '
              'name is set as you. Swap ${bidiIsolate(_myName ?? "them")} '
              'and ${bidiIsolate(_theirName ?? "you")}?',
              tone: NoticeTone.caution,
              actionLabel: 'Swap them',
              onAction: _swapNames,
            )
          else
            PaperPanel(
              child: Column(
                children: [
                  FigureRow(
                    'Your replies that qualify',
                    grouped(_exchanges.length),
                    emphasis: plan == null || plan.alreadyKnown == 0,
                  ),
                  if (plan != null && plan.alreadyKnown > 0) ...[
                    FigureRow(
                      'Already learned · skipped',
                      grouped(plan.alreadyKnown),
                    ),
                    FigureRow(
                      'New to learn',
                      grouped(plan.toEmbed.length),
                      emphasis: true,
                    ),
                  ],
                  if (estimate != null)
                    FigureRow(
                      'Estimated cost',
                      '~${compactTokens(estimate.estimatedTokens)} tokens · '
                          '≈ ${Pricing.formatUsd(estimate.estimatedUsd)}',
                    ),
                  const SizedBox(height: 3),
                  Text(
                    'An estimate, not a quote. A reply only counts if '
                    'something came before it.',
                    style: Type.prose(
                      size: 12,
                      color: Paper.muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 11),
          PaperAction(
            title: plan != null && !plan.isNewChat && !plan.replacesExisting
                ? 'Add to the memory'
                : 'Build the memory',
            centred: true,
            tone: ActionTone.accent,
            onTap: noQualifying || plan == null ? null : _build,
          ),
          const SizedBox(height: 11),
          Footnote(footnote),
        ],
      ),
      children: [
        StepRail(
          step: 3,
          total: 4,
          onBack: () => setState(() => _step = _Step.export),
        ),
        if (_error != null) FailureNotice(error: _error!),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SerifTitle(
              'Read it. Does this look like your chat?',
              size: 30,
            ),
            const SizedBox(height: 7),
            Text(
              '${_sourceName ?? "export"} · $layout',
              style: Type.numeric(
                size: 13,
                color: Paper.muted,
                weight: FontWeight.w400,
              ),
            ),
          ],
        ),
        _ReadSummary(chat: chat, myName: _myName!, theirName: _theirName!),
        _WhoIsWho(
          senders: chat.senders,
          myName: _myName!,
          theirName: _theirName!,
          onPick: (mine) {
            setState(() {
              _myName = mine;
              _theirName = chat.senders.firstWhere(
                (s) => s != mine,
                orElse: () => mine,
              );
            });
            _recomputeExchanges();
          },
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ step 4

  Widget _buildStep() {
    final done = _built;

    return PaperScreen(
      bottom: done == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperAction(
                  title: 'Done',
                  centred: true,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: 11),
                PaperAction(
                  title: 'Want a private fine-tuned model?',
                  subtitle:
                      'Costs real money and takes hours — most people '
                      'never need it.',
                  tone: ActionTone.outline,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const FineTuneScreen(),
                    ),
                  ),
                ),
              ],
            ),
      children: [
        StepRail(step: 4, total: 4),
        if (done == null)
          _BuildingCard(
            progress: _progress,
            total: _plan?.toEmbed.length ?? _exchanges.length,
            onCancel: () => setState(() => _cancelRequested = true),
          )
        else
          _BuiltCard(
            added: _addedCount ?? done.exchangeCount,
            total: done.exchangeCount,
            theirName: done.theirName.isEmpty ? 'them' : done.theirName,
          ),
      ],
    );
  }
}

/// What the parser understood, so the user can recognise their own chat.
class _ReadSummary extends StatelessWidget {
  const _ReadSummary({
    required this.chat,
    required this.myName,
    required this.theirName,
  });

  final ParsedChat chat;
  final String myName;
  final String theirName;

  @override
  Widget build(BuildContext context) => PaperCard(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: _Figure(
                value: grouped(chat.textMessageCount),
                label: 'messages',
              ),
            ),
            const SizedBox(width: 26),
            Flexible(
              child: _Figure(value: grouped(chat.turns.length), label: 'turns'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Paper.dividerFirm)),
          ),
          child: Column(
            children: [
              for (final entry in chat.senderMessageCounts.entries)
                FigureRow('${entry.key} sent', grouped(entry.value)),
              FigureRow(
                'Set aside · photos, deleted, system notices',
                grouped(chat.mediaCount + chat.deletedCount + chat.systemCount),
              ),
              FigureRow(
                "Lines it couldn't read",
                grouped(chat.unparsedLineCount),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: Type.numeric(size: 26)),
      const SizedBox(height: 2),
      Text(
        label,
        style: Type.prose(size: 12, color: Paper.tertiary, height: 1.3),
      ),
    ],
  );
}

/// The identity choice, weighted as heavily as the design does.
class _WhoIsWho extends StatelessWidget {
  const _WhoIsWho({
    required this.senders,
    required this.myName,
    required this.theirName,
    required this.onPick,
  });

  final List<String> senders;
  final String myName;
  final String theirName;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Which one is you?', style: Type.strong(size: 13, height: 1.35)),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _NameChoice(
              role: 'ME',
              name: myName,
              selected: true,
              onTap: null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _NameChoice(
              role: 'THEM',
              name: theirName,
              selected: false,
              onTap: () => onPick(theirName),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      emphasised(
        'Only *${bidiIsolate(myName)}*’s replies get learned. Pick the '
        'wrong one and it will imitate ${bidiIsolate(theirName)} convincingly '
        '— and nothing will warn you.',
        size: 13,
        color: Paper.secondary,
      ),
    ],
  );
}

class _NameChoice extends StatelessWidget {
  const _NameChoice({
    required this.role,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String role;
  final String name;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? Paper.ink : Paper.card,
        borderRadius: Corner.all(Corner.choice),
        border: selected ? null : Border.all(color: Paper.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            role,
            style: TextStyle(
              fontFamily: Fonts.sans,
              fontSize: 11,
              height: 1.3,
              letterSpacing: 1.1,
              color: selected ? const Color(0x99FAF7F0) : Paper.muted,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Type.strong(
              size: 17,
              color: selected ? Paper.onInk : Paper.ink,
            ),
          ),
        ],
      ),
    ),
  );
}

class _BuildingCard extends StatelessWidget {
  const _BuildingCard({
    required this.progress,
    required this.total,
    required this.onCancel,
  });

  final StyleMemoryProgress? progress;
  final int total;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final done = progress?.embedded ?? 0;
    final of = progress?.total ?? total;
    return InkCard(
      radius: Corner.card,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Building your memory',
                  style: Type.strong(size: 15, color: Paper.onInk, height: 1.3),
                ),
              ),
              Text(
                '${grouped(done)} / ${grouped(of)}',
                style: Type.numeric(size: 13, color: Paper.amber),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: Corner.all(Corner.pill),
            child: LinearProgressIndicator(
              value: progress?.fraction,
              minHeight: 6,
              backgroundColor: const Color(0x26FAF7F0),
              color: Paper.amber,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            progress?.stage ?? 'Starting',
            style: Type.prose(
              size: 13,
              color: const Color(0xA6FAF7F0),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onCancel,
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                borderRadius: Corner.all(Corner.small),
                border: Border.all(color: const Color(0x40FAF7F0), width: 1.5),
              ),
              child: Center(
                child: Text(
                  'Cancel',
                  style: Type.strong(size: 14, color: Paper.onInk),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Cancel and your current memory stays exactly as it is. Nothing '
            'is replaced until the build finishes.',
            style: Type.prose(
              size: 12,
              color: const Color(0x80FAF7F0),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _BuiltCard extends StatelessWidget {
  const _BuiltCard({
    required this.added,
    required this.total,
    required this.theirName,
  });

  final int added;
  final int total;
  final String theirName;

  @override
  Widget build(BuildContext context) => PaperPanel(
    color: Paper.greenPanel,
    radius: Corner.action,
    padding: const EdgeInsets.all(15),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          added == 0
              ? 'Nothing new — it was up to date.'
              : '${grouped(added)} replies learned.',
          style: Type.display(22, color: Paper.green),
        ),
        const SizedBox(height: 6),
        Text(
          'It knows ${grouped(total)} of the ways you write to '
          '${bidiIsolate(theirName)}, and the chat is ticked on the home '
          "screen. Screenshot a chat and it'll take it from there.",
          style: Type.prose(size: 13, color: Paper.greenText, height: 1.45),
        ),
      ],
    ),
  );
}
