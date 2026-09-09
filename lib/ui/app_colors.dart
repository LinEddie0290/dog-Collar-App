import 'package:flutter/material.dart';

/// デザイン(白基調+暖色アクセント)のトークン集。
/// Design Canvas で確定した叩き台に合わせている。
class AppColors {
  AppColors._();

  static const Color background = Color(0xFFFAF6F1);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFEFE3D6);
  static const Color divider = Color(0xFFF1E7DA);

  static const Color textPrimary = Color(0xFF2B2320);
  static const Color textSecondary = Color(0xFF8A7C70);
  static const Color textFaint = Color(0xFFB8AA9C);

  static const Color accent = Color(0xFFB85042);
  static const Color accent2 = Color(0xFFD9A441);

  static const Color connected = Color(0xFF6E9271);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[accent, accent2],
  );
}
