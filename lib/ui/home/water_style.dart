/// T35：ホームの「白い水」の色・板块ごとの色とアイコン。
/// 画面イメージ：首輪開発計画/03_設計メモ/T35_画面イメージ/ホーム画面イメージ_v1_白。
/// ほかのタブの色（app_colors.dart）はデザイナーと話すまで今のまま。
library;

import 'package:flutter/material.dart';

import '../../data/health_items.dart';

class WaterColors {
  WaterColors._();

  static const Color bgTop = Color(0xFFF7FCFF);
  static const Color bgMid = Color(0xFFE2F4FB);
  static const Color bgBottom = Color(0xFFD3EEF8);

  static const Color text = Color(0xFF0B2A40);
  static const Color sub = Color(0xFF5C7F93);
  static const Color value = Color(0xFF46677A);

  /// 細い線（軌道・カードのふち）。
  static const Color line = Color(0x403CAAD2);
  static const Color aqua = Color(0xFF14BFE0);

  /// 提醒の点。赤は使わない（診断ではないので）。
  static const Color alert = Color(0xFFFF9A3C);

  /// 「示例」の文字。
  static const Color demo = Color(0xFF8A9BA8);

  /// 白いガラスのカード。
  static const Color card = Color(0xB8FFFFFF);
}

Color boardColor(Board b) => switch (b) {
      Board.exercise => const Color(0xFF14BFE0),
      Board.sleep => const Color(0xFF8B74FF),
      Board.physio => const Color(0xFFFF5C8F),
      Board.skin => const Color(0xFF22C98B),
      Board.mind => const Color(0xFFF2A81D),
      Board.diet => const Color(0xFF3A8DFF),
    };

IconData boardIcon(Board b) => switch (b) {
      Board.exercise => Icons.directions_run,
      Board.sleep => Icons.bedtime_outlined,
      Board.physio => Icons.monitor_heart_outlined,
      Board.skin => Icons.water_drop_outlined,
      Board.mind => Icons.graphic_eq,
      Board.diet => Icons.rice_bowl_outlined,
    };
