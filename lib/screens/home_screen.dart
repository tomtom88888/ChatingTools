import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/stored_exchange.dart';
import '../services/share_intake.dart';
import '../state/providers.dart';
import '../widgets/failure_text.dart';
import 'generate_screen.dart';
import 'settings_screen.dart';
import 'train_screen.dart';

/// Dashboard: what the app has learned, and the two things you can do.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  StreamSubscription<SharedExport>? _shareSubscription;

  @override
  void initState() {
    super.initState();
    // A chat export shared into the app goes straight to training.
    _shareSubscription = ShareIntake.stream().listen(
      _openTrainingFor,
      onError: (Object error) {
        if (mounted) showFailureSnackBar(context, error);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await ShareIntake.initial();
      if (initial != null && mounted) unawaited(_openTrainingFor(initial));
    });
  }

  @override
  void dispose() {
    unawaited(_shareSubscription?.cancel());
    super.dispose();
  }

  Future<void> _openTrainingFor(SharedExport export) async {
    await ShareIntake.markHandled();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrainScreen(sharedExport: export),
      ),
    );
    if (mounted) _refresh();
  }

  void _refresh() {
    ref.invalidate(styleMemoryStatsProvider);
    ref.invalidate(styleMemoryCountProvider);
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(styleMemoryStatsProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final trained = (stats.value?.exchangeCount ?? 0) > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ReplyLikeMe'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _push(const SettingsScreen()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StyleMemoryCard(stats: stats, settings: settings),
            const SizedBox(height: 16),
            _ActionCard(
              icon: Icons.school_outlined,
              title: trained
                  ? 'Retrain from a new export'
                  : 'Train on a chat export',
              subtitle: trained
                  ? 'Import a newer export to refresh what the app knows.'
                  : 'Import a WhatsApp .txt or .zip export to get started.',
              onTap: () => _push(const TrainScreen()),
            ),
            _ActionCard(
              icon: Icons.auto_awesome_outlined,
              title: 'Suggest a reply',
              subtitle: trained
                  ? 'Pick a screenshot of the conversation.'
                  : 'Train first, so suggestions sound like you.',
              enabled: trained,
              onTap: () => _push(const GenerateScreen()),
            ),
            const SizedBox(height: 24),
            const Text(
              'Chat data never leaves this device. Only the text of the API '
              'calls goes to OpenAI.',
              style: TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _StyleMemoryCard extends StatelessWidget {
  const _StyleMemoryCard({
    required this.stats,
    required this.settings
  });

  final AsyncValue<StyleMemoryStats?> stats;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: stats.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text(describeFailure(error)),
          data: (value) {
            if (value == null || value.isEmpty) {
              return const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nothing learned yet'),
                  SizedBox(height: 6),
                  Text(
                    'Import a chat export and the app will build a style '
                    'memory from the replies you actually sent.',
                  ),
                ],
              );
            }
            final mode = settings.mode == TrainingMode.fineTune
                ? 'fine-tuned model'
                : 'style memory';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.psychology_outlined),
                    const SizedBox(width: 8),
                    Text(
                      '${value.exchangeCount} exchanges learned',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _Detail('You', value.myName),
                _Detail('Them', value.theirName),
                _Detail('Generating with', mode),
                _Detail(
                  'Embeddings',
                  '${value.embeddingModel} (${value.dimensions}d)',
                ),
                _Detail('Built', _formatDate(value.builtAt)),
                if (settings.mode == TrainingMode.fineTune &&
                    !settings.hasFineTunedModel) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Fine-tune mode is on but no fine-tuned model exists yet, '
                    'so style memory is being used.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  static String _formatDate(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        enabled: enabled,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
