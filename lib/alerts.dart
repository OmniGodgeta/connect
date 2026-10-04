import 'package:flutter/services.dart';

/// Foreground notification and the Android back-to-home gesture.
abstract class RoomAlerts {
  Future<bool> requestNotifications();

  Future<void> start(String text);

  Future<void> update(String text);

  Future<void> stop();

  Future<void> background();
}

class NoopAlerts implements RoomAlerts {
  @override
  Future<bool> requestNotifications() async => true;

  @override
  Future<void> start(String text) async {}

  @override
  Future<void> update(String text) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> background() async {}
}

class PlatformAlerts implements RoomAlerts {
  static const _channel = MethodChannel('connect/room');

  @override
  Future<bool> requestNotifications() async {
    try {
      return await _channel.invokeMethod<bool>('notifications') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start(String text) => _send('start', text);

  @override
  Future<void> update(String text) => _send('update', text);

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  @override
  Future<void> background() async {
    try {
      await _channel.invokeMethod<void>('background');
    } catch (_) {}
  }

  Future<void> _send(String method, String text) async {
    try {
      await _channel.invokeMethod<void>(method, <String, String>{'text': text});
    } catch (_) {}
  }
}
