# GPS(位置情報)機能 — セットアップと現状

このドキュメントは、GPS機能を追加したときの変更点と、残っている手動作業を
まとめたものです。`flutter analyze` でエラーが出た場合は、まずここを見てください。

## 何を追加したか

- `packages/collar_geo/` — 座標変換(WGS84↔GCJ-02)・地理囲い判定の純Dartパッケージ
  (`collar_data` と同じ思想: 依存ゼロ、`dart run bin/demo.dart` で単体確認可能)
- `packages/collar_data` の `SensorSample` に `lat` / `lng` / `gpsAccuracyM` を追加
  (⚠️ 学弟/データ層担当との「二人の契約」に対する変更 — 実際の項圈のJSONキー名が
  `lat`/`lng`/`gps_accuracy_m` で合っているか確認してください)
- `lib/state/location_controller.dart` — 位置情報と地理囲いの状態管理(CollarControllerと同じ設計)
- `lib/ui/map_page.dart` + `lib/ui/amap_provider.dart` + `lib/ui/map_provider.dart` — 地図タブ
- ボトムナビに「地図」タブを追加(Home / **Map** / History / Settings)
- 日英中3言語ぶんの文言を追加

## 動作確認の状況

**`flutter analyze` エラー0件**(残る info は `avoid_print` と
`unnecessary_library_name` だけで、これは `collar_data` 側も同じスタイルなので
既存に合わせて意図的に残しています)。
**`packages/collar_geo` のセルフテストは全項目パス**
(北京の座標ずれ 554.9m、上海の往復変換誤差 0.000m、囲いの入退場・重複抑制・
初回誤報なし、円の多角形近似の頂点誤差 0.00m)。

途中で出たエラーの内訳と直し方(同じ罠を踏んだとき用):

- `LatLng` / `AMapApiKey` / `AMapPrivacyStatement` が見つからない
  → これらは `amap_map` ではなく土台パッケージ `x_amap_base` 側にあった
    (import は `package:x_amap_base/x_amap_base.dart`。pub.dev のドキュメントは
     2.x 系のもので、そちらはファイル名が `amap_flutter_base.dart` に変わって
     いるため、1.0.3 では動かない)。`show` 付きで import を追加し、
    `pubspec.yaml` に `x_amap_base: ^1.0.3` を明示依存として追加。
    (`Marker` / `Polygon` / `CameraPosition` は `amap_map` が独自に持っている
     ので、`show` で必要な名前だけ取り込んで衝突を避けている)
- `AMapPrivacyStatement(hasContainsPrivacy: ...)` → 正しくは `hasContains:`

API は pub cache 内の x_amap_base 1.0.3 の実ソースで確認済み(公開ドキュメントは
2.x 系なので信用しないこと):

```
AMapApiKey({String? iosKey, String? androidKey})
AMapPrivacyStatement({bool? hasContains, bool? hasShow, bool? hasAgree})
AMapInitializer.init(BuildContext, {AMapApiKey? apiKey})
AMapInitializer.updatePrivacyAgree(AMapPrivacyStatement)
const LatLng(double latitude, double longitude)   // 位置引数
```

### collar_geo のセルフテストの回し方

`packages/collar_geo` は独立したパッケージなので、初回だけそのディレクトリで
`dart pub get` が必要です(ルートの `flutter pub get` では生成されません)。

```bash
cd packages/collar_geo
dart pub get        # ← 初回のみ。これを忘れると "Couldn't resolve the package" になる
dart run bin/demo.dart
```

## 必要な手動セットアップ(アカウント操作なので代行できません)

### 1. 高徳地図の API キー

1. https://console.amap.com で開発者登録
2. Android用・iOS用、それぞれAPIキーを発行
3. `lib/ui/amap_init.dart` の `amapAndroidKey` / `amapIosKey` を実際の値に置き換える

キーを設定するまでは、地図タブには「地図の設定が必要です」という案内が出るだけで、
アプリ自体はクラッシュしません(`isAmapConfigured` によるガード)。

### 2. ネイティブ設定

**追加済み**(`amap_map` 1.0.15 の example アプリの設定に合わせました。編集後、
XMLとplistとして壊れていないことは `xml.etree` / `plistlib` でパースして確認済み):

- `android/app/src/main/AndroidManifest.xml`
  → `INTERNET` / `ACCESS_COARSE_LOCATION` / `ACCESS_FINE_LOCATION` /
    `ACCESS_NETWORK_STATE` / `ACCESS_WIFI_STATE` の5つ
- `ios/Runner/Info.plist`
  → `NSLocationWhenInUseUsageDescription` /
    `NSLocationAlwaysAndWhenInUseUsageDescription`(日本語の説明文)

なお、Androidの `com.amap.api.v2.apikey` の meta-data は**不要**です
(example でもコメントアウトされている)。このプラグインはキーをコードから
`AMapInitializer.init(context, apiKey: ...)` で渡す方式なので、
`lib/ui/amap_init.dart` の定数を書き換えるだけで両プラットフォームに効きます。

iOSの説明文は今は日本語固定です。アプリ自体は日英中3言語なので、ここも
言語ごとに出し分けたくなったら `ios/Runner/<lang>.lproj/InfoPlist.strings` を
足すことになります(今すぐ必要ではないので保留)。

**まだ入れていないもの: `ws://` (平文通信) の許可**

これはGPSとは無関係で、実機の首輪に WebSocket で繋ぐときに必要になります。
アプリ全体の通信の安全性を下げる設定なので、私の判断で勝手に入れるのは
やめました。実機接続を試す段になったら、以下を足してください。

Android — `<application ...>` タグに属性を1つ追加:

```xml
<application
    android:label="collar_app"
    android:usesCleartextTraffic="true"   <!-- ← これ。ws:// は平文なので必要 -->
    ...>
```

iOS — `Info.plist` に(開発中だけの緩い設定。審査に出す前に、
`NSExceptionDomains` で首輪のアドレスだけ許可する形に絞るのが望ましい):

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
<key>NSLocalNetworkUsageDescription</key>
<string>同じWi-Fi上の首輪に接続するために使用します。</string>
```

## 動作確認の流れ(おすすめ)

1. ~~`cd packages/collar_geo && dart pub get && dart run bin/demo.dart`~~ 済(全パス)
2. ~~`flutter pub get && flutter analyze`~~ 済(エラー0)
3. 高徳APIキーを設定 ← **いまここ**
4. `flutter run` して、「アプリ内モックを使う」のまま地図タブを開く
   → `FakeCollarDataSource` が10フレームに1回GPS座標を出すので、しばらく待つと
   マーカーが表示されるはず
5. 実機の首輪と繋ぐ段階になったら、上の「まだ入れていないもの: `ws://`」を足す
