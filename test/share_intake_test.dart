import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:replylikeme/services/share_intake.dart';

SharedMediaFile file(
  String path, [
  SharedMediaType type = SharedMediaType.file,
]) => SharedMediaFile(path: path, type: type);

void main() {
  test('an export is routed to training', () {
    final item = ShareIntake.itemFrom([
      file('/tmp/WhatsApp Chat with Sam.txt'),
    ]);
    expect(item, isA<SharedExport>());
    expect(item!.name, 'WhatsApp Chat with Sam.txt');
  });

  test('a screenshot is routed to writing a reply', () {
    final item = ShareIntake.itemFrom([file('/tmp/Screenshot_1.PNG')]);
    expect(item, isA<SharedScreenshot>());
    expect((item! as SharedScreenshot).mimeType, 'image/png');
  });

  test('an image the platform labels as one is accepted', () {
    final item = ShareIntake.itemFrom([
      file('/tmp/shared-content-1', SharedMediaType.image),
    ]);
    expect(item, isA<SharedScreenshot>());
    expect((item! as SharedScreenshot).mimeType, 'image/jpeg');
  });

  test('an export wins over a screenshot shared with it', () {
    final item = ShareIntake.itemFrom([
      file('/tmp/a.jpg'),
      file('/tmp/chat.zip'),
    ]);
    expect(item, isA<SharedExport>());
  });

  test('anything else is ignored', () {
    expect(ShareIntake.itemFrom([file('/tmp/song.mp3')]), isNull);
    expect(ShareIntake.itemFrom(const []), isNull);
  });
}
