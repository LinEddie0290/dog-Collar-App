import 'package:flutter/material.dart';

/// アプリ全体の色（白い水のデザイン、T35）。
/// ホームの色（home/water_style.dart）と同じ系統。前は白＋暖色（赤茶）だった。
class AppColors {
  AppColors._();

  /// ページの地の色（上のバーも同じ色）。
  static const Color background = Color(0xFFF1F9FD);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFCDE6F1);
  static const Color divider = Color(0xFFDCEEF6);

  static const Color textPrimary = Color(0xFF0B2A40);
  static const Color textSecondary = Color(0xFF5C7F93);
  static const Color textFaint = Color(0xFF86A3B3);

  /// 主役の色（ボタン・リンク・選んだもの）。白い地の上の文字でも読める濃さの水色。
  static const Color accent = Color(0xFF0A93BE);

  /// 「まあまあ」（品質 fair・提醒の線）。黄色系。
  static const Color accent2 = Color(0xFFE8A02E);

  /// 注意・うまくいかなかったとき（品質 unusable・エラーの文）。赤にはしない（診断ではないので）。
  static const Color warn = Color(0xFFE0652F);

  static const Color connected = Color(0xFF1FB57F);

  /// 大きいボタン（测定の「开始测量」）。ホームの真ん中の球と同じ水色。
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFFC4F1FF), Color(0xFF63C6ED)],
  );

  /// [heroGradient] の上の文字・アイコン。
  static const Color onHero = Color(0xFF06324D);
}
