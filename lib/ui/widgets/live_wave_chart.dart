import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_colors.dart';

/// 測定中の心弾動をそのまま流して見せる波形。
///
/// 出しているのは生の加速度ではなく 8–40 Hz を通したあとの信号。生のままだと
/// 重力(約9.8 m/s²)と体の揺れが桁違いに大きく、心拍は線の太さに埋もれて
/// 何も見えない。解析が実際に見ている信号を見せる、という意味でもある。
///
/// 縦の倍率は自動だが、毎フレーム作り直すと波の大きさがチラつくので、
/// 前のフレームの倍率へゆっくり寄せている（[_smooth]）。
class LiveWaveChart extends StatefulWidget {
  const LiveWaveChart({
    super.key,
    required this.wave,
    required this.beatIndices,
    required this.seconds,
    this.height = 130,
  });

  /// 帯域通過後の波形。右端が最新。
  final List<double> wave;

  /// [wave] の中の拍の位置。
  final List<int> beatIndices;

  /// [wave] が何秒ぶんか。縦の目盛り(1秒ごと)に使う。
  final double seconds;

  final double height;

  @override
  State<LiveWaveChart> createState() => _LiveWaveChartState();
}

class _LiveWaveChartState extends State<LiveWaveChart> {
  /// 表示上の振幅。0 のままだと初回に発散するので下限を持たせる。
  double _scale = 0.02;

  static const double _smooth = 0.15;

  @override
  Widget build(BuildContext context) {
    if (widget.wave.isNotEmpty) {
      double peak = 0;
      for (final double v in widget.wave) {
        final double a = v.abs();
        if (a > peak) peak = a;
      }
      // 下限 0.005 m/s²。無音に近いときに倍率が上がりきって、ノイズが
      // 立派な波形に見えてしまうのを防ぐ。
      final double target = math.max(peak, 0.005);
      _scale = _scale + (target - _scale) * _smooth;
    }

    return SizedBox(
      height: widget.height,
      child: CustomPaint(
        painter: _WavePainter(
          wave: widget.wave,
          beats: widget.beatIndices,
          seconds: widget.seconds,
          scale: _scale,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.wave,
    required this.beats,
    required this.seconds,
    required this.scale,
  });

  final List<double> wave;
  final List<int> beats;
  final double seconds;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final double mid = size.height / 2;

    // 1秒ごとの縦線。波が横に流れていることが分かるための目盛りで、
    // データより目立たせない。
    if (seconds > 0.5) {
      final Paint grid = Paint()
        ..color = AppColors.border
        ..strokeWidth = 1;
      final int ticks = seconds.floor();
      for (int i = 1; i <= ticks; i++) {
        final double x = size.width * (1 - i / seconds);
        if (x < 0) break;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      }
    }

    // 中心線
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..color = AppColors.textFaint.withValues(alpha: 0.35)
        ..strokeWidth = 1,
    );

    if (wave.length < 2) return;

    // 縦は ±scale を画面の 90% に割り当てる。
    final double half = size.height * 0.45;
    double y(double v) => mid - (v / scale).clamp(-1.0, 1.0) * half;
    double x(int i) => size.width * i / (wave.length - 1);

    final Path path = Path()..moveTo(x(0), y(wave[0]));
    for (int i = 1; i < wave.length; i++) {
      path.lineTo(x(i), y(wave[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );

    // 拍。上端に短い線と点。波形の上に重ねないので、線が読みにくくならない。
    final Paint tick = Paint()
      ..color = AppColors.connected
      ..strokeWidth = 1.4;
    final Paint dot = Paint()..color = AppColors.connected;
    for (final int i in beats) {
      if (i < 0 || i >= wave.length) continue;
      final double px = x(i);
      canvas.drawLine(Offset(px, 0), Offset(px, 7), tick);
      canvas.drawCircle(Offset(px, 9.5), 2.6, dot);
    }

    // 右端が「いま」。ここに入ってくる。
    canvas.drawLine(
      Offset(size.width - 0.5, 0),
      Offset(size.width - 0.5, size.height),
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.5)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.wave != wave || old.beats != beats || old.scale != scale;
}
