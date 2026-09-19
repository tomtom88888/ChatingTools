import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/stored_exchange.dart';
import '../services/embeddings_store.dart';
import '../services/finetune_service.dart';
import '../services/openai_service.dart';
import '../services/reply_generator.dart';
import '../services/secure_key_store.dart';
import '../services/settings_store.dart';
import '../services/style_memory_service.dart';

// --------------------------------------------------------------------- storage

final secureKeyStoreProvider = Provider<SecureKeyStore>(
  (ref) => SecureKeyStore(),
);

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => const SettingsStore(),
);

final exchangeStoreProvider = Provider<SqfliteExchangeStore>((ref) {
  final store = SqfliteExchangeStore();
  ref.onDispose(store.close);
  return store;
});

// ------------------------------------------------------------------- API key

/// The saved OpenAI key, or `null` if setup hasn't happened yet.
///
/// The value is held in memory only while the app runs; the only copy at rest
/// is in the platform keystore.
class ApiKeyNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() => ref.read(secureKeyStoreProvider).read();

  Future<void> save(String key) async {
    await ref.read(secureKeyStoreProvider).write(key);
    state = AsyncValue.data(key.trim());
  }

  Future<void> clear() async {
    await ref.read(secureKeyStoreProvider).delete();
    state = const AsyncValue.data(null);
  }
}

final apiKeyProvider = AsyncNotifierProvider<ApiKeyNotifier, String?>(
  ApiKeyNotifier.new,
);

final hasApiKeyProvider = Provider<bool>((ref) {
  final key = ref.watch(apiKeyProvider).value;
  return key != null && key.isNotEmpty;
});

// ------------------------------------------------------------------- settings

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.read(settingsStoreProvider).load();

  Future<void> update(AppSettings next) async {
    await ref.read(settingsStoreProvider).save(next);
    state = AsyncValue.data(next);
  }

  /// Applies a change to the current settings, loading them first if needed.
  Future<void> edit(AppSettings Function(AppSettings current) change) async {
    final current = state.value ?? await future;
    await update(change(current));
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

// -------------------------------------------------------------------- services

/// `null` until a key is saved, so screens can't accidentally call OpenAI
/// without one.
final openAiServiceProvider = Provider<OpenAiService?>((ref) {
  final key = ref.watch(apiKeyProvider).value;
  if (key == null || key.isEmpty) return null;
  final service = OpenAiService(apiKey: key);
  ref.onDispose(service.close);
  return service;
});

final styleMemoryServiceProvider = Provider<StyleMemoryService?>((ref) {
  final openai = ref.watch(openAiServiceProvider);
  if (openai == null) return null;
  return StyleMemoryService(
    openai: openai,
    store: ref.watch(exchangeStoreProvider),
  );
});

final replyGeneratorProvider = Provider<ReplyGenerator?>((ref) {
  final openai = ref.watch(openAiServiceProvider);
  if (openai == null) return null;
  return ReplyGenerator(openai: openai);
});

final fineTuneServiceProvider = Provider<FineTuneService?>((ref) {
  final openai = ref.watch(openAiServiceProvider);
  if (openai == null) return null;
  return FineTuneService(openai: openai);
});

// ---------------------------------------------------------------- style memory

/// What the stored style memory was built from. Invalidate after training.
final styleMemoryStatsProvider = FutureProvider<StyleMemoryStats?>(
  (ref) => ref.watch(exchangeStoreProvider).stats(),
);

final styleMemoryCountProvider = FutureProvider<int>(
  (ref) => ref.watch(exchangeStoreProvider).count(),
);

// ----------------------------------------------------------------- data wiping

/// Deletes everything this app stored on the device.
///
/// The API key is handled separately, because "forget what you learned about
/// me" and "forget my OpenAI credentials" are different requests.
class DataWiper {
  const DataWiper(this._ref);

  final Ref _ref;

  Future<void> wipe({required bool includeApiKey}) async {
    await _ref.read(exchangeStoreProvider).deleteEverything();
    await _ref.read(settingsStoreProvider).clear();
    if (includeApiKey) await _ref.read(apiKeyProvider.notifier).clear();
    _ref.invalidate(settingsProvider);
    _ref.invalidate(exchangeStoreProvider);
    _ref.invalidate(styleMemoryStatsProvider);
    _ref.invalidate(styleMemoryCountProvider);
  }
}

final dataWiperProvider = Provider<DataWiper>(DataWiper.new);
