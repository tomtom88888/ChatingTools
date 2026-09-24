import 'dart:async';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Something handed to the app by the Android/iOS share sheet.
sealed class SharedItem {
  const SharedItem({required this.path, required this.name});

  final String path;
  final String name;
}

/// A chat export: goes to Train.
class SharedExport extends SharedItem {
  const SharedExport({required super.path, required super.name});
}

/// A screenshot of a conversation: goes straight to Generate.
class SharedScreenshot extends SharedItem {
  const SharedScreenshot({required super.path, required super.name});

  /// The image type the vision API is told, from the file extension.
  String get mimeType {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}

/// Wraps receive_sharing_intent so the screens deal in [SharedItem] rather
/// than platform media types.
class ShareIntake {
  const ShareIntake._();

  static const Set<String> _exportExtensions = {'.txt', '.zip'};

  /// Formats the vision API accepts. HEIC is not among them, and iOS shares
  /// screenshots as PNG anyway.
  static const Set<String> _imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
  };

  /// Anything shared while the app was already running.
  static Stream<SharedItem> stream() => ReceiveSharingIntent.instance
      .getMediaStream()
      .map(itemFrom)
      .where((item) => item != null)
      .cast<SharedItem>();

  /// Whatever launched the app, if it was launched by a share.
  static Future<SharedItem?> initial() async =>
      itemFrom(await ReceiveSharingIntent.instance.getInitialMedia());

  /// Tells the platform the shared payload has been consumed, so it isn't
  /// delivered again on the next launch.
  static Future<void> markHandled() => ReceiveSharingIntent.instance.reset();

  /// Picks the first shared file that is an export or a screenshot. An export
  /// wins if both were shared, because training is the rarer, deliberate act.
  static SharedItem? itemFrom(List<SharedMediaFile> files) {
    SharedScreenshot? screenshot;
    for (final file in files) {
      final path = file.path;
      final lower = path.toLowerCase();
      final separator = path.lastIndexOf(RegExp(r'[/\\]'));
      final name = separator == -1 ? path : path.substring(separator + 1);
      if (_exportExtensions.any(lower.endsWith)) {
        return SharedExport(path: path, name: name);
      }
      final isImage =
          _imageExtensions.any(lower.endsWith) ||
          file.type == SharedMediaType.image;
      if (isImage) screenshot ??= SharedScreenshot(path: path, name: name);
    }
    return screenshot;
  }
}
