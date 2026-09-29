import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_provider.dart';
import '../models/app_settings.dart';
import '../services/openai_service.dart';
import '../services/secure_key_store.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/failure_text.dart';
import '../widgets/paper_dialog.dart';
import '../widgets/paper_ui.dart';
import 'finetune_screen.dart';
import 'settings/settings_widgets.dart';
import 'settings/spending_section.dart';

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

  /// Pulls the model ids the saved keys can actually use, so the fields
  /// below are not guesswork about anyone's current naming.
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

  /// Adds, replaces or removes the key for [provider]. A new key is checked
  /// with the provider before it is saved.
  Future<void> _editKey(AiProvider provider, {required bool saved}) async {
    final controller = TextEditingController();
    final action = await showDialog<_KeyAction>(
      context: context,
      builder: (context) => PaperDialog(
        title: saved
            ? 'Replace ${provider.label} key'
            : 'Add ${provider.label} key',
        confirmLabel: 'Save',
        onConfirm: () => Navigator.of(context).pop(_KeyAction.save),
        extraLabel: saved ? 'Remove key' : null,
        onExtra: saved
            ? () => Navigator.of(context).pop(_KeyAction.remove)
            : null,
        child: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          style: Type.numeric(size: 14, weight: FontWeight.w400),
          decoration: paperFieldDecoration(provider.keyHint),
        ),
      ),
    );
    final key = controller.text.trim();
    controller.dispose();
    if (action == null || !mounted) return;

    final keys = ref.read(apiKeysProvider.notifier);
    if (action == _KeyAction.remove) {
      try {
        await keys.remove(provider);
        if (mounted) showToast(context, '${provider.label} key removed.');
      } on Object catch (error) {
        if (mounted) showFailureSnackBar(context, error);
      }
      return;
    }

    final problem =
        SecureKeyStore.validationError(key) ??
        (AiProvider.forKey(key) == provider
            ? null
            : "That isn't a ${provider.label} key.");
    if (problem != null) {
      showFailureSnackBar(context, Exception(problem));
      return;
    }
    final probe = OpenAiService.forKeys(
      const ApiKeys().withKey(provider, key),
      maxRetries: 1,
    );
    try {
      await probe.listModelsFor(provider);
      await keys.save(provider, key);
      if (mounted) showToast(context, '${provider.label} key saved.');
    } on Object catch (error) {
      if (mounted) showFailureSnackBar(context, error);
    } finally {
      probe.close();
    }
  }

  Future<void> _deleteEverything() async {
    final choice = await showDialog<_WipeChoice>(
      context: context,
      builder: (context) => PaperDialog(
        title: 'Delete all my data?',
        confirmLabel: 'Delete everything',
        destructive: true,
        onConfirm: () => Navigator.of(context).pop(_WipeChoice.everything),
        extraLabel: 'Delete, keep my key',
        onExtra: () => Navigator.of(context).pop(_WipeChoice.keepKey),
        child: Text(
          'This removes every learned chat, your settings, the spending tally, '
          'the record of which suggestions you took, and the record of any '
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
    final keys = ref.watch(apiKeysProvider).value ?? const ApiKeys();
    final chatCount = ref.watch(chatsProvider).value?.length ?? 0;

    return settingsValue.when(
      loading: () => Scaffold(
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
          ScreenBar(
            title: 'Settings',
            onBack: () => Navigator.of(context).pop(),
          ),
          FailureNotice(
            error: error,
            onRetry: () => ref.invalidate(settingsProvider),
          ),
        ],
      ),
      data: (settings) => PaperScreen(
        gap: 14,
        children: [
          ScreenBar(
            title: 'Settings',
            onBack: () => Navigator.of(context).pop(),
          ),
          const SerifTitle('Settings', size: 34),

          const MonoLabel('API keys'),
          PaperCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final p in AiProvider.values)
                  TapRow(
                    key: ValueKey('key-${p.name}'),
                    label: p.label,
                    value: keys[p] == null
                        ? 'Not added'
                        : SecureKeyStore.mask(keys[p]!),
                    mono: keys[p] != null,
                    actionLabel: keys.has(p) ? 'Change' : 'Add',
                    onTap: () => _editKey(p, saved: keys.has(p)),
                  ),
                TapRow(
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
          ModelField(
            label: 'Reads screenshots',
            value: settings.visionModel,
            suggestions: _suggest(AppSettings.chatModelsFor(keys)),
            helper: _needsKey(settings.visionModel, keys),
            onChanged: (v) => _edit((s) => s.copyWith(visionModel: v)),
          ),
          ModelField(
            label: 'Writes replies',
            value: settings.generationModel,
            suggestions: _suggest(AppSettings.chatModelsFor(keys)),
            helper: _needsKey(settings.generationModel, keys),
            onChanged: (v) => _edit((s) => s.copyWith(generationModel: v)),
          ),
          ModelField(
            label: 'Fingerprints the memory',
            value: settings.embeddingModel,
            suggestions: _suggest(AppSettings.embeddingModelsFor(keys)),
            helper:
                _needsKey(settings.embeddingModel, keys) ??
                (keys.canFingerprint
                    ? 'OpenAI or Gemini. Changing this makes the memory you '
                          'have unusable — retrain afterwards.'
                    : "Claude can't fingerprint: add an OpenAI or Gemini key "
                          'to learn chats and search them.'),
            onChanged: (v) => _edit((s) => s.copyWith(embeddingModel: v)),
          ),
          NumberStepper(
            label: 'Fingerprint size',
            helper:
                'Shorter is a smaller, faster memory. Retrain after '
                'changing.',
            value: settings.embeddingDimensions,
            min: 64,
            max: 3072,
            step: 64,
            onChanged: (v) => _edit((s) => s.copyWith(embeddingDimensions: v)),
          ),

          const MonoLabel('How replies are made'),
          ModeChoice(
            settings: settings,
            onPick: (mode) => _edit((s) => s.copyWith(mode: mode)),
            onOpenFineTune: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const FineTuneScreen()),
            ),
          ),
          NumberStepper(
            label: 'Context turns',
            helper: 'How much conversation is used, training and generating.',
            value: settings.contextTurns,
            min: 1,
            max: 40,
            onChanged: (v) => _edit((s) => s.copyWith(contextTurns: v)),
          ),
          NumberStepper(
            label: 'Retrieved examples',
            helper: 'How many past exchanges the model is shown.',
            value: settings.retrievedExampleCount,
            min: 1,
            max: 30,
            onChanged: (v) =>
                _edit((s) => s.copyWith(retrievedExampleCount: v)),
          ),
          NumberStepper(
            label: 'Reply options',
            value: settings.variantCount,
            min: 1,
            max: 6,
            onChanged: (v) => _edit((s) => s.copyWith(variantCount: v)),
          ),

          const MonoLabel('The prompt'),
          SystemPromptField(
            value: settings.effectiveSystemPrompt,
            edited: settings.hasCustomSystemPrompt,
            onChanged: (v) => _edit((s) => s.copyWith(systemPrompt: v)),
            onReset: () => _edit((s) => s.copyWith(resetSystemPrompt: true)),
          ),

          const MonoLabel('Your chats'),
          PaperCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StackedRow(
                  label: 'You, in the exports',
                  value: settings.myName.isEmpty
                      ? 'Set when you import an export'
                      : settings.myName,
                ),
                StackedRow(
                  label: 'Chats learned',
                  value: switch (chatCount) {
                    0 => 'None yet',
                    1 => 'One — tick or untick it on the home screen',
                    _ => '$chatCount — tick which to use on the home screen',
                  },
                  last: true,
                ),
              ],
            ),
          ),

          const MonoLabel('Spending'),
          SpendingSection(
            settings: settings,
            onPrices: (input, output) => _edit(
              (s) => input == null || output == null
                  ? s.copyWith(clearChatPrices: true)
                  : s.copyWith(
                      chatInputUsdPerMillion: input,
                      chatOutputUsdPerMillion: output,
                    ),
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
                    'Every chat learned, settings, spending and the saved '
                    'fine-tuned model id. Your key can stay.',
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
            'Model names change. Load the list above and pick one your keys '
            "can use. A model's name decides who runs it: claude-… is Claude, "
            'gemini-… is Gemini, anything else is OpenAI.',
          ),
        ],
      ),
    );
  }

  /// A warning when [model]'s provider has no key saved.
  static String? _needsKey(String model, ApiKeys keys) {
    final provider = AiProvider.forModel(model);
    if (keys.has(provider)) return null;
    return 'No ${provider.label} key saved: add one above, or pick another '
        'model.';
  }

  /// The account's own models once loaded, otherwise the built-in suggestions.
  List<String> _suggest(List<String> fallback) {
    final models = _accountModels;
    return models == null || models.isEmpty ? fallback : models;
  }
}

enum _WipeChoice { keepKey, everything }

enum _KeyAction { save, remove }
