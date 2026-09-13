import 'package:amap_map/amap_map.dart';
import 'package:flutter/widgets.dart';
// AMapApiKey / AMapPrivacyStatement は amap_map ではなく土台パッケージ側。
import 'package:x_amap_base/x_amap_base.dart'
    show AMapApiKey, AMapPrivacyStatement;

/// 高德地図の API キー。
///
/// アカウント作成・キー発行が必要な作業なのでこちらでは代行できません:
///   1. https://console.amap.com で開発者登録
///   2. Android 用と iOS 用、それぞれの API キーを発行
///   3. 下の2つの定数を実際のキーに置き換える
///
/// プレースホルダーのままの間は [isAmapConfigured] が false を返し、
/// MapPage は地図の代わりに「設定が必要です」という案内を表示する
/// (存在しないキーで地図 SDK を呼んでクラッシュさせないためのガード)。
const String amapAndroidKey = 'YOUR_AMAP_ANDROID_KEY';
const String amapIosKey = 'YOUR_AMAP_IOS_KEY';

bool get isAmapConfigured =>
    amapAndroidKey != 'YOUR_AMAP_ANDROID_KEY' && amapIosKey != 'YOUR_AMAP_IOS_KEY';

/// 高德地図 SDK の初期化(API キー登録 + プライバシー同意)。
///
/// API は pub cache 内の x_amap_base 1.0.3 の実ソースで確認済み:
///   AMapApiKey({String? iosKey, String? androidKey})
///   AMapPrivacyStatement({bool? hasContains, bool? hasShow, bool? hasAgree})
///   AMapInitializer.init(BuildContext, {AMapApiKey? apiKey})
///   AMapInitializer.updatePrivacyAgree(AMapPrivacyStatement)
///
/// SDK のバージョンを上げたときにここが壊れる可能性があるので、地図 SDK の
/// 初期化はこの1ファイルに閉じ込めてある。
///
/// 呼び出し方: amap_map の README どおり、runApp が最初に表示する Widget の
/// `build` の中で `context` を渡して一度だけ呼ぶ(main.dart の
/// `_CollarAppState.build` がそうしている)。`initState` では BuildContext が
/// まだ使えないのでダメ。
///
/// [isAmapConfigured] が true のときだけ呼ぶこと。プレースホルダーキーのまま
/// 呼ぶと SDK 内部でエラーになる可能性があるため。
void initAmap(BuildContext context) {
  AMapInitializer.updatePrivacyAgree(
    const AMapPrivacyStatement(
      hasContains: true,
      hasShow: true,
      hasAgree: true,
    ),
  );

  AMapInitializer.init(
    context,
    apiKey: const AMapApiKey(
      androidKey: amapAndroidKey,
      iosKey: amapIosKey,
    ),
  );
}
