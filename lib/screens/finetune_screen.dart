import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/finetune_job.dart';
import '../services/finetune_service.dart';
import '../services/pricing.dart';
import '../state/providers.dart';
import '../widgets/failure_text.dart';

/// Mode B: build a JSONL dataset from the style memory, show what it will
/// cost, and only then start a fine-tuning job.
class FineTuneScreen extends ConsumerStatefulWidget {
  const FineTuneScreen({super.key});

  @override
  ConsumerState<FineTuneScreen> createState() => _FineTuneScreenState();
}

class _FineTuneScreenState extends ConsumerState<FineTuneScreen> {
  String? _jsonl;
  FineTuneEstimate? _estimate;
  int _epochs = FineTuneService.defaultEpochs;

  FineTuneJob? _job;
  StreamSubscription<FineTuneJob>? _watch;

  bool _preparing = false;
  bool _starting = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _prepare();
      await _resumePendingJob();
    });
  }

  @override
  void dispose() {
    unawaited(_watch?.cancel());
    super.dispose();
  }

  /// Builds the dataset from what's already in the style memory, so the cost
  /// shown comes from the exact bytes that would be uploaded.
  Future<void> _prepare() async {
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      final settings = await ref.read(settingsProvider.future);
      final exchanges = await ref.read(exchangeStoreProvider).all();
      final jsonl = FineTuneService.buildJsonl(
        exchanges,
        myName: settings.myName,
        theirName: settings.theirName,
        contextTurns: settings.contextTurns,
      );
      if (mounted) {
        setState(() {
          _jsonl = jsonl;
          _estimate = FineTuneService.estimate(jsonl, epochs: _epochs);
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  void _setEpochs(int epochs) {
    final jsonl = _jsonl;
    setState(() {
      _epochs = epochs;
      if (jsonl != null) {
        _estimate = FineTuneService.estimate(jsonl, epochs: epochs);
      }
    });
  }

  /// A job started in an earlier session is still running; pick it back up.
  Future<void> _resumePendingJob() async {
    final jobId = await ref.read(settingsStoreProvider).pendingFineTuneJobId();
    if (jobId == null || jobId.isEmpty) return;
    _startWatching(jobId);
  }

  Future<void> _start() async {
    final service = ref.read(fineTuneServiceProvider);
    final jsonl = _jsonl;
    final estimate = _estimate;
    if (service == null || jsonl == null || estimate == null) return;

    final confirmed = await _confirm(estimate);
    if (confirmed != true || !mounted) return;

    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final settings = await ref.read(settingsProvider.future);
      final job = await service.start(
        jsonl: jsonl,
        baseModel: settings.fineTuneBaseModel,
        suffix: 'replylikeme',
        epochs: _epochs,
      );
      await ref.read(settingsStoreProvider).setPendingFineTuneJobId(job.id);
      if (mounted) setState(() => _job = job);
      _startWatching(job.id);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// Spending money needs an explicit yes, with the number in front of them.
  Future<bool?> _confirm(FineTuneEstimate estimate) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('This will cost money'),
      content: Text(
        'Training on ${estimate.exampleCount} examples for '
        '${estimate.epochs} ${estimate.epochs == 1 ? "epoch" : "epochs"} is '
        'roughly ${estimate.estimatedTotalTokens} tokens, about '
        '${estimate.formattedUsd} at '
        '${Pricing.formatUsd(estimate.usdPerMillionTokens)} per million '
        'training tokens.\n\n'
        'That is an estimate, not a quote: the real figure comes from '
        "OpenAI's tokeniser and current prices, and your account is charged "
        'either way.\n\n'
        'Your messages are uploaded to OpenAI as a training file to do this.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('Start (${estimate.formattedUsd})'),
        ),
      ],
    ),
  );

  void _startWatching(String jobId) {
    final service = ref.read(fineTuneServiceProvider);
    if (service == null) return;
    unawaited(_watch?.cancel());
    _watch = service
        .watch(jobId)
        .listen(
          (job) async {
            if (mounted) setState(() => _job = job);
            if (!job.isTerminal) return;

            await ref.read(settingsStoreProvider).setPendingFineTuneJobId(null);
            final model = job.fineTunedModel;
            if (job.status == FineTuneStatus.succeeded &&
                model != null &&
                model.isNotEmpty) {
              // Save the model and switch to it: the user paid for it.
              await ref
                  .read(settingsProvider.notifier)
                  .edit(
                    (s) => s.copyWith(
                      fineTunedModel: model,
                      mode: TrainingMode.fineTune,
                    ),
                  );
            }
          },
          onError: (Object error) {
            if (mounted) setState(() => _error = error);
          },
        );
  }

  Future<void> _cancelJob() async {
    final service = ref.read(fineTuneServiceProvider);
    final job = _job;
    if (service == null || job == null) return;
    try {
      final cancelled = await service.cancel(job.id);
      await ref.read(settingsStoreProvider).setPendingFineTuneJobId(null);
      if (mounted) setState(() => _job = cancelled);
    } on Object catch (error) {
      if (mounted) showFailureSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final estimate = _estimate;
    final job = _job;
    final running = job != null && !job.isTerminal;

    return Scaffold(
      appBar: AppBar(title: const Text('Fine-tuning')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Before you start'),
                    SizedBox(height: 8),
                    Text(
                      'OpenAI is winding fine-tuning down. Accounts that never '
                      'fine-tuned before cannot create jobs any more, and '
                      'existing ones lose access during January 2027. If your '
                      'account cannot use it, starting a job will fail with '
                      "OpenAI's own message and nothing will be charged.\n\n"
                      'Style memory needs no training run, costs almost '
                      'nothing, and is usually just as convincing.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              FailureCard(error: _error!, onRetry: _prepare),
            ],
            const SizedBox(height: 12),
            if (_preparing)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (estimate == null || estimate.exampleCount == 0)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'There is nothing to train on yet. Import a chat export '
                    'and build the style memory first — fine-tuning reuses '
                    'exactly that data.',
                  ),
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'The dataset',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('${estimate.exampleCount} training examples'),
                      Text('Base model: ${settings.fineTuneBaseModel}'),
                      Text(
                        'Up to ${settings.contextTurns} previous turns as '
                        'context per example',
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('Epochs'),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: running || _epochs <= 1
                                ? null
                                : () => _setEpochs(_epochs - 1),
                          ),
                          Text('$_epochs'),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: running || _epochs >= 10
                                ? null
                                : () => _setEpochs(_epochs + 1),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Text(
                        'Estimated cost: ${estimate.formattedUsd}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '~${estimate.estimatedTotalTokens} training tokens at '
                        '${Pricing.formatUsd(estimate.usdPerMillionTokens)} '
                        'per million. Estimate only.',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _starting || running ? null : _start,
                        icon: const Icon(Icons.model_training),
                        label: Text(
                          _starting ? 'Starting...' : 'Review cost and start',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (job != null) ...[
              const SizedBox(height: 12),
              _JobCard(job: job, onCancel: running ? _cancelJob : null),
            ],
            if (settings.hasFineTunedModel) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Fine-tuned model saved'),
                  subtitle: Text(settings.fineTunedModel!),
                  trailing: TextButton(
                    onPressed: () => ref
                        .read(settingsProvider.notifier)
                        .edit(
                          (s) => s.copyWith(
                            clearFineTunedModel: true,
                            mode: TrainingMode.styleMemory,
                          ),
                        ),
                    child: const Text('Forget'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, this.onCancel, super.key});

  final FineTuneJob job;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  job.status.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (!job.isTerminal)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Job ${job.id}', style: const TextStyle(fontSize: 12)),
            if (job.trainedTokens != null)
              Text(
                '${job.trainedTokens} tokens trained',
                style: const TextStyle(fontSize: 12),
              ),
            if (job.fineTunedModel != null)
              Text(job.fineTunedModel!, style: const TextStyle(fontSize: 12)),
            if (job.error != null) ...[
              const SizedBox(height: 8),
              Text(
                job.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (!job.isTerminal) ...[
              const SizedBox(height: 8),
              const Text(
                'This runs on OpenAI and can take a while. You can leave this '
                'screen; the job is picked back up next time you open it.',
                style: TextStyle(fontSize: 12),
              ),
            ],
            if (onCancel != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onCancel,
                  child: const Text('Cancel job'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
