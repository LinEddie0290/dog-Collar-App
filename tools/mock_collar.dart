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
  // 実機は心拍を測れない(光学式センサーが載っていない)。代わりに赤外温度
  // センサーが返す体温を模擬する。犬の平常体温は 38〜39℃ 前後。
  double bodyTemp = 38.5;

  // GPS はプレースホルダーの原点付近をゆっくりランダムウォークする。実際の
  // 「家」の座標ではないので、地理囲いのテストをするときは
  // LocationController.setHomeFence() で合わせた座標を設定すること。
  double gpsLat = 31.2304;
  double gpsLng = 121.4737;

  final Timer timer = Timer.periodic(const Duration(seconds: 1), (Timer _) {
    bodyTemp += (random.nextDouble() - 0.5) * 0.15;
    bodyTemp = bodyTemp.clamp(37.5, 39.8);

    // GPS は体温/IMUよりずっと低頻度という想定(5秒に1回程度)。
    final bool hasGpsFix = sequence % 5 == 0;
    if (hasGpsFix) {
      gpsLat += (random.nextDouble() - 0.5) * 0.00003;
      gpsLng += (random.nextDouble() - 0.5) * 0.00003;
    }

    final Map<String, Object?> payload = <String, Object?>{
      'v': 1,
      'type': 'sensor',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'seq': sequence++,
      'body_temp_c': _round3(bodyTemp),
      'ambient_temp_c': _round3(25.0 + (random.nextDouble() - 0.5) * 2),
      // resp は実機では常に無い(呼吸センサーが無く、IMU からの推定は未実装)。
      // モックだけが値を出すので、UI が null を正しく扱えるかの確認にも使える。
      'resp': 20 + random.nextInt(8),
      'imu': <String, double>{
        'ax': _round3((random.nextDouble() - 0.5) * 0.2),
        'ay': _round3(-0.98 + (random.nextDouble() - 0.5) * 0.1),
        'az': _round3((random.nextDouble() - 0.5) * 0.2),
      },
      'battery': 78,
      if (hasGpsFix) 'lat': _round6(gpsLat),
      if (hasGpsFix) 'lng': _round6(gpsLng),
      // 実機は精度(メートル)を送ってこない。NMEA の GGA から取れるのは
      // 測位品質・衛星数・HDOP(倍率)まで。
      if (hasGpsFix) 'fix_quality': 1,
      if (hasGpsFix) 'satellites': 8 + random.nextInt(4),
      if (hasGpsFix) 'hdop': _round3(0.8 + random.nextDouble() * 0.8),
    };

    socket.add(jsonEncode(payload));
  });

  await socket.done;
  timer.cancel();
  stdout.writeln('client disconnected');
}

double _round3(double value) => (value * 1000).roundToDouble() / 1000;

double _round6(double value) => (value * 1000000).roundToDouble() / 1000000;

Future<List<String>> _localIpAddresses() async {
  final List<NetworkInterface> interfaces =
      await NetworkInterface.list(type: InternetAddressType.IPv4);

  return <String>[
    for (final NetworkInterface interface in interfaces)
      for (final InternetAddress address in interface.addresses)
        if (!address.isLoopback) address.address,
  ];
}
