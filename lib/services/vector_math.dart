import 'dart:math' as math;
import 'dart:typed_data';

/// Vector helpers for the on-device style-memory search.
///
/// Embeddings are stored unit-length, which turns cosine similarity into a
/// plain dot product — the whole search is then one pass of multiply-add over
/// a few thousand short vectors, fast enough to run on the UI isolate.
///
/// Pure Dart, no Flutter, so it is unit-testable.
class VectorMath {
  const VectorMath._();

  /// Scales [values] to unit length. A zero vector is returned unchanged,
  /// since it has no direction to preserve.
  static Float32List normalise(List<double> values) {
    final out = Float32List(values.length);
    var sumOfSquares = 0.0;
    for (var i = 0; i < values.length; i++) {
      sumOfSquares += values[i] * values[i];
    }
    if (sumOfSquares == 0) return out;
    final scale = 1.0 / math.sqrt(sumOfSquares);
    for (var i = 0; i < values.length; i++) {
      out[i] = values[i] * scale;
    }
    return out;
  }

  /// Dot product, which equals cosine similarity for unit-length inputs.
  ///
  /// Throws [ArgumentError] on a length mismatch: that means the embedding
  /// model or dimension count changed and the memory needs rebuilding.
  static double dot(Float32List a, Float32List b) {
    if (a.length != b.length) {
      throw ArgumentError(
        'vector length mismatch (${a.length} vs ${b.length}) - the style '
        'memory was built with a different embedding model or dimension count',
      );
    }
    var total = 0.0;
    for (var i = 0; i < a.length; i++) {
      total += a[i] * b[i];
    }
    return total;
  }

  /// Little-endian float32 encoding for the sqflite BLOB column.
  static Uint8List encode(Float32List vector) {
    final bytes = Uint8List(vector.length * 4);
    final view = ByteData.view(bytes.buffer);
    for (var i = 0; i < vector.length; i++) {
      view.setFloat32(i * 4, vector[i], Endian.little);
    }
    return bytes;
  }

  /// Inverse of [encode].
  static Float32List decode(Uint8List bytes) {
    if (bytes.lengthInBytes % 4 != 0) {
      throw ArgumentError(
        'stored vector is ${bytes.lengthInBytes} bytes, not a whole number of '
        'float32 values',
      );
    }
    final view = ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    final out = Float32List(bytes.lengthInBytes ~/ 4);
    for (var i = 0; i < out.length; i++) {
      out[i] = view.getFloat32(i * 4, Endian.little);
    }
    return out;
  }

  /// Indices of the [k] vectors most similar to [query], best first.
  ///
  /// Keeps only the running top-k rather than sorting every candidate, so a
  /// large memory costs one pass and k comparisons per item.
  static List<int> topK(Float32List query, List<Float32List> vectors, int k) {
    if (k < 1 || vectors.isEmpty) return const [];
    final best = <({int index, double score})>[];
    for (var i = 0; i < vectors.length; i++) {
      final score = dot(query, vectors[i]);
      if (best.length < k) {
        best.add((index: i, score: score));
        best.sort((a, b) => b.score.compareTo(a.score));
      } else if (score > best.last.score) {
        best
          ..removeLast()
          ..add((index: i, score: score))
          ..sort((a, b) => b.score.compareTo(a.score));
      }
    }
    return best.map((e) => e.index).toList(growable: false);
  }
}
