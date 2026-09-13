# ml/bark_semantics — dog-bark understanding pipeline (Python, standalone)

Audio-only bark **detection → semantics** pipeline (YAMNet-based, **no training**).
This is a self-contained Python project vendored into the app monorepo; it is
**not** Flutter and does not import anything from the Dart packages. Wiring it to
the collar's microphone feed is a separate integration task (not done here).

Relation to the collar: PR #4 established the real device (Seeed XIAO
nRF54LM20A) carries a **microphone**, which is what this pipeline consumes. It
does **not** use the BLE vitals/IMU/GPS path — those are the Dart packages under
`packages/`.

## Layers
- **L0** detection: YAMNet frames → bark events + type + rules (`detect.py`,
  `aggregate.py`, `rules.py`). TFLite parity verified.
- **L1** acoustics: `features.py` (Praat F0/HNR), `baseline.py` (per-dog,
  per-device percentile normalization) → `schema.AffectEstimate`.
- **L2** context: `context.py` (reuses YAMNet scores; no 2nd inference pass).
- **L3** intent: `infer.py` (config-driven rules + safety degradation).
- End-to-end: `analyze.py`.

## Run
```bash
pip install -r requirements.txt          # tensorflow-cpu, parselmouth, ...
pip install -r requirements-dev.txt      # + pytest
python3 -m pytest tests/ -q              # 52 tests
python3 analyze.py <clip.wav> --dog-id rex --device phone_mic
```
Network note (this host): model download needs the proxy + system CA —
`HTTPS_PROXY=http://127.0.0.1:7890 SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt`.

## Docs
- `docs/class_map.md` — verified YAMNet dog classes (two-tier gate/type).
- `docs/RESULTS.md` — measured ESC-50 metrics, tuned defaults, **Limitations**
  (clean-audio vs phone/collar-mic domain gap — thresholds need re-tuning on
  real audio).
- `docs/DATA_LICENSES.md` — dev-set licenses; only YAMNet (Apache-2.0) ships.

Everything tunable lives in `config.yaml` under `semantics.*` (+ L0 sections).
`data/` and model caches are gitignored; nothing large is committed.
