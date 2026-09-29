import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/ai_provider.dart';

/// Stores the API keys in the platform keystore — Keychain on iOS,
/// EncryptedSharedPreferences on Android — one entry per provider.
///
/// The keys are never written anywhere else, never printed, and never
/// included in an error message. Only [mask] ever renders one, and only
/// partially.
class SecureKeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Android encrypts by default in flutter_secure_storage 11.
            // On iOS, keep the key off backups and out of reach until the
            // device has been unlocked once since boot.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  /// The OpenAI entry keeps the name it had when it was the only key.
  static String _keyName(AiProvider provider) => switch (provider) {
    AiProvider.openai => 'openai_api_key',
    AiProvider.anthropic => 'anthropic_api_key',
    AiProvider.gemini => 'gemini_api_key',
  };

  final FlutterSecureStorage _storage;

  Future<String?> read(AiProvider provider) async {
    final value = await _storage.read(key: _keyName(provider));
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Every saved key.
  Future<ApiKeys> readAll() async {
    var keys = const ApiKeys();
    for (final provider in AiProvider.values) {
      final key = await read(provider);
      if (key != null) keys = keys.withKey(provider, key);
    }
    return keys;
  }

  Future<void> write(AiProvider provider, String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('refusing to store an empty API key');
    }
    await _storage.write(key: _keyName(provider), value: trimmed);
  }

  Future<void> delete(AiProvider provider) =>
      _storage.delete(key: _keyName(provider));

  Future<void> deleteAll() async {
    for (final provider in AiProvider.values) {
      await delete(provider);
    }
  }

  /// A shape check, not an authorisation check — only the provider can say
  /// whether a key works. This just catches the obvious paste mistakes, and
  /// works out whose key it is.
  static String? validationError(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return 'Paste your key to continue.';
    if (trimmed.contains(RegExp(r'\s'))) {
      return "There's a space in there — pasting often grabs one.";
    }
    final provider = AiProvider.forKey(trimmed);
    if (provider == null) {
      return "That doesn't look like an OpenAI (sk-…), Claude (sk-ant-…) or "
          'Gemini (AIza…) key.';
    }
    if (trimmed.length < 20) {
      return "That's shorter than any ${provider.label} key — probably a "
          'partial paste.';
    }
    return null;
  }

  /// `sk-proj...a1b2` — enough to recognise which key is saved, not enough to
  /// use it.
  static String mask(String key) {
    final trimmed = key.trim();
    if (trimmed.length <= 11) return '*' * trimmed.length;
    return '${trimmed.substring(0, 7)}${'*' * 6}${trimmed.substring(trimmed.length - 4)}';
  }
}
