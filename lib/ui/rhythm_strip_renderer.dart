/// 1回分の測定波形を、横スクロールできる1枚の PNG 画像にする。
///
/// 履歴の JSONL は「1行数百バイト」を前提にしている
/// (`lib/data/measurement_store.dart` 冒頭のコメント参照)。波形の生データを
/// そこへ直接書くと、この前提が壊れる。代わりにここでは画像ファイルとして
/// 書き出し、レコードにはファイル名(相対パス)だけを残す。写真アプリと
/// 同じ考え方 — 台帳は軽く、実体は別ファイル。
///
/// 描く内容はライブ表示([LiveWaveChart])と同じ言語 — 帯域通過後の波形＋拍の
/// ティックマーク。ただしライブ表示の直近5秒の窓とは違い、測定全体
/// (通常60秒)を描く。60秒ぶんを1画面に収めると線が潰れるので、
/// 横方向は「見た目の1秒あたりのピクセル数」を固定し、画像自体を横長にして
/// 表示側([RhythmStripView])で横スクロールさせる。
///
/// `state/` から `ui/` を参照する形になるが、ここにあるのは
/// BuildContext を必要としない純粋な描画関数で、[AppColors] という表示の
/// トークンを共有したいだけなので許容している。
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 波形1枚を PNG のバイト列にして返す。[wave] が短すぎる、または
/// サンプリング周波数が不明なときは null(呼ぶ側は測定の保存自体は続ける)。
///
/// [wave] は帯域通過後の信号(例: `VitalsResult.beatBand`)、[beatIndices] は
/// その中での拍の位置(サンプル番号、例: `VitalsResult.beatTimesSeconds` を
/// [sampleRateHz] 倍したもの)。
Future<Uint8List?> renderRhythmStripPng({
  required List<double> wave,
  required List<int> beatIndices,
  required double sampleRateHz,
}) async {
  if (wave.length < 2 || sampleRateHz <= 0) return null;

  final double seconds = wave.length / sampleRateHz;

  // 横: 1秒あたり140px。安静時(1〜2拍/秒)でも拍同士が重ならない密度。
  const double pxPerSecond = 140;
  const double heightLogical = 220;
  // 保存後にスマホの写真アプリで拡大しても粗くならないよう、2倍解像度で描く。
  const double dpr = 2.0;

  final double widthLogical = math.max(seconds * pxPerSecond, 60);
  final int w = (widthLogical * dpr).round();
  final int h = (heightLogical * dpr).round();

  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas =
      Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  canvas.scale(dpr);

  // 背景。透明のまま書き出すと写真アプリで市松模様になるので塗っておく。
  canvas.drawRect(
    Rect.fromLTWH(0, 0, widthLogical, heightLogical),
    Paint()..color = AppColors.surface,
  );

  const double waveTop = 34; // 上に拍のティックマーク用の余白
  const double waveBottom = heightLogical - 28; // 下に時間軸の余白
  final double mid = (waveTop + waveBottom) / 2;
  final double half = (waveBottom - waveTop) / 2 * 0.9;

  // 1秒ごとの縦線。5秒ごとは少し濃くして時刻を添える。
  final Paint gridLight = Paint()
    ..color = AppColors.border
    ..strokeWidth = 1;
  final Paint gridBold = Paint()
    ..color = AppColors.border.withValues(alpha: 0.9)
    ..strokeWidth = 1.2;
  final int ticks = seconds.floor();
  for (int i = 0; i <= ticks; i++) {
    final double x = i * pxPerSecond;
    final bool bold = i % 5 == 0;
    canvas.drawLine(Offset(x, waveTop - 10), Offset(x, waveBottom + 6),
        bold ? gridBold : gridLight);
    if (bold) {
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: '${i}s',
          style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 3, waveBottom + 8));
    }
  }

  // 中心線
  canvas.drawLine(
    Offset(0, mid),
    Offset(widthLogical, mid),
    Paint()
      ..color = AppColors.textFaint.withValues(alpha: 0.35)
      ..strokeWidth = 1,
  );

  // 縦の倍率。1点だけの突発的な山(体の動き)に引っぱられないよう、
  // 最大値ではなく上位5%点を基準にする。ライブ表示は最大値を使っているが、
  // あちらは5秒の窓だけなので山が混ざりにくい。60秒だと体の動きの山が
  // 混ざりやすく、最大値を使うと本来の拍が線の下側に潰れてしまう。
  double scale = 0.02;
  final List<double> abs =
      wave.map((double v) => v.abs()).toList(growable: false)..sort();
  if (abs.isNotEmpty) {
    final int idx = (abs.length * 0.95).clamp(0, abs.length - 1).round();
    scale = math.max(abs[idx], 0.005);
  }

  double x(int i) => i / sampleRateHz * pxPerSecond;
  double y(double v) => mid - (v / scale).clamp(-1.0, 1.0) * half;

  final Path path = Path()..moveTo(x(0), y(wave[0]));
  for (int i = 1; i < wave.length; i++) {
    path.lineTo(x(i), y(wave[i]));
  }
  canvas.drawPath(
    path,
    Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round,
  );

  // 拍。上端に短い線と点。波形の上に重ねないので線が読みにくくならない。
  final Paint tick = Paint()
    ..color = AppColors.connected
    ..strokeWidth = 1.6;
  final Paint dot = Paint()..color = AppColors.connected;
  for (final int i in beatIndices) {
    if (i < 0 || i >= wave.length) continue;
    final double px = x(i);
    canvas.drawLine(Offset(px, 6), Offset(px, waveTop - 12), tick);
    canvas.drawCircle(Offset(px, waveTop - 16), 3, dot);
  }

  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(w, h);
  final ByteData? bytes =
      await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes?.buffer.asUint8List();
}
