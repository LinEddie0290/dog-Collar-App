// にせ首輪 (mock collar) — 別プロセスで動く WebSocket サーバー。
//
// package:collar_data の FakeCollarDataSource はアプリの中だけで完結するが、
// こちらは実際に WiFi/WebSocket 経由での通信を、実機を使わずに確認したい時に使う。
//
// 使い方:
//   dart run tools/mock_collar.dart          → ポート 8080 で起動
//   dart run tools/mock_collar.dart 9000     → ポート 9000 で起動
//
// Flutter は不要。Dart だけで動く。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

Future<void> main(List<String> args) async {
  final int port =
      args.isNotEmpty ? (int.tryParse(args.first) ?? 8080) : 8080;

  final HttpServer server =
      await HttpServer.bind(InternetAddress.anyIPv4, port);

  stdout.writeln('mock collar 起動しました');
  stdout.writeln('  Simulator から : ws://localhost:$port/ws');
  for (final String ip in await _localIpAddresses()) {
    stdout.writeln('  実機から       : ws://$ip:$port/ws');
  }
  stdout.writeln('停止するには Ctrl+C');

  await for (final HttpRequest request in server) {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.ok
        ..write('mock collar is running. connect to /ws');
      await request.response.close();
      continue;
    }

    final WebSocket socket = await WebSocketTransformer.upgrade(request);
    stdout.writeln('client connected');
    unawaited(_pushReadings(socket));
  }
}

Future<void> _pushReadings(WebSocket socket) async {
  final Random random = Random();
  int sequence = 0;
  double heartRate = 90;

  final Timer timer = Timer.periodic(const Duration(seconds: 1), (Timer _) {
    heartRate += (random.nextDouble() - 0.5) * 6;
    heartRate = heartRate.clamp(60.0, 130.0);

    final Map<String, Object?> payload = <String, Object?>{
      'v': 1,
      'type': 'sensor',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'seq': sequence++,
      'hr': heartRate.round(),
      'resp': 20 + random.nextInt(8),
      'imu': <String, double>{
        'ax': _round3((random.nextDouble() - 0.5) * 0.2),
        'ay': _round3(-0.98 + (random.nextDouble() - 0.5) * 0.1),
        'az': _round3((random.nextDouble() - 0.5) * 0.2),
      },
      'battery': 78,
    };

    socket.add(jsonEncode(payload));
  });

  await socket.done;
  timer.cancel();
  stdout.writeln('client disconnected');
}

double _round3(double value) => (value * 1000).roundToDouble() / 1000;

Future<List<String>> _localIpAddresses() async {
  final List<NetworkInterface> interfaces =
      await NetworkInterface.list(type: InternetAddressType.IPv4);

  return <String>[
    for (final NetworkInterface interface in interfaces)
      for (final InternetAddress address in interface.addresses)
        if (!address.isLoopback) address.address,
  ];
}
