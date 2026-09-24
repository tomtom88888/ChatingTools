import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/api_usage.dart';
import '../../models/app_settings.dart';
import '../../services/pricing.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/format.dart';
import '../../widgets/paper_dialog.dart';
import '../../widgets/paper_ui.dart';

/// What the app has spent on your key, month by month, counted from the
/// token figures OpenAI returns with every response.
class SpendingSection extends ConsumerWidget {
  const SpendingSection({
    required this.settings,
    required this.onPrices,
    super.key,
  });

  final AppSettings settings;

  /// Saves new chat prices; `null` for either clears both.
  final void Function(double? input, double? output) onPrices;

  UsageCost _cost(MonthlyUsage month) => Pricing.costOf(
    month,
    embeddingModel: settings.embeddingModel,
    chatInputUsdPerMillion: settings.chatInputUsdPerMillion,
    chatOutputUsdPerMillion: settings.chatOutputUsdPerMillion,
  );

  String _costLabel(UsageCost cost) {
    final amount = Pricing.formatUsd(cost.usd);
    return cost.complete ? '≈ $amount' : '≥ $amount';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final months = ref.watch(usageProvider).value ?? const <MonthlyUsage>[];
    final thisKey = MonthlyUsage.keyFor(DateTime.now());
    final current = months.firstWhere(
      (m) => m.month == thisKey,
      orElse: () => MonthlyUsage(month: thisKey),
    );
    final earlier = months.where((m) => m.month != thisKey).toList();
    final cost = _cost(current);
    final pricesSet =
        settings.chatInputUsdPerMillion != null &&
        settings.chatOutputUsdPerMillion != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaperCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FigureRow(
                monthName(thisKey),
                current.isEmpty ? 'nothing yet' : _costLabel(cost),
                emphasis: true,
              ),
              for (final kind in UsageKind.values)
                if (current[kind].requests > 0)
                  FigureRow(
                    '${kind.label} · ${current[kind].requests}×',
                    _tokens(current[kind]),
                  ),
              for (final month in earlier.take(5))
                FigureRow(
                  monthName(month.month),
                  '${compactTokens(month.total.inputTokens + month.total.outputTokens)}'
                  ' tokens · ${_costLabel(_cost(month))}',
                ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        Text(
          pricesSet
              ? 'Counted from the token figures OpenAI sends back with each '
                    'call. An estimate: your OpenAI dashboard has the bill.'
              : 'Fingerprinting is priced; reading screenshots and writing '
                    'replies are not until you enter your chat model’s prices '
                    'below, so the figure above is a floor.',
          style: Type.prose(size: 12.5, color: Paper.muted, height: 1.4),
        ),
        const SizedBox(height: 12),
        _PriceRow(
          input: settings.chatInputUsdPerMillion,
          output: settings.chatOutputUsdPerMillion,
          onSave: onPrices,
        ),
      ],
    );
  }

  static String _tokens(UsageTotals totals) => totals.outputTokens == 0
      ? '${compactTokens(totals.inputTokens)} tokens'
      : '${compactTokens(totals.inputTokens)} in · '
            '${compactTokens(totals.outputTokens)} out';
}

/// The two chat prices, per million tokens, as typed-in dollar amounts.
class _PriceRow extends StatefulWidget {
  const _PriceRow({
    required this.input,
    required this.output,
    required this.onSave,
  });

  final double? input;
  final double? output;
  final void Function(double? input, double? output) onSave;

  @override
  State<_PriceRow> createState() => _PriceRowState();
}

class _PriceRowState extends State<_PriceRow> {
  late final TextEditingController _input = TextEditingController(
    text: _show(widget.input),
  );
  late final TextEditingController _output = TextEditingController(
    text: _show(widget.output),
  );

  static String _show(double? value) => value == null ? '' : '$value';

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _commit() {
    double? parse(String text) {
      final value = double.tryParse(text.trim().replaceAll(r'$', ''));
      return value == null || value < 0 ? null : value;
    }

    final input = parse(_input.text);
    final output = parse(_output.text);
    if (input == widget.input && output == widget.output) return;
    widget.onSave(input, output);
  }

  Widget _field(String label, TextEditingController controller) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Type.strong(size: 13, height: 1.35)),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: Type.numeric(size: 14, weight: FontWeight.w400),
          decoration: paperFieldDecoration(r'$ per 1M'),
          onEditingComplete: _commit,
          onTapOutside: (_) => _commit(),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _field('Chat input price', _input),
      const SizedBox(width: 10),
      _field('Chat output price', _output),
    ],
  );
}
