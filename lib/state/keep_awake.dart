import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the app running while it has work in progress, even when the screen
/// turns off or another app comes to the front.
///
/// Android freezes or kills a backgrounded app to save battery, and its
/// requests die with it. While anything holds this, a foreground service
/// runs, with a "Ditto is working" notification, and Android leaves the app
/// and its network alone. It stops a few seconds after the last hold is let
/// go, so back-to-back requests don't flash the notification on and off.
///
/// iOS has nothing like it; there, requests that the phone cut off wait for
/// the app to come back and try again (see [AppActivity]).
class KeepAwake {
  KeepAwake._();

  static final KeepAwake instance = KeepAwake._();

  /// Only Android has the service, and never under tests.
  static bool get supported =>
      !kIsWeb &&
      Platform.isAndroid &&
      !Platform.environment.containsKey('FLUTTER_TEST');

  static const Duration linger = Duration(seconds: 4);

  int _holds = 0;
  Timer? _stop;
  bool _running = false;
  bool _initialised = false;
  bool _askedToNotify = false;

  /// What the notification says.
  String _text = 'Working…';

  /// Holds the app awake while [work] runs.
  Future<T> during<T>(Future<T> Function() work) async {
    hold();
    try {
      return await work();
    } finally {
      release();
    }
  }

  void hold() {
    _holds++;
    _stop?.cancel();
    _stop = null;
    if (!_running && supported) unawaited(_start());
  }

  void release() {
    if (_holds > 0) _holds--;
    if (_holds > 0 || !supported) return;
    _stop?.cancel();
    _stop = Timer(linger, () {
      _stop = null;
      if (_holds == 0) unawaited(_end());
    });
  }

  /// Says what is being done, in the notification.
  void describe(String text) {
    if (text == _text) return;
    _text = text;
    if (_running) {
      unawaited(FlutterForegroundTask.updateService(notificationText: text));
    }
  }

  Future<void> _start() async {
    _running = true;
    try {
      if (!_initialised) {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'ditto_working',
            channelName: 'Work in progress',
            channelDescription:
                'Shown while Ditto imports a chat or talks to the AI, so '
                'the work carries on with the screen off.',
            onlyAlertOnce: true,
          ),
          iosNotificationOptions: const IOSNotificationOptions(
            showNotification: false,
          ),
          foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.nothing(),
            allowWakeLock: true,
            allowWifiLock: true,
            allowAutoRestart: false,
          ),
        );
        _initialised = true;
      }
      // Without it the service still runs, just without a visible
      // notification; ask once.
      if (!_askedToNotify) {
        _askedToNotify = true;
        final permission =
            await FlutterForegroundTask.checkNotificationPermission();
        if (permission != NotificationPermission.granted) {
          await FlutterForegroundTask.requestNotificationPermission();
        }
      }
      if (await FlutterForegroundTask.isRunningService) return;
      final result = await FlutterForegroundTask.startService(
        serviceId: 4242,
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: 'Ditto is working',
        notificationText: _text,
      );
      if (result is ServiceRequestFailure) _running = false;
    } on Object {
      // Keeping awake is a nicety: the work goes on without it, and a
      // request the phone cuts off still waits for the app to come back.
      _running = false;
    }
    // Everything may have finished while the service was starting.
    if (_running && _holds == 0 && _stop == null) release();
  }

  Future<void> _end() async {
    if (!_running) return;
    _running = false;
    try {
      await FlutterForegroundTask.stopService();
    } on Object {
      // Already gone.
    }
  }
}
