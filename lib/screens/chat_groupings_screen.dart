import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/stored_exchange.dart';
import '../services/chat_groupings.dart';
import '../services/group_map.dart';
import '../services/groupings_store.dart';
import '../services/topic_timeline.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/failure_text.dart';
import '../widgets/format.dart';
import '../widgets/paper_ui.dart';
import 'groupings/group_map_card.dart';
import 'groupings/topic_timeline_card.dart';
import 'settings/settings_widgets.dart';

/// Your learned replies, grouped by what was being said, with a name for
/// each group from the model.
class ChatGroupingsScreen extends ConsumerStatefulWidget {
  const ChatGroupingsScreen({super.key});

  @override
  ConsumerState<ChatGroupingsScreen> createState() =>
      _ChatGroupingsScreenState();
}

class _ChatGroupingsScreenState extends ConsumerState<ChatGroupingsScreen> {
  int _count = ChatGrouper.defaultGroups;
  bool _busy = false;
  Object? _error;
  List<ChatGroup>? _groups;
  GroupMap _map = GroupMap.empty;
  TopicTimeline? _timeline;

  /// When the groups on screen were made, and from which chats; `null`
  /// before there are any.
  DateTime? _madeAt;
  Set<int> _madeFrom = const {};

  /// Whether the saved groupings are still being read back.
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// Opens on the last groupings made, read back out of the style memory.
  Future<void> _restore() async {
    try {
      final saved = await ref.read(groupingsStoreProvider).load();
      if (saved == null) return;
      final exchanges = await ref
          .read(exchangeStoreProvider)
          .all(chatIds: saved.chatIds);
      final groups = saved.resolve(exchanges);
      if (groups.isEmpty || !mounted) return;
      final map = GroupMap.of(groups);
      final timeline = TopicTimeline.of(groups);
      setState(() {
        _groups = groups;
        _map = map;
        _timeline = timeline;
        _count = saved.count;
        _madeAt = saved.at;
        _madeFrom = saved.chatIds;
      });
    } on Object {
      // Unreadable or out of date: the page just starts empty.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The ticked chats that match the current fingerprint settings; all
  /// matching chats when none are ticked.
  static List<ChatMemory> _source(List<ChatMemory> all, AppSettings settings) {
    final usable = [
      for (final c in all)
        if (!c.isEmpty &&
            c.matches(settings.embeddingModel, settings.embeddingDimensions))
          c,
    ];
    final ticked = usable.where((c) => c.enabled).toList();
    return ticked.isEmpty ? usable : ticked;
  }

  /// A note when the groups on screen no longer cover what would be grouped
  /// now: other chats ticked, or replies added or forgotten since.
  Widget? _staleness(List<ChatGroup> groups, List<ChatMemory> source) {
    final now = {for (final c in source) c.id};
    final grouped = groups.fold(0, (sum, g) => sum + g.size);
    final available = source.fold(0, (sum, c) => sum + c.exchangeCount);
    final String? why;
    if (!now.containsAll(_madeFrom) || !_madeFrom.containsAll(now)) {
      why = 'The chats ticked have changed since.';
    } else if (available > grouped) {
      final added = available - grouped;
      why =
          '$added ${added == 1 ? "reply has" : "replies have"} been added '
          'since.';
    } else {
      why = null;
    }
    if (why == null) return null;
    return Notice(
      'Grouped on ${dayMonthTime(_madeAt!)}. $why Group again to include '
      'everything.',
      tone: NoticeTone.caution,
    );
  }

  Future<void> _run(List<ChatMemory> chats) async {
    final grouper = ref.read(chatGrouperProvider);
    if (grouper == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final settings = await ref.read(settingsProvider.future);
      final exchanges = await ref
          .read(exchangeStoreProvider)
          .all(chatIds: {for (final c in chats) c.id});
      final groups = await grouper.group(
        exchanges,
        count: _count,
        model: settings.generationModel,
        groupChatIds: {
          for (final c in chats)
            if (c.isGroup) c.id,
        },
      );
      final map = GroupMap.of(groups);
      final timeline = TopicTimeline.of(groups);
      final chatIds = {for (final c in chats) c.id};
      final now = DateTime.now();
      if (groups.isNotEmpty) {
        await ref
            .read(groupingsStoreProvider)
            .save(
              SavedGrouping.of(
                groups,
                count: _count,
                chatIds: chatIds,
                at: now,
              ),
            );
      }
      if (mounted) {
        setState(() {
          _groups = groups;
          _map = map;
          _timeline = timeline;
          _madeAt = now;
          _madeFrom = chatIds;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatsProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final hasKey = ref.watch(chatGrouperProvider) != null;

    return PaperScreen(
      children: [
        Row(
          children: [
            BackArrow(onTap: () => Navigator.of(context).pop()),
            const SizedBox(width: 10),
            const MonoLabel('Chat groupings'),
          ],
        ),
        const SerifTitle('What you ', accent: 'talk about', trailing: '.'),
        ...chats.when(
          loading: () => [const LinearProgressIndicator(minHeight: 3)],
          error: (error, _) => [FailureNotice(error: error)],
          data: (all) {
            final source = _source(all, settings);
            if (source.isEmpty) {
              return const [
                Notice(
                  'Import a chat export first, or rebuild the ones made with '
                  'a different fingerprint model than Settings uses.',
                  tone: NoticeTone.caution,
                  title: 'Nothing to group',
                ),
              ];
            }
            final replies = source.fold(0, (sum, c) => sum + c.exchangeCount);
            final groups = _groups;
            return [
              Text(
                'Every reply learned from '
                '${nameList([for (final c in source) bidiIsolate(c.theirName.isEmpty ? "an unnamed chat" : c.theirName)])} '
                '(${grouped(replies)} ${replies == 1 ? "reply" : "replies"}) is grouped by what was being said. '
                'The grouping happens on the phone; a few short samples from '
                'each group go to OpenAI so it can name them.',
                style: Type.prose(size: 14, color: Paper.body, height: 1.45),
              ),
              NumberStepper(
                label: 'Groups',
                helper: 'How many to split your replies into',
                value: _count,
                min: ChatGrouper.minGroups,
                max: ChatGrouper.maxGroups,
                onChanged: (v) => setState(() => _count = v),
              ),
              PaperAction(
                title: groups == null ? 'Group my chats' : 'Group again',
                subtitle: hasKey
                    ? 'Into $_count groups, named by ${settings.generationModel}'
                    : 'Add your OpenAI key in Settings first',
                tone: groups == null ? ActionTone.accent : ActionTone.outline,
                busy: _busy,
                onTap: hasKey ? () => _run(source) : null,
              ),
              if (_error != null)
                FailureNotice(error: _error!, onRetry: () => _run(source)),
              if (groups != null && groups.isEmpty)
                const Notice('No replies with fingerprints to group.'),
              if (_loading && groups == null)
                const LinearProgressIndicator(minHeight: 3),
              if (groups != null && groups.isNotEmpty && _madeAt != null)
                _staleness(groups, source) ??
                    Text(
                      'Grouped on ${dayMonthTime(_madeAt!)}.',
                      style: Type.prose(size: 12.5, color: Paper.muted),
                    ),
              if (groups != null && groups.isNotEmpty) ...[
                GroupMapCard(key: ValueKey(groups), groups: groups, map: _map),
                if (_timeline case final timeline?
                    when timeline.buckets.length > 1)
                  TopicTimelineCard(
                    key: ValueKey(timeline),
                    groups: groups,
                    timeline: timeline,
                  ),
                for (var i = 0; i < groups.length; i++)
                  _GroupCard(
                    key: ValueKey('group-${groups[i].name}-${groups[i].size}'),
                    group: groups[i],
                    number: i + 1,
                    total: groups.fold(0, (sum, g) => sum + g.size),
                  ),
              ],
            ];
          },
        ),
        const Footnote('Kept on this phone until you group again.'),
      ],
    );
  }
}

/// One group: its name, how much of your chat it is, and its most typical
/// exchanges.
class _GroupCard extends StatefulWidget {
  const _GroupCard({
    required this.group,
    required this.number,
    required this.total,
    super.key,
  });

  final ChatGroup group;

  /// Its number on the map, from 1.
  final int number;
  final int total;

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  bool _open = false;

  static const int _collapsed = 3;
  static const int _expanded = 8;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final share = widget.total == 0 ? 0.0 : group.size / widget.total;
    final shown = group.members.take(_open ? _expanded : _collapsed).toList();
    final more = group.size > _collapsed;

    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GroupBadge(
                number: widget.number,
                colour: GroupMapCard.colourOf(widget.number - 1),
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(group.name, style: Type.display(22))),
            ],
          ),
          if (group.about.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              group.about,
              style: Type.prose(
                size: 13.5,
                color: Paper.secondary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: (share * box.maxWidth).clamp(3.0, box.maxWidth),
                      height: 6,
                      decoration: BoxDecoration(
                        color: GroupMapCard.colourOf(widget.number - 1),
                        borderRadius: Corner.all(const Radius.circular(4)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${grouped(group.size)} · ${percent(share)}',
                style: Type.numeric(size: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final exchange in shown) _Sample(exchange: exchange),
          if (more)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _open = !_open),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  foregroundColor: Paper.accent,
                ),
                child: Text(
                  _open ? 'Show fewer' : 'Show more',
                  style: Type.strong(size: 13, color: Paper.accent),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What they said, then your reply, in the chat's two bubble colours.
class _Sample extends StatelessWidget {
  const _Sample({required this.exchange});

  final StoredExchange exchange;

  @override
  Widget build(BuildContext context) {
    final said = exchange.context.isEmpty ? '' : exchange.context.last.text;
    Widget bubble(String text, Color color, Alignment side) => Align(
      alignment: side,
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: color,
          borderRadius: Corner.all(Corner.bubble),
        ),
        child: Text(
          text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Type.prose(size: 13.5, color: Paper.ink, height: 1.35),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Paper.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (said.isNotEmpty) bubble(said, Paper.panel, Alignment.centerLeft),
          bubble(exchange.replyText, Paper.bubbleMine, Alignment.centerRight),
        ],
      ),
    );
  }
}
