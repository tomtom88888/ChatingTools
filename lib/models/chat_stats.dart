import 'dart:math' as math;

import 'chat_message.dart';
import 'parsed_chat.dart';

/// What one side of a chat did, counted from the export.
class PersonStats {
  const PersonStats({
    this.messages = 0,
    this.words = 0,
    this.longestMessageWords = 0,
    this.media = 0,
    this.deleted = 0,
    this.emoji = 0,
    this.questions = 0,
    this.laughs = 0,
    this.lateNight = 0,
    this.replies = 0,
    this.medianReplySeconds,
    this.quickReplies = 0,
    this.conversationsStarted = 0,
    this.doubleTexts = 0,
    this.topEmoji = const {},
    this.topWords = const {},
  });

  /// Text messages sent.
  final int messages;
  final int words;
  final int longestMessageWords;

  /// Photos, videos, stickers, voice notes and documents.
  final int media;
  final int deleted;

  /// Emoji used, in total.
  final int emoji;

  /// Messages with a question mark.
  final int questions;

  /// Messages that laugh: "haha", "lol", "😂", "חחח" and the like.
  final int laughs;

  /// Messages sent between midnight and 5am.
  final int lateNight;

  /// Times this side answered the other within [ChatStats.replyWindow].
  final int replies;

  /// The middle of those answer times; `null` with no answers to time.
  final int? medianReplySeconds;

  /// Answers within five minutes.
  final int quickReplies;

  /// Conversations this side opened after [ChatStats.conversationGap] of
  /// silence.
  final int conversationsStarted;

  /// Times this side texted again after an hour without an answer — but
  /// before the silence was long enough to count as a new conversation.
  final int doubleTexts;

  final Map<String, int> topEmoji;
  final Map<String, int> topWords;

  double get wordsPerMessage => messages == 0 ? 0 : words / messages;

  double get quickReplyShare => replies == 0 ? 0 : quickReplies / replies;

  Map<String, Object?> toJson() => {
    'messages': messages,
    'words': words,
    'longestMessageWords': longestMessageWords,
    'media': media,
    'deleted': deleted,
    'emoji': emoji,
    'questions': questions,
    'laughs': laughs,
    'lateNight': lateNight,
    'replies': replies,
    'medianReplySeconds': medianReplySeconds,
    'quickReplies': quickReplies,
    'conversationsStarted': conversationsStarted,
    'doubleTexts': doubleTexts,
    'topEmoji': topEmoji,
    'topWords': topWords,
  };

  factory PersonStats.fromJson(Object? raw) {
    if (raw is! Map) return const PersonStats();
    int n(String key) => (raw[key] as num?)?.toInt() ?? 0;
    return PersonStats(
      messages: n('messages'),
      words: n('words'),
      longestMessageWords: n('longestMessageWords'),
      media: n('media'),
      deleted: n('deleted'),
      emoji: n('emoji'),
      questions: n('questions'),
      laughs: n('laughs'),
      lateNight: n('lateNight'),
      replies: n('replies'),
      medianReplySeconds: (raw['medianReplySeconds'] as num?)?.toInt(),
      quickReplies: n('quickReplies'),
      conversationsStarted: n('conversationsStarted'),
      doubleTexts: n('doubleTexts'),
      topEmoji: _counts(raw['topEmoji']),
      topWords: _counts(raw['topWords']),
    );
  }
}

/// The numbers behind a chat: who says how much, how fast each of you
/// answers, and when you talk. Worked out on the phone from the export when it
/// is imported, and stored with the chat.
class ChatStats {
  const ChatStats({
    this.me = const PersonStats(),
    this.them = const PersonStats(),
    this.firstAt,
    this.lastAt,
    this.activeDays = 0,
    this.longestStreakDays = 0,
    this.busiestDay,
    this.busiestDayMessages = 0,
    this.byHour = const [],
    this.byWeekday = const [],
    this.members = const {},
  });

  static const ChatStats empty = ChatStats();

  /// An answer later than this is a new conversation, not a reply.
  static const Duration replyWindow = Duration(hours: 12);

  /// Silence longer than this, and the next message opens a new conversation.
  static const Duration conversationGap = Duration(hours: 6);

  /// Texting again after this long unanswered is a double text.
  static const Duration doubleTextGap = Duration(hours: 1);

  static const Duration quickReply = Duration(minutes: 5);

  final PersonStats me;
  final PersonStats them;

  final DateTime? firstAt;
  final DateTime? lastAt;

  /// Days with at least one message.
  final int activeDays;

  /// The most days in a row with at least one message.
  final int longestStreakDays;

  final DateTime? busiestDay;
  final int busiestDayMessages;

  /// Messages by hour of the day, 0-23.
  final List<int> byHour;

  /// Messages by weekday, Monday first.
  final List<int> byWeekday;

  /// Text messages by each of the other people, most talkative first — in a
  /// group, who "them" actually is. Up to [keepMembers] names.
  final Map<String, int> members;

  static const int keepMembers = 12;

  int get totalMessages => me.messages + them.messages;
  int get totalWords => me.words + them.words;
  bool get isEmpty => totalMessages == 0;

  /// Your share of the messages, 0-1.
  double get myShare => totalMessages == 0 ? 0 : me.messages / totalMessages;

  // ------------------------------------------------------------------ building

  /// Counts [chat], taking [myName] as you and everyone else as them.
  static ChatStats from(ParsedChat chat, {required String myName}) {
    final mine = _Tally();
    final theirs = _Tally();
    final byHour = List<int>.filled(24, 0);
    final byWeekday = List<int>.filled(7, 0);
    final perDay = <DateTime, int>{};
    final memberCounts = <String, int>{};

    ChatMessage? previous;
    for (final message in chat.messages) {
      if (message.kind == MessageKind.system || message.sender == null) {
        continue;
      }
      final isMe = message.sender == myName;
      final tally = isMe ? mine : theirs;
      tally.count(message);
      if (!isMe && message.kind == MessageKind.text) {
        memberCounts[message.sender!] =
            (memberCounts[message.sender!] ?? 0) + 1;
      }

      final at = message.timestamp;
      if (at != null) {
        byHour[at.hour]++;
        byWeekday[at.weekday - 1]++;
        final day = DateTime(at.year, at.month, at.day);
        perDay[day] = (perDay[day] ?? 0) + 1;
      }

      final previousAt = previous?.timestamp;
      final gap = at != null && previousAt != null
          ? at.difference(previousAt)
          : null;
      if (previous == null || (gap != null && gap > conversationGap)) {
        tally.conversationsStarted++;
      }
      if (previous != null && gap != null && !gap.isNegative) {
        final samePerson = previous.sender == message.sender;
        if (!samePerson && gap <= replyWindow) {
          tally.replyTimes.add(gap.inSeconds);
        } else if (samePerson &&
            gap > doubleTextGap &&
            gap <= conversationGap) {
          // Longer than that, and it is a new conversation instead.
          tally.doubleTexts++;
        }
      }
      previous = message;
    }

    final days = perDay.keys.toList()..sort();
    var streak = 0;
    var best = 0;
    for (var i = 0; i < days.length; i++) {
      final continues = i > 0 && days[i].difference(days[i - 1]).inHours <= 25;
      streak = continues ? streak + 1 : 1;
      best = math.max(best, streak);
    }
    DateTime? busiest;
    var busiestCount = 0;
    perDay.forEach((day, count) {
      if (count > busiestCount) {
        busiest = day;
        busiestCount = count;
      }
    });

    final stamps = chat.messages
        .map((m) => m.timestamp)
        .whereType<DateTime>()
        .toList();
    return ChatStats(
      me: mine.build(),
      them: theirs.build(),
      firstAt: stamps.isEmpty ? null : stamps.reduce(_earlier),
      lastAt: stamps.isEmpty ? null : stamps.reduce(_later),
      activeDays: perDay.length,
      longestStreakDays: best,
      busiestDay: busiest,
      busiestDayMessages: busiestCount,
      byHour: byHour,
      byWeekday: byWeekday,
      members: _Tally._top(memberCounts, keepMembers),
    );
  }

  static DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  static DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

  // --------------------------------------------------------------- persistence

  Map<String, Object?> toJson() => {
    'me': me.toJson(),
    'them': them.toJson(),
    'firstAt': firstAt?.millisecondsSinceEpoch,
    'lastAt': lastAt?.millisecondsSinceEpoch,
    'activeDays': activeDays,
    'longestStreakDays': longestStreakDays,
    'busiestDay': busiestDay?.millisecondsSinceEpoch,
    'busiestDayMessages': busiestDayMessages,
    'byHour': byHour,
    'byWeekday': byWeekday,
    'members': members,
  };

  factory ChatStats.fromJson(Object? raw) {
    if (raw is! Map) return ChatStats.empty;
    DateTime? at(String key) {
      final value = raw[key];
      return value is num
          ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
          : null;
    }

    List<int> ints(String key) {
      final value = raw[key];
      return value is List
          ? value.whereType<num>().map((v) => v.toInt()).toList()
          : const [];
    }

    return ChatStats(
      me: PersonStats.fromJson(raw['me']),
      them: PersonStats.fromJson(raw['them']),
      firstAt: at('firstAt'),
      lastAt: at('lastAt'),
      activeDays: (raw['activeDays'] as num?)?.toInt() ?? 0,
      longestStreakDays: (raw['longestStreakDays'] as num?)?.toInt() ?? 0,
      busiestDay: at('busiestDay'),
      busiestDayMessages: (raw['busiestDayMessages'] as num?)?.toInt() ?? 0,
      byHour: ints('byHour'),
      byWeekday: ints('byWeekday'),
      members: _counts(raw['members']),
    );
  }
}

Map<String, int> _counts(Object? raw) => raw is Map
    ? {
        for (final entry in raw.entries)
          if (entry.key is String && entry.value is num)
            entry.key as String: (entry.value as num).toInt(),
      }
    : const {};

/// Running counts for one side while reading the export.
class _Tally {
  int messages = 0;
  int words = 0;
  int longest = 0;
  int media = 0;
  int deleted = 0;
  int emoji = 0;
  int questions = 0;
  int laughs = 0;
  int lateNight = 0;
  int conversationsStarted = 0;
  int doubleTexts = 0;
  final List<int> replyTimes = [];
  final Map<String, int> emojiCounts = {};
  final Map<String, int> wordCounts = {};

  static final RegExp _space = RegExp(r'\s+');
  static final RegExp _emoji = RegExp(
    r'(?:[\u{1F1E6}-\u{1F1FF}]{2}|[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]'
    r'(?:\u{FE0F})?(?:[\u{1F3FB}-\u{1F3FF}])?'
    r'(?:\u{200D}[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}](?:\u{FE0F})?)*)',
    unicode: true,
  );
  static final RegExp _laugh = RegExp(
    r'(?:\b(?:a?ha(?:ha)+|he(?:he)+|lo+l|lmf?ao|rofl|xd)\b|😂|🤣|😆|ח{3,}|ההה+)',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _wordEdges = RegExp(
    r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$',
    unicode: true,
  );

  /// Words too common to say anything, in the languages most likely here.
  static const Set<String> _stopWords = {
    'the',
    'and',
    'you',
    'that',
    'for',
    'are',
    'but',
    'not',
    'was',
    'with',
    'have',
    'this',
    'just',
    'its',
    "it's",
    'what',
    'your',
    'can',
    'all',
    'out',
    'get',
    'too',
    'yes',
    'yeah',
    'will',
    'dont',
    "don't",
    'from',
    'she',
    'him',
    'her',
    'his',
    'they',
    'then',
    'there',
    'when',
    'how',
    'did',
    'got',
    'one',
    'were',
    'had',
    'has',
    'about',
    'would',
    'been',
    'im',
    "i'm",
    'our',
    'who',
    'של',
    'את',
    'זה',
    'לא',
    'אני',
    'מה',
    'עם',
    'גם',
    'על',
    'יש',
    'כן',
    'אם',
    'הוא',
    'היא',
    'אבל',
    'רק',
    'כל',
    'או',
    'אז',
    'לי',
    'לך',
    'אתה',
    'זאת',
    'היה',
    'שלי',
    'שלך',
    'אין',
    'עוד',
    'כי',
    'אנחנו',
    'הם',
    'לו',
  };

  void count(ChatMessage message) {
    switch (message.kind) {
      case MessageKind.media:
        media++;
        return;
      case MessageKind.deleted:
        deleted++;
        return;
      case MessageKind.system:
        return;
      case MessageKind.text:
        break;
    }
    final text = message.text.trim();
    if (text.isEmpty) return;
    messages++;
    final tokens = text.split(_space).where((w) => w.isNotEmpty).toList();
    words += tokens.length;
    longest = math.max(longest, tokens.length);
    if (text.contains('?')) questions++;
    if (_laugh.hasMatch(text)) laughs++;
    final hour = message.timestamp?.hour;
    if (hour != null && hour < 5) lateNight++;

    for (final match in _emoji.allMatches(text)) {
      emoji++;
      final e = match.group(0)!;
      emojiCounts[e] = (emojiCounts[e] ?? 0) + 1;
    }
    for (final token in tokens) {
      final word = token.toLowerCase().replaceAll(_wordEdges, '');
      if (word.length < 3 || _stopWords.contains(word)) continue;
      if (_emoji.hasMatch(word) || _laugh.hasMatch(word)) continue;
      wordCounts[word] = (wordCounts[word] ?? 0) + 1;
    }
  }

  PersonStats build() {
    final times = [...replyTimes]..sort();
    return PersonStats(
      messages: messages,
      words: words,
      longestMessageWords: longest,
      media: media,
      deleted: deleted,
      emoji: emoji,
      questions: questions,
      laughs: laughs,
      lateNight: lateNight,
      replies: times.length,
      medianReplySeconds: _median(times),
      quickReplies: times
          .where((s) => s <= ChatStats.quickReply.inSeconds)
          .length,
      conversationsStarted: conversationsStarted,
      doubleTexts: doubleTexts,
      topEmoji: _top(emojiCounts, 8),
      topWords: _top(wordCounts, 10),
    );
  }

  /// The middle of [sorted]; with an even count, halfway between the two
  /// middle values.
  static int? _median(List<int> sorted) {
    if (sorted.isEmpty) return null;
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : ((sorted[mid - 1] + sorted[mid]) / 2).round();
  }

  static Map<String, int> _top(Map<String, int> counts, int n) {
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return Map.fromEntries(entries.take(n));
  }
}
