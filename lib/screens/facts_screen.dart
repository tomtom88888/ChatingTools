import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/stored_exchange.dart';
import '../services/chat_facts.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/failure_text.dart';
import '../widgets/format.dart';
import '../widgets/paper_ui.dart';

/// Things the other person has told you, pulled out of the chat so replies
/// can call back to them: the dog's name, the exam on Friday.
class FactsScreen extends ConsumerStatefulWidget {
  const FactsScreen({super.key});

  @override
  ConsumerState<FactsScreen> createState() => _FactsScreenState();
}

class _FactsScreenState extends ConsumerState<FactsScreen> {
  int? _chatId;
  Map<int, SavedFacts> _saved = const {};
  bool _loading = true;
  bool _busy = false;
  (int, int)? _progress;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await ref.read(factsStoreProvider).load();
      if (mounted) setState(() => _saved = saved);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _them(ChatMemory chat) =>
      chat.theirName.isEmpty ? 'them' : chat.theirName;

  Future<void> _find(ChatMemory chat) async {
    final finder = ref.read(chatFactsProvider);
    if (finder == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    try {
      final settings = await ref.read(settingsProvider.future);
      final exchanges = await ref
          .read(exchangeStoreProvider)
          .all(chatIds: {chat.id});
      final facts = await finder.find(
        exchanges,
        myName: chat.myName,
        them: chat.theirName,
        model: settings.generationModel,
        group: chat.isGroup,
        onProgress: (done, of) {
          if (mounted) setState(() => _progress = (done, of));
        },
      );
      final saved = SavedFacts(at: DateTime.now(), facts: facts);
      await ref.read(factsStoreProvider).save(chat.id, saved);
      if (mounted) setState(() => _saved = {..._saved, chat.id: saved});
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _forget(ChatMemory chat, ChatFact fact) async {
    final current = _saved[chat.id];
    if (current == null) return;
    final next = current.without(fact);
    setState(() => _saved = {..._saved, chat.id: next});
    await ref.read(factsStoreProvider).save(chat.id, next);
  }

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatsProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final hasKey = ref.watch(chatFactsProvider) != null;

    return PaperScreen(
      children: [
        Row(
          children: [
            BackArrow(onTap: () => Navigator.of(context).pop()),
            const SizedBox(width: 10),
            const MonoLabel('Remember'),
          ],
        ),
        ...chats.when(
          loading: () => [const LinearProgressIndicator(minHeight: 3)],
          error: (error, _) => [FailureNotice(error: error)],
          data: (all) {
            final learned = [
              for (final c in all)
                if (!c.isEmpty) c,
            ];
            if (learned.isEmpty) {
              return const [
                SerifTitle('Nothing to remember yet.', size: 34),
                Notice('Import a chat export first.', tone: NoticeTone.caution),
              ];
            }
            final chat = learned.firstWhere(
              (c) => c.id == _chatId,
              orElse: () => learned.first,
            );
            final them = _them(chat);
            final saved = _saved[chat.id];
            return [
              SerifTitle(
                'What to remember about ',
                accent: bidiIsolate(them),
                trailing: '.',
                size: 32,
              ),
              if (learned.length > 1)
                _ChatPills(
                  chats: learned,
                  selected: chat.id,
                  onPick: _busy
                      ? null
                      : (id) => setState(() {
                          _chatId = id;
                          _error = null;
                        }),
                ),
              Text(
                'Reads what ${bidiIsolate(them)} wrote and picks out things '
                'worth bringing up later: what they like, the people in their '
                'life, plans coming up. When you write to '
                '${bidiIsolate(them)}, a reply can call back to one when it '
                'fits.',
                style: Type.prose(size: 14, color: Paper.body, height: 1.45),
              ),
              if (_loading) const LinearProgressIndicator(minHeight: 3),
              if (_busy) _Progress(progress: _progress),
              if (!_busy)
                PaperAction(
                  title: saved == null
                      ? 'Find things to remember'
                      : 'Look through the chat again',
                  subtitle: hasKey
                      ? 'Sends what ${bidiIsolate(them)} wrote to '
                            '${settings.generationModel}'
                      : 'Add your OpenAI key in Settings first',
                  tone: saved == null ? ActionTone.accent : ActionTone.outline,
                  onTap: hasKey ? () => _find(chat) : null,
                ),
              if (_error != null)
                FailureNotice(error: _error!, onRetry: () => _find(chat)),
              if (saved != null && saved.facts.isEmpty)
                Notice(
                  'Nothing stood out in what ${bidiIsolate(them)} wrote. A '
                  'longer export may have more.',
                ),
              if (saved != null && saved.facts.isNotEmpty) ...[
                Text(
                  'Found on ${dayMonthTime(saved.at)}. Tap × on anything wrong '
                  'and it won’t be used.',
                  style: Type.prose(size: 12.5, color: Paper.muted),
                ),
                for (final category in ChatFacts.categories)
                  if (saved.facts.where((f) => f.category == category).toList()
                      case final facts when facts.isNotEmpty)
                    _Category(
                      title: category,
                      facts: facts,
                      onForget: (f) => _forget(chat, f),
                    ),
              ],
            ];
          },
        ),
        const Footnote(
          'Kept on this phone. Forgetting a chat forgets these too.',
        ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.progress});

  final (int, int)? progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    return PaperPanel(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MonoLabel('Reading the chat', spacing: 0.12),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: Corner.all(Corner.pill),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: p == null || p.$2 == 0 ? null : p.$1 / p.$2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            p == null || p.$2 <= 1
                ? 'Picking out what is worth remembering.'
                : 'Part ${(p.$1 + 1).clamp(1, p.$2)} of ${p.$2}. A long chat '
                      'is read in parts, then the findings are merged.',
            style: Type.prose(size: 13, color: Paper.body, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _Category extends StatelessWidget {
  const _Category({
    required this.title,
    required this.facts,
    required this.onForget,
  });

  final String title;
  final List<ChatFact> facts;
  final ValueChanged<ChatFact> onForget;

  @override
  Widget build(BuildContext context) => PaperCard(
    padding: const EdgeInsets.fromLTRB(16, 12, 6, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Type.display(20)),
        const SizedBox(height: 4),
        for (final fact in facts)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, right: 10),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Paper.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    fact.text,
                    style: Type.prose(size: 14, color: Paper.ink, height: 1.4),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Forget this',
                visualDensity: VisualDensity.compact,
                onPressed: () => onForget(fact),
                icon: Icon(Icons.close_rounded, size: 18, color: Paper.muted),
              ),
            ],
          ),
      ],
    ),
  );
}

class _ChatPills extends StatelessWidget {
  const _ChatPills({
    required this.chats,
    required this.selected,
    required this.onPick,
  });

  final List<ChatMemory> chats;
  final int selected;
  final ValueChanged<int>? onPick;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final chat in chats)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: onPick == null ? null : () => onPick!(chat.id),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: chat.id == selected ? Paper.accent : Paper.card,
                  borderRadius: Corner.all(Corner.pill),
                  border: chat.id == selected
                      ? null
                      : Border.all(color: Paper.border, width: 1.5),
                ),
                child: Text(
                  chat.theirName.isEmpty ? 'Unnamed' : chat.theirName,
                  style: Type.strong(
                    size: 14,
                    color: chat.id == selected ? Paper.onAccent : Paper.ink,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
