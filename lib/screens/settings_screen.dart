import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../services/secure_key_store.dart';
import '../state/providers.dart';
import '../widgets/failure_text.dart';
import 'finetune_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  List<String>? _accountModels;
  bool _loadingModels = false;

  Future<void> _edit(AppSettings Function(AppSettings) change) =>
      ref.read(settingsProvider.notifier).edit(change);

  /// Pulls the model ids this account can actually use, so the fields don't
  /// depend on names baked in at build time.
  Future<void> _loadAccountModels() async {
    final openai = ref.read(openAiServiceProvider);
    if (openai == null) return;
    setState(() => _loadingModels = true);
    try {
      final models = await openai.listModels();
      if (mounted) setState(() => _accountModels = models);
    } on Object catch (error) {
      if (mounted) showFailureSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _replaceKey() async {
    final controller = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace API key'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'OpenAI API key'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (key == null || !mounted) return;

    final problem = SecureKeyStore.validationError(key);
    if (problem != null) {
      showFailureSnackBar(context, Exception(problem));
      return;
    }
    try {
      await ref.read(apiKeyProvider.notifier).save(key);
    } on Object catch (error) {
      if (mounted) showFailureSnackBar(context, error);
    }
  }

  Future<void> _deleteEverything() async {
    final choice = await showDialog<_WipeChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all my data?'),
        content: const Text(
          'This removes the style memory, your settings, and the record of any '
          'fine-tuned model — everything this app keeps on the phone. It '
          'cannot be undone.\n\n'
          'Files already uploaded to OpenAI, and any model trained there, are '
          'not touched: delete those in your OpenAI dashboard.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_WipeChoice.keepKey),
            child: const Text('Delete, keep my key'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_WipeChoice.everything),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    try {
      await ref
          .read(dataWiperProvider)
          .wipe(includeApiKey: choice == _WipeChoice.everything);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Deleted.')));
      if (choice == _WipeChoice.everything) {
        // Without a key there is nothing to show here; RootScreen takes over.
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on Object catch (error) {
      if (mounted) showFailureSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsValue = ref.watch(settingsProvider);
    final apiKey = ref.watch(apiKeyProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FailureCard(
              error: error,
              onRetry: () => ref.invalidate(settingsProvider),
            ),
          ),
        ),
        data: (settings) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Section('OpenAI account'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('API key'),
                    subtitle: Text(
                      apiKey == null
                          ? 'Not saved'
                          : SecureKeyStore.mask(apiKey),
                    ),
                    trailing: TextButton(
                      onPressed: _replaceKey,
                      child: const Text('Replace'),
                    ),
                  ),
                  ListTile(
                    title: const Text('Model list'),
                    subtitle: Text(
                      _accountModels == null
                          ? 'Load the models your account can use, so the '
                                'fields below are not guesswork.'
                          : '${_accountModels!.length} models available',
                    ),
                    trailing: _loadingModels
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: _loadAccountModels,
                            child: const Text('Load'),
                          ),
                  ),
                ],
              ),
            ),

            _Section('Models'),
            _ModelField(
              label: 'Reading screenshots (vision)',
              value: settings.visionModel,
              suggestions: _suggest(AppSettings.suggestedChatModels),
              onChanged: (value) =>
                  _edit((s) => s.copyWith(visionModel: value)),
            ),
            _ModelField(
              label: 'Writing replies',
              value: settings.generationModel,
              suggestions: _suggest(AppSettings.suggestedChatModels),
              onChanged: (value) =>
                  _edit((s) => s.copyWith(generationModel: value)),
            ),
            _ModelField(
              label: 'Embeddings (style memory)',
              value: settings.embeddingModel,
              suggestions: _suggest(AppSettings.suggestedEmbeddingModels),
              helper:
                  'Changing this makes the existing style memory unusable — '
                  'retrain after changing it.',
              onChanged: (value) =>
                  _edit((s) => s.copyWith(embeddingModel: value)),
            ),
            _NumberTile(
              label: 'Embedding dimensions',
              value: settings.embeddingDimensions,
              min: 64,
              max: 3072,
              step: 64,
              helper:
                  'Shorter vectors mean a smaller, faster memory. Retrain '
                  'after changing.',
              onChanged: (value) =>
                  _edit((s) => s.copyWith(embeddingDimensions: value)),
            ),

            _Section('How replies are made'),
            Card(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: SegmentedButton<TrainingMode>(
                      segments: const [
                        ButtonSegment(
                          value: TrainingMode.styleMemory,
                          label: Text('Style memory'),
                        ),
                        ButtonSegment(
                          value: TrainingMode.fineTune,
                          label: Text('Fine-tuned'),
                        ),
                      ],
                      selected: {settings.mode},
                      onSelectionChanged: (selection) =>
                          _edit((s) => s.copyWith(mode: selection.first)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      settings.mode == TrainingMode.styleMemory
                          ? 'Mode A: retrieves your most similar past replies '
                                'and prompts a base model with them. Instant, '
                                'and only costs embeddings.'
                          : settings.hasFineTunedModel
                          ? 'Mode B: generating with ${settings.fineTunedModel}, '
                                'still using your retrieved examples as '
                                'context.'
                          : 'Mode B: no fine-tuned model exists yet, so style '
                                'memory is used until one does.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  ListTile(
                    title: const Text('Fine-tuning'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const FineTuneScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _NumberTile(
              label: 'Context turns',
              value: settings.contextTurns,
              min: 1,
              max: 40,
              helper:
                  'How much of the conversation is used, both when training '
                  'and when generating.',
              onChanged: (value) =>
                  _edit((s) => s.copyWith(contextTurns: value)),
            ),
            _NumberTile(
              label: 'Retrieved examples',
              value: settings.retrievedExampleCount,
              min: 1,
              max: 30,
              helper: 'How many similar past exchanges are shown to the model.',
              onChanged: (value) =>
                  _edit((s) => s.copyWith(retrievedExampleCount: value)),
            ),
            _NumberTile(
              label: 'Reply options',
              value: settings.variantCount,
              min: 1,
              max: 6,
              onChanged: (value) =>
                  _edit((s) => s.copyWith(variantCount: value)),
            ),

            _Section('Names in the export'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('You'),
                    subtitle: Text(
                      settings.myName.isEmpty
                          ? 'Set when you import an export'
                          : settings.myName,
                    ),
                  ),
                  ListTile(
                    title: const Text('Them'),
                    subtitle: Text(
                      settings.theirName.isEmpty
                          ? 'Set when you import an export'
                          : settings.theirName,
                    ),
                  ),
                ],
              ),
            ),

            _Section('Your data'),
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: const Text('Delete all my data'),
                subtitle: const Text(
                  'Style memory, settings and the saved fine-tuned model id.',
                ),
                onTap: _deleteEverything,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Model names change. If a model stops working, load the list '
              "above and pick one your account has, or check OpenAI's model "
              'documentation.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// The account's own models when they've been loaded, otherwise the built-in
  /// suggestions.
  List<String> _suggest(List<String> fallback) {
    final models = _accountModels;
    if (models == null || models.isEmpty) return fallback;
    return models;
  }
}

enum _WipeChoice { keepKey, everything }

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 4),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// A free-text model id with a menu of suggestions, because any id can be
/// typed but most people want to pick.
class _ModelField extends StatefulWidget {
  const _ModelField({
    required this.label,
    required this.value,
    required this.suggestions,
    required this.onChanged,
    this.helper
  });

  final String label;
  final String value;
  final List<String> suggestions;
  final String? helper;
  final ValueChanged<String> onChanged;

  @override
  State<_ModelField> createState() => _ModelFieldState();
}

class _ModelFieldState extends State<_ModelField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_ModelField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      _controller.text = widget.value;
      return;
    }
    if (value != widget.value) widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: _controller,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helper,
          helperMaxLines: 3,
          suffixIcon: PopupMenuButton<String>(
            icon: const Icon(Icons.arrow_drop_down),
            tooltip: 'Suggestions',
            itemBuilder: (context) => [
              for (final suggestion in widget.suggestions.take(60))
                PopupMenuItem(value: suggestion, child: Text(suggestion)),
            ],
            onSelected: (value) {
              _controller.text = value;
              widget.onChanged(value);
            },
          ),
        ),
        onEditingComplete: _commit,
        onTapOutside: (_) => _commit(),
      ),
    );
  }
}

class _NumberTile extends StatelessWidget {
  const _NumberTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.helper
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String? helper;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: helper == null ? null : Text(helper!),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: value - step < min
                  ? null
                  : () => onChanged(value - step),
            ),
            Text('$value'),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: value + step > max
                  ? null
                  : () => onChanged(value + step),
            ),
          ],
        ),
      ),
    );
  }
}
