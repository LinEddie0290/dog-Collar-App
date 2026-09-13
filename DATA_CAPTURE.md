# データ採取ガイド

首輪から実データを採る手順。コマンドは断りがなければ
`~/Desktop/PET-main` の中で実行します。

---

## 1. 仕組み — 経路は2つある

センサーの値は MCU に集まり、そこから **USB** と **BLE** の2経路で出ていきます。
同じセンサーの同じ値が、別の口から出るイメージです。

```
 ┌──────────────────── 首輪(XIAO nRF54LM20A Sense) ────────────────────┐
 │                                                                     │
 │  ①内蔵IMU ┐                                                        │
 │  ②BMI088  ├→ MCU が採取 → 32フレームのリングバッファ ─┬→ USB      │
 │  ③赤外温度┤                                             └→ BLE      │
 │  ④GPS     │                                                         │
 │  ⑤マイク  ┘                                                         │
 └─────────────────────────────────────────────────────────────────────┘
                        │                          │
                 有線(USB ケーブル)          無線(Bluetooth)
                        ↓                          ↓
                    Mac の採取ツール          Mac / スマホアプリ
```

| | USB 採取 | BLE 採取 |
|---|---|---|
| 何に使うか | **データをちゃんと残して解析する** | **スマホが実際に受け取るものを確認する** |
| 帯域 | 広い(マイクも余裕) | 狭い(マイクを流すと他が落ちる) |
| 保存 | 自動。専用ディレクトリに整理される | **自分でリダイレクトが必要** |
| 解析ツール | 波形 HTML・PNG・CSV・WAV を生成 | JSON が流れるだけ |
| 犬に着けられるか | ケーブルが繋がるので無理 | できる |

**採取の主役は USB です。** 犬に着けて動かすデータが必要なときだけ BLE を使います。

重要な前提が2つあります。

- **両者はボード上の同じセンサー設定を共有します。** スマホから `STOP` を送ると
  USB 側にも新しいデータが来なくなります。逆に普通の `capture` は USB 出力の
  オン/オフだけを操作し、センサーの選択は変えません。
- **バッファは全センサー共用で32フレームだけ**です。内蔵 IMU が 104Hz で
  回っていると1秒未満で埋まります。溢れた分は古いものから捨てられます。

---

## 2. 0回目 — 環境構築(まだ未実行です)

`PET-main/.venv` と `.tools` が無いので、**まだ一度も構築されていません**。
最初にこれが必要です。

```sh
cd ~/Desktop/PET-main
./scripts/setup.sh
```

- 数 GB のツールチェーンをダウンロードします。**初回はネットと時間が必要**です
- 固件を一度ビルドしますが、**ボードへの書き込みはしません**(接続も不要)
- Apple Silicon Mac では Rosetta と開発者ツールが必要です

終わったら確認します。

```sh
./scripts/pet info
./scripts/pet ports      # ボードが見えるか
```

### setup.sh が途中で失敗したとき

このスクリプトは**3段階**で、途中で失敗しても前の段階は残ります。
再実行すると終わった段階は飛ばされます。

| 段階 | 何をするか | 採取に必要か |
|---|---|---|
| ① Python 環境 | pyserial / numpy / matplotlib / plotly など38個 | **必要** |
| ② PlatformIO ツール | コンパイラ、Zephyr 本体など | 不要 |
| ③ Zephyr モジュール37個 + ビルド | 固件をコンパイルするための部品 | 不要 |

**①が終わっていれば採取と波形表示はできます。** ②③はファームウェアを
自分で書き換えるときにだけ必要です。ボードに固件が既に書かれているなら
(9/11 の検証時に書き込み済み)、②③の失敗は無視して採取を始められます。

判定はこれで付きます。

```sh
.venv/bin/python -c "import serial, numpy, matplotlib, plotly; print('採取OK')"
```

### `shallow.lock: File exists` で失敗する場合

③の段階で git が残したロックファイルが原因です。前回の中断時の置き土産で、
消さないと何度再実行しても同じところで止まります。

```sh
cd ~/Desktop/PET-main
find .tools/module-staging -name "*.lock" -delete
./scripts/setup.sh
```

それでも同じモジュールが失敗するなら、そのモジュールの作業ディレクトリを
消してやり直します(再ダウンロードされます)。

```sh
rm -rf .tools/module-staging/失敗したモジュール名
./scripts/setup.sh
```

`Failed to connect to github.com port 443` は単純な回線の問題です。
再実行するか、回線の速い場所で試してください。

> ⚠️ `PET-main` は git リポジトリではなく zip を展開したものです。`captures/` は
> ここに作られるので、**フォルダを消したり再ダウンロードすると採取データも
> 消えます**。大事なデータは別の場所にコピーしてください。

---

## 3. 配線の確認(外付けモジュール)

内蔵 IMU とマイクは何もしなくても採れます。残り3つは配線が必要です。

| モジュール | 配線 |
|---|---|
| BMI088(IMU) | SDA → D4、SCL → D5 |
| MLX90615(赤外温度) | SDA → D0、SCL → D1 |
| Air530(GPS) | TX → D7、RX → D6 |

3つともブレッドボードで 3V3 / GND を共有します。

**ここが引っかかりポイントです。**

- **動作中の抜き差しは効きません。** モジュールの検出は**起動時のみ**です。
  繋ぎ忘れに気づいたら、配線してから**電源を入れ直す**必要があります
- **GPS の検出窓は約 2.2 秒だけ**です。この間に正しい NMEA を1つも出せなかった
  モジュールは「無し」と判定されます。GPS が認識されないときは、まず再起動を
  試してください
- **GPS はアンテナと空の見通しが必要です。** 屋内では、正しい書式の NMEA は
  届くのに測位は永久に失敗します(9/11 の検証で 1,200 件届いて測位 0 件)

---

## 4. USB で採る(基本形)

ボードを USB で Mac に繋いで、

```sh
cd ~/Desktop/PET-main
./scripts/pet capture --seconds 30
```

これだけです。ボードは自動で探します(USB の VID/PID `2886:0068`)。
`captures/` の下に UTC 時刻の名前でディレクトリが作られ、**最後に「今回の
ディレクトリ」と確認コマンドが表示されます**。それをそのまま使います。

よく使う形：

```sh
# 名前を付けて保存（後から探しやすい）
./scripts/pet capture --seconds 60 --output captures/walking

# Ctrl+C まで採り続ける
./scripts/pet capture --seconds 0

# ボードが見つからないとき：ポートを確認して明示する
./scripts/pet ports
./scripts/pet capture --port /dev/cu.usbmodemXXXX --seconds 30
```

**Ctrl+C は正しい終わり方です。** 停止を要求して残りを受け取ってから保存します。
USB を抜くと、そこまでのデータは読めますが「不完全」と表示されます。

`No PET USB handshake` と出たら、ポート・ボーレート(1000000)・新しい固件が
書かれているかを確認します。なお古い `tools/capture_serial.py` はログを見る
だけのツールで、採取の代わりには使えません。

---

## 5. 採ったデータを確認する

```sh
./scripts/pet view captures/20260910T162356Z-xxxxxxxx
```

ブラウザで `waveforms.html` が開きます。オフラインで動き、範囲選択・ホイールで
拡大、ホバーで数値、凡例でオン/オフ、ダブルクリックで戻せます。

### 出来上がるファイル

```
captures/20260910T162356Z-xxxxxxxx/
├── raw.usb          ← 生のバイト列（これが証拠。消さない）
├── session.json     ← 採取の記録と品質カウンタ
└── analysis/
    ├── waveforms.html   ← 対話的な波形ページ
    ├── onboard_imu.png  ← 3行2列、六軸の個別グラフ
    ├── onboard_imu.csv  ← 時刻＋六軸の全データ
    ├── mic.png          ← PCM 波形と RMS
    ├── mic-001.wav      ← 16000Hz モノラル PCM16
    └── （温度・GPS も同様。GPS は CSV のみでグラフ無し）
```

繋いでいないモジュールは「データ無し」と表示されます。**ゼロの偽の線は
引かれません。**

### session.json で見るべき7項目

採取が成功したかは、波形の見た目ではなくここで判断します。

| 項目 | 正常な値 | 意味 |
|---|---|---|
| `quality_ok` | `true` | 下の項目をまとめた総合判定 |
| `finished` / `stop_acknowledged` | `true` | 正常に握手して正常に終わったか |
| `bad_records` / `truncated_records` | `0` | CRC・書式エラー、途中で切れた記録 |
| `missing_sequence_numbers` | `0` | 途中で欠けたフレーム数 |
| `device_queued_minus_received` | `0` | 末尾の取りこぼし。0以外なら最後が欠けている |
| `latest_device_status.usb_dropped` | `0` | USB キューの溢れ |
| `sensor_read_errors` | `0` | センサーの読み取り失敗 |

### 品質を1コマンドで確認する

`session.json` を開いて目で追う代わりに、直近の採取の重要項目だけ抜き出せます。
`jq` は不要です(環境内の Python を使います)。

```sh
.venv/bin/python -c "
import json, glob, os
d = max(glob.glob('captures/*'), key=os.path.getmtime)
s = json.load(open(d + '/session.json'))
ng = []
print('採取ディレクトリ:', d)
for k in ['quality_ok','finished','stop_acknowledged','bad_records',
          'truncated_records','missing_sequence_numbers',
          'device_queued_minus_received','sensor_read_errors']:
    v = s.get(k)
    bad = (v is False) if isinstance(v, bool) else bool(v)
    if bad: ng.append(k)
    print(('  NG ' if bad else '  ok ') + k + ':', v)
u = s.get('latest_device_status', {}).get('usb_dropped')
if u: ng.append('usb_dropped')
print(('  NG ' if u else '  ok ') + 'usb_dropped:', u)
print()
print('→ 問題なし' if not ng else '→ 確認が必要: ' + ', '.join(ng))
"
```

どのセンサーから何件届いたかは、波形を出せば一目で分かります。繋いでいない
モジュールは「データ無し」と表示されるので、**期待したセンサーが「無し」に
なっていないか**が最初の確認点です。

`quality_ok` が `true` でも「バスが一度もリトライしなかった」という意味では
ありません。赤外温度センサーは失敗すると限定的にリトライします(9/11 は 14 回
リトライして全部復帰)。リトライの記録は `raw.usb` の `PET MLX retry` の行に
残ります。

---

## 6. BLE で採る(無線・スマホに近い形)

犬に着けて動かす、あるいはスマホが受け取るものを確認したいときはこちら。
**初回は macOS の Bluetooth 許可を求められます。**

```sh
cd ~/Desktop/PET-main
bash -c 'source scripts/env.sh; .tools/bin/uv run --no-project \
  --python .venv/bin/python --with bleak tools/pet_ble_client.py --seconds 15'
```

長いですが、`uv` が Bleak を一時的に用意するだけで、固件側の環境は汚しません。

**このツールは自分ではファイルに保存しません。** JSON が1行ずつ標準出力に
流れるので、残したいならリダイレクトします。

```sh
mkdir -p ~/Desktop/ble-captures
bash -c 'source scripts/env.sh; .tools/bin/uv run --no-project \
  --python .venv/bin/python --with bleak tools/pet_ble_client.py --seconds 60' \
  > ~/Desktop/ble-captures/walk-01.jsonl
```

主なオプション：

| オプション | 意味 |
|---|---|
| `--seconds 60` | 受信する秒数(既定 10) |
| `--mask 0x0f` | センサーを選ぶ。`STOP → SET_CONFIG → START` を自動で送る |
| `--rates 104 100 2 0 0` | サンプリングレート。**切ったセンサーは必ず 0** |
| `--print-samples` | 全サンプルを表示(既定は毎秒1件に要約) |
| `--stop-on-exit` | 終了時にボードの採取も止める |
| `--scan-seconds 10` | スキャンの待ち時間 |

**マイクを切る例**(IMU2つ＋温度＋GPS だけ。GPS のレートは有効でも 0 です)：

```sh
... tools/pet_ble_client.py --mask 0x0f --rates 104 100 2 0 0 --seconds 60
```

マイク単体で約 32kB/s あり、BLE では他のセンサーを餓死させます。
**BLE で採るときは基本的にマイクを切ってください。**

通常の終了ではボードは採取を続けます。止めたいときだけ `--stop-on-exit` です。

---

## 7. IMU だけ高速で採る

動きの細かい変化を見たいとき用の別入口です。2つの IMU だけを 416/400Hz で
採ります。

```sh
./scripts/pet capture-imu400 --seconds 20
./scripts/pet analyze-imu-frequency captures/該当ディレクトリ
```

この間、ボードの設定は一時的にこのスクリプトが握ります。**BLE 側の
`START` / `STOP` / `SET_CONFIG` は `BUSY` を返します**(スクリプト終了、または
5秒の心跳切れで元に戻ります)。スマホアプリを繋ぎながらは使えません。

---

## 8. 何を何回採るか(提案)

いま**いちばん分かっていないのは GPS が実際に測位できるかどうか**です。
アプリ側の地図はもう出来ているので、ここが埋まらないと先に進めません。

| # | 目的 | 経路 | 場所 | 時間 | 見るところ |
|---|---|---|---|---|---|
| 1 | 全センサーが生きているか | USB | 屋内 | 30秒 | `session.json` が全部 0 / `available_mask` に5つ |
| 2 | **GPS が測位できるか** | USB | **屋外・空が見える所** | 5〜10分 | GPS の CSV で `GGA` の品質が 1 以上、衛星数 > 0 |
| 3 | 体温が実際に取れるか | USB | 犬に当てて | 1分 | 温度 CSV の object が 38〜39℃ 台 |
| 4 | 犬に着けて歩く | BLE | 屋外 | 5分 | 取りこぼし、測位の継続性 |
| 5 | 静止 / 歩行 / 走行 | USB | どこでも | 各30秒 | IMU の波形が3パターンで違うか |

**2 が最優先です。** GPS は初回測位に数分かかることがあるので、屋外で
5〜10分は粘ってください。測位できない場合、アンテナの接続と空の見通しを
確認したうえで、`--seconds 0` で採りながら待つのが確実です。

3 は赤外温度センサーの向きが重要です。周囲温度と体温がほぼ同じ値なら、
センサーが犬の皮膚を向いていません。

---

## 9. データを渡す・残すとき

- `captures/` は **git の管理外**です。ソースには含まれないので、共有するには
  ディレクトリを個別にコピーします
- 残すべきは `raw.usb` と `session.json` です。`analysis/` は後からいつでも
  `./scripts/pet view` で作り直せます
- `PET-main` を消したり再ダウンロードすると `captures/` も消えます。
  採ったデータは別の場所(`~/Desktop/captures-keep/` など)に退避してください

---

## 10. アプリ側で採る場合(まだ使えません)

`dog-Collar-App` の BLE 実装(`lib/data/ble_collar_data_source.dart`)は
書き終えていますが、実機での接続確認はまだです。動くようになると、アプリが
受信した全フレームが JSONL で端末に保存されます。

```
{"rx_ts":1757308800456,"raw":{...解釈した値...},"pet_frame_hex":"5054..."}
```

`pet_frame_hex` が生のフレームです。デコーダのバグを疑ったとき、
犬にもう一度歩いてもらわずに `pet_codec.py decode <hex>` で再生できます。

それまでの実データ採取は、上の USB / BLE ツールで行ってください。
