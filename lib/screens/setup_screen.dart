import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_provider.dart';
import '../services/openai_exception.dart';
import '../services/openai_service.dart';
import '../services/secure_key_store.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/failure_text.dart';
import '../widgets/paper_ui.dart';

/// First run: state what the app does and where the data goes, then take the
/// key and check it before saving.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _controller = TextEditingController();
  bool _obscured = true;
  bool _busy = false;

  /// Failed a local rule — no request was spent.
  String? _shapeProblem;

  /// The provider, or the network, said no.
  Object? _failure;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTyped);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTyped);
    _controller.dispose();
    super.dispose();
  }

  void _onTyped() {
    if (_shapeProblem != null || _failure != null) {
      setState(() {
        _shapeProblem = null;
        _failure = null;
      });
    } else {
      setState(
        () {},
      ); // the button enables as soon as there is something to check
    }
  }

  /// Pasting a key out of a browser very often brings whitespace with it, so
  /// offer the fix rather than only complaining.
  void _stripWhitespace() {
    _controller.text = _controller.text.replaceAll(RegExp(r'\s'), '');
    setState(() => _shapeProblem = null);
  }

  Future<void> _submit() async {
    final key = _controller.text.trim();
    final problem = SecureKeyStore.validationError(key);
    if (problem != null) {
      setState(() => _shapeProblem = problem);
      return;
    }

    setState(() {
      _busy = true;
      _shapeProblem = null;
      _failure = null;
    });

    // Verify before saving, so a typo surfaces here and not halfway through
    // training.
    final provider = AiProvider.forKey(key)!;
    final probe = OpenAiService.forKeys(
      const ApiKeys().withKey(provider, key),
      maxRetries: 1,
    );
    try {
      await probe.listModelsFor(provider);
      await ref.read(apiKeysProvider.notifier).save(provider, key);
    } on Object catch (error) {
      if (mounted) setState(() => _failure = error);
    } finally {
      probe.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _hasWhitespace => _controller.text.contains(RegExp(r'\s'));

  /// Whose key is being typed, once it can be told.
  AiProvider? get _provider => AiProvider.forKey(_controller.text);

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    final offline =
        failure is OpenAiException &&
        (failure.kind == OpenAiErrorKind.network ||
            failure.kind == OpenAiErrorKind.timeout);

    return PaperScreen(
      padding: Frame.screenWide,
      gap: 26,
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaperAction(
            title: _busy
                ? 'Asking ${_provider?.label ?? 'the provider'}…'
                : 'Check key & continue',
            centred: true,
            busy: _busy,
            radius: Corner.field,
            onTap: _controller.text.trim().isEmpty ? null : _submit,
          ),
          const SizedBox(height: 14),
          Text(
            'No key yet? Make one at',
            style: Type.prose(size: 13.5, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          for (final p in AiProvider.values)
            Text(
              '${p.label}: ${p.keysPage}',
              style: Type.prose(size: 13, color: Paper.accent, height: 1.5),
              textAlign: TextAlign.center,
            ),
        ],
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DittoLogo(size: 52, nameSize: 22),
            const SizedBox(height: 18),
            const SerifTitle(
              'It writes back ',
              accent: 'in your words',
              trailing: " — not an assistant's.",
              size: 38,
            ),
            const SizedBox(height: 12),
            Text(
              'Hand it one exported WhatsApp or Instagram chat. It reads how '
              'you actually '
              'reply to that person, then suggests three replies that sound '
              'like you.',
              style: Type.prose(size: 15),
            ),
          ],
        ),
        const _WhereYourWordsGo(),
        _KeyField(
          controller: _controller,
          obscured: _obscured,
          onToggleObscured: () => setState(() => _obscured = !_obscured),
          problem: _shapeProblem,
          onStripWhitespace: _hasWhitespace ? _stripWhitespace : null,
          onSubmitted: _busy ? null : _submit,
          provider: _provider,
        ),
        if (failure != null)
          Notice(
            offline
                ? "Couldn't reach ${_provider?.label ?? 'the provider'}. "
                      'Check your connection — nothing '
                      'was saved or spent.'
                : describeFailure(failure),
            tone: offline ? NoticeTone.neutral : NoticeTone.failure,
            actionLabel: 'Try again',
            onAction: _busy ? null : _submit,
          ),
      ],
    );
  }
}

/// The privacy promise, stated before anything is asked for.
class _WhereYourWordsGo extends StatelessWidget {
  const _WhereYourWordsGo();

  static const List<String> _promises = [
    'Your chat file stays on this phone. Always.',
    'The AI you pick (OpenAI, Claude or Gemini) sees three things: the text '
        'being learned, the screenshot you pick, and the prompt. Nothing '
        'else.',
    'No account, no server of ours. You pay the AI company directly with '
        'your own key.',
  ];

  @override
  Widget build(BuildContext context) => PaperPanel(
    radius: Corner.card,
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WHERE YOUR WORDS GO',
          style: Type.prose(
            size: 12,
            color: Paper.green,
            height: 1.3,
            weight: FontWeight.w600,
          ).copyWith(letterSpacing: 0.09 * 12),
        ),
        for (final promise in _promises) ...[
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 6, right: 11),
                decoration: BoxDecoration(
                  color: Paper.green,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  promise,
                  style: Type.prose(size: 14, color: Paper.body, height: 1.45),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _KeyField extends StatelessWidget {
  const _KeyField({
    required this.controller,
    required this.obscured,
    required this.onToggleObscured,
    required this.problem,
    required this.onStripWhitespace,
    required this.onSubmitted,
    required this.provider,
  });

  final TextEditingController controller;
  final bool obscured;
  final VoidCallback onToggleObscured;
  final String? problem;
  final VoidCallback? onStripWhitespace;
  final VoidCallback? onSubmitted;
  final AiProvider? provider;

  @override
  Widget build(BuildContext context) {
    final invalid = problem != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                'Your OpenAI, Claude or Gemini API key',
                style: Type.strong(size: 13, height: 1.35),
              ),
            ),
            GestureDetector(
              onTap: onToggleObscured,
              child: Text(
                obscured ? 'Show' : 'Hide',
                style: Type.prose(
                  size: 12,
                  color: Paper.accent,
                  height: 1.35,
                  weight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Paper.card,
            borderRadius: Corner.all(Corner.field),
            border: Border.all(
              color: invalid ? Paper.accent : Paper.border,
              width: 1.5,
            ),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscured,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
            style: Type.numeric(
              size: 15,
              weight: FontWeight.w400,
            ).copyWith(height: 1.2),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
              hintText: 'sk-…, sk-ant-… or AIza…',
              hintStyle: Type.numeric(
                size: 15,
                color: Paper.placeholder,
                weight: FontWeight.w400,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (invalid)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  problem!,
                  style: Type.prose(size: 13, color: Paper.accent, height: 1.4),
                ),
              ),
              if (onStripWhitespace != null) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: onStripWhitespace,
                  child: Text(
                    'Strip it',
                    style: Type.strong(size: 13, color: Paper.accent),
                  ),
                ),
              ],
            ],
          )
        else
          Text(switch (provider) {
            null =>
              "Stored in this phone's keychain. Checked once, before it's "
                  'saved. You can add keys from the others in Settings.',
            AiProvider.anthropic =>
              'A Claude key. Claude writes replies and reads screenshots, '
                  "but can't fingerprint chats: to learn them, also add an "
                  'OpenAI or Gemini key in Settings.',
            final p =>
              'A ${p.label} key. Stored in this phone\'s keychain, and '
                  "checked with ${p.label} once, before it's saved.",
          }, style: Type.prose(size: 13, color: Paper.tertiary, height: 1.45)),
      ],
    );
  }
}
