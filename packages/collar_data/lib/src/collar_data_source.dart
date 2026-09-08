import 'conn_status.dart';
import 'raw_frame.dart';

/// A source of raw collar frames. Two implementations:
///   * [FakeCollarDataSource]  — generates synthetic data, no hardware needed.
///   * WebSocketCollarDataSource — the real WiFi/WebSocket link.
///
/// The repository and UI depend only on this interface, so you can develop and
/// test the whole pipeline against the fake source and swap in the real one
/// later without touching anything downstream.
abstract class CollarDataSource {
  /// Raw frames as they arrive. Broadcast: survives reconnects, multiple
  /// listeners allowed.
  Stream<RawFrame> get frames;

  /// Connection state transitions.
  Stream<ConnStatus> get status;

  /// Begin connecting (and, for the real source, keep reconnecting on drop).
  Future<void> connect();

  /// Stop and release resources.
  Future<void> disconnect();
}
