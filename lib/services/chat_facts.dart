import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_usage.dart';
import '../models/stored_exchange.dart';
import 'openai_service.dart';

/// Something the other person has told you, worth calling back to: their
/// dog's name, the exam next week, that they hate coriander.
class ChatFact {
  const ChatFact({required this.text, required this.category});

  final String text;
  final String category;

  Map<String, Object?> toJson() => {'text': text, 'category': category};

  static ChatFact? fromJson(Object? json) {
    if (json is! Map) return null;
    final text = json['text'] ?? json['fact'];
    if (text is! String || text.trim().isEmpty) return null;
    final category = json['category'];
    return ChatFact(
      text: text.trim(),
      category: ChatFacts.categoryOf(category is String ? category : ''),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatFact && other.text == text && other.category == category;

  @override
  int get hashCode => Object.hash(text, category);
}

/// Reads what the other person said in a chat and picks out the facts about
/// them worth remembering.
///
/// The app keeps no copy of the export itself, only your replies with the
/// messages leading up to each, so their side is rebuilt from those lead-ups
/// with repeats removed: in practice nearly everything they said shortly
/// before one of your replies.
class ChatFacts {
  ChatFacts({required this.openai});

  final OpenAiService openai;

  static const List<String> categories = [
    'About them',
    'Likes',
    'Dislikes',
    'People & pets',
    'Work & study',
    'Plans & dates',
    'Other',
  ];

  /// Characters of their messages per request.
  static const int chunkCharacters = 12000;

  /// At most this many chunks are read: about 100,000 characters of what
  /// they said, spread over the whole chat.
  static const int maxChunks = 8;

  /// The most facts kept for one chat.
  static const int maxFacts = 40;

  static String categoryOf(String raw) {
    final lower = raw.trim().toLowerCase();
    for (final c in categories) {
      if (c.toLowerCase() == lower) return c;
    }
    return 'Other';
  }

  /// Their messages, oldest first, one line each with its date.
  static List<String> theirLines(
    List<StoredExchange> exchanges, {
    required String myName,
  }) {
    final seen = <String>{};
    final lines = <(DateTime?, int, String)>[];
    var order = 0;
    for (final e in exchanges) {
      for (final turn in e.context) {
        if (turn.sender == myName || turn.text.trim().isEmpty) continue;
        final at = turn.firstTimestamp ?? turn.lastTimestamp;
        final key =
            '${turn.sender}\u0000${at?.millisecondsSinceEpoch}'
            '\u0000${turn.text}';
        if (!seen.add(key)) continue;
        final date = at == null
            ? ''
            : '[${at.year}-${_two(at.month)}-${_two(at.day)}] ';
        final flat = turn.text.replaceAll(RegExp(r'\s*\n\s*'), ' / ');
        lines.add((at, order++, '$date${turn.sender}: $flat'));
      }
    }
    lines.sort((a, b) {
      final x = a.$1;
      final y = b.$1;
      if (x != null && y != null && x != y) return x.compareTo(y);
      return a.$2.compareTo(b.$2);
    });
    return [for (final l in lines) l.$3];
  }

  /// [lines] cut into requests of about [chunkCharacters]. A chat too long
  /// to read whole keeps [maxChunks] of them spread evenly from its first
  /// message to its last, each a continuous stretch so it still reads as
  /// conversation; reading only the newest would make a busy chat's facts
  /// all about the last few weeks.
  static List<String> chunks(List<String> lines) {
    final out = <String>[];
    var current = StringBuffer();
    for (final line in lines) {
      if (current.length + line.length + 1 > chunkCharacters &&
          current.isNotEmpty) {
        out.add(current.toString());
        current = StringBuffer();
      }
      current.writeln(line);
    }
    if (current.isNotEmpty) out.add(current.toString());
    if (out.length <= maxChunks) return out;
    final last = out.length - 1;
    return [
      for (var i = 0; i < maxChunks; i++)
        out[(i * last / (maxChunks - 1)).round()],
    ];
  }

  /// Finds the facts in [exchanges] about [them]. [onProgress] hears how
  /// many requests are done out of how many.
  Future<List<ChatFact>> find(
    List<StoredExchange> exchanges, {
    required String myName,
    required String them,
    required String model,
    bool group = false,
    void Function(int done, int of)? onProgress,
  }) async {
    final parts = chunks(theirLines(exchanges, myName: myName));
    if (parts.isEmpty) return const [];
    final steps = parts.length + (parts.length > 1 ? 1 : 0);
    onProgress?.call(0, steps);

    final found = <ChatFact>[];
    for (var i = 0; i < parts.length; i++) {
      final raw = await openai.chat(
        model: model,
        messages: [
          {'role': 'system', 'content': findPrompt(them: them, group: group)},
          {'role': 'user', 'content': parts[i]},
        ],
        jsonMode: true,
        temperature: 0.2,
        usageKind: UsageKind.generation,
      );
      found.addAll(parse(raw));
      onProgress?.call(i + 1, steps);
    }
    if (parts.length == 1) return _capped(found);

    // Several passes find the same things, and older facts can be overtaken
    // by newer ones: one more pass merges them.
    final raw = await openai.chat(
      model: model,
      messages: [
        {'role': 'system', 'content': mergePrompt(them: them)},
        {
          'role': 'user',
          'content': jsonEncode({
            'facts': [for (final f in found) f.toJson()],
          }),
        },
      ],
      jsonMode: true,
      temperature: 0.2,
      usageKind: UsageKind.generation,
    );
    onProgress?.call(steps, steps);
    final merged = parse(raw);
    return _capped(merged.isEmpty ? found : merged);
  }

  static List<ChatFact> _capped(List<ChatFact> facts) {
    final seen = <String>{};
    return [
      for (final f in facts)
        if (seen.add(f.text.toLowerCase())) f,
    ].take(maxFacts).toList();
  }

  static String findPrompt({required String them, bool group = false}) {
    final who = group
        ? 'the other people in a group chat (say who each fact is about)'
        : them.isEmpty
        ? 'the other person in a private chat'
        : '$them, the other person in a private chat';
    return 'Below are messages written by $who, oldest first, each with its '
        'date. Pick out facts about them that a friend or date would want '
        'to remember and could bring up later: what they like and dislike, '
        'the people and pets in their life, their work or studies, where '
        'they live or are from, plans, trips, exams and dates coming up, '
        'things they are going through. Only what they actually said, never '
        'guesses. Keep each fact short, in the third person and in the '
        'language of the messages; give dates for anything tied to a time '
        '("had a job interview on 2026-03-02"). Skip small talk, anything '
        'about the reader, and passwords, addresses, phone or card numbers. '
        'Categories: ${categories.join(', ')}. Answer only with JSON: '
        '{"facts": [{"text": "...", "category": "..."}]}. An empty list is '
        'fine.';
  }

  static String mergePrompt({required String them}) =>
      'These facts about ${them.isEmpty ? "the other person" : them} were '
      'found in parts of the same chat spread over its whole history, oldest '
      'part first. Merge them: remove repeats, keep the newer of two that '
      'disagree (a new job, a plan that changed), drop anything trivial, and '
      'keep at most $maxFacts, the most useful first. Keep lasting facts from '
      'every part of the history, not only the most recent. Keep each short, '
      'in the language it is in, with its category from: '
      '${categories.join(', ')}. Answer only with JSON: '
      '{"facts": [{"text": "...", "category": "..."}]}';

  static List<ChatFact> parse(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return const [];
    Object? json;
    try {
      json = jsonDecode(raw.substring(start, end + 1));
    } on FormatException {
      return const [];
    }
    final list = json is Map ? json['facts'] : null;
    if (list is! List) return const [];
    return [for (final entry in list) ?ChatFact.fromJson(entry)];
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// The facts found for each chat, and when, kept on the device.
class FactsStore {
  const FactsStore();

  static const String _prefsKey = 'ditto_facts_v1';

  Future<Map<int, SavedFacts>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return decode(prefs.getString(_prefsKey));
  }

  Future<SavedFacts?> forChat(int chatId) async => (await load())[chatId];

  Future<void> save(int chatId, SavedFacts facts) async {
    final all = await load();
    all[chatId] = facts;
    await _write(all);
  }

  Future<void> remove(int chatId) async {
    final all = await load();
    if (all.remove(chatId) != null) await _write(all);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  Future<void> _write(Map<int, SavedFacts> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({for (final e in all.entries) '${e.key}': e.value.toJson()}),
    );
  }

  static Map<int, SavedFacts> decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return {};
      return {
        for (final e in json.entries)
          ?int.tryParse('${e.key}'): ?SavedFacts.fromJson(e.value),
      };
    } on FormatException {
      return {};
    }
  }
}

class SavedFacts {
  const SavedFacts({required this.at, required this.facts});

  final DateTime at;
  final List<ChatFact> facts;

  SavedFacts without(ChatFact fact) => SavedFacts(
    at: at,
    facts: [
      for (final f in facts)
        if (f != fact) f,
    ],
  );

  Map<String, Object?> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'facts': [for (final f in facts) f.toJson()],
  };

  static SavedFacts? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['at'];
    final facts = json['facts'];
    if (at is! num || facts is! List) return null;
    return SavedFacts(
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      facts: [for (final f in facts) ?ChatFact.fromJson(f)],
    );
  }
}
