import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'config.dart';
import 'protocol.dart';

abstract class Relay {
  Future<void> connect(void Function(RelayEvent event) onEvent);

  void hello(String id, String name, {String? room});

  void joinRoom(String room);

  void watchRooms(bool watch);

  void ptt(bool down);

  void photo(String jpegBase64);

  void audio(List<int> pcm);

  Future<void> close();
}

class SocketRelay implements Relay {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;

  @override
  Future<void> connect(void Function(RelayEvent event) onEvent) async {
    await close();
    final channel = WebSocketChannel.connect(Uri.parse(ConnectConfig.url));
    _channel = channel;
    try {
      await channel.ready.timeout(const Duration(seconds: 8));
    } catch (error) {
      await close();
      throw Exception('relay unreachable: $error');
    }
    _sub = channel.stream.listen(
      (Object? message) {
        if (message == null) return;
        final event = eventFromMessage(message);
        if (event != null) onEvent(event);
      },
      onError: (Object error) => onEvent(DisconnectedEvent(error)),
      onDone: () => onEvent(const DisconnectedEvent(null)),
      cancelOnError: true,
    );
  }

  @override
  void hello(String id, String name, {String? room}) {
    _channel?.sink.add(helloMessage(id, name, room: room));
  }

  @override
  void joinRoom(String room) {
    _channel?.sink.add(joinMessage(room));
  }

  @override
  void watchRooms(bool watch) {
    _channel?.sink.add(roomsMessage(watch: watch));
  }

  @override
  void ptt(bool down) {
    _channel?.sink.add(pttMessage(down));
  }

  @override
  void photo(String jpegBase64) {
    _channel?.sink.add(photoMessage(jpegBase64));
  }

  @override
  void audio(List<int> pcm) {
    _channel?.sink.add(pcm);
  }

  @override
  Future<void> close() async {
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    final channel = _channel;
    _channel = null;
    try {
      await channel?.sink.close();
    } catch (_) {
      // Already closed.
    }
  }
}
