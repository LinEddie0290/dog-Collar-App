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
    required this.bodyTempLabel,
    required this.ambientTempLabel,
    required this.celsiusUnit,
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
    required this.navMap,
    required this.mapNotConfiguredTitle,
    required this.mapNotConfiguredDesc,
    required this.waitingForLocation,
    required this.lastKnownLocationPrefix,
    // ── 測定画面 ──
    required this.navMeasure,
    required this.measureStart,
    required this.measureStop,
    required this.measureHint60s,
    required this.measurePleaseWait,
    required this.measureIdle,
    required this.measureConnecting,
    required this.measureSearching,
    required this.measureMeasuring,
    required this.measureAnalyzing,
    required this.measureDone,
    required this.measureFailed,
    required this.collarNotConnected,
    required this.collarConnectedTo,
    required this.collarChoose,
    required this.collarSwitch,
    required this.viewPastMeasurements,
    required this.tipsTitle,
    required this.tipSensorPlacement,
    required this.tipPartFur,
    required this.tipStayStill,
    required this.tipKeepPhoneClose,
    required this.liveStabilizing,
    required this.recentWindowNote,
    required this.receivedSamples,
    required this.measuredRate,
    required this.droppedPackets,
    required this.tooManyDropsWarning,
    required this.beatsDetectedIn,
    required this.beatIntervalsTitle,
    required this.notEcgDisclaimer,
    required this.qualityGood,
    required this.qualityFair,
    required this.qualityUnusable,
    required this.respirationShort,
    required this.beatCvLabel,
    // ── 首輪（機器）画面 ──
    required this.devicesTitle,
    required this.registeredCollars,
    required this.searchAction,
    required this.noCollarsYet,
    required this.selectAction,
    required this.selectedLabel,
    required this.renameAction,
    required this.forgetAction,
    required this.collarNameDialogTitle,
    required this.collarNameHint,
    required this.cancelAction,
    required this.saveAction,
    required this.signalStrength,
    required this.connectTimes,
    required this.lastConnected,
    required this.newlyFound,
    required this.goodToKnowTitle,
    required this.noteOneClientOnly,
    required this.noteKnownIsFast,
    required this.noteNoBatteryYet,
    // ── 記録画面 ──
    required this.recordsTitle,
    required this.dailyMeanTitle,
    required this.dailyMeanNote,
    required this.measurementCount,
    required this.exportCsvForVet,
    required this.csvCopied,
    required this.noRecordsYet,
    required this.deleteRecord,
    required this.durationLabel,
    required this.postureLabel,
    required this.reportTitle,
    required this.exportThisRecord,
    required this.exportPdf,
    required this.exportCsv,
    required this.exportBoth,
    required this.exportFailed,
    required this.hrvClinicalNote,
    required this.reportMeasuredWith,
    required this.reportNoJapaneseFont,
    required this.liveWaveTitle,
    required this.liveWaveHint,
    required this.rateTooLowWarning,
    required this.errBtOff,
    required this.errBtDenied,
    required this.errNotFound,
    required this.errWrongDevice,
    required this.errOldFirmware,
    required this.errBusy,
    required this.errConnectFailed,
    required this.errLinkLost,
    required this.errTooShortPrefix,
    required this.errTooShortSuffix,
    required this.errSaveFailed,
    required this.historyLoadFailed,
    required this.beatCountLabel,
    required this.secondsUnit,
    required this.daysCount,
    required this.caveatUnusable,
    required this.caveatFair,
    required this.caveatManyGaps,
  });

  final AppLanguage language;

  final String navHome;
  final String navHistory;
  final String navSettings;

  final String petName;
  final String petBreedAge;

  /// 赤外温度センサー(MLX90615)が返す体温。首輪が測れる唯一の生体指標。
  final String bodyTempLabel;

  /// センサー自身の周囲温度。体温が周囲温度に近いときは、センサーが犬の
  /// 皮膚を向いていないことを示す手がかりになる。
  final String ambientTempLabel;
  final String celsiusUnit;
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

  final String navMap;
  final String mapNotConfiguredTitle;
  final String mapNotConfiguredDesc;
  final String waitingForLocation;
  final String lastKnownLocationPrefix;

  // ── 測定画面 ──
  final String navMeasure;
  final String measureStart;
  final String measureStop;
  final String measureHint60s;
  final String measurePleaseWait;
  final String measureIdle;
  final String measureConnecting;
  final String measureSearching;
  final String measureMeasuring;
  final String measureAnalyzing;
  final String measureDone;
  final String measureFailed;
  final String collarNotConnected;

  /// 「{name} に接続中」の前半。名前は右側に別途出す。
  final String collarConnectedTo;
  final String collarChoose;
  final String collarSwitch;
  final String viewPastMeasurements;
  final String tipsTitle;
  final String tipSensorPlacement;
  final String tipPartFur;
  final String tipStayStill;
  final String tipKeepPhoneClose;
  final String liveStabilizing;
  final String recentWindowNote;
  final String receivedSamples;
  final String measuredRate;
  final String droppedPackets;
  final String tooManyDropsWarning;
  final String beatsDetectedIn;
  final String beatIntervalsTitle;
  final String notEcgDisclaimer;
  final String qualityGood;
  final String qualityFair;
  final String qualityUnusable;
  final String respirationShort;
  final String beatCvLabel;

  // ── 首輪（機器）画面 ──
  final String devicesTitle;
  final String registeredCollars;
  final String searchAction;
  final String noCollarsYet;
  final String selectAction;
  final String selectedLabel;
  final String renameAction;
  final String forgetAction;
  final String collarNameDialogTitle;
  final String collarNameHint;
  final String cancelAction;
  final String saveAction;
  final String signalStrength;
  final String connectTimes;
  final String lastConnected;
  final String newlyFound;
  final String goodToKnowTitle;
  final String noteOneClientOnly;
  final String noteKnownIsFast;
  final String noteNoBatteryYet;

  // ── 記録画面 ──
  final String recordsTitle;
  final String dailyMeanTitle;
  final String dailyMeanNote;
  final String measurementCount;
  final String exportCsvForVet;
  final String csvCopied;
  final String noRecordsYet;
  final String deleteRecord;
  final String durationLabel;
  final String postureLabel;
  final String reportTitle;
  final String exportThisRecord;
  final String exportPdf;
  final String exportCsv;
  final String exportBoth;
  final String exportFailed;
  final String hrvClinicalNote;
  final String reportMeasuredWith;
  final String reportNoJapaneseFont;
  final String liveWaveTitle;
  final String liveWaveHint;
  final String rateTooLowWarning;
  final String errBtOff;
  final String errBtDenied;
  final String errNotFound;
  final String errWrongDevice;
  final String errOldFirmware;
  final String errBusy;
  final String errConnectFailed;
  final String errLinkLost;
  final String errTooShortPrefix;
  final String errTooShortSuffix;
  final String errSaveFailed;
  final String historyLoadFailed;
  final String beatCountLabel;
  final String secondsUnit;
  final String daysCount;
  final String caveatUnusable;
  final String caveatFair;
  final String caveatManyGaps;

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

  /// GPSの精度表示 (例: "精度 ±5m")。
  String gpsAccuracyLabel(int meters) {
    switch (language) {
      case AppLanguage.ja:
        return '精度 ±${meters}m';
      case AppLanguage.en:
        return '±${meters}m accuracy';
      case AppLanguage.zh:
        return '精度 ±$meters米';
    }
  }

  /// "N分前" 表示。1分未満は justNow を使う想定(この関数は呼ばない)。
  String minutesAgoLabel(int minutes) {
    switch (language) {
      case AppLanguage.ja:
        return '$minutes分前';
      case AppLanguage.en:
        return minutes == 1 ? '1 minute ago' : '$minutes minutes ago';
      case AppLanguage.zh:
        return '$minutes分钟前';
    }
  }

  String geofenceExitMessage(String fenceName) {
    switch (language) {
      case AppLanguage.ja:
        return '$fenceNameの範囲から離れました';
      case AppLanguage.en:
        return 'Left the $fenceName area';
      case AppLanguage.zh:
        return '已离开$fenceName范围';
    }
  }

  String geofenceEnterMessage(String fenceName) {
    switch (language) {
      case AppLanguage.ja:
        return '$fenceNameの範囲に戻りました';
      case AppLanguage.en:
        return 'Back in the $fenceName area';
      case AppLanguage.zh:
        return '已回到$fenceName范围';
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
    bodyTempLabel: '体温',
    ambientTempLabel: '周囲温度',
    celsiusUnit: '℃',
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
    navMap: '地図',
    mapNotConfiguredTitle: '地図の設定が必要です',
    mapNotConfiguredDesc: '高徳地図のAPIキーを設定すると、ここに現在地が表示されます。',
    waitingForLocation: '位置情報の受信を待っています',
    lastKnownLocationPrefix: '最後に確認された位置',
    navMeasure: '測定',
    measureStart: '測定を開始',
    measureStop: '測定を停止',
    measureHint60s: '目安 60 秒',
    measurePleaseWait: 'しばらくお待ちください',
    measureIdle: '待機中',
    measureConnecting: '首輪につないでいます…',
    measureSearching: '首輪を探しています…',
    measureMeasuring: '測定中',
    measureAnalyzing: '解析中…',
    measureDone: '完了',
    measureFailed: '失敗',
    collarNotConnected: '首輪が未接続',
    collarConnectedTo: '接続中',
    collarChoose: '選ぶ',
    collarSwitch: '切り替え',
    viewPastMeasurements: 'これまでの測定を見る',
    tipsTitle: '測るときのコツ',
    tipSensorPlacement: 'センサーは左胸の下（心臓の下側）に当てる。ここが一番信号が強い',
    tipPartFur: '毛をかき分けて、皮膚に密着させる',
    tipStayStill: 'できるだけ動かない状態で60秒',
    tipKeepPhoneClose: 'スマホは首輪の近くに置く',
    liveStabilizing: '安定するまで15秒ほどかかります',
    recentWindowNote: '直近30秒の値',
    receivedSamples: '受信',
    measuredRate: '実測レート',
    droppedPackets: '取りこぼし',
    tooManyDropsWarning: '通信の取りこぼしが多いです。スマホを首輪に近づけてください。',
    beatsDetectedIn: '拍を検出',
    beatIntervalsTitle: '1拍ごとの間隔',
    notEcgDisclaimer: 'この測定は加速度センサーで心臓の機械的な振動を捉えたもので、心電図ではありません。不整脈の診断には使えません。',
    qualityGood: '信頼できる',
    qualityFair: '参考値',
    qualityUnusable: '算出不可',
    respirationShort: '呼吸',
    beatCvLabel: '拍間隔のばらつき',
    devicesTitle: '首輪',
    registeredCollars: '登録済みの首輪',
    searchAction: '探す',
    noCollarsYet: 'まだ登録された首輪がありません。\n首輪に電源を入れてから「探す」を押してください。',
    selectAction: '使う',
    selectedLabel: '選択中',
    renameAction: '名前を変える',
    forgetAction: '登録を削除',
    collarNameDialogTitle: '首輪の名前',
    collarNameHint: '例: モモの首輪',
    cancelAction: 'やめる',
    saveAction: '保存',
    signalStrength: '電波',
    connectTimes: '接続',
    lastConnected: '前回',
    newlyFound: '新しく見つかった首輪',
    goodToKnowTitle: '知っておくこと',
    noteOneClientOnly: '首輪は同時に1台しか接続できません。パソコンから繋いでいる間はスマホから接続できません。',
    noteKnownIsFast: '登録済みの首輪はスキャンなしで接続するので数秒で繋がります。',
    noteNoBatteryYet: '首輪に電池はまだ無いので、USBで給電しているときだけ動きます。',
    recordsTitle: '測定の記録',
    dailyMeanTitle: '日ごとの平均心拍',
    dailyMeanNote: '算出できなかった測定は含めていません',
    measurementCount: '件の測定',
    exportCsvForVet: '獣医用にCSV出力',
    csvCopied: 'CSV をコピーしました。メールなどに貼り付けてください。',
    noRecordsYet: 'まだ測定がありません。\n測定タブから始めてください。',
    deleteRecord: 'この記録を削除',
    durationLabel: '測定時間',
    postureLabel: '姿勢',
    reportTitle: '心拍測定レポート',
    exportThisRecord: 'この測定を書き出す',
    exportPdf: 'PDF で書き出す',
    exportCsv: 'CSV で書き出す',
    exportBoth: 'PDF と CSV の両方',
    exportFailed: '書き出しに失敗しました',
    hrvClinicalNote: 'SDNN・RMSSD は機械振動から求めた値です。心電図の基準値とは比較できません。同一個体の履歴比較にのみ使用してください。',
    reportMeasuredWith: '測定機器: PET-Sense 首輪（加速度センサー）',
    reportNoJapaneseFont: '日本語フォントが未同梱のため英字で出力しました',
    liveWaveTitle: '心臓の振動（8–40 Hz）',
    liveWaveHint: '上の緑のしるしが1拍。等間隔に並んでいれば、うまく取れています。',
    rateTooLowWarning: 'サンプリングが低すぎて心拍を算出できません。首輪の設定を確認してください。',
    errBtOff: 'Bluetooth がオフになっています。設定からオンにしてください。',
    errBtDenied: 'Bluetooth の使用が許可されていません。設定から許可してください。',
    errNotFound: '首輪が見つかりません。電源が入っているか確認してください。',
    errWrongDevice: '別の機器につながりました。首輪の電源を入れ直してからもう一度お試しください。',
    errOldFirmware: '首輪のファームウェアが古い可能性があります。',
    errBusy: '別のアプリかパソコンが首輪に接続しています。首輪は同時に1台しか接続できません。',
    errConnectFailed: '接続できませんでした。首輪の電源と Bluetooth を確認してください。',
    errLinkLost: '接続が失われました。',
    errTooShortPrefix: '測定時間が短すぎます（',
    errTooShortSuffix: '秒以上必要）',
    errSaveFailed: '結果は出ましたが保存に失敗しました',
    historyLoadFailed: '履歴を読めませんでした',
    beatCountLabel: '検出拍数',
    secondsUnit: '秒',
    daysCount: '日分',
    caveatUnusable: '信号が不十分なため、心拍数は算出できませんでした。',
    caveatFair: '信号が弱めです。参考値として扱ってください。',
    caveatManyGaps: '通信の取りこぼしが多いため、拍間隔の指標は信頼できません。',
  );

  static const AppStrings _en = AppStrings(
    language: AppLanguage.en,
    navHome: 'Home',
    navHistory: 'History',
    navSettings: 'Settings',
    petName: 'Momo',
    petBreedAge: 'Shiba Inu · 2 yrs',
    bodyTempLabel: 'Body Temp',
    ambientTempLabel: 'Ambient',
    celsiusUnit: '°C',
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
    navMap: 'Map',
    mapNotConfiguredTitle: 'Map setup required',
    mapNotConfiguredDesc:
        'Set up an Amap API key to see the current location here.',
    waitingForLocation: 'Waiting for a location fix',
    lastKnownLocationPrefix: 'Last known location',
    navMeasure: 'Measure',
    measureStart: 'Start measuring',
    measureStop: 'Stop measuring',
    measureHint60s: 'About 60 seconds',
    measurePleaseWait: 'Please wait',
    measureIdle: 'Ready',
    measureConnecting: 'Connecting to the collar…',
    measureSearching: 'Looking for the collar…',
    measureMeasuring: 'Measuring',
    measureAnalyzing: 'Analysing…',
    measureDone: 'Done',
    measureFailed: 'Failed',
    collarNotConnected: 'Collar not connected',
    collarConnectedTo: 'Connected',
    collarChoose: 'Choose',
    collarSwitch: 'Switch',
    viewPastMeasurements: 'View past measurements',
    tipsTitle: 'Getting a good reading',
    tipSensorPlacement: 'Hold the sensor below the left chest, under the heart — the signal is strongest there',
    tipPartFur: 'Part the fur so it sits against the skin',
    tipStayStill: 'Keep as still as possible for 60 seconds',
    tipKeepPhoneClose: 'Keep the phone near the collar',
    liveStabilizing: 'Takes about 15 seconds to settle',
    recentWindowNote: 'from the last 30 seconds',
    receivedSamples: 'Received',
    measuredRate: 'Actual rate',
    droppedPackets: 'Dropped',
    tooManyDropsWarning: 'A lot of packets are being dropped. Move the phone closer to the collar.',
    beatsDetectedIn: 'beats detected',
    beatIntervalsTitle: 'Beat-to-beat intervals',
    notEcgDisclaimer: 'This reading comes from an accelerometer sensing the mechanical vibration of the heart. It is not an ECG and cannot diagnose an arrhythmia.',
    qualityGood: 'Reliable',
    qualityFair: 'Approximate',
    qualityUnusable: 'Not measurable',
    respirationShort: 'Breathing',
    beatCvLabel: 'Interval variability',
    devicesTitle: 'Collar',
    registeredCollars: 'Known collars',
    searchAction: 'Search',
    noCollarsYet: 'No collars registered yet.\nPower on the collar, then tap Search.',
    selectAction: 'Use',
    selectedLabel: 'Selected',
    renameAction: 'Rename',
    forgetAction: 'Forget',
    collarNameDialogTitle: 'Collar name',
    collarNameHint: 'e.g. Momo\'s collar',
    cancelAction: 'Cancel',
    saveAction: 'Save',
    signalStrength: 'Signal',
    connectTimes: 'Connected',
    lastConnected: 'Last',
    newlyFound: 'Newly found',
    goodToKnowTitle: 'Good to know',
    noteOneClientOnly: 'The collar accepts one client at a time. While a computer is connected, the phone cannot connect.',
    noteKnownIsFast: 'A known collar connects without scanning, so it takes only a few seconds.',
    noteNoBatteryYet: 'The collar has no battery yet, so it only runs while powered over USB.',
    recordsTitle: 'Measurement records',
    dailyMeanTitle: 'Daily average heart rate',
    dailyMeanNote: 'Measurements that could not be computed are excluded',
    measurementCount: 'measurements',
    exportCsvForVet: 'Export CSV for the vet',
    csvCopied: 'CSV copied. Paste it into an email or a note.',
    noRecordsYet: 'No measurements yet.\nStart one from the Measure tab.',
    deleteRecord: 'Delete this record',
    durationLabel: 'Duration',
    postureLabel: 'Posture',
    reportTitle: 'Heart-rate measurement report',
    exportThisRecord: 'Export this measurement',
    exportPdf: 'Export as PDF',
    exportCsv: 'Export as CSV',
    exportBoth: 'Both PDF and CSV',
    exportFailed: 'Export failed',
    hrvClinicalNote: 'SDNN and RMSSD are derived from a mechanical signal. They are not comparable to ECG reference ranges; use them only against this animal’s own history.',
    reportMeasuredWith: 'Device: PET-Sense collar (accelerometer)',
    reportNoJapaneseFont: 'Exported in Latin script (no CJK font bundled)',
    liveWaveTitle: 'Heart vibration (8–40 Hz)',
    liveWaveHint: 'Each green mark is one beat. Evenly spaced marks mean a good signal.',
    rateTooLowWarning: 'The sampling rate is too low to compute a heart rate. Check the collar configuration.',
    errBtOff: 'Bluetooth is off. Please turn it on in Settings.',
    errBtDenied: 'Bluetooth permission is not granted. Please allow it in Settings.',
    errNotFound: 'Collar not found. Check that it is powered on.',
    errWrongDevice: 'Connected to a different device. Power-cycle the collar and try again.',
    errOldFirmware: 'The collar\'s firmware may be out of date.',
    errBusy: 'Another app or computer is connected to the collar. It accepts only one connection at a time.',
    errConnectFailed: 'Could not connect. Check the collar’s power and your Bluetooth.',
    errLinkLost: 'The connection was lost.',
    errTooShortPrefix: 'The measurement was too short (at least ',
    errTooShortSuffix: 's required)',
    errSaveFailed: 'The result was computed but could not be saved',
    historyLoadFailed: 'Could not read the history',
    beatCountLabel: 'Beats found',
    secondsUnit: 's',
    daysCount: 'days',
    caveatUnusable: 'The signal was too weak to compute a heart rate.',
    caveatFair: 'The signal was weak. Treat this as approximate.',
    caveatManyGaps: 'Too many packets were dropped, so the interval metrics are unreliable.',
  );

  static const AppStrings _zh = AppStrings(
    language: AppLanguage.zh,
    navHome: '首页',
    navHistory: '历史',
    navSettings: '设置',
    petName: 'Momo',
    petBreedAge: '柴犬・2岁',
    bodyTempLabel: '体温',
    ambientTempLabel: '环境温度',
    celsiusUnit: '℃',
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
    navMap: '地图',
    mapNotConfiguredTitle: '需要配置地图',
    mapNotConfiguredDesc: '配置高德地图 API Key 后，这里会显示当前位置。',
    waitingForLocation: '等待位置信息',
    lastKnownLocationPrefix: '最后已知位置',
    navMeasure: '测量',
    measureStart: '开始测量',
    measureStop: '停止测量',
    measureHint60s: '约 60 秒',
    measurePleaseWait: '请稍候',
    measureIdle: '待机中',
    measureConnecting: '正在连接项圈…',
    measureSearching: '正在搜索项圈…',
    measureMeasuring: '测量中',
    measureAnalyzing: '正在分析…',
    measureDone: '完成',
    measureFailed: '失败',
    collarNotConnected: '项圈未连接',
    collarConnectedTo: '已连接',
    collarChoose: '选择',
    collarSwitch: '切换',
    viewPastMeasurements: '查看历史测量',
    tipsTitle: '测量要点',
    tipSensorPlacement: '把传感器贴在左胸下方（心脏下侧），这里信号最强',
    tipPartFur: '拨开毛发，使其紧贴皮肤',
    tipStayStill: '尽量保持不动 60 秒',
    tipKeepPhoneClose: '手机放在项圈附近',
    liveStabilizing: '大约需要 15 秒才能稳定',
    recentWindowNote: '最近 30 秒的数值',
    receivedSamples: '已接收',
    measuredRate: '实测采样率',
    droppedPackets: '丢包',
    tooManyDropsWarning: '丢包较多。请把手机靠近项圈。',
    beatsDetectedIn: '次心跳',
    beatIntervalsTitle: '逐拍间隔',
    notEcgDisclaimer: '本测量通过加速度传感器捕捉心脏的机械振动，并非心电图，不能用于诊断心律失常。',
    qualityGood: '可信',
    qualityFair: '参考值',
    qualityUnusable: '无法计算',
    respirationShort: '呼吸',
    beatCvLabel: '间隔波动',
    devicesTitle: '项圈',
    registeredCollars: '已登记的项圈',
    searchAction: '搜索',
    noCollarsYet: '还没有登记的项圈。\n请先给项圈通电，然后点击“搜索”。',
    selectAction: '使用',
    selectedLabel: '已选择',
    renameAction: '重命名',
    forgetAction: '删除登记',
    collarNameDialogTitle: '项圈名称',
    collarNameHint: '例如：毛毛的项圈',
    cancelAction: '取消',
    saveAction: '保存',
    signalStrength: '信号',
    connectTimes: '已连接',
    lastConnected: '上次',
    newlyFound: '新发现的项圈',
    goodToKnowTitle: '须知',
    noteOneClientOnly: '项圈同时只能连接一台设备。电脑连接期间，手机无法连接。',
    noteKnownIsFast: '已登记的项圈无需搜索即可连接，几秒即可完成。',
    noteNoBatteryYet: '项圈目前没有电池，只有通过 USB 供电时才能工作。',
    recordsTitle: '测量记录',
    dailyMeanTitle: '每日平均心率',
    dailyMeanNote: '未包含无法计算的测量',
    measurementCount: '条测量',
    exportCsvForVet: '导出 CSV 给兽医',
    csvCopied: '已复制 CSV，可粘贴到邮件或备忘录中。',
    noRecordsYet: '还没有测量记录。\n请从“测量”标签开始。',
    deleteRecord: '删除这条记录',
    durationLabel: '测量时长',
    postureLabel: '姿势',
    reportTitle: '心率测量报告',
    exportThisRecord: '导出这条测量',
    exportPdf: '导出为 PDF',
    exportCsv: '导出为 CSV',
    exportBoth: 'PDF 与 CSV 两者',
    exportFailed: '导出失败',
    hrvClinicalNote: 'SDNN 与 RMSSD 来自机械振动信号，不能与心电图参考值比较，仅可用于同一个体的历史对比。',
    reportMeasuredWith: '测量设备: PET-Sense 项圈（加速度传感器）',
    reportNoJapaneseFont: '未内置中日文字体，已以拉丁字母输出',
    liveWaveTitle: '心脏振动（8–40 Hz）',
    liveWaveHint: '上方每个绿色标记为一次心跳。间隔均匀说明信号良好。',
    rateTooLowWarning: '采样率过低，无法计算心率。请检查项圈配置。',
    errBtOff: '蓝牙已关闭，请在设置中开启。',
    errBtDenied: '未获得蓝牙使用权限，请在设置中允许。',
    errNotFound: '未找到项圈，请确认已通电。',
    errWrongDevice: '连接到了其他设备。请重新给项圈上电后再试。',
    errOldFirmware: '项圈固件可能过旧。',
    errBusy: '其他应用或电脑正连接着项圈。项圈同时只能连接一台设备。',
    errConnectFailed: '连接失败。请检查项圈电源与蓝牙。',
    errLinkLost: '连接已断开。',
    errTooShortPrefix: '测量时间过短（至少需要 ',
    errTooShortSuffix: ' 秒）',
    errSaveFailed: '已算出结果，但保存失败',
    historyLoadFailed: '无法读取历史记录',
    beatCountLabel: '检出心跳数',
    secondsUnit: '秒',
    daysCount: '天',
    caveatUnusable: '信号不足，无法计算心率。',
    caveatFair: '信号较弱，请作为参考值看待。',
    caveatManyGaps: '丢包较多，逐拍间隔指标不可靠。',
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
