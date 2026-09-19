import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/chat_turn.dart';
import '../models/stored_exchange.dart';
import 'exchange_store.dart';
import 'vector_math.dart';

/// The on-device style memory, backed by sqflite.
///
/// Vectors are stored as little-endian float32 blobs and kept unit-length, so
/// similarity search is a dot product. Rows are cached in memory after the
/// first read: at the default 512 dimensions a few thousand exchanges is a
/// handful of megabytes, and searching in memory avoids decoding every blob on
/// every keystroke-speed query.
class SqfliteExchangeStore implements ExchangeStore {
  SqfliteExchangeStore({this.databaseName = 'replylikeme_style_memory.db'});

  final String databaseName;

  static const int _schemaVersion = 1;

  Database? _database;
  List<StoredExchange>? _cache;

  Future<Database> _open() async {
    final existing = _database;
    if (existing != null) return existing;
    final path = p.join(await getDatabasesPath(), databaseName);
    final database = await openDatabase(
      path,
      version: _schemaVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE exchanges (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            context_json  TEXT    NOT NULL,
            context_text  TEXT    NOT NULL,
            reply         TEXT    NOT NULL,
            ts            INTEGER,
            vector        BLOB    NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE meta (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
    _database = database;
    return database;
  }

  @override
  Future<void> replaceAll(
    List<StoredExchange> exchanges, {
    required StyleMemoryStats stats,
  }) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete('exchanges');
      final batch = txn.batch();
      for (final exchange in exchanges) {
        batch.insert('exchanges', {
          'context_json': jsonEncode(
            exchange.context.map((t) => t.toJson()).toList(),
          ),
          'context_text': exchange.contextText,
          'reply': exchange.replyText,
          'ts': exchange.timestamp?.millisecondsSinceEpoch,
          'vector': VectorMath.encode(exchange.vector),
        });
      }
      await batch.commit(noResult: true);

      await txn.delete('meta');
      await txn.insert('meta', {
        'key': 'stats',
        'value': jsonEncode({
          'exchangeCount': stats.exchangeCount,
          'embeddingModel': stats.embeddingModel,
          'dimensions': stats.dimensions,
          'myName': stats.myName,
          'theirName': stats.theirName,
          'builtAt': stats.builtAt.toIso8601String(),
        }),
      });
    });
    _cache = null;
  }

  @override
  Future<StyleMemoryStats?> stats() async {
    final db = await _open();
    final rows = await db.query(
      'meta',
      where: 'key = ?',
      whereArgs: ['stats'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.first['value']! as String);
    if (decoded is! Map) return null;
    final builtAt = DateTime.tryParse(decoded['builtAt'] as String? ?? '');
    return StyleMemoryStats(
      exchangeCount: (decoded['exchangeCount'] as num?)?.toInt() ?? 0,
      embeddingModel: decoded['embeddingModel'] as String? ?? '',
      dimensions: (decoded['dimensions'] as num?)?.toInt() ?? 0,
      myName: decoded['myName'] as String? ?? '',
      theirName: decoded['theirName'] as String? ?? '',
      builtAt: builtAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  Future<int> count() async {
    final cached = _cache;
    if (cached != null) return cached.length;
    final db = await _open();
    final result = await db.rawQuery('SELECT COUNT(*) AS n FROM exchanges');
    return (result.first['n'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<List<StoredExchange>> all() async {
    final cached = _cache;
    if (cached != null) return cached;
    final db = await _open();
    final rows = await db.query('exchanges', orderBy: 'id ASC');
    final exchanges = rows.map(_fromRow).toList(growable: false);
    _cache = exchanges;
    return exchanges;
  }

  @override
  Future<List<ScoredExchange>> mostSimilar(
    Float32List query, {
    int limit = 8,
  }) async {
    final exchanges = await all();
    if (exchanges.isEmpty || limit < 1) return const [];

    final vectors = exchanges.map((e) => e.vector).toList(growable: false);
    // A dimension mismatch means the memory predates a settings change; let
    // VectorMath's ArgumentError surface so the UI can say "rebuild it".
    final indices = VectorMath.topK(query, vectors, limit);
    return indices
        .map(
          (i) => ScoredExchange(
            exchange: exchanges[i],
            similarity: VectorMath.dot(query, vectors[i]),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> deleteEverything() async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete('exchanges');
      await txn.delete('meta');
    });
    _cache = null;
    await db.close();
    _database = null;
    // Drop the file too, so "delete all my data" leaves nothing behind.
    await deleteDatabase(p.join(await getDatabasesPath(), databaseName));
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
    _cache = null;
  }

  static StoredExchange _fromRow(Map<String, Object?> row) {
    final contextJson = jsonDecode(row['context_json']! as String);
    final context = contextJson is List
        ? contextJson
              .whereType<Map<String, Object?>>()
              .map(ChatTurn.fromJson)
              .toList(growable: false)
        : const <ChatTurn>[];
    final ts = row['ts'];
    return StoredExchange(
      id: (row['id'] as num?)?.toInt() ?? -1,
      context: context,
      contextText: row['context_text']! as String,
      replyText: row['reply']! as String,
      vector: VectorMath.decode(row['vector']! as Uint8List),
      timestamp: ts is num
          ? DateTime.fromMillisecondsSinceEpoch(ts.toInt())
          : null,
    );
  }
}
