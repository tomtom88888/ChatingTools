import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_app.dart';
import '../state/providers.dart';

/// Which app each learned chat came from, for every screen below it, so a
/// bubble can be drawn in its own chat's colours.
class ChatApps extends InheritedWidget {
  const ChatApps({required this.apps, required super.child, super.key});

  final Map<int, ChatApp> apps;

  /// The app of chat [chatId]; WhatsApp when unknown.
  static ChatApp of(BuildContext context, int? chatId) {
    final scope = context.dependOnInheritedWidgetOfExactType<ChatApps>();
    return scope?.apps[chatId] ?? ChatApp.whatsapp;
  }

  @override
  bool updateShouldNotify(ChatApps oldWidget) =>
      !mapEquals(apps, oldWidget.apps);
}

/// Keeps [ChatApps] in step with the learned chats.
class ChatAppsScope extends ConsumerWidget {
  const ChatAppsScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(chatsProvider).value ?? const [];
    return ChatApps(apps: {for (final c in chats) c.id: c.app}, child: child);
  }
}
