import '../models/chat_message.dart';
import '../models/extracted_message.dart';
import 'whatsapp_parser.dart';

/// Turns a pasted conversation into messages, as an alternative to reading a
/// screenshot.
///
/// Pasting skips the vision call — the slowest and dearest step — and can't
/// misread a bubble. It accepts, in order of preference:
///
/// 1. export-style lines (`12/03/2023, 19:45 - Sam: hi`), including what
///    WhatsApp puts on the clipboard when you copy several messages
///    (`[19:45, 12/03/2023] Sam: hi`);
/// 2. `Name: text` lines, where the name is you, "me" or "I" for your side;
/// 3. anything else, one message per line, all from them — sides can be
///    flipped on the next screen, exactly as after reading a screenshot.
class PastedConversation {
  const PastedConversation._();

  /// A leading `[...]` stamp, as WhatsApp's copy puts before each message.
  static final RegExp _bracketStamp = RegExp(r'^\[[^\]\n]{3,40}\]\s*');

  static final RegExp _named = RegExp(
    r'^(?<sender>[^:"\n]{1,40}?):[  ]?(?<body>.*)$',
  );

  static const Set<String> _selfNames = {'me', 'i', 'myself', 'you (me)'};

  static List<ExtractedMessage> parse(String raw, {required String myName}) {
    final text = WhatsAppParser.normalise(raw).trim();
    if (text.isEmpty) return const [];

    bool isMe(String sender) {
      final s = sender.trim().toLowerCase();
      return _selfNames.contains(s) ||
          (myName.isNotEmpty && s == myName.trim().toLowerCase());
    }

    // An export, or an export-shaped copy.
    final parsed = WhatsAppParser.parse(text);
    final exportMessages = parsed.messages
        .where((m) => m.kind == MessageKind.text && m.sender != null)
        .toList();
    if (exportMessages.isNotEmpty) {
      return [
        for (final m in exportMessages)
          ExtractedMessage(
            speaker: isMe(m.sender!) ? Speaker.me : Speaker.them,
            text: m.text,
          ),
      ];
    }

    final out = <ExtractedMessage>[];
    final lines = text.split('\n');
    final anyNamed = lines.any(
      (l) => _named.hasMatch(l.replaceFirst(_bracketStamp, '').trim()),
    );
    for (final rawLine in lines) {
      final line = rawLine.replaceFirst(_bracketStamp, '').trim();
      if (line.isEmpty) continue;
      final match = anyNamed ? _named.firstMatch(line) : null;
      if (match != null) {
        final body = match.namedGroup('body')!.trim();
        if (body.isEmpty) continue;
        out.add(
          ExtractedMessage(
            speaker: isMe(match.namedGroup('sender')!)
                ? Speaker.me
                : Speaker.them,
            text: body,
          ),
        );
      } else if (anyNamed && out.isNotEmpty) {
        // A line with no name continues the message above it.
        final last = out.removeLast();
        out.add(last.copyWith(text: '${last.text}\n$line'));
      } else {
        out.add(ExtractedMessage(speaker: Speaker.them, text: line));
      }
    }
    return out;
  }
}
