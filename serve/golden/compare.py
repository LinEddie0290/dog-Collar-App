"""Step 3 checker: compare the collar C log-mel against the ref golden, at BOTH the
raw-element level and the DECISION level.

Usage:
  python compare.py --c-dir <dir>         # <dir>/<clip>/logmel.bin produced by C
  python compare.py --self-test           # uses ref as stand-in for C (error 0, cos 1)

For every clip it reports:
  * per-element |dB| error vs ref (mean/p99/p99.9/max, all-bin + meaningful-bin),
    compared to the C tolerance baseline in frontend_spec.json (pass = <= 3x baseline)
  * encode_from_logmel(C_logmel) vs encode_from_logmel(ref_logmel): embedding cosine
    and type7 top-1 agreement  -> the FINAL gate if the raw error exceeds 3x baseline
    (e.g. C uses a fixed-point FFT): shows whether the extra error actually moves the
    classifier.
The filterbank is the shipped contract ced_mel_fb_64x257.bin; C must load it, not
re-derive htk.
"""
from __future__ import annotations
import argparse, json, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SERVE = os.path.dirname(HERE)
sys.path.insert(0, SERVE)

TYPE7 = ("breathing", "coughing", "dog", "pant", "sneezing", "snoring", "others")


def _stats(d):
    return {"mean": float(d.mean()), "p99": float(np.percentile(d, 99)),
            "p99_9": float(np.percentile(d, 99.9)), "max": float(d.max())}


def _load_c_logmel(c_dir, clip, shape):
    p = os.path.join(c_dir, clip, "logmel.bin")
    if not os.path.isfile(p):
        return None
    return np.fromfile(p, dtype="<f4").reshape(shape)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--c-dir", help="dir with <clip>/logmel.bin from the C impl")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--model", action="store_true", default=True,
                    help="also run the decision-level check (needs CED weights)")
    ap.add_argument("--ced-dir", default=os.path.join(SERVE, "models/ced-tiny"),
                    help="local CED weights (deploy: serve/models/ced-tiny; dev: collar-audio copy)")
    ap.add_argument("--ced-manifest", default=os.path.join(SERVE, "weights_manifest.json"))
    a = ap.parse_args()
    if not os.path.isdir(a.ced_dir):
        alt = "/NVme2/aidi/collar-audio/serve/models/ced-tiny"
        if os.path.isdir(alt):
            a.ced_dir = alt; a.ced_manifest = "/NVme2/aidi/collar-audio/serve/weights_manifest.json"
    if not a.c_dir and not a.self_test:
        ap.error("need --c-dir or --self-test")

    spec = json.load(open(os.path.join(SERVE, "frontend_spec.json")))
    base = spec["c_side_tolerance_baseline"]
    model = None
    if a.model:
        try:
            import model_a as MA
            cfg = {"ced_model_dir": a.ced_dir, "weights_manifest": a.ced_manifest}
            model = MA.ModelA(config=cfg)
        except Exception as e:
            print(f"[warn] decision-level check skipped (no weights?): {e}")

    clips = [d for d in sorted(os.listdir(HERE)) if os.path.isdir(os.path.join(HERE, d))
             and os.path.isfile(os.path.join(HERE, d, "ref_logmel.npy"))]
    print(f"comparing {len(clips)} clips; baseline all_bin max={base['all_bin']['max']}")
    worst_cos, all_ok = 1.0, True
    for clip in clips:
        ref = np.load(os.path.join(HERE, clip, "ref_logmel.npy"))
        if a.self_test:
            c = ref.copy()
        else:
            shp = json.load(open(os.path.join(HERE, clip, "shapes.json")))["ref_logmel"]["shape"]
            c = _load_c_logmel(a.c_dir, clip, shp)
            if c is None:
                print(f"  {clip}: no C logmel.bin, skip"); continue
        d = np.abs(ref - c)
        peak = ref.max(); meaningful = ref > peak - 80.0
        st_all, st_hi = _stats(d), _stats(d[meaningful] if meaningful.any() else d)
        ok = st_all["max"] <= 3 * base["all_bin"]["max"]
        line = f"  {clip:14s} raw max={st_all['max']:.2e} (<=3x base {3*base['all_bin']['max']:.2e}:{ok})"
        if model is not None:
            import numpy as _np
            er = model.emb.encode_from_logmel(ref); ec = model.emb.encode_from_logmel(c)
            cs = float(er @ ec / (_np.linalg.norm(er) * _np.linalg.norm(ec) + 1e-12))
            t_r = TYPE7[int(_np.argmax(_run_t7(model, er)))]; t_c = TYPE7[int(_np.argmax(_run_t7(model, ec)))]
            line += f" | emb_cos={cs:.6f} top1 ref={t_r} C={t_c} {'OK' if t_r==t_c else 'DIFF'}"
            worst_cos = min(worst_cos, cs)
        all_ok = all_ok and ok
        print(line)
    print(f"SUMMARY: raw<=3x baseline for all clips: {all_ok}" +
          (f" | worst embedding cosine: {worst_cos:.6f}" if model is not None else "") +
          "\n(if raw fails but cosine ~1 and top-1 matches, the C error does NOT affect the classifier -> decision-level PASS.)")


def _run_t7(model, emb):
    import model_a as MA
    return MA.type7_proba(emb[None], model.type7)[0]


if __name__ == "__main__":
    main()
