import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:replylikeme/models/stored_exchange.dart';
import 'package:replylikeme/services/chat_groupings.dart';
import 'package:replylikeme/services/group_map.dart';
import 'package:replylikeme/services/vector_math.dart';

ChatGroup group(int axis, int size, {int seed = 0, int dims = 16}) {
  final random = math.Random(seed);
  return ChatGroup(
    name: 'g$axis',
    about: '',
    members: [
      for (var i = 0; i < size; i++)
        StoredExchange(
          id: i,
          context: const [],
          contextText: '',
          replyText: 'r$i',
          vector: VectorMath.normalise([
            for (var d = 0; d < dims; d++)
              (d == axis ? 1.0 : 0.0) + (random.nextDouble() - 0.5) * 0.3,
          ]),
        ),
    ],
  );
}

double distance((double, double) a, (double, double) b) =>
    math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));

void main() {
  test('one point per reply, every one inside the square', () {
    final groups = [group(0, 30), group(3, 20, seed: 1), group(7, 10, seed: 2)];
    final map = GroupMap.of(groups);
    expect(map.points.map((p) => p.length), [30, 20, 10]);
    expect(map.centres, hasLength(3));
    for (final (x, y) in map.points.expand((p) => p)) {
      expect(x, inInclusiveRange(-1, 1));
      expect(y, inInclusiveRange(-1, 1));
    }
  });

  test('groups land apart, and each reply near its own group', () {
    final groups = [group(0, 30), group(3, 30, seed: 1), group(7, 30, seed: 2)];
    final map = GroupMap.of(groups);
    for (var g = 0; g < 3; g++) {
      for (final p in map.points[g]) {
        final own = distance(p, map.centres[g]);
        for (var other = 0; other < 3; other++) {
          if (other == g) continue;
          expect(
            own,
            lessThan(distance(p, map.centres[other])),
            reason: 'a reply of group $g sits nearer another group',
          );
        }
      }
    }
  });

  test('two groups still get a second direction to spread along', () {
    final map = GroupMap.of([group(0, 25), group(5, 25, seed: 1)]);
    final ys = map.points.expand((p) => p).map((p) => p.$2).toSet();
    expect(ys.length, greaterThan(10), reason: 'not all on one line');
    expect(
      (map.centres[0].$1 - map.centres[1].$1).abs(),
      greaterThan(1),
      reason: 'the two groups sit at opposite ends of the first axis',
    );
  });

  test('a single group, and no groups, do not break it', () {
    expect(GroupMap.of([group(0, 12)]).points.single, hasLength(12));
    expect(GroupMap.of(const []).points, isEmpty);
  });

  test('is the same every time', () {
    final groups = [group(0, 20), group(2, 20, seed: 4), group(9, 5, seed: 5)];
    expect(GroupMap.of(groups).points, GroupMap.of(groups).points);
  });
}
