import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

/// Persists [AppSettings] — model choices, names, mode, window sizes.
///
/// Nothing secret goes in here; the API key lives in SecureKeyStore.
class SettingsStore {
  const SettingsStore();

  static const String _prefsKey = 'replylikeme_settings_v1';
  static const String _fineTuneJobKey = 'replylikeme_finetune_job_id';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const AppSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) return AppSettings.fromJson(decoded);
    } on FormatException {
      // Corrupt preferences shouldn't brick the app; fall back to defaults.
    }
    return const AppSettings();
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(settings.toJson()));
  }

  /// The id of a fine-tuning job still in flight, so polling can resume after
  /// the app is closed.
  Future<String?> pendingFineTuneJobId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_fineTuneJobKey);
  }

  Future<void> setPendingFineTuneJobId(String? jobId) async {
    final prefs = await SharedPreferences.getInstance();
    if (jobId == null || jobId.isEmpty) {
      await prefs.remove(_fineTuneJobKey);
    } else {
      await prefs.setString(_fineTuneJobKey, jobId);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    await prefs.remove(_fineTuneJobKey);
  }
}
