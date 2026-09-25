import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

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

  static String read(List<int> bytes, {String? filename}) {
    if (bytes.isEmpty) {
      throw const ChatExportException('That file is empty.');
    }
    final isZip =
        looksLikeZip(bytes) ||
        (filename != null && filename.toLowerCase().endsWith('.zip'));
    return isZip ? _readZip(bytes) : _decodeText(bytes);
  }

  static String _readZip(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object catch (error) {
      throw ChatExportException('That .zip could not be opened ($error).');
    }

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
