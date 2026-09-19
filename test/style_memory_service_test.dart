import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:replylikeme/models/chat_turn.dart';
import 'package:replylikeme/models/exchange.dart';
import 'package:replylikeme/models/stored_exchange.dart';
import 'package:replylikeme/services/exchange_store.dart';
import 'package:replylikeme/services/openai_exception.dart';
import 'package:replylikeme/services/openai_service.dart';
import 'package:replylikeme/services/style_memory_service.dart';
import 'package:replylikeme/services/vector_math.dart';
import 'package:replylikeme/services/whatsapp_parser.dart';

/// In-memory stand-in for the sqflite store.
class FakeStore implements ExchangeStore {
  List<StoredExchange> rows = [];
  StyleMemoryStats? savedStats;
  int replaceCalls = 0;

  @override
  Future<void> replaceAll(
    List<StoredExchange> exchanges, {
    required StyleMemoryStats stats,
  }) async {
    replaceCalls++;
    rows = List.of(exchanges);
    savedStats = stats;
  }

  @override
  Future<StyleMemoryStats?> stats() async => savedStats;

  @override
  Future<int> count() async => rows.length;

  @override
  Future<List<StoredExchange>> all() async => rows;

  @override
  Future<List<ScoredExchange>> mostSimilar(
    Float32List query, {
    int limit = 8,
  }) async {
    final vectors = rows.map((r) => r.vector).toList(growable: false);
    return VectorMath.topK(query, vectors, limit)
        .map(
          (i) => ScoredExchange(
            exchange: rows[i],
            similarity: VectorMath.dot(query, vectors[i]),
          ),
        )
        .toList();
  }

  @override
  Future<void> deleteEverything() async {
    rows = [];
    savedStats = null;
  }
}

ChatTurn turn(String sender, String text) =>
    ChatTurn(sender: sender, text: text, messageCount: 1);

Exchange exchange(String theirText, String myReply) => Exchange(
  context: [turn('Sam', theirText)],
  reply: turn('Robin', myReply),
);

void main() {
  /// Returns a deterministic vector per input so retrieval is checkable.
  OpenAiService embedderThat(
    List<double> Function(String input) vectorFor, {
    void Function(int batchSize)? onBatch,
  }) => OpenAiService(
    apiKey: 'sk-test-0123456789abcdefghij',
    maxRetries: 0,
    client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final inputs = (body['input']! as List).cast<String>();
      onBatch?.call(inputs.length);
      return http.Response(
        jsonEncode({
          'data': [
            for (var i = 0; i < inputs.length; i++)
              {'index': i, 'embedding': vectorFor(inputs[i])},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );

  group('build', () {
    test('embeds every exchange and stores unit vectors', () async {
      final store = FakeStore();
      final service = StyleMemoryService(
        openai: embedderThat((input) => [input.length.toDouble(), 1]),
        store: store,
      );

      final stats = await service.build(
        exchanges: [exchange('pub?', 'go on then'), exchange('when', 'half 8')],
        myName: 'Robin',
        theirName: 'Sam',
        embeddingModel: 'text-embedding-3-small',
        dimensions: 2,
      );

      expect(store.rows, hasLength(2));
      expect(stats.exchangeCount, 2);
      expect(stats.dimensions, 2);
      expect(stats.myName, 'Robin');
      expect(stats.theirName, 'Sam');
      for (final row in store.rows) {
        expect(VectorMath.dot(row.vector, row.vector), closeTo(1.0, 1e-6));
      }
      expect(store.rows.first.replyText, 'go on then');
      expect(store.rows.first.contextText, 'Sam: pub?');
    });

    test('batches large imports and reports progress', () async {
      final store = FakeStore();
      final batchSizes = <int>[];
      final service = StyleMemoryService(
        openai: embedderThat(
          (input) => [1, 0],
          onBatch: batchSizes.add,
        ),
        store: store,
      );

      final progress = <StyleMemoryProgress>[];
      await service.build(
        exchanges: [
          for (var i = 0; i < 200; i++) exchange('q$i', 'a$i'),
        ],
        myName: 'Robin',
        theirName: 'Sam',
        embeddingModel: 'text-embedding-3-small',
        dimensions: 2,
        onProgress: progress.add,
      );

      expect(batchSizes, [96, 96, 8]);
      expect(store.rows, hasLength(200));
      expect(progress.first.embedded, 0);
      expect(progress.map((p) => p.embedded), contains(96));
      expect(progress.last.embedded, 200);
      expect(progress.last.fraction, 1.0);
    });

    test('explains an export with none of my replies in it', () async {
      final store = FakeStore();
      final service = StyleMemoryService(
        openai: embedderThat((input) => [1, 0]),
        store: store,
      );
      await expectLater(
        service.build(
          exchanges: const [],
          myName: 'Robin',
          theirName: 'Sam',
          embeddingModel: 'text-embedding-3-small',
          dimensions: 2,
        ),
        throwsA(
          isA<OpenAiException>().having(
            (e) => e.message,
            'message',
            contains('right name for yourself'),
          ),
        ),
      );
      expect(store.replaceCalls, 0);
    });

    test('cancelling leaves the existing memory untouched', () async {
      final store = FakeStore()
        ..rows = [
          StoredExchange(
            id: 1,
            context: [turn('Sam', 'old')],
            contextText: 'Sam: old',
            replyText: 'old reply',
            vector: VectorMath.normalise([1, 0]),
          ),
        ];
      var batches = 0;
      final service = StyleMemoryService(
        openai: embedderThat((input) => [1, 0], onBatch: (_) => batches++),
        store: store,
      );

      await expectLater(
        service.build(
          exchanges: [for (var i = 0; i < 200; i++) exchange('q$i', 'a$i')],
          myName: 'Robin',
          theirName: 'Sam',
          embeddingModel: 'text-embedding-3-small',
          dimensions: 2,
          isCancelled: () => batches >= 1,
        ),
        throwsA(isA<StyleMemoryCancelled>()),
      );
      expect(store.replaceCalls, 0);
      expect(store.rows.single.replyText, 'old reply');
    });
  });

  group('retrieve', () {
    test('returns the closest stored exchanges, best first', () async {
      final store = FakeStore();
      // Embed on the first word, so "pub" queries match the "pub" exchange.
      List<double> vectorFor(String input) =>
          input.contains('pub') ? [1, 0] : [0, 1];

      final service = StyleMemoryService(
        openai: embedderThat(vectorFor),
        store: store,
      );
      await service.build(
        exchanges: [exchange('pub tonight?', 'go on then'), exchange('cinema?', 'nah')],
        myName: 'Robin',
        theirName: 'Sam',
        embeddingModel: 'text-embedding-3-small',
        dimensions: 2,
      );

      final hits = await service.retrieve(
        context: [turn('Sam', 'pub later')],
        embeddingModel: 'text-embedding-3-small',
        dimensions: 2,
        limit: 2,
      );

      expect(hits.first.exchange.replyText, 'go on then');
      expect(hits.first.similarity, closeTo(1.0, 1e-6));
      expect(hits.last.exchange.replyText, 'nah');
    });

    test('returns nothing, without calling out, on an empty memory', () async {
      var calls = 0;
      final service = StyleMemoryService(
        openai: embedderThat((input) {
          calls++;
          return [1, 0];
        }),
        store: FakeStore(),
      );
      final hits = await service.retrieve(
        context: [turn('Sam', 'anything')],
        embeddingModel: 'text-embedding-3-small',
        dimensions: 2,
        limit: 8,
      );
      expect(hits, isEmpty);
      expect(calls, 0);
    });
  });

  group('estimate', () {
    test('scales with the amount of text to embed', () async {
      final service = StyleMemoryService(
        openai: embedderThat((input) => [1, 0]),
        store: FakeStore(),
      );
      final small = service.estimate([exchange('hi', 'yo')]);
      final large = service.estimate([
        for (var i = 0; i < 100; i++) exchange('a much longer question $i', 'a$i'),
      ]);
      expect(small.exchangeCount, 1);
      expect(large.exchangeCount, 100);
      expect(large.estimatedTokens, greaterThan(small.estimatedTokens));
      expect(large.estimatedUsd, greaterThan(0));
    });
  });

  group('exchangesFrom', () {
    test('reads a real export end to end', () async {
      final chat = WhatsAppParser.parse(
        File('test/fixtures/android_export.txt').readAsStringSync(),
      );
      final service = StyleMemoryService(
        openai: embedderThat((input) => [1, 0]),
        store: FakeStore(),
      );
      final exchanges = service.exchangesFrom(
        chat,
        myName: 'Robin',
        contextTurns: 10,
      );
      expect(exchanges, hasLength(4));
      expect(exchanges.every((e) => e.reply.sender == 'Robin'), isTrue);
    });
  });
}
