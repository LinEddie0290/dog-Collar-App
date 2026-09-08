import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'collar_data_source.dart';
import 'conn_status.dart';
import 'raw_frame.dart';

/// The real link: connects to the collar's WebSocket over WiFi and streams
/// frames. Delivered after [FakeCollarDataSource] on purpose — the fake source
/// unblocks the UI first; this one plugs in unchanged behind the same interface.
///
/// Assumes the collar runs a WebSocket **server** (typical for embedded
/// devices) and the phone connects as **client** to e.g. `ws://<collar-ip>:81`.
/// Confirm the direction/port/path with whoever builds the collar firmware.
///
/// Uses dart:io's built-in WebSocket — no external package, works on
/// Android/iOS/desktop. For Flutter Web, swap to package:web_socket_channel;
/// the rest of the pipeline is unaffected.
///
/// Reconnection: on any drop/error it emits `reconnecting` and retries with
/// exponential backoff (capped), because pet collars drop off WiFi constantly.
class WebSocketCollarDataSource implements CollarDataSource {
  final String url;
  final Duration initialBackoff;
  final Duration maxBackoff;

  WebSocketCollarDataSource(
    this.url, {
    this.initialBackoff = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 30),
  });

  final _frames = StreamController<RawFrame>.broadcast();
  final _status = StreamController<ConnStatus>.broadcast();

  WebSocket? _ws;
  StreamSubscription? _wsSub;
  bool _closed = false;
  Duration _backoff = const Duration(seconds: 1);

  @override
  Stream<RawFrame> get frames => _frames.stream;

  @override
  Stream<ConnStatus> get status => _status.stream;

  @override
  Future<void> connect() async {
    _backoff = initialBackoff;
    await _connectOnce();
  }

  Future<void> _connectOnce() async {
    if (_closed) return;
    _status.add(ConnStatus.connecting);
    try {
      final ws = await WebSocket.connect(url);
      if (_closed) {
        await ws.close();
        return;
      }
      _ws = ws;
      _backoff = initialBackoff; // reset on success
      _status.add(ConnStatus.connected);
      _wsSub = ws.listen(
        _onMessage,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic data) {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final decoded = jsonDecode(data as String);
      if (decoded is Map<String, dynamic>) {
        _frames.add(RawFrame(now, decoded));
      } else if (decoded is Map) {
        _frames.add(RawFrame(now, Map<String, dynamic>.from(decoded)));
      }
      // Non-object payloads are ignored rather than crashing the stream.
    } catch (_) {
      // A malformed frame must not kill the connection; drop and continue.
    }
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _wsSub?.cancel();
    _wsSub = null;
    _ws = null;
    _status.add(ConnStatus.reconnecting);
    final delay = _backoff;
    _backoff = Duration(
      milliseconds: (_backoff.inMilliseconds * 2)
          .clamp(
            initialBackoff.inMilliseconds,
            maxBackoff.inMilliseconds,
          )
          .toInt(),
    );
    Timer(delay, _connectOnce);
  }

  @override
  Future<void> disconnect() async {
    _closed = true;
    await _wsSub?.cancel();
    await _ws?.close();
    _status.add(ConnStatus.disconnected);
    await _frames.close();
    await _status.close();
  }
}
