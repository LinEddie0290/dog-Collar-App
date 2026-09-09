/// アプリがサポートする言語。
enum AppLanguage { ja, en, zh }

extension AppLanguageX on AppLanguage {
  /// ロケールコード(MaterialApp の locale に使う)。
  String get code {
    switch (this) {
      case AppLanguage.ja:
        return 'ja';
      case AppLanguage.en:
        return 'en';
      case AppLanguage.zh:
        return 'zh';
    }
  }

  /// 言語選択メニューに出す名前。あえて「今のアプリの言語」ではなく
  /// 「その言語自身での表記」にしている(自分の言語を見失わないため)。
  String get nativeName {
    switch (this) {
      case AppLanguage.ja:
        return '日本語';
      case AppLanguage.en:
        return 'English';
      case AppLanguage.zh:
        return '中文';
    }
  }
}

AppLanguage appLanguageFromCode(String? code) {
  switch (code) {
    case 'en':
      return AppLanguage.en;
    case 'zh':
      return AppLanguage.zh;
    case 'ja':
    default:
      return AppLanguage.ja;
  }
}
