/// What an API call was for, so spending can be broken down.
enum UsageKind {
  /// Training the style memory, and embedding each conversation to search it.
  embedding,

  /// Reading a screenshot.
  vision,

  /// Writing and tweaking replies.
  generation;

  String get label => switch (this) {
    embedding => 'Fingerprinting',
    vision => 'Reading screenshots',
    generation => 'Writing replies',
  };
}

/// The tokens one API call used, as OpenAI reported them.
class ApiUsage {
  const ApiUsage({
    required this.kind,
    required this.model,
    required this.inputTokens,
    this.outputTokens = 0,
  });

  final UsageKind kind;
  final String model;
  final int inputTokens;
  final int outputTokens;

  /// Reads the `usage` object of an OpenAI response, or `null` if it has none.
  static ApiUsage? fromResponse(
    Map<String, Object?> json, {
    required UsageKind kind,
    required String model,
  }) {
    final usage = json['usage'];
    if (usage is! Map) return null;
    int n(String key) => (usage[key] as num?)?.toInt() ?? 0;
    final input = n('prompt_tokens') + n('input_tokens');
    final output = n('completion_tokens') + n('output_tokens');
    final total = n('total_tokens');
    if (input == 0 && output == 0 && total == 0) return null;
    return ApiUsage(
      kind: kind,
      model: model,
      inputTokens: input == 0 && output == 0 ? total : input,
      outputTokens: output,
    );
  }
}

/// Running totals for one kind of call in one month.
class UsageTotals {
  const UsageTotals({
    this.requests = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
  });

  final int requests;
  final int inputTokens;
  final int outputTokens;

  UsageTotals plus(ApiUsage usage) => UsageTotals(
    requests: requests + 1,
    inputTokens: inputTokens + usage.inputTokens,
    outputTokens: outputTokens + usage.outputTokens,
  );

  UsageTotals operator +(UsageTotals other) => UsageTotals(
    requests: requests + other.requests,
    inputTokens: inputTokens + other.inputTokens,
    outputTokens: outputTokens + other.outputTokens,
  );

  Map<String, Object?> toJson() => {
    'requests': requests,
    'in': inputTokens,
    'out': outputTokens,
  };

  factory UsageTotals.fromJson(Object? raw) {
    if (raw is! Map) return const UsageTotals();
    int n(String key) => (raw[key] as num?)?.toInt() ?? 0;
    return UsageTotals(
      requests: n('requests'),
      inputTokens: n('in'),
      outputTokens: n('out'),
    );
  }
}

/// One month of API usage, by kind.
class MonthlyUsage {
  const MonthlyUsage({required this.month, this.byKind = const {}});

  /// `yyyy-mm`.
  final String month;
  final Map<UsageKind, UsageTotals> byKind;

  static String keyFor(DateTime at) =>
      '${at.year.toString().padLeft(4, '0')}-'
      '${at.month.toString().padLeft(2, '0')}';

  UsageTotals operator [](UsageKind kind) =>
      byKind[kind] ?? const UsageTotals();

  UsageTotals get total =>
      byKind.values.fold(const UsageTotals(), (sum, t) => sum + t);

  bool get isEmpty => total.requests == 0;

  MonthlyUsage plus(ApiUsage usage) => MonthlyUsage(
    month: month,
    byKind: {...byKind, usage.kind: this[usage.kind].plus(usage)},
  );

  Map<String, Object?> toJson() => {
    for (final entry in byKind.entries) entry.key.name: entry.value.toJson(),
  };

  factory MonthlyUsage.fromJson(String month, Object? raw) {
    if (raw is! Map) return MonthlyUsage(month: month);
    return MonthlyUsage(
      month: month,
      byKind: {
        for (final kind in UsageKind.values)
          if (raw[kind.name] != null)
            kind: UsageTotals.fromJson(raw[kind.name]),
      },
    );
  }
}
