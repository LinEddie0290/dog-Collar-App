# 通信方式とデータ契約の変更（2026-09-12）

`SensorSample` は二人の共有インターフェースなので、変更点をここにまとめます。
`packages/collar_data/README.md` の「SensorSample 是两人接口，数据侧改字段会提前通知」
に従った通知です。

## なぜ変えたか

アプリのデータ層は **JSON over WiFi (WebSocket)** を前提に作られていました。
`PET-main/docs/mobile-app-integration.md` を読むと、実機はそのどれでもありません。

> 设备为 Seeed XIAO nRF54LM20A Sense，通过 BLE GATT 传输数据，
> **不提供 Wi-Fi、TCP 或 MQTT 服务**

nRF54LM20A は Nordic 社の BLE 専用 SoC で、Wi-Fi のハードが載っていません。
つまり `WebSocketCollarDataSource`（`ws://<collar-ip>:81`）は実機に到達不能で、
これまでモックサーバーとだけ通信していたことになります。

加えて、`SensorSample` に追加されていた GPS フィールドの注記で懸念されていた
ことがそのまま現実になりました。

> please confirm the raw JSON key names (`lat` / `lng` / `gps_accuracy_m`)
> match what the collar firmware actually sends

キー名が違っていたのではなく、**首輪は JSON を送ってきません**。バイナリの
固定レイアウトで、GPS は生の NMEA 文がそのまま乗ってきます。

## いちばん大きい変更：心拍と呼吸が取れない

首輪に載っているセンサーは5つで、心拍センサーと呼吸センサーは含まれません。

| ID | センサー | アプリでの扱い |
|---|---|---|
| 1 | LSM6DS3TR-C IMU（内蔵） | `ax`..`az` / `gx`..`gz` |
| 2 | BMI088 IMU（外付け） | 同上（既定では ID 1 のみ表示） |
| 3 | MLX90615 赤外温度 | **`bodyTempC` / `ambientTempC`（新規・主役）** |
| 4 | Air530 GPS | `lat` / `lng` / `fixQuality` / `satellites` / `hdop` |
| 5 | MSM261DGT006 マイク | 未使用（既定で SET_CONFIG により停止） |

そのため：

- **`hr` を削除しました。** 取得経路が存在しないため、フィールドごと外しました。
  ホーム画面と履歴画面は体温表示に差し替えています。
- **`resp` は残しました。** 現行ハードでは常に `null` です。IMU の周期成分から
  推定するのが現実的な手法で、後から追加する予定があるため、そのときに
  この契約を再度変えなくて済むよう欄だけ確保しています。
- **`battery` も常に `null` です。** センサー一覧にも 20 バイトの Status
  スナップショットにも電池残量が含まれていません。UI は `--` を表示します。
  出すにはファームウェア側の対応（MCU の電源電圧読み取りを PET v1 に追加）が
  必要です。
- **`gpsAccuracyM` を削除しました。** 首輪は精度（メートル）を送ってきません。
  NMEA の GGA から取れるのは測位品質・衛星数・HDOP までです。HDOP は無次元の
  倍率なので、`estimatedAccuracyM`（`HDOP × 5m`）という**概算**として別に
  切り出し、UI では「目安」と明示します。

## `SensorSample` の差分

```diff
- final double? hr;                  // 削除：心拍センサーが存在しない
- final double? gpsAccuracyM;        // 削除：首輪は精度を送ってこない
+ final double? bodyTempC;           // 追加：赤外温度センサーの対象温度
+ final double? ambientTempC;        // 追加：センサー自身の周囲温度
+ final double? gx, gy, gz;          // 追加：角速度（IMU から届いているので）
+ final int? fixQuality;             // 追加：GGA の測位品質。0 は未測位
+ final int? satellites;             // 追加：測位に使った衛星数
+ final double? hdop;                // 追加：HDOP（倍率、メートルではない）

  final double? resp;                // 維持。実機では常に null（後日 IMU から推定）
  final int? battery;                // 維持。実機では常に null
```

JSON のキー名（モックとアーカイブで使用）：
`body_temp_c` / `ambient_temp_c` / `fix_quality` / `satellites` / `hdop`、
IMU は `imu: {ax, ay, az, gx, gy, gz}`。

## 「正しい NMEA」と「測位できた」は別物

ここが一番ハマりやすいところなので、判定を一箇所に閉じ込めました。

2026-09-11 の検証記録より：

> GPS 的 120 条 GGA 均为 fix quality 0、使用卫星数 0，120 条 RMC 均为状态 V。
> **这证明 GPS UART/NMEA 数据能被采集，不证明已成功定位。**

書式の正しい NMEA が 1,200 件届いていて、測位は 0 件でした（屋内のため）。
なので `hasLocation` は座標の有無だけでなく `fixQuality >= 1` も見ます。
ここを緩めると「測位していないのに地図に犬が出る」ことになります。

**屋外での測位確認がまだ未実施です。** これはアプリ側では解決できないので、
相棒さんに確認が必要な項目です。

## 座標系（これを忘れると数百メートルずれる）

NMEA が返すのは WGS84、高徳地図が使うのは GCJ-02 です。地図に出す前に
`wgs84ToGcj02()` を通す必要があります。上海付近でのずれは実測で約 570m でした。
`collar_geo` にもとから入っていた変換がそのまま必要になります。

## 追加したもの

| ファイル | 役割 |
|---|---|
| `collar_data/lib/src/pet_protocol.dart` | PET v1 のフレーム・分割・再組み立て・コマンド・応答 |
| `collar_data/lib/src/pet_sample.dart` | IMU / 温度 / GPS / マイク / 読み取りエラーのデコード |
| `collar_data/lib/src/pet_assembler.dart` | センサー別フレームを1つのスナップショットに統合 |
| `collar_geo/lib/src/nmea.dart` | NMEA 解析、測位有効性の判定、HDOP からの精度概算 |
| `lib/data/ble_collar_data_source.dart` | flutter_blue_plus による実機接続 |
| `collar_data/bin/pet_demo.dart` | プロトコルの自己検証 |
| `collar_geo/bin/nmea_demo.dart` | NMEA の自己検証 |

`pet_protocol.dart` は `PET-main/tools/pet_codec.py` の移植です。自己検証に
焼き込んだ期待値はそのリファレンス実装に生成させたもので、GET_CONFIG の
フレームは手引き 4.3 の例と1バイトも違いません。

## 構造上の都合：1フレーム1センサー

PET v1 は**1フレームに1センサー分しか入りません**。IMU フレームに温度は無く、
GPS フレームに IMU は無い。一方で UI は「全部入った1つのオブジェクト」を
欲しがります。そこで `PetSampleAssembler` が各センサーの最新値を保持して
統合スナップショットを作ります。

センサーごとに鮮度の期限を持たせています。期限切れの値は `null` に戻します。
これが無いと、モジュールが外れて報告を止めても最後の値が画面に残り続け、
生きているように見えてしまいます。

| センサー | 期限 | 理由 |
|---|---|---|
| IMU | 3秒 | 26〜104Hz で来るので、3秒来なければ異常 |
| 温度 | 15秒 | 2Hz。読み取りリトライで間隔が伸びることがある |
| 位置 | 2分 | `LocationController.offlineThreshold` と一致 |

また UI 向けの発行は 250ms 間隔に絞っています。IMU をそのまま流すと毎秒
26〜104 個のスナップショットが履歴バッファ（600件）に入り、6秒分しか
残らなくなるためです。**アーカイブは間引かず全フレーム保存します。**

## 帯域の都合：マイクは既定で切る

接続時に `STOP → SET_CONFIG → START` を送り、マイクを止めて IMU を 26Hz に
落とします。理由は、

- マイク単体で約 32kB/s あり、BLE では他のセンサーを餓死させる
- ファームウェアのキューは**全センサー共用で32フレーム**しかなく、溢れると
  `dropped` が増えて GPS フィックスが落ちる

吠え声翻訳を実装するときは `enableMicrophone: true` にしますが、そのときは
他を削る前提で設計する必要があります。

## アーカイブが実機でも「忠実」になるように

`RawFrame` に `bytes` を追加し、アーカイブの各行に `pet_frame_hex` を
書くようにしました。デコードした map はこちらの**解釈**で、バイト列が
**証拠**です。デコーダのバグを疑ったとき、犬にもう一度歩いてもらわずに
`decodeFrame` や `pet_codec.py decode` で再生できます。

## 相棒さんに確認したいこと

1. **屋外で GPS が測位できたか。** 検証記録は屋内のため全件 fix quality 0 です。
2. **電池残量を PET v1 に追加する予定があるか。** 今は UI に出せません。
3. **心拍センサーを追加する予定があるか。** 無い前提で UI を体温に寄せました。
4. **IMU を 26Hz に落として問題ないか。** 行動分類に 104Hz が必要なら、
   マイクを切ったうえで上げ直せます。

---

## 2026-09-13 実機テストで判明した不具合と修正

### サンプリング 26 Hz で心拍が嘘になっていた（最重要）

実機で3回測定したところ、3回とも **221.4 bpm / 品質 good / 信頼度 0.86–0.93**
という値が出た。CSV の `サンプリング(Hz)` 列は `26`。

原因は3つ重なっていた。

1. `BleCollarDataSource.imuRateHz` の既定値が `26` だった。心弾動の帯域は
   8–40 Hz なので、26 Hz サンプリング（ナイキスト 13 Hz）では帯域そのものが
   測定範囲の外にある。
2. iOS では `BluetoothDevice.requestMtu()` が例外になる（MTU は CoreBluetooth
   が自分で決める仕様）。例外を捕まえて `_mtu = 23` と決めつけていたため、
   実際には MTU 185 程度あるのに「最小 MTU」と判定され、レートが 52 Hz に
   引き下げられていた。
3. `VitalsAnalyzer` がナイキスト周波数を確認せずに 8–40 Hz の帯域通過を
   かけていた。biquad の係数が壊れて出力が発振し、それを自己相関が
   「強い周期性」と読んだ。**エラーにならず、品質 good として保存された。**

修正:

| 箇所 | 変更 |
|---|---|
| `ble_collar_data_source.dart` | 既定レートを 26 → **104 Hz** |
| 同 | `requestMtu` 失敗時は `device.mtuNow` を読む（23 と決めつけない） |
| `vitals_analyzer.dart` | `minSampleRateHz = 40.0`。これ未満は `unusable`（理由 `rate_too_low`）を返し、数値を出さない |
| 同 | 帯域をナイキスト×0.9 に収める。収まらないときは切り詰めて続行し、信頼度の低下として現れる |
| `bin/demo.dart` | 26 Hz で数値を出さないこと・104 Hz で 78 bpm を出すことをテストに追加 |

400 Hz の実測データ（2026-09-12、胸骨左下、内蔵IMU）を間引いて検証した結果:

| サンプリング | 帯域 | 心拍 | 信頼度 |
|---|---|---|---|
| 416 Hz | 8–40 Hz | 77.7 bpm | 0.59 |
| 208 Hz | 8–40 Hz | 77.9 bpm | 0.33 |
| **104 Hz** | 8–40 Hz | **77.8 bpm** | **0.25** |
| 52 Hz | 8–22.5 Hz | 78.7 bpm | 0.19 |
| 26 Hz | 6–12 Hz | 79.2 bpm | 0.05 |

104 Hz で値は正しく出る。信頼度に余裕を持たせたいなら 208 Hz も選べるが、
BLE の取りこぼしが増える可能性があるため既定は 104 Hz にした。

**26 Hz で保存された記録は削除すること。** 数値は意味を持たない。

### 測定中の表示

* 帯域通過後の波形を 10 fps で流す `LiveWaveChart` を追加。拍の検出位置も
  重ねて出す。数値が出る前から「取れているか」が分かるようにするため。
* 画面の心拍の初回表示を 15 秒 → **8 秒**に短縮（`liveMinSeconds`）。
  保存する測定の基準は 15 秒のまま。自己相関は 8 秒（約6周期）あれば立つ。
* 更新間隔 3 秒 → 1 秒。

### 1測定ごとの書き出し

`RecordExport`（`lib/data/record_export.dart`）を追加。1件の測定を
**PDF 1枚**（人が読む・獣医に渡す）と **CSV**（機械が読む・解析やAIに回す）
として書き出す。PDF だけ・CSV だけ・両方の3通りを選べる。

* 保存先は `Documents/reports/`。`UIFileSharingEnabled` を立ててあるので
  「ファイル」アプリからも取り出せる。共有シート経由でメール・AirDrop も可。
* ファイル名は `2026-09-13_1102_78bpm.pdf` の形。日時が先頭なので何通
  渡しても時間順に並ぶ。
* CSV の列名は英語で固定。表示言語で列名が変わると、同じ列を指せなくなる。
* PDF の日本語には TTF の同梱が必要（`assets/fonts/README.txt`）。
  フォントが無い場合は英字ラベルの PDF になる。止めるより出すほうがまし。
* PDF には必ず「心電図ではない」「SDNN/RMSSD は心電図の基準値と比較できない」
  を数値と同じページに載せる。
