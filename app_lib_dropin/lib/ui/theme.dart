import 'package:flutter/material.dart';

import 'app_colors.dart';

/// デザイン(白基調+暖色アクセント)に合わせた ThemeData。
ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    colorSchemeSeed: AppColors.accent,
    scaffoldBackgroundColor: AppColors.background,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withOpacity(0.12),
      iconTheme: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        final bool selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.accent : AppColors.textFaint,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        final bool selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          color: selected ? AppColors.accent : AppColors.textFaint,
        );
      }),
    ),
  );
}
