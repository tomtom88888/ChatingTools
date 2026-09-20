import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A screen on warm paper: no app bar, the design's own frame, and the action
/// block seated at the foot of the screen.
///
/// With a [bottom] the content scrolls above it and the actions stay put, which
/// is what the design draws and what a thumb expects. Without one the whole
/// page scrolls.
class PaperScreen extends StatelessWidget {
  const PaperScreen({
    required this.children,
    this.bottom,
    this.padding = Frame.screen,
    this.gap = Frame.gap,
    super.key,
  });

  final List<Widget> children;

  /// The action block, seated at the bottom of the screen.
  final Widget? bottom;

  final EdgeInsets padding;
  final double gap;

  @override
  Widget build(BuildContext context) {
    // The design's frame is measured from the edge of the screen, status bar
    // included, which is how the iOS mock is drawn. On a phone with a taller
    // notch or a three-button navigation bar that is not enough room, so each
    // edge takes whichever is larger: the design's figure, or the system inset
    // plus a little breathing space. Without this the footnote at the foot of
    // every screen sits underneath the navigation bar.
    final insets = MediaQuery.viewPaddingOf(context);
    final frame = EdgeInsets.fromLTRB(
      padding.left,
      padding.top > insets.top + 16 ? padding.top : insets.top + 16,
      padding.right,
      padding.bottom > insets.bottom + 14 ? padding.bottom : insets.bottom + 14,
    );

    final stacked = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) stacked.add(SizedBox(height: gap));
      stacked.add(children[i]);
    }
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: stacked,
    );

    final Widget body;
    if (bottom == null) {
      body = SingleChildScrollView(
        child: Padding(padding: frame, child: column),
      );
    } else {
      body = Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  frame.left,
                  frame.top,
                  frame.right,
                  gap,
                ),
                child: column,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              frame.left,
              0,
              frame.right,
              frame.bottom,
            ),
            child: bottom,
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Paper.bg,
      body: body,
    );
  }
}

/// Wraps a name in Unicode isolate marks before it is dropped into an English
/// sentence.
///
/// Without this a Hebrew or Arabic name reorders the text around it: a row
/// built as "\$me (me) -> \$them" renders with the two names swapped, which
/// reads as though the app learned the wrong person. The isolate tells the
/// bidirectional algorithm to resolve the name on its own and leave the
/// sentence alone. Latin names are unaffected.
String bidiIsolate(String name) =>
    name.isEmpty ? name : '\u2068$name\u2069';

/// The small uppercase mono label that titles a block.
class MonoLabel extends StatelessWidget {
  const MonoLabel(
    this.text, {
    this.color = Paper.muted,
    this.size = 11,
    this.spacing = 0.16,
    super.key,
  });

  final String text;
  final Color color;
  final double size;
  final double spacing;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Type.label(size: size, color: color, spacing: spacing),
  );
}

/// A serif headline, optionally with one italic accent clause.
class SerifTitle extends StatelessWidget {
  const SerifTitle(
    this.text, {
    this.accent,
    this.trailing,
    this.size = 32,
    this.color = Paper.ink,
    super.key,
  });

  final String text;

  /// Rendered italic in the accent colour, immediately after [text].
  final String? accent;

  /// Plain text after the accent clause.
  final String? trailing;

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (accent == null) {
      return Text(text, style: Type.display(size, color: color));
    }
    return Text.rich(
      TextSpan(
        style: Type.display(size, color: color),
        children: [
          TextSpan(text: text),
          TextSpan(text: accent, style: Type.displayItalic(size)),
          if (trailing != null) TextSpan(text: trailing),
        ],
      ),
    );
  }
}

/// White, lifted, rounded — the design's default container for content.
class PaperCard extends StatelessWidget {
  const PaperCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = Corner.card,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final Radius radius;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Paper.card,
      borderRadius: Corner.all(radius),
      boxShadow: Paper.lift,
    ),
    child: child,
  );
}

/// A sunken panel, one step back from the page.
class PaperPanel extends StatelessWidget {
  const PaperPanel({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(15, 13, 15, 13),
    this.radius = Corner.field,
    this.color = Paper.panel,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final Radius radius;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(color: color, borderRadius: Corner.all(radius)),
    child: child,
  );
}

/// The dark card: used for the one thing on a screen that matters most.
class InkCard extends StatelessWidget {
  const InkCard({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(22, 24, 22, 24),
    this.radius = Corner.hero,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final Radius radius;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Paper.ink,
      borderRadius: Corner.all(radius),
    ),
    child: child,
  );
}

/// How prominent an action is.
enum ActionTone {
  /// Ink. The step forward.
  ink,

  /// Terracotta. The one action the screen exists for.
  accent,

  /// Outlined on white. An alternative.
  outline,

  /// Flat panel, dimmed. Present but not yet available.
  disabled,
}

/// A full-width tappable action. [subtitle] and [trailing] give the design's
/// two-line form; without them it is a plain centred button.
class PaperAction extends StatelessWidget {
  const PaperAction({
    required this.title,
    this.subtitle,
    this.onTap,
    this.tone = ActionTone.ink,
    this.trailing,
    this.centred = false,
    this.busy = false,
    this.radius = Corner.action,
    super.key,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final ActionTone tone;
  final Widget? trailing;

  /// A centred label with no subtitle or arrow.
  final bool centred;

  /// Shows a spinner in place of the arrow and blocks the tap.
  final bool busy;

  final Radius radius;

  @override
  Widget build(BuildContext context) {
    final effective = onTap == null || busy ? ActionTone.disabled : tone;
    final (bg, fg, sub, border) = switch (effective) {
      ActionTone.ink => (Paper.ink, Paper.onInk, const Color(0xA6FAF7F0), null),
      ActionTone.accent => (
        Paper.accent,
        Colors.white,
        const Color(0xCCFFFFFF),
        null,
      ),
      ActionTone.outline => (
        Paper.card,
        Paper.ink,
        Paper.tertiary,
        Paper.borderSoft,
      ),
      ActionTone.disabled => (
        tone == ActionTone.ink ? Paper.ink : Paper.panel,
        tone == ActionTone.ink ? Paper.onInk : Paper.ink,
        Paper.secondary,
        null,
      ),
    };

    final label = centred
        ? Center(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: Type.strong(size: 16, color: fg),
            ),
          )
        : Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Type.strong(size: 17, color: fg)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: Type.prose(size: 13, color: sub, height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (busy)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              else
                trailing ??
                    Text('→', style: TextStyle(fontSize: 19, color: fg)),
            ],
          );

    return Opacity(
      opacity: effective == ActionTone.disabled && tone != ActionTone.ink
          ? 0.55
          : (busy ? 0.75 : 1),
      child: Material(
        color: bg,
        borderRadius: Corner.all(radius),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: Corner.all(radius),
          child: Container(
            padding: centred
                ? const EdgeInsets.all(18)
                : const EdgeInsets.fromLTRB(19, 18, 19, 18),
            decoration: BoxDecoration(
              borderRadius: Corner.all(radius),
              border: border == null
                  ? null
                  : Border.all(color: border, width: 1.5),
            ),
            child: label,
          ),
        ),
      ),
    );
  }
}

/// A line of quiet text, centred under an action.
class Footnote extends StatelessWidget {
  const Footnote(this.text, {this.color = Paper.muted, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: Type.prose(size: 12.5, color: color, height: 1.45),
  );
}

/// What a notice means. Each has its own surface in the design.
enum NoticeTone { neutral, caution, failure, success }

/// A short block of text explaining a state, with an optional inline action.
class Notice extends StatelessWidget {
  const Notice(
    this.message, {
    this.tone = NoticeTone.neutral,
    this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String message;
  final NoticeTone tone;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, titleColor) = switch (tone) {
      NoticeTone.neutral => (Paper.panel, Paper.body, Paper.ink),
      NoticeTone.caution => (Paper.warnPanel, Paper.warnText, Paper.accent),
      NoticeTone.failure => (Paper.errorPanel, Paper.errorText, Paper.errorText),
      NoticeTone.success => (Paper.greenPanel, Paper.greenText, Paper.green),
    };

    return PaperPanel(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: Type.strong(size: 13.5, color: titleColor)),
            const SizedBox(height: 5),
          ],
          Text(
            message,
            style: Type.prose(size: 13.5, color: fg, height: 1.45),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: Type.strong(size: 13, color: Paper.accent).copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: Paper.accent.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A label/value row inside a [PaperCard], stacked as the design draws it.
class StackedRow extends StatelessWidget {
  const StackedRow({
    required this.label,
    this.value,
    this.valueChild,
    this.mono = false,
    this.last = false,
    super.key,
  }) : assert(
         value != null || valueChild != null,
         'a row needs either a value or a valueChild',
       );

  final String label;

  /// Plain text value. Use [valueChild] instead when the value mixes scripts.
  final String? value;

  /// A built value, for rows whose content cannot be a single string.
  final Widget? valueChild;

  final bool mono;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: Paper.divider)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Type.prose(size: 12, color: Paper.tertiary, height: 1.3),
        ),
        const SizedBox(height: 3),
        valueChild ??
            Text(
              value!,
              style: mono
                  ? Type.numeric(size: 12.5, weight: FontWeight.w400)
                  : Type.strong(size: 14, height: 1.35),
            ),
      ],
    ),
  );
}

/// Renders `<me> (me) -> <them>` as three separate pieces in a pinned
/// left-to-right row.
///
/// Packed into one string this reorders when either name is written in a
/// right-to-left script: the bidirectional algorithm resolves the neutral
/// characters between two such names against them, and the pair swaps, so the
/// app appears to have learned the wrong person. Separate widgets in a Row
/// with an explicit direction cannot reorder \u2014 position is decided by the
/// widget list, not by the text.
class NamePairValue extends StatelessWidget {
  const NamePairValue({required this.me, required this.them, super.key});

  final String me;
  final String them;

  @override
  Widget build(BuildContext context) {
    final style = Type.strong(size: 14, height: 1.35);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(me, style: style, textDirection: TextDirection.ltr),
          Text(
            ' (me) \u2192 ',
            style: style.copyWith(color: Paper.tertiary),
            textDirection: TextDirection.ltr,
          ),
          Text(them, style: style, textDirection: TextDirection.ltr),
        ],
      ),
    );
  }
}

/// A right-aligned figure against a left-aligned name.
class FigureRow extends StatelessWidget {
  const FigureRow(this.label, this.value, {this.emphasis = false, super.key});

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3.5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: Type.prose(
              size: 13,
              color: emphasis ? Paper.ink : Paper.tertiary,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: Type.numeric(
            size: 13,
            color: emphasis ? Paper.ink : Paper.tertiary,
            weight: emphasis ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ],
    ),
  );
}

/// The four-segment progress rail at the top of Train, with a back chevron.
class StepRail extends StatelessWidget {
  const StepRail({
    required this.step,
    required this.total,
    this.onBack,
    super.key,
  });

  /// 1-based.
  final int step;
  final int total;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (onBack != null)
        GestureDetector(
          onTap: onBack,
          child: const Padding(
            padding: EdgeInsets.only(right: 14),
            child: Text(
              '←',
              style: TextStyle(fontSize: 19, color: Paper.secondary),
            ),
          ),
        ),
      Expanded(
        child: Row(
          children: [
            for (var i = 1; i <= total; i++) ...[
              if (i > 1) const SizedBox(width: 5),
              Expanded(
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: i <= step ? Paper.accent : Paper.borderSoft,
                    borderRadius: Corner.all(Corner.pill),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(width: 14),
      Text('$step/$total', style: Type.numeric(size: 11, color: Paper.muted)),
    ],
  );
}

/// A numbered instruction list on a white card.
class NumberedSteps extends StatelessWidget {
  const NumberedSteps(this.steps, {super.key});

  /// Each entry is rendered as prose; `*emphasis*` marks bold runs.
  final List<String> steps;

  @override
  Widget build(BuildContext context) => PaperCard(
    radius: Corner.steps,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: i == steps.length - 1
                  ? null
                  : const Border(bottom: BorderSide(color: Paper.divider)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    (i + 1).toString().padLeft(2, '0'),
                    style: Type.numeric(size: 12, color: Paper.accent),
                  ),
                ),
                Expanded(child: emphasised(steps[i], size: 14.5)),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Renders `*bold*` runs inside otherwise plain prose, which is how the design
/// stresses the words a user has to look for in another app's menus.
Widget emphasised(
  String source, {
  double size = 14,
  Color color = Paper.ink,
  double height = 1.45,
}) {
  final base = Type.prose(size: size, color: color, height: height);
  final spans = <TextSpan>[];
  var bold = false;
  for (final part in source.split('*')) {
    if (part.isNotEmpty) {
      spans.add(
        TextSpan(
          text: part,
          style: bold ? base.copyWith(fontWeight: FontWeight.w600) : base,
        ),
      );
    }
    bold = !bold;
  }
  return Text.rich(TextSpan(style: base, children: spans));
}
