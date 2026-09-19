import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replylikeme/services/chat_export_reader.dart';

void main() {
  final androidExport = File('test/fixtures/android_export.txt')
      .readAsStringSync();

  List<int> zipWith(Map<String, String> entries) {
    final archive = Archive();
    entries.forEach((name, content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile.bytes(name, bytes));
    });
    return ZipEncoder().encode(archive);
  }

  group('plain text', () {
    test('reads a .txt export', () {
      final text = ChatExportReader.read(
        utf8.encode(androidExport),
        filename: 'WhatsApp Chat with Sam.txt',
      );
      expect(text, androidExport);
    });

    test('strips a UTF-8 BOM', () {
      final text = ChatExportReader.read(utf8.encode('\ufeffhello'));
      expect(text, 'hello');
    });

    test('survives a malformed byte instead of losing the chat', () {
      final text = ChatExportReader.read([...utf8.encode('hi'), 0xff]);
      expect(text, startsWith('hi'));
    });

    test('rejects an empty file with a readable message', () {
      expect(
        () => ChatExportReader.read(const []),
        throwsA(
          isA<ChatExportException>().having(
            (e) => e.message,
            'message',
            contains('empty'),
          ),
        ),
      );
    });
  });

  group('zip', () {
    test('pulls the transcript out of a WhatsApp zip', () {
      final bytes = zipWith({
        'WhatsApp Chat with Sam.txt': androidExport,
        '00000042-PHOTO-2023-03-13-19-46-40.jpg': 'not really a photo',
      });
      expect(ChatExportReader.read(bytes), androidExport);
    });

    test('is detected by magic number even without the extension', () {
      final bytes = zipWith({'chat.txt': androidExport});
      expect(ChatExportReader.looksLikeZip(bytes), isTrue);
      expect(
        ChatExportReader.read(bytes, filename: 'share-target'),
        androidExport,
      );
    });

    test('picks the largest transcript when there are several', () {
      final bytes = zipWith({
        'short.txt': 'tiny',
        'WhatsApp Chat with Sam.txt': androidExport,
      });
      expect(ChatExportReader.read(bytes), androidExport);
    });

    test('explains a zip with no transcript in it', () {
      final bytes = zipWith({'photo.jpg': 'nope'});
      expect(
        () => ChatExportReader.read(bytes),
        throwsA(
          isA<ChatExportException>().having(
            (e) => e.message,
            'message',
            contains('no .txt transcript'),
          ),
        ),
      );
    });

    test('explains a corrupt zip', () {
      final bytes = [0x50, 0x4b, 0x03, 0x04, 0x00, 0x01, 0x02];
      expect(
        () => ChatExportReader.read(bytes, filename: 'broken.zip'),
        throwsA(isA<ChatExportException>()),
      );
    });
  });
}
