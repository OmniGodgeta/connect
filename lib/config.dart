/// Tailscale address of the relay on this PC.
///
/// Override for a local run:
/// `flutter run --dart-define=CONNECT_URL=ws://10.0.2.2:8792/ws`
abstract final class ConnectConfig {
  static const url = String.fromEnvironment(
    'CONNECT_URL',
    defaultValue: 'wss://retroverse.tail51f9d6.ts.net:8732/ws',
  );

  /// Signed 16-bit little-endian mono PCM. Both phones use this rate.
  static const sampleRate = 16000;
}
