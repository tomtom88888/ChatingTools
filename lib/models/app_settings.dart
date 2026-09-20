/// How replies are produced.
enum TrainingMode {
  /// Mode A (default): retrieve similar past exchanges and prompt a base model
  /// with them. Instant, and costs only embeddings.
  styleMemory,

  /// Mode B: generate with a model fine-tuned on your own replies. Costs money
  /// to train, and still uses retrieved examples as context.
  fineTune,
}

/// Everything configurable, none of it secret. The API key lives in
/// flutter_secure_storage and never appears here.
class AppSettings {
  const AppSettings({
    this.visionModel = defaultVisionModel,
    this.generationModel = defaultGenerationModel,
    this.embeddingModel = defaultEmbeddingModel,
    this.embeddingDimensions = defaultEmbeddingDimensions,
    this.fineTuneBaseModel = defaultFineTuneBaseModel,
    this.mode = TrainingMode.styleMemory,
    this.contextTurns = defaultContextTurns,
    this.retrievedExampleCount = defaultRetrievedExampleCount,
    this.variantCount = defaultVariantCount,
    this.myName = '',
    this.theirName = '',
    this.fineTunedModel,
    this.systemPrompt,
  });

  // OpenAI renames and retires models often, so these are starting points, not
  // constants of nature. Settings can pull the live list from GET /v1/models.
  //
  // Checked against OpenAI's docs in September 2026:
  //   gpt-5.6-terra          balanced tier, vision-capable, 1.05M context
  //   gpt-5.6-luna           cheaper tier, also vision-capable
  //   gpt-6-astra            flagship
  //   text-embedding-3-small 1536 dims, shortenable via `dimensions`
  static const String defaultVisionModel = 'gpt-5.6-terra';
  static const String defaultGenerationModel = 'gpt-5.6-terra';
  static const String defaultEmbeddingModel = 'text-embedding-3-small';

  /// text-embedding-3-* can return shortened vectors. 512 keeps the whole
  /// style memory small enough to hold in RAM for similarity search while
  /// losing very little retrieval quality.
  static const int defaultEmbeddingDimensions = 512;

  /// Fine-tuning is being wound down by OpenAI; this is the last base model
  /// their docs list for supervised fine-tuning.
  static const String defaultFineTuneBaseModel = 'gpt-4o-mini-2024-07-18';

  /// The instructions the generating model is given, before the retrieved
  /// examples and the conversation.
  ///
  /// `{me}` and `{them}` are filled in with the names from the export, so the
  /// prompt keeps working after a retrain against a different chat. Editing
  /// this is the bluntest control the app has over how replies come out; the
  /// reset in Settings puts it back.
  static const String defaultSystemPrompt =
      'You are writing a single WhatsApp message as {me}, replying to '
      '{them}.\n'
      '\n'
      'Write the way {me} actually writes. The examples of real past messages '
      'you are given are the only style reference that matters; copy their:\n'
      '- tone and level of warmth or bluntness\n'
      '- typical message length (usually short)\n'
      '- slang, abbreviations, filler words and in-jokes\n'
      '- emoji use, including using none\n'
      '- capitalisation and punctuation habits, including lowercase starts, '
      'missing full stops and repeated letters\n'
      '- language, and any mixing or switching between languages mid-message\n'
      '\n'
      'Never explain yourself, never add a greeting or sign-off that {me} '
      'would not use, and never sound like an assistant. Do not mention that '
      'you are an AI or that you were given examples.';

  static const int defaultContextTurns = 10;
  static const int defaultRetrievedExampleCount = 8;
  static const int defaultVariantCount = 3;

  /// Suggested alternatives shown in Settings. Not a whitelist — any model id
  /// can be typed in, because this list ages.
  static const List<String> suggestedChatModels = [
    'gpt-5.6-terra',
    'gpt-5.6-luna',
    'gpt-6-astra',
  ];
  static const List<String> suggestedEmbeddingModels = [
    'text-embedding-3-small',
    'text-embedding-3-large',
  ];

  final String visionModel;
  final String generationModel;
  final String embeddingModel;
  final int embeddingDimensions;
  final String fineTuneBaseModel;
  final TrainingMode mode;

  /// How many previous turns of context to use, both when building training
  /// examples and when generating.
  final int contextTurns;

  /// How many similar past exchanges to retrieve for each generation.
  final int retrievedExampleCount;

  /// How many reply options to offer.
  final int variantCount;

  /// Your name as it appears in the export.
  final String myName;

  /// The other person's name as it appears in the export.
  final String theirName;

  /// Set once a fine-tuning job has succeeded.
  final String? fineTunedModel;

  /// An edited system prompt, or `null` to use [defaultSystemPrompt].
  final String? systemPrompt;

  /// The prompt template actually in force. An empty edit falls back to the
  /// default rather than sending the model no instructions at all.
  String get effectiveSystemPrompt =>
      systemPrompt == null || systemPrompt!.trim().isEmpty
      ? defaultSystemPrompt
      : systemPrompt!;

  /// Whether the prompt has been edited away from the default.
  bool get hasCustomSystemPrompt =>
      effectiveSystemPrompt.trim() != defaultSystemPrompt.trim();

  bool get hasNames => myName.isNotEmpty && theirName.isNotEmpty;

  bool get hasFineTunedModel =>
      fineTunedModel != null && fineTunedModel!.isNotEmpty;

  /// The model that will actually generate: the fine-tuned one when Mode B is
  /// on and a model exists, otherwise the base generation model.
  String get effectiveGenerationModel =>
      mode == TrainingMode.fineTune && hasFineTunedModel
      ? fineTunedModel!
      : generationModel;

  AppSettings copyWith({
    String? visionModel,
    String? generationModel,
    String? embeddingModel,
    int? embeddingDimensions,
    String? fineTuneBaseModel,
    TrainingMode? mode,
    int? contextTurns,
    int? retrievedExampleCount,
    int? variantCount,
    String? myName,
    String? theirName,
    String? fineTunedModel,
    bool clearFineTunedModel = false,
    String? systemPrompt,
    bool resetSystemPrompt = false,
  }) => AppSettings(
    visionModel: visionModel ?? this.visionModel,
    generationModel: generationModel ?? this.generationModel,
    embeddingModel: embeddingModel ?? this.embeddingModel,
    embeddingDimensions: embeddingDimensions ?? this.embeddingDimensions,
    fineTuneBaseModel: fineTuneBaseModel ?? this.fineTuneBaseModel,
    mode: mode ?? this.mode,
    contextTurns: contextTurns ?? this.contextTurns,
    retrievedExampleCount: retrievedExampleCount ?? this.retrievedExampleCount,
    variantCount: variantCount ?? this.variantCount,
    myName: myName ?? this.myName,
    theirName: theirName ?? this.theirName,
    fineTunedModel: clearFineTunedModel
        ? null
        : (fineTunedModel ?? this.fineTunedModel),
    systemPrompt: resetSystemPrompt
        ? null
        : (systemPrompt ?? this.systemPrompt),
  );

  Map<String, Object?> toJson() => {
    'visionModel': visionModel,
    'generationModel': generationModel,
    'embeddingModel': embeddingModel,
    'embeddingDimensions': embeddingDimensions,
    'fineTuneBaseModel': fineTuneBaseModel,
    'mode': mode.name,
    'contextTurns': contextTurns,
    'retrievedExampleCount': retrievedExampleCount,
    'variantCount': variantCount,
    'myName': myName,
    'theirName': theirName,
    'fineTunedModel': fineTunedModel,
    'systemPrompt': systemPrompt,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    String str(String key, String fallback) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : fallback;
    }

    int integer(String key, int fallback) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return fallback;
    }

    final rawMode = json['mode'];
    return AppSettings(
      visionModel: str('visionModel', defaultVisionModel),
      generationModel: str('generationModel', defaultGenerationModel),
      embeddingModel: str('embeddingModel', defaultEmbeddingModel),
      embeddingDimensions: integer(
        'embeddingDimensions',
        defaultEmbeddingDimensions,
      ),
      fineTuneBaseModel: str('fineTuneBaseModel', defaultFineTuneBaseModel),
      mode: TrainingMode.values.firstWhere(
        (m) => m.name == rawMode,
        orElse: () => TrainingMode.styleMemory,
      ),
      contextTurns: integer('contextTurns', defaultContextTurns),
      retrievedExampleCount: integer(
        'retrievedExampleCount',
        defaultRetrievedExampleCount,
      ),
      variantCount: integer('variantCount', defaultVariantCount),
      myName: str('myName', ''),
      theirName: str('theirName', ''),
      fineTunedModel: json['fineTunedModel'] as String?,
      systemPrompt: json['systemPrompt'] as String?,
    );
  }
}
