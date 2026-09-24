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
  /// Keeps the running top-k in a min-heap, so a memory of n vectors costs one
  /// pass of dot products plus O(n log k) bookkeeping, rather than re-sorting
  /// the shortlist every time it changes.
  static List<int> topK(Float32List query, List<Float32List> vectors, int k) {
    final scored = topKScored(query, vectors, k);
    return scored.map((e) => e.index).toList(growable: false);
  }

  /// As [topK], with each index's score.
  static List<({int index, double score})> topKScored(
    Float32List query,
    List<Float32List> vectors,
    int k,
  ) {
    if (k < 1 || vectors.isEmpty) return const [];
    final heap = _MinHeap(k);
    for (var i = 0; i < vectors.length; i++) {
      heap.offer(i, dot(query, vectors[i]));
    }
    return heap.drainBestFirst();
  }
}

/// A fixed-capacity min-heap of (index, score): the root is the weakest of
/// the best seen so far, so a better candidate replaces it in O(log k).
class _MinHeap {
  _MinHeap(this.capacity);

  final int capacity;
  final List<int> _index = [];
  final List<double> _score = [];

  void offer(int index, double score) {
    if (_index.length < capacity) {
      _index.add(index);
      _score.add(score);
      _siftUp(_index.length - 1);
    } else if (score > _score[0]) {
      _index[0] = index;
      _score[0] = score;
      _siftDown(0);
    }
  }

  void _swap(int a, int b) {
    final i = _index[a];
    _index[a] = _index[b];
    _index[b] = i;
    final s = _score[a];
    _score[a] = _score[b];
    _score[b] = s;
  }

  void _siftUp(int at) {
    while (at > 0) {
      final parent = (at - 1) >> 1;
      if (_score[at] >= _score[parent]) return;
      _swap(at, parent);
      at = parent;
    }
  }

  void _siftDown(int at) {
    final n = _index.length;
    while (true) {
      final left = 2 * at + 1;
      final right = left + 1;
      var smallest = at;
      if (left < n && _score[left] < _score[smallest]) smallest = left;
      if (right < n && _score[right] < _score[smallest]) smallest = right;
      if (smallest == at) return;
      _swap(at, smallest);
      at = smallest;
    }
  }

  /// Everything held, best first. Ties keep the earlier index first, which
  /// matches the order a stable sort would give.
  List<({int index, double score})> drainBestFirst() {
    final out = [
      for (var i = 0; i < _index.length; i++)
        (index: _index[i], score: _score[i]),
    ];
    out.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.index.compareTo(b.index);
    });
    return out;
  }
}
