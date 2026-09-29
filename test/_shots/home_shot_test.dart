import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:replylikeme/models/chat_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_smoke_test.dart';

Future<void> loadFonts() async {
  final loader = FontLoader('Nunito');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Nunito-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

void main() {
  testWidgets('home shot', (tester) async {
    await tester.runAsync(loadFonts);
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(top: 94, bottom: 68);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ReceiveSharingIntent.setMockValues(initialMedia: const [], mediaStream: const Stream.empty());
    await pumpApp(tester, apiKey: 'sk-test-0123456789abcdefghij', store: FakeStore(
      chats: [exampleChat(), exampleChat(id: 2, them: 'Maya').copyWith(app: ChatApp.instagram), exampleChat(id: 3, them: 'Noa')],
      rows: [exampleExchange(), exampleExchange(chatId: 2), exampleExchange(chatId: 3)],
    ));
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('home.png'));
  });
}
