import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../services/secure_key_store.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/failure_text.dart';
import '../widgets/paper_ui.dart';
import 'finetune_screen.dart';

/// The design document does not draw Settings, so this follows its language:
/// warm paper, mono section labels, serif only for the page title.
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

  /// Pulls the model ids this account can actually use, so the fields below
  /// are not guesswork about OpenAI's current naming.
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
      builder: (context) => _PaperDialog(
        title: 'Replace API key',
        confirmLabel: 'Save',
        onConfirm: () => Navigator.of(context).pop(controller.text),
        child: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          style: Type.numeric(size: 14, weight: FontWeight.w400),
          decoration: _fieldDecoration('sk-…'),
        ),
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
      if (mounted) showToast(context, 'Key replaced.');
    } on Object catch (error) {
      if (mounted) showFailureSnackBar(context, error);
    }
  }

  Future<void> _deleteEverything() async {
    final choice = await showDialog<_WipeChoice>(
      context: context,
      builder: (context) => _PaperDialog(
        title: 'Delete all my data?',
        confirmLabel: 'Delete everything',
        destructive: true,
        onConfirm: () => Navigator.of(context).pop(_WipeChoice.everything),
        extraLabel: 'Delete, keep my key',
        onExtra: () => Navigator.of(context).pop(_WipeChoice.keepKey),
        child: Text(
          'This removes the style memory, your settings, and the record of any '
          'fine-tuned model — everything this app keeps on the phone. It '
          'cannot be undone.\n\nFiles already uploaded to OpenAI, and any model '
          'trained there, are not touched: delete those in your OpenAI '
          'dashboard.',
          style: Type.prose(size: 14, color: Paper.body),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    try {
      await ref
          .read(dataWiperProvider)
          .wipe(includeApiKey: choice == _WipeChoice.everything);
      if (!mounted) return;
      showToast(context, 'Deleted.');
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

    return settingsValue.when(
      loading: () => const Scaffold(
        backgroundColor: Paper.bg,
        body: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (error, _) => PaperScreen(
        children: [
          _Back(onTap: () => Navigator.of(context).pop()),
          FailureNotice(
            error: error,
            onRetry: () => ref.invalidate(settingsProvider),
          ),
        ],
      ),
      data: (settings) => PaperScreen(
        gap: 14,
        children: [
          _Back(onTap: () => Navigator.of(context).pop()),
          const SerifTitle('Settings', size: 34),

          const MonoLabel('OpenAI account'),
          PaperCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TapRow(
                  label: 'API key',
                  value: apiKey == null
                      ? 'Not saved'
                      : SecureKeyStore.mask(apiKey),
                  mono: apiKey != null,
                  actionLabel: 'Replace',
                  onTap: _replaceKey,
                ),
                _TapRow(
                  label: 'Models your account can use',
                  value: _accountModels == null
                      ? 'Not loaded — the fields below are suggestions'
                      : '${_accountModels!.length} available',
                  actionLabel: _loadingModels ? null : 'Load',
                  busy: _loadingModels,
                  onTap: _loadAccountModels,
                  last: true,
                ),
              ],
            ),
          ),

          const MonoLabel('Models'),
          _ModelField(
            label: 'Reads screenshots',
            value: settings.visionModel,
            suggestions: _suggest(AppSettings.suggestedChatModels),
            onChanged: (v) => _edit((s) => s.copyWith(visionModel: v)),
          ),
          _ModelField(
            label: 'Writes replies',
            value: settings.generationModel,
            suggestions: _suggest(AppSettings.suggestedChatModels),
            onChanged: (v) => _edit((s) => s.copyWith(generationModel: v)),
          ),
          _ModelField(
            label: 'Fingerprints the memory',
            value: settings.embeddingModel,
            suggestions: _suggest(AppSettings.suggestedEmbeddingModels),
            helper: 'Changing this makes the memory you have unusable — '
                'retrain afterwards.',
            onChanged: (v) => _edit((s) => s.copyWith(embeddingModel: v)),
          ),
          _Stepper(
            label: 'Fingerprint size',
            helper: 'Shorter is a smaller, faster memory. Retrain after '
                'changing.',
            value: settings.embeddingDimensions,
            min: 64,
            max: 3072,
            step: 64,
            onChanged: (v) => _edit((s) => s.copyWith(embeddingDimensions: v)),
          ),

          const MonoLabel('How replies are made'),
          _ModeChoice(
            settings: settings,
            onPick: (mode) => _edit((s) => s.copyWith(mode: mode)),
            onOpenFineTune: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const FineTuneScreen()),
            ),
          ),
          _Stepper(
            label: 'Context turns',
            helper: 'How much conversation is used, training and generating.',
            value: settings.contextTurns,
            min: 1,
            max: 40,
            onChanged: (v) => _edit((s) => s.copyWith(contextTurns: v)),
          ),
          _Stepper(
            label: 'Retrieved examples',
            helper: 'How many past exchanges the model is shown.',
            value: settings.retrievedExampleCount,
            min: 1,
            max: 30,
            onChanged: (v) => _edit((s) => s.copyWith(retrievedExampleCount: v)),
          ),
          _Stepper(
            label: 'Reply options',
            value: settings.variantCount,
            min: 1,
            max: 6,
            onChanged: (v) => _edit((s) => s.copyWith(variantCount: v)),
          ),

          const MonoLabel('Names in the export'),
          PaperCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StackedRow(
                  label: 'You',
                  value: settings.myName.isEmpty
                      ? 'Set when you import an export'
                      : settings.myName,
                ),
                StackedRow(
                  label: 'Them',
                  value: settings.theirName.isEmpty
                      ? 'Set when you import an export'
                      : settings.theirName,
                  last: true,
                ),
              ],
            ),
          ),

          const MonoLabel('Your data'),
          GestureDetector(
            onTap: _deleteEverything,
            child: PaperPanel(
              color: Paper.errorPanel,
              radius: Corner.action,
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delete all my data',
                    style: Type.strong(size: 15, color: Paper.errorText),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Style memory, settings, and the saved fine-tuned model '
                    'id. Your key can stay.',
                    style: Type.prose(
                      size: 13,
                      color: Paper.errorText,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Footnote(
            'Model names change. Load the list above and pick one your account '
            "has, or check OpenAI's model documentation.",
          ),
        ],
      ),
    );
  }

  /// The account's own models once loaded, otherwise the built-in suggestions.
  List<String> _suggest(List<String> fallback) {
    final models = _accountModels;
    return models == null || models.isEmpty ? fallback : models;
  }
}

enum _WipeChoice { keepKey, everything }

InputDecoration _fieldDecoration(String hint) => InputDecoration(
  isDense: true,
  filled: true,
  fillColor: Paper.card,
  hintText: hint,
  hintStyle: Type.numeric(
    size: 14,
    color: Paper.placeholder,
    weight: FontWeight.w400,
  ),
  contentPadding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
  border: OutlineInputBorder(
    borderRadius: Corner.all(Corner.small),
    borderSide: const BorderSide(color: Paper.border, width: 1.5),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: Corner.all(Corner.small),
    borderSide: const BorderSide(color: Paper.border, width: 1.5),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: Corner.all(Corner.small),
    borderSide: const BorderSide(color: Paper.accent, width: 1.5),
  ),
);

class _Back extends StatelessWidget {
  const _Back({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: GestureDetector(
      onTap: onTap,
      child: const Text(
        '←',
        style: TextStyle(fontSize: 19, color: Paper.secondary),
      ),
    ),
  );
}

class _TapRow extends StatelessWidget {
  const _TapRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.actionLabel,
    this.mono = false,
    this.busy = false,
    this.last = false,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final String? actionLabel;
  final bool mono;
  final bool busy;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: Paper.divider)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Type.prose(size: 12, color: Paper.tertiary, height: 1.3),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: mono
                    ? Type.numeric(size: 13, weight: FontWeight.w400)
                    : Type.strong(size: 14, height: 1.35),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (busy)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (actionLabel != null)
          GestureDetector(
            onTap: onTap,
            child: Text(
              actionLabel!,
              style: Type.strong(size: 13, color: Paper.accent),
            ),
          ),
      ],
    ),
  );
}

/// A model id as free text with a menu of suggestions: any id can be typed,
/// because this list ages faster than the app ships.
class _ModelField extends StatefulWidget {
  const _ModelField({
    required this.label,
    required this.value,
    required this.suggestions,
    required this.onChanged,
    this.helper,
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(widget.label, style: Type.strong(size: 13, height: 1.35)),
      const SizedBox(height: 7),
      TextField(
        controller: _controller,
        autocorrect: false,
        style: Type.numeric(size: 14, weight: FontWeight.w400),
        decoration: _fieldDecoration('model id').copyWith(
          suffixIcon: PopupMenuButton<String>(
            icon: const Icon(
              Icons.expand_more,
              size: 20,
              color: Paper.tertiary,
            ),
            tooltip: 'Suggestions',
            color: Paper.bg,
            itemBuilder: (context) => [
              for (final suggestion in widget.suggestions.take(60))
                PopupMenuItem(
                  value: suggestion,
                  child: Text(
                    suggestion,
                    style: Type.numeric(size: 13, weight: FontWeight.w400),
                  ),
                ),
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
      if (widget.helper != null) ...[
        const SizedBox(height: 6),
        Text(
          widget.helper!,
          style: Type.prose(size: 12.5, color: Paper.muted, height: 1.4),
        ),
      ],
    ],
  );
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.helper,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String? helper;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => PaperCard(
    padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Type.strong(size: 14, height: 1.35)),
              if (helper != null) ...[
                const SizedBox(height: 3),
                Text(
                  helper!,
                  style: Type.prose(
                    size: 12.5,
                    color: Paper.tertiary,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        _Nudge(
          icon: Icons.remove,
          onTap: value - step < min ? null : () => onChanged(value - step),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: Type.numeric(size: 15),
          ),
        ),
        _Nudge(
          icon: Icons.add,
          onTap: value + step > max ? null : () => onChanged(value + step),
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
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: onTap == null ? Paper.bg : Paper.panel,
        borderRadius: Corner.all(Corner.pill),
      ),
      child: Icon(
        icon,
        size: 17,
        color: onTap == null ? Paper.placeholder : Paper.ink,
      ),
    ),
  );
}

class _ModeChoice extends StatelessWidget {
  const _ModeChoice({
    required this.settings,
    required this.onPick,
    required this.onOpenFineTune,
  });

  final AppSettings settings;
  final ValueChanged<TrainingMode> onPick;
  final VoidCallback onOpenFineTune;

  @override
  Widget build(BuildContext context) {
    final explanation = switch (settings.mode) {
      TrainingMode.styleMemory =>
        'Retrieves your most similar past replies and prompts a base model '
            'with them. Instant, and costs only embeddings.',
      TrainingMode.fineTune => settings.hasFineTunedModel
          ? 'Generating with ${settings.fineTunedModel}, still using your '
                'retrieved examples as context.'
          : 'No fine-tuned model exists yet, so style memory is used until '
                'one does.',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final mode in TrainingMode.values) ...[
              if (mode != TrainingMode.values.first) const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => onPick(mode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: settings.mode == mode ? Paper.ink : Paper.card,
                      borderRadius: Corner.all(Corner.small),
                      border: settings.mode == mode
                          ? null
                          : Border.all(color: Paper.border, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        mode == TrainingMode.styleMemory
                            ? 'Style memory'
                            : 'Fine-tuned',
                        style: Type.strong(
                          size: 14,
                          color: settings.mode == mode
                              ? Paper.onInk
                              : Paper.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          explanation,
          style: Type.prose(size: 12.5, color: Paper.tertiary, height: 1.45),
        ),
        const SizedBox(height: 10),
        PaperAction(
          title: 'Fine-tuning',
          subtitle: 'Costs money, and OpenAI is retiring it',
          tone: ActionTone.outline,
          onTap: onOpenFineTune,
        ),
      ],
    );
  }
}

/// A dialog in the design's language rather than Material's.
class _PaperDialog extends StatelessWidget {
  const _PaperDialog({
    required this.title,
    required this.child,
    required this.confirmLabel,
    required this.onConfirm,
    this.destructive = false,
    this.extraLabel,
    this.onExtra,
  });

  final String title;
  final Widget child;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final bool destructive;
  final String? extraLabel;
  final VoidCallback? onExtra;

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Paper.bg,
    surfaceTintColor: Paper.bg,
    shape: RoundedRectangleBorder(borderRadius: Corner.all(Corner.card)),
    title: Text(title, style: Type.strong(size: 17)),
    content: child,
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(
          'Cancel',
          style: Type.strong(size: 14, color: Paper.secondary),
        ),
      ),
      if (extraLabel != null && onExtra != null)
        TextButton(
          onPressed: onExtra,
          child: Text(
            extraLabel!,
            style: Type.strong(size: 14, color: Paper.secondary),
          ),
        ),
      TextButton(
        onPressed: onConfirm,
        child: Text(
          confirmLabel,
          style: Type.strong(
            size: 14,
            color: destructive ? Paper.errorText : Paper.accent,
          ),
        ),
      ),
    ],
  );
}
