import 'dart:typed_data';

import '../models/stored_exchange.dart';

/// The local style memory.
///
/// An interface rather than a concrete class so the services above it can be
/// unit-tested without a device database.
abstract interface class ExchangeStore {
  /// Replaces the whole memory in one transaction. Training is all-or-nothing:
  /// a half-embedded import would silently skew every retrieval.
  Future<void> replaceAll(
    List<StoredExchange> exchanges, {
    required StyleMemoryStats stats,
  });

  /// What the current memory was built from, or `null` if there isn't one.
  Future<StyleMemoryStats?> stats();

  Future<int> count();

  /// The [limit] stored exchanges whose context is closest to [query].
  Future<List<ScoredExchange>> mostSimilar(Float32List query, {int limit = 8});

  /// Everything, oldest first — used to build the fine-tuning dataset.
  Future<List<StoredExchange>> all();

  /// Wipes the memory and its metadata.
  Future<void> deleteEverything();
}
