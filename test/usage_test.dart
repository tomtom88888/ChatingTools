import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:replylikeme/models/api_usage.dart';
import 'package:replylikeme/models/reply_suggestion.dart';
import 'package:replylikeme/models/suggestion_feedback.dart';
import 'package:replylikeme/services/openai_service.dart';
import 'package:replylikeme/services/pricing.dart';
import 'package:replylikeme/services/usage_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('reading usage off responses', () {
    test('chat completions report input and output', () {
      final usage = ApiUsage.fromResponse(
        {
          'usage': {'prompt_tokens': 120, 'completion_tokens': 30},
        },
        kind: UsageKind.generation,
        model: 'm',
      );
      expect(usage!.inputTokens, 120);
      expect(usage.outputTokens, 30);
    });

    test('embeddings report only a total', () {
      final usage = ApiUsage.fromResponse(
        {
          'usage': {'total_tokens': 900},
        },
        kind: UsageKind.embedding,
        model: 'm',
      );
      expect(usage!.inputTokens, 900);
      expect(usage.outputTokens, 0);
    });

    test('a response without usage reports nothing', () {
      expect(
        ApiUsage.fromResponse(const {}, kind: UsageKind.vision, model: 'm'),
        isNull,
      );
    });

    test('the client tells its listener about every call', () async {
      final seen = <ApiUsage>[];
      final service = OpenAiService(
        apiKey: 'sk-test-0123456789abcdefghij',
        maxRetries: 0,
        onUsage: seen.add,
        client: MockClient((request) async {
          final isEmbedding = request.url.path.endsWith('/embeddings');
          return http.Response(
            jsonEncode(
              isEmbedding
                  ? {
                      'data': [
                        {
                          'index': 0,
                          'embedding': [1, 0],
                        },
                      ],
                      'usage': {'prompt_tokens': 5, 'total_tokens': 5},
                    }
                  : {
                      'choices': [
                        {
                          'message': {'content': 'hi'},
                        },
                      ],
                      'usage': {'prompt_tokens': 50, 'completion_tokens': 2},
                    },
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await service.embed(['x'], model: 'text-embedding-3-small');
      await service.chat(
        model: 'gpt',
        messages: const [
          {'role': 'user', 'content': 'x'},
        ],
      );
      expect(seen.map((u) => (u.kind, u.inputTokens, u.outputTokens)), [
        (UsageKind.embedding, 5, 0),
        (UsageKind.generation, 50, 2),
      ]);
    });
  });

  group('the monthly tally', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('adds calls up per month and kind, newest month first', () async {
      const store = UsageStore();
      const call = ApiUsage(
        kind: UsageKind.generation,
        model: 'm',
        inputTokens: 100,
        outputTokens: 10,
      );
      await store.record(call, at: DateTime(2026, 8, 30));
      await store.record(call, at: DateTime(2026, 9, 1));
      await store.record(call, at: DateTime(2026, 9, 2));

      final months = await store.load();
      expect(months.map((m) => m.month), ['2026-09', '2026-08']);
      final september = months.first[UsageKind.generation];
      expect(september.requests, 2);
      expect(september.inputTokens, 200);
      expect(september.outputTokens, 20);
      expect(months.first[UsageKind.vision].requests, 0);
    });

    test('keeps a year of months', () async {
      const store = UsageStore();
      for (var m = 1; m <= 15; m++) {
        await store.record(
          const ApiUsage(kind: UsageKind.embedding, model: 'e', inputTokens: 1),
          at: DateTime(2025, m, 1),
        );
      }
      final months = await store.load();
      expect(months, hasLength(UsageStore.keepMonths));
      expect(months.first.month, '2026-03');
    });
  });

  group('costing a month', () {
    final month = const MonthlyUsage(month: '2026-09')
        .plus(
          const ApiUsage(
            kind: UsageKind.embedding,
            model: 'e',
            inputTokens: 1000000,
          ),
        )
        .plus(
          const ApiUsage(
            kind: UsageKind.generation,
            model: 'g',
            inputTokens: 1000000,
            outputTokens: 500000,
          ),
        );

    test('prices embeddings, and flags chat calls it cannot price', () {
      final cost = Pricing.costOf(
        month,
        embeddingModel: 'text-embedding-3-small',
      );
      expect(cost.usd, closeTo(0.02, 1e-9));
      expect(cost.complete, isFalse);
    });

    test('adds chat calls once their prices are known', () {
      final cost = Pricing.costOf(
        month,
        embeddingModel: 'text-embedding-3-small',
        chatInputUsdPerMillion: 2,
        chatOutputUsdPerMillion: 8,
      );
      expect(cost.usd, closeTo(0.02 + 2 + 4, 1e-9));
      expect(cost.complete, isTrue);
    });
  });

  test('feedback sums up picks, topic changes and tweaks', () {
    final summary = FeedbackSummary.of([
      SuggestionFeedback(
        at: DateTime(2026),
        shownKinds: const [SuggestionKind.reply, SuggestionKind.newTopic],
        pickedIndex: 1,
        refinements: const ['shorter', 'shorter'],
        saved: true,
      ),
      SuggestionFeedback(
        at: DateTime(2026),
        shownKinds: const [SuggestionKind.reply, SuggestionKind.newTopic],
        pickedIndex: 0,
      ),
      SuggestionFeedback(
        at: DateTime(2026),
        shownKinds: const [SuggestionKind.reply],
        refinements: const ['warmer'],
      ),
    ]);
    expect(summary.sets, 3);
    expect(summary.picked, 2);
    expect(summary.pickRate, closeTo(2 / 3, 1e-9));
    expect(summary.newTopicRate, 0.5);
    expect(summary.pickedByPosition, {1: 1, 0: 1});
    expect(summary.refinements, {'shorter': 2, 'warmer': 1});
    expect(summary.saved, 1);
  });
}
