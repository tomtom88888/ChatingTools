/// Status of an OpenAI fine-tuning job, as reported by the API.
enum FineTuneStatus {
  validatingFiles,
  queued,
  running,
  succeeded,
  failed,
  cancelled,
  unknown;

  static FineTuneStatus parse(String? raw) => switch (raw) {
    'validating_files' => validatingFiles,
    'queued' => queued,
    'running' => running,
    'succeeded' => succeeded,
    'failed' => failed,
    'cancelled' => cancelled,
    _ => unknown,
  };

  bool get isTerminal =>
      this == succeeded || this == failed || this == cancelled;

  String get label => switch (this) {
    validatingFiles => 'Validating the training file',
    queued => 'Queued',
    running => 'Training',
    succeeded => 'Done',
    failed => 'Failed',
    cancelled => 'Cancelled',
    unknown => 'Unknown',
  };
}

/// One fine-tuning job.
class FineTuneJob {
  const FineTuneJob({
    required this.id,
    required this.status,
    required this.baseModel,
    this.fineTunedModel,
    this.trainedTokens,
    this.error,
    this.createdAt,
    this.finishedAt,
  });

  factory FineTuneJob.fromJson(Map<String, Object?> json) {
    final error = json['error'];
    return FineTuneJob(
      id: (json['id'] as String?) ?? '',
      status: FineTuneStatus.parse(json['status'] as String?),
      baseModel: (json['model'] as String?) ?? '',
      fineTunedModel: json['fine_tuned_model'] as String?,
      trainedTokens: (json['trained_tokens'] as num?)?.toInt(),
      error: error is Map && error['message'] is String
          ? error['message'] as String
          : null,
      createdAt: _time(json['created_at']),
      finishedAt: _time(json['finished_at']),
    );
  }

  static DateTime? _time(Object? seconds) => seconds is num
      ? DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000)
      : null;

  final String id;
  final FineTuneStatus status;
  final String baseModel;
  final String? fineTunedModel;
  final int? trainedTokens;
  final String? error;
  final DateTime? createdAt;
  final DateTime? finishedAt;

  bool get isTerminal => status.isTerminal;

  @override
  String toString() => 'FineTuneJob($id, ${status.name}, $fineTunedModel)';
}
