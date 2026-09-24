import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/finetune_job.dart';
import '../services/finetune_service.dart';
import '../services/pricing.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/failure_text.dart';
import '../widgets/paper_ui.dart';

/// Mode B. The only screen that spends real money and the only one that sends
/// the user's messages anywhere, so it is deliberately unhurried.
///
/// The design document leaves this screen undrawn; it follows the same
/// language as the rest.
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

  /// Builds the dataset from what is already learned, so the cost shown comes
  /// from the exact bytes that would be uploaded.
  Future<void> _prepare() async {
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      final settings = await ref.read(settingsProvider.future);
      // The model learns from the chats that are switched on, each exchange
      // carrying the names from its own chat.
      final chats = await ref.read(chatsProvider.future);
      final enabled = {
        for (final chat in chats)
          if (chat.enabled) chat.id: chat,
      };
      final exchanges = await ref
          .read(exchangeStoreProvider)
          .all(chatIds: enabled.keys.toSet());
      final jsonl = FineTuneService.buildJsonl(
        exchanges,
        myName: settings.myName,
        theirName: settings.theirName,
        contextTurns: settings.contextTurns,
        chats: enabled,
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

  /// A job started in an earlier session may still be running.
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
      backgroundColor: Paper.bg,
      surfaceTintColor: Paper.bg,
      shape: RoundedRectangleBorder(borderRadius: Corner.all(Corner.card)),
      title: Text('This will cost money', style: Type.strong(size: 17)),
      content: Text(
        'Training on ${estimate.exampleCount} examples for ${estimate.epochs} '
        '${estimate.epochs == 1 ? "pass" : "passes"} is roughly '
        '${estimate.estimatedTotalTokens} tokens, about '
        '${estimate.formattedUsd} at '
        '${Pricing.formatUsd(estimate.usdPerMillionTokens)} per million '
        'training tokens.\n\nThat is an estimate, not a quote: the real figure '
        "comes from OpenAI's tokeniser and current prices, and your account is "
        'charged either way.\n\nYour messages are uploaded to OpenAI as a '
        'training file to do this.',
        style: Type.prose(size: 14, color: Paper.body),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: Type.strong(size: 14, color: Paper.secondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            'Start (${estimate.formattedUsd})',
            style: Type.strong(size: 14, color: Paper.accent),
          ),
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
    final nothingToTrain = estimate == null || estimate.exampleCount == 0;

    return PaperScreen(
      gap: 16,
      bottom: nothingToTrain || running
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperAction(
                  title: _starting ? 'Starting…' : 'Review the cost and start',
                  centred: true,
                  busy: _starting,
                  onTap: _starting ? null : _start,
                ),
                const SizedBox(height: 11),
                const Footnote(
                  'Nothing is uploaded or charged until you confirm the amount.',
                ),
              ],
            ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: BackArrow(onTap: () => Navigator.of(context).pop()),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SerifTitle('A model of your own', size: 32),
            const SizedBox(height: 9),
            Text(
              'Mode B trains a private model on the same replies the style '
              'memory already holds. It is not the recommended path.',
              style: Type.prose(size: 14.5),
            ),
          ],
        ),
        const Notice(
          'Accounts that never fine-tuned before can no longer create jobs, '
          'and existing ones lose access during January 2027. If yours cannot, '
          "starting fails with OpenAI's own message and nothing is charged.\n\n"
          'Style memory needs no training run, costs almost nothing, and is '
          'usually just as convincing.',
          tone: NoticeTone.caution,
          title: 'OpenAI is retiring fine-tuning',
        ),
        if (_error != null) FailureNotice(error: _error!, onRetry: _prepare),
        if (_preparing)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (nothingToTrain)
          PaperPanel(
            radius: Corner.card,
            padding: const EdgeInsets.all(16),
            child: Text(
              'There is nothing to train on yet. Import a chat export and '
              'build the style memory first — fine-tuning reuses exactly '
              'that data.',
              style: Type.prose(size: 14, color: Paper.body),
            ),
          )
        else
          _DatasetCard(
            estimate: estimate,
            settings: settings,
            epochs: _epochs,
            locked: running || _starting,
            onEpochs: _setEpochs,
          ),
        if (job != null)
          _JobCard(job: job, onCancel: running ? _cancelJob : null),
        if (settings.hasFineTunedModel)
          PaperCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fine-tuned model saved',
                        style: Type.strong(size: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        settings.fineTunedModel!,
                        style: Type.numeric(
                          size: 12.5,
                          color: Paper.tertiary,
                          weight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => ref
                      .read(settingsProvider.notifier)
                      .edit(
                        (s) => s.copyWith(
                          clearFineTunedModel: true,
                          mode: TrainingMode.styleMemory,
                        ),
                      ),
                  child: Text(
                    'Forget',
                    style: Type.strong(size: 13, color: Paper.accent),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DatasetCard extends StatelessWidget {
  const _DatasetCard({
    required this.estimate,
    required this.settings,
    required this.epochs,
    required this.locked,
    required this.onEpochs,
  });

  final FineTuneEstimate estimate;
  final AppSettings settings;
  final int epochs;
  final bool locked;
  final ValueChanged<int> onEpochs;

  @override
  Widget build(BuildContext context) => PaperCard(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MonoLabel('The dataset', spacing: 0.12),
        const SizedBox(height: 12),
        FigureRow(
          'Training examples',
          estimate.exampleCount.toString(),
          emphasis: true,
        ),
        FigureRow('Base model', settings.fineTuneBaseModel),
        FigureRow(
          'Context per example',
          'up to ${settings.contextTurns} turns',
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Paper.dividerFirm)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Passes over the data',
                  style: Type.prose(size: 13, color: Paper.tertiary),
                ),
              ),
              _Nudge(
                icon: Icons.remove,
                onTap: locked || epochs <= 1
                    ? null
                    : () => onEpochs(epochs - 1),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '$epochs',
                  textAlign: TextAlign.center,
                  style: Type.numeric(size: 15),
                ),
              ),
              _Nudge(
                icon: Icons.add,
                onTap: locked || epochs >= 10
                    ? null
                    : () => onEpochs(epochs + 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Estimated cost ${estimate.formattedUsd}',
          style: Type.display(22),
        ),
        const SizedBox(height: 4),
        Text(
          '~${estimate.estimatedTotalTokens} training tokens at '
          '${Pricing.formatUsd(estimate.usdPerMillionTokens)} per million. '
          'An estimate, not a quote.',
          style: Type.prose(size: 12.5, color: Paper.muted, height: 1.45),
        ),
      ],
    ),
  );
}

class _Nudge extends StatelessWidget {
  const _Nudge({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: onTap == null ? Paper.bg : Paper.panel,
        borderRadius: Corner.all(Corner.pill),
      ),
      child: Icon(
        icon,
        size: 16,
        color: onTap == null ? Paper.placeholder : Paper.ink,
      ),
    ),
  );
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, this.onCancel});

  final FineTuneJob job;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => InkCard(
    radius: Corner.card,
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                job.status.label,
                style: Type.strong(size: 15, color: Paper.onHero, height: 1.3),
              ),
            ),
            if (!job.isTerminal)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Paper.amber,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          job.id,
          style: Type.numeric(
            size: 12,
            color: Paper.onHero.withValues(alpha: 0.60),
            weight: FontWeight.w400,
          ),
        ),
        if (job.trainedTokens != null) ...[
          const SizedBox(height: 4),
          Text(
            '${job.trainedTokens} tokens trained',
            style: Type.numeric(
              size: 12,
              color: Paper.amber,
              weight: FontWeight.w400,
            ),
          ),
        ],
        if (job.fineTunedModel != null) ...[
          const SizedBox(height: 4),
          Text(
            job.fineTunedModel!,
            style: Type.numeric(
              size: 12,
              color: Paper.amber,
              weight: FontWeight.w400,
            ),
          ),
        ],
        if (job.error != null) ...[
          const SizedBox(height: 10),
          Text(
            job.error!,
            style: Type.prose(
              size: 13,
              color: const Color(0xFFFFD9CF),
              height: 1.45,
            ),
          ),
        ],
        if (!job.isTerminal) ...[
          const SizedBox(height: 10),
          Text(
            'This runs on OpenAI and can take hours. You can leave — the '
            'job is picked back up next time you open this screen.',
            style: Type.prose(
              size: 12,
              color: Paper.onHero.withValues(alpha: 0.50),
              height: 1.45,
            ),
          ),
        ],
        if (onCancel != null) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onCancel,
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                borderRadius: Corner.all(Corner.small),
                border: Border.all(
                  color: Paper.onHero.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  'Cancel the job',
                  style: Type.strong(size: 14, color: Paper.onHero),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
