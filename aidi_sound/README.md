# aidi_sound — 犬の発声検出（吠叫 / 低吼 …）参照実装

項圈マイクの音から犬の発声を検出して「開始・終了・種類・確信度」を返す、
**Python の参照実装**です。携帯側（TFLite / Dart）の出力がこれと一致するか
確認するための「正解」として使ってください。

- モデル: **Google YAMNet**（Apache-2.0、再学習なし）。犬かどうかの判定(gate) +
  発声タイプの判定(type) を YAMNet の 521 クラススコアから作ります。
- しきい値など調整値はすべて `config.yaml`。コード内にハードコードなし。

このフォルダは**読むだけ・実行するだけ**でOK。中身を変える必要はありません。

---

## 1. 関数の仕様（これだけ使えば良い）

`infer.py`:

```python
detect_events_int16(pcm, sample_rate=16000) -> list[dict]
```

- 入力 `pcm`: **16 kHz / モノラル / int16** の 1 次元配列（numpy / list / bytes 可）。
  項圈マイクの生フォーマットそのもの。16k 以外なら内部で 16k にリサンプル。
- 出力: 検出 1 件 = 1 要素の list。

```json
{ "start_ms": 1440, "end_ms": 4320, "class": "bark", "prob": 0.502 }
```

| フィールド | 意味 |
|---|---|
| `start_ms` | 開始（ミリ秒） |
| `end_ms`   | 終了（ミリ秒） |
| `class`    | 種類（下の表） |
| `prob`     | 0..1 の確信度（そのタイプの平均スコア） |

---

## 2. 種類（class）の名前 — App 側の追加ぶんはここ

| 返す値 `class` | 日本語/中文 | App の状態 |
|---|---|---|
| `bark`  | 吠叫 | ✅ 既にある |
| `growl` | 低吼 | ✅ 既にある |
| `howl`  | 嚎叫 | ➕ 追加して |
| `whine` | 呜咽 | ➕ 追加して |
| `yip`   | 尖叫 / 幼犬の短い鳴き | ➕ 追加して（不要なら無視でOK） |

内部ラベル → App 名の対応は `infer.py` の `_CLASS_RENAME` にあります
（YAMNet 内部では `growling` / `whimper` ですが、出力時に `growl` / `whine` に変換済み）。

> 注意: 現状 `bark` と `growl` 以外は**トリガーしにくい**可能性があります。§4 参照。

---

## 3. 動かし方

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install tensorflow-cpu==2.17.0 tensorflow_hub==0.16.1 \
            numpy==1.26.4 scipy==1.15.3 soundfile==0.14.0 PyYAML==6.0.3
#  ↑ 初回は YAMNet(約17MB)を自動DL。オフラインなら YAMNET_DIR にSavedModelを置く。

# 仕様どおり 1 行 1 イベント:  start_ms <TAB> end_ms <TAB> class <TAB> prob
python3 infer.py test/test_input.wav
# => 1440    4320    bark    0.502

python3 infer.py test/test_input.wav --json   # JSON 配列で欲しいとき
```

---

## 4. 公開データでの精度（完成度表に入れる用）

計測は **ESC-50**（2000クリップ：犬40 + 非犬1960、cat/cow/pig/rooster 等の
難しい負例込み）。詳細は `docs/RESULTS.md`。

- **「犬の発声か否か」のクリップ単位: P=0.84 / R=0.93 / F1=0.88**
  （既定しきい値 thr=0.50, 中央値平滑3, 最短0.96秒）。
- **種類別（bark/growl/…の取り違え率）は未計測**。ESC-50 に種類ラベルが無いため。
  正直に「クリップ単位の犬検出のみ測定済み、種類別の P/R は型ラベル付きデータ待ち」
  と書くのが正確です。数字をでっち上げていません。
- **重要な注意（ドメインギャップ）**: ESC-50 はクリーンな近接マイク。実機は
  部屋の反響・距離減衰でスコアが下がるため、**実録音でしきい値の再調整が必要**。
  今の 0.50 は出発点であって出荷値ではありません。

---

## 5. テスト用 wav と期待出力（携帯と突き合わせる用）

- `test/test_input.wav` … 16 kHz / モノラル / int16 / 5.0 秒（ESC-50 の犬クリップ）。
- `test/expected_output.json` … 上の wav に対するこの参照実装の出力:

```json
[ { "start_ms": 1440, "end_ms": 4320, "class": "bark", "prob": 0.502 } ]
```

携帯側が同じ wav でこの 1 件（bark, 1440–4320ms 付近）を出せば結線OKの目安。
※ `prob` の小数は実装差で多少ずれます。**区間と class が合うか**を主に見てください。

---

## 6. 携帯実装メモ（Dart か TFLite か）

**結論の推奨: TFLite。** YAMNet には Google 公式の TFLite があり
（このフォルダに同梱: **`model/yamnet.tflite`**, 約4MB）、この Python 参照と
パリティ検証済み（最良フレーム相関 0.993）。Dart で DSP を書き直すより安全。

役割分担:
- **重い所（YAMNet 推論）= TFLite on-device**。入力 16k mono float32[-1,1]
  （= int16/32768）。
- **軽い所（イベント化：しきい値・平滑・区間マージ・タイプ投票）= `aggregate.py` を
  Dart へ移植**。純ロジック（TF なし・約120行）なので移植は容易。設定は
  `config.yaml` の値をそのまま使う。

**一番ハマる所（必読）**:
TF Hub 版 YAMNet は **0.48 秒ごと**にフレームを出す（0.96秒窓オーバーラップ）が、
公式 **TFLite の "classification" 版は 1 回 0.975 秒の固定窓**。フレーム刻みが違うと
しきい値がそのまま移らない。**TFLite 側で窓を 0.48 秒ずつスライドさせて**
参照と同じ刻みにそろえること（詳細 `docs/RESULTS.md` Amendment 5）。

最終決定（Dart 再実装 vs TFLite）は、この参照とテスト wav で突き合わせてから
一緒に決めましょう。

---

## 7. ライセンス / 出典

- **YAMNet** — Apache-2.0 (Google)。`model/yamnet.tflite` は Google 公式配布物。
- **`test/test_input.wav`** — ESC-50 データセットのクリップ `1-30226-A-0`
  （`dog` クラス）を 16 kHz / mono / int16 に変換したもの。ESC-50 は
  **CC BY-NC 3.0**（研究・評価用途）。出典: K. J. Piczak, *ESC: Dataset for
  Environmental Sound Classification*, ACM MM 2015。
- `infer.py` / `aggregate.py` / `config.yaml` は本プロジェクトのコード。
