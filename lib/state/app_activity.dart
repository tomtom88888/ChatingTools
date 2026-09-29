import 'dart:async';

import 'package:flutter/widgets.dart';

/// Whether the app is in front of the user, and a way to wait until it is.
///
/// When the screen turns off or another app comes to the front, the phone
/// can freeze the app mid-request; the request then fails with a timeout or
/// a dropped connection that has nothing to do with OpenAI. Requests use
/// this to tell that case apart: the app went away since the request began,
/// so it waits to be back in front and tries again instead of failing.
class AppActivity with WidgetsBindingObserver {
  AppActivity._() {
    WidgetsBinding.instance.addObserver(this);
    _state =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  }

  static AppActivity? _instance;

  /// Created on first use, once the Flutter binding exists.
  static AppActivity get instance => _instance ??= AppActivity._();

  late AppLifecycleState _state;
  Completer<void>? _back;

  /// How many times the app has left the foreground since it started.
  int interruptions = 0;

  bool get active => _state == AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_state == AppLifecycleState.resumed &&
        state != AppLifecycleState.resumed) {
      interruptions++;
    }
    _state = state;
    if (active) {
      _back?.complete();
      _back = null;
    }
  }

  /// Completes at once when the app is in front, otherwise when it next is.
  Future<void> whenActive() {
    if (active) return Future.value();
    return (_back ??= Completer<void>()).future;
  }
}
