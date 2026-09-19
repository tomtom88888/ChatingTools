import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the OpenAI API key in the platform keystore — Keychain on iOS,
/// EncryptedSharedPreferences on Android.
///
/// The key is never written anywhere else, never printed, and never included in
/// an error message. Only [mask] ever renders it, and only partially.
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

  static const String _keyName = 'openai_api_key';

  final FlutterSecureStorage _storage;

  Future<String?> read() async {
    final value = await _storage.read(key: _keyName);
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<bool> hasKey() async => (await read()) != null;

  Future<void> write(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('refusing to store an empty API key');
    }
    await _storage.write(key: _keyName, value: trimmed);
  }

  Future<void> delete() => _storage.delete(key: _keyName);

  /// A shape check, not an authorisation check — only OpenAI can say whether a
  /// key works. This just catches the obvious paste mistakes.
  static String? validationError(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return 'Paste your key to continue.';
    if (trimmed.contains(RegExp(r'\s'))) {
      return "There's a space in there — pasting often grabs one.";
    }
    if (!trimmed.startsWith('sk-')) {
      return 'OpenAI keys start with sk-. This looks like a different '
          "service's key.";
    }
    if (trimmed.length < 20) {
      return "That's shorter than any OpenAI key — probably a partial "
          'paste.';
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
