import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_usage.dart';

/// Keeps a per-month tally of the tokens the app has used, on the device.
///
/// Only counts are stored — never the text that was sent.
class UsageStore {
  const UsageStore();

  static const String _prefsKey = 'replylikeme_usage_v1';

  /// How many months are kept; older ones are dropped as new ones start.
  static const int keepMonths = 12;

  /// Every stored month, newest first.
  Future<List<MonthlyUsage>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_prefsKey));
  }

  /// Adds [usage] to the month of [at], and returns every month afterwards.
  Future<List<MonthlyUsage>> record(ApiUsage usage, {DateTime? at}) async {
    final prefs = await SharedPreferences.getInstance();
    final months = {
      for (final m in _decode(prefs.getString(_prefsKey))) m.month: m,
    };
    final key = MonthlyUsage.keyFor(at ?? DateTime.now());
    months[key] = (months[key] ?? MonthlyUsage(month: key)).plus(usage);
    final kept =
        (months.values.toList()..sort((a, b) => b.month.compareTo(a.month)))
            .take(keepMonths)
            .toList();
    await prefs.setString(
      _prefsKey,
      jsonEncode({for (final m in kept) m.month: m.toJson()}),
    );
    return kept;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static List<MonthlyUsage> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      return [
        for (final entry in decoded.entries)
          if (entry.key is String)
            MonthlyUsage.fromJson(entry.key as String, entry.value),
      ]..sort((a, b) => b.month.compareTo(a.month));
    } on FormatException {
      return const [];
    }
  }
}
