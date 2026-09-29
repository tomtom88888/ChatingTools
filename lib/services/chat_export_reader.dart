import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'instagram_parser.dart';

/// What an import file turned out to hold.
sealed class ChatSource {
  const ChatSource();
}

/// A WhatsApp export's text, still to be parsed.
class WhatsAppSource extends ChatSource {
  const WhatsAppSource(this.text);

  final String text;
}

/// The conversations in an Instagram export, most recent first. A zip of a
/// whole account holds many; a single `message_1.json` holds one.
class InstagramSource extends ChatSource {
  const InstagramSource(this.threads);

  final List<InstagramThread> threads;
}

/// Raised when an import file cannot be turned into export text.
class ChatExportException implements Exception {
  const ChatExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Turns whatever the user picked — a `.txt` export or the `.zip` WhatsApp
/// produces when the chat includes media — into export text.
///
/// Pure Dart, so it is unit-testable without a device.
class ChatExportReader {
  const ChatExportReader._();

  /// ZIP local-file-header magic: `PK\x03\x04`.
  static bool looksLikeZip(List<int> bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07);

  /// Reads export text from [bytes]. [filename] is only a hint; the ZIP magic
  /// number wins, because share-sheet intents often lose the extension.
  /// The chat's name from an export's filename, which WhatsApp builds from
  /// it: "WhatsApp Chat with Family.txt" (Android), "WhatsApp Chat - Family
  /// .zip" (iOS). `null` when the name carries none, as the "_chat.txt"
  /// inside an iOS zip does.
  static String? chatNameFromFilename(String filename) {
    var name = filename.split(RegExp(r'[/\\]')).last;
    name = name.replaceFirst(RegExp(r'\.(txt|zip)$', caseSensitive: false), '');
    // A copy the phone renamed: "… (1)".
    name = name.replaceFirst(RegExp(r'\s*\(\d+\)$'), '');
    final match = RegExp(
      r'^WhatsApp\s+Chat\s*(?:with|-|–|—)\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(name.trim());
    final result = match?.group(1)?.trim();
    return result == null || result.isEmpty ? null : result;
  }

  /// Works out what [bytes] hold: a WhatsApp export (`.txt`, or the `.zip`
  /// WhatsApp makes), or Instagram's JSON (one `message_N.json`, or the zip
  /// of a "Download your information" export).
  static ChatSource open(List<int> bytes, {String? filename}) {
    if (bytes.isEmpty) {
      throw const ChatExportException('That file is empty.');
    }
    final isZip =
        looksLikeZip(bytes) ||
        (filename != null && filename.toLowerCase().endsWith('.zip'));
    if (!isZip) {
      final text = _decodeText(bytes);
      if (InstagramParser.looksLikeThread(text)) {
        final thread = InstagramParser.thread([text]);
        if (thread.messages.isEmpty) {
          throw const ChatExportException(
            'That Instagram file has no messages in it.',
          );
        }
        return InstagramSource([thread]);
      }
      return WhatsAppSource(text);
    }

    final archive = _openZip(bytes);
    final threadFiles = <String, List<ArchiveFile>>{};
    for (final f in archive.files) {
      if (f.isFile && InstagramParser.isThreadFile(f.name)) {
        (threadFiles[InstagramParser.threadFolder(f.name)] ??= []).add(f);
      }
    }
    if (threadFiles.isEmpty) return WhatsAppSource(_transcriptIn(archive));
    final threads = [
      for (final files in threadFiles.values)
        InstagramParser.thread([for (final f in files) _decodeText(f.content)]),
    ].where((t) => t.messages.isNotEmpty).toList();
    if (threads.isEmpty) {
      throw const ChatExportException(
        'That Instagram export has no messages in it. When you ask Instagram '
        'for your information, tick Messages and choose JSON.',
      );
    }
    threads.sort((a, b) {
      final x = a.lastAt;
      final y = b.lastAt;
      if (x == null || y == null) return b.size.compareTo(a.size);
      return y.compareTo(x);
    });
    return InstagramSource(threads);
  }

  static String read(List<int> bytes, {String? filename}) {
    if (bytes.isEmpty) {
      throw const ChatExportException('That file is empty.');
    }
    final isZip =
        looksLikeZip(bytes) ||
        (filename != null && filename.toLowerCase().endsWith('.zip'));
    return isZip ? _readZip(bytes) : _decodeText(bytes);
  }

  static String _readZip(List<int> bytes) => _transcriptIn(_openZip(bytes));

  static Archive _openZip(List<int> bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } on Object catch (error) {
      throw ChatExportException('That .zip could not be opened ($error).');
    }
  }

  static String _transcriptIn(Archive archive) {
    // WhatsApp puts exactly one .txt transcript in the archive alongside the
    // media; if there are several, the largest is the transcript.
    final candidates =
        archive.files
            .where((f) => f.isFile && f.name.toLowerCase().endsWith('.txt'))
            .toList()
          ..sort((a, b) => b.size.compareTo(a.size));

    if (candidates.isEmpty) {
      throw const ChatExportException(
        'That .zip has no .txt transcript in it. Export the chat again and '
        'pick the zip WhatsApp offers you.',
      );
    }
    return _decodeText(candidates.first.content);
  }

  static String _decodeText(List<int> bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    // WhatsApp writes UTF-8. allowMalformed keeps one bad byte from losing an
    // entire chat history.
    var text = const Utf8Decoder(allowMalformed: true).convert(data);
    if (text.startsWith('\ufeff')) text = text.substring(1);
    return text;
  }
}
