import 'package:collar_data/collar_data.dart';
import 'package:flutter/widgets.dart';

import 'app_language.dart';

/// アプリ内の文言(日本語・英語・中国語)をまとめた辞書。
///
/// flutter の `gen-l10n` (ARBファイル + コード生成) は使わず、手書きの
/// シンプルなクラスにしている。生成ステップを増やさずに `flutter run` で
/// そのまま動かせるようにするため。
class AppStrings {
  const AppStrings({
    required this.language,
    required this.navHome,
    required this.navHistory,
    required this.navSettings,
    required this.petName,
    required this.petBreedAge,
    required this.heartRateLabel,
    required this.justNow,
    required this.notReceivedYet,
    required this.respirationLabel,
    required this.breathsPerMinUnit,
    required this.stableStatus,
    required this.waitingForData,
    required this.batteryLabel,
    required this.barkTranslationTitle,
    required this.comingSoon,
    required this.barkTranslationDesc,
    required this.historyChartTitle,
    required this.noDataYet,
    required this.avgLabel,
    required this.maxLabel,
    required this.minLabel,
    required this.historyInfoNote,
    required this.settingsTitle,
    required this.connectionSection,
    required this.useMockToggleTitle,
    required this.useMockToggleSubtitle,
    required this.urlFieldLabel,
    required this.statusLabel,
    required this.connectButton,
    required this.disconnectButton,
    required this.collarSection,
    required this.nameLabel,
    required this.collarNameValue,
    required this.firmwareLabel,
    required this.dataSection,
    required this.storageLocationLabel,
    required this.storageLocationDesc,
    required this.exportRecordsLabel,
    required this.languageSection,
    required this.appTitle,
    required this.connDisconnected,
    required this.connConnecting,
    required this.connConnected,
    required this.connReconnecting,
  });

  final AppLanguage language;

  final String navHome;
  final String navHistory;
  final String navSettings;

  final String petName;
  final String petBreedAge;

  final String heartRateLabel;
  final String justNow;
  final String notReceivedYet;

  final String respirationLabel;
  final String breathsPerMinUnit;
  final String stableStatus;
  final String waitingForData;

  final String batteryLabel;

  final String barkTranslationTitle;
  final String comingSoon;
  final String barkTranslationDesc;

  final String historyChartTitle;
  final String noDataYet;
  final String avgLabel;
  final String maxLabel;
  final String minLabel;
  final String historyInfoNote;

  final String settingsTitle;
  final String connectionSection;
  final String useMockToggleTitle;
  final String useMockToggleSubtitle;
  final String urlFieldLabel;
  final String statusLabel;
  final String connectButton;
  final String disconnectButton;
  final String collarSection;
  final String nameLabel;
  final String collarNameValue;
  final String firmwareLabel;
  final String dataSection;
  final String storageLocationLabel;
  final String storageLocationDesc;
  final String exportRecordsLabel;
  final String languageSection;
  final String appTitle;

  final String connDisconnected;
  final String connConnecting;
  final String connConnected;
  final String connReconnecting;

  /// 履歴画面の「直近N件」表示(言語によって語順が違うので関数にしている)。
  String recentCountLabel(int count) {
    switch (language) {
      case AppLanguage.ja:
        return '直近$count件';
      case AppLanguage.en:
        return 'Last $count readings';
      case AppLanguage.zh:
        return '最近$count条记录';
    }
  }

  String connStatusLabel(ConnStatus status) {
    switch (status) {
      case ConnStatus.disconnected:
        return connDisconnected;
      case ConnStatus.connecting:
        return connConnecting;
      case ConnStatus.connected:
        return connConnected;
      case ConnStatus.reconnecting:
        return connReconnecting;
    }
  }

  static AppStrings forLanguage(AppLanguage language) {
    switch (language) {
      case AppLanguage.ja:
        return _ja;
      case AppLanguage.en:
        return _en;
      case AppLanguage.zh:
        return _zh;
    }
  }

  static const AppStrings _ja = AppStrings(
    language: AppLanguage.ja,
    navHome: 'ホーム',
    navHistory: '履歴',
    navSettings: '設定',
    petName: 'モモ',
    petBreedAge: '柴犬・2歳',
    heartRateLabel: '心拍数',
    justNow: 'たった今',
    notReceivedYet: '未受信',
    respirationLabel: '呼吸',
    breathsPerMinUnit: '回/分',
    stableStatus: '安定しています',
    waitingForData: '受信を待っています',
    batteryLabel: '電池',
    barkTranslationTitle: '鳴き声・感情翻訳',
    comingSoon: '近日公開',
    barkTranslationDesc: '鳴き声から気持ちを読み取る機能を開発中です',
    historyChartTitle: '心拍数の推移(セッション内)',
    noDataYet: 'まだデータがありません',
    avgLabel: '平均',
    maxLabel: '最高',
    minLabel: '最低',
    historyInfoNote:
        '現在表示しているのは、このアプリを起動してからの記録です。日付をまたいだ履歴の閲覧は、'
        '端末に保存されたファイルを読み込む機能として今後追加予定です。',
    settingsTitle: '設定',
    connectionSection: '接続',
    useMockToggleTitle: 'アプリ内モックを使う',
    useMockToggleSubtitle: '首輪が無くても動作を確認できます',
    urlFieldLabel: '接続先 URL',
    statusLabel: '状態',
    connectButton: '接続する',
    disconnectButton: '切断する',
    collarSection: '首輪',
    nameLabel: '名前',
    collarNameValue: 'モモの首輪',
    firmwareLabel: 'ファームウェア',
    dataSection: 'データ',
    storageLocationLabel: '保存先',
    storageLocationDesc: '端末内に日付ごとに保存されます',
    exportRecordsLabel: '記録をエクスポート(準備中)',
    languageSection: '言語',
    appTitle: '首輪アプリ',
    connDisconnected: '未接続',
    connConnecting: '接続中…',
    connConnected: '接続済み',
    connReconnecting: '再接続中…',
  );

  static const AppStrings _en = AppStrings(
    language: AppLanguage.en,
    navHome: 'Home',
    navHistory: 'History',
    navSettings: 'Settings',
    petName: 'Momo',
    petBreedAge: 'Shiba Inu · 2 yrs',
    heartRateLabel: 'Heart Rate',
    justNow: 'Just now',
    notReceivedYet: 'No data yet',
    respirationLabel: 'Respiration',
    breathsPerMinUnit: 'breaths/min',
    stableStatus: 'Stable',
    waitingForData: 'Waiting for data',
    batteryLabel: 'Battery',
    barkTranslationTitle: 'Bark & Emotion Translation',
    comingSoon: 'Coming soon',
    barkTranslationDesc:
        "A feature to read your dog's mood from its bark is in development.",
    historyChartTitle: 'Heart rate trend (this session)',
    noDataYet: 'No data yet',
    avgLabel: 'Avg',
    maxLabel: 'Max',
    minLabel: 'Min',
    historyInfoNote:
        'This shows data recorded since the app was launched. Browsing history '
        'across multiple days, read from files saved on the device, is a planned '
        'future feature.',
    settingsTitle: 'Settings',
    connectionSection: 'Connection',
    useMockToggleTitle: 'Use in-app mock',
    useMockToggleSubtitle: 'Try the app without a physical collar',
    urlFieldLabel: 'Server URL',
    statusLabel: 'Status',
    connectButton: 'Connect',
    disconnectButton: 'Disconnect',
    collarSection: 'Collar',
    nameLabel: 'Name',
    collarNameValue: "Momo's Collar",
    firmwareLabel: 'Firmware',
    dataSection: 'Data',
    storageLocationLabel: 'Storage location',
    storageLocationDesc: 'Saved on this device, organized by date',
    exportRecordsLabel: 'Export records (coming soon)',
    languageSection: 'Language',
    appTitle: 'Collar App',
    connDisconnected: 'Disconnected',
    connConnecting: 'Connecting…',
    connConnected: 'Connected',
    connReconnecting: 'Reconnecting…',
  );

  static const AppStrings _zh = AppStrings(
    language: AppLanguage.zh,
    navHome: '首页',
    navHistory: '历史',
    navSettings: '设置',
    petName: 'Momo',
    petBreedAge: '柴犬・2岁',
    heartRateLabel: '心率',
    justNow: '刚刚',
    notReceivedYet: '暂无数据',
    respirationLabel: '呼吸',
    breathsPerMinUnit: '次/分',
    stableStatus: '状态稳定',
    waitingForData: '等待数据接收',
    batteryLabel: '电量',
    barkTranslationTitle: '吠叫·情绪翻译',
    comingSoon: '即将推出',
    barkTranslationDesc: '正在开发从吠叫声读取情绪的功能',
    historyChartTitle: '心率趋势(本次会话)',
    noDataYet: '暂无数据',
    avgLabel: '平均',
    maxLabel: '最高',
    minLabel: '最低',
    historyInfoNote:
        '当前显示的是本次启动应用以来记录的数据。跨日期查看历史记录(读取保存在设备中的'
        '文件)是计划中的后续功能。',
    settingsTitle: '设置',
    connectionSection: '连接',
    useMockToggleTitle: '使用应用内模拟数据',
    useMockToggleSubtitle: '即使没有项圈也能体验功能',
    urlFieldLabel: '连接地址 URL',
    statusLabel: '状态',
    connectButton: '连接',
    disconnectButton: '断开连接',
    collarSection: '项圈',
    nameLabel: '名称',
    collarNameValue: 'Momo 的项圈',
    firmwareLabel: '固件版本',
    dataSection: '数据',
    storageLocationLabel: '保存位置',
    storageLocationDesc: '按日期保存在设备本地',
    exportRecordsLabel: '导出记录(即将推出)',
    languageSection: '语言',
    appTitle: '项圈应用',
    connDisconnected: '未连接',
    connConnecting: '连接中…',
    connConnected: '已连接',
    connReconnecting: '重新连接中…',
  );
}

/// context から現在の言語の [AppStrings] を取り出すための InheritedWidget。
class AppStringsScope extends InheritedWidget {
  const AppStringsScope({
    super.key,
    required this.language,
    required super.child,
  });

  final AppLanguage language;

  AppStrings get strings => AppStrings.forLanguage(language);

  static AppStrings of(BuildContext context) {
    final AppStringsScope? scope =
        context.dependOnInheritedWidgetOfExactType<AppStringsScope>();
    assert(scope != null, 'AppStringsScope が見つかりません。MaterialApp の builder で包んでください。');
    return scope?.strings ?? AppStrings.forLanguage(AppLanguage.ja);
  }

  static AppLanguage languageOf(BuildContext context) {
    final AppStringsScope? scope =
        context.dependOnInheritedWidgetOfExactType<AppStringsScope>();
    return scope?.language ?? AppLanguage.ja;
  }

  @override
  bool updateShouldNotify(AppStringsScope oldWidget) =>
      oldWidget.language != language;
}
