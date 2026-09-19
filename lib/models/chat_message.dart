/// What a single exported WhatsApp line turned out to be.
enum MessageKind {
  /// Ordinary text the sender typed. Only these carry style signal.
  text,

  /// A photo/video/sticker/document placeholder such as `<Media omitted>`.
  media,

  /// "This message was deleted" / "You deleted this message".
  deleted,

  /// A line WhatsApp itself wrote: encryption notice, group events, calls.
  system,
}

/// One parsed line (or multi-line block) from a WhatsApp export.
class ChatMessage {
  const ChatMessage({
    required this.sender,
    required this.timestamp,
    required this.text,
    required this.kind,
    required this.rawText,
    this.wasEdited = false,
  });

  /// `null` for [MessageKind.system] lines, which have no sender.
  final String? sender;

  /// `null` when the timestamp could not be understood.
  final DateTime? timestamp;

  /// The message body, with media/deleted placeholders and the
  /// `<This message was edited>` marker removed. Empty for non-text kinds.
  final String text;

  /// The body exactly as it appeared in the export, for display and debugging.
  final String rawText;

  final MessageKind kind;

  final bool wasEdited;

  bool get isText => kind == MessageKind.text;

  /// A text message that actually has content worth learning from.
  bool get carriesStyle => isText && text.trim().isNotEmpty;

  ChatMessage copyWith({String? text, String? rawText}) => ChatMessage(
    sender: sender,
    timestamp: timestamp,
    text: text ?? this.text,
    rawText: rawText ?? this.rawText,
    kind: kind,
    wasEdited: wasEdited,
  );

  @override
  String toString() =>
      'ChatMessage(${kind.name}, ${sender ?? "-"}, $timestamp, "$text")';
}
