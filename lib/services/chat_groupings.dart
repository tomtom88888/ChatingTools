import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/api_usage.dart';
import '../models/stored_exchange.dart';
import 'openai_service.dart';
import 'vector_math.dart';

/// Where a set of exchanges comes from.
enum ChatKind {
  /// One-to-one chats only.
  direct,

  /// Group chats only.
  group,

  /// Some of each.
  mixed,
}

/// One group of learned replies that sit close together in meaning, with the
/// name the model gave it.
class ChatGroup {
  const ChatGroup({
    required this.name,
    required this.about,
    required this.members,
  });

  final String name;

  /// One short sentence on what the group holds; may be empty.
  final String about;

  /// Every exchange in the group, the most typical first.
  final List<StoredExchange> members;

  int get size => members.length;

  ChatGroup named(String name, String about) =>
      ChatGroup(name: name, about: about, members: members);
}

/// Spherical k-means over unit-length embeddings: points are assigned by
/// cosine similarity, and each centre is the normalised mean of its points.
///
/// Pure Dart and deterministic for a given [seed], so it is unit-testable.
class KMeans {
  const KMeans._();

  /// The group each of [vectors] falls in, `0 ≤ group < k`. Group numbers are
  /// dense: every one from 0 to k−1 has at least one member.
  static List<int> assign(
    List<Float32List> vectors,
    int k, {
    int seed = 7,
    int maxIterations = 40,
  }) {
    final n = vectors.length;
    if (n == 0) return const [];
    k = k.clamp(1, n);
    final random = math.Random(seed);
    final centres = _seed(vectors, k, random);
    final groups = List<int>.filled(n, -1);

    for (var iteration = 0; iteration < maxIterations; iteration++) {
      var moved = 0;
      final closeness = Float64List(n);
      for (var i = 0; i < n; i++) {
        var best = 0;
        var bestScore = -double.infinity;
        for (var c = 0; c < k; c++) {
          final score = VectorMath.dot(vectors[i], centres[c]);
          if (score > bestScore) {
            bestScore = score;
            best = c;
          }
        }
        closeness[i] = bestScore;
        if (groups[i] != best) {
          groups[i] = best;
          moved++;
        }
      }
      if (moved == 0 && iteration > 0) break;

      // New centres. A group left empty takes the point that fits its own
      // group worst, so there are always k groups.
      final dims = vectors.first.length;
      final sums = List.generate(k, (_) => Float64List(dims));
      final sizes = List<int>.filled(k, 0);
      for (var i = 0; i < n; i++) {
        final sum = sums[groups[i]];
        final v = vectors[i];
        for (var d = 0; d < dims; d++) {
          sum[d] += v[d];
        }
        sizes[groups[i]]++;
      }
      for (var c = 0; c < k; c++) {
        if (sizes[c] == 0) {
          var worst = -1;
          for (var i = 0; i < n; i++) {
            if (sizes[groups[i]] > 1 &&
                (worst < 0 || closeness[i] < closeness[worst])) {
              worst = i;
            }
          }
          // k ≤ n, so with a group empty another has at least two members.
          sizes[groups[worst]]--;
          groups[worst] = c;
          sizes[c] = 1;
          closeness[worst] = 1;
          centres[c] = Float32List.fromList(vectors[worst]);
          continue;
        }
        centres[c] = VectorMath.normalise(sums[c]);
      }
    }
    return groups;
  }

  /// k-means++: each next centre is picked with odds proportional to how far
  /// it is from the nearest centre so far, which spreads them out.
  static List<Float32List> _seed(
    List<Float32List> vectors,
    int k,
    math.Random random,
  ) {
    final n = vectors.length;
    final centres = <Float32List>[vectors[random.nextInt(n)]];
    final distance = Float64List(n)..fillRange(0, n, double.infinity);
    while (centres.length < k) {
      final latest = centres.last;
      var total = 0.0;
      for (var i = 0; i < n; i++) {
        // Squared Euclidean distance between unit vectors.
        final d = math.max(0.0, 2 - 2 * VectorMath.dot(vectors[i], latest));
        if (d < distance[i]) distance[i] = d;
        total += distance[i];
      }
      if (total <= 0) {
        // Everything left is a duplicate of a centre; any point will do.
        centres.add(vectors[random.nextInt(n)]);
        continue;
      }
      var pick = random.nextDouble() * total;
      var chosen = n - 1;
      for (var i = 0; i < n; i++) {
        pick -= distance[i];
        if (pick <= 0) {
          chosen = i;
          break;
        }
      }
      centres.add(vectors[chosen]);
    }
    return centres;
  }
}

/// Groups learned replies by what was being said, and has the model name
/// each group.
///
/// Only the grouping is local; naming sends a few short samples per group to
/// OpenAI, the same way writing a reply sends retrieved examples.
class ChatGrouper {
  ChatGrouper({required this.openai});

  final OpenAiService openai;

  static const int defaultGroups = 10;
  static const int minGroups = 2;
  static const int maxGroups = 30;

  /// Samples of each group shown to the model.
  static const int samplesPerGroup = 6;

  /// Longest sample text sent, per side.
  static const int sampleCharacters = 160;

  /// Above this much arithmetic the clustering runs off the UI isolate.
  static const int _backgroundWork = 4000000;

  /// Splits [exchanges] into up to [count] groups, biggest first, and names
  /// them with [model].
  ///
  /// Exchanges whose vectors are a different length from the majority (built
  /// with another fingerprint model) are left out.
  ///
  /// [groupChatIds] are the chats that are group chats; every other chat is
  /// a one-to-one chat, and the model is told so.
  Future<List<ChatGroup>> group(
    List<StoredExchange> exchanges, {
    required int count,
    required String model,
    Set<int> groupChatIds = const {},
  }) async {
    final usable = _sameLength(exchanges);
    if (usable.isEmpty) return const [];
    final vectors = [for (final e in usable) e.vector];
    final k = count.clamp(1, usable.length);

    final work = vectors.length * k * vectors.first.length;
    final assignment = work > _backgroundWork
        ? await Isolate.run(() => KMeans.assign(vectors, k))
        : KMeans.assign(vectors, k);

    final groups = arrange(usable, assignment);
    return name(groups, model: model, groupChatIds: groupChatIds);
  }

  /// Builds the groups from an assignment: members ordered most typical
  /// first, groups ordered biggest first, each called "Group N" until named.
  static List<ChatGroup> arrange(
    List<StoredExchange> exchanges,
    List<int> assignment,
  ) {
    final byGroup = <int, List<StoredExchange>>{};
    for (var i = 0; i < exchanges.length; i++) {
      (byGroup[assignment[i]] ??= []).add(exchanges[i]);
    }
    final groups = <ChatGroup>[];
    for (final members in byGroup.values) {
      final dims = members.first.vector.length;
      final mean = Float64List(dims);
      for (final m in members) {
        for (var d = 0; d < dims; d++) {
          mean[d] += m.vector[d];
        }
      }
      final centre = VectorMath.normalise(mean);
      final scored = [
        for (final m in members) (m, VectorMath.dot(m.vector, centre)),
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      groups.add(
        ChatGroup(
          name: '',
          about: '',
          members: [for (final (m, _) in scored) m],
        ),
      );
    }
    groups.sort((a, b) => b.size.compareTo(a.size));
    return [
      for (var i = 0; i < groups.length; i++)
        groups[i].named('Group ${i + 1}', ''),
    ];
  }

  /// Asks the model for a name and a line for each group. A group the reply
  /// leaves out keeps its "Group N".
  Future<List<ChatGroup>> name(
    List<ChatGroup> groups, {
    required String model,
    Set<int> groupChatIds = const {},
  }) async {
    if (groups.isEmpty) return groups;
    final kind = kindOf(groups, groupChatIds);
    final raw = await openai.chat(
      model: model,
      messages: [
        {'role': 'system', 'content': namingSystemPrompt(kind)},
        {
          'role': 'user',
          'content': namingPrompt(groups, groupChatIds: groupChatIds),
        },
      ],
      jsonMode: true,
      temperature: 0.4,
      usageKind: UsageKind.generation,
    );
    final names = parseNames(raw);
    return [
      for (var i = 0; i < groups.length; i++)
        if (names[i + 1] case (final name, final about))
          groups[i].named(name, about)
        else
          groups[i],
    ];
  }

  /// Whether the exchanges come from one-to-one chats, group chats, or both.
  static ChatKind kindOf(List<ChatGroup> groups, Set<int> groupChatIds) {
    var direct = false;
    var group = false;
    for (final g in groups) {
      for (final e in g.members) {
        if (groupChatIds.contains(e.chatId)) {
          group = true;
        } else {
          direct = true;
        }
      }
    }
    return group && direct
        ? ChatKind.mixed
        : (group ? ChatKind.group : ChatKind.direct);
  }

  /// The instructions. The clusters are called topics throughout, never
  /// groups: in a chat app "group" reads as "group chat", and a model told
  /// about "groups" of messages from a one-to-one chat will describe them as
  /// a group chat.
  static String namingSystemPrompt(ChatKind kind) {
    final source = switch (kind) {
      ChatKind.direct =>
        'private one-to-one chats (DMs) between "me" and one other person. '
            'None of them is a group chat: never describe anything as a '
            'group, a group chat or "everyone", and speak of the other '
            'person in the singular.',
      ChatKind.group =>
        'group chats. In each exchange "them" is whoever in the group spoke '
            'just before "me".',
      ChatKind.mixed =>
        'a mix of private one-to-one chats (DMs) and group chats; each '
            'exchange is marked [DM] or [group chat]. Only call something a '
            'group chat when its exchanges are marked so.',
    };
    return 'You name the topics in one person\'s text-message history. The '
        'exchanges come from $source\n\n'
        'They have been clustered into numbered topics, so the exchanges in '
        'a topic share a subject, a mood or a kind of moment. For every '
        'topic give a short, specific name of two to four words, in the '
        'language of the messages, and one plain sentence on what the topic '
        'holds. Make the names distinct from each other. Never quote private '
        'details such as addresses or numbers. Answer only with JSON: '
        '{"topics": [{"topic": 1, "name": "...", "about": "..."}]}';
  }

  /// The samples, as numbered topics of "them → me" lines, each marked with
  /// its kind of chat when both kinds are present.
  static String namingPrompt(
    List<ChatGroup> groups, {
    Set<int> groupChatIds = const {},
  }) {
    final mixed = kindOf(groups, groupChatIds) == ChatKind.mixed;
    final out = StringBuffer();
    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      out.writeln('Topic ${i + 1} (${group.size} exchanges):');
      for (final e in group.members.take(samplesPerGroup)) {
        final said = e.context.isEmpty ? '' : e.context.last.text;
        final mark = !mixed
            ? ''
            : (groupChatIds.contains(e.chatId) ? '[group chat] ' : '[DM] ');
        out.writeln(
          '- $mark'
          'them: "${_clip(said)}" → me: "${_clip(e.replyText)}"',
        );
      }
      out.writeln();
    }
    return out.toString().trimRight();
  }

  /// Group number to (name, about), from the model's JSON. Tolerates a code
  /// fence or text around the object.
  static Map<int, (String, String)> parseNames(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return const {};
    Object? json;
    try {
      json = jsonDecode(raw.substring(start, end + 1));
    } on FormatException {
      return const {};
    }
    final list = json is Map ? (json['topics'] ?? json['groups']) : json;
    if (list is! List) return const {};
    final out = <int, (String, String)>{};
    for (final entry in list) {
      if (entry is! Map) continue;
      final number = entry['topic'] ?? entry['group'];
      final name = entry['name'];
      if (number is! num || name is! String || name.trim().isEmpty) continue;
      final about = entry['about'];
      out[number.toInt()] = (name.trim(), about is String ? about.trim() : '');
    }
    return out;
  }

  static String _clip(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= sampleCharacters
        ? flat
        : '${flat.substring(0, sampleCharacters - 1)}…';
  }

  static List<StoredExchange> _sameLength(List<StoredExchange> exchanges) {
    final counts = <int, int>{};
    for (final e in exchanges) {
      if (e.vector.isEmpty) continue;
      counts[e.vector.length] = (counts[e.vector.length] ?? 0) + 1;
    }
    if (counts.isEmpty) return const [];
    final length = counts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
    return [
      for (final e in exchanges)
        if (e.vector.length == length) e,
    ];
  }
}
