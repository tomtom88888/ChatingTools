import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/stored_exchange.dart';
import '../services/share_intake.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/failure_text.dart';
import '../widgets/format.dart';
import '../widgets/paper_dialog.dart';
import '../widgets/paper_ui.dart';
import 'generate_screen.dart';
import 'settings_screen.dart';
import 'style_report_screen.dart';
import 'train_screen.dart';

/// What the app knows, which of it to use, and the things you can do.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  StreamSubscription<SharedItem>? _shareSubscription;

  @override
  void initState() {
    super.initState();
    // Something shared into the app skips this screen: an export opens Train,
    // a screenshot opens Generate with it already picked.
    _shareSubscription = ShareIntake.stream().listen(
      _openShared,
      onError: (Object error) {
        if (mounted) showFailureSnackBar(context, error);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await ShareIntake.initial();
      if (initial != null && mounted) unawaited(_openShared(initial));
    });
  }

  @override
  void dispose() {
    unawaited(_shareSubscription?.cancel());
    super.dispose();
  }

  Future<void> _openShared(SharedItem item) async {
    await ShareIntake.markHandled();
    if (!mounted) return;
    switch (item) {
      case SharedExport():
        await _push(TrainScreen(sharedExport: item));
      case SharedScreenshot():
        await _push(GenerateScreen(sharedScreenshot: item));
    }
  }

  void _refresh() {
    ref.invalidate(chatsProvider);
    ref.invalidate(feedbackProvider);
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) _refresh();
  }

  Future<void> _confirmDelete(ChatMemory chat) async {
    final name = chat.theirName.isEmpty ? 'this chat' : chat.theirName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => PaperDialog(
        title: 'Forget ${bidiIsolate(name)}?',
        confirmLabel: 'Forget it',
        destructive: true,
        onConfirm: () => Navigator.of(context).pop(true),
        child: Text(
          'Removes the ${grouped(chat.exchangeCount)} replies learned from '
          'this chat. Your other chats stay as they are. Importing the export '
          'again brings it back.',
          style: Type.prose(size: 14, color: Paper.body),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(chatsProvider.notifier).delete(chat.id);
    } on Object catch (error) {
      if (mounted) showFailureSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatsProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();

    void openSettings() => _push(const SettingsScreen());
    void openTrain() => _push(const TrainScreen());

    return chats.when(
      loading: () => _HomeFrame(
        onSettings: openSettings,
        bottom: _Actions(
          trained: false,
          anyEnabled: false,
          onTrain: openTrain,
          onGenerate: null,
        ),
        children: const [_LoadingSkeleton()],
      ),
      error: (error, _) => _HomeFrame(
        onSettings: openSettings,
        bottom: _Actions(
          trained: false,
          anyEnabled: false,
          onTrain: openTrain,
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
      data: (all) {
        final learned = all.where((c) => !c.isEmpty).toList();
        final enabled = learned.where((c) => c.enabled).toList();
        final trained = learned.isNotEmpty;
        final stale = enabled
            .where(
              (c) => !c.matches(
                settings.embeddingModel,
                settings.embeddingDimensions,
              ),
            )
            .toList();
        return _HomeFrame(
          onSettings: openSettings,
          bottom: _Actions(
            trained: trained,
            anyEnabled: enabled.isNotEmpty,
            onTrain: openTrain,
            onGenerate: enabled.isNotEmpty
                ? () => _push(const GenerateScreen())
                : null,
          ),
          children: trained
              ? [
                  _KnowsYou(enabled: enabled),
                  _ChatList(
                    chats: learned,
                    onToggle: (chat, on) => ref
                        .read(chatsProvider.notifier)
                        .setEnabled(chat.id, enabled: on),
                    onDelete: _confirmDelete,
                  ),
                  if (stale.isNotEmpty)
                    Notice(
                      '${nameList([for (final c in stale) c.theirName])} '
                      '${stale.length == 1 ? "was" : "were"} built with a '
                      'different fingerprint model or size than Settings now '
                      'uses, so ${stale.length == 1 ? "it is" : "they are"} '
                      'skipped when writing. Import the export again to '
                      'rebuild.',
                      tone: NoticeTone.caution,
                      title: 'Needs rebuilding',
                    ),
                  _MemoryDetails(chats: enabled.isEmpty ? learned : enabled),
                  PaperAction(
                    title: 'Your style report',
                    subtitle: 'How you text, chat by chat — no API calls',
                    tone: ActionTone.outline,
                    onTap: () => _push(const StyleReportScreen()),
                  ),
                  if (settings.mode == TrainingMode.fineTune &&
                      !settings.hasFineTunedModel)
                    _FineTuneMismatch(onFix: openSettings),
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

/// The hero: whose chats replies are drawn from, and how many of your replies
/// that is.
class _KnowsYou extends StatelessWidget {
  const _KnowsYou({required this.enabled});

  final List<ChatMemory> enabled;

  @override
  Widget build(BuildContext context) {
    final count = enabled.fold(0, (sum, c) => sum + c.exchangeCount);
    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            enabled.isEmpty
                ? 'Tick a chat below to write from it'
                : 'It knows how you write to',
            style: Type.prose(
              size: 15,
              color: const Color(0x9EFAF7F0),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            enabled.isEmpty
                ? 'no one, for now'
                : nameList([for (final c in enabled) c.theirName]),
            style: Type.display(40, color: Paper.onInk),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                grouped(count),
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
}

/// Every learned chat, each with a tick box: ticked chats are the ones
/// replies are written from.
class _ChatList extends StatelessWidget {
  const _ChatList({
    required this.chats,
    required this.onToggle,
    required this.onDelete,
  });

  final List<ChatMemory> chats;
  final void Function(ChatMemory chat, bool enabled) onToggle;
  final ValueChanged<ChatMemory> onDelete;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(child: MonoLabel('Chats it writes from')),
          Text(
            '${chats.where((c) => c.enabled).length} of ${chats.length} on',
            style: Type.numeric(
              size: 11.5,
              color: Paper.muted,
              weight: FontWeight.w400,
            ),
          ),
        ],
      ),
      const SizedBox(height: 9),
      PaperCard(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < chats.length; i++)
              _ChatRow(
                chat: chats[i],
                last: i == chats.length - 1,
                onToggle: (on) => onToggle(chats[i], on),
                onDelete: () => onDelete(chats[i]),
              ),
          ],
        ),
      ),
      const SizedBox(height: 7),
      Text(
        'How you text a partner is not how you text your boss. Tick only the '
        'chats that sound like the reply you want.',
        style: Type.prose(size: 12.5, color: Paper.muted, height: 1.4),
      ),
    ],
  );
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.chat,
    required this.last,
    required this.onToggle,
    required this.onDelete,
  });

  final ChatMemory chat;
  final bool last;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final saved = chat.savedCount > 0 ? ' · ${chat.savedCount} starred' : '';
    return InkWell(
      key: ValueKey('chat-${chat.id}'),
      onTap: () => onToggle(!chat.enabled),
      borderRadius: Corner.all(Corner.small),
      child: Container(
        padding: const EdgeInsets.fromLTRB(2, 8, 0, 8),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: Paper.divider)),
        ),
        child: Row(
          children: [
            Checkbox(
              value: chat.enabled,
              onChanged: (on) => onToggle(on ?? false),
              activeColor: Paper.ink,
              checkColor: Paper.onInk,
              side: const BorderSide(color: Paper.placeholder, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: Corner.all(const Radius.circular(5)),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.theirName.isEmpty ? 'Unnamed chat' : chat.theirName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.strong(
                      size: 15,
                      height: 1.3,
                      color: chat.enabled ? Paper.ink : Paper.tertiary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${grouped(chat.exchangeCount)} replies$saved · '
                    '${dayMonth(chat.builtAt)}',
                    style: Type.numeric(
                      size: 11.5,
                      color: Paper.muted,
                      weight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              color: Paper.bg,
              icon: const Icon(
                Icons.more_horiz,
                size: 20,
                color: Paper.tertiary,
              ),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Forget this chat',
                    style: Type.strong(size: 14, color: Paper.errorText),
                  ),
                ),
              ],
              onSelected: (_) => onDelete(),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryDetails extends StatelessWidget {
  const _MemoryDetails({required this.chats});

  final List<ChatMemory> chats;

  @override
  Widget build(BuildContext context) {
    final newest = chats.reduce((a, b) => a.builtAt.isAfter(b.builtAt) ? a : b);
    final me = chats
        .map((c) => c.myName)
        .firstWhere((n) => n.isNotEmpty, orElse: () => 'you');
    final models = {
      for (final c in chats) '${c.embeddingModel} · ${c.dimensions}',
    };
    return PaperCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        // Without this the rows shrink to their content and centre themselves,
        // taking the dividers with them; the design runs both full width.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StackedRow(
            label: 'Learning from',
            valueChild: NamePairValue(
              me: me,
              them: nameList([for (final c in chats) c.theirName]),
            ),
          ),
          StackedRow(
            label: 'Fingerprints',
            value: models.join('\n'),
            mono: true,
          ),
          StackedRow(
            label: chats.length == 1 ? 'Built' : 'Last built',
            value: dayMonthTime(newest.builtAt),
            last: true,
          ),
        ],
      ),
    );
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
    required this.anyEnabled,
    required this.onTrain,
    required this.onGenerate,
    this.trainTitle,
  });

  final bool trained;
  final bool anyEnabled;
  final VoidCallback onTrain;
  final VoidCallback? onGenerate;
  final String? trainTitle;

  @override
  Widget build(BuildContext context) {
    final locked = !trained || !anyEnabled;
    final write = PaperAction(
      title: 'Write a reply',
      subtitle: !trained
          ? 'Nothing learned yet — teach it first'
          : anyEnabled
          ? 'From a screenshot or pasted chat'
          : 'Tick at least one chat above',
      tone: ActionTone.accent,
      onTap: onGenerate,
      trailing: locked
          ? const Icon(Icons.lock_outline, size: 16, color: Paper.tertiary)
          : null,
    );
    final train = PaperAction(
      title:
          trainTitle ??
          (trained ? 'Add or refresh a chat' : 'Teach it your voice'),
      subtitle: trained
          ? 'Import an export · only new replies are sent'
          : 'Import a WhatsApp export',
      tone: trained ? ActionTone.outline : ActionTone.ink,
      onTap: onTrain,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Trained: writing is the everyday act, so it leads. Untrained: there
        // is nothing to write from, so teaching leads.
        if (trained) ...[
          write,
          const SizedBox(height: 11),
          train,
        ] else ...[
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
