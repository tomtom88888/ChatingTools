import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:replylikeme/services/vector_math.dart';

void main() {
  group('normalise', () {
    test('scales to unit length', () {
      final unit = VectorMath.normalise([3, 4]);
      expect(unit[0], closeTo(0.6, 1e-6));
      expect(unit[1], closeTo(0.8, 1e-6));
      expect(VectorMath.dot(unit, unit), closeTo(1.0, 1e-6));
    });

    test('leaves a zero vector alone instead of dividing by zero', () {
      final zero = VectorMath.normalise([0, 0, 0]);
      expect(zero, everyElement(0.0));
    });
  });

  group('dot', () {
    test('is cosine similarity for unit vectors', () {
      final a = VectorMath.normalise([1, 0]);
      final b = VectorMath.normalise([0, 1]);
      final c = VectorMath.normalise([1, 1]);
      expect(VectorMath.dot(a, a), closeTo(1.0, 1e-6));
      expect(VectorMath.dot(a, b), closeTo(0.0, 1e-6));
      expect(VectorMath.dot(a, c), closeTo(0.70710678, 1e-6));
    });

    test('explains a dimension mismatch instead of reading past the end', () {
      expect(
        () => VectorMath.dot(Float32List(4), Float32List(8)),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('different embedding model'),
          ),
        ),
      );
    });
  });

  group('encode/decode', () {
    test('round-trips a vector', () {
      final original = VectorMath.normalise([0.1, -0.25, 3, 0, 42.5]);
      final restored = VectorMath.decode(VectorMath.encode(original));
      expect(restored.length, original.length);
      for (var i = 0; i < original.length; i++) {
        expect(restored[i], closeTo(original[i], 1e-6));
      }
    });

    test('uses four bytes per value', () {
      expect(VectorMath.encode(Float32List(512)).lengthInBytes, 2048);
    });

    test('rejects a truncated blob', () {
      expect(
        () => VectorMath.decode(Uint8List(7)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('topK', () {
    final vectors = [
      VectorMath.normalise([1, 0]), // 0: identical to the query
      VectorMath.normalise([0, 1]), // 1: orthogonal
      VectorMath.normalise([-1, 0]), // 2: opposite
      VectorMath.normalise([0.9, 0.1]), // 3: close
    ];

    test('returns the closest first', () {
      final query = VectorMath.normalise([1, 0]);
      expect(VectorMath.topK(query, vectors, 2), [0, 3]);
    });

    test('never returns more than it has', () {
      final query = VectorMath.normalise([1, 0]);
      expect(VectorMath.topK(query, vectors, 99), hasLength(4));
      expect(VectorMath.topK(query, vectors, 99).last, 2);
    });

    test('handles degenerate arguments', () {
      final query = VectorMath.normalise([1, 0]);
      expect(VectorMath.topK(query, vectors, 0), isEmpty);
      expect(VectorMath.topK(query, const [], 5), isEmpty);
    });
  });
}
