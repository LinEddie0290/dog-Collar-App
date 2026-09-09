import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_language.dart';

/// アプリ全体の表示言語。設定画面から変更し、端末に保存して次回起動時も
/// 復元する。
class LocaleController extends ChangeNotifier {
  static const String _prefsKey = 'app_language_code';

  AppLanguage language = AppLanguage.ja;

  /// 保存済みの言語設定を読み込む。見つからない/読み込めない場合は
  /// デフォルト(日本語)のまま。main() から起動直後に一度呼ぶ想定。
  Future<void> loadSaved() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? code = prefs.getString(_prefsKey);
      if (code != null) {
        language = appLanguageFromCode(code);
        notifyListeners();
      }
    } catch (_) {
      // 読み込みに失敗しても、デフォルト言語でアプリは使える。
    }
  }

  Future<void> setLanguage(AppLanguage value) async {
    if (value == language) return;
    language = value;
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, value.code);
    } catch (_) {
      // 保存に失敗しても、今回の起動中は選んだ言語のまま使える。
    }
  }
}
