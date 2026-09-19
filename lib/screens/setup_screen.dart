import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/openai_service.dart';
import '../services/secure_key_store.dart';
import '../state/providers.dart';
import '../widgets/failure_text.dart';

/// First run: take the OpenAI API key and check it works.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _controller = TextEditingController();
  bool _obscured = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    final shapeError = SecureKeyStore.validationError(key);
    if (shapeError != null) {
      setState(() => _error = shapeError);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    // Verify against the API before saving, so a typo is caught here rather
    // than halfway through training.
    final probe = OpenAiService(apiKey: key, maxRetries: 1);
    try {
      await probe.listModels();
      await ref.read(apiKeyProvider.notifier).save(key);
    } on Object catch (error) {
      if (mounted) setState(() => _error = describeFailure(error));
    } finally {
      probe.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ReplyLikeMe')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Replies in your own words',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'ReplyLikeMe learns how you text from a WhatsApp chat export '
                'you choose, then suggests replies in that style.\n\n'
                'Your chats stay on this phone. The only thing sent anywhere '
                'is the text of the API calls to OpenAI, using your own key.',
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                obscureText: _obscured,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'OpenAI API key',
                  hintText: 'sk-...',
                  errorText: _error,
                  suffixIcon: IconButton(
                    tooltip: _obscured ? 'Show' : 'Hide',
                    icon: Icon(
                      _obscured ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  ),
                ),
                onSubmitted: (_) => _busy ? null : _save(),
              ),
              const SizedBox(height: 8),
              const Text(
                'Create one at platform.openai.com/api-keys. It is stored in '
                "this phone's keystore and never leaves the device except as "
                'the Authorization header on calls to OpenAI.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Check and save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
