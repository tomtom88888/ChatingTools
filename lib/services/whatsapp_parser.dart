import '../models/chat_message.dart';
import '../models/chat_turn.dart';
import '../models/exchange.dart';
import '../models/parsed_chat.dart';

/// Parses WhatsApp "Export chat" text files into messages, turns and
/// training exchanges.
///
/// Handles both layouts WhatsApp produces:
///
/// * Android — `12/03/2023, 19:45 - Alice: hello`
/// * iOS     — `[12/03/2023, 19:45:12] Alice: hello`
///
/// plus 12-hour clocks, day-first / month-first / ISO dates, multi-line
/// messages, media and deleted placeholders, edit markers, and the system
/// lines WhatsApp writes itself.
///
/// This class is deliberately free of any Flutter dependency so it can be
/// unit-tested with plain `dart test`.
class WhatsAppParser {
  const WhatsAppParser._();

  /// `[12/03/2023, 19:45:12] rest`
  static final RegExp _iosLine = RegExp(
    r'^\['
    r'(?<date>\d{1,4}[./-]\d{1,2}[./-]\d{2,4})'
    r',?\s+'
    r'(?<time>\d{1,2}:\d{2}(?::\d{2})?)'
    r'\s*(?<ampm>[AaPp]\.?[Mm]\.?)?'
    r'\]\s*'
    r'(?<rest>.*)$',
  );

  /// `12/03/2023, 19:45 - rest`
  static final RegExp _androidLine = RegExp(
    r'^'
    r'(?<date>\d{1,4}[./-]\d{1,2}[./-]\d{2,4})'
    r',?\s+'
    r'(?<time>\d{1,2}:\d{2}(?::\d{2})?)'
    r'\s*(?<ampm>[AaPp]\.?[Mm]\.?)?'
    r'\s+-\s'
    r'(?<rest>.*)$',
  );

  /// Splits `Alice: hello` into sender and body. Sender names are capped and
  /// may not contain a colon, which is what separates a real message from a
  /// system line such as `Alice changed the group description`.
  static final RegExp _senderSplit = RegExp(
    r'^(?<sender>[^:\n]{1,80}?):[ \u00a0]?(?<body>.*)$',
  );

  static final RegExp _editedMarker = RegExp(
    r'\s*<[^<>]*(?:edited|bearbeitet|modifi\w*)[^<>]*>\s*$',
    caseSensitive: false,
  );

  static final RegExp _attachedMarker = RegExp(
    r'^<attached:.*>$|\(file attached\)$',
    caseSensitive: false,
  );

  /// `image omitted`, `<Media omitted>`, `sticker omitted`, ...
  static final RegExp _omittedMarker = RegExp(
    r'^<?\s*(?:[\w -]{0,24}\s)?omitted\s*>?$',
    caseSensitive: false,
  );

  static const Set<String> _deletedBodies = {
    'this message was deleted',
    'this message was deleted.',
    'you deleted this message',
    'you deleted this message.',
    'this message was deleted by an admin',
    'null',
  };

  /// Bidi marks and exotic spaces WhatsApp sprinkles into exports. Left in
  /// place they break every regex below.
  static const List<String> _invisibleChars = [
    '\u200e', // LEFT-TO-RIGHT MARK
    '\u200f', // RIGHT-TO-LEFT MARK
    '\ufeff', // BOM / ZERO WIDTH NO-BREAK SPACE
    '\u2066', '\u2067', '\u2068', '\u2069', // isolates
  ];

  /// Parses [raw] export text. Never throws on malformed input: lines it
  /// cannot understand are counted in [ParsedChat.unparsedLineCount].
  static ParsedChat parse(String raw, {Duration maxTurnGap = defaultTurnGap}) {
    final normalised = normalise(raw);
    if (normalised.trim().isEmpty) return ParsedChat.empty;

    final lines = normalised.split('\n');

    // Pass 1 — find the timestamp layout and the date component order, both of
    // which are properties of the file as a whole rather than of one line.
    var iosHits = 0;
    var androidHits = 0;
    final dateStrings = <String>[];
    for (final line in lines) {
      final ios = _iosLine.firstMatch(line);
      if (ios != null) {
        iosHits++;
        dateStrings.add(ios.namedGroup('date')!);
        continue;
      }
      final android = _androidLine.firstMatch(line);
      if (android != null) {
        androidHits++;
        dateStrings.add(android.namedGroup('date')!);
      }
    }
    if (iosHits == 0 && androidHits == 0) {
      return ParsedChat(
        messages: const [],
        turns: const [],
        format: ExportFormat.unknown,
        senderMessageCounts: const {},
        mediaCount: 0,
        deletedCount: 0,
        systemCount: 0,
        unparsedLineCount: lines.where((l) => l.trim().isNotEmpty).length,
      );
    }
    final format = iosHits >= androidHits
        ? ExportFormat.ios
        : ExportFormat.android;
    final dateOrder = _inferDateOrder(dateStrings);

    // Pass 2 — build messages, folding continuation lines into their parent.
    final messages = <ChatMessage>[];
    var unparsed = 0;
    for (final line in lines) {
      final match = _iosLine.firstMatch(line) ?? _androidLine.firstMatch(line);
      if (match == null) {
        // Continuation of a multi-line message, or junk before the first one.
        if (messages.isEmpty) {
          if (line.trim().isNotEmpty) unparsed++;
          continue;
        }
        final previous = messages.removeLast();
        if (previous.kind == MessageKind.text) {
          messages.add(
            previous.copyWith(
              text: '${previous.text}\n$line',
              rawText: '${previous.rawText}\n$line',
            ),
          );
        } else {
          // Don't graft stray text onto a media or system placeholder.
          messages.add(previous);
          if (line.trim().isNotEmpty) unparsed++;
        }
        continue;
      }

      final timestamp = _parseTimestamp(
        match.namedGroup('date')!,
        match.namedGroup('time')!,
        match.namedGroup('ampm'),
        dateOrder,
      );
      messages.add(_buildMessage(match.namedGroup('rest')!, timestamp));
    }

    // Trim the trailing blank lines that a final newline folds in.
    if (messages.isNotEmpty) {
      final last = messages.removeLast();
      messages.add(
        last.kind == MessageKind.text
            ? last.copyWith(text: last.text.replaceAll(RegExp(r'\n+$'), ''))
            : last,
      );
    }

    final counts = <String, int>{};
    var media = 0;
    var deleted = 0;
    var system = 0;
    for (final m in messages) {
      switch (m.kind) {
        case MessageKind.system:
          system++;
        case MessageKind.media:
          media++;
        case MessageKind.deleted:
          deleted++;
        case MessageKind.text:
          break;
      }
      final sender = m.sender;
      if (sender != null) counts[sender] = (counts[sender] ?? 0) + 1;
    }
    final sortedSenders = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ParsedChat(
      messages: messages,
      turns: mergeTurns(messages, maxGap: maxTurnGap),
      format: format,
      senderMessageCounts: Map.fromEntries(sortedSenders),
      mediaCount: media,
      deletedCount: deleted,
      systemCount: system,
      unparsedLineCount: unparsed,
    );
  }

  /// Strips bidi marks and folds exotic spaces so the line regexes can work.
  static String normalise(String raw) {
    var out = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    for (final ch in _invisibleChars) {
      out = out.replaceAll(ch, '');
    }
    return out
        .replaceAll('\u202f', ' ') // NARROW NO-BREAK SPACE, used before AM/PM
        .replaceAll('\u00a0', ' ');
  }

  /// How far apart two messages from one sender may be and still count as the
  /// same turn. Beyond this they are separate thoughts, not one split bubble.
  static const Duration defaultTurnGap = Duration(minutes: 60);

  /// Merges consecutive style-carrying messages from one sender into a turn.
  ///
  /// Media, deleted and system messages are skipped rather than ending a turn:
  /// a photo in the middle of someone typing is not a change of speaker. A gap
  /// longer than [maxGap] does end the turn, so yesterday's last message and
  /// this morning's first never merge. Messages without a usable timestamp are
  /// merged on sender alone.
  ///
  /// Because skipping non-text messages can leave two same-sender turns next to
  /// each other, [buildExchanges] checks who spoke last rather than assuming
  /// turns alternate.
  static List<ChatTurn> mergeTurns(
    List<ChatMessage> messages, {
    Duration maxGap = defaultTurnGap,
  }) {
    final turns = <ChatTurn>[];
    final pending = <ChatMessage>[];

    void flush() {
      if (pending.isEmpty) return;
      turns.add(ChatTurn.fromMessages(List.of(pending)));
      pending.clear();
    }

    for (final message in messages) {
      if (!message.carriesStyle) continue;
      if (pending.isNotEmpty) {
        final previous = pending.last;
        final changedSpeaker = previous.sender != message.sender;
        final previousAt = previous.timestamp;
        final currentAt = message.timestamp;
        final tooFarApart =
            previousAt != null &&
            currentAt != null &&
            currentAt.difference(previousAt).abs() > maxGap;
        if (changedSpeaker || tooFarApart) flush();
      }
      pending.add(message);
    }
    flush();
    return turns;
  }

  /// Builds `their turn(s) -> my reply` training examples.
  ///
  /// [maxContextTurns] bounds how far back each example reaches. Openers (a
  /// message of mine with nothing before it) are skipped, because there is no
  /// context to retrieve them by.
  static List<Exchange> buildExchanges(
    List<ChatTurn> turns, {
    required String me,
    int maxContextTurns = 10,
  }) {
    if (maxContextTurns < 1) {
      throw ArgumentError.value(
        maxContextTurns,
        'maxContextTurns',
        'must be at least 1',
      );
    }
    final exchanges = <Exchange>[];
    for (var i = 0; i < turns.length; i++) {
      final turn = turns[i];
      if (turn.sender != me) continue;
      if (i == 0) continue; // an opener, not a reply
      final start = i - maxContextTurns < 0 ? 0 : i - maxContextTurns;
      final context = turns.sublist(start, i);
      if (context.isEmpty || context.last.sender == me) continue;
      exchanges.add(Exchange(context: context, reply: turn));
    }
    return exchanges;
  }

  // ---------------------------------------------------------------- internals

  static ChatMessage _buildMessage(String rest, DateTime? timestamp) {
    final trimmedRest = rest.trimRight();
    final split = _senderSplit.firstMatch(trimmedRest);
    if (split == null) {
      // No `Sender: ` prefix — WhatsApp wrote this line itself.
      return ChatMessage(
        sender: null,
        timestamp: timestamp,
        text: '',
        rawText: trimmedRest,
        kind: MessageKind.system,
      );
    }

    final sender = split.namedGroup('sender')!.trim();
    final rawBody = split.namedGroup('body')!;
    var body = rawBody.trim();

    final wasEdited = _editedMarker.hasMatch(body);
    if (wasEdited) body = body.replaceAll(_editedMarker, '').trim();

    if (_deletedBodies.contains(body.toLowerCase())) {
      return ChatMessage(
        sender: sender,
        timestamp: timestamp,
        text: '',
        rawText: rawBody.trim(),
        kind: MessageKind.deleted,
        wasEdited: wasEdited,
      );
    }
    if (_omittedMarker.hasMatch(body) || _attachedMarker.hasMatch(body)) {
      return ChatMessage(
        sender: sender,
        timestamp: timestamp,
        text: '',
        rawText: rawBody.trim(),
        kind: MessageKind.media,
        wasEdited: wasEdited,
      );
    }
    return ChatMessage(
      sender: sender,
      timestamp: timestamp,
      text: body,
      rawText: rawBody.trim(),
      kind: MessageKind.text,
      wasEdited: wasEdited,
    );
  }

  static _DateOrder _inferDateOrder(List<String> dates) {
    var sawFourDigitFirst = false;
    var firstExceedsTwelve = false;
    var secondExceedsTwelve = false;
    for (final date in dates) {
      final parts = date.split(RegExp(r'[./-]'));
      if (parts.length != 3) continue;
      if (parts[0].length == 4) {
        sawFourDigitFirst = true;
        continue;
      }
      final first = int.tryParse(parts[0]);
      final second = int.tryParse(parts[1]);
      if (first != null && first > 12) firstExceedsTwelve = true;
      if (second != null && second > 12) secondExceedsTwelve = true;
    }
    if (sawFourDigitFirst) return _DateOrder.isoFirst;
    if (firstExceedsTwelve) return _DateOrder.dayFirst;
    if (secondExceedsTwelve) return _DateOrder.monthFirst;
    // Ambiguous (every date <= 12/12). Day-first is the WhatsApp default
    // outside the US, and timestamps here only drive ordering anyway.
    return _DateOrder.dayFirst;
  }

  static DateTime? _parseTimestamp(
    String date,
    String time,
    String? ampm,
    _DateOrder order,
  ) {
    final dateParts = date.split(RegExp(r'[./-]'));
    if (dateParts.length != 3) return null;
    final a = int.tryParse(dateParts[0]);
    final b = int.tryParse(dateParts[1]);
    final c = int.tryParse(dateParts[2]);
    if (a == null || b == null || c == null) return null;

    final int year;
    final int month;
    final int day;
    switch (order) {
      case _DateOrder.isoFirst:
        year = a;
        month = b;
        day = c;
      case _DateOrder.monthFirst:
        year = _expandYear(c);
        month = a;
        day = b;
      case _DateOrder.dayFirst:
        year = _expandYear(c);
        month = b;
        day = a;
    }

    final timeParts = time.split(':');
    var hour = int.tryParse(timeParts[0]) ?? 0;
    final minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0;
    final second = timeParts.length > 2 ? int.tryParse(timeParts[2]) ?? 0 : 0;

    if (ampm != null) {
      final isPm = ampm.toLowerCase().startsWith('p');
      if (isPm && hour < 12) {
        hour += 12;
      } else if (!isPm && hour == 12) {
        hour = 0;
      }
    }

    if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23) {
      return null;
    }
    return DateTime(year, month, day, hour, minute, second);
  }

  static int _expandYear(int value) {
    if (value >= 100) return value;
    // WhatsApp only ever wrote two-digit years in this century.
    return 2000 + value;
  }
}

enum _DateOrder { dayFirst, monthFirst, isoFirst }
