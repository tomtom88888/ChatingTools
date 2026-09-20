import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/stored_exchange.dart';
import '../services/share_intake.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/failure_text.dart';
import '../widgets/paper_ui.dart';
import 'generate_screen.dart';
import 'settings_screen.dart';
import 'train_screen.dart';

/// What the app knows, and the two things you can do about it.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  StreamSubscription<SharedExport>? _shareSubscription;

  @override
  void initState() {
    super.initState();
    // A chat export shared into the app skips this screen and opens Train.
    _shareSubscription = ShareIntake.stream().listen(
      _openTrainingFor,
      onError: (Object error) {
        if (mounted) showFailureSnackBar(context, error);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await ShareIntake.initial();
      if (initial != null && mounted) unawaited(_openTrainingFor(initial));
    });
  }

  @override
  void dispose() {
    unawaited(_shareSubscription?.cancel());
    super.dispose();
  }

  Future<void> _openTrainingFor(SharedExport export) async {
    await ShareIntake.markHandled();
    if (!mounted) return;
    await _push(TrainScreen(sharedExport: export));
  }

  void _refresh() {
    ref.invalidate(styleMemoryStatsProvider);
    ref.invalidate(styleMemoryCountProvider);
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(styleMemoryStatsProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();

    return stats.when(
      loading: () => _HomeFrame(
        onSettings: () => _push(const SettingsScreen()),
        bottom: _Actions(
          trained: false,
          count: 0,
          onTrain: () => _push(const TrainScreen()),
          onGenerate: null,
        ),
        children: const [_LoadingSkeleton()],
      ),
      error: (error, _) => _HomeFrame(
        onSettings: () => _push(const SettingsScreen()),
        bottom: _Actions(
          trained: false,
          count: 0,
          onTrain: () => _push(const TrainScreen()),
          onGenerate: null,
          trainTitle: 'Rebuild from an export',
        ),
        children: [
          Notice(
            "Couldn't open the memory stored on this phone. Your key is fine. "
            'Re-importing your export rebuilds it.',
            tone: NoticeTone.failure,
            title: 'Memory unreadable',
            actionLabel: 'Try again',
            onAction: _refresh,
          ),
        ],
      ),
      data: (value) {
        final trained = value != null && !value.isEmpty;
        return _HomeFrame(
          onSettings: () => _push(const SettingsScreen()),
          bottom: _Actions(
            trained: trained,
            count: value?.exchangeCount ?? 0,
            onTrain: () => _push(const TrainScreen()),
            onGenerate: trained ? () => _push(const GenerateScreen()) : null,
          ),
          children: trained
              ? [
                  _KnowsYou(stats: value),
                  _MemoryDetails(stats: value),
                  if (settings.mode == TrainingMode.fineTune &&
                      !settings.hasFineTunedModel)
                    _FineTuneMismatch(
                      onFix: () => _push(const SettingsScreen()),
                    ),
                ]
              : const [_DoesNotKnowYou()],
        );
      },
    );
  }
}

/// The shared chrome: the wordmark and the settings button.
class _HomeFrame extends StatelessWidget {
  const _HomeFrame({
    required this.children,
    required this.bottom,
    required this.onSettings,
  });

  final List<Widget> children;
  final Widget bottom;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => PaperScreen(
    bottom: bottom,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(child: MonoLabel('ReplyLikeMe')),
          GestureDetector(
            onTap: onSettings,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Paper.panel,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.settings_outlined,
                size: 18,
                color: Paper.secondary,
              ),
            ),
          ),
        ],
      ),
      ...children,
    ],
  );
}

/// The hero: who it knows, and how many of your replies it read.
class _KnowsYou extends StatelessWidget {
  const _KnowsYou({required this.stats});

  final StyleMemoryStats stats;

  @override
  Widget build(BuildContext context) => InkCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'It knows how you write to',
          style: Type.prose(size: 15, color: const Color(0x9EFAF7F0), height: 1.3),
        ),
        const SizedBox(height: 6),
        Text(
          stats.theirName.isEmpty ? 'them' : stats.theirName,
          style: Type.display(40, color: Paper.onInk),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              _grouped(stats.exchangeCount),
              style: Type.numeric(size: 30, color: Paper.amber),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'of your replies learned',
                style: Type.prose(size: 14, color: const Color(0x9EFAF7F0)),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Thousands separators, so a five-figure count reads at a glance.
String _grouped(int value) {
  final digits = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

class _MemoryDetails extends StatelessWidget {
  const _MemoryDetails({required this.stats});

  final StyleMemoryStats stats;

  @override
  Widget build(BuildContext context) => PaperCard(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Column(
      // Without this the rows shrink to their content and centre themselves,
      // taking the dividers with them; the design runs both full width.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StackedRow(
          label: 'Learning from',
          valueChild: NamePairValue(
            me: stats.myName.isEmpty ? 'you' : stats.myName,
            them: stats.theirName.isEmpty ? 'them' : stats.theirName,
          ),
        ),
        StackedRow(
          label: 'Fingerprints',
          value: '${stats.embeddingModel} · ${stats.dimensions}',
          mono: true,
        ),
        StackedRow(
          label: 'Built',
          value: _when(stats.builtAt),
          last: true,
        ),
      ],
    ),
  );

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _when(DateTime at) {
    final hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final suffix = at.hour < 12 ? 'am' : 'pm';
    final minute = at.minute.toString().padLeft(2, '0');
    return '${at.day} ${_months[at.month - 1]}, $hour12:$minute $suffix';
  }
}

class _FineTuneMismatch extends StatelessWidget {
  const _FineTuneMismatch({required this.onFix});

  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) => PaperPanel(
    color: Paper.warnPanel,
    padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 11),
          child: Text(
            '!',
            style: TextStyle(fontSize: 15, height: 1.2, color: Paper.accent),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              emphasised(
                'You picked *fine-tuned* mode, but no fine-tuned model is '
                'saved — so style memory is doing the work.',
                size: 13.5,
                color: Paper.warnText,
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: onFix,
                child: Text(
                  'Fix in Settings',
                  style: Type.strong(size: 13, color: Paper.accent).copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: Paper.accent.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The untrained state: what will happen, in three lines.
class _DoesNotKnowYou extends StatelessWidget {
  const _DoesNotKnowYou();

  static const List<String> _steps = [
    'Export the chat from WhatsApp — the app shows you exactly how.',
    'Say which name is you. Only your replies get learned.',
    'A minute or two of building. Costs well under a cent.',
  ];

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
            const SerifTitle("It doesn't know you yet.", size: 34),
            const SizedBox(height: 10),
            Text(
              'Import one exported WhatsApp conversation and it will read '
              'every reply you sent in it — how long, how punctuated, how '
              'you open and sign off — and keep that here on the phone.',
              style: Type.prose(size: 14.5),
            ),
          ],
        ),
      ),
      const SizedBox(height: Frame.gap),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            for (var i = 0; i < _steps.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '0${i + 1}',
                      style: Type.numeric(size: 12, color: Paper.accent),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _steps[i],
                      style: Type.prose(
                        size: 14,
                        color: Paper.body,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

/// Skeletons while the local store is read. The actions stay tappable.
class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        height: 150,
        decoration: BoxDecoration(
          color: Paper.panel,
          borderRadius: Corner.all(Corner.hero),
        ),
      ),
      const SizedBox(height: Frame.gap),
      Container(
        height: 132,
        decoration: BoxDecoration(
          color: Paper.panel,
          borderRadius: Corner.all(Corner.card),
        ),
      ),
    ],
  );
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.trained,
    required this.count,
    required this.onTrain,
    required this.onGenerate,
    this.trainTitle,
  });

  final bool trained;
  final int count;
  final VoidCallback onTrain;
  final VoidCallback? onGenerate;
  final String? trainTitle;

  @override
  Widget build(BuildContext context) {
    final write = PaperAction(
      title: 'Write a reply',
      subtitle: trained
          ? 'From a screenshot of your chat'
          : 'Nothing learned yet — teach it first',
      tone: ActionTone.accent,
      onTap: onGenerate,
      trailing: trained
          ? null
          : const Icon(Icons.lock_outline, size: 16, color: Paper.tertiary),
    );
    final train = PaperAction(
      title: trainTitle ?? (trained ? 'Refresh the memory' : 'Teach it your voice'),
      subtitle: trained
          ? 'Import a newer export · replaces all ${_grouped(count)}'
          : 'Import a WhatsApp export',
      tone: trained ? ActionTone.outline : ActionTone.ink,
      onTap: onTrain,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Trained: writing is the everyday act, so it leads. Untrained: there
        // is nothing to write from, so teaching leads.
        if (trained) ...[write, const SizedBox(height: 11), train] else ...[
          train,
          const SizedBox(height: 11),
          write,
        ],
        const SizedBox(height: 15),
        const Footnote('Your chat history never leaves this phone.'),
      ],
    );
  }
}
