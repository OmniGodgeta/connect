import 'package:flutter/services.dart';

/// Foreground notification and the Android back-to-home gesture.
abstract class RoomAlerts {
  Future<bool> requestNotifications();

  Future<void> start(String text);

  Future<void> update(String text);

  Future<void> stop();

  Future<void> background();

  /// Volume keys talk only while this is armed, which is while a game is
  /// in front. The accessibility service ignores them otherwise.
  Future<void> armKeys(bool on);

  Future<bool> keysGranted();

  Future<bool> overlayGranted();

  Future<void> openKeys();

  Future<void> openOverlay();

  Future<void> showBubble(String text);

  Future<void> hideBubble();
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

  @override
  Future<void> armKeys(bool on) async {}

  @override
  Future<bool> keysGranted() async => true;

  @override
  Future<bool> overlayGranted() async => true;

  @override
  Future<void> openKeys() async {}

  @override
  Future<void> openOverlay() async {}

  @override
  Future<void> showBubble(String text) async {}

  @override
  Future<void> hideBubble() async {}
}

class PlatformAlerts implements RoomAlerts {
  static const _channel = MethodChannel('connect/room');

  void bind(void Function(bool down) onHold) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'volumeDown':
        case 'bubbleDown':
          onHold(true);
        case 'volumeUp':
        case 'bubbleUp':
          onHold(false);
      }
      return null;
    });
  }

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

  @override
  Future<void> armKeys(bool on) async {
    try {
      await _channel.invokeMethod<void>('arm', <String, bool>{'on': on});
    } catch (_) {}
  }

  @override
  Future<bool> keysGranted() async {
    try {
      return await _channel.invokeMethod<bool>('keysGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> overlayGranted() async {
    try {
      return await _channel.invokeMethod<bool>('overlayGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openKeys() async {
    try {
      await _channel.invokeMethod<void>('openKeys');
    } catch (_) {}
  }

  @override
  Future<void> openOverlay() async {
    try {
      await _channel.invokeMethod<void>('openOverlay');
    } catch (_) {}
  }

  @override
  Future<void> showBubble(String text) async {
    try {
      await _channel.invokeMethod<void>('bubble', <String, String>{
        'text': text,
      });
    } catch (_) {}
  }

  @override
  Future<void> hideBubble() async {
    try {
      await _channel.invokeMethod<void>('bubbleHide');
    } catch (_) {}
  }

  Future<void> _send(String method, String text) async {
    try {
      await _channel.invokeMethod<void>(method, <String, String>{'text': text});
    } catch (_) {}
  }
}
