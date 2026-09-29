import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/stored_exchange.dart';
import 'chat_groupings.dart';

/// The last chat groupings made, kept on the device so the page opens on
/// them instead of asking for a new (paid) naming call every visit.
///
/// Only names and references are stored: each reply is referred to by its
/// content fingerprint ([StoredExchange.hash]), which survives re-importing
/// the same export, and the replies themselves are read back from the style
/// memory. A reply that has since been forgotten simply drops out.
class GroupingsStore {
  const GroupingsStore();

  static const String _prefsKey = 'ditto_groupings_v1';

  Future<SavedGrouping?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SavedGrouping.decode(prefs.getString(_prefsKey));
  }

  Future<void> save(SavedGrouping grouping) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, grouping.encode());
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}

/// One saved run of the groupings.
class SavedGrouping {
  const SavedGrouping({
    required this.at,
    required this.count,
    required this.chatIds,
    required this.groups,
  });

  factory SavedGrouping.of(
    List<ChatGroup> groups, {
    required int count,
    required Set<int> chatIds,
    DateTime? at,
  }) => SavedGrouping(
    at: at ?? DateTime.now(),
    count: count,
    chatIds: chatIds,
    groups: [
      for (final g in groups)
        (
          name: g.name,
          about: g.about,
          keys: [for (final m in g.members) keyOf(m)],
        ),
    ],
  );

  final DateTime at;

  /// How many groups were asked for.
  final int count;

  /// The chats the replies were drawn from.
  final Set<int> chatIds;

  /// Each group's name and line, and its members, most typical first.
  final List<({String name, String about, List<String> keys})> groups;

  int get replies => groups.fold(0, (sum, g) => sum + g.keys.length);

  /// How a reply is referred to: its content fingerprint, or its row id for
  /// one stored without a fingerprint.
  static String keyOf(StoredExchange e) =>
      e.hash.isNotEmpty ? e.hash : 'id:${e.id}';

  /// The groups again, with their members read back out of [exchanges].
  /// Members no longer there are left out, and so is a group left empty.
  List<ChatGroup> resolve(List<StoredExchange> exchanges) {
    final byKey = {for (final e in exchanges) keyOf(e): e};
    return [
      for (final g in groups)
        if ([for (final k in g.keys) ?byKey[k]] case final members
            when members.isNotEmpty)
          ChatGroup(name: g.name, about: g.about, members: members),
    ];
  }

  String encode() => jsonEncode({
    'at': at.millisecondsSinceEpoch,
    'count': count,
    'chats': chatIds.toList(),
    'groups': [
      for (final g in groups)
        {'name': g.name, 'about': g.about, 'keys': g.keys},
    ],
  });

  static SavedGrouping? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final at = json['at'];
      final count = json['count'];
      final chats = json['chats'];
      final groups = json['groups'];
      if (at is! num || count is! num || chats is! List || groups is! List) {
        return null;
      }
      return SavedGrouping(
        at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
        count: count.toInt(),
        chatIds: {
          for (final c in chats)
            if (c is num) c.toInt(),
        },
        groups: [
          for (final g in groups)
            if (g is Map && g['name'] is String && g['keys'] is List)
              (
                name: g['name'] as String,
                about: g['about'] is String ? g['about'] as String : '',
                keys: [
                  for (final k in g['keys'] as List)
                    if (k is String) k,
                ],
              ),
        ],
      );
    } on FormatException {
      return null;
    }
  }
}
