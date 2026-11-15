#!/usr/bin/env python3
"""
aidi_sound — 犬の発声（吠叫/低吼…）検出の参照実装 (reference implementation)

これは「正解」を決める Python 参照実装です。携帯側(TFLite/Dart)の出力が
これと一致するかを確認するために使います。モデルは Google YAMNet。

公開した唯一の関数:

    detect_events_int16(pcm, sample_rate=16000) -> list[dict]

入力:
    pcm         : 1 次元の int16 配列 (numpy.ndarray / list / bytes いずれも可)。
                  モノラル。値域 -32768..32767。項圈マイクの生フォーマット。
    sample_rate : 入力のサンプリングレート。16000 以外は 16k に内部リサンプルします。

出力: 検出イベントごとに 1 要素の list。各要素:
    {
      "start_ms": int,   # 開始 (ミリ秒)
      "end_ms":   int,   # 終了 (ミリ秒)
      "class":    str,   # 種類: "bark" / "growl" / "howl" / "whine" / "yip"
      "prob":     float, # 0..1 の確信度 (その種類の平均スコア)
    }

備考:
  - 1 ファイルを丸ごと渡す用途を想定（オフライン / バッチ）。ストリーミングは
    呼び出し側で窓をスライドさせてください（下の「携帯実装メモ」参照）。
  - しきい値などの調整値はすべて config.yaml にあります。ここでは何もハードコード
    していません。
"""
from __future__ import annotations

import os
import numpy as np
import yaml

import aggregate as agg

TARGET_SR = 16000
_HERE = os.path.dirname(os.path.abspath(__file__))
_CFG = yaml.safe_load(open(os.path.join(_HERE, "config.yaml")))

# --- YAMNet 本体 (遅延ロード、1 回だけ) --------------------------------------
_YAM = None


def _load_yamnet():
    """YAMNet を読み込む。
    1) 環境変数 YAMNET_DIR が指す SavedModel を優先 (オフライン)。
    2) なければ tensorflow_hub 経由で取得 (初回のみネットワーク)。
    どちらも callable で、呼ぶと (scores[F,521], embeddings, log_mel) を返す。
    """
    global _YAM
    if _YAM is not None:
        return _YAM
    import tensorflow as tf
    local = os.environ.get("YAMNET_DIR")
    if local:
        _YAM = tf.saved_model.load(local)
    else:
        import tensorflow_hub as hub
        _YAM = hub.load(_CFG["model"]["tfhub_url"])
    return _YAM


# --- 前処理 ------------------------------------------------------------------
def _to_float_mono_16k(pcm, sample_rate: int) -> np.ndarray:
    """int16 PCM -> float32 [-1,1], モノラル, 16 kHz。"""
    x = np.frombuffer(pcm, dtype=np.int16) if isinstance(pcm, (bytes, bytearray)) \
        else np.asarray(pcm)
    if x.dtype != np.int16:
        # 呼び出し側が誤って float を渡した場合も一応通す
        x = x.astype(np.int16)
    if x.ndim > 1:  # ステレオで来たら平均してモノラル
        x = x.mean(axis=1)
    wav = x.astype(np.float32) / 32768.0
    if sample_rate != TARGET_SR:
        from math import gcd
        from scipy.signal import resample_poly
        g = gcd(int(sample_rate), TARGET_SR)
        wav = resample_poly(wav, TARGET_SR // g, int(sample_rate) // g).astype(np.float32)
    return wav


def _frame_rms_db(wav: np.ndarray, n_frames: int, hop_s: float, win_s: float) -> np.ndarray:
    import math
    hop = int(round(hop_s * TARGET_SR))
    win = int(round(win_s * TARGET_SR))
    out = np.empty(n_frames, dtype=float)
    for f in range(n_frames):
        seg = wav[f * hop: f * hop + win]
        rms = math.sqrt(float(np.mean(seg ** 2))) if len(seg) else 0.0
        out[f] = 20.0 * math.log10(rms + 1e-10)
    return out


# L0 の内部ラベル -> App 側の呼び名
_CLASS_RENAME = {
    "bark": "bark",         # 吠叫
    "growling": "growl",    # 低吼
    "howl": "howl",         # 嚎叫
    "whimper": "whine",     # 呜咽
    "yip": "yip",           # 尖叫/幼犬の鳴き
}


# --- 公開 API ----------------------------------------------------------------
def detect_events_int16(pcm, sample_rate: int = 16000) -> list[dict]:
    """int16 16 kHz モノラル -> 検出イベント list（モジュール docstring 参照）。"""
    wav = _to_float_mono_16k(pcm, sample_rate)
    yam = _load_yamnet()
    scores, _emb, _spec = yam(wav)
    scores = np.asarray(scores)                 # [F, 521]
    n = scores.shape[0]

    cls = _CFG["classes"]
    gate = agg.compute_gate(scores, cls["gate"], cls["gate_combine"])
    type_arrays = agg.compute_type_arrays(scores, cls["type"])
    rms_db = _frame_rms_db(wav, n, _CFG["model"]["hop_s"], _CFG["model"]["window_s"])

    events = agg.frames_to_events(gate, type_arrays, rms_db, _CFG, _CFG["model"]["hop_s"])

    out = []
    for e in events:
        out.append({
            "start_ms": int(round(e["start_s"] * 1000)),
            "end_ms": int(round(e["end_s"] * 1000)),
            "class": _CLASS_RENAME.get(e["type"], e["type"]),
            "prob": float(e["confidence"]),
        })
    return out


# --- CLI: wav ファイル -> 1 行 1 イベント ------------------------------------
def _read_wav_int16(path: str):
    import soundfile as sf
    x, sr = sf.read(path, dtype="int16", always_2d=True)
    return x[:, 0] if x.shape[1] == 1 else x.mean(axis=1).astype(np.int16), sr


def main():
    import argparse, json, sys
    ap = argparse.ArgumentParser(description="犬の発声検出 (参照実装)")
    ap.add_argument("wav", help="16 kHz mono int16 の wav を推奨 (他形式も内部変換)")
    ap.add_argument("--json", action="store_true", help="JSON 配列で出力")
    args = ap.parse_args()

    pcm, sr = _read_wav_int16(args.wav)
    events = detect_events_int16(pcm, sr)

    if args.json:
        print(json.dumps(events, indent=2, ensure_ascii=False))
    else:
        # 仕様どおり: 1 検出 = 1 行: start_ms  end_ms  class  prob
        for e in events:
            print(f"{e['start_ms']}\t{e['end_ms']}\t{e['class']}\t{e['prob']:.3f}")
        if not events:
            print("(no events)", file=sys.stderr)


if __name__ == "__main__":
    main()
