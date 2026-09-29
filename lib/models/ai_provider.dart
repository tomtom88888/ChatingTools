/// The companies whose models Ditto can use. Each needs its own API key.
enum AiProvider {
  openai,
  anthropic,
  gemini;

  /// The name people know it by.
  String get label => switch (this) {
    openai => 'OpenAI',
    anthropic => 'Claude',
    gemini => 'Gemini',
  };

  /// Where to make a key.
  String get keysPage => switch (this) {
    openai => 'platform.openai.com/api-keys',
    anthropic => 'platform.claude.com/settings/keys',
    gemini => 'aistudio.google.com/apikey',
  };

  /// What a key looks like, as a hint in a text field.
  String get keyHint => switch (this) {
    openai => 'sk-…',
    anthropic => 'sk-ant-…',
    gemini => 'AIza…',
  };

  /// Whether it can fingerprint text for the style memory and search. Claude
  /// has no embeddings API.
  bool get canFingerprint => this != anthropic;

  /// Who serves [model], told from its name: `claude-…` is Claude,
  /// `gemini-…` (and Google's older embedding names) is Gemini, and anything
  /// else, fine-tuned models included, is OpenAI.
  static AiProvider forModel(String model) {
    final id = model.trim().toLowerCase();
    if (id.startsWith('claude')) return anthropic;
    if (id.startsWith('gemini') ||
        id.startsWith('models/') ||
        id.startsWith('text-embedding-00') ||
        id.startsWith('embedding-')) {
      return gemini;
    }
    return openai;
  }

  /// Whose key [key] is, told from how it starts, or `null` if it looks like
  /// none of them.
  static AiProvider? forKey(String key) {
    final k = key.trim();
    if (k.startsWith('sk-ant-')) return anthropic;
    if (k.startsWith('sk-')) return openai;
    if (k.startsWith('AIza')) return gemini;
    return null;
  }
}

/// The saved key for each provider. Held in memory while the app runs; the
/// only copy at rest is in the platform keystore.
class ApiKeys {
  const ApiKeys([this._keys = const {}]);

  final Map<AiProvider, String> _keys;

  String? operator [](AiProvider provider) => _keys[provider];

  bool has(AiProvider provider) => (_keys[provider] ?? '').isNotEmpty;

  bool get isEmpty => !AiProvider.values.any(has);

  bool get isNotEmpty => !isEmpty;

  /// The providers with a key, in the order of [AiProvider.values].
  List<AiProvider> get providers => [
    for (final p in AiProvider.values)
      if (has(p)) p,
  ];

  /// Whether some key can fingerprint text: learning chats and searching
  /// need one.
  bool get canFingerprint => providers.any((p) => p.canFingerprint);

  ApiKeys withKey(AiProvider provider, String key) =>
      ApiKeys({..._keys, provider: key.trim()});

  ApiKeys without(AiProvider provider) => ApiKeys({..._keys}..remove(provider));

  @override
  bool operator ==(Object other) =>
      other is ApiKeys && AiProvider.values.every((p) => other[p] == this[p]);

  @override
  int get hashCode =>
      Object.hashAll([for (final p in AiProvider.values) this[p]]);
}
