import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/exchange.dart';
import '../models/parsed_chat.dart';
import '../services/chat_export_reader.dart';
import '../services/pricing.dart';
import '../services/share_intake.dart';
import '../services/style_memory_service.dart';
import '../services/whatsapp_parser.dart';
import '../state/providers.dart';
import '../widgets/failure_text.dart';
import 'finetune_screen.dart';

/// Import a WhatsApp export, say which name is yours, and build style memory.
class TrainScreen extends ConsumerStatefulWidget {
  const TrainScreen({this.sharedExport, super.key});

  /// Set when the app was opened through the share sheet.
  final SharedExport? sharedExport;

  @override
  ConsumerState<TrainScreen> createState() => _TrainScreenState();
}

class _TrainScreenState extends ConsumerState<TrainScreen> {
  ParsedChat? _chat;
  String? _sourceName;
  String? _myName;
  String? _theirName;
  List<Exchange> _exchanges = const [];

  bool _reading = false;
  bool _building = false;
  bool _cancelRequested = false;
  StyleMemoryProgress? _progress;
  Object? _error;
  int? _builtCount;

  @override
  void initState() {
    super.initState();
    final shared = widget.sharedExport;
    if (shared != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadFile(File(shared.path), shared.name),
      );
    }
  }

  Future<void> _pickFile() async {
    setState(() => _error = null);
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Pick a WhatsApp chat export',
        type: FileType.custom,
        allowedExtensions: const ['txt', 'zip'],
      );
      if (picked == null) return;
      await _loadBytes(await picked.xFile.readAsBytes(), picked.name);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _loadFile(File file, String name) async {
    try {
      await _loadBytes(await file.readAsBytes(), name);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _loadBytes(List<int> bytes, String name) async {
    setState(() {
      _reading = true;
      _error = null;
      _builtCount = null;
    });
    try {
      final text = ChatExportReader.read(bytes, filename: name);
      final chat = WhatsAppParser.parse(text);

      if (chat.format == ExportFormat.unknown) {
        throw const ChatExportException(
          "That file doesn't look like a WhatsApp export. In WhatsApp open the "
          'chat, tap the menu, then More > Export chat.',
        );
      }
      if (chat.senders.length < 2) {
        throw const ChatExportException(
          'That export only has messages from one person in it, so there are '
          'no replies to learn from.',
        );
      }

      final settings = await ref.read(settingsProvider.future);
      final senders = chat.senders;
      // Prefer the names already configured; otherwise guess from the export.
      final mine = senders.contains(settings.myName)
          ? settings.myName
          : senders.first;
      final theirs =
          senders.contains(settings.theirName) && settings.theirName != mine
          ? settings.theirName
          : senders.firstWhere((s) => s != mine, orElse: () => senders.last);
      setState(() {
        _chat = chat;
        _sourceName = name;
        _myName = mine;
        _theirName = theirs;
      });
      _recomputeExchanges();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  /// Exchanges are derived from the export and the chosen name, so they are
  /// recomputed when either changes rather than on every rebuild.
  void _recomputeExchanges() {
    if (!mounted) return;
    final chat = _chat;
    final me = _myName;
    if (chat == null || me == null) {
      setState(() => _exchanges = const []);
      return;
    }
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    setState(() {
      _exchanges = WhatsAppParser.buildExchanges(
        chat.turns,
        me: me,
        maxContextTurns: settings.contextTurns,
      );
    });
  }

  Future<void> _build() async {
    final service = ref.read(styleMemoryServiceProvider);
    final chat = _chat;
    final me = _myName;
    final them = _theirName;
    if (service == null || chat == null || me == null || them == null) return;

    final settings = await ref.read(settingsProvider.future);

    setState(() {
      _building = true;
      _cancelRequested = false;
      _error = null;
      _progress = null;
    });

    try {
      final stats = await service.build(
        exchanges: _exchanges,
        myName: me,
        theirName: them,
        embeddingModel: settings.embeddingModel,
        dimensions: settings.embeddingDimensions,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        isCancelled: () => _cancelRequested,
      );

      // Remember who is who, so generation and fine-tuning agree with training.
      await ref
          .read(settingsProvider.notifier)
          .edit((current) => current.copyWith(myName: me, theirName: them));
      ref.invalidate(styleMemoryStatsProvider);
      ref.invalidate(styleMemoryCountProvider);

      if (mounted) setState(() => _builtCount = stats.exchangeCount);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _building = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final chat = _chat;

    return Scaffold(
      appBar: AppBar(title: const Text('Train')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              FailureCard(error: _error!),
              const SizedBox(height: 12),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1. Import an export',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'In WhatsApp: open the chat, tap the contact name, scroll '
                      'down and tap Export chat, then choose Without media. '
                      'Share it straight into ReplyLikeMe, or save it and pick '
                      'it here.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _reading || _building ? null : _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: Text(
                        _sourceName == null
                            ? 'Choose .txt or .zip'
                            : 'Chosen: $_sourceName',
                      ),
                    ),
                    if (_reading) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),
            if (chat != null) ...[
              const SizedBox(height: 12),
              _SummaryCard(chat: chat),
              const SizedBox(height: 12),
              _NamesCard(
                senders: chat.senders,
                myName: _myName,
                theirName: _theirName,
                enabled: !_building,
                onChanged: (mine, theirs) {
                  setState(() {
                    _myName = mine;
                    _theirName = theirs;
                  });
                  _recomputeExchanges();
                },
              ),
              const SizedBox(height: 12),
              _BuildCard(
                exchanges: _exchanges,
                settings: settings,
                building: _building,
                progress: _progress,
                builtCount: _builtCount,
                onBuild: _build,
                onCancel: () => setState(() => _cancelRequested = true),
                onFineTune: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FineTuneScreen(),
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.chat});

  final ParsedChat chat;

  @override
  Widget build(BuildContext context) {
    final layout = switch (chat.format) {
      ExportFormat.android => 'Android export',
      ExportFormat.ios => 'iOS export',
      ExportFormat.unknown => 'Unrecognised layout',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '2. What was in the file',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(layout),
                _Chip('${chat.textMessageCount} text messages'),
                _Chip('${chat.turns.length} turns'),
                if (chat.mediaCount > 0) _Chip('${chat.mediaCount} media'),
                if (chat.deletedCount > 0)
                  _Chip('${chat.deletedCount} deleted'),
                if (chat.systemCount > 0) _Chip('${chat.systemCount} system'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              chat.senderMessageCounts.entries
                  .map((e) => '${e.key}: ${e.value}')
                  .join('  ·  '),
              style: const TextStyle(fontSize: 13),
            ),
            if (chat.unparsedLineCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${chat.unparsedLineCount} lines could not be read and were '
                'skipped.',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Chip(label: Text(label), visualDensity: VisualDensity.compact);
}

class _NamesCard extends StatelessWidget {
  const _NamesCard({
    required this.senders,
    required this.myName,
    required this.theirName,
    required this.enabled,
    required this.onChanged
  });

  final List<String> senders;
  final String? myName;
  final String? theirName;
  final bool enabled;
  final void Function(String? mine, String? theirs) onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '3. Who is who',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Only the replies from the name you pick as yours are learned.',
            ),
            const SizedBox(height: 12),
            _SenderDropdown(
              label: 'That is me',
              value: myName,
              senders: senders,
              enabled: enabled,
              onChanged: (value) => onChanged(
                value,
                value == theirName
                    ? senders.firstWhere(
                        (s) => s != value,
                        orElse: () => theirName ?? senders.last,
                      )
                    : theirName,
              ),
            ),
            const SizedBox(height: 12),
            _SenderDropdown(
              label: 'That is them',
              value: theirName,
              senders: senders,
              enabled: enabled,
              onChanged: (value) => onChanged(
                value == myName
                    ? senders.firstWhere(
                        (s) => s != value,
                        orElse: () => myName ?? senders.first,
                      )
                    : myName,
                value,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuildCard extends ConsumerWidget {
  const _BuildCard({
    required this.exchanges,
    required this.settings,
    required this.building,
    required this.progress,
    required this.builtCount,
    required this.onBuild,
    required this.onCancel,
    required this.onFineTune
  });

  final List<Exchange> exchanges;
  final AppSettings settings;
  final bool building;
  final StyleMemoryProgress? progress;
  final int? builtCount;
  final VoidCallback onBuild;
  final VoidCallback onCancel;
  final VoidCallback onFineTune;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(styleMemoryServiceProvider);
    final estimate = service?.estimate(exchanges);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '4. Build the style memory',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '${exchanges.length} replies of yours have something before them '
              'to reply to. Each one is embedded once and stored on this '
              'phone.',
            ),
            if (estimate != null && exchanges.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Roughly ${estimate.estimatedTokens} embedding tokens, about '
                '${Pricing.formatUsd(estimate.estimatedUsd)}. Estimates only.',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            if (building) ...[
              LinearProgressIndicator(value: progress?.fraction),
              const SizedBox(height: 8),
              Text(
                progress == null
                    ? 'Starting'
                    : '${progress!.stage} — ${progress!.embedded}/${progress!.total}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                ),
              ),
            ] else
              FilledButton.icon(
                onPressed: exchanges.isEmpty ? null : onBuild,
                icon: const Icon(Icons.psychology_outlined),
                label: Text(
                  builtCount == null ? 'Build style memory' : 'Rebuild',
                ),
              ),
            if (builtCount != null && !building) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Learned $builtCount exchanges. Ready to use.'),
                  ),
                ],
              ),
            ],
            const Divider(height: 32),
            Text(
              'Optional: fine-tune a model',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            const Text(
              'Mode B trains your own model on the same data. It costs money, '
              'takes a while, and OpenAI is winding fine-tuning down — style '
              'memory is the default for good reason.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: builtCount == null && settings.myName.isEmpty
                  ? null
                  : onFineTune,
              child: const Text('Fine-tuning'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SenderDropdown extends StatelessWidget {
  const _SenderDropdown({
    required this.label,
    required this.value,
    required this.senders,
    required this.enabled,
    required this.onChanged
  });

  final String label;
  final String? value;
  final List<String> senders;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        items: [
          for (final sender in senders)
            DropdownMenuItem(value: sender, child: Text(sender)),
        ],
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}
