import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/app_settings.dart';
import '../models/extracted_message.dart';
import '../models/stored_exchange.dart';
import '../services/reply_generator.dart';
import '../state/providers.dart';
import '../widgets/failure_text.dart';

/// Pick a screenshot, check what the model read off it, get three replies.
class GenerateScreen extends ConsumerStatefulWidget {
  const GenerateScreen({super.key});

  @override
  ConsumerState<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends ConsumerState<GenerateScreen> {
  Uint8List? _screenshot;
  List<ExtractedMessage> _messages = [];
  List<String> _variants = [];
  List<ScoredExchange> _examples = [];

  bool _reading = false;
  bool _generating = false;
  Object? _error;

  Future<void> _pickScreenshot() async {
    setState(() => _error = null);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // Big enough for small text to stay legible, small enough to keep the
        // vision call cheap.
        maxWidth: 1400,
        imageQuality: 90,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        _screenshot = bytes;
        _messages = [];
        _variants = [];
      });
      await _extract(bytes, picked.mimeType ?? _guessMimeType(picked.name));
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  static String _guessMimeType(String name) =>
      name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';

  Future<void> _extract(Uint8List bytes, String mimeType) async {
    final openai = ref.read(openAiServiceProvider);
    if (openai == null) return;
    final settings = await ref.read(settingsProvider.future);

    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final messages = await openai.extractConversation(
        imageBytes: bytes,
        model: settings.visionModel,
        imageMimeType: mimeType,
      );
      if (mounted) setState(() => _messages = messages);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _generate() async {
    final generator = ref.read(replyGeneratorProvider);
    final memory = ref.read(styleMemoryServiceProvider);
    if (generator == null || memory == null) return;
    final settings = await ref.read(settingsProvider.future);

    setState(() {
      _generating = true;
      _error = null;
      _variants = [];
    });
    try {
      final conversation = ReplyGenerator.turnsFrom(
        _messages,
        myName: settings.myName.isEmpty ? 'Me' : settings.myName,
        theirName: settings.theirName.isEmpty ? 'Them' : settings.theirName,
      );
      final examples = await memory.retrieve(
        context: conversation,
        embeddingModel: settings.embeddingModel,
        dimensions: settings.embeddingDimensions,
        limit: settings.retrievedExampleCount,
      );
      final variants = await generator.generate(
        conversation: conversation,
        examples: examples,
        settings: settings.copyWith(
          myName: settings.myName.isEmpty ? 'Me' : settings.myName,
          theirName: settings.theirName.isEmpty ? 'Them' : settings.theirName,
        ),
      );
      if (mounted) {
        setState(() {
          _examples = examples;
          _variants = variants;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _copy(String reply) async {
    await Clipboard.setData(ClipboardData(text: reply));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied. Paste it into WhatsApp.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _toggleSide(int index) {
    setState(() {
      final message = _messages[index];
      _messages[index] = message.copyWith(
        speaker: message.speaker == Speaker.me ? Speaker.them : Speaker.me,
      );
      _variants = [];
    });
  }

  Future<void> _editText(int index) async {
    final controller = TextEditingController(text: _messages[index].text);
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fix the text'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(labelText: 'Message'),
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
    if (updated == null || !mounted) return;
    setState(() {
      if (updated.trim().isEmpty) {
        _messages.removeAt(index);
      } else {
        _messages[index] = _messages[index].copyWith(text: updated.trim());
      }
      _variants = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final canGenerate = _messages.isNotEmpty && !_generating && !_reading;

    return Scaffold(
      appBar: AppBar(title: const Text('Suggest a reply')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              FailureCard(error: _error!),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: _reading || _generating ? null : _pickScreenshot,
              icon: const Icon(Icons.image_outlined),
              label: Text(
                _screenshot == null
                    ? 'Pick a screenshot of the conversation'
                    : 'Pick a different screenshot',
              ),
            ),
            if (_screenshot != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _screenshot!,
                  height: 200,
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                ),
              ),
            ],
            if (_reading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text(
                'Reading the screenshot with the vision model...',
                style: TextStyle(fontSize: 12),
              ),
            ],
            if (_messages.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'What it read',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Tap a side to swap who sent it, or the text to fix it. Vision '
                'models do get bubble alignment wrong.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _messages.length; i++)
                _ExtractedRow(
                  message: _messages[i],
                  settings: settings,
                  onToggleSide: () => _toggleSide(i),
                  onEdit: () => _editText(i),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: canGenerate ? _generate : null,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: Text(
                  _variants.isEmpty
                      ? 'Suggest ${settings.variantCount} replies'
                      : 'Suggest again',
                ),
              ),
            ],
            if (_generating) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_variants.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Tap one to copy',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final variant in _variants)
                Card(
                  child: InkWell(
                    onTap: () => _copy(variant),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(child: Text(variant)),
                          const SizedBox(width: 8),
                          const Icon(Icons.copy_outlined, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                _examples.isEmpty
                    ? 'No past examples matched, so this is the base model '
                          'guessing.'
                    : 'Based on ${_examples.length} similar past exchanges '
                          '(closest match '
                          '${(_examples.first.similarity * 100).round()}%), '
                          'generated with ${settings.effectiveGenerationModel}.',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExtractedRow extends StatelessWidget {
  const _ExtractedRow({
    required this.message,
    required this.settings,
    required this.onToggleSide,
    required this.onEdit,
    super.key,
  });

  final ExtractedMessage message;
  final AppSettings settings;
  final VoidCallback onToggleSide;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final mine = message.speaker == Speaker.me;
    final scheme = Theme.of(context).colorScheme;
    final label = mine
        ? (settings.myName.isEmpty ? 'me' : settings.myName)
        : (settings.theirName.isEmpty ? 'them' : settings.theirName);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          InkWell(
            onTap: onToggleSide,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 92,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              decoration: BoxDecoration(
                color: mine
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(mine ? Icons.arrow_forward : Icons.arrow_back, size: 14),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(message.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
