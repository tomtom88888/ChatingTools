import 'dart:async';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// A chat export handed to the app by the Android/iOS share sheet.
class SharedExport {
  const SharedExport({required this.path, required this.name});

  final String path;
  final String name;
}

/// Wraps receive_sharing_intent so the screens deal in [SharedExport] rather
/// than platform media types.
class ShareIntake {
  const ShareIntake._();

  static const Set<String> _acceptedExtensions = {'.txt', '.zip'};

  /// Anything shared while the app was already running.
  static Stream<SharedExport> stream() => ReceiveSharingIntent.instance
      .getMediaStream()
      .map(exportFrom)
      .where((export) => export != null)
      .cast<SharedExport>();

  /// Whatever launched the app, if it was launched by a share.
  static Future<SharedExport?> initial() async =>
      exportFrom(await ReceiveSharingIntent.instance.getInitialMedia());

  /// Tells the platform the shared payload has been consumed, so it isn't
  /// delivered again on the next launch.
  static Future<void> markHandled() => ReceiveSharingIntent.instance.reset();

  /// Picks the first shared file that could be a WhatsApp export.
  static SharedExport? exportFrom(List<SharedMediaFile> files) {
    for (final file in files) {
      final path = file.path;
      final lower = path.toLowerCase();
      final matches = _acceptedExtensions.any(lower.endsWith);
      if (!matches) continue;
      final separator = path.lastIndexOf(RegExp(r'[/\\]'));
      return SharedExport(
        path: path,
        name: separator == -1 ? path : path.substring(separator + 1),
      );
    }
    return null;
  }
}
