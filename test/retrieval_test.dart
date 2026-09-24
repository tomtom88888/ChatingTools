import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:replylikeme/models/stored_exchange.dart';
import 'package:replylikeme/services/retrieval.dart';
import 'package:replylikeme/services/vector_math.dart';

StoredExchange row(int id, List<double> v, String reply, {DateTime? at}) =>
    StoredExchange(
      id: id,
      context: const [],
      contextText: 'ctx $id',
      replyText: reply,
      vector: VectorMath.normalise(v),
      timestamp: at,
    );

void main() {
  final query = VectorMath.normalise([1, 0, 0]);

  group('topK', () {
    test('agrees with a full sort on random data', () {
      final random = math.Random(7);
      final vectors = [
        for (var i = 0; i < 500; i++)
          VectorMath.normalise([
            for (var d = 0; d < 16; d++) random.nextDouble() - 0.5,
          ]),
      ];
      final q = vectors[3];
      final expected = List<int>.generate(vectors.length, (i) => i)
        ..sort(
          (a, b) => VectorMath.dot(
            q,
            vectors[b],
          ).compareTo(VectorMath.dot(q, vectors[a])),
        );
      expect(VectorMath.topK(q, vectors, 25), expected.take(25).toList());
    });
  });

  group('select', () {
    test('passes over a reply already chosen', () {
      final rows = [
        row(1, [1, 0.01, 0], 'ok see you then'),
        row(2, [1, 0.02, 0], 'OK  see you then'),
        row(3, [1, 0.03, 0], 'ok see you then'),
        row(4, [0.8, 0.6, 0], 'running late sorry'),
      ];
      final picked = const Retrieval().select(query, rows, limit: 3);
      expect(picked.map((e) => e.exchange.id), unorderedEquals([1, 4]));
    });

    test('prefers variety over a near-copy of the best match', () {
      final rows = [
        row(1, [0.95, 0.31, 0], 'a'),
        row(2, [0.95, 0.30, 0.05], 'b'), // almost the same as 1
        row(3, [0.9, -0.43, 0], 'c'), // nearly as relevant, and different
      ];
      final varied = const Retrieval().select(query, rows, limit: 2);
      final ids = varied.map((e) => e.exchange.id).toSet();
      expect(ids, contains(3));
      expect(ids.intersection({1, 2}), hasLength(1), reason: 'not both twins');

      // With the variety term off it is plain similarity ranking.
      final plain = const Retrieval(
        relevanceWeight: 1,
      ).select(query, rows, limit: 2);
      expect(plain.map((e) => e.exchange.id).toSet(), {1, 2});
    });

    test('recency breaks a near tie in favour of the recent reply', () {
      final now = DateTime(2026, 9, 24);
      final rows = [
        row(1, [1, 0.001, 0], 'old', at: DateTime(2019, 1, 1)),
        row(2, [1, 0.002, 0], 'new', at: DateTime(2026, 9, 1)),
      ];
      final picked = const Retrieval().select(query, rows, limit: 1, now: now);
      expect(picked.single.exchange.replyText, 'new');
    });

    test('recency never outweighs a clearly better match', () {
      final now = DateTime(2026, 9, 24);
      final rows = [
        row(1, [1, 0, 0], 'old but right', at: DateTime(2019, 1, 1)),
        row(2, [0.7, 0.7, 0], 'new but off', at: DateTime(2026, 9, 20)),
      ];
      final picked = const Retrieval().select(query, rows, limit: 1, now: now);
      expect(picked.single.exchange.replyText, 'old but right');
    });

    test('reports the raw similarity, best first', () {
      final rows = [
        row(1, [0.6, 0.8, 0], 'x'),
        row(2, [1, 0, 0], 'y'),
      ];
      final picked = const Retrieval().select(query, rows, limit: 2);
      expect(picked.first.exchange.id, 2);
      expect(picked.first.similarity, closeTo(1, 1e-6));
      expect(picked.last.similarity, closeTo(0.6, 1e-6));
    });

    test('a vector of another length is an error, not a silent miss', () {
      expect(
        () => const Retrieval().select(query, [
          StoredExchange(
            id: 1,
            context: const [],
            contextText: '',
            replyText: 'x',
            vector: Float32List(2),
          ),
        ], limit: 1),
        throwsArgumentError,
      );
    });
  });

  group('contentHash', () {
    BigInt fnv1a64(List<int> bytes) {
      final prime = BigInt.parse('100000001b3', radix: 16);
      final mask = (BigInt.one << 64) - BigInt.one;
      var h = BigInt.parse('cbf29ce484222325', radix: 16);
      for (final b in bytes) {
        h = ((h ^ BigInt.from(b)) * prime) & mask;
      }
      return h;
    }

    test('is 64-bit FNV-1a of context, NUL, reply', () {
      for (final (context, reply) in [
        ('', ''),
        ('Sam: pub?', 'go on then'),
        ('מאיה: מה קורה', 'בסדר 😂'),
      ]) {
        final expected = fnv1a64(
          utf8.encode('$context\u0000$reply'),
        ).toRadixString(16).padLeft(16, '0');
        expect(StoredExchange.contentHash(context, reply), expected);
      }
    });

    test('tells apart exchanges that only differ in where the split is', () {
      expect(
        StoredExchange.contentHash('ab', 'c'),
        isNot(StoredExchange.contentHash('a', 'bc')),
      );
    });
  });
}
