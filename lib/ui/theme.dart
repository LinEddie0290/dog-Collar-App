import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 白い水のデザインに合わせた ThemeData（T35）。
///
/// 部品ごとのテーマは置かず、色の組（ColorScheme）だけで決める。
/// チップ・スイッチ・ボタン・上のバー・下から出るシートは、ここの色をそのまま使う。
ThemeData buildAppTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(seedColor: AppColors.accent).copyWith(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFD3EEF8),
    onPrimaryContainer: AppColors.onHero,
    secondary: AppColors.accent,
    onSecondary: Colors.white,
    // 選んだチップ・選んだ区切りボタンの地
    secondaryContainer: const Color(0xFFCDEEFA),
    onSecondaryContainer: AppColors.onHero,
    error: AppColors.warn,
    onError: Colors.white,
    // 上のバー・ページの地
    surface: AppColors.background,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
    // 下から出るシート・ダイアログ・メニューは白
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: Colors.white,
    surfaceContainerHigh: Colors.white,
    surfaceContainerHighest: const Color(0xFFE1F1F8),
    // スクロールしても上のバーに色を足さない
    surfaceTint: Colors.transparent,
    outline: const Color(0xFF8FBFD3),
    outlineVariant: AppColors.border,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    dividerColor: AppColors.divider,
  );
}
